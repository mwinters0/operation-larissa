@tool
class_name ScreenData
extends Resource
## Everything on one of the 12 screens of a sector, and how to write it back as the original's record.
##
## Teaches: nested typed Resources (arrays of other Resources), one file per screen (the sector lists them as
## external resources), and an encoder with validation: `encode()` rebuilds the original 0x500-byte screen
## record from the editable fields, `validate()` explains in plain words what does not fit in it. The fidelity
## test (tests/legacy/test_screen_fidelity.gd) compares `encode()` of all 384 original screens with the original bytes.
##
## `@tool` (here and on the other classes the screen editor loads: DecoPlacement, AnimDecoData, MathTriggerData, PieceData,
## SectorData, ZoneData, ZoneTable, TileCodec): inside the Godot editor a script WITHOUT it is only a placeholder that keeps
## the exported values; its methods (`encode`, `validate` ...) do not run there. The game ignores the keyword.
##
## THE RECORD (DESIGN 4.1; a screen is at offset 0x72 + k * 0x500 of its sector's data, `original_offset`):
##   0x000  38 x 18 tile bytes (row-major), 684 bytes = 0x2AC
##   0x2AC  five lists, each a count byte and then that many entries (`LAYOUT`, the one table that says it all)
##          bg decos / mid decos / fg decos   3 bytes   x/4, y/2, slot | 0x80 if mirrored
##          anim decos                        22 bytes  see AnimDecoData
##          math triggers                     4 bytes   x/4, y/2, trigger slot, flags (see MathTriggerData)
##   then   up to 0x500 not used by the game. In 377 of the 384 original records that is all zero. The other
##          seven keep leftover bytes of an earlier, longer version of the lists (DESIGN 4.1); they are stored
##          in `stale_bytes` at `stale_offset` so that the record can be rebuilt exactly. A screen that grows
##          over them simply overwrites them, as it would in the original.
## The limits are the original's: a list holds at most 255 entries and the whole record 0x500 = 1280 bytes
## (the biggest original record uses 1164). They are explained, not lifted.

## Size of the whole record.
const RECORD_SIZE := 0x500
const TILE_COLUMNS := 38
const TILE_ROWS := 18
## Number of tile bytes = offset of the first list (0x2AC).
const TILE_BYTES := TILE_COLUMNS * TILE_ROWS
## Where a sector's data keeps screen 0 (a 0x72-byte header comes first) and how far apart the records are.
const FIRST_RECORD_OFFSET := 0x72

## The layout of the lists in the record, in order: ONE table used by `encode`, `validate` and `field_at`
## (the "first difference at byte ..." message). `size` = bytes per entry, `fields` = names of the first
## bytes of an entry, `rest` = name for the bytes after those (anim decos: the frame list).
const LAYOUT: Array[Dictionary] = [
	{"name": "bg decos", "size": 3, "fields": ["x", "y", "slot and mirror flag"], "rest": ""},
	{"name": "mid decos", "size": 3, "fields": ["x", "y", "slot and mirror flag"], "rest": ""},
	{"name": "fg decos", "size": 3, "fields": ["x", "y", "slot and mirror flag"], "rest": ""},
	{"name": "anim decos", "size": 22, "fields": ["x", "y", "width", "height", "start cursor"], "rest": "frame list byte %d"},
	{"name": "math triggers", "size": 4, "fields": ["x", "y", "slot", "flags"], "rest": ""},
]

## Provenance: which original sector and screen this one was made from by the importer
## (tools/import/step_sectors.py), -1 for a screen that does not come from the original. A tool that has the
## original game files can read the screen's original record back from them (`original_offset`).
@export var original_sector: int = -1
@export var original_screen: int = -1

## 38 x 18 tile bytes, row-major (index = row * 38 + column). See DESIGN 4.1:
## 0x40 = solid (low 6 bits pick the picture), 0x80 = water current, 0 = empty.
@export var tiles: PackedByteArray = PackedByteArray()
## Decorations drawn behind the tiles / between tiles and sub / in front of the sub.
@export var bg_decos: Array[DecoPlacement] = []
@export var mid_decos: Array[DecoPlacement] = []
@export var fg_decos: Array[DecoPlacement] = []
@export var anim_decos: Array[AnimDecoData] = []
@export var triggers: Array[MathTriggerData] = []
## Leftover bytes in the unused part of the original record (see the header), starting at record offset
## `stale_offset`. Empty for 377 of the 384 original screens. Not something to edit.
@export var stale_offset: int = 0
@export var stale_bytes: PackedByteArray = PackedByteArray()


## Offset of an original screen's record inside its sector's data.
static func original_offset(screen: int) -> int:
	return FIRST_RECORD_OFFSET + screen * RECORD_SIZE


## The entries of list number `list` of `LAYOUT` (0 bg decos .. 4 math triggers) as resources.
func _list(list: int) -> Array:
	match list:
		0:
			return bg_decos
		1:
			return mid_decos
		2:
			return fg_decos
		3:
			return anim_decos
		_:
			return triggers


## Bytes the used part of the record takes (tiles, five count bytes and all entries). At most RECORD_SIZE.
func used_bytes() -> int:
	var total := TILE_BYTES
	for i in LAYOUT.size():
		total += 1 + _list(i).size() * int(LAYOUT[i].size)
	return total


## Everything that stops this screen from being stored as an original record, in plain words; empty when it
## fits. `encode()` returns nothing while this is not empty.
func validate() -> Array[String]:
	var found: Array[String] = []
	if tiles.size() != TILE_BYTES:
		found.append("tiles: %d bytes, but a screen is %d x %d = %d tile bytes" % [tiles.size(), TILE_COLUMNS, TILE_ROWS, TILE_BYTES])
	else:
		var odd := 0
		for i in TILE_BYTES:
			if not TileCodec.is_canonical(tiles[i]):
				odd += 1
				if odd <= 3:
					found.append("tile row %d column %d: byte 0x%02x is not one of the original's tile bytes (0, 0x40-0x7f wall, 0x80-0xbf current)" % [i / TILE_COLUMNS, i % TILE_COLUMNS, tiles[i]])
		if odd > 3:
			found.append("... and %d more tile bytes like that" % (odd - 3))
	for i in LAYOUT.size():
		var name: String = LAYOUT[i].name
		var entries := _list(i)
		if entries.size() > 255:
			found.append("%s: %d entries, but the count is one byte, so 255 is the most" % [name, entries.size()])
		for e in entries.size():
			if entries[e] == null:
				found.append("%s entry %d: empty" % [name, e])
				continue
			for message in entries[e].problems():
				found.append("%s entry %d: %s" % [name, e, message])
	var used := used_bytes()
	if used > RECORD_SIZE:
		found.append("the screen needs %d bytes but a record holds %d (0x%x): %d too many; an anim deco takes 22, a trigger 4, a deco 3" % [used, RECORD_SIZE, RECORD_SIZE, used - RECORD_SIZE])
	if not stale_bytes.is_empty() and (stale_offset < TILE_BYTES or stale_offset + stale_bytes.size() > RECORD_SIZE):
		found.append("stale_bytes do not fit in the record at offset 0x%x" % stale_offset)
	return found


## The original record for this screen: exactly RECORD_SIZE bytes, or an empty array while `validate()` finds
## problems. The unused part is zero, except the `stale_bytes`, which the lists overwrite if they grew over them.
func encode() -> PackedByteArray:
	if not validate().is_empty():
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(RECORD_SIZE)
	for i in stale_bytes.size():
		out[stale_offset + i] = stale_bytes[i]
	for i in TILE_BYTES:
		out[i] = tiles[i]
	var p := TILE_BYTES
	for i in LAYOUT.size():
		var entries := _list(i)
		out[p] = entries.size()
		p += 1
		for entry in entries:
			var bytes: PackedByteArray = entry.encode()
			for b in bytes.size():
				out[p + b] = bytes[b]
			p += bytes.size()
	return out


## Messages for one pixel position stored as x / 4 and y / 2 in single bytes (decos, anim decos, triggers).
## `x_name` / `y_name` name the two numbers in the message.
static func position_problems(pos: Vector2i, x_name: String, y_name: String) -> Array[String]:
	var found: Array[String] = []
	if pos.x < 0 or pos.x > 1020:
		found.append("%s %d does not fit: the original keeps %s / 4 in one byte, so 0 to 1020" % [x_name, pos.x, x_name])
	elif pos.x % 4 != 0:
		found.append("%s %d is not on the grid: the original keeps %s / 4, so it must be a multiple of 4" % [x_name, pos.x, x_name])
	if pos.y < 0 or pos.y > 510:
		found.append("%s %d does not fit: the original keeps %s / 2 in one byte, so 0 to 510" % [y_name, pos.y, y_name])
	elif pos.y % 2 != 0:
		found.append("%s %d is not on the grid: the original keeps %s / 2, so it must be a multiple of 2" % [y_name, pos.y, y_name])
	return found


## The name of the field that byte `offset` of `record` belongs to, e.g. "mid decos entry 3 y" or
## "tile row 4 column 17". The counts in `record` tell where the lists are, so it works on any record.
static func field_at(record: PackedByteArray, offset: int) -> String:
	if offset < TILE_BYTES:
		return "tile row %d column %d" % [offset / TILE_COLUMNS, offset % TILE_COLUMNS]
	var p := TILE_BYTES
	for section in LAYOUT:
		if p >= record.size():
			break
		if offset == p:
			return "%s count" % section.name
		var size: int = section.size
		var end := p + 1 + record[p] * size
		if offset < end:
			var within := (offset - p - 1) % size
			var names: Array = section.fields
			var field: String = names[within] if within < names.size() else (section.rest as String) % (within - names.size())
			return "%s entry %d %s" % [section.name, (offset - p - 1) / size, field]
		p = end
	return "unused bytes after the lists"


## "" when the two records are the same, else "first difference at byte 0x1a3 (mid decos entry 3 y): expected
## 0x40, got 0x42". Names the field using the `expected` record's layout.
static func first_difference(expected: PackedByteArray, actual: PackedByteArray) -> String:
	if actual.size() != expected.size():
		return "the record has %d bytes, expected %d" % [actual.size(), expected.size()]
	for i in expected.size():
		if expected[i] != actual[i]:
			return "first difference at byte 0x%03x (%s): expected 0x%02x, got 0x%02x" % [i, field_at(expected, i), expected[i], actual[i]]
	return ""
