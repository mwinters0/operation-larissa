class_name TestProblemTableFidelity
extends GdUnitTestSuite
## Teaches: a fixture of HASHES as the anchor for an encoder (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"), for
## the stored problems. tests/fixtures/problem_tables.json holds, for each of the 34 problem types and 4 educational
## levels, the provenance (the NEP.DLL resource 10512 + 4 * type + level) and the SHA-256 of the whole original table
## (a count byte, the records, zeros up to a multiple of 512 bytes), and no original bytes. `ProblemType.encode_table()`
## turns the flat records of `problem_type_NN.tres` back into that table, 7-byte numbers included, and must hash to it, or
## the failure names the table and the first byte that differs. The hashes are the anchor that does not come from your copy
## of the game: a different release or a patched copy is caught instead of being compared with itself.
##
## The original table BYTES are written by the importer into the git-ignored tests/fixtures/original/problem_tables.json.
## The tests that need them (the byte-for-byte comparison that names the field, the zero padding) skip with a message when
## it is missing; the hash tests never need it.

const FIXTURE := "res://tests/fixtures/problem_tables.json"
const ORIGINAL_BYTES := "res://tests/fixtures/original/problem_tables.json"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"

## DELIBERATE CHANGES to the stored problems of an original type: type number -> the reason. A designer who changes or adds
## a stored problem on purpose and wants to keep the change lists the type here; it then skips only the comparison with the
## original (it must still be valid and encode). The project's convention is the "Deliberate deviation" in
## docs/port/FIDELITY.md. To go back to the original instead, run tools/import/reset_tables.py problems.
const DELIBERATE_TYPE_CHANGES := {}


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _fixture() -> Array:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed["tables"]


## The original table bytes (type * 4 + level -> bytes), or an empty dictionary when the importer has not written them.
func _original_tables() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(ORIGINAL_BYTES):
		return out
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_BYTES))
	for entry: Dictionary in parsed["tables"]:
		out[int(entry["type"]) * 4 + int(entry["level"])] = String(entry["hex"]).hex_decode()
	return out


func _type(type_id: int) -> ProblemType:
	return Catalog.problem_type(type_id)


func _copy_of(type_id: int) -> ProblemType:
	return _type(type_id).duplicate_deep() as ProblemType


func test_the_fixture_covers_the_136_tables_with_their_provenance_and_holds_no_bytes() -> void:
	var tables := _fixture()
	assert_int(tables.size()).is_equal(136)
	for i in tables.size():
		var entry: Dictionary = tables[i]
		assert_array(entry.keys()).contains_exactly_in_any_order(["type", "level", "source", "offset", "size", "sha256"])
		assert_int(int(entry["type"]) * 4 + int(entry["level"])).is_equal(i)
		assert_str(entry["source"]["file"]).is_equal("NEP.DLL")
		assert_int(int(entry["source"]["real_id"])).is_equal(10512 + i)
		assert_str(entry["source"]["extracted"]).is_equal("data/NEP_raw/NEP_%d.bin" % (10512 + i))
		assert_int(int(entry["offset"])).is_equal(0)
		assert_int(int(entry["size"]) % ProblemType.TABLE_UNIT).is_equal(0)
		assert_int(String(entry["sha256"]).length()).is_equal(64)


## This also proves the zero padding and every byte the program never reads (the byte after a fraction's denominator, the
## five bytes of a number's authoring leftovers): the importer hashes the resource as NEP.DLL holds it.
func test_every_table_encodes_to_the_hash_of_the_original() -> void:
	var problems: Array[String] = []
	var originals := _original_tables()
	for entry: Dictionary in _fixture():
		var type_id: int = entry["type"]
		var level: int = entry["level"]
		if DELIBERATE_TYPE_CHANGES.has(type_id):
			continue
		var type := _type(type_id)
		var messages := type.problems()
		if not messages.is_empty():
			problems.append("type %d: does not fit the original's tables: %s" % [type_id, messages[0]])
			continue
		var bytes := type.encode_table(level)
		if FixtureHash.sha256_hex(bytes) == entry["sha256"] and bytes.size() == int(entry["size"]):
			continue
		var text := "type %d level %d differs from the original (edited on purpose? list the type in DELIBERATE_TYPE_CHANGES); %s to see which byte" % [type_id, level, NEED_THE_IMPORTER]
		if originals.has(type_id * 4 + level):
			text = "type %d level %d: %s (edited on purpose? list the type in DELIBERATE_TYPE_CHANGES)" % [type_id, level, ProblemType.first_difference(originals[type_id * 4 + level], bytes, type.field_kinds)]
		problems.append(text)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_levels_a_type_offers_are_the_tables_with_records() -> void:
	for type_id in 34:
		var type := _type(type_id)
		for level in 4:
			assert_int(type.levels_available[level]).override_failure_message("type %d level %d" % [type_id, level]).is_equal(1 if type.record_count(level) > 0 else 0)


# --- what the original bytes show (need the importer's raw file) ------------------------------------------------

func test_the_tables_match_the_original_byte_for_byte_and_only_zeros_follow_the_records() -> void:
	if not FileAccess.file_exists(ORIGINAL_BYTES):
		prints("SKIPPED: %s is missing; %s" % [ORIGINAL_BYTES, NEED_THE_IMPORTER])
		return
	var originals := _original_tables()
	assert_int(originals.size()).is_equal(136)
	for key: int in originals:
		var type_id := key / 4
		if DELIBERATE_TYPE_CHANGES.has(type_id):
			continue
		var type := _type(type_id)
		var original: PackedByteArray = originals[key]
		assert_str(ProblemType.first_difference(original, type.encode_table(key % 4), type.field_kinds)).override_failure_message("type %d level %d" % [type_id, key % 4]).is_empty()
		for i in range(1 + original[0] * type.record_size(), original.size()):
			assert_int(original[i]).override_failure_message("type %d level %d byte %d" % [type_id, key % 4, i]).is_equal(0)


func test_the_numbers_that_hold_leftover_bytes_are_kept() -> void:
	# Type 6, level 1, field f0 of the first record is 1/2 followed by the byte 0xb0 that the program never reads; type 3
	# level 0 holds numbers that are not numbers at all (the 16-bit kind 0xc4c4). Both are in the flat form.
	var six := _type(6)
	assert_int(six.records[six.record_levels.find(1)][3]).is_equal(2 + 65536 * 0xb0)
	var three := _type(3)
	assert_int(three.records[0][6]).is_equal(2)               # leftover bytes: f3 of the first record starts at the seventh int
	assert_int(three.records[0][7]).is_equal(0xc4c4)
	assert_float(ProblemRecord.new(six.field_kinds, six.records[six.record_levels.find(1)]).value_at(0)).is_equal(0.5)
	assert_float(ProblemRecord.new(three.field_kinds, three.records[0]).value_at(3)).is_equal(0.0)


# --- a deliberately edited table gives a readable message --------------------------------------------------------

func test_an_edited_field_is_named() -> void:
	var type := _copy_of(1)
	var original := type.encode_table(1)
	type.records[type.record_levels.find(1) + 2][9] += 1                 # record 2, field f2 (a number: kind, a, b, c): a
	assert_str(ProblemType.first_difference(original, type.encode_table(1), type.field_kinds)).starts_with("first difference at byte 0x").contains("(record 2, field f2, byte ")
	assert_str(ProblemType.first_difference(original, original, type.field_kinds)).is_empty()
	assert_str(ProblemType.first_difference(original, PackedByteArray(), type.field_kinds)).contains("0 bytes")
	var more := _copy_of(30)
	var plain := more.encode_table(0)
	more.records[0][3] = (more.records[0][3] + 1) % 256
	assert_str(ProblemType.first_difference(plain, more.encode_table(0), more.field_kinds)).contains("(record 0, field f3)")


func test_a_record_added_changes_the_count_and_the_size_rule_holds() -> void:
	var type := _copy_of(25)
	var original := type.encode_table(0)
	type.records.append(type.records[0].duplicate())
	type.record_levels.append(0)
	var longer := type.encode_table(0)
	assert_int(longer[0]).is_equal(original[0] + 1)
	assert_str(ProblemType.first_difference(original, longer, type.field_kinds)).is_not_empty()
	assert_int(type.table_size(0)).is_equal(512)
	assert_int(type.table_size(27)).is_equal(1024)                      # 1 + 27 * 19 = 514 bytes
	assert_int(_type(5).table_size(10)).is_equal(1024)


# --- what does not fit is refused, in words ---------------------------------------------------------------------

func test_an_original_type_has_no_problems() -> void:
	for type_id in 34:
		assert_array(_type(type_id).problems()).override_failure_message("type %d" % type_id).is_empty()


func test_values_that_do_not_fit_are_refused() -> void:
	var type := _copy_of(2)                                             # cccccccn
	type.records[0][0] = 256
	type.records[0][7] = 5                                              # a number of kind 5
	var text := "\n".join(type.problems())
	assert_str(text).contains("record 0 (level 1) field f0: 256 does not fit (0 to 255)")
	assert_str(text).contains("number kind 5 does not exist")
	assert_int(type.encode_table(1).size()).is_equal(0)
	type = _copy_of(2)
	type.records[1] = PackedInt64Array([1, 2, 3])
	assert_str("\n".join(type.problems())).contains("record 1 (level 1): 3 ints, but the fields \"cccccccn\" take 11")
	type = _copy_of(2)
	type.records[0] = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0, 200, 300, 0])      # a decimal: the mantissa is fine, the exponent is not
	assert_str("\n".join(type.problems())).contains("exponent 300 does not fit")
	type = _copy_of(2)
	type.record_levels.resize(type.record_levels.size() - 1)
	assert_str("\n".join(type.problems())).contains("there must be one level per record")


func test_a_table_holds_at_most_255_records() -> void:
	var type := _copy_of(12)
	for i in 300:
		type.records.append(PackedInt64Array([1, 2, 3]))
		type.record_levels.append(1)
	assert_str("\n".join(type.problems())).contains("level 1: 300 records, but a table holds at most 255")
