class_name TestScreenEditor
extends GdUnitTestSuite
## Teaches: testing an editor tool without the editor. The `ScreenEditor` scene root builds its nodes in `reload()` and reads
## them back in `build()`; the central claim is that this loses nothing: for every screen of the pack the nodes encode to the
## screen's bytes again. The rest are the rules of editing: what the tile layers may hold, the grid, the sector data that
## travels with a screen, and saving into a COPY of the data (user://), never the committed files.

const SECTORS := DevPack.SECTORS_DIR
const TEMP := "user://screen_editor_test"
const INVISIBLE := TileCodec.INVISIBLE_WALL_SOURCE


## A ScreenEditor for (sector, screen), loaded but not in the tree (enough for build / save; `in_tree` puts it in).
func _editor(sector: int, screen: int, dir: String = SECTORS, in_tree: bool = false) -> ScreenEditor:
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor
	editor.data_dir = dir
	editor.sector = sector
	editor.screen = screen
	if in_tree:
		add_child(editor)                                  # _ready loads
	else:
		editor.reload()
	return editor


## Copies sector `s` (the sector file and its screen folder) into a temp folder and returns it.
func _temp_copy(s: int) -> String:
	DirAccess.make_dir_recursive_absolute(Catalog.sector_dir(s, TEMP))
	DirAccess.copy_absolute(Catalog.sector_path(s, SECTORS), Catalog.sector_path(s, TEMP))
	for m in Catalog.SCREENS_PER_SECTOR:
		DirAccess.copy_absolute(ScreenFile.screen_path(SECTORS, s, m), ScreenFile.screen_path(TEMP, s, m))
	return TEMP


func after_test() -> void:
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	PackFiles.remove_tree("user://screen_editor_test_own")
	if DirAccess.dir_exists_absolute(TEMP):
		for s in Ground.clean_sectors():
			for m in Catalog.SCREENS_PER_SECTOR:
				DirAccess.remove_absolute(ScreenFile.screen_path(TEMP, s, m))
			DirAccess.remove_absolute(Catalog.sector_path(s, TEMP))
			DirAccess.remove_absolute(Catalog.sector_dir(s, TEMP))
		DirAccess.remove_absolute(TEMP)


func _deco_layer(editor: ScreenEditor, layer: String) -> Node:
	return editor.get_node(layer)


# --- the editor loses nothing ---------------------------------------------------------------------------------------

func test_every_screen_of_the_pack_encodes_back_to_its_record() -> void:
	var problems: Array[String] = []
	for s in Ground.clean_sectors():
		for m in Catalog.SCREENS_PER_SECTOR:
			var editor := auto_free(ScreenEditor.new()) as ScreenEditor
			editor.sector = s
			editor.screen = m
			editor.reload()
			var built := editor.build()
			if not built.problems.is_empty():
				problems.append("sector %d screen %d: %s" % [s, m, built.problems[0]])
				continue
			var record := Catalog.sector(s).screens[m].encode()
			if built.screen.encode() != record:
				problems.append("sector %d screen %d: does not encode to its record: %s" % [s, m, ScreenData.first_difference(record, built.screen.encode())])
			elif editor.is_dirty():
				problems.append("sector %d screen %d: dirty right after loading" % [s, m])
			editor.free()
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_the_sector_data_survives_the_round_trip_too() -> void:
	for s in [Ground.MAIN, Ground.LEDGE, Ground.EDIT, Ground.FINALE]:
		var sector := Catalog.sector(s)
		for m in Catalog.SCREENS_PER_SECTOR:
			var built := _editor(s, m).build()
			assert_int(built.pieces.size()).is_equal(sector.pieces.size())
			for i in sector.pieces.size():
				assert_int(built.pieces[i].screen).is_equal(sector.pieces[i].screen)
				assert_vector(built.pieces[i].pos).is_equal(sector.pieces[i].pos)
			assert_vector(built.start_pos).is_equal(sector.start_pos)
			assert_int(built.start_frame).is_equal(sector.start_frame)


func test_the_layers_are_in_the_games_draw_order() -> void:
	var names: Array[String] = []
	for child in _editor(Ground.MAIN, 0).get_children():
		names.append(child.name)
	assert_array(names).is_equal(["Background", "BackDecos", "Walls", "MidDecos", "Pieces", "Station", "Foes", "FrontDecos", "AnimDecos", "Currents", "Triggers"])
	names.clear()
	for child in _editor(Ground.MAIN, Tuning.resolve().midpoint_screen).get_children():
		names.append(child.name)
	assert_array(names).contains(["Start"])
	assert_array(names).is_equal(["Background", "BackDecos", "Walls", "MidDecos", "Pieces", "Start", "Station", "Foes", "FrontDecos", "AnimDecos", "Currents", "Triggers"])


func test_the_children_of_a_layer_are_the_list_in_order() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var screen := Ground.main().screens[6]
	var layer := _deco_layer(editor, "MidDecos")
	assert_int(layer.get_child_count()).is_equal(screen.mid_decos.size())
	for i in screen.mid_decos.size():
		var node := layer.get_child(i) as ScreenEditorDeco
		assert_int(node.slot).is_equal(screen.mid_decos[i].slot)
		assert_vector(node.position).is_equal(Vector2(screen.mid_decos[i].pos))      # window pixels, as in the file
		assert_bool(node.mirrored).is_equal(screen.mid_decos[i].flag)


func test_walls_show_the_zone_atlas_and_the_invisible_wall_has_its_own_tile() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var walls := editor.get_node("Walls") as TileMapLayer
	var screen := Ground.main().screens[6]
	var zone_source := Catalog.zone(Ground.main().zone).tile_source_id
	var invisible := 0
	for i in ScreenData.TILE_BYTES:
		var cell := Vector2i(i % ScreenData.TILE_COLUMNS, i / ScreenData.TILE_COLUMNS)
		if screen.tiles[i] == 0x40:
			invisible += 1
			assert_int(walls.get_cell_source_id(cell)).is_equal(INVISIBLE)
		elif screen.tiles[i] & 0xC0 == 0x40:
			assert_int(walls.get_cell_source_id(cell)).is_equal(zone_source)
	assert_int(invisible).is_greater(0)


func test_currents_go_to_the_currents_layer() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var currents := editor.get_node("Currents") as TileMapLayer
	var screen := Ground.main().screens[6]
	var expected := 0
	for byte in screen.tiles:
		if byte & 0xC0 == 0x80:
			expected += 1
	assert_int(currents.get_used_cells().size()).is_equal(expected)
	for cell in currents.get_used_cells():
		assert_int(currents.get_cell_source_id(cell)).is_equal(TileCodec.CURRENTS_SOURCE)


func test_the_station_stands_on_the_first_and_last_screen_only() -> void:
	assert_int(_editor(Ground.MAIN, 0).get_node("Station").get_child_count()).is_greater(0)
	assert_int(_editor(Ground.MAIN, 11).get_node("Station").get_child_count()).is_greater(0)
	assert_int(_editor(Ground.MAIN, 4).get_node("Station").get_child_count()).is_equal(0)
	assert_bool(_editor(Ground.MAIN, 4).get_node("Station").owner == null).is_true()


# --- painting tiles ---------------------------------------------------------------------------------------------------

func test_painting_a_wall_changes_the_byte() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var walls := editor.get_node("Walls") as TileMapLayer
	var zone_source := Catalog.zone(Ground.main().zone).tile_source_id
	walls.set_cell(Vector2i(5, 5), zone_source, Vector2i(3, 2))                    # cell 19 of the atlas
	var built := editor.build()
	assert_array(built.problems).is_empty()
	assert_int(built.screen.tiles[5 * ScreenData.TILE_COLUMNS + 5]).is_equal(0x40 | 19)
	walls.set_cell(Vector2i(6, 5), INVISIBLE, Vector2i.ZERO)
	assert_int(editor.build().screen.tiles[5 * ScreenData.TILE_COLUMNS + 6]).is_equal(0x40)
	walls.erase_cell(Vector2i(5, 5))
	assert_int(editor.build().screen.tiles[5 * ScreenData.TILE_COLUMNS + 5]).is_equal(0)


func test_painting_a_current_changes_the_byte() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var currents := editor.get_node("Currents") as TileMapLayer
	currents.set_cell(Vector2i(10, 3), TileCodec.CURRENTS_SOURCE, Vector2i(4, 2))   # direction 4, strength 2
	var built := editor.build()
	assert_array(built.problems).is_empty()
	assert_int(built.screen.tiles[3 * ScreenData.TILE_COLUMNS + 10]).is_equal(0x80 | 2 << 3 | 4)


func test_a_tile_of_another_zone_is_refused_not_converted() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var other_zone := (Catalog.zone(Ground.main().zone).tile_source_id + 1) % TileCodec.ZONE_SOURCE_COUNT
	(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(4, 4), other_zone, Vector2i(1, 1))
	var built := editor.build()
	assert_int(built.problems.size()).is_equal(1)
	assert_str(built.problems[0]).contains("another zone").contains("Walls cell (4, 4)")
	assert_int(built.screen.tiles[4 * ScreenData.TILE_COLUMNS + 4]).is_equal(0)       # left empty, not guessed


func test_a_current_in_walls_and_a_wall_in_currents_are_refused() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var zone_source := Catalog.zone(Ground.main().zone).tile_source_id
	(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(1, 1), TileCodec.CURRENTS_SOURCE, Vector2i(0, 0))
	(editor.get_node("Currents") as TileMapLayer).set_cell(Vector2i(2, 2), zone_source, Vector2i(1, 0))
	var text := "\n".join(editor.build().problems)
	assert_str(text).contains("Walls cell (1, 1) is a current arrow")
	assert_str(text).contains("Currents cell (2, 2) is a wall tile")


func test_a_cell_that_is_wall_and_current_is_a_conflict() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var zone_source := Catalog.zone(Ground.main().zone).tile_source_id
	(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(8, 8), zone_source, Vector2i(2, 0))
	(editor.get_node("Currents") as TileMapLayer).set_cell(Vector2i(8, 8), TileCodec.CURRENTS_SOURCE, Vector2i(1, 1))
	var built := editor.build()
	assert_int(built.problems.size()).is_equal(1)
	assert_str(built.problems[0]).contains("cell (8, 8) has a wall AND a current")


func test_cells_outside_the_screen_are_refused() -> void:
	var editor := _editor(Ground.MAIN, 6)
	(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(38, 0), Catalog.zone(Ground.main().zone).tile_source_id, Vector2i(1, 0))
	(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(0, -1), Catalog.zone(Ground.main().zone).tile_source_id, Vector2i(1, 0))
	assert_int(editor.build().problems.size()).is_equal(2)
	assert_str(editor.build().problems[0]).contains("outside the 38 x 18 screen")


func test_an_alternative_tile_is_refused() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var tile_set := (editor.get_node("Walls") as TileMapLayer).tile_set
	var source := tile_set.get_source(Catalog.zone(Ground.main().zone).tile_source_id) as TileSetAtlasSource
	source.create_alternative_tile(Vector2i(1, 0), 5)
	(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(3, 3), source_id_of(editor), Vector2i(1, 0), 5)
	assert_str("\n".join(editor.build().problems)).contains("alternative tile")
	source.remove_alternative_tile(Vector2i(1, 0), 5)


func source_id_of(editor: ScreenEditor) -> int:
	return Catalog.zone(Ground.main().zone).tile_source_id


func test_many_tile_problems_are_summed_up() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var other_zone := (Catalog.zone(Ground.main().zone).tile_source_id + 1) % TileCodec.ZONE_SOURCE_COUNT
	for x in 20:
		(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(x, 0), other_zone, Vector2i(1, 1))
	var built := editor.build()
	assert_int(built.problems.size()).is_equal(ScreenEditor.MAX_PROBLEMS_SHOWN + 1)
	assert_str(built.problems[-1]).contains("and 12 more")


# --- the grid ------------------------------------------------------------------------------------------------------------

func test_decos_snap_to_the_grid_of_the_original() -> void:
	var editor := _editor(Ground.MAIN, 6, SECTORS, true)
	var deco := _deco_layer(editor, "MidDecos").get_child(0) as ScreenEditorDeco
	deco.position = Vector2(101, 59)
	assert_vector(deco.position).is_equal(Vector2(100, 60))                       # x / 4, y / 2
	deco.position = Vector2(102.5, 59.4)
	assert_vector(deco.position).is_equal(Vector2(104, 60))
	assert_array(deco.to_record().problems()).is_empty()


func test_anim_decos_pieces_and_triggers_snap_too() -> void:
	var editor := _editor(Ground.MAIN, 6, SECTORS, true)
	var anim := _deco_layer(editor, "AnimDecos").get_child(0) as ScreenEditorAnimDeco
	anim.position = Vector2(51, 33)
	assert_vector(anim.position).is_equal(Vector2(52, 34))
	var trigger := _deco_layer(editor, "Triggers").get_child(0) as ScreenEditorTrigger
	trigger.position = Vector2(51, 33)
	assert_vector(trigger.position).is_equal(Vector2(52, 34))
	var piece_editor := _editor(Ground.MAIN, 6, SECTORS, true)
	var piece := _deco_layer(piece_editor, "Pieces").get_child(0) as ScreenEditorPiece
	piece.position = Vector2(101, 59)
	assert_vector(piece.position).is_equal(Vector2(102, 60))                      # x / 2, y / 2
	var start := _editor(Ground.MAIN, Tuning.resolve().midpoint_screen, SECTORS, true).get_node("Start") as ScreenEditorStart
	start.position = Vector2(101, 59)
	assert_vector(start.position).is_equal(Vector2(102, 60))


# --- decos, anim decos, triggers ---------------------------------------------------------------------------------------

func test_editing_a_deco_trigger_and_anim_deco_changes_the_record() -> void:
	var editor := _editor(Ground.MAIN, 6, SECTORS, true)
	var deco := _deco_layer(editor, "BackDecos").get_child(0) as ScreenEditorDeco
	deco.slot = 5
	deco.mirrored = true
	var trigger := _deco_layer(editor, "Triggers").get_child(0) as ScreenEditorTrigger
	trigger.test_nibble = 3
	trigger.armed = false
	var anim := _deco_layer(editor, "AnimDecos").get_child(0) as ScreenEditorAnimDeco
	anim.start_cursor = 2
	var built := editor.build()
	editor.refresh()
	assert_array(built.problems).is_empty()
	assert_int(built.screen.bg_decos[0].slot).is_equal(5)
	assert_bool(built.screen.bg_decos[0].flag).is_true()
	assert_int(built.screen.triggers[0].flags & 0x8F).is_equal(3)                    # not armed, nibble 3
	assert_int(built.screen.anim_decos[0].start_cursor).is_equal(2)
	assert_str(editor.status).contains("there is no original")


func test_the_order_of_the_children_is_the_order_of_the_list() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var layer := _deco_layer(editor, "MidDecos")
	var first := layer.get_child(0)
	var second := layer.get_child(1)
	layer.move_child(first, 1)
	var built := editor.build()
	assert_int(built.screen.mid_decos[0].slot).is_equal((second as ScreenEditorDeco).slot)
	assert_int(built.screen.mid_decos[1].slot).is_equal((first as ScreenEditorDeco).slot)


func test_a_duplicated_deco_is_a_new_list_entry() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var layer := _deco_layer(editor, "FrontDecos")
	var before := editor.build().screen.fg_decos.size()
	var copy := (layer.get_child(0) as ScreenEditorDeco).duplicate()
	layer.add_child(copy)
	assert_int(editor.build().screen.fg_decos.size()).is_equal(before + 1)


func test_a_wrong_kind_of_node_in_a_layer_is_a_problem() -> void:
	var editor := _editor(Ground.MAIN, 6)
	_deco_layer(editor, "BackDecos").add_child(ScreenEditorTrigger.new())
	var built := editor.build()
	assert_int(built.problems.size()).is_equal(1)
	assert_str(built.problems[0]).contains("BackDecos/").contains("is not a ScreenEditorDeco")


func test_the_limits_of_the_original_are_explained() -> void:
	var editor := _editor(Ground.MAIN, 6)
	var layer := _deco_layer(editor, "BackDecos")
	for i in 256:
		layer.add_child(ScreenEditorDeco.new())
	var text := "\n".join(editor.build().problems)
	assert_str(text).contains("255 is the most")
	assert_str(text).contains("a record holds 1280")


func test_the_trigger_rule_is_shown_in_words() -> void:
	var text := ScreenEditorTrigger.describe_nibble(8)
	assert_str(text).contains("x range")
	var always := ScreenEditorTrigger.describe_nibble(0)
	assert_str(always).contains("fires at once")
	assert_int(always.length()).is_greater(10)


func test_a_slot_without_a_picture_is_flagged() -> void:
	var editor := _editor(Ground.MAIN, 6, SECTORS, true)
	var deco := _deco_layer(editor, "BackDecos").get_child(0) as ScreenEditorDeco
	deco.slot = 127
	assert_int(deco._get_configuration_warnings().size()).is_greater(0)


# --- pieces and the start --------------------------------------------------------------------------------------------------

func test_a_piece_can_be_moved_to_another_screen_and_the_sector_remembers() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var editor := _editor(Ground.MAIN, 6, dir)
	var piece := _deco_layer(editor, "Pieces").get_child(0) as ScreenEditorPiece
	var index := piece.piece_index
	piece.move_to_screen = 4
	piece.position = Vector2(100, 102)
	var built := editor.build()
	assert_array(built.problems).is_empty()
	assert_int(built.pieces[index].screen).is_equal(4)
	assert_vector(built.pieces[index].pos).is_equal(Vector2i(100, 102))
	assert_bool(editor.save_screen()).is_true()
	var sector := ResourceLoader.load(ScreenFile.sector_path(dir, Ground.MAIN), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	assert_int(sector.pieces[index].screen).is_equal(4)
	assert_vector(sector.pieces[index].pos).is_equal(Vector2i(100, 102))
	assert_bool(editor.is_dirty()).is_false()
	# the committed sector is untouched, and the moved piece now belongs to screen 4
	assert_int(Ground.main().pieces[index].screen).is_equal(6)
	assert_int(_editor(Ground.MAIN, 4, dir).get_node("Pieces").get_child_count()).is_greater(0)


func test_a_piece_marker_the_sector_does_not_know_yet_is_a_problem_until_the_sector_has_taken_it() -> void:
	# deleting and duplicating markers changes the sector (test_screen_editor_markers.gd); until the editor has run
	# `sync_with_markers` the nodes and the sector disagree, and that is reported, not saved
	var editor := _editor(Ground.MAIN, 6)
	var layer := _deco_layer(editor, "Pieces")
	var piece := layer.get_child(0) as ScreenEditorPiece
	layer.remove_child(piece)
	assert_str("\n".join(editor.build().problems)).contains("has no marker on this screen")
	piece.owner = null
	layer.add_child(piece)
	layer.add_child(piece.duplicate())
	assert_str("\n".join(editor.build().problems)).contains("appears twice")
	piece.piece_index = 99
	assert_str("\n".join(editor.build().problems)).contains("the sector has no piece 99")


func test_the_respawn_point_is_on_the_midpoint_screen() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var editor := _editor(Ground.MAIN, Tuning.resolve().midpoint_screen, dir)
	var start := editor.get_node("Start") as ScreenEditorStart
	assert_vector(start.pixel_position()).is_equal(Ground.main().start_pos)
	assert_int(start.start_frame).is_equal(Ground.main().start_frame)
	start.position = Vector2(80, 70)
	start.start_frame = 2
	assert_bool(editor.save_screen()).is_true()
	var sector := ResourceLoader.load(ScreenFile.sector_path(dir, Ground.MAIN), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	assert_vector(sector.start_pos).is_equal(Vector2i(80, 70))
	assert_int(sector.start_frame).is_equal(2)


func test_there_is_no_start_node_on_other_screens() -> void:
	assert_bool(_editor(Ground.MAIN, Tuning.resolve().midpoint_screen + 1).get_node_or_null("Start") == null).is_true()


# --- saving ------------------------------------------------------------------------------------------------------------------

func test_saving_without_a_change_leaves_both_files_byte_identical() -> void:
	for pair in [[Ground.MAIN, 6], [Ground.MAIN, Tuning.resolve().midpoint_screen], [Ground.MAIN, 0], [Ground.LEDGE, 2], [Ground.MAP, 9], [Ground.FINALE, 5], [Ground.TANGLE, 3]]:            # screens with everything, a tunnel, pieces, the respawn screen
		var dir := _temp_copy(pair[0])
		var editor := _editor(pair[0], pair[1], dir)
		var screen_before := FileAccess.get_file_as_bytes(ScreenFile.screen_path(dir, pair[0], pair[1]))
		var sector_before := FileAccess.get_file_as_bytes(ScreenFile.sector_path(dir, pair[0]))
		assert_bool(editor.is_dirty()).is_false()
		assert_bool(editor.save_screen()).override_failure_message("sector %d screen %d: %s" % [pair[0], pair[1], editor.status]).is_true()
		assert_bool(FileAccess.get_file_as_bytes(ScreenFile.screen_path(dir, pair[0], pair[1])) == screen_before).override_failure_message("sector %d screen %d: the screen file changed" % [pair[0], pair[1]]).is_true()
		assert_bool(FileAccess.get_file_as_bytes(ScreenFile.sector_path(dir, pair[0])) == sector_before).override_failure_message("sector %d: the sector file changed" % pair[0]).is_true()


func test_a_saved_change_reads_back_and_the_status_says_so() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var editor := _editor(Ground.MAIN, 5, dir, true)
	assert_str(editor.status).contains("your own: there is no original to compare with").contains("nothing to save").contains("/ 1280 bytes")
	var walls := editor.get_node("Walls") as TileMapLayer
	walls.set_cell(Vector2i(3, 9), Catalog.zone(Ground.main().zone).tile_source_id, Vector2i(2, 0))
	editor.refresh()
	assert_bool(editor.is_dirty()).is_true()
	assert_str(editor.status).contains("unsaved changes").contains("there is no original")
	assert_bool(editor.save_screen()).is_true()
	assert_str(editor.status).contains("nothing to save").contains("there is no original")
	var saved := ResourceLoader.load(ScreenFile.screen_path(dir, Ground.MAIN, 5), "", ResourceLoader.CACHE_MODE_IGNORE) as ScreenData
	assert_int(saved.tiles[9 * ScreenData.TILE_COLUMNS + 3]).is_equal(0x42)
	assert_int(saved.original_sector).is_equal(-1)                                  # (dev's screens come from no original)
	assert_int(saved.original_screen).is_equal(-1)
	assert_array(saved.validate()).is_empty()
	# only the committed copy stays what it was
	assert_int(Ground.main().screens[5].tiles[9 * ScreenData.TILE_COLUMNS + 3]).is_not_equal(0x42)


func test_nothing_is_written_while_there_are_problems() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var editor := _editor(Ground.MAIN, 5, dir)
	var path := ScreenFile.screen_path(dir, Ground.MAIN, 5)
	var before := FileAccess.get_file_as_bytes(path)
	(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(0, 0), (Catalog.zone(Ground.main().zone).tile_source_id + 1) % 5, Vector2i(1, 1))
	editor.refresh()
	assert_str(editor.status).contains("CAN NOT BE SAVED")
	assert_bool(editor.save_screen()).is_false()
	assert_array(FileAccess.get_file_as_bytes(path)).is_equal(before)
	assert_int(editor._get_configuration_warnings().size()).is_greater(0)


func test_revert_brings_back_the_saved_screen() -> void:
	var editor := _editor(Ground.MAIN, 5)
	(editor.get_node("Walls") as TileMapLayer).set_cell(Vector2i(3, 9), Catalog.zone(Ground.main().zone).tile_source_id, Vector2i(2, 0))
	assert_bool(editor.is_dirty()).is_true()
	editor.reload()
	assert_bool(editor.is_dirty()).is_false()
	assert_array(editor.build().screen.encode()).is_equal(Ground.main().screens[5].encode())


func test_a_missing_screen_is_reported_not_crashed_on() -> void:
	var editor := _editor(Ground.MAIN, 5, "user://no_such_folder")
	assert_str(editor.load_error).contains("is not there")
	assert_str(editor.status).contains("is not there")
	assert_bool(editor.save_screen()).is_false()


# --- the scene file ------------------------------------------------------------------------------------------------------------

func test_saving_the_scene_writes_no_screen_data() -> void:
	var editor := _editor(Ground.MAIN, 6, SECTORS, true)
	editor.owner = null
	var full := PackedScene.new()
	full.pack(editor)
	assert_int(full.get_state().get_node_count()).is_greater(10)                         # with owners, the nodes would be saved
	editor.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var bare := PackedScene.new()
	bare.pack(editor)
	assert_int(bare.get_state().get_node_count()).is_equal(1)                           # just the root: sector and screen
	editor.notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	assert_object(editor.get_node("Walls").owner).is_same(editor)
	assert_object(_deco_layer(editor, "BackDecos").get_child(0).owner).is_same(editor)


## A screen editor scene that is open in a background tab of the editor (restored with the session) is not in the tree, so it
## never loaded: `build()` of it is an empty screen. The plugin asks every open one to save on Ctrl+S; it used to write that
## empty screen over the real file.
func test_an_editor_that_never_loaded_is_not_dirty_and_writes_nothing() -> void:
	var dir := _temp_copy(Ground.MAIN)
	var path := ScreenFile.screen_path(dir, Ground.MAIN, 1)
	var before := FileAccess.get_file_as_bytes(path)
	var editor := auto_free(ScreenEditor.new()) as ScreenEditor        # no reload(): like a scene in a background tab
	editor.data_dir = dir
	editor.sector = Ground.MAIN
	editor.screen = 1
	assert_bool(editor.is_dirty()).is_false()
	assert_bool(editor.save_screen()).is_false()
	assert_bool(FileAccess.get_file_as_bytes(path) == before).is_true()


func test_the_template_scene_is_a_bare_root() -> void:
	var root := (load("res://addons/screen_editor/screen_editor.tscn") as PackedScene).instantiate()
	assert_bool(root is ScreenEditor).is_true()
	assert_int(root.get_child_count()).is_equal(0)
	root.free()


# --- the plugin's helpers ------------------------------------------------------------------------------------------------------

func test_the_screen_is_found_from_the_file_path() -> void:
	var screen := ScreenData.new()
	screen.take_over_path(DevPack.SECTORS_DIR + "/sector_07/screen_03.tres")
	assert_vector(ScreenEditorPlugin.screen_of(screen)).is_equal(Vector2i(7, 3))
	var own := ScreenData.new()                                                      # (a designer's sector lives in the project)
	own.take_over_path(Catalog.SECTORS_DIR + "/sector_40/screen_11.tres")
	assert_vector(ScreenEditorPlugin.screen_of(own)).is_equal(Vector2i(40, 11))
	var other := ScreenData.new()
	assert_vector(ScreenEditorPlugin.screen_of(other)).is_equal(Vector2i(-1, -1))
	assert_vector(ScreenEditorPlugin.screen_of(auto_free(Node.new()))).is_equal(Vector2i(-1, -1))
	assert_vector(ScreenEditorPlugin.screen_of(Ground.main())).is_equal(Vector2i(-1, -1))
	assert_vector(ScreenEditorPlugin.screen_of(Ground.main().screens[4])).is_equal(Vector2i(Ground.MAIN, 4))


# --- sectors of the designers' own ---------------------------------------------------------------------------------------------

const OWN := "user://screen_editor_test_own"


## A scratch folder with the template sector `index` in it (what "New sector..." makes), and `Catalog.sectors_dir` pointing at it.
func _own_sector(index: int) -> String:
	PackFiles.remove_tree(OWN)
	DirAccess.make_dir_recursive_absolute(OWN)
	var made := SectorFactory.new_from_template(index, 0, 0, OWN)
	assert_bool(made.ok()).override_failure_message(made.error).is_true()
	return OWN


func test_a_sector_of_the_designers_own_says_it_has_no_original_instead_of_a_missing_fixture() -> void:
	var dir := _own_sector(40)
	var editor := _editor(40, 0, dir, true)
	assert_str(editor.status).contains("Sector 40, screen 0").contains("sector 40 is your own: there is no original to compare with")
	assert_str(editor.status).not_contains("screens.json is missing")
	PackFiles.remove_tree(OWN)


func test_the_edit_screen_dialog_offers_every_sector_there_is() -> void:
	assert_int(ScreenEditorPlugin.sector_limit()).is_equal(Catalog.last_sector())
	var dir := _own_sector(40)
	Catalog.sectors_dir = dir
	assert_int(ScreenEditorPlugin.sector_limit()).is_equal(40)
	_own_sector_more(41)
	assert_int(ScreenEditorPlugin.sector_limit()).is_equal(41)          # a sector made later is offered at once: the limit is asked when the dialog opens
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	PackFiles.remove_tree(OWN)


func _own_sector_more(index: int) -> void:
	var made := SectorFactory.new_from_template(index, 0, 0, OWN)
	assert_bool(made.ok()).override_failure_message(made.error).is_true()
