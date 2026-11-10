class_name TestSpriteMeta
extends GdUnitTestSuite
## Hit boxes are kept per sprite in pixels (the original's half-pixel tables, doubled, are in `tests/legacy/test_sprite_meta_legacy.gd`).


func test_the_flipped_rect_is_its_own_box_of_the_same_size() -> void:
	# A table with a box and a different flipped box for each sprite: `hit_rect` gives the flipped one when asked, and the two are not mirror images by rule.
	var meta := SpriteMetaTable.new()
	meta.sizes = [Vector2i(40, 20), Vector2i(60, 30)]
	meta.hit_rects = [Rect2i(4, 2, 30, 16), Rect2i(6, 4, 40, 20)]
	meta.hit_rects_flipped = [Rect2i(8, 2, 30, 16), Rect2i(14, 4, 40, 20)]
	assert_that(meta.hit_rect(0)).is_equal(Rect2i(4, 2, 30, 16))
	assert_that(meta.hit_rect(0, true)).is_equal(Rect2i(8, 2, 30, 16))
	assert_that(meta.hit_rect(1, true).size).is_equal(meta.hit_rect(1).size)
	assert_that(meta.hit_rect(1, true)).is_not_equal(meta.hit_rect(1))


func test_every_table_of_the_chain_has_one_box_per_picture() -> void:
	for zone in Catalog.ZONE_COUNT:
		var meta := SpriteMeta.for_zone(zone)
		assert_int(meta.hit_rects.size()).is_equal(meta.count())
		assert_int(meta.hit_rects_flipped.size()).is_equal(meta.count())
		assert_array(meta.problems()).is_empty()
