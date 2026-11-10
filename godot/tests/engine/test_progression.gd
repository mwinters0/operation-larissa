class_name TestProgression
extends GdUnitTestSuite
## Teaches: table-driven tests for pure functions (DESIGN 3.8 and 3.6).


func test_progress_packs_the_sector_and_the_midpoint_flag() -> void:
	assert_int(Progression.sector_of(0x1D)).is_equal(14)
	assert_bool(Progression.past_midpoint(0x1D)).is_true()
	assert_bool(Progression.past_midpoint(0x1C)).is_false()
	assert_int(Progression.with_midpoint(0x1C, true)).is_equal(0x1D)
	assert_int(Progression.with_midpoint(0x1D, false)).is_equal(0x1C)


func test_the_tour_walks_through_its_sectors_and_ends_at_the_finale() -> void:
	var progress := Progression.start_progress(0)
	for sector in DevPack.TOUR_SECTORS:
		assert_int(Progression.sector_of(progress)).is_equal(sector)
		progress = Progression.next_progress(progress | 1)       # the midpoint flag is cleared on the way
		assert_bool(Progression.past_midpoint(progress)).is_false()
	assert_int(progress).is_equal(DevPack.TOUR_FINALE * 2)
	assert_bool(Progression.is_finale(progress)).is_true()
	assert_bool(Progression.is_finale(DevPack.TOUR_SECTORS[-1] * 2)).is_false()
	assert_int(Progression.next_progress(progress)).is_equal(progress)     # the finale stays


func test_the_zone_of_a_progress_word_is_its_sectors_and_the_tour_has_no_old_game_number() -> void:
	for sector in DevPack.TOUR_SECTORS + [DevPack.TOUR_FINALE]:
		for flag in 2:
			assert_int(Progression.zone_of(sector * 2 + flag)).is_equal(Catalog.sector(sector).zone)
			assert_int(Progression.game_of(sector * 2 + flag)).is_equal(-1)
	assert_int(Progression.zone_of(2 * 2)).is_equal(2)               # dev's sectors 0-4 are in zones 0-4
	assert_int(Progression.game_of(2 * 200)).is_equal(-1)            # a sector of no campaign


func test_default_educational_level_comes_from_the_campaign() -> void:
	var tour := [0, 1, 1, 2, 2]                                      # the tour's own list, by zone
	for zone in 5:
		assert_int(Progression.default_edu_level(0, zone)).is_equal(tour[zone])
	assert_int(Progression.default_edu_level(0, 6)).is_equal(2)      # beyond the list: the last one


func test_midpoint_needs_screen_6_and_every_piece_before_it() -> void:
	var screens := PackedInt32Array([3, 0, 5, 6, 9])             # pieces 0..4
	assert_bool(Progression.midpoint_flag(false, 0b11111, screens, 6)).is_false()   # never was on screen 6
	assert_bool(Progression.midpoint_flag(true, 0b11000, screens, 6)).is_false()    # pieces 0-2 are missing
	assert_bool(Progression.midpoint_flag(true, 0b00111, screens, 6)).is_true()     # 3 and 4 are beyond the midpoint
	assert_bool(Progression.midpoint_flag(true, 0b00011, screens, 6)).is_false()    # piece 2 (screen 5) is missing


func test_pieces_missing_counts_the_unset_bits() -> void:
	assert_int(Progression.pieces_missing(0, 8)).is_equal(8)
	assert_int(Progression.pieces_missing(0b101, 4)).is_equal(2)
	assert_int(Progression.pieces_missing(0xFF, 8)).is_equal(0)
