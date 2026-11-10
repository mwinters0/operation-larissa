class_name TriggerModel
extends RefCounted
## An invisible spot on a screen that starts a math problem when the sub reaches it, as the rules see it. No nodes.
##
## Teaches: a rule that is a lookup table, and why the "armed" state lives in an object that outlives the screen: the node that
## marks the trigger on the screen (`MathTrigger`) is thrown away whenever the screen changes, and the shared `SectorData` must
## never be modified, so `SimWorld` makes one of these for every trigger of the sector when the sector loads and each remembers
## whether it is live. Like the pieces, the original decides with a lookup table and integer compares (`DetectMathTrigger`
## 0x427744, see `fires`), not with physics.

## `MathTriggerTable` (0x442994), dumped from ONWIN32.EXE: 9 sprite cells x 16 flag nibbles. Index
## `cell * 16 + (flags & 15)`. Bit 1 (2) = the sub's x range must contain the trigger's x, bit 0 (1) = the
## sub's y range must contain its y; 0 = that axis is not tested (a trigger whose entry is 0 fires as soon as
## it is armed, wherever the sub is on the screen).
const TABLE: PackedByteArray = [
	0, 1, 0, 1, 0, 0, 0, 0, 2, 3, 0, 3, 2, 3, 0, 3,   # cell 0
	0, 0, 1, 1, 0, 0, 0, 0, 2, 0, 3, 3, 2, 0, 3, 3,   # cell 1
	0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 3, 2, 0, 0, 3,   # cell 2
	0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 3, 2, 0, 0, 3,   # cell 3
	0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 3,   # cell 4
	0, 0, 0, 0, 2, 0, 0, 3, 0, 0, 0, 0, 2, 0, 0, 3,   # cell 5
	0, 0, 0, 0, 2, 0, 0, 3, 0, 0, 0, 0, 2, 0, 0, 3,   # cell 6
	0, 0, 1, 1, 2, 0, 3, 3, 0, 0, 0, 0, 2, 0, 3, 3,   # cell 7
	0, 1, 0, 1, 2, 3, 0, 3, 0, 0, 0, 0, 2, 3, 0, 3,   # cell 8
]
## The sub's picture box: SubX .. SubX + 95, SubY .. SubY + 57 (inclusive).
const SUB_BOX_LAST := Vector2i(95, 57)

var data: MathTriggerData
## The screen the trigger is on, and its position in that screen's list (together they identify it).
var screen: int = 0
var index: int = 0
## Is it live? Cleared when it fires; set again at the start of a sector and, for the "re-arm on enter" ones, at every entry.
var armed: bool = true


func _init(trigger_data: MathTriggerData = null, screen_index: int = 0, trigger_index: int = 0) -> void:
	data = trigger_data
	screen = screen_index
	index = trigger_index
	if trigger_data != null:
		armed = trigger_data.armed


## `DetectMathTrigger` (0x427744), the fire rule for ONE armed trigger: `sub_pos` = SubX / SubY (window pixels, the picture's
## top-left corner), `cell` = SubCell (0-8, the sub's current sprite cell, already updated for this tick), `point` = the trigger
## point (x * 4, y * 2 of the file, window pixels), `flags` = byte 3 of the record (only the low nibble is used here). Look up
## `TABLE[cell * 16 + (flags & 15)]`: if bit 1 is set the point's x must be in [SubX, SubX + 95]; if bit 0 is set its y must be
## in [SubY, SubY + 57]; an axis whose bit is clear is not tested. Fires if every tested axis passes (an entry of 0 always
## fires). The armed bit (7) is checked by the caller.
static func fires(flags: int, cell: int, sub_pos: Vector2i, point: Vector2i) -> bool:
	var mode := TABLE[cell * 16 + (flags & 15)]
	if mode & 2 != 0 and (point.x < sub_pos.x or point.x > sub_pos.x + SUB_BOX_LAST.x):
		return false
	if mode & 1 != 0 and (point.y < sub_pos.y or point.y > sub_pos.y + SUB_BOX_LAST.y):
		return false
	return true


## Does the sub at `sub_pos` in `cell` fire this trigger (armed or not)?
func fires_for(sub_pos: Vector2i, cell: int) -> bool:
	return fires(data.flags, cell, sub_pos, data.pos)
