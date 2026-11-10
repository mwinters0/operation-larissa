class_name ScreenPlaytest
extends Control
## Flies one screen of a sector from a chosen state: the tool scene behind the screen editor's "Playtest screen".
##
## Teaches: a tool scene that is only a harness. The state to start from is a `PlaytestSetup` (air, ink, pieces, flags, creature
## states, where the sub is), read from the command line or from the environment variable the editor sets, and applied to the
## sector world's `SimWorld` before the first tick; after that nothing here decides a rule. A math problem opens and a lost tank or a
## lost game is answered as in the game (`ToolRun`: a little later, outside the signal), except that it starts the setup over instead
## of the sector (this is a test of ONE screen, not of the run).
##
## Keys:  R  start over from the setup      P  pause the clock      S  one tick (while paused)
##        -  =  slower / faster              H  show hit rectangles   F1  the setup on/off
##        F3  text read-out of air and ink (the console is the real Hud)
## Command line (after `--`) or `FoeSandbox.ARGS_ENV`: the words of `PlaytestSetup.to_arguments`.

const SPEEDS: Array[float] = [0.125, 0.25, 0.5, 1.0, 2.0, 4.0]

## What the scene was asked to start from.
var setup := PlaytestSetup.new()

var _speed_index: int = 3
var _restarts: int = 0
## The math problems and the lost tanks, as the game answers them (`ToolRun`); a loss starts the setup over (`_start_over`).
var _run: ToolRun

@onready var world: SectorWorld = %SectorWorld
@onready var title_label: Label = %TitleLabel
@onready var setup_label: Label = %SetupLabel
@onready var debug_hud: Label = %DebugHud


func _ready() -> void:
	setup = PlaytestSetup.from_arguments(FoeSandbox.launch_args())
	for message in setup.problems():
		push_warning("playtest: " + message)
	GameClock.paused = false
	GameClock.tick.connect(func(_count: int) -> void: _refresh())
	_run = ToolRun.new(world, self, _start_over)
	start()
	GameClock.paused = setup.paused
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_R:
			start()
		KEY_P:
			GameClock.paused = not GameClock.paused
		KEY_S:
			GameClock.step()
		KEY_H:
			world.show_collisions = not world.show_collisions
		KEY_MINUS:
			_set_speed(_speed_index - 1)
		KEY_EQUAL:
			_set_speed(_speed_index + 1)
		KEY_F1:
			setup_label.visible = not setup_label.visible
		KEY_F3:
			debug_hud.visible = not debug_hud.visible
	_refresh()


## Begins the playtest: the world is loaded and the sub placed as `setup` says (a launch from the station runs in the game's ticks,
## as it does at the start of a sector). The same call starts it over.
func start() -> void:
	world.take_input()                                 # (a key pressed before is forgotten)
	setup.apply(world.sim)
	world.refresh_views()


func _set_speed(index: int) -> void:
	_speed_index = clampi(index, 0, SPEEDS.size() - 1)
	Engine.time_scale = SPEEDS[_speed_index]


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## A lost tank or game: the playtest starts over (the sector's own restart would take the sub away from the screen being tested).
func _start_over() -> void:
	_restarts += 1
	start()
	_refresh()


func _refresh() -> void:
	if world.sector == null:
		return
	title_label.text = "Playtest: sector %d - %s - screen %d   speed x%s%s%s" % [
			world.sector_index, Catalog.zone(world.sector.zone).title, world.screen_index, str(SPEEDS[_speed_index]),
			"   [paused]" if GameClock.paused else "", "   [started over %d]" % _restarts if _restarts > 0 else ""]
	setup_label.text = "%s\nR starts over   P pauses   S steps   H hit rectangles   F1 hides this" % setup.describe()
