class_name StationLayout
extends RefCounted
## Where the pictures of a supply station go: the ONE list of its parts (the three bodies, the door, the balloon), their picture numbers in the station bundle, their places and mirrors, for the station
## on the left (the start of a sector, screen 0) and on the right (the dock, the last screen). `SupplyStation` puts its nodes there, `ScreenEditorStation` draws the still station there, and
## `SkinState` tells a skin mod the same parts, so none of them repeats a number. Places are playfield pixels (the original's window pixels minus the playfield's origin, (16, 32)), the top-left
## corner of the picture; `door` is the picture of the closed door and `balloon` of the balloon at rest (the balloon's path is `StationSequence`).
##
## The parts are listed in the order they are drawn, back to front: the balloon, the bodies, the door (`LaunchBalloon` draws the balloon first, so it rises from behind the station).
##
## Teaches: one table for the numbers that two views and an export of the state all need, instead of the same literals in each.

## The pictures of the station bundle: 0 and 1 the body, 2 the closed door (3 and 4 moving), 6 the balloon.
const BODY := 0
const BODY_END := 1
const DOOR_CLOSED := 2
const BALLOON := 6

## The window pixels of the pieces of each station (the original's numbers).
const LEFT_BODY := Vector2(16, 144)
const RIGHT_BODY := Vector2(448, 144)
const RIGHT_BODY_MIDDLE := Vector2(528, 144)
const RIGHT_BODY_END := Vector2(576, 144)
const LEFT_DOOR_X := 84
const RIGHT_DOOR_X := 448


## The parts of the station on the left (`left`) or the right: an Array of `{name, picture, position, mirrored}`, `name` one of `balloon`, `body_a`, `body_b`, `body_c`, `door`.
## The right station is three bodies (the first picture 0, the other two picture 1, the last one mirrored); the left one is picture 0 mirrored.
static func parts(left: bool) -> Array[Dictionary]:
	var origin := SubModel.PLAYFIELD_ORIGIN
	var path := StationSequence.balloon()                       # (the balloon waits where its path starts)
	var found: Array[Dictionary] = [
		_part(&"balloon", BALLOON, Vector2(path.balloon_x, path.balloon_from_y) - origin, false),
		_part(&"body_a", BODY, (LEFT_BODY if left else RIGHT_BODY) - origin, left),
	]
	if not left:
		found.append(_part(&"body_b", BODY_END, RIGHT_BODY_MIDDLE - origin, false))
		found.append(_part(&"body_c", BODY_END, RIGHT_BODY_END - origin, true))
	found.append(_part(&"door", DOOR_CLOSED, Vector2(LEFT_DOOR_X if left else RIGHT_DOOR_X, StationSequence.DRIVE_Y) - origin, left))
	return found


static func _part(part_name: StringName, picture: int, position: Vector2, mirrored: bool) -> Dictionary:
	return {"name": part_name, "picture": picture, "position": position, "mirrored": mirrored}
