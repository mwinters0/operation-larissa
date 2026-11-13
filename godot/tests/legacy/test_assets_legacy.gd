class_name TestAssetsLegacy
extends GdUnitTestSuite
## Teaches: testing a picture lookup from the file side. Every picture FILE the importer wrote for the original game must be named by a row of the pack's `pictures.json`, and every row must
## answer with a picture, so a missing file or a row that names nothing fails here, not on the title screen. (The names and strings side, on any pack, is in tests/engine/test_assets.gd; the
## table against every key the data holds is `test_picture_keys_legacy.gd`.)

const PICTURE_FOLDERS: Array[String] = ["ui", "problem_art", "sprites", "tiles", "backgrounds"]


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _table() -> PictureTable:
	return Pack.open(LegacyPack.root()).picture_table()


func test_the_table_names_every_picture_file_the_importer_wrote() -> void:
	var table := _table()
	var named := {}
	for key in table.files:
		named[table.files[key]] = key
	var checked := 0
	var pack := Pack.open(LegacyPack.root())
	for folder in PICTURE_FOLDERS:
		for rel in pack.all_files():
			if rel.begins_with("assets/%s/" % folder) and rel.get_extension() == "png":
				assert_bool(named.has(rel)).override_failure_message("%s is named by no row of pictures.json" % rel).is_true()
				checked += 1
	assert_int(checked).is_greater(1000)


func test_every_row_answers_with_a_picture() -> void:
	var table := _table()
	for key in table.keys():
		assert_object(Pictures.resolve(key)).override_failure_message("%s: no picture" % key).is_not_null()


func test_the_original_pictures_are_under_their_keys() -> void:
	var table := _table()
	assert_str(table.files["ui_picture/title_sky"]).is_equal("assets/ui/title/title_sky_1039.png")        # a named picture: <name>_<number>
	assert_str(table.files["ui_picture/radar_map"]).is_equal("assets/ui/map/radar_map_1000.png")
	assert_str(table.files["ui_picture/ui_2025"]).is_equal("assets/ui/story/ui_2025.png")                  # nobody named it: the made-up name has the number
	assert_str(table.files["problem_art/log_scan_0"]).is_equal("assets/problem_art/b116/log_scan_0_2046.png")
	assert_str(table.files["problem_art/pa_1780"]).is_equal("assets/problem_art/single/pa_1780.png")
	assert_str(table.aliases["problem_art/pa_2012"]).is_equal("ui_picture/ui_2012")                         # a picture the story keeps: the problem art id is its alias
	assert_str(table.files["tile/zone0_tiles"]).is_equal("assets/tiles/zone0_tiles.png")
	assert_str(table.files["background/bg_s03_07"]).is_equal("assets/backgrounds/bg_s03_07.png")


func test_the_original_texts_say_what_they_said() -> void:
	assert_str(Catalog.text(&"click_to_go_on")).is_equal("Click to go on.")
	assert_bool(Catalog.has_text(&"hint_4")).is_false()                  # the calculator hint has no text in the data
	assert_str(AudioService.music_for_sector(7)).is_equal(&"sector_song_2")
