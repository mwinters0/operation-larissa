@tool
class_name ScreenEditorAnimDeco
extends ScreenEditorItem
## One animated decoration (`AnimDecoData`): a list of deco slots shown one after another, one per game tick.
##
## Teaches: the same node-from-record pattern as `ScreenEditorDeco`, with a list property (`PackedInt32Array`) that the
## Inspector edits as a little array. The editor shows the picture the game shows when the screen is entered: entry
## `start_cursor % frames.size()` of the list. (The game then steps through the list once per tick; the editor does not
## animate.) The yellow rectangle is `size`, the largest frame, as the original stores it.

## The deco slots in play order; they repeat, so "6 x picture A, 6 x picture B" makes a slow blink. The record has
## room for 16 of them.
@export var frames: PackedInt32Array = PackedInt32Array():
	set(value):
		frames = value
		show_picture()
		_edited()
## Where in the list the animation starts. Identical neighbours use different values so they do not move in step.
@export_range(0, 255) var start_cursor: int = 0:
	set(value):
		start_cursor = value
		show_picture()
		_edited()
## Size of the largest frame in pixels (stored as width / 4 and height / 2).
@export var size: Vector2i = Vector2i.ZERO:
	set(value):
		size = value
		queue_redraw()
		_edited()


func _init() -> void:
	super()
	grid = Vector2i(4, 2)


func show_picture() -> void:
	if sprite_frames == null:
		return
	var count := sprite_frames.get_frame_count(&"all")
	var shown := 0
	if not frames.is_empty():
		shown = frames[start_cursor % frames.size()]
	self_modulate = Color.WHITE if shown >= 0 and shown < count and not frames.is_empty() else Color(1, 1, 1, 0.0)
	frame = clampi(shown, 0, maxi(count - 1, 0))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(size)), Color(1, 0.9, 0.2, 0.8), false)


func to_record() -> AnimDecoData:
	var record := AnimDecoData.new()
	record.pos = pixel_position()
	record.frames = frames
	record.size = size
	record.start_cursor = start_cursor
	return record


static func from_record(record: AnimDecoData) -> ScreenEditorAnimDeco:
	var node := ScreenEditorAnimDeco.new()
	node.frames = record.frames
	node.start_cursor = record.start_cursor
	node.size = record.size
	node.position = Vector2(record.pos)
	return node


func _get_configuration_warnings() -> PackedStringArray:
	var found := _common_warnings()
	for message in to_record().problems():
		found.append(message)
	if frames.is_empty():
		found.append("An animated deco needs at least one frame.")
	return found
