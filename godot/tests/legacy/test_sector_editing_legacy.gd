class_name TestSectorEditingLegacy
extends GdUnitTestSuite
## Adding and taking back pieces and creatures on the original's 32 sectors gives their bytes back exactly (the header with its left-over entries, the creature
## buffer, the lists of the file as the importer wrote them). The editing rules, on the sectors of dev, are in `tests/engine/test_sector_editing.gd`.
## Everything is written under user://, never into res://data.

const SECTORS := LegacyPack.SECTORS_DIR


## A fresh, private copy of an original sector (the catalog's are shared and cached).
func _load(sector: int) -> SectorData:
	return ResourceLoader.load(Catalog.sector_path(sector, SECTORS), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData


func test_a_piece_added_and_removed_again_gives_the_original_header_back() -> void:
	var failures: Array[String] = []
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := _load(s)
		if sector.pieces.size() >= SectorData.MAX_PIECES:
			continue
		var original := sector.encode()
		assert_array(Array(original)).is_not_empty()
		assert_array(sector.add_piece(4, Vector2i(100, 62))).is_empty()
		var grown := sector.encode()
		assert_int(grown.decode_u16(4)).is_equal(sector.pieces.size())
		if grown == original:
			failures.append("sector %d: the added piece is not in the header" % s)
		assert_array(sector.remove_piece(sector.pieces.size() - 1)).is_empty()
		if sector.encode() != original:
			failures.append("sector %d: %s" % [s, SectorData.first_difference(original, sector.encode())])
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()



func test_an_added_piece_takes_over_the_slot_of_a_stale_entry_and_gives_it_back() -> void:
	var sector := _load(6)                                     # slot 7 still holds a left-over of the original
	var original := sector.encode()
	assert_int(sector.pieces.size()).is_equal(7)
	assert_array(sector.add_piece(1, Vector2i(64, 64))).is_empty()
	var header := sector.encode()
	assert_int(header[0x06 + 7]).is_equal(1)                   # the new piece, not the left-over
	assert_array(sector.remove_piece(7)).is_empty()
	assert_array(Array(sector.encode())).is_equal(Array(original))
	assert_array(Array(sector.stale_pieces)).is_equal([7, 4, 576, 176])



func test_the_original_sectors_have_their_script_right_after_the_records() -> void:
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := _load(s)
		var buffer := sector.encode_foe_buffer()
		assert_int(buffer.size()).override_failure_message("sector %d" % s).is_greater(1 + FoeData.RECORD_SIZE * sector.foes.size())
		assert_int(buffer[0]).is_equal(sector.foes.size())
		assert_array(Array(buffer.slice(1, 1 + FoeData.RECORD_SIZE))).is_equal(Array(sector.encode_foe_records()[0]))
		assert_array(Array(buffer.slice(1 + FoeData.RECORD_SIZE * sector.foes.size()))).is_equal(Array(sector.foe_bytecode))



func test_a_creature_added_and_removed_again_gives_the_original_buffer_back() -> void:
	var failures: Array[String] = []
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := _load(s)
		var original := sector.encode_foe_buffer()
		assert_array(Array(original)).is_not_empty()
		var problems := sector.add_foe(3, Vector2i(120, 80))
		if not problems.is_empty():
			failures.append("sector %d: %s" % [s, problems[0]])
			continue
		if sector.encode_foe_buffer() == original:
			failures.append("sector %d: the added creature is not in the buffer" % s)
		problems = sector.remove_foe(sector.foes.size() - 1)
		if not problems.is_empty():
			failures.append("sector %d: %s" % [s, problems[0]])
		elif sector.encode_foe_buffer() != original:
			failures.append("sector %d: the buffer is not the original after taking the creature back" % s)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()



func test_sector_lists_write_every_original_list_exactly_as_the_importer_did() -> void:
	var failures: Array[String] = []
	for s in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := _load(s)
		var text := FileAccess.get_file_as_string(Catalog.sector_path(s, SECTORS))
		for group: String in ["pieces", "foes"]:
			var result := SectorLists.rewrite(text.split("\n"), group, sector.get(group))
			if not (result.error as String).is_empty():
				failures.append("sector %d %s: %s" % [s, group, result.error])
			elif "\n".join(result.lines) != text:
				failures.append("sector %d %s are written differently" % [s, group])
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


