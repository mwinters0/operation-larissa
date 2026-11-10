class_name TestSectorEditing
extends GdUnitTestSuite
## Teaches: editing the data with plain functions, and what "within the original limits" means for each kind of thing. The
## sector's pieces and creatures are added and removed by `SectorData.add_piece` / `remove_piece` / `add_foe` / `remove_foe`
## (no editor, no nodes): they return the problems in words and change nothing when there are any. The tests cover
##   - the limits: 11 piece slots in the header, the count byte of the foe buffer, the data canister that stays piece 0,
##   - the bytes: the header and the foe buffer of a sector with an added piece or creature, and the first ones again after the
##     addition is taken back,
##   - the numbers in the creature script: a creature that the script names (`Put_Foe_To_Sleep ray_stinger`) can not be removed,
##     and neither can one in front of it, because that would change what the line means,
##   - the file: `ResourceSaver` (through `SectorDataSaver`) writes the changed lists, and the original file again after a
##     round trip; `SectorLists` writes every list of the pack's sectors exactly as the generator did.
## Everything is written under user://, never into res://data.

const SECTORS := DevPack.SECTORS_DIR
const TEMP := "user://sector_editing_test"

var _savers: Array[ResourceFormatSaver] = []


func before_test() -> void:
	_savers = [ScreenDataSaver.new(), SectorDataSaver.new()]
	for saver in _savers:
		ResourceSaver.add_resource_format_saver(saver, true)
	ScreenFile.last_refusal = ""
	DirAccess.make_dir_recursive_absolute(TEMP)


func after_test() -> void:
	for saver in _savers:
		ResourceSaver.remove_resource_format_saver(saver)
	_savers.clear()
	for file in DirAccess.get_files_at(TEMP):
		DirAccess.remove_absolute(TEMP.path_join(file))
	DirAccess.remove_absolute(TEMP)


## A fresh, private copy of a sector of the dev pack (the catalog's are shared and cached).
func _load(sector: int) -> SectorData:
	return ResourceLoader.load(Catalog.sector_path(sector, SECTORS), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData


func _copy_file(sector: int) -> String:
	var path := TEMP.path_join("sector_%02d.tres" % sector)
	assert_int(DirAccess.copy_absolute(Catalog.sector_path(sector, SECTORS), path)).is_equal(OK)
	return path


func _reload(path: String) -> SectorData:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData


# --- pieces -----------------------------------------------------------------------------------------------------------

func test_a_piece_added_and_removed_again_gives_the_header_back() -> void:
	var failures: Array[String] = []
	for s in Ground.clean_sectors():
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


func test_an_added_piece_is_a_slot_of_the_header() -> void:
	var sector := _load(Ground.EDIT)
	var count := sector.pieces.size()
	assert_array(sector.add_piece(7, Vector2i(210, 94))).is_empty()
	var header := sector.encode()
	assert_int(header.decode_u16(4)).is_equal(count + 1)
	assert_int(header[0x06 + count]).is_equal(7)
	assert_int(header.decode_u16(0x11 + 2 * count)).is_equal(105)
	assert_int(header.decode_u16(0x27 + 2 * count)).is_equal(47)
	assert_bool(sector.pieces[count].is_canister).is_false()


func test_an_added_piece_takes_over_the_slot_of_a_stale_entry_and_gives_it_back() -> void:
	var sector := _load(Ground.EDIT)
	var count := sector.pieces.size()
	sector.stale_pieces = PackedInt32Array([count, 4, 576, 176])           # slot `count` still holds a left-over (the importer keeps the original's)
	var original := sector.encode()
	assert_array(sector.add_piece(1, Vector2i(64, 64))).is_empty()
	var header := sector.encode()
	assert_int(header[0x06 + count]).is_equal(1)                              # the new piece, not the left-over
	assert_array(sector.remove_piece(count)).is_empty()
	assert_array(Array(sector.encode())).is_equal(Array(original))
	assert_array(Array(sector.stale_pieces)).is_equal([count, 4, 576, 176])


func test_the_twelfth_piece_is_refused_and_nothing_changes() -> void:
	var sector := _load(Ground.MAIN)                               # eleven pieces
	assert_int(sector.pieces.size()).is_equal(SectorData.MAX_PIECES)
	var before := sector.encode()
	var problems := sector.add_piece(1, Vector2i(64, 64))
	assert_array(problems).has_size(1)
	assert_str(problems[0]).contains("11 pieces")
	assert_int(sector.pieces.size()).is_equal(SectorData.MAX_PIECES)
	assert_array(Array(sector.encode())).is_equal(Array(before))


func test_a_piece_must_lie_on_a_screen_and_on_the_grid() -> void:
	var sector := _load(Ground.EDIT)
	var count := sector.pieces.size()
	assert_str(" ".join(sector.add_piece(12, Vector2i(64, 64)))).contains("screen 12")
	assert_str(" ".join(sector.add_piece(-1, Vector2i(64, 64)))).contains("screen -1")
	assert_str(" ".join(sector.add_piece(3, Vector2i(65, 64)))).contains("even")
	assert_str(" ".join(sector.add_piece(3, Vector2i(64, -2)))).contains("does not fit")
	assert_int(sector.pieces.size()).is_equal(count)


func test_the_data_canister_stays_piece_zero() -> void:
	var sector := _load(Ground.EDIT)
	assert_bool(sector.pieces[0].is_canister).is_true()
	assert_str(" ".join(sector.remove_piece(0))).contains("data canister")
	assert_str(" ".join(sector.add_piece(2, Vector2i(64, 64), 0))).contains("data canister")
	assert_bool(sector.pieces[0].is_canister).is_true()
	assert_str(" ".join(sector.remove_piece(99))).contains("does not exist")
	assert_str(" ".join(sector.add_piece(2, Vector2i(64, 64), 99))).contains("only")
	# alone it can go, and the first piece to come back is the canister again
	var small := _load(Ground.FINALE)
	assert_int(small.pieces.size()).is_equal(0)
	assert_array(small.add_piece(2, Vector2i(64, 64))).is_empty()
	assert_bool(small.pieces[0].is_canister).is_true()
	assert_array(small.remove_piece(0)).is_empty()
	assert_int(small.pieces.size()).is_equal(0)


func test_a_piece_removed_from_the_middle_moves_the_others_up_and_undoes() -> void:
	var sector := _load(Ground.EDIT)
	var names: Array[Vector2i] = []
	for piece in sector.pieces:
		names.append(piece.pos)
	var original := sector.encode()
	var removed := sector.pieces[3]
	assert_array(sector.remove_piece(3)).is_empty()
	assert_vector(sector.pieces[3].pos).is_equal(names[4])
	assert_int(sector.pieces.size()).is_equal(names.size() - 1)
	assert_array(sector.insert_piece(removed, 3)).is_empty()
	assert_array(Array(sector.encode())).is_equal(Array(original))


func test_the_collected_mask_of_a_game_in_progress_follows_the_numbers() -> void:
	# pieces 0, 1, 3 and 5 taken
	var mask := 0b101011
	assert_int(SectorData.pieces_mask_after_remove(mask, 3)).is_equal(0b10011)     # 3 gone, 5 is now 4
	assert_int(SectorData.pieces_mask_after_remove(mask, 2)).is_equal(0b10111)     # 2 was not taken: 3 -> 2, 5 -> 4
	assert_int(SectorData.pieces_mask_after_remove(mask, 5)).is_equal(0b1011)
	assert_int(SectorData.pieces_mask_after_insert(mask, 2)).is_equal(0b1010011)   # 3 -> 4, 5 -> 6, the new piece 2 is not taken
	assert_int(SectorData.pieces_mask_after_insert(mask, 6)).is_equal(mask)
	for at in 8:
		assert_int(SectorData.pieces_mask_after_remove(SectorData.pieces_mask_after_insert(mask, at), at)).is_equal(mask)


# --- creatures --------------------------------------------------------------------------------------------------------

func test_every_sector_has_its_script_right_after_the_records() -> void:
	for s in Ground.clean_sectors():
		var sector := _load(s)
		if sector.foes.is_empty():
			continue
		var buffer := sector.encode_foe_buffer()
		assert_int(buffer.size()).override_failure_message("sector %d" % s).is_greater(1 + FoeData.RECORD_SIZE * sector.foes.size())
		assert_int(buffer[0]).is_equal(sector.foes.size())
		assert_array(Array(buffer.slice(1, 1 + FoeData.RECORD_SIZE))).is_equal(Array(sector.encode_foe_records()[0]))
		assert_array(Array(buffer.slice(1 + FoeData.RECORD_SIZE * sector.foes.size()))).is_equal(Array(sector.foe_bytecode))


func test_a_creature_added_at_the_end_is_a_record_and_moves_the_script() -> void:
	var sector := _load(Ground.EDIT)
	var count := sector.foes.size()
	var script_before := sector.foe_bytecode.duplicate()           # (compiles the script: the creatures' entry points are numbers now)
	var first_entry := sector.foes[0].pc
	var like := sector.foes[1]
	assert_array(sector.add_foe(5, Vector2i(200, 100), 1)).is_empty()
	assert_int(sector.foes.size()).is_equal(count + 1)
	assert_int(sector.foe_script_base).is_equal(1 + FoeData.RECORD_SIZE * (count + 1))
	var buffer := sector.encode_foe_buffer()
	assert_int(buffer[0]).is_equal(count + 1)
	var records := sector.encode_foe_records()
	assert_int(records.size()).is_equal(count + 1)
	# the copy: the position and screen of its own, the rest of the creature it was made from
	var added := sector.foes[count]
	assert_int(added.screen).is_equal(5)
	assert_vector(added.pos).is_equal(Vector2i(200, 100))
	assert_str(added.start_label).is_equal(like.start_label)
	assert_int(added.frame).is_equal(like.frame)
	assert_int(added.damage).is_equal(like.damage)
	assert_int(added.pc).is_equal(like.pc)
	# the script is the same bytes, 34 further on: every entry point moved with it
	assert_array(Array(sector.foe_bytecode)).is_equal(Array(script_before))
	assert_int(sector.encode_foe_records()[0].decode_u16(0x10)).is_equal(first_entry + FoeData.RECORD_SIZE)
	assert_array(Array(buffer.slice(1 + FoeData.RECORD_SIZE * (count + 1)))).is_equal(Array(script_before))


func test_a_creature_added_and_removed_again_gives_the_buffer_back() -> void:
	var failures: Array[String] = []
	for s in Ground.clean_sectors():
		var sector := _load(s)
		if sector.foes.is_empty():
			continue
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
			failures.append("sector %d: the buffer is not the first one after taking the creature back" % s)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_the_count_byte_is_the_creature_limit() -> void:
	var sector := _load(Ground.MAIN)
	while sector.foes.size() < SectorData.MAX_FOES:
		var problems := sector.add_foe(1, Vector2i(64, 64))
		assert_array(problems).is_empty()
		if not problems.is_empty():
			return
	assert_int(sector.foes.size()).is_equal(255)
	assert_int(sector.encode_foe_buffer()[0]).is_equal(255)
	var base := sector.foe_script_base
	var problems := sector.add_foe(1, Vector2i(64, 64))
	assert_array(problems).has_size(1)
	assert_str(problems[0]).contains("255")
	assert_int(sector.foes.size()).is_equal(255)
	assert_int(sector.foe_script_base).is_equal(base)
	assert_array(sector.foe_notes()).has_size(1)                # beyond 128 the script can not name them
	# a count of 256 would not fit the byte, whoever put it there
	sector.foes.append(FoeData.new())
	assert_str(" ".join(sector.foe_problems())).contains("at most 255")


func test_a_creature_must_be_on_a_screen_with_a_grid_position() -> void:
	var sector := _load(Ground.EDIT)
	var count := sector.foes.size()
	assert_str(" ".join(sector.add_foe(12, Vector2i(64, 64)))).contains("screen 12")
	assert_str(" ".join(sector.add_foe(1, Vector2i(63, 64)))).contains("even")
	assert_int(sector.foes.size()).is_equal(count)


func test_a_creature_the_script_names_can_not_be_removed() -> void:
	var sector := _load(Ground.EDIT)                           # `Put_Foe_To_Sleep foe_3`, `Wake_Foe foe_1` (the made-up names of creatures 3 and 1)
	var count := sector.foes.size()
	var tank := FoeNames.for_sector(sector).index_for(FoeOps.Kind.FOE, "foe_3")
	var stinger := FoeNames.for_sector(sector).index_for(FoeOps.Kind.FOE, "foe_1")
	assert_int(tank).is_equal(3)
	var problems := sector.remove_foe(tank)
	assert_array(problems).is_not_empty()
	assert_str(problems[0]).contains("line").contains("names creature %d" % tank)
	assert_int(sector.foes.size()).is_equal(count)
	problems = sector.remove_foe(stinger)
	assert_str(" ".join(problems)).contains("names creature %d, the one to remove" % stinger)
	assert_int(sector.foes.size()).is_equal(count)


func test_a_creature_in_front_of_a_named_one_can_not_be_removed_or_inserted() -> void:
	var sector := _load(Ground.EDIT)
	var count := sector.foes.size()
	var base := sector.foe_script_base
	var problems := sector.remove_foe(0)
	assert_str(" ".join(problems)).contains("which would become creature")
	assert_array(sector.add_foe(1, Vector2i(64, 64), -1, 0)).is_not_empty()
	assert_int(sector.foes.size()).is_equal(count)
	assert_int(sector.foe_script_base).is_equal(base)


func test_a_creature_nobody_names_comes_out_of_the_middle() -> void:
	var sector := _load(Ground.MAIN)                            # no line of its script names a creature
	assert_array(sector.foe_operand_uses()).is_empty()
	var count := sector.foes.size()
	var second := sector.foes[2]
	var third := sector.foes[3]
	assert_array(sector.remove_foe(2)).is_empty()
	assert_int(sector.foes.size()).is_equal(count - 1)
	assert_object(sector.foes[2]).is_same(third)
	assert_int(sector.foe_script_base).is_equal(1 + FoeData.RECORD_SIZE * (count - 1))
	assert_array(sector.insert_foe(second, 2)).is_empty()       # the undo of the removal
	assert_array(Array(sector.encode_foe_buffer())).is_equal(Array(_load(Ground.MAIN).encode_foe_buffer()))


func test_self_relative_operands_are_checked_for_the_creatures_that_can_run_them() -> void:
	var sector := _synthetic_sector("""
quiet:
    Return
sleeper:
    Put_Foe_To_Sleep self+1
    Return
""", 3)                                                         # only creature 1 runs `sleeper`: it puts creature 2 to sleep
	assert_array(sector.foe_problems()).is_empty()
	assert_int(sector.foe_operand_uses().size()).is_equal(1)
	assert_str(" ".join(sector.remove_foe(2))).contains("self+1")                         # the creature it reaches
	assert_str(" ".join(sector.add_foe(1, Vector2i(64, 64), 0, 2))).contains("self+1")    # between the two: the distance changes
	assert_array(sector.add_foe(1, Vector2i(64, 64), 0, 1)).is_empty()                    # in front of both: they move together
	assert_array(sector.remove_foe(1)).is_empty()                                         # and out again
	assert_array(sector.remove_foe(0)).is_empty()                                         # a creature in front of the pair
	assert_int(sector.foes.size()).is_equal(2)
	assert_str(" ".join(sector.remove_foe(1))).contains("self+1").contains("creature 0")  # but not the one it reaches: 0 is the runner now


func test_a_script_that_does_not_compile_blocks_the_numbering_checks() -> void:
	var sector := _synthetic_sector("quiet:\n    Return\n", 2)
	sector.foes[1].hit_label = "nowhere"
	assert_str(" ".join(sector.remove_foe(1))).contains("does not compile")


func test_the_finale_treasure_stays() -> void:
	var sector := _load(Ground.FINALE)
	assert_str(" ".join(sector.remove_foe(0))).contains("treasure")


## A sector of `count` creatures that all use the labels `quiet` (start, hit and ink) and the given script text.
func _synthetic_sector(source: String, count: int) -> SectorData:
	var sector := SectorData.new()
	sector.index = 1
	sector.neighbors_left = PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1])
	sector.neighbors_right = sector.neighbors_left.duplicate()
	sector.neighbors_up = sector.neighbors_left.duplicate()
	sector.neighbors_down = sector.neighbors_left.duplicate()
	var script := FoeScript.new()
	script.source = source
	sector.foe_script = script
	sector.foe_script_base = 1 + FoeData.RECORD_SIZE * count
	for k in count:
		var foe := FoeData.new()
		foe.start_label = "sleeper" if k == 1 else "quiet"
		foe.hit_label = "quiet"
		foe.ink_label = "quiet"
		sector.foes.append(foe)
	return sector


# --- the file ---------------------------------------------------------------------------------------------------------

func test_sector_lists_write_every_list_exactly_as_the_generator_did() -> void:
	var failures: Array[String] = []
	for s in Ground.clean_sectors():
		var sector := _load(s)
		var text := FileAccess.get_file_as_string(Catalog.sector_path(s, SECTORS))
		for group: String in ["pieces", "foes"]:
			var result := SectorLists.rewrite(text.split("\n"), group, sector.get(group))
			if not (result.error as String).is_empty():
				failures.append("sector %d %s: %s" % [s, group, result.error])
			elif "\n".join(result.lines) != text:
				failures.append("sector %d %s are written differently" % [s, group])
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_a_piece_added_and_taken_back_leaves_the_file_as_it_was() -> void:
	for s in [Ground.EDIT, Ground.LEDGE, Ground.FINALE]:
		var path := _copy_file(s)
		var before := FileAccess.get_file_as_bytes(path)
		var sector := _reload(path)
		assert_array(sector.add_piece(2, Vector2i(100, 62))).is_empty()
		assert_int(ResourceSaver.save(sector, path)).is_equal(OK)
		assert_str(ScreenFile.last_refusal).is_empty()
		assert_bool(FileAccess.get_file_as_bytes(path) == before).is_false()
		var grown := _reload(path)
		assert_int(grown.pieces.size()).is_equal(sector.pieces.size())
		assert_vector(grown.pieces[grown.pieces.size() - 1].pos).is_equal(Vector2i(100, 62))
		assert_bool(grown.pieces[0].is_canister).is_true()
		assert_array(Array(grown.encode())).is_equal(Array(sector.encode()))
		assert_array(grown.remove_piece(grown.pieces.size() - 1)).is_empty()
		assert_int(ResourceSaver.save(grown, path)).is_equal(OK)
		assert_bool(FileAccess.get_file_as_bytes(path) == before).override_failure_message("sector %d: not the original file" % s).is_true()


func test_a_creature_added_and_taken_back_leaves_the_file_as_it_was() -> void:
	for s in [Ground.EDIT, Ground.MAIN, Ground.MAP]:
		var path := _copy_file(s)
		var before := FileAccess.get_file_as_bytes(path)
		var sector := _reload(path)
		assert_array(sector.add_foe(4, Vector2i(88, 66))).is_empty()
		assert_int(ResourceSaver.save(sector, path)).is_equal(OK)
		assert_str(ScreenFile.last_refusal).is_empty()
		var grown := _reload(path)
		assert_int(grown.foes.size()).is_equal(sector.foes.size())
		assert_int(grown.foe_script_base).is_equal(sector.foe_script_base)
		assert_vector(grown.foes[grown.foes.size() - 1].pos).is_equal(Vector2i(88, 66))
		assert_array(Array(grown.encode_foe_buffer())).is_equal(Array(sector.encode_foe_buffer()))
		assert_array(grown.remove_foe(grown.foes.size() - 1)).is_empty()
		assert_int(ResourceSaver.save(grown, path)).is_equal(OK)
		assert_bool(FileAccess.get_file_as_bytes(path) == before).override_failure_message("sector %d: not the original file" % s).is_true()


func test_pieces_creatures_neighbours_and_music_are_saved_together() -> void:
	var path := _copy_file(Ground.EDIT)
	var sector := _reload(path)
	var removed_piece := sector.pieces[4].pos
	assert_array(sector.remove_piece(4)).is_empty()
	assert_array(sector.add_piece(11, Vector2i(30, 50))).is_empty()
	assert_array(sector.remove_foe(sector.foes.size() - 1)).is_empty()
	assert_array(sector.add_foe(2, Vector2i(40, 60))).is_empty()
	assert_array(sector.add_foe(3, Vector2i(42, 60))).is_empty()
	sector.neighbors_up[5] = 4
	sector.music_name = "esect3"
	sector.start_pos = Vector2i(60, 70)
	assert_int(ResourceSaver.save(sector, path)).is_equal(OK)
	assert_str(ScreenFile.last_refusal).is_empty()
	var back := _reload(path)
	assert_int(back.pieces.size()).is_equal(sector.pieces.size())
	assert_int(back.foes.size()).is_equal(sector.foes.size())
	for k in sector.pieces.size():
		assert_vector(back.pieces[k].pos).is_equal(sector.pieces[k].pos)
		assert_int(back.pieces[k].screen).is_equal(sector.pieces[k].screen)
		assert_bool(back.pieces[k].is_canister).is_equal(k == 0)
	for k in sector.foes.size():
		assert_vector(back.foes[k].pos).is_equal(sector.foes[k].pos)
		assert_str(back.foes[k].start_label).is_equal(sector.foes[k].start_label)
	assert_int(back.neighbors_up[5]).is_equal(4)
	assert_str(back.music_name).is_equal("esect3")
	assert_vector(back.start_pos).is_equal(Vector2i(60, 70))
	assert_int(back.foe_script_base).is_equal(1 + FoeData.RECORD_SIZE * back.foes.size())
	assert_vector(back.pieces[back.pieces.size() - 1].pos).is_equal(Vector2i(30, 50))
	assert_bool(back.pieces.any(func(p: PieceData) -> bool: return p.pos == removed_piece)).is_false()
	assert_array(Array(back.encode_foe_buffer())).is_equal(Array(sector.encode_foe_buffer()))
	# a second save of the same sector changes nothing
	var after_first := FileAccess.get_file_as_bytes(path)
	assert_int(ResourceSaver.save(back, path)).is_equal(OK)
	assert_bool(FileAccess.get_file_as_bytes(path) == after_first).is_true()
	# and the file is still importer text: ids unique, the lists point at them
	var text := FileAccess.get_file_as_string(path)
	assert_bool(text.contains("uid=")).is_false()
	var ids: Array[String] = []
	for line in text.split("\n"):
		if line.begins_with("[sub_resource"):
			assert_bool(ids.has(line)).override_failure_message("duplicate block " + line).is_false()
			ids.append(line)


func test_a_changed_foe_script_base_that_does_not_follow_the_count_is_still_refused() -> void:
	var path := _copy_file(Ground.EDIT)
	var before := FileAccess.get_file_as_bytes(path)
	var sector := _reload(path)
	sector.foe_script_base += 1
	assert_int(ResourceSaver.save(sector, path)).is_equal(OK)
	assert_str(ScreenFile.last_refusal).contains("foe_script_base").contains("NOT written")
	assert_bool(FileAccess.get_file_as_bytes(path) == before).is_true()
