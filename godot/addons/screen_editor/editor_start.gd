@tool
class_name ScreenEditorStart
extends ScreenEditorItem
## Where the sub reappears after losing a tank past the middle of the sector (`SectorData.start_pos`, `start_frame`).
##
## Teaches: more sector data shown on a screen. The header of `sector_NN.tres` holds ONE respawn point, and the game
## places it on the midpoint screen (screen 6 in the original, `Tuning.midpoint_screen`): a sector that is started anew begins with the launch from the
## supply station on screen 0 instead (DESIGN 3.6). The editor therefore shows this node on that screen only. The picture
## is the sub's sprite cell `start_frame` (0-8: 0-4 turning left, 6 facing right ...), at its top-left corner `position`,
## as `SubModel.place_original` puts it.

## Which of the sub's 9 pictures it shows when it appears.
@export_range(0, 8) var start_frame: int = 6:
	set(value):
		start_frame = value
		show_picture()
		_edited()


func _init() -> void:
	super()
	grid = Vector2i(2, 2)


func show_picture() -> void:
	if sprite_frames != null:
		frame = clampi(start_frame, 0, sprite_frames.get_frame_count(&"all") - 1)
		modulate = Color(1, 1, 1, 0.75)


func _get_configuration_warnings() -> PackedStringArray:
	var found := _common_warnings()
	for message in ScreenEditorPiece.problems_of(pixel_position(), "respawn point"):
		found.append(message)
	return found
