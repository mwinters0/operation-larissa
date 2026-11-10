class_name ModLoader
extends Node
## Loads the SafeGDScript (`.sgd`) entry script of a mod pack into a Sandbox with restrictions on, and keeps watch over it.
##
## Adapted from the `ModLoader` of godot-sandbox's `examples/modding` (https://github.com/libriscv/godot-sandbox, BSD-3-Clause, Copyright (c) the godot-sandbox authors; the
## licence is in `addons/godot_sandbox/LICENSE`, which `tools/fetch_sandbox.py` puts there). Differences: a mod is a PACK (`Pack.mod` is its manifest entry, the script is read from
## the pack, the mod's id is the pack's id), there is no scan of folders (`ModHost` loads the mods of the chain in use), the limits come from the clamped `ModSpec`, and a mod's own
## `load()` is always refused: the files of its pack reach it through the API (`ModApi`, the pack's door), never through a path.
##
## What a mod can do, in the words of the Sandbox:
##   * RESTRICTIONS are always on. A mod reaches only the objects the game grants (`add_allowed_object`), and of those only the properties `property_policy` and the methods
##     `method_policy` allow; an unset policy denies everything.
##   * LIMITS (`ModSpec.limits`, clamped to the game's ceilings) bound the instructions per call, the memory, the allocations, the references and the coroutines.
##   * A mod that raises too often (`MAX_FAULTS` within a stretch of frames) is QUARANTINED: its frame and input callbacks are switched off; the others go on.
## Every call into a mod, whoever makes it, goes through `call_mod`: the arguments are made read-only (`freeze`), the function runs under the mod's instruction limit, an error or a timeout (the Sandbox's counters moved) is
## reported as a fault, and a container the mod hands back is copied (`detach`) before the game keeps it. The callers decide only what a fault means to them.
##
## Teaches: running code you do not trust inside a sandbox: restrictions and limits set BEFORE the script's member initializers run, one function for every call across the edge (read-only arguments, a fault read
## from the counters, a copied answer), an exception counter as the health check, and quarantine instead of a crash.

## A mod was loaded, or refused (with the reason). `mod_errored` carries the new faults since the last frame, `mod_quarantined` says the callbacks were switched off.
signal mod_loaded(id: String)
signal mod_failed(id: String, reason: String)
signal mod_errored(id: String, exceptions: int, timeouts: int)
signal mod_quarantined(id: String)

## Faults (exceptions) that quarantine a mod, and the clean frames after which the count is forgiven.
const MAX_FAULTS := 60
const CLEAN_FRAMES_TO_FORGIVE := 120

## How the game answers a mod asking for something: `api_provider.call(id, pack) -> Dictionary` builds the API (`ModApi.build`); the policies are called as
## `property_policy.call(id, object, property, is_set) -> bool` and `method_policy.call(id, object, method) -> bool`. An unset policy denies.
var api_provider := Callable()
var property_policy := Callable()
var method_policy := Callable()

var _mods := {}
var _health := {}

## A test sets this to play a build without the extension.
static var pretend_no_sandbox := false


## Can this build run a mod? True when the godot-sandbox extension is loaded (`ClassDB` knows `Sandbox` and `SafeGDScript`).
static func sandbox_available() -> bool:
	return not pretend_no_sandbox and ClassDB.class_exists("Sandbox") and ClassDB.class_exists("SafeGDScript")


## Runs a throwaway restricted script, once. The extension makes some machinery when the first script is compiled and the first restrictions are set (the compiler, a Sandbox node running `gdscript.elf`; a helper node) and keeps it for the life
## of the program, outside the tree; doing that at start-up (about 10 ms) means the first mod does not stall the game with it, and that machinery is not counted as a node a later scene leaked.
static func warm_up() -> void:
	if not sandbox_available():
		return
	var script: Variant = ClassDB.instantiate(&"SafeGDScript")
	script.set_source_code("var x := 1\nfunc warm_up():\n\tpass\n")
	var node := Node.new()
	node.set_script(script)
	node.set("restrictions", true)
	node.free()


## The sentence for a build without the extension.
static func missing_extension_text() -> String:
	return "a mod pack needs the godot-sandbox extension, which this build does not have (docs/SETUP.md: `uv run tools/fetch_sandbox.py` fetches it; an exported game keeps its library beside the executable)"


func get_mod(id: String) -> Node:
	return _mods.get(id)


func get_mod_ids() -> Array:
	return _mods.keys()


func is_quarantined(id: String) -> bool:
	return _health.has(id) and bool(_health[id]["quarantined"])


func resume(id: String) -> void:
	var node: Node = _mods.get(id)
	if node == null or not is_quarantined(id):
		return
	_reset_health(id, node)
	_set_callbacks_enabled(node, true)


func unload(id: String) -> void:
	var node: Node = _mods.get(id)
	if node == null:
		return
	if declares(node, "mod_deinit", 0):
		if not call_mod(node, "mod_deinit", [])["ok"]:
			push_warning("[mods] mod '%s' raised inside mod_deinit()" % id)
	_mods.erase(id)
	_health.erase(id)
	if node.get_parent() != null:
		remove_child(node)
	node.free()


func unload_all() -> void:
	for id in _mods.keys():
		unload(id)


func _exit_tree() -> void:
	unload_all()


## Loads the mod of `pack` (`pack.mod` is its entry): returns its node, or null with `mod_failed` emitted. The id of the mod is the pack's id.
func load_mod(pack: Pack) -> Node:
	var id := String(pack.id)
	var spec := pack.mod
	if spec == null:
		mod_failed.emit(id, "the pack's manifest has no \"mod\"")
		return null
	if not sandbox_available():
		mod_failed.emit(id, missing_extension_text())
		return null
	if _mods.has(id):
		mod_failed.emit(id, "a mod with this id is already loaded")
		return null
	if not pack.has(spec.entry):
		mod_failed.emit(id, "entry script not found: " + pack.path_of(spec.entry))
		return null
	var source_bytes := pack.read_bytes(spec.entry)
	if source_bytes.size() > ModSpec.MAX_SOURCE_BYTES:
		mod_failed.emit(id, "entry script is larger than %d bytes" % ModSpec.MAX_SOURCE_BYTES)
		return null
	var source := source_bytes.get_string_from_utf8()
	if source.strip_edges().is_empty():
		mod_failed.emit(id, "entry script is empty or not UTF-8: " + spec.entry)
		return null

	# (made by name: this script must parse in a build without the extension, which only refuses the mod)
	var script: Variant = ClassDB.instantiate(&"SafeGDScript")
	# Attach a harmless program first. This creates the Sandbox so restrictions and limits can be set before the mod's member initializers run.
	script.set_source_code("func __mod_bootstrap():\n\tpass\n")
	var node := Node.new()
	node.name = id
	node.set_script(script)
	_restrict(node, spec)
	var before_init := faults_of(node)

	# Breakpoints use the source path. Set it before compiling the mod.
	script.take_over_path(pack.path_of(spec.entry))
	script.set_source_code(source)

	var compile_error: String = script.get_compile_error()
	if not compile_error.is_empty():
		node.free()
		mod_failed.emit(id, "did not compile: " + compile_error)
		return null

	if not declares(node, "mod_init", 1):
		node.free()
		mod_failed.emit(id, "no mod_init(api) function taking exactly one argument")
		return null

	# Reading a sandbox property creates the real instance record and runs member initializers. Restrictions and limits are already active.
	var after_init := faults_of(node)
	if after_init.x > before_init.x or after_init.y > before_init.y:
		node.free()
		mod_failed.emit(id, "a member initializer raised inside the sandbox")
		return null

	_set_callbacks_enabled(node, true)
	_mods[id] = node                                   # (registered before the API is built: the API's functions may ask for the mod)

	var api := {}
	if api_provider.is_valid():
		api = api_provider.call(id, pack)

	# Before add_child: Godot runs _enter_tree/_ready during it.
	if not call_mod(node, "mod_init", [api])["ok"]:
		_mods.erase(id)
		node.free()
		mod_failed.emit(id, "mod_init() raised inside the sandbox")
		return null

	_reset_health(id, node)
	add_child(node)

	mod_loaded.emit(id)
	return node


func _process(_delta: float) -> void:
	check_health()


## Looks at the exception counters of every mod: new faults are reported, a mod with too many is quarantined, a stretch of clean frames forgives the count. Once per frame.
func check_health() -> void:
	for id in _mods:
		var node: Node = _mods[id]
		if is_quarantined(id):
			continue
		var health: Dictionary = _health[id]
		var counts := faults_of(node)
		var exceptions := counts.x
		var timeouts := counts.y
		var de := exceptions - int(health["exceptions"])
		var dt := timeouts - int(health["timeouts"])
		if de == 0 and dt == 0:
			health["clean"] = int(health["clean"]) + 1
			if int(health["clean"]) >= CLEAN_FRAMES_TO_FORGIVE:
				health["faults"] = 0
				health["clean"] = 0
			continue
		health["exceptions"] = exceptions
		health["timeouts"] = timeouts
		health["clean"] = 0
		# Every timeout also increments monitor_exceptions.
		health["faults"] = int(health["faults"]) + de
		mod_errored.emit(id, de, dt)
		if int(health["faults"]) >= MAX_FAULTS:
			health["quarantined"] = true
			_set_callbacks_enabled(node, false)
			mod_quarantined.emit(id)


## Clears the fault count of a mod (after a failing call that was meant to fail, as the hostile-mod audit makes).
func forgive(id: String) -> void:
	var node: Node = _mods.get(id)
	if node != null:
		_reset_health(id, node)


func _reset_health(id: String, node: Node) -> void:
	var counts := faults_of(node)
	_health[id] = {
		"exceptions": counts.x,
		"timeouts": counts.y,
		"faults": 0,
		"clean": 0,
		"quarantined": false,
	}


func _set_callbacks_enabled(node: Node, enabled: bool) -> void:
	node.set_process(enabled and declares(node, "_process", 1))
	node.set_physics_process(enabled and declares(node, "_physics_process", 1))
	node.set_process_input(enabled and declares(node, "_input", 1))
	node.set_process_shortcut_input(enabled and declares(node, "_shortcut_input", 1))
	node.set_process_unhandled_input(enabled and declares(node, "_unhandled_input", 1))
	node.set_process_unhandled_key_input(enabled and declares(node, "_unhandled_key_input", 1))


func _restrict(node: Node, spec: ModSpec) -> void:
	node.set("restrictions", true)
	node.call("set_resource_allowed_callback", _resource_allowed)
	if property_policy.is_valid():
		node.call("set_property_allowed_callback", _property_allowed.bind(node.name))
	if method_policy.is_valid():
		node.call("set_method_allowed_callback", _method_allowed.bind(node.name))
	node.set("execution_timeout", clampi(spec.limits["execution_timeout"], 1, ModSpec.MAX_EXECUTION_TIMEOUT))
	node.set("memory_max", clampi(spec.limits["memory_max"], 1, ModSpec.MAX_MEMORY))
	node.set("allocations_max", clampi(spec.limits["allocations_max"], 1, ModSpec.MAX_ALLOCATIONS))
	node.set("references_max", clampi(spec.limits["references_max"], 1, ModSpec.MAX_REFERENCES))
	node.set("coroutines_max", clampi(spec.limits["coroutines_max"], 1, ModSpec.MAX_COROUTINES))


## A mod's own `load("path")` is refused whatever the path: a path reaches `ResourceLoader`, and a pack's files reach the game only through the pack's door (`Pack.file`).
## The mod asks for a file of its pack through the API (`ModApi`: `load`).
func _resource_allowed(_sandbox: Object, _path: String) -> bool:
	return false


func _property_allowed(_sandbox: Object, object: Object, property: String, is_set: bool, id: String) -> bool:
	return property_policy.call(id, object, property, is_set)


func _method_allowed(_sandbox: Object, object: Object, method: String, id: String) -> bool:
	return method_policy.call(id, object, method)


## Does the mod `node` define `function` taking exactly `arity` arguments?
static func declares(node: Node, function: String, arity: int) -> bool:
	for method in node.get_method_list():
		if method["name"] == function:
			return method["args"].size() == arity
	return false


## Why the script of `node` lacks what the manifest `spec` lists (`ModSpec.functions`): one sentence per function it does not define with that many arguments. [] when it defines them all.
static func missing_functions(node: Node, spec: ModSpec) -> Array[String]:
	var found: Array[String] = []
	var needed := spec.functions()
	for function in needed:
		if not declares(node, function, needed[function].size()):
			found.append("the script defines no %s taking exactly %d argument%s" % [ModSpec.signature(function, needed[function]), needed[function].size(), "" if needed[function].size() == 1 else "s"])
	return found


## The ONE call into a mod: `function` of `node` with `args`. Every container among the arguments is made read-only first (`freeze`). Returns {"ok": true, "value": the answer, a container copied with `detach`} or
## {"ok": false, "why": a sentence}: the mod is gone (freed or unloaded), it ran past its instruction limit, or it raised an error (the Sandbox's counters moved during the call; a timeout also counts as an exception).
## A fault returns no value; what it means (keep the last frame, fall back, record it) is the caller's.
static func call_mod(node: Variant, function: String, args: Array) -> Dictionary:
	if not is_instance_valid(node):
		return {"ok": false, "why": "the mod is gone"}
	for argument in args:
		freeze(argument)
	var before := faults_of(node)
	var value: Variant = node.callv(function, args)
	var after := faults_of(node)
	if after.y > before.y:
		return {"ok": false, "why": "it ran past its instruction limit"}
	if after.x > before.x:
		return {"ok": false, "why": "it raised an error"}
	return {"ok": true, "value": detach(value)}


## The Sandbox's counters of `node`: x = exceptions, y = execution timeouts (every timeout also counts as an exception).
static func faults_of(node: Node) -> Vector2i:
	return Vector2i(int(node.get("monitor_exceptions")), int(node.get("monitor_execution_timeouts")))


## Deep make_read_only(). Marks before descending, so the read-only test is also the cycle guard.
static func freeze(value: Variant) -> void:
	if value is Dictionary:
		if value.is_read_only():
			return
		value.make_read_only()
		for key in value:
			freeze(value[key])
	elif value is Array:
		if value.is_read_only():
			return
		value.make_read_only()
		for element in value:
			freeze(element)


## Deep-copies a container so the game holds an independent value.
static func detach(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
