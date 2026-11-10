class_name InputReader
extends RefCounted
## The one place where the keys of the player are turned into the `InputSnapshot` of a game tick.
##
## Teaches: collecting events between two ticks. The frame loop (60 Hz) calls `press_fire` when a key event arrives; the game
## tick (12.17 Hz) calls `take`, which polls the held keys (the steering) and hands over, and forgets, the presses counted so
## far. So a press that lands between two ticks is neither lost nor counted twice, and a held key is one steering state however
## many frames it spans. Whoever owns a tick has one of these (`SectorWorld`, `SubSandbox`); the rules (`Sub`, the world's
## `tick`) only ever see the snapshot.
##
## This and `SectorWorld._unhandled_input` are the only code that reads the playfield's keys.

var _fire_presses: int = 0


## One press of the fire button happened (not an echo of a held key).
func press_fire() -> void:
	_fire_presses += 1


## Reads the held keys now and takes the presses counted since the last `take` (they are forgotten).
func take() -> InputSnapshot:
	var snapshot := InputSnapshot.new()
	snapshot.steer = steering()
	snapshot.fire_presses = _fire_presses
	_fire_presses = 0
	return snapshot


## Forgets the presses counted so far (a new sector: whatever was typed before it is not an order for it).
func forget() -> void:
	_fire_presses = 0


## The arrow keys / WASD / d-pad as -1, 0, +1 per axis, with the original's priorities (`InputSnapshot.steer_from_keys`).
static func steering() -> Vector2i:
	return InputSnapshot.steer_from_keys(
			Input.is_action_pressed(&"sub_left"), Input.is_action_pressed(&"sub_right"),
			Input.is_action_pressed(&"sub_up"), Input.is_action_pressed(&"sub_down"))
