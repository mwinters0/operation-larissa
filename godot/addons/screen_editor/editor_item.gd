@tool
class_name ScreenEditorItem
extends AnimatedSprite2D
## Base of the picture nodes of the screen editor: a deco, an animated deco, a piece, the sub's start.
##
## Teaches: `@tool` classes that hold their own editor behaviour. The node keeps the OFFICIAL position in
## `position` (window pixels, the numbers stored in the file) and makes the 2D editor respect the original's grid:
## the original stores a deco's x / 4 and y / 2 in single bytes, so a deco can only stand on multiples of (4, 2). Godot's
## 2D editor moves nodes by writing `position`; `set_notify_local_transform(true)` tells us every time that happens
## (`NOTIFICATION_LOCAL_TRANSFORM_CHANGED`) and we round it back onto the grid. Dragging with the mouse, the arrow keys
## and typing into the Inspector then all end up on legal positions, and the editor's undo still works, because undo only
## writes back positions that were already snapped.
##
## All the picture nodes show a picture of a `SpriteFrames` ("slot k = frame k of the animation `all`", the same way the
## game's `Deco` does it). The frames come from the `ScreenEditor` root (it knows the sector's zone), picked up when the
## node enters the tree, so a node made by "Add Child Node" or Ctrl+D works too.

## The step the position snaps to, in window pixels. Subclasses set it in `_init`.
var grid: Vector2i = Vector2i(2, 2)


func _init() -> void:
	centered = false
	set_notify_local_transform(true)


func _enter_tree() -> void:
	var editor := ScreenEditor.find_for(self)
	if editor != null:
		adopt(editor)
	_edited()


## Called when the node joins a `ScreenEditor`: take the pictures it offers. Subclasses extend this.
func adopt(editor: ScreenEditor) -> void:
	if sprite_frames == null:
		sprite_frames = editor.frames_for(self)
		animation = &"all"
	show_picture()


## Show the picture that goes with the node's data. Subclasses override this.
func show_picture() -> void:
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		var snapped_position := ScreenEditorItem.snap(position, grid)
		if snapped_position != position:
			position = snapped_position            # sends this notification once more, with nothing left to fix
		else:
			_edited()


## `p` rounded to the nearest multiple of `step` on each axis.
static func snap(p: Vector2, step: Vector2i) -> Vector2:
	return Vector2(roundi(p.x / step.x) * step.x, roundi(p.y / step.y) * step.y)


## The position as the integer pixels of the file.
func pixel_position() -> Vector2i:
	return Vector2i(position.round())


## Something the file would store changed: refresh warnings and the root's status line.
func _edited() -> void:
	if not is_inside_tree():
		return
	update_configuration_warnings()
	var editor := ScreenEditor.find_for(self)
	if editor != null:
		editor.queue_refresh()


## The properties of `AnimatedSprite2D` that must not be edited by hand: the node shows the picture of its data. Hiding
## them keeps the Inspector down to the numbers the original stores.
const HIDDEN: Array[StringName] = [&"sprite_frames", &"animation", &"autoplay", &"frame", &"frame_progress", &"speed_scale",
		&"centered", &"offset", &"flip_h", &"flip_v"]


func _validate_property(property: Dictionary) -> void:
	if property.name in HIDDEN:
		property.usage = PROPERTY_USAGE_NONE


## Rotation and scale are not part of the original's data: say so when somebody uses them.
func _common_warnings() -> PackedStringArray:
	var found := PackedStringArray()
	if rotation != 0.0 or scale != Vector2.ONE or skew != 0.0:
		found.append("Rotation, scale and skew are not stored: the original has none. Put them back to 0 / (1, 1).")
	if get_parent() == null or not (get_parent() is Node2D):
		found.append("This node must stand inside one of the screen's layers (a Node2D under the ScreenEditor).")
	return found
