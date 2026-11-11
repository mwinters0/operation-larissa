class_name SkinChoice
extends RefCounted
## Which skin the game wears right now, and how to change it. One small place that knows where the skins are, so that the command
## line, a menu, the debug keys and the tests all say the same thing (the sibling of `PresenterChoice`, which picks the presenter).
##
## The current skin is a `static var`: not a node and not an autoload, so a tool, a test or the screen editor can ask for it with no
## game running. Whoever shows something skin-dependent LISTENS for a change (`events.changed`) and shows it again:
##   * `SectorWorld` makes a new presenter (the one of the new skin) that builds the screen from the rules' state,
##   * `Hud` puts its layout and lettering on again,
##   * `select` itself puts the skin's `RenderSettings` on the window and its menu theme on the project theme (`ThemeBuilder.apply`: every control that has no theme of its own looks it up, so open screens change with no step of their own).
## Screens that are made when they are entered (a problem, a story page, the log) simply ask `Assets` / `Catalog` when they are
## built and so have the skin that is current then.
##
## ONE SKIN FOR A WHILE. Two skins can be on screen at once (the side-by-side tool, `src/debug/skin_compare.tscn`), but `current()` is
## one global. `within(skin, action)` is the seam: while `action` runs, `current()` answers `skin`, so every picture and data file
## that `Assets` and `Catalog` fetch in it is that skin's. A `SectorPresenter` that has a `skin` runs all of its work this way
## (`SectorPresenter.run_in_skin`, and the handlers `_listen` connects), so a presenter dressed for skin X keeps resolving through X
## whatever the rest of the game wears. Nothing that is not asked for in the call changes, and nothing about the rules does.
##
## SKIN MODS. A mod pack whose manifest says `skin` (`ModSpec`) is a skin too: `ModHost` makes its `ModSkin` (a `GameSkin` that the original presenter wears, with the layers the sandboxed script draws put over the original's) when the mod runs, and `available`
## and `load_skin` offer it beside the skins that ship, so the command line, F3 then S, the compare tool and the tests choose it like any other. It lives as long as the mod: when the mod is unloaded or
## quarantined, `leave_dead_mod_skins` puts the original on (until then a presenter bound to the gone mod shows the original's layers and asks nobody).
##
## Teaches: shared state without a node. A `static var` is a global with a name; the one thing a class cannot hold statically is a
## signal, so `events` is a small object that owns it. Connecting a signal to a node's method is undone by itself when the node is freed.
##
## From the command line (arguments after `--`):
##     godot --path godot -- --skin=<id>        the skin in res://skins/<id>/skin.tres, or the id of a skin mod of the pack in use (`--pack=`); unknown ids are a loud error

const ORIGINAL := &"original"
const SKINS_DIR := "res://skins"

## A test or tool sets this to decide before the first thing is drawn (it wins over the command line). Empty: no choice.
static var forced: StringName = &""

## The signal of a switch. (A class cannot have a static signal: this object has it.)
static var events := SkinEvents.new()

static var _current: GameSkin
static var _original: GameSkin
## The skins `within` is running for, innermost last. While there is one, `current()` is it.
static var _scoped: Array[GameSkin] = []


## The events of the skin in use.
class SkinEvents extends RefCounted:
	## The skin in use is another one now (or the same one, selected again after its resources were edited). Show again.
	signal changed(skin: GameSkin)


## The id this run asks for: `forced`, else `--skin=<id>` on the command line, else the original.
static func requested() -> StringName:
	if not forced.is_empty():
		return forced
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skin="):
			return StringName(arg.get_slice("=", 1))
	return ORIGINAL


## The original skin: maps nothing, so everything is today's.
static func original() -> GameSkin:
	if _original == null:
		_original = load(path_of(ORIGINAL)) as GameSkin
	return _original


## Where the skin `id` lives.
static func path_of(id: StringName) -> String:
	return "%s/%s/skin.tres" % [SKINS_DIR, id]


## The ids of the skins there are: those that ship with the game (a folder of `res://skins/` with a `skin.tres`), the original first, and then the skin mods that run (`ModHost.skin_ids`: the
## packs of the chain in use that carry a mod with a `skin`; they are code of a stranger in a sandbox, `docs/create/SKIN_API.md`).
static func available() -> Array[StringName]:
	var found: Array[StringName] = [ORIGINAL]
	for folder in DirAccess.get_directories_at(SKINS_DIR):
		if folder != ORIGINAL and ResourceLoader.exists(path_of(StringName(folder))):
			found.append(StringName(folder))
	found.append_array(ModHost.skin_ids())
	return found


## The skin after `id` in `available()`, wrapping round to the first (the debug key `S` steps through the skins with it). An id that is
## not in the list (a test skin loaded from a file) is followed by the first, the original.
static func after(id: StringName) -> StringName:
	var ids := available()
	return ids[(ids.find(id) + 1) % ids.size()]


## The skin `id`: one that ships, or the skin of a skin mod that runs (`ModSkin`, the same kind of object, so everything that wears a skin treats it alike). An unknown one is a loud error and gives
## the original, not a half-dressed game.
static func load_skin(id: StringName) -> GameSkin:
	if id == ORIGINAL:
		return original()
	var modded := ModHost.skin(id)
	if modded != null:
		return modded
	if not ResourceLoader.exists(path_of(id)):
		push_error("SkinChoice: no skin '%s' (expected %s; the skins are: %s)" % [id, path_of(id), ", ".join(available())])
		return original()
	return load(path_of(id)) as GameSkin


## The skin in use: the one of the `within` call that is running, else the one selected. The first time anybody asks, it is the one this
## run asked for (`requested`) and its render settings go on the window.
static func current() -> GameSkin:
	if not _scoped.is_empty():
		return _scoped.back()
	if _current == null:
		select(load_skin(requested()))
	return _current


## The skin something wears: `skin` when it has one of its own (a presenter or a HUD of the side-by-side tool), else the skin in use. The one place that says so.
static func worn(skin: GameSkin) -> GameSkin:
	return skin if skin != null else current()


## Puts `skin` on: it becomes the current one, its render settings go on the window (`RenderSettings.apply_to`), and everybody
## who listens to `events.changed` shows it. The rules do not hear of it and nothing about timing changes.
static func select(skin: GameSkin) -> void:
	_current = skin
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		skin.render_settings().apply_to(tree.root)
	ThemeBuilder.apply(skin)
	events.changed.emit(skin)


## The skin in use was the skin of a mod that has stopped (unloaded with its pack, or quarantined for faulting): the original is put on, as a user choosing it would. `ModHost` calls this whenever
## the running mods change or one is quarantined; it does nothing while the skin in use is one that ships or a mod skin that runs.
static func leave_dead_mod_skins() -> void:
	if _current is ModSkin and ModHost.skin(_current.id) != _current:
		select(original())


## `select(load_skin(id))`.
static func select_id(id: StringName) -> void:
	select(load_skin(id))


## Makes the skins in use forget the changed copies of data resources they made (`GameSkin.forget`): the packs' pictures changed (a pack was
## mounted or removed), and a copy made before still holds the old ones. Nothing is selected and nothing is announced.
static func forget_all() -> void:
	if _original != null:
		_original.forget()
	if _current != null:
		_current.forget()


## Runs `action` (a Callable that returns at once: no `await` inside, a coroutine would leave the scope at its first wait) with `skin` as the
## skin in use, and returns what it returns. Nothing is selected: the window keeps its render settings, `events.changed` does not fire
## and everything outside the call still sees the skin that is selected. A null `skin` just runs `action`. Calls may nest.
static func within(skin: GameSkin, action: Callable) -> Variant:
	if skin == null:
		return action.call()
	_scoped.append(skin)
	var result: Variant = action.call()
	_scoped.pop_back()
	return result
