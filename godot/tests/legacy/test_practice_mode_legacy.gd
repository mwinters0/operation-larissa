class_name TestPracticeModeLegacy
extends GdUnitTestSuite
## Which of the ORIGINAL's problem types a practice set can draw at each level follows its stored record counts (do_math_practice 0x42d817).
## The sets and the scoring themselves are tested on dev in tests/engine/test_practice_mode.gd.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_all_set_lists_every_type_of_the_level_in_order() -> void:
	# record counts of the stored data per level (types 1-33 that have problems): 19, 28, 28, 24
	var expected := [19, 28, 28, 24]
	for level in 4:
		assert_int(PracticeSet.build(PracticeSet.Kind.ALL, level).size()).is_equal(expected[level])


func test_the_level_filter_follows_the_stored_record_counts() -> void:
	assert_bool(PracticeSet.is_available(2, 0)).is_false()        # the speed graph has no whole-number problems
	assert_bool(PracticeSet.is_available(2, 1)).is_true()
	assert_bool(PracticeSet.is_available(12, 1)).is_false()
	assert_bool(PracticeSet.is_available(12, 0)).is_true()
