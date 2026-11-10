@tool
class_name ProblemType
extends Resource
## Static description of one of the 34 math problem types: its title, its text
## templates, the original's stored problem records and how an answer is judged.
##
## Teaches: a data-driven Resource. The importer (tools/import/step_problems.py) copies
## the original game's data into one `problem_type_NN.tres` per type; nothing about the
## 34 types is hard-coded except how to word them (`ProblemTexts`).
##
## THE STORED RECORDS. The original does not generate problems, it stores them: each type
## has 4 tables (one per educational level) of fixed-size records, and picking a problem
## is `records[rand() % N]` (`ProblemFactory.make`). A record is a list of numbered fields
## (f0, f1 ...; DESIGN 5.4 says what each means for each type). To keep the .tres small
## every record is one flat `PackedInt64Array`; `ProblemRecord` decodes it.

@export var id: int = 0
@export var title: String = ""
## Every text of the type's bundle BY POSITION, as the original indexes them
## ("prompt = texts[0]", "hint = texts[L + 1]" ...). Positions the game never filled
## (levels where the type does not occur, missing worked solutions) are "".
## Templates contain `{k}` slots (see `TextTemplate`).
@export var texts: PackedStringArray = PackedStringArray()
## NEP.DLL text id of each position (0 where there is no text).
@export var text_ids: PackedInt32Array = PackedInt32Array()
## True if the on-screen calculator is offered (false for lock and ballast types).
@export var uses_calculator: bool = true
## Which of the 4 educational levels contain this type (index = level).
@export var levels_available: PackedInt32Array = PackedInt32Array()
## The bundle's own folder (res://), and the files in display order. Use `art_files`: a picture that the story, title or
## finale-creature code owns is kept once, in its own folder, and listed here with that path.
@export var art_dir: String = ""
@export var art_files: PackedStringArray = PackedStringArray()
## (`art_dir` and `art_files` are paths into a pack: how the data form of a pack writes them, `ResourceJson`.)
const JSON_PATH_FIELDS: Array[String] = ["art_dir", "art_files"]

## One character per stored field: 'c' u8, 'b' signed byte, 'w' u16, 'n' number
## (decimal or fraction, four ints in the flat record). See `ProblemRecord`.
@export var field_kinds: String = ""
## All stored records of all levels, flat-encoded.
@export var records: Array[PackedInt64Array] = []
## The educational level (0-3) each entry of `records` belongs to.
@export var record_levels: PackedInt32Array = PackedInt32Array()

## Field holding the expected answer, per level (-1: not a single stored value).
@export var answer_fields: PackedInt32Array = PackedInt32Array()
## "exact", "near" (relative tolerance), "close" (absolute tolerance), "range", "sum" or "wheel".
@export var compare_mode: String = "exact"
## Tolerance per level for "near" / "close" (0 means exact).
@export var tolerances: PackedFloat64Array = PackedFloat64Array()
## Levels at which the typed answer must be of the same KIND (fraction / decimal) as the stored one.
@export var kind_checked_levels: PackedInt32Array = PackedInt32Array()
## Side tables of a few types: lock wheel labels (0), ballast denominations (28, 29),
## the bound fields of the water-pressure range (4).
@export var extras: Dictionary = {}
## How the original draws this type's diagram (docs/data/problem_diagrams.json, DESIGN 5.5):
## `family` names the `DiagramBase` subclass (`DiagramFactory`), `items` is the list of pictures
## and numbers drawn onto the art (vocabulary in `DiagramBase`), plus a few family-specific keys.
@export var diagram: Dictionary = {}


## How many stored records exist for `level`.
func record_count(level: int) -> int:
	return record_levels.count(level)


## The `n`-th stored record of `level` (n in 0 .. record_count - 1), decoded.
func record(level: int, n: int) -> ProblemRecord:
	var seen := 0
	for i in record_levels.size():
		if record_levels[i] == level:
			if seen == n:
				return ProblemRecord.new(field_kinds, records[i])
			seen += 1
	return null


## Text at a bundle position, "" if the position does not exist or holds no text.
func text_at(position: int) -> String:
	if position < 0 or position >= texts.size():
		return ""
	return texts[position]


# --- the original's table bytes ----------------------------------------------------------------------------------
# Each level of a type is one resource of NEP.DLL: a count byte, that many records, zeros. The flat
# records keep every byte of it (even the ones the program never reads), so `encode_table()` gives the resource back;
# tests/legacy/test_problem_table_fidelity.gd checks the hashes against tests/fixtures/problem_tables.json (docs/port/FIDELITY.md).
# The layout of a number and of the flat form is in tools/import/problem_tables.py.

## The tables are padded with zeros to a multiple of this many bytes.
const TABLE_UNIT := 512
## Bytes of a number in the original's record (the CompactNumber).
const NUMBER_SIZE := 7
## Most records a table can hold (one count byte).
const MAX_RECORDS := 255


## Bytes of one field of `field_kinds` in the original's record: c 1, b 1, w 2, n 7.
static func field_size(kind: String) -> int:
	return {"c": 1, "b": 1, "w": 2, "n": NUMBER_SIZE}.get(kind, 0)


## Bytes of one record in the original's table.
func record_size() -> int:
	var total := 0
	for k in field_kinds:
		total += field_size(k)
	return total


## Ints of one flat record: one per field, four per number.
func flat_size() -> int:
	var total := 0
	for k in field_kinds:
		total += 4 if k == "n" else 1
	return total


## Bytes of a whole table of `count` records: the count byte and the records, up to a multiple of TABLE_UNIT.
func table_size(count: int) -> int:
	var used := 1 + count * record_size()
	return ((used + TABLE_UNIT - 1) / TABLE_UNIT) * TABLE_UNIT


## Everything that stops the records from being stored as the original's, in plain words; empty when they fit.
## `encode_table()` returns nothing while this is not empty.
func problems() -> Array[String]:
	var found: Array[String] = []
	for k in field_kinds:
		if field_size(k) == 0:
			found.append("field_kinds: '%s' is not a kind of field (c, b, w or n)" % k)
			return found
	if records.size() != record_levels.size():
		found.append("%d records but %d record levels: there must be one level per record" % [records.size(), record_levels.size()])
		return found
	for level in 4:
		if record_count(level) > MAX_RECORDS:
			found.append("level %d: %d records, but a table holds at most %d (one count byte)" % [level, record_count(level), MAX_RECORDS])
	for i in records.size():
		var where := "record %d (level %d)" % [i, record_levels[i]]
		if record_levels[i] < 0 or record_levels[i] > 3:
			found.append("%s: the educational levels are 0 to 3" % where)
		if records[i].size() != flat_size():
			found.append("%s: %d ints, but the fields \"%s\" take %d" % [where, records[i].size(), field_kinds, flat_size()])
			continue
		var at := 0
		for f in field_kinds.length():
			var kind := field_kinds[f]
			var name := "%s field f%d" % [where, f]
			if kind == "n":
				found.append_array(_number_problems(records[i], at, name))
				at += 4
				continue
			var limits: Array = {"c": [0, 255], "b": [-128, 127], "w": [0, 65535]}[kind]
			if records[i][at] < limits[0] or records[i][at] > limits[1]:
				found.append("%s: %d does not fit (%d to %d)" % [name, records[i][at], limits[0], limits[1]])
			at += 1
	return found


func _number_problems(flat: PackedInt64Array, at: int, name: String) -> Array[String]:
	var found: Array[String] = []
	var a := flat[at + 1]
	var b := flat[at + 2]
	var c := flat[at + 3]
	match flat[at]:
		0:
			if a < -2147483648 or a > 2147483647:
				found.append("%s: mantissa %d does not fit in 32 bits" % [name, a])
			if b < 0 or b > 255:
				found.append("%s: exponent %d does not fit (0 to 255)" % [name, b])
			if c != 0:
				found.append("%s: the fourth int of a decimal is 0, not %d" % [name, c])
		1:
			if a < -128 or a > 127 or b < -128 or b > 127:
				found.append("%s: whole part %d and numerator %d must each fit in a signed byte" % [name, a, b])
			if c < 0 or c > 256 * 65536 - 1:
				found.append("%s: denominator + 65536 * the unread byte is %d, but must be 0 to %d" % [name, c, 256 * 65536 - 1])
		2:
			if a < 2 or a > 65535 or b < 0 or b > 4294967295 or c < 0 or c > 255:
				found.append("%s: leftover bytes (%d, %d, %d) do not fit (a 16-bit kind of 2 or more, 32 bits, a byte)" % [name, a, b, c])
		_:
			found.append("%s: number kind %d does not exist (0 decimal, 1 fraction, 2 leftover bytes)" % [name, flat[at]])
	return found


## The original's table of educational level `level` (0-3): exactly `table_size()` bytes, or an empty array while
## `problems()` finds problems (or the level does not exist).
func encode_table(level: int) -> PackedByteArray:
	if level < 0 or level > 3 or not problems().is_empty():
		return PackedByteArray()
	var count := record_count(level)
	var out := PackedByteArray()
	out.resize(table_size(count))
	out[0] = count
	var pos := 1
	for i in records.size():
		if record_levels[i] != level:
			continue
		var flat := records[i]
		var at := 0
		for kind in field_kinds:
			match kind:
				"c":
					out.encode_u8(pos, flat[at])
				"b":
					out.encode_s8(pos, flat[at])
				"w":
					out.encode_u16(pos, flat[at])
				"n":
					_encode_number(out, pos, flat, at)
			pos += field_size(kind)
			at += 4 if kind == "n" else 1
	return out


static func _encode_number(out: PackedByteArray, pos: int, flat: PackedInt64Array, at: int) -> void:
	var a := flat[at + 1]
	var b := flat[at + 2]
	var c := flat[at + 3]
	match flat[at]:
		0:
			out.encode_u16(pos, 0)
			out.encode_u8(pos + 2, b)
			out.encode_s32(pos + 3, a)
		1:
			out.encode_u16(pos, 1)
			out.encode_s8(pos + 2, a)
			out.encode_s8(pos + 3, b)
			out.encode_u16(pos + 4, c & 0xFFFF)
			out.encode_u8(pos + 6, c >> 16)
		_:
			out.encode_u16(pos, a)
			out.encode_u32(pos + 2, b)
			out.encode_u8(pos + 6, c)


## The name of what byte `offset` of a table with these `kinds` belongs to, e.g. "record 3, field f2, byte 4 of the 7-byte
## number".
static func field_at(offset: int, kinds: String) -> String:
	if offset == 0:
		return "the record count"
	var size := 0
	for k in kinds:
		size += field_size(k)
	if size == 0:
		return "outside the records"
	var record := (offset - 1) / size
	var within := (offset - 1) % size
	var start := 0
	for f in kinds.length():
		var length := field_size(kinds[f])
		if within < start + length:
			var text := "record %d, field f%d" % [record, f]
			return text + (", byte %d of the 7-byte number" % (within - start)) if kinds[f] == "n" else text
		start += length
	return "outside the records"


## "" when the two tables are the same, else "first difference at byte 0x0e (record 0, field f2, byte 1 of the 7-byte
## number): expected 0x02, got 0x03". Names the byte of the `expected` table, whose records have the fields `kinds`. After
## the last record only the size and zeros are compared.
static func first_difference(expected: PackedByteArray, actual: PackedByteArray, kinds: String) -> String:
	if actual.size() != expected.size():
		return "the table has %d bytes, expected %d" % [actual.size(), expected.size()]
	var used := 1
	var size := 0
	for k in kinds:
		size += field_size(k)
	if not expected.is_empty():
		used += expected[0] * size
	for i in expected.size():
		if expected[i] != actual[i]:
			var what := field_at(i, kinds) if i < used else "padding after the records"
			return "first difference at byte 0x%02x (%s): expected 0x%02x, got 0x%02x" % [i, what, expected[i], actual[i]]
	return ""
