@tool
class_name ScreenEditorDeco
extends ScreenEditorItem
## One decoration (`DecoPlacement`) on the screen: seaweed, rock, coral ...
##
## Teaches: `@export` on a `@tool` node (the Inspector edits it live), a property setter that redraws, and turning a node
## back into a data resource (`to_record`). The stored record is 3 bytes: x / 4, y / 2, and the slot with bit 7 as the
## "mirrored" flag (DESIGN 4.1). Which layer the node stands in (BackDecos, MidDecos, FrontDecos) says WHEN it is drawn;
## the ORDER of the nodes inside a layer is the order of the list in the record, and later entries are drawn over earlier ones.

## Picture number in the zone's deco set (0-69 are shared by all zones, 70 and up belong to the zone).
@export_range(0, 127) var slot: int = 0:
	set(value):
		slot = value
		show_picture()
		_edited()
## Draw the picture flipped left to right (bit 7 of the id byte).
@export var mirrored: bool = false:
	set(value):
		mirrored = value
		flip_h = value
		_edited()


func _init() -> void:
	super()
	grid = Vector2i(4, 2)


func show_picture() -> void:
	if sprite_frames == null:
		return
	var count := sprite_frames.get_frame_count(&"all")
	flip_h = mirrored
	self_modulate = Color.WHITE if slot < count else Color(1, 1, 1, 0.0)     # a slot without picture is blank
	frame = clampi(slot, 0, maxi(count - 1, 0))
	queue_redraw()


func _draw() -> void:
	if sprite_frames != null and slot >= sprite_frames.get_frame_count(&"all"):
		draw_rect(Rect2(Vector2.ZERO, Vector2(16, 16)), Color(1, 0.2, 0.2, 0.7), false)     # "no picture for this slot"


## The record this node stands for.
func to_record() -> DecoPlacement:
	var record := DecoPlacement.new()
	record.pos = pixel_position()
	record.slot = slot
	record.flag = mirrored
	return record


static func from_record(record: DecoPlacement) -> ScreenEditorDeco:
	var node := ScreenEditorDeco.new()
	node.slot = record.slot
	node.mirrored = record.flag
	node.position = Vector2(record.pos)
	return node


func _get_configuration_warnings() -> PackedStringArray:
	var found := _common_warnings()
	for message in to_record().problems():
		found.append(message)
	if sprite_frames != null and slot >= sprite_frames.get_frame_count(&"all"):
		found.append("This zone has no deco picture %d (it has %d); the game would draw nothing." % [slot, sprite_frames.get_frame_count(&"all")])
	return found
