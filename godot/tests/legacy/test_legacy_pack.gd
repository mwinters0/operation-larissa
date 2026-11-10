class_name TestLegacyPack
extends GdUnitTestSuite
## Teaches: a program that is built to show content it does not ship says so plainly. The legacy pack (the original game) is made by the importer
## from the player's own copy (docs/play/LEGACY.md), so `LegacyPack` is how the rest of the project asks whether it is there: the main scene
## and the test suites. This suite runs with and without the game, which is the point.


func test_the_game_is_there_exactly_when_none_of_its_witnesses_is_missing() -> void:
	assert_bool(LegacyPack.present()).is_equal(LegacyPack.missing().is_empty())
	assert_str(LegacyPack.problem()).is_equal("" if LegacyPack.present() else LegacyPack.problem(LegacyPack.missing()))


func test_a_missing_file_is_named_and_the_sentence_says_what_to_do() -> void:
	var wanted: Array[String] = ["res://project.godot", "res://nothing/here.png", "res://nothing/there.png"]
	var lost := LegacyPack.missing(wanted)
	assert_array(lost).contains_exactly(["res://nothing/here.png", "res://nothing/there.png"])
	var text := LegacyPack.problem(lost)
	assert_str(text).contains("res://nothing/here.png").contains("2 of its files")
	assert_str(text).contains("run the importer on your copy of the game").contains("import_all.py").contains("--import")


func test_nothing_is_missing_from_a_list_of_files_that_are_there() -> void:
	var wanted: Array[String] = ["res://project.godot", "res://tests/legacy/legacy_pack.gd"]
	assert_array(LegacyPack.missing(wanted)).is_empty()
	assert_str(LegacyPack.problem(LegacyPack.missing(wanted))).is_empty()


func test_the_witnesses_are_paths_of_the_importers_outputs() -> void:
	for path in LegacyPack.WITNESSES:
		assert_bool(path.begins_with(LegacyPack.ROOT + "data/") or path.begins_with(LegacyPack.ROOT + "assets/")).is_true()


func test_the_legacy_pack_has_one_root_and_every_path_is_made_from_it() -> void:
	assert_str(LegacyPack.ROOT).is_equal("res://packs/legacy/")
	assert_str(LegacyPack.path("data/zones.tres")).is_equal("res://packs/legacy/data/zones.tres")
	assert_str(LegacyPack.root()).is_equal("res://packs/legacy")
	for path in LegacyPack.WITNESSES:
		assert_bool(path.begins_with(LegacyPack.ROOT)).override_failure_message("%s is not under %s" % [path, LegacyPack.ROOT]).is_true()


func test_the_folder_of_the_legacy_pack_is_a_complete_pack_like_any_other() -> void:
	if not LegacyPack.present():
		return
	var pack := Pack.open(LegacyPack.root())
	assert_array(pack.errors).is_empty()
	assert_str(pack.id).is_equal(LegacyPack.ID)
	assert_str(pack.base).is_equal(&"")                                          # no base: nothing is under it
	assert_array(Packs.resolve(pack).packs).has_size(1)
	assert_object(Packs.resolve(pack).fallback).is_null()


func test_the_legacy_id_is_not_reserved_and_base_true_is_gone() -> void:
	var shelf := PackShelf.new(&"fine")
	shelf.write_json("pack.json", {"id": "fine", "title": "Fine", "version": "1", "base": true})
	assert_str("\n".join(Pack.open(shelf.root).errors)).contains("\"base\" must be a string")
	shelf.write_json("pack.json", {"id": "legacy", "title": "Another legacy", "version": "1", "base": "dev"})
	assert_array(Pack.open(shelf.root).errors).is_empty()                        # (an ordinary id: it is the folder of the project that wins when both exist)
	shelf.remove()


func test_the_suite_plays_the_project_folder_or_with_the_switch_the_data_form_export() -> void:
	if not LegacyPack.present():
		return
	assert_str(LegacyPack.export_error()).is_empty()
	assert_str(Packs.chosen().id).is_equal(LegacyPack.ID)
	if LegacyPack.as_data_asked():
		assert_bool(LegacyPack.plays_the_export()).is_true()
		assert_str(Packs.chosen().root).is_equal(LegacyPack.AS_DATA_DIR + "/legacy")
		assert_str(Packs.chosen().base).is_equal(&"")
	else:
		assert_str(Packs.chosen().root).is_equal(LegacyPack.root())
		assert_bool(Packs.chosen().trusted).is_true()
