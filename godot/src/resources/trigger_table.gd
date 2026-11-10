@tool
class_name TriggerTable
extends Resource
## Maps (trigger slot, educational level, pick) to a math problem type.
##
## Teaches: flattening a 3-D table into one PackedByteArray plus an index function, and how the way back to the original's
## bytes is the same flat array (`encode()`; tests/legacy/test_trigger_table_fidelity.gd checks its hash against
## tests/fixtures/trigger_table.json, docs/port/FIDELITY.md).

const SLOTS := 63
const LEVELS := 4
const PICKS := 2
## The original's table: SLOTS * LEVELS * PICKS bytes.
const SIZE := SLOTS * LEVELS * PICKS

## SLOTS * LEVELS * PICKS bytes, laid out [slot][level][pick].
@export var table: PackedByteArray = PackedByteArray()

## Problem type (0-33) for a trigger slot at `level` (0-3); `pick` is 0 or 1
## (the original chooses randomly between the two candidates).
func type_for(slot: int, level: int, pick: int) -> int:
	return table[(slot * LEVELS + level) * PICKS + pick]


## Everything that stops the table from being stored as the original's, in plain words; empty when it fits.
## `encode()` returns nothing while this is not empty.
func problems() -> Array[String]:
	var found: Array[String] = []
	if table.size() != SIZE:
		found.append("table: %d bytes, but the original has %d (%d slots x %d levels x %d picks)" % [table.size(), SIZE, SLOTS, LEVELS, PICKS])
	return found


## The original's table: exactly SIZE bytes (one byte per problem type), or an empty array while `problems()` finds problems.
func encode() -> PackedByteArray:
	if not problems().is_empty():
		return PackedByteArray()
	return table.duplicate()


## The name of the entry that byte `offset` belongs to, e.g. "slot 12, educational level 2, pick 1".
static func field_at(offset: int) -> String:
	if offset < 0 or offset >= SIZE:
		return "outside the table"
	return "slot %d, educational level %d, pick %d" % [offset / (LEVELS * PICKS), (offset / PICKS) % LEVELS, offset % PICKS]


## "" when the two tables are the same, else "first difference at byte 0x19 (slot 3, educational level 0, pick 1): expected
## 0x15, got 0x16". Names the entry of the `expected` table.
static func first_difference(expected: PackedByteArray, actual: PackedByteArray) -> String:
	if actual.size() != expected.size():
		return "the table has %d bytes, expected %d" % [actual.size(), expected.size()]
	for i in expected.size():
		if expected[i] != actual[i]:
			return "first difference at byte 0x%02x (%s): expected 0x%02x, got 0x%02x" % [i, field_at(i), expected[i], actual[i]]
	return ""
