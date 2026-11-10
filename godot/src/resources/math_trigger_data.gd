@tool
class_name MathTriggerData
extends Resource
## A spot on a screen that starts a math problem when the sub touches it.
##
## Teaches: one owner for every piece of information. The original stores the trigger's behaviour in ONE
## flags byte (DESIGN 4.1); this resource keeps exactly the parts as separate fields, and `flags` is
## computed from them, never stored. The fields are what the Inspector edits; `encode()` writes the record.
##
## The flags byte of the original: bit 7 armed, bit 5 re-arm on entering the screen, low nibble = how the
## sub's position is tested (`TriggerModel.TABLE`, DESIGN 4.1). Bits 6 and 4 never occur in the 90 original
## triggers; nobody knows what they would do, so they are kept in `other_bits` and written back unchanged.
## Whether a trigger has been used is NOT stored here: `SectorWorld` keeps that per run, and this resource
## only says how the trigger starts out.

## Size of one entry in the original screen record.
const RECORD_SIZE := 4
## The unknown bits of the flags byte (6 and 4), see `other_bits`.
const OTHER_BITS_MASK := 0x50
## Number of problem trigger slots (`TriggerTable`).
const SLOT_COUNT := 63

## Trigger point in WINDOW pixels (x*4, y*2 of the file; the playfield starts at (16, 32)).
@export var pos: Vector2i = Vector2i.ZERO
## Problem *trigger slot* (0-62). TriggerTable maps slot + level to a problem type.
@export var slot: int = 0
## Bit 7 of the flags byte: the trigger starts out live (the run clears it when it is used).
@export var armed: bool = true
## Bit 5: re-arm whenever the player enters the screen again.
@export var rearm_on_enter: bool = false
## The low nibble (bits 3-0) of the flags byte. Together with the sub's sprite cell it picks an entry of
## `TriggerModel.TABLE`, which says whether the sub's x range and / or y range must contain the trigger
## point (bit 1 = x, bit 0 = y; 0 = fires at once). The whole nibble matters, not just those two bits.
@export_range(0, 15) var test_nibble: int = 0
## Bits 6 and 4 of the flags byte (0x40 and 0x10), unknown meaning, zero in all original data.
@export_flags("Bit 4:16", "Bit 6:64") var other_bits: int = 0

## The original flags byte, computed from the fields above (read only).
var flags: int:
	get:
		return (0x80 if armed else 0) | (0x20 if rearm_on_enter else 0) | (other_bits & OTHER_BITS_MASK) | (test_nibble & 0x0F)


## The 4 bytes of the original record: x / 4, y / 2, trigger slot, flags.
## Only meaningful when `problems()` is empty.
func encode() -> PackedByteArray:
	return PackedByteArray([pos.x / 4, pos.y / 2, slot, flags])


## What keeps this trigger from being stored in the original format; empty when it fits.
func problems() -> Array[String]:
	var found: Array[String] = []
	found.append_array(ScreenData.position_problems(pos, "x", "y"))
	if slot < 0 or slot >= SLOT_COUNT:
		found.append("trigger slot %d does not exist: the problem table has slots 0 to %d" % [slot, SLOT_COUNT - 1])
	if test_nibble < 0 or test_nibble > 15:
		found.append("test_nibble %d does not fit in 4 bits (0 to 15)" % test_nibble)
	if other_bits & ~OTHER_BITS_MASK != 0:
		found.append("other_bits 0x%02x: only bits 4 and 6 (0x10 and 0x40) are free in the flags byte" % other_bits)
	return found
