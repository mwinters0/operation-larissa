extends Control
## Skin authoring tool: ONE game, two looks, side by side. The left half is the original skin, the right half the skin
## you pick; both are bound to the same rules (`SimWorld`), so they show the very same moment of the very same sector. Lay the debug
## rectangles over both (O) and you can see whether your pictures cover what the rules test; fly (F) and watch both halves follow.
##
## Teaches: what "a skin is only a look" means in practice. There is one `SimWorld` (the left half's `SectorWorld` owns it) and two
## presenters listening to it; the right one is dressed for its skin with `SectorPresenter.skin`, so while the global
## `SkinChoice.current()` stays the original everything the right half fetches (pictures, frames, the HUD's layout and words) comes from the
## skin you picked (`SkinChoice.within`). Each half is a 640 x 400 `SubViewport`, given its skin's render settings (`RenderSettings.apply_to`),
## because filtering and pixel snapping are properties of the viewport. Then it is the same tool as the sector viewer for choosing
## what to look at.
##
## Keys:  [ and ]  previous / next sector      Arrows  neighbouring screen      Space  pause the clock
##        , and .  previous / next skin for the right half (or the drop-down above it)
##        O  the debug rectangles over both halves      L  educational level 0-3
##        F  flight mode: the arrows (or WASD) steer the sub through the screens, Space fires ink; a lost tank respawns the sub;
##           Enter opens the problem a trigger is counting down to
##        F1  this key list
##
## Command line (after `--`):
##   godot --path godot res://src/debug/skin_compare.tscn -- --skin=<id> --sector=3 --screen=5 --fly --overlay \
##         --ticks=40 --snapshot=/some/where/shot.png
## `--skin=<id>` is the skin of the RIGHT half (a folder `res://skins/<id>`, or the path of any `GameSkin` file such as
## `res://tests/skins/tiny/skin.tres`, which is then added to the drop-down; the left one is always the original, so `SkinChoice` is held on
## the original here); `--overlay` starts with the rectangles on. With --snapshot the tool runs --ticks game ticks, saves its window as a
## PNG and quits.
##
## What is not dressed: the problem screens and everything else that opens over the tool show the original skin (the tool is not the game).

const HUD_SCENE := preload("res://src/ui/hud.tscn")
## The tool's window: two 640 x 400 halves side by side under a 40 px header.
const HALF_SIZE := Vector2i(640, 400)
const WINDOW_SIZE := Vector2i(HALF_SIZE.x * 2, HALF_SIZE.y + 40)

@export var start_sector: int = 0
@export var start_screen: int = 0

var start_level: int = -1
var _pending_ticks: int = 0
var _start_flying: bool = false
## The skins in the drop-down, in its order: `SkinChoice.available()` and the one `--skin=` named by a path, if any.
var _skins: Array[GameSkin] = []
## The skin of the right half to start with: an id of `res://skins/`, or the path of a skin file (`--skin=`).
var start_skin: String = SkinChoice.ORIGINAL
## The skin of the right half, its presenter, its HUD and its rectangles.
var _skin: GameSkin
var _presenter: SectorPresenter
var _hud: Hud
var _overlay: DebugRectPresenter
## The rectangles are on (they are the world's for the left half, the tool's for the right one).
var _overlay_wanted: bool = false
## Starting a sector, a math problem, a lost tank: as the game does (`ToolRun`).
var _run: ToolRun

@onready var world: SectorWorld = %SectorWorld
@onready var left_viewport: SubViewport = %LeftViewport
@onready var right_viewport: SubViewport = %RightViewport
@onready var right_playfield: Control = %RightPlayfield
@onready var skin_picker: OptionButton = %SkinPicker
@onready var skin_label: Label = %SkinLabel
@onready var title_label: Label = %TitleLabel
@onready var help_label: Label = %HelpLabel


func _init() -> void:
	# The skin in use stays the original, whatever `--skin=` says (that is the right half's): the left half and the tool's own screens are
	# the original. (Before any child is ready, so that the world takes the original's presenter.)
	SkinChoice.forced = SkinChoice.ORIGINAL


func _ready() -> void:
	var snapshot_path := _apply_command_line()
	_fit_window()
	SkinChoice.original().render_settings().apply_to(left_viewport)
	_fill_skin_picker()
	GameState.reset()
	GameState.edu_level = start_level if start_level >= 0 else GameState.edu_level
	world.screen_loaded.connect(_on_screen_loaded)
	world.sim.ticked.connect(_show_title)
	_run = ToolRun.new(world, self)
	_run.begin_sector(start_sector, start_screen)
	if _start_flying:
		world.start_flight()
	_show_skin(_skins[skin_picker.selected])             # (after the sector is loaded: the presenter builds what the rules hold)
	if PresenterChoice.overlay_requested():
		_set_overlay(true)
	if not snapshot_path.is_empty():
		await _save_snapshot_and_quit(snapshot_path)


## Draws the frame: both halves show every moving thing `GameClock.tick_fraction()` of the way into the current tick. (The left one is
## the world's own job, it does it in its `_process`.)
func _process(_delta: float) -> void:
	var fraction := GameClock.tick_fraction()
	if _presenter != null:
		_presenter.run_in_skin(_presenter.show_between_ticks.bind(fraction))
	if _overlay != null:
		_overlay.show_between_ticks(fraction)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var flying := world.sim.sub.active
	match key_event.keycode:
		KEY_F1:
			help_label.visible = not help_label.visible
		KEY_F:
			if flying:
				world.stop_flight()
			else:
				world.start_flight()
			_refresh_right()
		KEY_BRACKETLEFT:
			_change_sector(-1)
		KEY_BRACKETRIGHT:
			_change_sector(1)
		KEY_LEFT:
			_go(SectorData.Direction.LEFT)
		KEY_RIGHT:
			_go(SectorData.Direction.RIGHT)
		KEY_UP:
			_go(SectorData.Direction.UP)
		KEY_DOWN:
			_go(SectorData.Direction.DOWN)
		KEY_L:
			GameState.edu_level = (GameState.edu_level + 1) % 4
			_on_screen_loaded(world.sector_index, world.screen_index)
		KEY_O:
			_set_overlay(_overlay == null)
		KEY_COMMA:
			_pick_skin(posmod(_skins.find(_skin) - 1, _skins.size()))
		KEY_PERIOD:
			_pick_skin(posmod(_skins.find(_skin) + 1, _skins.size()))
		KEY_SPACE:
			if not flying:
				GameClock.paused = not GameClock.paused
				_on_screen_loaded(world.sector_index, world.screen_index)


# --- the right half -----------------------------------------------------------------------------

## Dresses the right half in `skin`: the viewport gets the skin's render settings, a presenter of the skin is bound to the world's rules,
## and so is a HUD with the skin's layout and lettering. What was there is taken away first.
func _show_skin(skin: GameSkin) -> void:
	_clear_right()
	_skin = skin
	skin.render_settings().apply_to(right_viewport)
	# Everything that is built for the skin is built inside it: a node fetches its pictures when it enters the tree (`_ready`).
	SkinChoice.within(skin, func() -> void:
		_presenter = PresenterChoice.make_presenter_for(skin)
		right_playfield.add_child(_presenter)
		skin.render_settings().apply_to_playfield(_presenter)
		_presenter.bind(world.sim)
		_hud = HUD_SCENE.instantiate() as Hud
		_hud.skin = skin
		right_viewport.add_child(_hud))
	if _overlay_wanted:
		_overlay = DebugRectPresenter.overlay(right_playfield, world.sim)
	skin_label.text = skin.display_name if not skin.display_name.is_empty() else String(skin.id)
	_show_title()


## Takes the right half's presenter, rectangles and HUD away (the presenter stops listening to the rules before it is freed).
func _clear_right() -> void:
	for node: Node in [_presenter, _overlay, _hud]:
		if node == null:
			continue
		if node is SectorPresenter:
			(node as SectorPresenter).unbind()
		node.get_parent().remove_child(node)
		node.queue_free()
	_presenter = null
	_overlay = null
	_hud = null


## Shows the whole state of the rules in the right half again, as the world does for the left one after it moved something by hand.
func _refresh_right() -> void:
	if _presenter != null:
		_presenter.run_in_skin(_presenter.refresh)


## The debug rectangles over both halves, or off. The left ones belong to the world (`SectorWorld.set_overlay`).
func _set_overlay(on: bool) -> void:
	_overlay_wanted = on
	world.set_overlay(on)
	if on and _overlay == null:
		_overlay = DebugRectPresenter.overlay(right_playfield, world.sim)
	elif not on and _overlay != null:
		_overlay.unbind()
		right_playfield.remove_child(_overlay)
		_overlay.queue_free()
		_overlay = null
	_show_title()


func _fill_skin_picker() -> void:
	for id in SkinChoice.available():
		_skins.append(SkinChoice.load_skin(id))
	var wanted := -1
	if start_skin.begins_with("res://"):                     # (a skin file that does not live in res://skins/, e.g. the test skin)
		var skin := load(start_skin) as GameSkin
		if skin != null:
			_skins.append(skin)
			wanted = _skins.size() - 1
	else:
		for i in _skins.size():
			if _skins[i].id == StringName(start_skin):
				wanted = i
	if wanted < 0:
		push_error("skin_compare: no skin '%s' (the skins are: %s)" % [start_skin, ", ".join(_skins.map(func(s: GameSkin) -> String: return s.id))])
		wanted = 0
	for skin in _skins:
		skin_picker.add_item(String(skin.id))
	skin_picker.select(wanted)
	skin_picker.item_selected.connect(_pick_skin)


## The right half wears the skin number `index` of the drop-down.
func _pick_skin(index: int) -> void:
	skin_picker.select(index)
	_show_skin(_skins[index])


# --- what to look at (as the sector viewer) --------------------------------------------------------

func _go(direction: SectorData.Direction) -> void:
	if not world.sim.sub.active:
		world.go(direction)
		_refresh_right()


func _change_sector(step: int) -> void:
	_run.begin_sector(Catalog.step_sector(world.sector_index, step))
	_refresh_right()


func _on_screen_loaded(_sector_index: int, _screen_index: int) -> void:
	_show_title()


func _show_title() -> void:
	var sector := world.sector
	if sector == null:
		return
	var zone := Catalog.zone(sector.zone)
	var game := Catalog.campaign_name_of_sector(sector.index)
	title_label.text = "Sector %d (%s) - %s - screen %d / 11  level %d%s%s%s     tick %d     left: original   right: %s" % [
		world.sector_index, game, zone.title, world.screen_index, GameState.edu_level,
		"   [overlay]" if _overlay_wanted else "",
		"   [paused]" if GameClock.paused else "",
		"   [flying]" if world.sim.sub.active else "",
		world.sim.tick_number, _skin.id if _skin != null else "-"]


# --- the window and the command line ---------------------------------------------------------------

## Two halves need a wider window than the game's: the tool says so (nothing when it is embedded in the editor's game view).
func _fit_window() -> void:
	var window := get_window()
	window.content_scale_size = WINDOW_SIZE
	if not window.is_embedded():
		window.size = WINDOW_SIZE


## Reads `--key=value` / `--flag` user arguments; returns the snapshot path ("" if none).
func _apply_command_line() -> String:
	var snapshot_path := ""
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"skin":
				start_skin = value
			"sector":
				start_sector = value.to_int()
			"screen":
				start_screen = value.to_int()
			"fly":
				_start_flying = true
			"ticks":
				_pending_ticks = value.to_int()
			"level":
				start_level = value.to_int()
			"snapshot":
				snapshot_path = value
	return snapshot_path


func _save_snapshot_and_quit(path: String) -> void:
	GameClock.paused = true                       # we step the clock by hand
	for i in _pending_ticks:
		GameClock.step()
	# Wait for the frame that contains the final state to be drawn.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save snapshot %s (error %d)" % [path, error])
	get_tree().quit(0 if error == OK else 1)
