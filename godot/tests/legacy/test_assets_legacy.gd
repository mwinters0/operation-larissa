class_name TestAssetsLegacy
extends GdUnitTestSuite
## Teaches: testing a resolver from the file side (a path is compared by what follows the pack's folder, `Packs.relative`: the pack played may be the project's folder or its data-form export). Every FILE the importer wrote for the original game must be found again by the rule that turns its
## number into a path, so a renamed folder or a missing picture fails here, not on the title screen. (The names and strings side, on any pack, is in
## tests/engine/test_assets.gd.)

const UI_ROOT := LegacyPack.ROOT + "assets/ui"


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


## The folder rule of `Assets.ui_picture_path` against the folders the importer really filled.
func test_the_folder_rule_finds_every_ui_picture_where_the_importer_put_it() -> void:
	var checked := 0
	for folder in DirAccess.get_directories_at(UI_ROOT):
		for file in DirAccess.get_files_at(UI_ROOT.path_join(folder)):
			if file.ends_with(".png"):
				var number := int(file.get_basename().rsplit("_", true, 1)[1])
				assert_str(Packs.relative(Assets.ui_picture_path(number))).is_equal("assets/ui/%s/%s" % [folder, file])
				checked += 1
	assert_int(checked).is_greater(100)


func test_the_problem_art_index_finds_every_picture_of_its_own_folder() -> void:
	var checked := 0
	for folder in DirAccess.get_directories_at(LegacyPack.ROOT + "assets/problem_art"):
		for file in DirAccess.get_files_at((LegacyPack.ROOT + "assets/problem_art").path_join(folder)):
			if file.ends_with(".png"):
				assert_str(Packs.relative(Assets.problem_art_path(int(file.get_basename().rsplit("_", true, 1)[1])))).is_equal("assets/problem_art/%s/%s" % [folder, file])
				checked += 1
	assert_int(checked).is_greater(100)


func test_the_original_pictures_are_where_their_numbers_say() -> void:
	assert_str(Packs.relative(Assets.ui_picture_path(1039))).is_equal("assets/ui/title/title_sky_1039.png")     # a named picture: <name>_<number>
	assert_str(Packs.relative(Assets.ui_picture_path(1000))).is_equal("assets/ui/map/radar_map_1000.png")
	assert_str(Packs.relative(Assets.ui_picture_path(2025))).is_equal("assets/ui/story/ui_2025.png")           # nobody named it: the old name
	assert_str(Packs.relative(Assets.problem_art_path(2046))).is_equal("assets/problem_art/b116/log_scan_0_2046.png")
	assert_str(Packs.relative(Assets.problem_art_path(1780))).is_equal("assets/problem_art/single/pa_1780.png")


func test_the_original_texts_say_what_they_said() -> void:
	assert_str(Catalog.text(&"click_to_go_on")).is_equal("Click to go on.")
	assert_bool(Catalog.has_text(&"hint_4")).is_false()                  # the calculator hint has no text in the data
	assert_str(AudioService.music_for_sector(7)).is_equal(&"sector_song_2")
