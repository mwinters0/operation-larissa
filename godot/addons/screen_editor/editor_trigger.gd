@tool
class_name ScreenEditorTrigger
extends Node2D
## One math trigger (`MathTriggerData`): an invisible spot that starts a math problem when the sub touches it.
##
## Teaches: a `Node2D` that draws itself (`_draw`) because it has no picture, `queue_redraw`, and reusing a game table
## in the editor. The game decides whether a trigger fires with `TriggerModel.TABLE` (DESIGN 4.1): the sub's sprite cell and
## the trigger's `test_nibble` pick an entry that says whether the sub's x range and / or y range must contain the point.
## `fires_when` prints that table as words so you can see what a nibble does. Order matters: `DetectMathTrigger` takes the
## FIRST armed trigger of the list that fires, and at most one per game tick.

## Which problem to ask (0-62; `TriggerTable` maps the slot and the level to a problem type).
@export_range(0, 62) var slot: int = 0:
	set(value):
		slot = value
		_changed()
## The trigger starts out live (bit 7 of the flags byte).
@export var armed: bool = true:
	set(value):
		armed = value
		_changed()
## Live again every time the player enters the screen (bit 5).
@export var rearm_on_enter: bool = false:
	set(value):
		rearm_on_enter = value
		_changed()
## The low 4 bits of the flags byte: how the sub's position is tested (see `fires_when`).
@export_range(0, 15) var test_nibble: int = 0:
	set(value):
		test_nibble = value
		_changed()
## Bits 4 and 6 of the flags byte. Nobody knows what they do and no original trigger sets them.
@export_flags("Bit 4:16", "Bit 6:64") var other_bits: int = 0:
	set(value):
		other_bits = value
		_changed()
## What the nibble means, from `TriggerModel.TABLE` (read only).
@export var fires_when: String = "":
	get:
		return ScreenEditorTrigger.describe_nibble(test_nibble)
	set(_value):
		pass

## Position grid of the original: x / 4 and y / 2.
const GRID := Vector2i(4, 2)


func _init() -> void:
	set_notify_local_transform(true)


func _enter_tree() -> void:
	_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == &"fires_when":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_NO_INSTANCE_STATE


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		var snapped_position := ScreenEditorItem.snap(position, GRID)
		if snapped_position != position:
			position = snapped_position
		else:
			_changed()


func _changed() -> void:
	queue_redraw()
	if not is_inside_tree():
		return
	update_configuration_warnings()
	var editor := ScreenEditor.find_for(self)
	if editor != null:
		editor.queue_refresh()


func _draw() -> void:
	var color := Color(1, 0.8, 0.2) if armed else Color(0.6, 0.6, 0.6)
	draw_circle(Vector2.ZERO, 5.0, Color(color, 0.5))
	draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 16, color)
	draw_line(Vector2(-9, 0), Vector2(9, 0), color)
	draw_line(Vector2(0, -9), Vector2(0, 9), color)
	draw_string(ThemeDB.fallback_font, Vector2(8, -6), "slot %d" % slot, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


## One line per group of sprite cells with the same rule, from the game's own table.
static func describe_nibble(nibble: int) -> String:
	var groups: Dictionary = {}                      # rule text -> cells
	for cell in 9:
		var mode: int = TriggerModel.TABLE[cell * 16 + (nibble & 15)]
		var rule := "fires at once" if mode == 0 else "needs the sub's %s range to contain the point" % (
				"x and y" if mode == 3 else ("x" if mode == 2 else "y"))
		groups[rule] = groups.get(rule, "") + (", " if groups.has(rule) else "") + str(cell)
	var parts: Array[String] = []
	for rule: String in groups:
		parts.append("sub cell %s: %s" % [groups[rule], rule])
	return "; ".join(parts)


func to_record() -> MathTriggerData:
	var record := MathTriggerData.new()
	record.pos = Vector2i(position.round())
	record.slot = slot
	record.armed = armed
	record.rearm_on_enter = rearm_on_enter
	record.test_nibble = test_nibble
	record.other_bits = other_bits
	return record


static func from_record(record: MathTriggerData) -> ScreenEditorTrigger:
	var node := ScreenEditorTrigger.new()
	node.slot = record.slot
	node.armed = record.armed
	node.rearm_on_enter = record.rearm_on_enter
	node.test_nibble = record.test_nibble
	node.other_bits = record.other_bits
	node.position = Vector2(record.pos)
	return node


func _get_configuration_warnings() -> PackedStringArray:
	var found := PackedStringArray()
	for message in to_record().problems():
		found.append(message)
	if rotation != 0.0 or scale != Vector2.ONE:
		found.append("Rotation and scale are not stored.")
	return found
