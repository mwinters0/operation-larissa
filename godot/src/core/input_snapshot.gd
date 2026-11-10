class_name InputSnapshot
extends RefCounted
## What the rules need to know about the player's hands in ONE game tick, taken once at the start of the tick.
##
## Teaches: why a game that runs a slow fixed tick (12.17 Hz) next to a fast frame loop (60 Hz) does not let its rules call
## `Input` themselves. Asked in the middle of a tick, `Input` answers for "right now"; the rules must answer the same on
## every machine and in every test, so the node that owns the tick asks `Input` ONCE (see `InputReader`), writes the answers
## into one of these and hands it to the rules. A test needs no keyboard: it fills the fields it cares about.
##
## There are two kinds of input in it:
##  * a STATE, read at the moment of the tick: which way the keys point (`steer`). Holding a key for 5 frames of a 1 tick wait is
##    the same as holding it for 1.
##  * EVENTS, which happen between ticks and must not be lost or counted twice: a fire press (`fire_presses`). The reader counts
##    them while they happen and hands them over, and starts from zero again, in the snapshot of the next tick.
##
## Not in it: the Enter key that opens a waiting math problem. That is a request to the flow of the game, not to the rules of a
## tick: a message or a hint over the playfield stops the clock, and Enter must still open the problem then (the hint of the
## blinking light is closed by the very Enter that opens it), so `SectorWorld` acts on it when it arrives.

## The direction of the arrow keys / WASD / d-pad as -1, 0, +1 per axis (x: left -1, right +1; y: up -1, down +1).
var steer: Vector2i = Vector2i.ZERO
## How many times the fire button was pressed since the previous snapshot (a held key does not repeat). Normally 0 or 1; two
## presses inside one tick of 82 ms are two shots, if the rules allow them.
var fire_presses: int = 0


## A snapshot with the sub steered one way, for tests and tools.
static func steering(x: int, y: int = 0) -> InputSnapshot:
	var snapshot := InputSnapshot.new()
	snapshot.steer = Vector2i(x, y)
	return snapshot


## A snapshot with the fire button pressed `times` times.
static func firing(times: int = 1) -> InputSnapshot:
	var snapshot := InputSnapshot.new()
	snapshot.fire_presses = times
	return snapshot


## The steering rule of the original: when both keys of an axis are held, LEFT beats right and DOWN beats up (`DoAction`
## tests the left key first and the down key first). `left` ... `down` say which keys are held.
static func steer_from_keys(left: bool, right: bool, up: bool, down: bool) -> Vector2i:
	var result := Vector2i.ZERO
	if left:
		result.x = -1
	elif right:
		result.x = 1
	if down:
		result.y = 1
	elif up:
		result.y = -1
	return result
