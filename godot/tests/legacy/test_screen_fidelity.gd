class_name TestScreenFidelity
extends GdUnitTestSuite
## Teaches: a fixture of HASHES as the anchor for an encoder (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes").
## tests/fixtures/screens.json holds, per screen of sectors 0-31, its provenance and the SHA-256 of the original 0x500-byte
## record, and no original bytes; `ScreenData.encode()` must hash to it for every stored screen, or the failure names the
## sector and the screen. The hashes are the anchor that does not come from your copy of the game: a different release or a
## patched copy is caught instead of being compared with itself. The record BYTES are written by the importer into the
## git-ignored tests/fixtures/original/screens.json; with them the failure also names the field of the first differing byte,
## and the one test that compares every record with its bytes (they are hash-checked first) runs; without them it skips.
## Also: provenance fields, validation messages, and the ownership of the redundant fields (trigger flags, anim deco records).

const FIXTURE := "res://tests/fixtures/screens.json"
const ORIGINAL_BYTES := "res://tests/fixtures/original/screens.json"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"

## DELIBERATE CHANGES to the screens of an original sector: "sector:screen" (e.g. "3:7") -> the reason.
## A designer who changes a screen of the original on purpose and wants to keep the change lists it here; the
## screen then skips only the comparison with the original bytes (it must still be valid and encode). The
## project's convention is the "Deliberate deviation" in docs/port/FIDELITY.md.
## To go back to the original instead, run tools/import/reset_screens.py.
const DELIBERATE_SCREEN_CHANGES := {}


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _fixture() -> Array:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed["sectors"]


## The original record bytes by "sector:screen", or an empty dictionary when the importer has not written them.
func _original_records() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(ORIGINAL_BYTES):
		return out
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_BYTES))
	for sector_entry: Dictionary in parsed["sectors"]:
		for entry: Dictionary in sector_entry["screens"]:
			var record := String(entry["record_hex"]).hex_decode()      # the hex is cut after the last non-zero byte, the rest is zero
			record.resize(ScreenData.RECORD_SIZE)
			out["%d:%d" % [int(sector_entry["index"]), int(entry["screen"])]] = record
	return out


func test_the_fixture_covers_every_screen_with_its_provenance_and_holds_no_bytes() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_array(parsed.keys()).contains_exactly_in_any_order(["comment", "size", "sectors"])
	assert_int(int(parsed["size"])).is_equal(ScreenData.RECORD_SIZE)
	var sectors := _fixture()
	assert_int(sectors.size()).is_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	for sector_entry: Dictionary in sectors:
		assert_array(sector_entry.keys()).contains_exactly_in_any_order(["index", "source", "screens"])
		assert_str(sector_entry["source"]["file"]).is_equal("NEP.DLL")
		assert_int(int(sector_entry["source"]["size"])).is_equal(15872)
		assert_int(sector_entry["screens"].size()).is_equal(Catalog.SCREENS_PER_SECTOR)
		for entry: Dictionary in sector_entry["screens"]:
			assert_array(entry.keys()).contains_exactly_in_any_order(["screen", "offset", "sha256"])
			assert_int(int(entry["offset"])).is_equal(ScreenData.original_offset(int(entry["screen"])))
			assert_int(String(entry["sha256"]).length()).is_equal(64)


func test_every_screen_encodes_to_exactly_the_original_record() -> void:
	var problems: Array[String] = []
	var originals := _original_records()
	for sector_entry: Dictionary in _fixture():
		var s := int(sector_entry["index"])
		for entry: Dictionary in sector_entry["screens"]:
			var m := int(entry["screen"])
			if DELIBERATE_SCREEN_CHANGES.has("%d:%d" % [s, m]):
				continue
			var screen := Catalog.sector(s).screens[m]
			var messages := screen.validate()
			if not messages.is_empty():
				problems.append("sector %d screen %d: does not fit the record: %s" % [s, m, messages[0]])
				continue
			var encoded := screen.encode()
			if FixtureHash.sha256_hex(encoded) == entry["sha256"]:
				continue
			var text := "sector %d screen %d differs from the original (edited on purpose? list it in DELIBERATE_SCREEN_CHANGES, or reset it with tools/import/reset_screens.py); %s to see which field" % [s, m, NEED_THE_IMPORTER]
			if originals.has("%d:%d" % [s, m]):
				text = "sector %d screen %d: %s (edited on purpose? list it in DELIBERATE_SCREEN_CHANGES, or reset it with tools/import/reset_screens.py)" % [s, m, ScreenData.first_difference(originals["%d:%d" % [s, m]], encoded)]
			problems.append(text)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_original_record_bytes_hash_to_the_fixture_and_the_screens_encode_to_them() -> void:
	var originals := _original_records()
	if originals.is_empty():
		prints("SKIPPED: %s is missing; %s" % [ORIGINAL_BYTES, NEED_THE_IMPORTER])
		return
	var problems: Array[String] = []
	var count := 0
	for sector_entry: Dictionary in _fixture():
		var s := int(sector_entry["index"])
		for entry: Dictionary in sector_entry["screens"]:
			var key := "%d:%d" % [s, int(entry["screen"])]
			count += 1
			if not originals.has(key) or FixtureHash.sha256_hex(originals[key]) != entry["sha256"]:
				problems.append("sector %d screen %d: the record in %s does not match the SHA-256 committed in screens.json (your copy of the game is a different version or patched); %s" % [s, int(entry["screen"]), ORIGINAL_BYTES.get_file(), NEED_THE_IMPORTER])
				continue
			if DELIBERATE_SCREEN_CHANGES.has(key):
				continue
			var difference := ScreenData.first_difference(originals[key], Catalog.sector(s).screens[int(entry["screen"])].encode())
			if not difference.is_empty():
				problems.append("sector %d screen %d: %s" % [s, int(entry["screen"]), difference])
	assert_int(count).is_equal(Catalog.ORIGINAL_SECTOR_COUNT * Catalog.SCREENS_PER_SECTOR)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_every_stored_screen_knows_which_original_record_it_came_from() -> void:
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := Catalog.sector(s)
		for m in sector.screens.size():
			assert_int(sector.screens[m].original_sector).override_failure_message("sector %d screen %d" % [s, m]).is_equal(s)
			assert_int(sector.screens[m].original_screen).override_failure_message("sector %d screen %d" % [s, m]).is_equal(m)


func test_each_screen_is_its_own_file() -> void:
	for s in [0, 17, 31]:
		for m in Catalog.SCREENS_PER_SECTOR:
			var sector := load(LegacyPack.SECTORS_DIR + "/sector_%02d/sector_%02d.tres" % [s, s]) as SectorData          # (the authoring files: a pack that leaves the project holds the screens in the sector's file)
			assert_str(sector.screens[m].resource_path).is_equal(LegacyPack.SECTORS_DIR + "/sector_%02d/screen_%02d.tres" % [s, m])


func test_the_stale_bytes_of_the_seven_odd_records_are_kept() -> void:
	var with_stale := 0
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		for screen in Catalog.sector(s).screens:
			if not screen.stale_bytes.is_empty():
				with_stale += 1
	assert_int(with_stale).is_equal(7)


# --- a deliberately edited screen gives a readable message -----------------------------------------------------

## A copy of an original screen that is safe to change (the loaded resources are shared and cached).
func _copy_of(sector: int, screen: int) -> ScreenData:
	return Catalog.sector(sector).screens[screen].duplicate_deep() as ScreenData


## The record of a stored original screen as it encodes now (equal to the original: test_every_screen_encodes_to_exactly_the_original_record),
## the baseline for the messages about an edit; it needs no original bytes.
func _original(sector: int, screen: int) -> PackedByteArray:
	return Catalog.sector(sector).screens[screen].encode()


func test_an_edited_deco_is_named_by_list_entry_and_field() -> void:
	var screen := _copy_of(0, 0)
	assert_int(screen.mid_decos.size()).is_greater(3)
	screen.mid_decos[3].pos.y += 2
	var message := ScreenData.first_difference(_original(0, 0), screen.encode())
	assert_str(message).starts_with("first difference at byte 0x")
	assert_str(message).contains("(mid decos entry 3 y)")


func test_an_edited_tile_and_a_trigger_flag_are_named() -> void:
	var screen := _copy_of(0, 5)
	screen.tiles[2 * ScreenData.TILE_COLUMNS + 7] = 0x41
	assert_str(ScreenData.first_difference(_original(0, 5), screen.encode())).contains("(tile row 2 column 7)")
	screen = _copy_of(0, 5)
	screen.triggers[0].rearm_on_enter = false
	assert_str(ScreenData.first_difference(_original(0, 5), screen.encode())).contains("(math triggers entry 0 flags)")


func test_an_edited_anim_deco_frame_is_named() -> void:
	var screen := _copy_of(0, 6)
	assert_int(screen.anim_decos.size()).is_greater(0)
	screen.anim_decos[0].frames[2] += 1
	assert_str(ScreenData.first_difference(_original(0, 6), screen.encode())).contains("(anim decos entry 0 frame list byte 2)")


func test_equal_records_have_no_difference_and_a_short_one_is_reported() -> void:
	var record := _original(0, 0)
	assert_str(ScreenData.first_difference(record, record)).is_empty()
	assert_str(ScreenData.first_difference(record, PackedByteArray())).contains("0 bytes")


func test_field_names_cover_the_layout() -> void:
	var record := _original(0, 0)
	assert_str(ScreenData.field_at(record, 0)).is_equal("tile row 0 column 0")
	assert_str(ScreenData.field_at(record, ScreenData.TILE_BYTES)).is_equal("bg decos count")
	assert_str(ScreenData.field_at(record, ScreenData.TILE_BYTES + 1)).is_equal("bg decos entry 0 x")
	assert_str(ScreenData.field_at(record, ScreenData.RECORD_SIZE - 1)).is_equal("unused bytes after the lists")


# --- validation: what does not fit, in words -------------------------------------------------------------------

func test_an_original_screen_has_no_problems_and_uses_at_most_the_record() -> void:
	var biggest := 0
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		for screen in Catalog.sector(s).screens:
			biggest = maxi(biggest, screen.used_bytes())
	assert_int(biggest).is_equal(1164)


func test_positions_off_the_grid_or_out_of_range_are_explained() -> void:
	var screen := _copy_of(0, 0)
	screen.bg_decos[0].pos = Vector2i(18, 33)
	screen.bg_decos[1].pos = Vector2i(1024, -2)
	var found := screen.validate()
	assert_array(found).contains(["bg decos entry 0: x 18 is not on the grid: the original keeps x / 4, so it must be a multiple of 4",
		"bg decos entry 0: y 33 is not on the grid: the original keeps y / 2, so it must be a multiple of 2"])
	assert_str("\n".join(found)).contains("bg decos entry 1: x 1024 does not fit")
	assert_str("\n".join(found)).contains("bg decos entry 1: y -2 does not fit")
	assert_int(screen.encode().size()).is_equal(0)


func test_slots_and_fields_out_of_range_are_explained() -> void:
	var screen := _copy_of(0, 5)
	screen.mid_decos[0].slot = 128
	screen.triggers[0].slot = 63
	screen.triggers[0].test_nibble = 16
	screen.triggers[0].other_bits = 0x01
	var text := "\n".join(screen.validate())
	assert_str(text).contains("mid decos entry 0: slot 128 does not fit")
	assert_str(text).contains("math triggers entry 0: trigger slot 63 does not exist")
	assert_str(text).contains("test_nibble 16 does not fit")
	assert_str(text).contains("other_bits 0x01")


func test_too_many_entries_and_too_big_a_record_are_explained() -> void:
	var screen := _copy_of(0, 0)
	for i in 300:
		var deco := DecoPlacement.new()
		screen.fg_decos.append(deco)
	var text := "\n".join(screen.validate())
	assert_str(text).contains("fg decos: %d entries, but the count is one byte, so 255 is the most" % screen.fg_decos.size())
	assert_str(text).contains("the screen needs %d bytes but a record holds 1280" % screen.used_bytes())
	screen = _copy_of(0, 0)
	for i in 100:
		screen.anim_decos.append(AnimDecoData.new())
	assert_str("\n".join(screen.validate())).contains("bytes but a record holds 1280 (0x500)")


func test_an_anim_deco_with_too_many_frames_is_explained() -> void:
	var anim := AnimDecoData.new()
	anim.frames = PackedInt32Array(range(17))
	assert_str("\n".join(anim.problems())).contains("17 frames do not fit")
	anim.frames = PackedInt32Array([127])
	assert_str("\n".join(anim.problems())).contains("slot 127 does not fit")


func test_tile_bytes_that_the_original_never_uses_are_refused() -> void:
	var screen := _copy_of(0, 0)
	screen.tiles[5] = 0xC1
	screen.tiles.resize(ScreenData.TILE_BYTES)
	assert_str("\n".join(screen.validate())).contains("tile row 0 column 5: byte 0xc1")
	screen.tiles.resize(10)
	assert_str("\n".join(screen.validate())).contains("tiles: 10 bytes")


func test_a_screen_that_grows_over_stale_bytes_overwrites_them() -> void:
	var screen := _copy_of(0, 6)             # stale byte 0x71 at record offset 913, used part ends at 911
	assert_int(screen.stale_offset).is_equal(913)
	var before := screen.encode()
	assert_int(before[913]).is_equal(0x71)
	screen.fg_decos.append(DecoPlacement.new())           # three bytes more: the list now covers 911..913
	var after := screen.encode()
	assert_int(after.size()).is_equal(ScreenData.RECORD_SIZE)
	assert_int(after[913]).is_not_equal(0x71)


# --- one owner for every piece of information -------------------------------------------------------------------

func test_trigger_flags_are_computed_from_the_fields() -> void:
	var trigger := MathTriggerData.new()
	trigger.armed = true
	trigger.rearm_on_enter = true
	trigger.test_nibble = 1
	assert_int(trigger.flags).is_equal(0xA1)
	trigger.armed = false
	trigger.rearm_on_enter = false
	trigger.test_nibble = 15
	trigger.other_bits = 0x50
	assert_int(trigger.flags).is_equal(0x5F)
	assert_bool(trigger.problems().is_empty()).is_true()


func test_the_original_triggers_use_only_the_known_flag_bits() -> void:
	var seen: Dictionary = {}
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		for screen in Catalog.sector(s).screens:
			for trigger in screen.triggers:
				assert_int(trigger.other_bits).is_equal(0)
				seen[trigger.flags] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([0x81, 0x82, 0x84, 0x88, 0x8C, 0x8F, 0xA1, 0xA2, 0xAF])


func test_an_anim_deco_encodes_from_its_decoded_fields() -> void:
	var anim := AnimDecoData.new()
	anim.pos = Vector2i(48, 100)
	anim.size = Vector2i(32, 40)
	anim.start_cursor = 3
	anim.frames = PackedInt32Array([0x3E, 0x3E, 0x3F])
	var bytes := anim.encode()
	assert_int(bytes.size()).is_equal(22)
	assert_array(Array(bytes.slice(0, 9))).is_equal([12, 50, 8, 20, 3, 0x3F, 0x3F, 0x40, 0])
	assert_array(Array(bytes.slice(9))).is_equal([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
