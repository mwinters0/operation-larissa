class_name TestSpriteMetaLegacy
extends GdUnitTestSuite
## The legacy pack's hit boxes: the original's first creature box and the sizes of the combined tables.


func test_common_sprite_0() -> void:
	var meta: SpriteMetaTable = load(LegacyPack.ROOT + "data/sprite_meta/sprite_meta_common.tres")
	assert_int(meta.count()).is_equal(28)
	assert_that(meta.sizes[0]).is_equal(Vector2i(112, 48))
	assert_that(meta.hit_rect(0)).is_equal(Rect2i(6, 6, 98, 36))


func test_the_flipped_box_is_another_box_of_the_same_size() -> void:
	var meta: SpriteMetaTable = load(LegacyPack.ROOT + "data/sprite_meta/sprite_meta_common.tres")
	# The flipped box is a different box of the same size (it is not simply mirrored).
	assert_that(meta.hit_rect(0, true).size).is_equal(meta.hit_rect(0).size)
	assert_that(meta.hit_rect(0, true)).is_not_equal(meta.hit_rect(0))


func test_combined_table_sizes() -> void:
	assert_int(SpriteMeta.for_zone(0).count()).is_equal(28 + 7 + 11)
	assert_int(SpriteMeta.for_zone(4).count()).is_equal(28 + 7 + 18)
