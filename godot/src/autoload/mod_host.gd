class_name ModHost
extends Node
## The one owner of the running mods (autoload "Mods"). The mods that run are DERIVED from the chain in use: `wanted()` lists the packs of `Packs.chain()` whose manifest has a `mod`
## (the bottom of the chain first), and `sync()` makes the loaded mods exactly those, loading what is new and unloading what is gone or whose script changed. Every path that changes
## the chain (`Packs.choose`, `start`, `use`, `restore`, `reset`, `refresh`: the pack screen, `--pack=`, a tool, a test) announces it on `Packs.events.changed`; this node listens, and the
## sync runs at the next idle moment, so a pack that is borrowed and put back inside one call (`PackCheck`) costs no reload. A reader that needs the mods at once calls `sync()` (it does
## nothing when the loaded mods already are the chain's). There is no second list of mods anywhere.
##
## A mod can log, load files of its own pack and, when its manifest says `skin`, draw the sector (`ModApi`, `ModLayerHost`), when it says `problems`, draw the screens of the problem types it lists (`ModProblems`,
## `ModDiagram`) or, when it says `rules`, add gameplay at the hook points of the rules (`RuleHooks`) for a campaign that declares it. The rules never ask this node anything: a campaign's run resolves the mods it
## declares once, when it begins (`ModHooks.resolve`, which asks `rule_mod`), and the rules hold the table that came out.
## Each running mod has ONE record, its `ModParts` (made by `ModParts.make` from what the pack holds, kept while the mod runs). A SKIN mod's `ModSkin` is asked for by `SkinChoice` (`skin_ids`, `skin`), and when the mod goes
## (unloaded: the skin is not `alive` any more; or quarantined: it is not offered) the skin in use falls back to the original (`SkinChoice.leave_dead_mod_skins`). The `ModProblems` of a mod that draws problem screens is asked
## for with `problem_screen` (the mod that draws a type, only while it runs and is not quarantined, so a screen without one shows the plain diagram its data describes). A mod whose pack `ModParts.make` refuses, or whose script
## lacks a function its manifest lists (`ModSpec.functions`), is refused with the reason, like a script that does not compile.
## A build without the godot-sandbox extension never gets a mod pack with a script into its chain (`Pack` refuses its manifest); a DATA skin (no `entry`) needs no script, so it runs there too and `mod` has no node for it.
##
## Teaches: deriving a copy of state from its single owner (the chain) with one builder instead of patching it at each place the owner changes, coalescing a burst of changes into one
## update with `call_deferred`, and keeping the loaded set honest with a key per item (here the pack, its script file and the file's time).

## The mods are derived from the chain. The loaded scripts are the loader's own; these are what was refused and why, what was reported, whether the chain changed since, and the `ModParts` of each running mod (the key it was made under inside).
const CHAIN_FIELDS: Array[StringName] = [&"_failed", &"_reported", &"_stale", &"_parts"]
## Member variables that no scope clears, and why (docs/engine/ARCHITECTURE.md, "Lifetimes of state").
const KEPT_FIELDS: Dictionary[StringName, String] = {
	&"_loader": "wiring: made once in `_ready`; it holds the loaded mods, each with the key it was loaded under (`KEY_META`)",
	&"_api": "wiring: made once in `_ready` with the loader",
}

## A mod of the chain logged a message (`ModApi`'s `log`).
signal mod_logged(id: String, text: String)
## The loaded mods changed (a sync loaded or unloaded one).
signal mods_changed

## id -> the `ModParts` of a running mod (a data skin has one and no script in the loader).
var _parts: Dictionary = {}
## id -> {"key": ..., "reason": ...} for a mod that was refused; the key keeps a sync from trying the same script again.
var _failed: Dictionary = {}
## The ids whose faults were already reported in the log (one line per mod until it is unloaded).
var _reported: Dictionary = {}
## Did the chain change since the last sync?
var _stale := true
var _loader: ModLoader
var _api: ModApi
static var _instance: ModHost


func _ready() -> void:
	_instance = self
	ModLoader.warm_up()
	_loader = ModLoader.new()
	_loader.name = "Loader"
	_api = ModApi.new(_loader)
	_loader.api_provider = _api.build
	_loader.property_policy = _api.property_allowed
	_loader.method_policy = _api.method_allowed
	_loader.mod_failed.connect(_on_mod_failed)
	_loader.mod_errored.connect(_on_mod_errored)
	_loader.mod_quarantined.connect(_on_mod_quarantined)
	_api.logged.connect(func(id: String, text: String) -> void: mod_logged.emit(id, text))
	add_child(_loader)
	Packs.events.changed.connect(_on_chain_changed)
	_sync_later.call_deferred()                          # (a chain chosen before this node was ready)


## The packs of the chain in use that carry a mod, the bottom of the chain first (a pack laid over another loads after it).
static func wanted() -> Array[Pack]:
	var found: Array[Pack] = []
	for i in range(Packs.chain().size() - 1, -1, -1):
		var pack := Packs.chain()[i]
		if pack.mod != null:
			found.append(pack)
	return found


## What identifies a mod as the disk has it: the pack's folder or file, and the file that makes it the mod it is with its time (`Pack.modified_time`): the script, or the manifest of a data skin.
static func key_of(pack: Pack) -> String:
	var file := pack.mod.entry if pack.mod.has_entry() else Pack.MANIFEST
	return "%s|%s|%d" % [pack.root, file, pack.modified_time(file)]


## Makes the loaded mods the chain's. Cheap when nothing changed.
func sync() -> void:
	_stale = false
	var changed := false
	var packs := wanted()
	var wanted_keys := {}
	for pack in packs:
		wanted_keys[String(pack.id)] = key_of(pack)
	for id: String in _parts.keys():
		if wanted_keys.get(id) != _parts[id].key:
			_loader.unload(id)
			_end(id)
			changed = true
	for id: String in _failed.keys():
		if wanted_keys.get(id) != _failed[id]["key"]:
			_failed.erase(id)
	for id: String in _reported.keys():
		if _loader.get_mod(id) == null:
			_reported.erase(id)
	for pack in packs:
		var id := String(pack.id)
		if _parts.has(id) or _failed.has(id):
			continue
		var reasons: Array[String] = []
		var parts := ModParts.make(pack, reasons)
		if parts == null:
			_on_mod_failed(id, "; ".join(reasons))
			continue
		if pack.mod.has_entry():                         # (a data skin has no script: nothing to load, no Sandbox needed)
			var node := _loader.load_mod(pack)
			if node == null:
				continue
			var missing := ModLoader.missing_functions(node, pack.mod)
			if not missing.is_empty():
				_loader.unload(id)
				_on_mod_failed(id, "; ".join(missing))
				continue
		parts.key = wanted_keys[id]
		_parts[id] = parts
		changed = true
	if changed:
		SkinChoice.leave_dead_mod_skins()
		mods_changed.emit()


## The ids of the mods that run (scripts loaded, and data skins worn), in the order they were loaded.
func loaded_ids() -> Array:
	_sync_if_stale()
	return _parts.keys()


# --- for code that has no node (`SkinChoice`, `ModLayerHost`): the autoload's answers, nothing when it is not there (the editor) -------------

## The node of the running mod `id` (a Sandbox the game may call into), or null (also for a data skin: it has no script). It first makes the mods the chain's (`sync`) unless `sync_first` is false: a presenter asks in the middle of a frame, where a sync could
## swap the presenter itself (`SkinChoice.leave_dead_mod_skins`).
static func mod(id: StringName, sync_first := true) -> Node:
	if _instance == null:
		return null
	if sync_first:
		_instance._sync_if_stale()
	return _instance._loader.get_mod(String(id))


## Why a mod of the chain is not running ("" when it is, or there is none).
static func failure(id: StringName) -> String:
	if _instance == null:
		return ""
	_instance._sync_if_stale()
	return _instance._failed[String(id)]["reason"] if _instance._failed.has(String(id)) else ""


## Is the mod `id` quarantined (it faulted too often)? False when it is not running.
static func is_quarantined(id: StringName) -> bool:
	return _instance != null and _instance._loader.is_quarantined(String(id))


## The ids of the running skin mods, in the order they were loaded.
static func skin_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	if _instance != null:
		_instance._sync_if_stale()
		for id: String in _instance._parts:
			if _instance._parts[id].skin != null and not _instance._loader.is_quarantined(id):
				found.append(StringName(id))
	return found


## The skin of the running skin mod `id`, or null (also for a mod that is quarantined: it draws nothing, so it is not offered).
static func skin(id: StringName) -> ModSkin:
	if _instance == null:
		return null
	_instance._sync_if_stale()
	var parts: ModParts = _instance._parts.get(String(id))
	return null if parts == null or _instance._loader.is_quarantined(String(id)) else parts.skin


## The mod that draws the screen of problem type `type_id`, or null: the type is held by a pack of the chain whose mod lists it, runs and is not quarantined. A type nobody draws (no mod, a mod that was refused or
## faulted too often, a type another pack of the chain holds instead) is shown as its data describes it, by `DiagramBase`.
static func problem_screen(type_id: int) -> ModProblems:
	if _instance == null:
		return null
	_instance._sync_if_stale()
	var holder := Packs.holder(Catalog.problem_type_rel(type_id))
	if holder == null:
		return null
	var parts: ModParts = _instance._parts.get(String(holder.id))
	if parts == null or parts.screens == null or not parts.screens.types.has(type_id) or _instance._loader.is_quarantined(String(holder.id)):
		return null
	return parts.screens


## The node of the running mod `id` whose manifest has `rules`, or null (it is not in the chain, was refused, or has no rule hooks): what a campaign's run resolves its declared mods with (`ModHooks.resolve`).
## The reason it is null is `failure`.
static func rule_mod(id: StringName) -> Node:
	if _instance == null:
		return null
	_instance._sync_if_stale()
	var pack := Packs.pack(id)
	if pack == null or pack.mod == null or not pack.mod.has_rules:
		return null
	return _instance._loader.get_mod(String(id))


## The loader, for a caller that must reach a mod's health (a test, the audit); the game does not need it.
func loader() -> ModLoader:
	return _loader


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _sync_if_stale() -> void:
	if _stale:
		sync()


func _on_chain_changed() -> void:
	_stale = true
	_sync_later.call_deferred()


func _sync_later() -> void:
	if _stale:
		sync()


func _on_mod_failed(id: String, reason: String) -> void:
	push_warning("[mods] mod '%s' failed: %s" % [id, reason])
	if _failed.has(id):
		_failed[id]["reason"] = reason
	else:
		var packs := wanted().filter(func(pack: Pack) -> bool: return String(pack.id) == id)
		_failed[id] = {"key": key_of(packs[0]) if not packs.is_empty() else "", "reason": reason}


func _on_mod_errored(id: String, exceptions: int, timeouts: int) -> void:
	if _reported.has(id):
		return
	_reported[id] = true
	push_warning("[mods] mod '%s' faulted: %d exception(s), %d timeout(s); further faults are not reported" % [id, exceptions, timeouts])


func _on_mod_quarantined(id: String) -> void:
	_reported.erase(id)
	push_warning("[mods] mod '%s' is quarantined: it faulted too often" % id)
	if _parts.has(id) and _parts[id].skin != null:
		SkinChoice.leave_dead_mod_skins()


## The record of the mod `id` ends with it (its skin is not offered any more).
func _end(id: String) -> void:
	var parts: ModParts = _parts.get(id)
	if parts != null:
		parts.end()
		_parts.erase(id)
