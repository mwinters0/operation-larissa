extends Control
## Debug viewer for the playfield: browse every sector and screen.
##
## Teaches: `_unhandled_key_input`, the `unique name` (%) node lookup, and how a
## tiny tool scene can exercise a game system without the rest of the game.
##
## The console under the playfield is the real `Hud`; F1 shows this key list and F3 the old text read-out.
##
## Keys:  [ and ]  previous / next sector      Arrows  neighbouring screen
##        C  currents on/off      H  collision shapes on/off      Space  pause clock
##        T  show the (normally invisible) math triggers      L  educational level 0-3
##        P  swap the original look for the debug rectangles (`DebugRectPresenter`) and back
##        O  lay the debug rectangles OVER the picture of the skin in use (and take them off): the skin-authoring overlay
##        F  flight mode: the arrows (or WASD) now steer the sub through the screens,
##           Space fires ink; creatures cost oxygen (a lost tank respawns the sub).
##           Pieces are picked up by touching them; a math trigger blinks a light on the sub
##           and opens its problem after about 3 seconds, or at once with Enter.
##
## Command line (after `--`), used to take screenshots:
##   godot --path godot res://src/debug/sector_viewer.tscn -- --sector=3 --screen=5 \
##         --ticks=7 --currents --collisions --fly --bubble-seed=3 --snapshot=/some/where/shot.png
## and `--presenter=debug_rects` starts with the debug rectangles instead of the original look (`PresenterChoice`), `--overlay` with the
## rectangles laid over the picture, `--skin=<id>` in the skin `res://skins/<id>` (`SkinChoice`). Two skins side by side: `skin_compare.tscn`.
## With --snapshot the viewer saves the 640 x 400 picture and quits.

@export var start_sector: int = 0
@export var start_screen: int = 0

var _pending_ticks: int = 0   # --ticks=N: game ticks to run before a snapshot
var _start_flying: bool = false   # --fly: start in flight mode
var start_level: int = -1         # --level=N: educational level 0-3
var _run: ToolRun                 # starting a sector, a math problem, a lost tank: as the game does

@onready var world: SectorWorld = %SectorWorld
@onready var title_label: Label = %TitleLabel
@onready var help_label: Label = %HelpLabel
@onready var debug_hud: Label = %DebugHud


func _ready() -> void:
	var snapshot_path := _apply_command_line()
	world.screen_loaded.connect(_on_screen_loaded)
	GameState.reset()
	GameState.edu_level = start_level if start_level >= 0 else GameState.edu_level
	_run = ToolRun.new(world, self)
	_run.begin_sector(start_sector, start_screen)
	if _start_flying:
		world.start_flight()
	if not snapshot_path.is_empty():
		await _save_snapshot_and_quit(snapshot_path)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var flying := world.sim.sub.active
	match key_event.keycode:
		KEY_F1:
			help_label.visible = not help_label.visible
		KEY_F3:
			debug_hud.visible = not debug_hud.visible       # the old air/ink text read-out (the real HUD is the console)
		KEY_F:
			if flying:
				world.stop_flight()
			else:
				world.start_flight()
			_on_screen_loaded(world.sector_index, world.screen_index)
		KEY_BRACKETLEFT:
			_change_sector(-1)
		KEY_BRACKETRIGHT:
			_change_sector(1)
		KEY_LEFT:
			if not flying:
				world.go(SectorData.Direction.LEFT)
		KEY_RIGHT:
			if not flying:
				world.go(SectorData.Direction.RIGHT)
		KEY_UP:
			if not flying:
				world.go(SectorData.Direction.UP)
		KEY_DOWN:
			if not flying:
				world.go(SectorData.Direction.DOWN)
		KEY_C:
			world.show_currents = not world.show_currents
			_on_screen_loaded(world.sector_index, world.screen_index)
		KEY_T:
			world.show_triggers = not world.show_triggers
			_on_screen_loaded(world.sector_index, world.screen_index)
		KEY_L:
			GameState.edu_level = (GameState.edu_level + 1) % 4
			_on_screen_loaded(world.sector_index, world.screen_index)
		KEY_P:
			world.toggle_presenter()
			_on_screen_loaded(world.sector_index, world.screen_index)
		KEY_O:
			world.toggle_overlay()
			_on_screen_loaded(world.sector_index, world.screen_index)
		KEY_H:
			world.show_collisions = not world.show_collisions
			_on_screen_loaded(world.sector_index, world.screen_index)
		KEY_SPACE:
			if not flying:
				GameClock.paused = not GameClock.paused
				_on_screen_loaded(world.sector_index, world.screen_index)


func _change_sector(step: int) -> void:
	# `step_sector` wraps around the sectors that exist: stepping back from the first one gives the last one.
	_run.begin_sector(Catalog.step_sector(world.sector_index, step))


func _on_screen_loaded(sector_index: int, screen_index: int) -> void:
	var sector := world.sector
	var zone := Catalog.zone(sector.zone)
	var game := Catalog.campaign_name_of_sector(sector.index)
	title_label.text = "Sector %d (%s) - %s - screen %d / 11  level %d%s%s%s%s%s%s" % [
		sector_index, game, zone.title, screen_index, GameState.edu_level,
		"   [triggers]" if world.show_triggers else "",
		"   [currents]" if world.show_currents else "",
		"   [collisions]" if world.show_collisions else "",
		"   [overlay]" if world.overlay != null else "",
		"   [paused]" if GameClock.paused else "",
		"   [flying]" if world.sim.sub.active else ""]


# --- screenshot support (command line only) -------------------------------

## Reads `--key=value` / `--flag` user arguments; returns the snapshot path ("" if none).
func _apply_command_line() -> String:
	var snapshot_path := ""
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"sector":
				start_sector = value.to_int()
			"screen":
				start_screen = value.to_int()
			"fly":
				_start_flying = true
			"currents":
				world.show_currents = true
			"collisions":
				world.show_collisions = true
			"ticks":
				_pending_ticks = value.to_int()
			"level":
				start_level = value.to_int()
			"triggers":
				world.show_triggers = true
			"bubble-seed":
				if world.original != null:                           # (the debug rectangles have no bubbles)
					world.original.bubbles.seed_rng(value.to_int())     # the same ambient bubbles every run
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
