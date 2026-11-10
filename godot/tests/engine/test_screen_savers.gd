class_name TestScreenSavers
extends GdUnitTestSuite
## Teaches: why Ctrl+S in the Godot editor is safe for the generated data files. The editor re-saves every resource it believes was
## edited (and it believes that of every screen it has loaded); without help that rewrote `screen_MM.tres` in Godot's own text format.
## `ScreenDataSaver` and `SectorDataSaver` sit at the FRONT of `ResourceSaver`'s list (see their headers) and write the importer's
## text, or refuse. These tests register the savers exactly like `ScreenEditorPlugin._register_savers`, call `ResourceSaver.save`
## the way the editor does, and look at the bytes. Everything is written under user://, never into res://data.

const SECTORS := DevPack.SECTORS_DIR
const TEMP := "user://screen_savers_test"

var _savers: Array[ResourceFormatSaver] = []


func before_test() -> void:
	# The same call as the plugin's: the `true` puts the saver BEFORE Godot's own text saver, which would take every `.tres`.
	_savers = [ScreenDataSaver.new(), SectorDataSaver.new()]
	for saver in _savers:
		ResourceSaver.add_resource_format_saver(saver, true)
	ScreenFile.last_refusal = ""
	DirAccess.make_dir_recursive_absolute(TEMP)


func after_test() -> void:
	for saver in _savers:
		ResourceSaver.remove_resource_format_saver(saver)
	_savers.clear()
	_remove_tree(TEMP)


func _remove_tree(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(dir))
	DirAccess.remove_absolute(path)


func _load_screen(sector: int, screen: int, dir: String = SECTORS) -> ScreenData:
	return ResourceLoader.load(ScreenFile.screen_path(dir, sector, screen), "", ResourceLoader.CACHE_MODE_IGNORE) as ScreenData


## A copy of the sector file under user:// (its screens and script are still the res:// ones). Returns its path.
func _copy_sector(sector: int) -> String:
	var path := Catalog.sector_path(sector, TEMP)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_int(DirAccess.copy_absolute(Catalog.sector_path(sector, SECTORS), path)).is_equal(OK)
	return path


func _load_sector(path: String) -> SectorData:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData


# --- screens --------------------------------------------------------------------------------------------------------------

func test_every_screen_of_the_pack_is_saved_byte_for_byte_by_resource_saver() -> void:
	var path := TEMP + "/screen.tres"
	var problems: Array[String] = []
	var with_anim := 0
	for s in Ground.clean_sectors():
		for m in Catalog.SCREENS_PER_SECTOR:
			var screen := _load_screen(s, m)
			with_anim += screen.anim_decos.size()
			if ResourceSaver.save(screen, path) != OK or FileAccess.get_file_as_bytes(path) != FileAccess.get_file_as_bytes(ScreenFile.screen_path(SECTORS, s, m)):
				problems.append("sector %d screen %d" % [s, m])
			DirAccess.remove_absolute(path)
	assert_int(with_anim).override_failure_message("the animated decoration of the main sector is part of this test").is_greater(0)
	assert_array(problems).override_failure_message("saved differently from the committed file: " + ", ".join(problems)).is_empty()


func test_the_text_is_the_importers_not_godots() -> void:
	var path := TEMP + "/screen.tres"
	assert_int(ResourceSaver.save(_load_screen(Ground.MAIN, 5), path)).is_equal(OK)
	var text := FileAccess.get_file_as_string(path)
	assert_str(text).starts_with('[gd_resource type="Resource" script_class="ScreenData" format=3]')
	assert_str(text).contains("flag = false")                         # Godot leaves a default value out
	assert_bool(text.contains("uid=")).is_false()                     # and puts a uid in the header and on the scripts


func test_an_unchanged_screen_does_not_touch_an_existing_file() -> void:
	# Saving the same text again must not even touch the file (no new modification time, so no re-import and no editor reload).
	var path := TEMP + "/screen.tres"
	var screen := _load_screen(Ground.MAIN, 5)
	assert_int(ResourceSaver.save(screen, path)).is_equal(OK)
	var first := FileAccess.get_modified_time(path)
	OS.delay_msec(1100)                                                # modification times have a resolution of one second
	assert_int(ResourceSaver.save(screen, path)).is_equal(OK)
	assert_int(FileAccess.get_modified_time(path)).is_equal(first)


func test_an_edited_screen_is_saved_exactly_as_the_screen_editor_would_write_it() -> void:
	var path := TEMP + "/screen.tres"
	var screen := _load_screen(Ground.MAIN, 5)
	screen.tiles[40] = 0x41                                            # a wall tile picture 1
	screen.bg_decos[0].pos += Vector2i(8, 4)
	screen.triggers.clear()
	assert_int(ResourceSaver.save(screen, path)).is_equal(OK)
	assert_str(FileAccess.get_file_as_string(path)).is_equal(ScreenFile.screen_text(screen))
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ScreenData
	assert_int(back.tiles[40]).is_equal(0x41)
	assert_vector(back.bg_decos[0].pos).is_equal(screen.bg_decos[0].pos)
	assert_int(back.triggers.size()).is_equal(0)


## 300 decorations: more than the one-byte count and the 0x500-byte record allow.
func _overfill(screen: ScreenData) -> void:
	for i in 300:
		screen.bg_decos.append(DecoPlacement.new())


func test_a_screen_that_cannot_be_encoded_is_refused_and_the_file_stays() -> void:
	var path := TEMP + "/screen.tres"
	assert_int(ResourceSaver.save(_load_screen(Ground.MAIN, 5), path)).is_equal(OK)
	var before := FileAccess.get_file_as_bytes(path)
	var cases := {
		"tile": func(screen: ScreenData) -> void: screen.tiles[7] = 0x05,                              # not one of the tile bytes
		"grid": func(screen: ScreenData) -> void: screen.bg_decos[0].pos = Vector2i(10, 5),           # not a multiple of 4 x 2
		"size": func(screen: ScreenData) -> void: screen.tiles.resize(100),                            # not 38 x 18
		"full": _overfill,                                                                              # more than a record holds
	}
	for kind: String in cases:
		var screen := _load_screen(Ground.MAIN, 5)
		(cases[kind] as Callable).call(screen)
		ScreenFile.last_refusal = ""
		# OK on purpose: a failed save would be handed to Godot's own saver, which writes Godot's format (see ScreenFile.refuse).
		assert_int(ResourceSaver.save(screen, path)).is_equal(OK)
		assert_str(ScreenFile.last_refusal).override_failure_message("%s: not refused" % kind).contains("NOT written").contains("cannot be stored")
		assert_bool(FileAccess.get_file_as_bytes(path) == before).override_failure_message("%s: the file was changed" % kind).is_true()


func test_a_refused_screen_does_not_create_a_file() -> void:
	var path := TEMP + "/new.tres"
	var screen := ScreenData.new()                                     # no tiles at all: 0 bytes instead of 684
	ScreenFile.last_refusal = ""
	assert_int(ResourceSaver.save(screen, path)).is_equal(OK)
	assert_str(ScreenFile.last_refusal).contains("tiles: 0 bytes")
	assert_bool(FileAccess.file_exists(path)).is_false()


func test_the_savers_leave_other_paths_and_other_resources_alone() -> void:
	var saver := ScreenDataSaver.new()
	var sector_saver := SectorDataSaver.new()
	assert_bool(saver._recognize_path(ScreenData.new(), "user://a.tres")).is_true()
	assert_bool(saver._recognize_path(ScreenData.new(), "user://a.res")).is_false()        # a binary file is Godot's business
	assert_bool(saver._recognize(PieceData.new())).is_false()
	assert_bool(sector_saver._recognize(ScreenData.new())).is_false()
	assert_bool(sector_saver._recognize(SectorData.new())).is_true()
	assert_array(Array(saver._get_recognized_extensions(PieceData.new()))).is_empty()


# --- sectors --------------------------------------------------------------------------------------------------------------

func test_every_sector_of_the_pack_is_saved_byte_for_byte_by_resource_saver() -> void:
	var problems: Array[String] = []
	for s in Ground.clean_sectors():
		var path := _copy_sector(s)
		var before := FileAccess.get_file_as_bytes(path)
		var result := ResourceSaver.save(_load_sector(path), path)
		if result != OK or FileAccess.get_file_as_bytes(path) != before:
			problems.append("sector %d" % s)
	assert_array(problems).override_failure_message("changed by a save without a change: " + ", ".join(problems)).is_empty()


func test_a_moved_piece_and_respawn_point_are_written_like_the_screen_editors_patch() -> void:
	var path := _copy_sector(Ground.EDIT)
	var text := FileAccess.get_file_as_string(path)
	var sector := _load_sector(path)
	sector.pieces[2].screen = 7
	sector.pieces[2].pos = Vector2i(100, 102)
	sector.start_pos = Vector2i(70, 66)
	sector.start_frame = 2
	assert_int(ResourceSaver.save(sector, path)).is_equal(OK)
	var expected := ScreenFile.sector_text(text, sector.pieces, sector.start_pos, sector.start_frame)
	assert_str(expected.error).is_empty()
	assert_str(FileAccess.get_file_as_string(path)).is_equal(expected.text)
	assert_str(ScreenFile.last_refusal).is_empty()


func test_a_renamed_foe_label_changes_exactly_that_line() -> void:
	var path := _copy_sector(Ground.EDIT)
	var text := FileAccess.get_file_as_string(path)
	var sector := _load_sector(path)
	var old_label := sector.foes[1].hit_label
	sector.foes[1].hit_label = 'my "hit" label'                       # the quotes need the importer's escaping
	sector.foes[1].ink_label = sector.foes[0].hit_label                # several creatures may share a label
	assert_int(ResourceSaver.save(sector, path)).is_equal(OK)
	var before := text.split("\n")
	var after := FileAccess.get_file_as_string(path).split("\n")
	assert_int(after.size()).is_equal(before.size())
	var changed: Array[String] = []
	for i in before.size():
		if before[i] != after[i]:
			changed.append(after[i])
	assert_array(changed).is_equal(['hit_label = "my \\"hit\\" label"', 'ink_label = "%s"' % sector.foes[0].hit_label])
	assert_str(old_label).is_not_empty()
	var back := _load_sector(path)
	assert_str(back.foes[1].hit_label).is_equal('my "hit" label')


func test_creature_properties_and_neighbours_are_written_too() -> void:
	var path := _copy_sector(Ground.EDIT)
	var sector := _load_sector(path)
	sector.foes[0].pos += Vector2i(4, 2)
	sector.foes[0].flip = not sector.foes[0].flip
	sector.foes[0].damage += 3
	sector.foes[0].dormant = not sector.foes[0].dormant
	sector.neighbors_left[4] = 2
	assert_int(ResourceSaver.save(sector, path)).is_equal(OK)
	assert_str(ScreenFile.last_refusal).is_empty()
	var back := _load_sector(path)
	assert_vector(back.foes[0].pos).is_equal(sector.foes[0].pos)
	assert_bool(back.foes[0].flip).is_equal(sector.foes[0].flip)
	assert_int(back.foes[0].damage).is_equal(sector.foes[0].damage)
	assert_bool(back.foes[0].dormant).is_equal(sector.foes[0].dormant)
	assert_int(back.neighbors_left[4]).is_equal(2)
	assert_array(Array(back.neighbors_right)).is_equal(Array(sector.neighbors_right))
	# nothing else moved: the saved file differs from the original in 5 lines only (4 foe lines + the neighbours)
	var original := FileAccess.get_file_as_string(Catalog.sector_path(Ground.EDIT, SECTORS)).split("\n")
	var saved := FileAccess.get_file_as_string(path).split("\n")
	assert_int(saved.size()).is_equal(original.size())
	var differing := 0
	for i in original.size():
		differing += 1 if original[i] != saved[i] else 0
	assert_int(differing).is_equal(5)


func test_a_change_the_sector_saver_cannot_write_is_refused_by_name_and_nothing_is_written() -> void:
	var cases := {
		"zone": func(sector: SectorData) -> void: sector.zone = 4,
		"index": func(sector: SectorData) -> void: sector.index = 9,
		"foe_script_base": func(sector: SectorData) -> void: sector.foe_script_base += 1,
		"header_unused_3d": func(sector: SectorData) -> void: sector.header_unused_3d += 1,
		"pieces[0].is_canister": func(sector: SectorData) -> void: sector.pieces[0].is_canister = false,
		"foes[0].runtime_state": func(sector: SectorData) -> void: sector.foes[0].runtime_state = PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
		"screens": func(sector: SectorData) -> void: sector.screens[0] = sector.screens[1],
		"foe_script": func(sector: SectorData) -> void: sector.foe_script = load(Catalog.foe_path(1)) as FoeScript,
	}
	var path := _copy_sector(Ground.EDIT)
	var before := FileAccess.get_file_as_bytes(path)
	for field: String in cases:
		var sector := _load_sector(path)
		(cases[field] as Callable).call(sector)
		ScreenFile.last_refusal = ""
		assert_int(ResourceSaver.save(sector, path)).is_equal(OK)
		assert_str(ScreenFile.last_refusal).override_failure_message("%s: not refused" % field).contains("NOT written").contains(field.trim_suffix(":"))
		assert_bool(FileAccess.get_file_as_bytes(path) == before).override_failure_message("%s: the file was changed" % field).is_true()


func test_a_supported_change_is_not_written_when_an_unsupported_one_comes_with_it() -> void:
	var path := _copy_sector(Ground.EDIT)
	var before := FileAccess.get_file_as_bytes(path)
	var sector := _load_sector(path)
	sector.foes[0].start_label = "fine"
	sector.zone = 4
	assert_int(ResourceSaver.save(sector, path)).is_equal(OK)
	assert_str(ScreenFile.last_refusal).contains("zone")
	assert_bool(FileAccess.get_file_as_bytes(path) == before).is_true()


func test_a_sector_file_that_does_not_exist_is_not_created() -> void:
	var path := TEMP + "/nothing/sector_99.tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_int(ResourceSaver.save(_load_sector(Catalog.sector_path(Ground.EDIT, SECTORS)), path)).is_equal(OK)
	assert_str(ScreenFile.last_refusal).contains("can only be changed")
	assert_bool(FileAccess.file_exists(path)).is_false()


## The patch knows the properties of the sector resources by name. A new `@export` would otherwise be refused at the first save
## (never dropped), so this fails first and tells the next student what to teach `ScreenFile`.
func test_the_sector_patch_lists_match_the_stored_properties() -> void:
	var piece_properties: Array = []
	for property in PieceData.new().get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			piece_properties.append(property.name)
	var foe_properties: Array = []
	for property in FoeData.new().get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			foe_properties.append(property.name)
	var sector_properties: Array = []
	for property in SectorData.new().get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			sector_properties.append(property.name)
	assert_array(foe_properties).contains_exactly_in_any_order(ScreenFile.FOE_FIELDS + ["runtime_state"])      # runtime_state: not editable, like is_canister
	assert_array(piece_properties).contains_exactly_in_any_order(ScreenFile.PIECE_FIELDS + ["is_canister"])
	for name: String in ScreenFile.SECTOR_FIELDS:
		assert_array(sector_properties).contains([name])
