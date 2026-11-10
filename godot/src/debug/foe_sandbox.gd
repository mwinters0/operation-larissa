class_name FoeSandbox
extends Control
## Sandbox for the creatures: watch their scripts run, collide with them, shoot ink.
##
## Teaches: a tool scene that exercises one system (creature scripts) in isolation:
## a list of what every creature on the screen is doing right now (disassembled
## from the live program counter), a speed control that slows the whole game down
## with `Engine.time_scale`, and single-stepping the GameClock.
##
## Keys:  [ ]  previous / next sector         1 2  previous / next screen
##        - =  slower / faster                 P    pause the clock    S  one tick
##        F  fly the sub (arrows/WASD steer, Space fires ink)
##        H  show hit rectangles               R    start the sector again (creatures start over, nothing collected)
##        F1  creature list on/off    F3  text read-out of air and ink (the console is the real Hud)
##        F12  save a screenshot to user://screenshots/
##        Tab / Shift+Tab  select the next / previous creature on the screen (a frame marks it, the list shows it first)
## Command line (after `--`): --sector= --screen= --foe=N --pause --fly --touch=N --ticks=N --snapshot=PATH
## (--snapshot runs N ticks, writes the picture and quits, for documentation;
## --touch=N first puts the sub on creature number N so that they collide;
## --foe=N selects creature N and, unless --screen= says otherwise, opens on the screen it lives on;
## --pause starts with the clock stopped, to step with S).
## The same words may come in the environment variable NEPTUNE_SANDBOX_ARGS: the Foe Script editor's "Run in sandbox"
## button cannot give `EditorInterface.play_custom_scene` any arguments, so it sets the variable for the game it starts.
##
## SOURCE LINES. Every creature row shows the `.foe` line its program counter is on, next to the live disassembly
## (`FoeSourceMap`: the assembler's table of instruction -> line). While the clock is paused, and when run from the
## editor, the lines are also sent to the editor over the debugger channel (`EngineDebugger.send_message`, see
## `line_report`), where addons/foe_script_editor/foe_debugger_plugin.gd marks them in the Foe Script screen.

const SPEEDS: Array[float] = [0.125, 0.25, 0.5, 1.0, 2.0, 4.0]
const MAX_LIST_CREATURES := 3
const SCREENSHOT_DIR := "user://screenshots/"
## The environment variable that carries extra command-line words (see above).
const ARGS_ENV := "NEPTUNE_SANDBOX_ARGS"
## The message the sandbox sends to the editor's debugger plugin: `line_report()` as its only argument.
const LINES_MESSAGE := "foe_sandbox:lines"

@export var start_sector: int = 0
@export var start_screen: int = 0

## The creature the designer is looking at (its number in the sector), -1 for none.
var selected_foe: int = -1

var _speed_index: int = 3
var _shots: int = 0
var _reported_running := false
## The run as the game plays it: starting a sector, a math problem, a lost tank (`ToolRun`).
var _run: ToolRun

@onready var world: SectorWorld = %SectorWorld
@onready var title_label: Label = %TitleLabel
@onready var list_label: Label = %ListLabel
@onready var debug_hud: Label = %DebugHud
@onready var selection_marker: ReferenceRect = %SelectionMarker


## The words of the command line and of `ARGS_ENV`, read into a Dictionary: "sector", "screen" (-1: not given), "foe" (-1: none),
## "fly", "touch" (-1: none), "ticks", "snapshot", "pause". Unknown words are ignored. Plain data in, plain data out, so a test
## can check it without a scene.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {"sector": 0, "screen": -1, "foe": -1, "fly": false, "touch": -1, "ticks": 0, "snapshot": "", "pause": false}
	for arg in args:
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"sector":
				parsed["sector"] = value.to_int()
			"screen":
				parsed["screen"] = value.to_int()
			"foe":
				parsed["foe"] = value.to_int() if value.is_valid_int() else -1
			"fly":
				parsed["fly"] = true
			"pause":
				parsed["pause"] = true
			"touch":
				parsed["touch"] = value.to_int()
				parsed["fly"] = true
			"ticks":
				parsed["ticks"] = value.to_int()
			"snapshot":
				parsed["snapshot"] = value
	return parsed


## The words the game was given: the command line after `--`, then `ARGS_ENV` (split at spaces).
static func launch_args() -> PackedStringArray:
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_environment(ARGS_ENV).split(" ", false))
	return args


## The screen to open on: the one asked for, else the one creature `parsed["foe"]` lives on, else 0. A creature that
## the sector does not have is ignored (the sandbox opens on screen 0 and selects nothing).
static func opening_screen(parsed: Dictionary, sector: SectorData) -> int:
	if parsed["screen"] >= 0:
		return parsed["screen"]
	var foe: int = parsed["foe"]
	return sector.foes[foe].screen if foe >= 0 and foe < sector.foes.size() else 0


func _ready() -> void:
	var parsed := parse_args(launch_args())
	start_sector = parsed["sector"]
	start_screen = opening_screen(parsed, Catalog.sector(start_sector))
	var touch: int = parsed["touch"]
	var snapshot_path: String = parsed["snapshot"]
	GameState.reset()
	_run = ToolRun.new(world, self)
	GameClock.tick.connect(func(_count: int) -> void: _refresh())
	_run.begin_sector(start_sector, start_screen)
	if parsed["foe"] < world.sim.foes.size():
		selected_foe = parsed["foe"]
	if parsed["fly"]:
		world.start_flight()
	if parsed["pause"]:
		GameClock.paused = true
	_refresh()
	if not snapshot_path.is_empty():
		GameClock.paused = true
		if touch >= 0:
			# Centre the sub on the creature (the contacts are rectangle arithmetic in the next tick) and give the frames a moment to
			# draw it there.
			world.sim.sub.position = Rect2(world.sim.foes[touch].hit_rect_window()).get_center() - SubModel.PLAYFIELD_ORIGIN
			for i in 4:
				await get_tree().process_frame
		for i in parsed["ticks"]:
			GameClock.step()
		await _save_screenshot(snapshot_path, true)


func _process(_delta: float) -> void:
	# The frame follows the selected creature as it moves.
	var foe := selected_foe_model()
	selection_marker.visible = foe != null and foe.vm.screen == world.screen_index
	if selection_marker.visible:
		var rect := foe.hit_rect_window().grow(2)
		selection_marker.position = Vector2(rect.position)
		selection_marker.size = Vector2(rect.size)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_TAB:
			select_next_foe(-1 if key_event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
		KEY_F1:
			list_label.visible = not list_label.visible      # the creature list covers part of the playfield
		KEY_F3:
			debug_hud.visible = not debug_hud.visible
		KEY_BRACKETLEFT:
			_load(Catalog.step_sector(world.sector_index, -1), 0)
		KEY_BRACKETRIGHT:
			_load(Catalog.step_sector(world.sector_index, 1), 0)
		KEY_1:
			world.load_screen(posmod(world.screen_index - 1, Catalog.SCREENS_PER_SECTOR))
		KEY_2:
			world.load_screen(posmod(world.screen_index + 1, Catalog.SCREENS_PER_SECTOR))
		KEY_MINUS:
			_set_speed(_speed_index - 1)
		KEY_EQUAL:
			_set_speed(_speed_index + 1)
		KEY_P:
			GameClock.paused = not GameClock.paused
		KEY_S:
			GameClock.step()
		KEY_F:
			if world.sim.sub.active:
				world.stop_flight()
			else:
				world.start_flight()
		KEY_H:
			world.show_collisions = not world.show_collisions
		KEY_R:
			_load(world.sector_index, world.screen_index)
		KEY_F12:
			_shots += 1
			_save_screenshot("%sm4_sandbox_s%02d_sc%02d_%d.png" % [
					SCREENSHOT_DIR, world.sector_index, world.screen_index, _shots], false)
	_refresh()


## Starts `sector` on `screen` as the game starts a sector (`ToolRun.begin_sector`: nothing collected, the midpoint forgotten), and
## the sub flies on if it flew.
func _load(sector: int, screen: int) -> void:
	var flying := world.sim.sub.active
	_run.begin_sector(sector, screen)
	if flying:
		world.start_flight()


func _set_speed(index: int) -> void:
	_speed_index = clampi(index, 0, SPEEDS.size() - 1)
	Engine.time_scale = SPEEDS[_speed_index]


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## The selected creature's model, or null.
func selected_foe_model() -> FoeModel:
	return world.sim.foes[selected_foe] if selected_foe >= 0 and selected_foe < world.sim.foes.size() else null


## The creatures on the shown screen, in creature order.
func foes_on_screen() -> Array[FoeModel]:
	var found: Array[FoeModel] = []
	for foe in world.sim.foes:
		if foe.vm.screen == world.screen_index:
			found.append(foe)
	return found


## Selects the next (`step` 1) or previous (-1) creature on the shown screen; the first one when nothing on it is selected.
func select_next_foe(step: int) -> void:
	var shown := foes_on_screen()
	if shown.is_empty():
		return
	var at := -1
	for i in shown.size():
		if shown[i].vm.index == selected_foe:
			at = i
	selected_foe = shown[posmod(at + step, shown.size())].vm.index


## Where every creature on the shown screen is in the text: {"sector", "screen", "selected" (creature number or -1),
## "lines": {creature number: .foe line of the instruction it runs next}}. Plain Variants, as the debugger channel needs.
func line_report() -> Dictionary:
	var lines := {}
	for foe in foes_on_screen():
		lines[foe.vm.index] = world.sector.foe_line_of(foe.vm.pc)
	return {"sector": world.sector_index, "screen": world.screen_index, "selected": selected_foe, "lines": lines}


## While the clock is paused (stepping) tells the editor which line every creature is on; when it runs again, once, that
## nothing is marked any more (an empty "lines"). Does nothing unless the editor started this game.
func _report_to_editor() -> void:
	if not EngineDebugger.is_active():
		return
	if GameClock.paused:
		EngineDebugger.send_message(LINES_MESSAGE, [line_report()])
		_reported_running = false
	elif not _reported_running:
		var report := line_report()
		report["lines"] = {}
		EngineDebugger.send_message(LINES_MESSAGE, [report])
		_reported_running = true


## One row per creature on the shown screen (the selected one first), two lines each: the live disassembly, and under it
## the `.foe` line it came from.
func _refresh() -> void:
	if world.sector == null:
		return
	var sector := world.sector
	title_label.text = "Sector %d - %s - screen %d   speed x%s%s%s" % [
			sector.index, Catalog.zone(sector.zone).title, world.screen_index, str(SPEEDS[_speed_index]),
			"   [paused]" if GameClock.paused else "", "   [flying]" if world.sim.sub.active else ""]
	var shown := foes_on_screen()
	shown.sort_custom(func(a: FoeModel, b: FoeModel) -> bool: return a.vm.index == selected_foe and b.vm.index != selected_foe)
	var lines: Array[String] = []
	var rows := 0
	for foe in shown:
		var vm := foe.vm
		if rows >= MAX_LIST_CREATURES:
			continue
		rows += 1
		lines.append("%s#%-2d (%3d,%3d) pic %-3d%s dmg %-2d %s%s%s%s  %s" % [
				">" if vm.index == selected_foe else " ",
				vm.index, vm.x, vm.y, vm.frame, "m" if vm.flip else " ", vm.damage,
				"D" if vm.dormant else "-", "H" if vm.hidden else "-", "I" if vm.interrupted else "-",
				"F" if not vm.fault.is_empty() else "-",
				FoeAsm.instruction_text(sector.foe_bytecode, sector.foe_script_base, sector.foe_labels, vm.pc, FoeNames.for_sector(sector))])
		lines.append("      " + sector.foe_source_map.describe(vm.pc))
	if shown.size() > rows:
		lines.append("... and %d more on this screen (Tab selects)" % (shown.size() - rows))
	list_label.text = "\n".join(lines) if not lines.is_empty() else "(no creatures on this screen)"
	_report_to_editor()


## Saves the 640 x 400 picture. With `quit_after` the program ends (command line use).
func _save_screenshot(path: String, quit_after: bool) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := get_viewport().get_texture().get_image().save_png(absolute)
	if error != OK:
		push_error("Could not save screenshot %s (error %d)" % [absolute, error])
	else:
		print("screenshot saved: ", absolute)
	if quit_after:
		get_tree().quit(0 if error == OK else 1)
