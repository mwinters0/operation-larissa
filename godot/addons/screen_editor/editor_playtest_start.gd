@tool
class_name ScreenEditorPlaytestStart
extends AnimatedSprite2D
## Where the sub begins a playtest of this screen: drag it, or pick its picture. It is NOT part of the sector.
##
## Teaches: a node that exists only for the editor session. It is added to the scene root by the playtest dialog
## (`ScreenEditorPlaytestDialog`), with `owner` set so that it shows in the Scene dock and can be dragged. It is not stored
## anywhere: `ScreenEditor.build()` reads only the layers it made, and the root takes the owner away from every node before it
## saves the scene (`NOTIFICATION_EDITOR_PRE_SAVE`), so neither the `.tscn` holder nor the `.tres` files ever hear of it. "Revert
## to saved" and changing the sector or screen build the scene again, and the marker is gone.
## The position is the sub's SubX / SubY, window pixels of the picture's top-left corner, like `ScreenEditorStart`.

const NODE_NAME := "PlaytestStart"
## The sub keeps its x even when it moves (`SubModel`), and the editor snaps to that grid.
const GRID := Vector2i(2, 2)

## Which of the sub's 9 pictures it shows: 0-4 turning left, 6 facing right.
@export_range(0, 8) var cell: int = 6:
	set(value):
		cell = value
		_show_picture()


func _init() -> void:
	name = NODE_NAME
	centered = false
	modulate = Color(0.55, 1.0, 0.7, 0.8)
	set_notify_local_transform(true)
	sprite_frames = Packs.resource(ScreenEditor.SUB_FRAMES_REL) as SpriteFrames
	animation = &"all"
	_show_picture()


func _show_picture() -> void:
	if sprite_frames != null:
		frame = clampi(cell, 0, sprite_frames.get_frame_count(&"all") - 1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		var snapped_position := ScreenEditorItem.snap(position, GRID)
		if snapped_position != position:
			position = snapped_position


func _draw() -> void:
	var size := Vector2(PieceModel.SUB_PICTURE_SIZE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 1.0, 0.7, 0.9), false)
	draw_string(ThemeDB.fallback_font, Vector2(2, -4), "playtest start (not saved)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 1.0, 0.7))


## The sub's place for `PlaytestSetup`.
func pixel_position() -> Vector2i:
	return Vector2i(position.round())


func _validate_property(property: Dictionary) -> void:
	if property.name in ScreenEditorItem.HIDDEN:
		property.usage = PROPERTY_USAGE_NONE


## The marker of `editor`, or null.
static func find_in(editor: ScreenEditor) -> ScreenEditorPlaytestStart:
	return editor.get_node_or_null(NODE_NAME) as ScreenEditorPlaytestStart


## The marker of `editor`, made at `at` if it is not there yet.
static func ensure_in(editor: ScreenEditor, at: Vector2i, picture: int = 6) -> ScreenEditorPlaytestStart:
	var marker := find_in(editor)
	if marker == null:
		marker = ScreenEditorPlaytestStart.new()
		marker.position = Vector2(at)
		marker.cell = picture
		editor.add_child(marker)
		marker.owner = editor
	return marker
