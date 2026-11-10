class_name TestFoeRecordFidelity
extends GdUnitTestSuite
## Teaches: a fixture of HASHES as the anchor for an encoder (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"), for
## the creatures' 34-byte records. tests/fixtures/foe_records.json holds, per sector, its provenance and per creature the
## offset of its record and the SHA-256 of the original 34 bytes, and no original bytes. `SectorData.encode_foe_records()`
## (each `FoeData.encode()`, with the entry points the compiled script gives) must hash to them for all 640 creatures of
## sectors 0-31, or the failure names the sector and the creature. The hashes are the anchor that does not come from your
## copy of the game: a different release or a patched copy is caught instead of being compared with itself.
##
## The original record BYTES are written by the importer into the git-ignored tests/fixtures/original/foe_records.json.
## The tests that need them (the byte-for-byte comparison that names the field, "the flags are 0 or 1", "the run-time
## state is zero") skip with a message when it is missing; the hash tests never need it.

const FIXTURE := "res://tests/fixtures/foe_records.json"
const ORIGINAL_BYTES := "res://tests/fixtures/original/foe_records.json"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"

## DELIBERATE CHANGES to a creature record of an original sector: "sector:creature" (e.g. "3:7") -> the reason.
## A designer who changes a creature of the original on purpose (its start, its damage, its frame) and wants to keep the
## change lists it here; the creature then skips only the comparison with the original (it must still be valid and
## encode). A sector listed in TestFoeAsmLegacy.DELIBERATE_SCRIPT_CHANGES skips the comparison for all its creatures: a changed
## script moves the entry points, and the entry points are bytes of the record. The project's convention is the
## "Deliberate deviation" in docs/port/FIDELITY.md. To go back to the original instead, run
## tools/import/import_all.py --only sectors (it also resets the scripts and the screens of every sector).
const DELIBERATE_FOE_CHANGES := {}


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _fixture() -> Array:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed["sectors"]


## The original record bytes of every sector (index -> Array of PackedByteArray), or an empty dictionary when the
## importer has not written them.
func _original_records() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(ORIGINAL_BYTES):
		return out
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_BYTES))
	for entry: Dictionary in parsed["sectors"]:
		var records := []
		for hex: String in entry["records_hex"]:
			records.append(hex.hex_decode())
		out[int(entry["index"])] = records
	return out


## True (after saying why) when the importer's raw file is missing, for the tests that need the original bytes.
func _skip_without_original_bytes() -> bool:
	if FileAccess.file_exists(ORIGINAL_BYTES):
		return false
	prints("SKIPPED: %s is missing; %s" % [ORIGINAL_BYTES, NEED_THE_IMPORTER])
	return true


func _is_deliberate(sector: int, creature: int) -> bool:
	return DELIBERATE_FOE_CHANGES.has("%d:%d" % [sector, creature]) or TestFoeAsmLegacy.DELIBERATE_SCRIPT_CHANGES.has(sector)


## A copy of an original creature that is safe to change (the loaded resources are shared and cached), with the entry
## points of the compiled script filled in.
func _copy_of(sector: int, creature: int) -> FoeData:
	Catalog.sector(sector).ensure_compiled()
	return Catalog.sector(sector).foes[creature].duplicate_deep() as FoeData


func test_the_fixture_covers_every_creature_with_its_provenance_and_holds_no_bytes() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_int(int(parsed["size"])).is_equal(FoeData.RECORD_SIZE)
	assert_array(parsed.keys()).contains_exactly_in_any_order(["comment", "size", "sectors"])
	var sectors: Array = parsed["sectors"]
	assert_int(sectors.size()).is_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	var total := 0
	for i in sectors.size():
		var entry: Dictionary = sectors[i]
		assert_int(int(entry["index"])).is_equal(i)
		assert_str(entry["source"]["file"]).is_equal("NEP.DLL")
		assert_str(entry["source"]["extracted"]).is_not_empty()
		assert_array(entry.keys()).contains_exactly_in_any_order(["index", "source", "foes"])
		var foes: Array = entry["foes"]
		assert_int(foes.size()).override_failure_message("sector %d" % i).is_equal(Catalog.sector(i).foes.size())
		for k in foes.size():
			assert_array((foes[k] as Dictionary).keys()).contains_exactly_in_any_order(["offset", "sha256"])
			assert_int(int(foes[k]["offset"])).is_equal(1 + FoeData.RECORD_SIZE * k)
			assert_int(String(foes[k]["sha256"]).length()).is_equal(64)
		# the script bytecode follows the records: its first byte is where the stored script text starts
		assert_int(Catalog.sector(i).foe_script_base).is_equal(1 + FoeData.RECORD_SIZE * foes.size())
		total += foes.size()
	assert_int(total).is_equal(640)


func test_every_creature_encodes_to_exactly_the_original_record() -> void:
	var problems: Array[String] = []
	var originals := _original_records()
	for sector_entry: Dictionary in _fixture():
		var s := int(sector_entry["index"])
		var sector := Catalog.sector(s)
		var messages := sector.foe_problems()
		if not messages.is_empty():
			problems.append("sector %d: the creatures do not fit the original's records: %s" % [s, messages[0]])
			continue
		var records := sector.encode_foe_records()
		for k in sector_entry["foes"].size():
			if _is_deliberate(s, k):
				continue
			if FixtureHash.sha256_hex(records[k]) == sector_entry["foes"][k]["sha256"]:
				continue
			var text := "sector %d creature %d differs from the original (edited on purpose? list it in DELIBERATE_FOE_CHANGES); %s to see which field" % [s, k, NEED_THE_IMPORTER]
			if originals.has(s):
				text = "sector %d creature %d differs from the original: %s (edited on purpose? list it in DELIBERATE_FOE_CHANGES)" % [s, k, FoeData.first_difference(originals[s][k], records[k])]
			problems.append(text)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_hash_helper_gives_the_known_sha256() -> void:
	assert_str(FixtureHash.sha256_hex("abc".to_utf8_buffer())).is_equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")


func test_a_record_has_34_bytes_and_the_entry_points_are_the_compiled_script() -> void:
	var sector := Catalog.sector(0)
	var records := sector.encode_foe_records()
	assert_int(records.size()).is_equal(21)
	for k in records.size():
		assert_int(records[k].size()).is_equal(FoeData.RECORD_SIZE)
		assert_int(records[k].decode_u16(0x10)).is_equal(sector.foes[k].pc)
		assert_int(records[k].decode_u16(0x0B)).is_equal(sector.foes[k].script_hit)
		assert_int(records[k].decode_u16(0x0D)).is_equal(sector.foes[k].script_ink)
	# creature 0 of sector 0: x 360 / 2 = 0xb4, y 222 / 2 = 0x6f, damage 1, pc 827
	assert_int(records[0].decode_u16(0x03)).is_equal(180)
	assert_int(records[0].decode_u16(0x05)).is_equal(111)
	assert_int(records[0][0x0F]).is_equal(1)
	assert_int(records[0].decode_u16(0x10)).is_equal(827)


# --- what the original bytes show (need the importer's raw file) -----------------------------------------------

func test_the_record_bytes_match_the_original_byte_for_byte() -> void:
	if _skip_without_original_bytes():
		return
	var originals := _original_records()
	assert_int(originals.size()).is_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var records := Catalog.sector(s).encode_foe_records()
		assert_int(records.size()).override_failure_message("sector %d" % s).is_equal(originals[s].size())
		for k in records.size():
			if _is_deliberate(s, k):
				continue
			assert_int((originals[s][k] as PackedByteArray).size()).is_equal(FoeData.RECORD_SIZE)
			assert_str(FoeData.first_difference(originals[s][k], records[k])).override_failure_message("sector %d creature %d" % [s, k]).is_empty()


func test_the_flags_are_zero_or_one_and_the_run_time_state_is_zero_in_all_640_originals() -> void:
	if _skip_without_original_bytes():
		return
	var count := 0
	var originals := _original_records()
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := Catalog.sector(s)
		for k in originals[s].size():
			var raw: PackedByteArray = originals[s][k]
			var where := "sector %d creature %d" % [s, k]
			for offset in [0, 1, 8]:
				assert_bool(raw[offset] <= 1).override_failure_message("%s: byte 0x%02x is %d" % [where, offset, raw[offset]]).is_true()
			assert_bool(raw.slice(FoeData.RUNTIME_STATE_AT) == PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])).override_failure_message(where).is_true()
			assert_bool(sector.foes[k].runtime_state.is_empty()).override_failure_message(where).is_true()
			count += 1
	assert_int(count).is_equal(640)


# --- a deliberately edited creature gives a readable message ---------------------------------------------------

func test_an_edited_field_is_named() -> void:
	var original := _copy_of(0, 2)
	var bytes := original.encode()
	var foe := _copy_of(0, 2)
	foe.pos.x += 2
	assert_str(FoeData.first_difference(bytes, foe.encode())).starts_with("first difference at byte 0x").contains("(x)")
	foe = _copy_of(0, 2)
	foe.pos.y += 4
	assert_str(FoeData.first_difference(bytes, foe.encode())).contains("(y)")
	foe = _copy_of(0, 2)
	foe.damage = -1
	assert_str(FoeData.first_difference(bytes, foe.encode())).contains("(damage): expected 0x01, got 0xff")
	foe = _copy_of(0, 2)
	foe.dormant = not foe.dormant
	assert_str(FoeData.first_difference(bytes, foe.encode())).contains("(dormant)")
	foe = _copy_of(0, 2)
	foe.script_ink += 1
	assert_str(FoeData.first_difference(bytes, foe.encode())).contains("(ink script)")
	foe = _copy_of(0, 2)
	foe.pc += 1
	assert_str(FoeData.first_difference(bytes, foe.encode())).contains("(start pc)")
	foe = _copy_of(0, 2)
	foe.runtime_state = PackedByteArray([0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_str(FoeData.first_difference(bytes, foe.encode())).contains("(run-time state byte 0x14)")


func test_the_names_of_the_fields_and_equal_records_have_no_difference() -> void:
	var expected := ["dormant", "hidden", "screen", "x", "x", "y", "y", "frame", "flip", "frame min", "frame max",
		"hit script", "hit script", "ink script", "ink script", "damage", "start pc", "start pc", "run-time state byte 0x12"]
	for offset in expected.size():
		assert_str(FoeData.field_at(offset)).override_failure_message("byte 0x%02x" % offset).is_equal(expected[offset])
	assert_str(FoeData.field_at(0x21)).is_equal("run-time state byte 0x21")
	var bytes := _copy_of(1, 1).encode()
	assert_str(FoeData.first_difference(bytes, bytes)).is_empty()
	assert_str(FoeData.first_difference(bytes, PackedByteArray())).contains("0 bytes")


func test_a_set_run_time_state_is_kept_in_the_record() -> void:
	var foe := _copy_of(0, 0)
	var state := PackedByteArray()
	state.resize(FoeData.RUNTIME_STATE_SIZE)
	state[3] = 9
	foe.runtime_state = state
	assert_array(foe.problems()).is_empty()
	var bytes := foe.encode()
	assert_int(bytes.size()).is_equal(FoeData.RECORD_SIZE)
	assert_int(bytes[FoeData.RUNTIME_STATE_AT + 3]).is_equal(9)
	assert_bool(bytes.slice(0, FoeData.RUNTIME_STATE_AT) == _copy_of(0, 0).encode().slice(0, FoeData.RUNTIME_STATE_AT)).is_true()


# --- what does not fit is refused, in words ---------------------------------------------------------------------

func test_an_original_sector_has_no_creature_problems() -> void:
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		assert_array(Catalog.sector(s).foe_problems()).override_failure_message("sector %d" % s).is_empty()


func test_positions_off_the_grid_or_out_of_range_are_refused() -> void:
	var foe := _copy_of(0, 0)
	foe.pos = Vector2i(361, -2)
	var text := "\n".join(foe.problems())
	assert_str(text).contains("x 361 is not on the grid: the original keeps x / 2, so it must be even")
	assert_str(text).contains("y -2 does not fit")
	foe.pos = Vector2i(2 * 0xFFFF + 2, 6)
	assert_str("\n".join(foe.problems())).contains("x 131072 does not fit")
	assert_int(foe.encode().size()).is_equal(0)


func test_values_out_of_byte_range_are_refused() -> void:
	var foe := _copy_of(0, 0)
	foe.screen = 256
	foe.frame = -1
	foe.frame_min = 300
	foe.frame_max = 256
	foe.damage = 128
	foe.pc = 70000
	foe.runtime_state = PackedByteArray([1, 2, 3])
	var text := "\n".join(foe.problems())
	assert_str(text).contains("screen 256 does not fit")
	assert_str(text).contains("frame -1 does not fit")
	assert_str(text).contains("frame_min 300 does not fit")
	assert_str(text).contains("frame_max 256 does not fit")
	assert_str(text).contains("damage 128 does not fit: the original keeps it in one signed byte, so -128 to 127")
	assert_str(text).contains("pc 70000 does not fit in two bytes")
	assert_str(text).contains("runtime_state: 3 bytes, but it is empty or 16")
	assert_int(foe.encode().size()).is_equal(0)
	foe.damage = -128
	assert_bool("\n".join(foe.problems()).contains("damage")).is_false()


func test_a_sector_names_the_creature_that_does_not_fit_and_stops_the_records() -> void:
	var sector := Catalog.sector(0).duplicate_deep() as SectorData
	sector.foes[4].damage = 300
	assert_str("\n".join(sector.foe_problems())).contains("creature 4: damage 300 does not fit")
	assert_int(sector.encode_foe_records().size()).is_equal(0)


func test_a_script_that_does_not_compile_stops_the_records() -> void:
	var sector := Catalog.sector(0).duplicate_deep() as SectorData
	sector.foes[1].hit_label = "no_such_label"
	assert_str("\n".join(sector.foe_problems())).contains("the creature script does not compile")
	assert_int(sector.encode_foe_records().size()).is_equal(0)
