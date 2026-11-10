class_name TestSpriteFramesLegacy
extends GdUnitTestSuite
## The legacy pack's sprite sets: the original's slot counts and the size of its first creature picture.
## The pattern (animation "all", frame index == slot number) is tested on dev in `tests/engine/test_sprite_frames.gd`.


func test_foes_zone_0_slots() -> void:
	var frames := Catalog.foes_frames(0)
	assert_bool(frames.has_animation("all")).is_true()
	# 28 common creatures + 7 ink frames + 11 zone creatures.
	assert_int(frames.get_frame_count("all")).is_equal(28 + 7 + 11)


func test_first_foe_frame_matches_metadata_size() -> void:
	var texture := Catalog.foes_frames(0).get_frame_texture("all", 0)
	var meta := SpriteMeta.for_zone(0)
	assert_that(texture.get_size()).is_equal(Vector2(112, 48))
	assert_that(Vector2i(texture.get_size())).is_equal(meta.sizes[0])


func test_deco_slots() -> void:
	for zone_index in 5:
		var frames := Catalog.decos_frames(zone_index)
		assert_int(frames.get_frame_count("all")).is_equal(70 + Catalog.zone(zone_index).deco_count)
