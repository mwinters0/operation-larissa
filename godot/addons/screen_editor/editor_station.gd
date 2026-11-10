@tool
class_name ScreenEditorStation
extends Node2D
## The supply station the game draws on the first screen (the sub starts in it) and the last one (the dock). Not editable.
##
## Teaches: why the editor can not simply reuse a game scene. `SupplyStation` (src/gameplay/supply_station.gd) is not a
## `@tool` script and gets its pictures from the `Catalog`, so inside the editor it would be an empty node. This class
## repeats the part that only PLACES the pictures (`SupplyStation.set_side`), in window pixels, so the picture of the
## screen matches what the game shows; the numbers are the same ones. It has no owner in the scene, so it is neither saved
## nor listed in the scene tree.

const FRAMES_REL := "data/sprite_frames/station_frames.tres"
## Y of the door and of the sub while it drives.
const DRIVE_Y := SupplyStation.DRIVE_Y
## The screen of the end station (the dock), fixed in the original program like screen 0's start station.
const LAST_SCREEN := SimWorld.DOCK_SCREEN


## True for the screens that have a station: 0 (on the left) and 11 (on the right).
static func shown_on(screen: int) -> bool:
	return screen == 0 or screen == LAST_SCREEN


func show_for(screen: int) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if not shown_on(screen):
		return
	var frames := Packs.resource(FRAMES_REL) as SpriteFrames
	if frames == null:
		return
	var left := screen == 0
	_add(frames, 0, Vector2(16, 144) if left else Vector2(448, 144), left)               # the body
	if not left:
		_add(frames, 1, Vector2(528, 144), false)
		_add(frames, 1, Vector2(576, 144), true)
	_add(frames, 2, Vector2(84, DRIVE_Y) if left else Vector2(448, DRIVE_Y), left)       # the closed door


func _add(frames: SpriteFrames, picture: int, at: Vector2, flipped: bool) -> void:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = frames.get_frame_texture(&"all", picture)
	sprite.flip_h = flipped
	sprite.position = at
	add_child(sprite)
