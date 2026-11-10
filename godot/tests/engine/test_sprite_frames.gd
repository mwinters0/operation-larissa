class_name TestSpriteFrames
extends GdUnitTestSuite
## The "indexed SpriteFrames" pattern: animation "all", frame index == slot number. (The original's slot numbers and picture sizes are in
## `tests/legacy/test_sprite_frames_legacy.gd`.)


func test_every_foe_frame_has_a_metadata_entry() -> void:
	for zone_index in Catalog.ZONE_COUNT:
		var frame_count := Catalog.foes_frames(zone_index).get_frame_count("all")
		assert_int(SpriteMeta.for_zone(zone_index).count()).is_equal(frame_count)


func test_named_animations() -> void:
	var foes := Catalog.foes_frames(0)
	assert_int(foes.get_frame_count("ink_burst")).is_equal(7)
	assert_float(foes.get_animation_speed("ink_burst")).is_equal_approx(73.0 / 6.0, 0.001)
	assert_int(Catalog.sub_frames().get_frame_count("all")).is_equal(13)
	assert_int(Catalog.pieces_frames().get_frame_count("all")).is_equal(5)
	assert_int(Catalog.station_frames().get_frame_count("all")).is_equal(7)
	assert_int(Catalog.fx_frames().get_frame_count("bubble_columns")).is_equal(8)
