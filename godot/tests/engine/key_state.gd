class_name KeyState
extends RefCounted
## Test helper: the arrow keys a test "holds", handed to the rules as the `InputSnapshot` of each tick. The rules read no keyboard
## (`InputReader` is the only code that does), so a test needs no `Input.action_press`: it keeps a `KeyState`, calls `press` /
## `release` like a player would, and passes `snapshot()` to `SubModel.logic_tick` or `SectorWorld.tick`.

var _held := {}


func press(action: StringName) -> void:
	_held[StringName(action)] = true


func release(action: StringName) -> void:
	_held.erase(StringName(action))


func release_all() -> void:
	_held.clear()


func snapshot() -> InputSnapshot:
	var result := InputSnapshot.new()
	result.steer = InputSnapshot.steer_from_keys(
			_held.has(&"sub_left"), _held.has(&"sub_right"), _held.has(&"sub_up"), _held.has(&"sub_down"))
	return result
