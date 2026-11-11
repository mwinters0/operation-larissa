class_name PresenterChoice
extends RefCounted
## Which presenter shows the sector: the original look, or the debug rectangles. One small place that knows the names, so that the
## command line, the F3 debug keys, the sector viewer and the tests all say the same thing.
##
## Teaches: a choice made OUTSIDE the game. Nothing in the rules asks which presenter is in use (they cannot: they know no
## presenter), so the choice is a node swapped into `SectorWorld`, and the game is the same game either way.
##
## The ORIGINAL kind is "the presenter of the skin in use": a skin may bring its own scene (`GameSkin.presenter_scene`), whose root
## extends `SectorPresenter`, and the original's is the one it falls back to. The skin is chosen by `SkinChoice`; the kind here is
## chosen apart from it, so a skin's presenter and the debug rectangles can be swapped and swapped back.
##
## THE OVERLAY. Apart from being the presenter, the debug rectangles can be laid OVER whatever presenter the skin brings
## (`SectorWorld.set_overlay`): the rectangles the rules test drawn on top of the skin's pictures, to see whether a picture covers its
## rectangle. `-- --overlay` starts the game with it on, and it is a key in the game (F3 then O) and in the sector viewer (O).
##
## From the command line (arguments after `--`):
##     godot --path godot -- --presenter=debug_rects
##     godot --path godot -- --skin=<id> --overlay

const ORIGINAL := &"original"
const DEBUG_RECTS := &"debug_rects"
const ORIGINAL_SCENE := "res://src/gameplay/original_presenter.tscn"

## A test or tool sets this to decide before a `SectorWorld` is made (it wins over the command line). Empty: no choice.
static var forced: StringName = &""
## A test or tool sets this to start every `SectorWorld` with the debug rectangles laid over its presenter (`SectorWorld.set_overlay`).
static var overlay_forced: bool = false


## The kind this run asks for: `forced`, else `--presenter=<kind>` on the command line, else the original one.
static func requested() -> StringName:
	if not forced.is_empty():
		return forced
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--presenter="):
			return StringName(arg.get_slice("=", 1))
	return ORIGINAL


## A new presenter of kind `which` (not in the tree yet). An unknown kind is a loud error, not a silent fallback to the original look.
## The original kind is the skin's presenter scene, or the original's when the skin has none.
static func make_presenter(which: StringName) -> SectorPresenter:
	match which:
		ORIGINAL:
			return original_scene().instantiate() as SectorPresenter
		DEBUG_RECTS:
			return DebugRectPresenter.new()
	push_error("unknown presenter '%s' (expected '%s' or '%s')" % [which, ORIGINAL, DEBUG_RECTS])
	return original_scene().instantiate() as SectorPresenter


## The scene of the original kind: the presenter of `skin` (null: the skin in use), else `ORIGINAL_SCENE`.
static func original_scene(skin: GameSkin = null) -> PackedScene:
	var from_skin := SkinChoice.worn(skin).presenter_scene_or_null()
	return from_skin if from_skin != null else load(ORIGINAL_SCENE) as PackedScene


## A new presenter of the original kind dressed in `skin` (`SectorPresenter.skin`), not in the tree yet. Add it to the tree and bind it
## inside `presenter.run_in_skin(...)`, so that what it fetches when it is built is `skin`'s. For a tool that shows several skins at once.
static func make_presenter_for(skin: GameSkin) -> SectorPresenter:
	var presenter := original_scene(skin).instantiate() as SectorPresenter
	presenter.skin = skin
	return presenter


## The overlay of the debug rectangles asked for on the command line (`-- --overlay`) or by a test (`overlay_forced`).
static func overlay_requested() -> bool:
	return overlay_forced or OS.get_cmdline_user_args().has("--overlay")


## The kind `presenter` is (a skin's own presenter is the original kind).
static func kind_of(presenter: SectorPresenter) -> StringName:
	return DEBUG_RECTS if presenter is DebugRectPresenter else ORIGINAL


## The other one: what the debug key swaps to.
static func other_than(presenter: SectorPresenter) -> StringName:
	return ORIGINAL if kind_of(presenter) == DEBUG_RECTS else DEBUG_RECTS
