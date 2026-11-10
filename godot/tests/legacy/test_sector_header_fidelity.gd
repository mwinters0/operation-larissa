class_name TestSectorHeaderFidelity
extends GdUnitTestSuite
## Teaches: a fixture of HASHES as the anchor for an encoder (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes").
## tests/fixtures/sector_headers.json holds, per sector, its provenance and the SHA-256 of the original 0x72-byte header
## and of the whole 0x3E00-byte resource, and no original bytes. `SectorData.encode()` and `encode_resource()` must hash
## to them for all 32 sectors, or the failure names the sector. The hashes are the anchor that does not come from your
## copy of the game: a different release or a patched copy is caught instead of being compared with itself.
##
## The original header BYTES are written by the importer into the git-ignored tests/fixtures/original/sector_headers.json.
## The tests that need them (the byte-for-byte comparison, "only sectors 6 and 22 have stale piece entries") skip with a
## message when it is missing; the hash tests never need it.

const FIXTURE := "res://tests/fixtures/sector_headers.json"
const ORIGINAL_BYTES := "res://tests/fixtures/original/sector_headers.json"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"

## DELIBERATE CHANGES to the header of an original sector: sector number -> the reason. A designer who changes the
## header of the original on purpose (a neighbour, a piece, the start point) and wants to keep the change lists the sector
## here; its resource then skips only the hash comparison (it must still be valid and encode). The project's convention
## is the "Deliberate deviation" in docs/port/FIDELITY.md. A sector with a screen listed in
## TestScreenFidelity.DELIBERATE_SCREEN_CHANGES skips the whole-resource comparison too, since its bytes changed.
## To go back to the original instead, run tools/import/import_all.py --only sectors.
const DELIBERATE_SECTOR_CHANGES := {}


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _fixture() -> Array:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed["sectors"]


## The original header bytes of every sector (index -> bytes), or an empty dictionary when the importer has not written them.
func _original_headers() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(ORIGINAL_BYTES):
		return out
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_BYTES))
	for entry: Dictionary in parsed["sectors"]:
		out[int(entry["index"])] = String(entry["header_hex"]).hex_decode()
	return out


## True (after saying why) when the importer's raw file is missing, for the tests that need the original bytes.
func _skip_without_original_bytes() -> bool:
	if FileAccess.file_exists(ORIGINAL_BYTES):
		return false
	prints("SKIPPED: %s is missing; %s" % [ORIGINAL_BYTES, NEED_THE_IMPORTER])
	return true


func _has_deliberate_screen_change(sector: int) -> bool:
	for m in Catalog.SCREENS_PER_SECTOR:
		if TestScreenFidelity.DELIBERATE_SCREEN_CHANGES.has("%d:%d" % [sector, m]):
			return true
	return false


## A copy of an original sector that is safe to change (the loaded resources are shared and cached).
func _copy_of(sector: int) -> SectorData:
	return Catalog.sector(sector).duplicate_deep() as SectorData


func test_the_fixture_covers_every_sector_with_its_provenance_and_holds_no_bytes() -> void:
	var sectors := _fixture()
	assert_int(sectors.size()).is_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	for i in sectors.size():
		var entry: Dictionary = sectors[i]
		assert_int(int(entry["index"])).is_equal(i)
		assert_str(entry["source"]["file"]).is_equal("NEP.DLL")
		assert_int(int(entry["source"]["size"])).is_equal(SectorData.RESOURCE_SIZE)
		assert_str(entry["source"]["extracted"]).is_not_empty()
		assert_int(int(entry["offset"])).is_equal(0)
		assert_int(int(entry["size"])).is_equal(SectorData.HEADER_SIZE)
		assert_int(String(entry["header_sha256"]).length()).is_equal(64)
		assert_int(String(entry["resource_sha256"]).length()).is_equal(64)
		assert_array(entry.keys()).contains_exactly_in_any_order(["index", "source", "offset", "size", "header_sha256", "resource_sha256"])


func test_every_header_encodes_to_exactly_the_original_bytes() -> void:
	var problems: Array[String] = []
	var originals := _original_headers()
	for entry: Dictionary in _fixture():
		var s := int(entry["index"])
		if DELIBERATE_SECTOR_CHANGES.has(s):
			continue
		var sector := Catalog.sector(s)
		var messages := sector.header_problems()
		if not messages.is_empty():
			problems.append("sector %d: header does not fit the original's: %s" % [s, messages[0]])
			continue
		var header := sector.encode()
		if FixtureHash.sha256_hex(header) == entry["header_sha256"]:
			continue
		var text := "sector %d header differs from the original (edited on purpose? list it in DELIBERATE_SECTOR_CHANGES); %s to see which field" % [s, NEED_THE_IMPORTER]
		if originals.has(s):
			text = "sector %d header differs from the original: %s (edited on purpose? list it in DELIBERATE_SECTOR_CHANGES)" % [s, SectorData.first_difference(originals[s], header)]
		problems.append(text)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


## This also proves the zero tail: the importer hashes the resource as NEP.DLL holds it, 0x3E00 bytes, and
## `encode_resource()` ends with zeros, so an original with a non-zero byte after the last record would not match.
func test_every_whole_resource_hashes_to_the_original() -> void:
	var problems: Array[String] = []
	for entry: Dictionary in _fixture():
		var s := int(entry["index"])
		if DELIBERATE_SECTOR_CHANGES.has(s) or _has_deliberate_screen_change(s):
			continue
		var sector := Catalog.sector(s)
		var messages := sector.resource_problems()
		if not messages.is_empty():
			problems.append("sector %d: does not fit the original's resource: %s" % [s, messages[0]])
			continue
		var resource := sector.encode_resource()
		assert_int(resource.size()).is_equal(SectorData.RESOURCE_SIZE)
		if FixtureHash.sha256_hex(resource) != entry["resource_sha256"]:
			problems.append("sector %d resource differs from the original (edited on purpose? list it in DELIBERATE_SECTOR_CHANGES or DELIBERATE_SCREEN_CHANGES); %s to see which field" % [s, NEED_THE_IMPORTER])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_resource_is_the_header_the_screen_records_and_a_zero_tail() -> void:
	var sector := Catalog.sector(3)
	var resource := sector.encode_resource()
	assert_bool(resource.slice(0, SectorData.HEADER_SIZE) == sector.encode()).is_true()
	for m in Catalog.SCREENS_PER_SECTOR:
		var start := ScreenData.original_offset(m)
		assert_bool(resource.slice(start, start + ScreenData.RECORD_SIZE) == sector.screens[m].encode()).is_true()
	var end := ScreenData.original_offset(Catalog.SCREENS_PER_SECTOR)
	assert_int(end).is_equal(0x3C72)
	for i in range(end, SectorData.RESOURCE_SIZE):
		assert_int(resource[i]).is_equal(0)


func test_the_hash_helper_gives_the_known_sha256() -> void:
	assert_str(FixtureHash.sha256_hex(PackedByteArray())).is_equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	assert_str(FixtureHash.sha256_hex("abc".to_utf8_buffer())).is_equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")


# --- what the original bytes show (need the importer's raw file) -----------------------------------------------

func test_the_header_bytes_match_the_original_byte_for_byte() -> void:
	if _skip_without_original_bytes():
		return
	var originals := _original_headers()
	assert_int(originals.size()).is_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		if DELIBERATE_SECTOR_CHANGES.has(s):
			continue
		assert_str(SectorData.first_difference(originals[s], Catalog.sector(s).encode())).override_failure_message("sector %d" % s).is_empty()
		assert_int((originals[s] as PackedByteArray).size()).is_equal(SectorData.HEADER_SIZE)


func test_only_sectors_6_and_22_have_stale_piece_entries() -> void:
	if _skip_without_original_bytes():
		return
	var found := {}
	var originals := _original_headers()
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var header: PackedByteArray = originals[s]
		var count := header.decode_u16(4)
		assert_int(Catalog.sector(s).pieces.size()).is_equal(count)
		for slot in range(count, SectorData.MAX_PIECES):
			var entry := [header[0x06 + slot], header.decode_u16(0x11 + 2 * slot), header.decode_u16(0x27 + 2 * slot)]
			if entry != [0, 0, 0]:
				found[s] = [slot, entry[0], 2 * entry[1], 2 * entry[2]]
	assert_dict(found).is_equal({6: [7, 4, 576, 176], 22: [9, 5, 464, 288]})
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var expected := Array(found[s]) if found.has(s) else []
		assert_array(Array(Catalog.sector(s).stale_pieces)).is_equal(expected)


func test_the_bytes_the_game_never_reads_are_the_same_in_the_same_sectors() -> void:
	# 0x3D = 11 and 0x40 = 0x48 together in sectors 0-10 and 12-24, both 0 in sector 11 and 25-31; 0x41 is always 0.
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := Catalog.sector(s)
		var used := (s <= 10) or (s >= 12 and s <= 24)
		assert_int(sector.header_unused_3d).override_failure_message("sector %d" % s).is_equal(11 if used else 0)
		assert_int(sector.header_unused_40).override_failure_message("sector %d" % s).is_equal(0x48 if used else 0)
		assert_int(sector.header_unused_41).override_failure_message("sector %d" % s).is_equal(0)


# --- a deliberately edited header gives a readable message -----------------------------------------------------

func test_an_edited_field_is_named() -> void:
	var original := Catalog.sector(0).encode()
	var sector := _copy_of(0)
	sector.pieces[3].pos.x += 2
	assert_str(SectorData.first_difference(original, sector.encode())).starts_with("first difference at byte 0x").contains("(piece_x entry 3)")
	sector = _copy_of(0)
	sector.neighbors_right[5] = 7
	assert_str(SectorData.first_difference(original, sector.encode())).contains("(right neighbour of screen 5)")
	sector = _copy_of(0)
	sector.start_pos.y += 4
	assert_str(SectorData.first_difference(original, sector.encode())).contains("(start y)")
	sector = _copy_of(0)
	sector.start_frame = 2
	assert_str(SectorData.first_difference(original, sector.encode())).contains("(start frame)")
	sector = _copy_of(0)
	sector.header_unused_40 = 1
	assert_str(SectorData.first_difference(original, sector.encode())).contains("(unused byte 0x40)")


func test_a_piece_beyond_the_count_is_marked_unused_and_equal_headers_have_no_difference() -> void:
	var header := Catalog.sector(0).encode()
	assert_int(Catalog.sector(0).pieces.size()).is_equal(10)
	assert_str(SectorData.field_at(header, 0x06 + 9)).is_equal("piece_screen entry 9")
	assert_str(SectorData.field_at(header, 0x06 + 10)).is_equal("piece_screen entry 10 (unused slot)")
	assert_str(SectorData.field_at(header, 0x27 + 2 * 10 + 1)).is_equal("piece_y entry 10 (unused slot)")
	assert_str(SectorData.first_difference(header, header)).is_empty()
	assert_str(SectorData.first_difference(header, PackedByteArray())).contains("0 bytes")


func test_resource_differences_name_the_header_a_screen_field_or_the_tail() -> void:
	var original := Catalog.sector(0).encode_resource()
	var sector := _copy_of(0)
	sector.neighbors_up[0] = 3
	assert_str(SectorData.resource_first_difference(original, sector.encode_resource())).contains("(up neighbour of screen 0)")
	sector = _copy_of(0)
	sector.screens[4] = sector.screens[4].duplicate_deep() as ScreenData
	sector.screens[4].tiles[2 * ScreenData.TILE_COLUMNS + 7] = 0x41
	assert_str(SectorData.resource_first_difference(original, sector.encode_resource())).contains("(screen 4 tile row 2 column 7)")
	var tampered := original.duplicate()
	tampered[SectorData.RESOURCE_SIZE - 1] = 1
	assert_str(SectorData.resource_first_difference(original, tampered)).contains("(zero tail after the screens)")
	assert_str(SectorData.resource_first_difference(original, original)).is_empty()


# --- what does not fit is refused, in words ---------------------------------------------------------------------

func test_an_original_sector_has_no_problems() -> void:
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		assert_array(Catalog.sector(s).resource_problems()).override_failure_message("sector %d" % s).is_empty()


func test_positions_off_the_grid_or_out_of_range_are_refused() -> void:
	var sector := _copy_of(0)
	sector.start_pos = Vector2i(69, -2)
	sector.pieces[1].pos = Vector2i(2 * 0xFFFF + 2, 7)
	var text := "\n".join(sector.header_problems())
	assert_str(text).contains("start x 69 is not on the grid: the original keeps x / 2, so it must be even")
	assert_str(text).contains("start y -2 does not fit")
	assert_str(text).contains("piece 1 x 131072 does not fit")
	assert_str(text).contains("piece 1 y 7 is not on the grid")
	assert_int(sector.encode().size()).is_equal(0)
	assert_int(sector.encode_resource().size()).is_equal(0)


func test_neighbours_outside_minus_one_to_eleven_are_refused() -> void:
	var sector := _copy_of(0)
	sector.neighbors_left[2] = 12
	sector.neighbors_down[11] = -2
	var text := "\n".join(sector.header_problems())
	assert_str(text).contains("neighbors_left of screen 2: 12 is not a screen of the sector")
	assert_str(text).contains("neighbors_down of screen 11: -2 is not a screen of the sector")
	sector = _copy_of(0)
	sector.neighbors_up.resize(11)
	assert_str("\n".join(sector.header_problems())).contains("neighbors_up: 11 entries, but a sector has 12 screens")
	sector = _copy_of(0)
	sector.neighbors_left[0] = -1                  # "no neighbour" is fine
	sector.neighbors_left[1] = 11
	assert_array(sector.header_problems()).is_empty()


func test_values_out_of_byte_or_u16_range_and_too_many_pieces_are_refused() -> void:
	var sector := _copy_of(0)
	sector.start_frame = 70000
	sector.header_unused_3d = 256
	sector.header_unused_41 = -1
	sector.pieces[0].screen = 300
	var text := "\n".join(sector.header_problems())
	assert_str(text).contains("start_frame 70000 does not fit")
	assert_str(text).contains("header_unused_3d 256 does not fit in one byte")
	assert_str(text).contains("header_unused_41 -1 does not fit in one byte")
	assert_str(text).contains("piece 0: screen 300 does not fit")
	sector = _copy_of(0)
	for i in 5:
		sector.pieces.append(PieceData.new())
	assert_str("\n".join(sector.header_problems())).contains("pieces: 15, but the header has room for 11")


func test_stale_pieces_must_be_whole_entries_in_real_slots() -> void:
	var sector := _copy_of(0)
	sector.stale_pieces = PackedInt32Array([10, 1, 2, 3, 11, 0, 0, 0])
	assert_str("\n".join(sector.header_problems())).contains("stale piece 1: slot 11 does not exist")
	sector.stale_pieces = PackedInt32Array([10, 1, 2])
	assert_str("\n".join(sector.header_problems())).contains("each entry is four")


func test_a_piece_added_over_a_stale_slot_overwrites_it() -> void:
	var sector := _copy_of(6)                      # 7 pieces, a stale entry in slot 7
	assert_array(Array(sector.stale_pieces)).is_equal([7, 4, 576, 176])
	var before := sector.encode()
	assert_int(before[0x06 + 7]).is_equal(4)
	var piece := PieceData.new()
	piece.screen = 9
	piece.pos = Vector2i(10, 20)
	sector.pieces.append(piece)
	var after := sector.encode()
	assert_int(after[0x06 + 7]).is_equal(9)
	assert_int(after.decode_u16(0x11 + 14)).is_equal(5)
	assert_int(after.decode_u16(0x27 + 14)).is_equal(10)
	assert_int(after.decode_u16(4)).is_equal(8)


func test_a_screen_that_does_not_fit_stops_the_resource() -> void:
	var sector := _copy_of(0)
	sector.screens[2] = sector.screens[2].duplicate_deep() as ScreenData
	sector.screens[2].tiles.resize(10)
	assert_str("\n".join(sector.resource_problems())).contains("screen 2: tiles: 10 bytes")
	assert_int(sector.encode().size()).is_equal(SectorData.HEADER_SIZE)         # the header alone is still fine
	assert_int(sector.encode_resource().size()).is_equal(0)
	sector = _copy_of(0)
	sector.screens.pop_back()
	assert_str("\n".join(sector.resource_problems())).contains("screens: 11, but a sector has 12")
