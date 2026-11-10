extends Node
## Changes the current scene with a short fade to black (autoload "SceneRouter").
##
## Teaches: scene switching the standard way (`SceneTree.change_scene_to_file`), a `CanvasLayer`
## above everything for a fade that survives the switch, a fade COUNTED IN TICKS (`fade_ticks()` of the original's 1/73 s, data: `fade.ticks`, fed with real
## time through a `TickMeter`, instead of a `Tween` with a length in seconds: a step that holds up the game has its length in a number
## of the game's), and `await` so the caller can say "go there" in one line. Scenes do not pass arguments to each other: whatever
## the next scene needs (which player is playing) lives in the `GameState` autoload.
##
##     SceneRouter.go_to("res://src/ui/sign_in.tscn")
##
## THE ORDER OF A SCENE CHANGE, once the fade is black: `leaving` (the scene that goes is told while it is still whole), then
## `change_scene_to_file` (the old scene leaves the tree at once, its children before itself; the new one is added at the end of the
## frame), then `start_fresh` (nothing the old scene held is held any more). Godot runs the CHILDREN's `_exit_tree` before the
## parent's (`Node._propagate_exit_tree`), so a scene that let go of the autoloads only in its own `_exit_tree` would still be
## listening while its children give back what they hold (a problem screen its lost tank, a message box its clock hold). See
## docs/engine/ARCHITECTURE.md, "Lifetimes of state".
##
## Tests set `dry_run = true`: `go_to` then only records the path and emits the signal, so a
## test can check where the game WOULD go without replacing the test runner's own scene.

signal scene_changed(path: String)
## The current scene is about to leave the tree for `path` (see above): it detaches itself from the autoloads now. `Game` lets go of
## its flow here.
signal leaving(path: String)

const PACK_WARNING := "res://src/ui/pack_warning.tscn"
const OPENING := "res://src/story/opening.tscn"
const SIGN_IN := "res://src/ui/sign_in.tscn"
const PRACTICE := "res://src/problems/practice_mode.tscn"
const GAME := "res://src/gameplay/game.tscn"
## One fade (out, or in) lasts this many ticks of 1/73 s (`fade.ticks` of `data/rules/durations.json`, `Durations`). The port always
## had 0.18 s, which is 13.14 ticks; the whole ticks are 13 (0.178 s, 2 ms shorter).
static func fade_ticks() -> int:
	return maxi(Durations.at("fade.ticks"), 1)


var dry_run: bool = false
## The path of the last `go_to` call (for tests and debugging).
var last_path: String = ""

var _fade: ColorRect
var _busy: bool = false
var _meter := TickMeter.new()
## The fade that is running: ticks gone, and the opacity it started from and goes to (-1: none).
var _fade_elapsed: int = -1
var _fade_from: float = 0.0
var _fade_to_alpha: float = 0.0
signal _fade_done


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100                        # above every other layer of the game
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


## Fades out, loads the scene at `path`, fades in. Ignored while a switch is already running.
func go_to(path: String) -> void:
	if _busy:
		return
	_busy = true
	last_path = path
	if not dry_run:
		await _fade_to(1.0)
		leaving.emit(path)
		get_tree().change_scene_to_file(path)    # the old scene leaves the tree now, its children first
		start_fresh()
		await get_tree().process_frame           # the new scene is built during this frame
		await get_tree().process_frame
		await _fade_to(0.0)
	_busy = false
	scene_changed.emit(path)


## Nothing of the scene that left is held any more: the game clock runs (a scene that left it stopped or held must not freeze the next
## one) and no pause of the sound that a dialog took is left (`Audio.reset_pauses`). It runs after the old scene has left the tree, so
## whatever its nodes did on their way out is undone too.
func start_fresh() -> void:
	GameClock.paused = false
	Audio.reset_pauses()


func _fade_to(alpha: float) -> void:
	_fade_from = _fade.modulate.a
	_fade_to_alpha = alpha
	_fade_elapsed = 0
	_meter.reset()
	await _fade_done


func _process(delta: float) -> void:
	if _fade_elapsed >= 0:
		advance_fade(_meter.feed(delta))


## `ticks` ticks of the running fade went by: the black layer is that much more (or less) opaque; when the fade's ticks are over it ends.
## Public so that a test can run a fade without waiting.
func advance_fade(ticks: int) -> void:
	if _fade_elapsed < 0:
		return
	var length := fade_ticks()
	_fade_elapsed = mini(_fade_elapsed + ticks, length)
	_fade.modulate.a = lerpf(_fade_from, _fade_to_alpha, float(_fade_elapsed) / length)
	if _fade_elapsed >= length:
		_fade_elapsed = -1
		_fade_done.emit()
