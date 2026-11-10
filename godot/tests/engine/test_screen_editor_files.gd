class_name TestScreenEditorFiles
extends GdUnitTestSuite
## Teaches: why the screen editor writes its own files. The committed `screen_MM.tres` / `sector_NN.tres` come from the importer
## (Python); `ScreenFile` (GDScript) must write the SAME text, or a screen opened and saved without a change would show up
## in `git diff`. These tests compare every committed file with what `ScreenFile` makes of the loaded resources, and look at what
## the editor's patch of the sector file may touch. (Also: `ResourceSaver` is not used on purpose, see `ScreenFile`.)

const SECTORS := DevPack.SECTORS_DIR


func test_every_committed_screen_file_is_what_the_editor_writes() -> void:
	var problems: Array[String] = []
	for s in Ground.clean_sectors():
		for m in Catalog.SCREENS_PER_SECTOR:
			var path := ScreenFile.screen_path(SECTORS, s, m)
			var screen := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ScreenData
			if ScreenFile.screen_text(screen) != FileAccess.get_file_as_string(path):
				problems.append(path)
	assert_array(problems).override_failure_message("ScreenFile.screen_text differs from the generator's text for: " + ", ".join(problems)).is_empty()


func test_an_unchanged_sector_file_comes_back_unchanged() -> void:
	for s in Ground.clean_sectors():
		var path := ScreenFile.sector_path(SECTORS, s)
		var sector := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
		var text := FileAccess.get_file_as_string(path)
		var result := ScreenFile.sector_text(text, sector.pieces, sector.start_pos, sector.start_frame)
		assert_str(result.error).is_empty()
		assert_bool(result.text == text).override_failure_message("sector %d changed by an empty patch" % s).is_true()


func test_a_moved_piece_and_a_new_respawn_point_change_exactly_their_lines() -> void:
	var path := ScreenFile.sector_path(SECTORS, Ground.EDIT)
	var sector := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	var text := FileAccess.get_file_as_string(path)
	var pieces: Array[PieceData] = []
	for piece in sector.pieces:
		var copy := PieceData.new()
		copy.screen = piece.screen
		copy.pos = piece.pos
		copy.is_canister = piece.is_canister
		pieces.append(copy)
	pieces[2].screen = 7
	pieces[2].pos = Vector2i(100, 102)
	var result := ScreenFile.sector_text(text, pieces, Vector2i(70, 66), 2)
	assert_str(result.error).is_empty()
	var before := text.split("\n")
	var after := (result.text as String).split("\n")
	assert_int(after.size()).is_equal(before.size())
	var changed: Array[String] = []
	for i in before.size():
		if before[i] != after[i]:
			changed.append("%s -> %s" % [before[i], after[i]])
	assert_int(changed.size()).is_equal(4)
	assert_str("\n".join(changed)).contains("screen = 7").contains("pos = Vector2i(100, 102)").contains("start_pos = Vector2i(70, 66)").contains("start_frame = 2")


func test_the_patch_refuses_a_different_number_of_pieces() -> void:
	var path := ScreenFile.sector_path(SECTORS, Ground.EDIT)
	var sector := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	var fewer: Array[PieceData] = [sector.pieces[0]]
	var result := ScreenFile.sector_text(FileAccess.get_file_as_string(path), fewer, sector.start_pos, sector.start_frame)
	assert_str(result.error).contains("pieces")
	assert_str(result.text).is_empty()


## The writer knows the properties of the four screen resources by name. A new `@export` there would be dropped silently
## by an editor save, so this fails first and tells the next student to teach `ScreenFile` about it.
func test_the_writer_knows_every_stored_property_of_the_screen_resources() -> void:
	var expected := {
		"ScreenData": ["original_sector", "original_screen", "tiles", "bg_decos", "mid_decos", "fg_decos", "anim_decos", "triggers", "stale_offset", "stale_bytes"],
		"DecoPlacement": ["pos", "slot", "flag"],
		"AnimDecoData": ["pos", "frames", "size", "start_cursor"],
		"MathTriggerData": ["pos", "slot", "armed", "rearm_on_enter", "test_nibble", "other_bits"],
	}
	var objects := {"ScreenData": ScreenData.new(), "DecoPlacement": DecoPlacement.new(), "AnimDecoData": AnimDecoData.new(), "MathTriggerData": MathTriggerData.new()}
	for kind: String in expected:
		var found: Array[String] = []
		for property in (objects[kind] as Object).get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
				found.append(property.name)
		found.sort()
		var wanted: Array = expected[kind].duplicate()
		wanted.sort()
		assert_array(found).override_failure_message("%s: ScreenFile writes %s but the resource stores %s" % [kind, wanted, found]).is_equal(wanted)
