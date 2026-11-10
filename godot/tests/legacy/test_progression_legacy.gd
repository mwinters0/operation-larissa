class_name TestProgressionLegacy
extends GdUnitTestSuite
## Teaches: the progress words of the original's two games, the old formulas as tables (DESIGN 3.8 and 3.6; the rest: tests/engine/test_progression.gd).


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_voyager_walks_through_the_sectors_and_jumps_to_the_finale() -> void:
	var progress := Progression.start_progress(0)
	for sector in 14:
		assert_int(Progression.sector_of(progress)).is_equal(sector)
		progress = Progression.next_progress(progress | 1)       # the midpoint flag is cleared on the way
		assert_bool(Progression.past_midpoint(progress)).is_false()
	assert_int(progress).is_equal(0x1C)                         # sector 14, the last ordinary one
	assert_int(Progression.next_progress(progress)).is_equal(0x3C)
	assert_bool(Progression.is_finale(0x3C)).is_true()
	assert_bool(Progression.is_finale(0x1C)).is_false()


func test_expert_starts_at_0x1e_and_ends_at_0x3e() -> void:
	assert_int(Progression.start_progress(1)).is_equal(0x1E)
	assert_int(Progression.next_progress(0x1E)).is_equal(0x20)
	assert_int(Progression.next_progress(0x3A)).is_equal(0x3E)


func test_game_and_zone_of_a_progress_word() -> void:
	var cases := [   # progress, game, zone
		[0, 0, 0], [4, 0, 0], [6, 0, 1], [0x1C, 0, 4], [0x1E, 1, 0], [0x3A, 1, 4], [0x3C, 0, 5], [0x3E, 1, 6]]
	for c: Array in cases:
		assert_int(Progression.game_of(c[0])).is_equal(c[1])
		assert_int(Progression.zone_of(c[0])).is_equal(c[2])


func test_default_educational_level_per_game_and_zone() -> void:
	var voyager := [0, 0, 1, 1, 1]
	var expert := [2, 2, 2, 3, 3]
	for zone in 5:
		assert_int(Progression.default_edu_level(0, zone)).is_equal(voyager[zone])
		assert_int(Progression.default_edu_level(1, zone)).is_equal(expert[zone])
	assert_int(Progression.default_edu_level(1, 6)).is_equal(3)  # a finale uses the last zone's level


