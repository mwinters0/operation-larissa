extends Node
## The game's fixed logic clock (autoload "GameClock").
##
## Teaches: `_process` vs a fixed timestep (accumulating `delta`), signals, and
## why a singleton is the right tool for "one clock that everybody listens to".
##
## The original game ran its logic 73/6 = 12.17 times per second (one "game
## frame" = 6 ticks of a 73 Hz timer, see DESIGN 3.1). Creature scripts, animated
## decorations and the invulnerability blink all advance exactly one step per
## tick. Rendering and the sub's movement stay smooth at the monitor's rate;
## only the *logic* uses this slower clock.
##
## Usage:  GameClock.tick.connect(_on_tick)

## Emitted once per logic tick. `count` is the running total since startup.
signal tick(count: int)

## Cleared by `paused = false`, which `SceneRouter.start_fresh` does at every scene change: the switch and the holds of the scene before.
const SCENE_FIELDS: Array[StringName] = [&"_switch", &"_holds"]
## Member variables that no scope clears, and why (docs/engine/ARCHITECTURE.md, "Lifetimes of state").
const KEPT_FIELDS: Dictionary[StringName, String] = {
	&"paused": "a view of `_switch`, `_holds` and `window_active`, with nothing of its own",
	&"holds": "reads `_holds`",
	&"window_active": "the window's focus, not a scene's",
	&"tick_count": "a counter over the life of the program",
	&"_accumulator": "the part of a tick under way: time goes on across a scene change",
}
## Ticks per second (73 / 6 = 12.1666...).
const TICK_HZ := 73.0 / 6.0
## Length of one tick in seconds.
const TICK_SECONDS := 1.0 / TICK_HZ
## After a long stall (window drag, debugger break) do not fire hundreds of
## ticks at once; give up on anything beyond this many.
const MAX_TICKS_PER_ADVANCE := 5

## While true the clock does not run. Three things stop it: the plain switch (`paused = true`, for the
## sector viewer's Space key, tests and scenes that start with a stopped clock), the HOLDS of things that
## cover the playfield (`hold()` / `release()`: a message box, a problem screen, a dialog) and a window that
## is not the active one (`window_active`).
##
## Teaches: why "remember what I found and put it back" is the wrong way to share a switch. A message
## that opens while a problem is up, and a problem that opens while a message is up, close in either
## order; each one that restores its own remembered value can turn the clock back on under the other
## or, worse, leave it OFF for good (the "stuck after the first problem" bug). A counter has no order:
## the clock runs again when the LAST hold is released.
var paused: bool:
	get:
		return _switch or _holds > 0 or not window_active
	set(value):
		_switch = value
		if not value:
			_holds = 0                       # `paused = false` is the hard "start fresh" (a new scene, a test)
## False while the window has lost the focus or a menu is open: the original's game loop (`DoAction` 0x417ffc) polls the
## keyboard once per frame (`PeekInput` 0x410d50 -> 0x410bc5) and that poll does not return while the active flag
## (0x440d80, cleared by `PauseSoundOnDeactivate` 0x413847) is 0, so the whole game stands still; it goes on with the
## next frame (the frame alarm is absolute, there is no catching up). Its own flag, so the hard reset of `paused = false`
## (a new scene) cannot lose it.
var window_active: bool = true
## Total number of ticks emitted so far.
var tick_count: int = 0
## How many covers hold the clock right now (see `hold`).
var holds: int:
	get:
		return _holds

var _switch: bool = false
var _holds: int = 0
var _accumulator: float = 0.0


func _process(delta: float) -> void:
	advance(delta)


## The window lost / regained the focus (Godot sends these two notifications to every node).
func _notification(what: int) -> void:
	if not WindowFocus.enabled:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		window_active = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		window_active = true


## Something covers the playfield (a message box, a problem screen, a dialog): the clock stops. Every
## `hold()` needs exactly one `release()`; the clock runs again when the last one is gone.
func hold() -> void:
	_holds += 1


## The cover is gone. Extra releases are ignored (a hold that was cleared by `paused = false`).
func release() -> void:
	_holds = maxi(0, _holds - 1)


## Feeds `delta` seconds of elapsed time to the clock and emits as many ticks as
## that completes. Returns how many were emitted. `_process` calls this every
## frame; tests call it directly with made-up deltas ("simulated frames").
func advance(delta: float) -> int:
	if paused:
		return 0
	_accumulator = minf(_accumulator + delta, TICK_SECONDS * MAX_TICKS_PER_ADVANCE)
	var emitted := 0
	while _accumulator >= TICK_SECONDS:
		_accumulator -= TICK_SECONDS
		step()
		emitted += 1
		if paused:
			# A listener of this tick took a hold (a problem screen, a message, a dialog, the dissolve): the original's loop is
			# inside that one call and does not run the next pass until it returns, so the ticks of a long frame that are
			# still owed are not run behind the cover. They are not saved for later either: the frame alarm is absolute, there is no catching
			# up (`window_active`), and a leftover would fire a burst of ticks the moment the cover goes. Only the part of a tick that is
			# already under way stays, as after any other frame.
			_accumulator = fposmod(_accumulator, TICK_SECONDS)
			break
	return emitted


## How far we are into the current tick, from 0.0 (a tick has just happened) to
## just below 1.0 (the next one is due). Used to draw moving things smoothly
## between two logic positions, see `TickSmoothing`. While paused (or stepped by
## hand) everything is drawn exactly at its logic position, i.e. 1.0.
func tick_fraction() -> float:
	if paused:
		return 1.0
	return clampf(_accumulator / TICK_SECONDS, 0.0, 1.0)


## Emits exactly one tick right now, ignoring `paused` and the accumulator.
## Handy for single-stepping animations from a debug scene or a test.
func step() -> void:
	tick_count += 1
	tick.emit(tick_count)
