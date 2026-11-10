@tool
class_name ZoneTable
extends Resource
## Container for the 7 ZoneData entries (a Resource file needs one root object).
##
## Teaches: which part of a table is the original's and which is this project's. Only the default educational levels
## are a record of the original (10 bytes in the program's data segment, `game * 5 + zone`); the titles, the picture
## counts and the banners are this project's own (the original has no zone titles, and the counts say how many
## pictures of an art bundle the port uses). `encode_default_edu_levels()` rebuilds the original's 10 bytes;
## tests/legacy/test_zone_fidelity.gd checks them against the hash in tests/fixtures/zones.json (docs/port/FIDELITY.md).

## Bytes of the original's table: Voyager zones 0-4, then Expert zones 0-4.
const DEFAULT_EDU_SIZE := 10
## Zones that have a row in the original's table (the finales use the last one's).
const ORIGINAL_ZONES := 5

@export var zones: Array[ZoneData] = []


## Everything that stops the default levels from being stored as the original's, in plain words; empty when they fit.
## `encode_default_edu_levels()` returns nothing while this is not empty.
func default_edu_problems() -> Array[String]:
	var found: Array[String] = []
	if zones.size() < ORIGINAL_ZONES:
		found.append("zones: %d, but the table needs the %d zones of the original" % [zones.size(), ORIGINAL_ZONES])
		return found
	for z in ORIGINAL_ZONES:
		if zones[z] == null:
			found.append("zone %d: empty" % z)
			continue
		for pair: Array in [["Voyager", zones[z].default_edu_level_voyager], ["Expert", zones[z].default_edu_level_expert]]:
			if pair[1] < 0 or pair[1] > 3:
				found.append("%s zone %d: educational level %d does not exist, the levels are 0 to 3" % [pair[0], z, pair[1]])
	return found


## The original's 10 bytes: the educational level of `game * 5 + zone` (Voyager zones 0-4, then Expert zones 0-4), or an
## empty array while `default_edu_problems()` finds problems. The finale entries (zones 5 and 6) have no row of their own.
func encode_default_edu_levels() -> PackedByteArray:
	if not default_edu_problems().is_empty():
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(DEFAULT_EDU_SIZE)
	for z in ORIGINAL_ZONES:
		out[z] = zones[z].default_edu_level_voyager
		out[ORIGINAL_ZONES + z] = zones[z].default_edu_level_expert
	return out


## The name of the entry that byte `offset` of the table belongs to, e.g. "Expert zone 3".
static func field_at(offset: int) -> String:
	if offset < 0 or offset >= DEFAULT_EDU_SIZE:
		return "outside the table"
	return "%s zone %d" % ["Voyager" if offset < ORIGINAL_ZONES else "Expert", offset % ORIGINAL_ZONES]


## "" when the two tables are the same, else "first difference at byte 7 (Expert zone 2): expected 0x03, got 0x02".
## Names the entry of the `expected` table.
static func first_difference(expected: PackedByteArray, actual: PackedByteArray) -> String:
	if actual.size() != expected.size():
		return "the table has %d bytes, expected %d" % [actual.size(), expected.size()]
	for i in expected.size():
		if expected[i] != actual[i]:
			return "first difference at byte %d (%s): expected %d, got %d" % [i, field_at(i), expected[i], actual[i]]
	return ""
