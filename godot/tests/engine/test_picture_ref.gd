class_name TestPictureRef
extends GdUnitTestSuite
## Teaches: a `Texture2D` that is a name. A `PictureRef` holds a key and answers every question the engine asks a texture with the picture the chain gives that key, so these tests ask through the engine's own nodes (a `Sprite2D`'s pixel test, a `TextureRect`'s size,
## a tile set's grid) what each consumer asks, and check the answer follows a change of the chain. What reaches the screen is `test_picture_ref_render.gd` (a window).

var _shelf: PicturesShelf


func before_test() -> void:
	GameState.reset()
	_shelf = PicturesShelf.new()
	_shelf.mount_base()


func after_test() -> void:
	_shelf.remove()
	GameState.reset()


func test_it_answers_with_the_picture_of_its_key() -> void:
	var ref := PictureRef.of("ui_picture/title_sky")
	var held := Pictures.resolve("ui_picture/title_sky")
	assert_object(ref.resolved()).is_same(held)
	assert_vector(ref.get_size()).is_equal(Vector2(4, 4))
	assert_int(ref.get_width()).is_equal(4)
	assert_bool(ref.has_alpha()).is_equal(held.has_alpha())
	assert_int(ref.get_format()).is_equal(held.get_format())
	assert_that(PicturesShelf.color_of(ref)).is_equal(PicturesShelf.RED)                  # (`get_image` is the picture's)
	assert_that(ref.get_rid()).is_equal(held.get_rid())                                    # (what a NinePatchRect, a StyleBoxTexture and the renderer ask)
	assert_vector(PictureRef.of("ui_picture/coral_noon").get_size()).is_equal(Vector2(4, 4))     # (through an alias)
	assert_vector(PictureRef.of("frame/sub_00").get_size()).is_equal(Vector2(4, 4))            # (a scaled row: the size it is drawn at)


func test_a_key_no_pack_holds_is_an_empty_picture_told_once() -> void:
	var ref := PictureRef.of("frame/nobody_has_this")
	for i in 3:
		assert_vector(ref.get_size()).is_equal(Vector2.ZERO)
		assert_bool(ref.has_alpha()).is_false()
		assert_object(ref.get_image()).is_null()
		assert_bool(ref.get_rid().is_valid()).is_false()
		ref.emit_changed()
		ref._forget()
	var lines := TroubleLog.session.told.filter(func(line: String) -> bool: return line.contains("frame/nobody_has_this"))
	assert_array(lines).has_size(1)
	assert_str(lines[0]).contains(String(_shelf.base.id)).contains("nothing is drawn")


func test_a_pixel_is_opaque_when_the_pictures_is() -> void:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = PictureRef.of("deco/half_clear")
	add_child(sprite)
	assert_bool(sprite.is_pixel_opaque(Vector2(1, 1))).is_false()
	assert_bool(sprite.is_pixel_opaque(Vector2(6, 1))).is_true()
	assert_vector(sprite.get_rect().size).is_equal(Vector2(8, 4))
	sprite.queue_free()


func test_the_nodes_that_size_themselves_by_a_texture_ask_the_ref() -> void:
	var rect := TextureRect.new()
	rect.texture = PictureRef.of("tile/wall_sheet")
	assert_vector(rect.get_minimum_size()).is_equal(Vector2(32, 16))
	rect.free()
	var frames := SpriteFrames.new()
	frames.add_frame(&"default", PictureRef.of("tile/wall_sheet"))
	assert_vector(frames.get_frame_texture(&"default", 0).get_size()).is_equal(Vector2(32, 16))
	var box := StyleBoxTexture.new()
	box.texture = PictureRef.of("tile/wall_sheet")
	box.texture_margin_left = 4
	assert_vector(box.get_minimum_size()).is_equal(Vector2(4, 0))
	assert_vector(box.texture.get_size()).is_equal(Vector2(32, 16))


func test_a_tile_set_atlas_of_a_ref_has_its_grid_its_tiles_and_its_padded_copy() -> void:
	var source := TileSetAtlasSource.new()
	source.texture = PictureRef.of("tile/wall_sheet")
	source.texture_region_size = Vector2i(16, 16)
	assert_vector(source.get_atlas_grid_size()).is_equal(Vector2i(2, 1))
	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))
	assert_int(source.get_tiles_count()).is_equal(2)                                      # (the picture's size was known when the tiles were made)
	await get_tree().process_frame                                                          # (the padded copy the tile map draws is made later, from `get_image`)
	var padded := source.get_runtime_texture()
	assert_vector(padded.get_size()).is_equal(Vector2(36, 18))
	var image := padded.get_image()
	assert_that(image.get_pixel(1 + 16 + 2 + 8, 9)).is_equal(PicturesShelf.GREEN)         # (the second tile, in its padding)
	assert_that(image.get_pixel(9, 9)).is_equal(PicturesShelf.RED)


func test_it_follows_a_change_of_the_chain_and_tells_its_holders() -> void:
	var ref := PictureRef.of("ui_picture/title_sky")
	var told := [0]
	ref.changed.connect(func() -> void: told[0] += 1)
	assert_that(PicturesShelf.color_of(ref)).is_equal(PicturesShelf.RED)
	_shelf.mount_over()
	assert_int(told[0]).is_greater(0)
	assert_that(PicturesShelf.color_of(ref)).is_equal(PicturesShelf.WHITE)
	var sprite := Sprite2D.new()
	sprite.texture = ref
	_shelf.mount_base()
	assert_that(PicturesShelf.color_of(sprite.texture)).is_equal(PicturesShelf.RED)
	sprite.free()


func test_a_ref_is_a_sub_resource_with_a_key_in_a_tres() -> void:
	var path := "user://picture_ref_test.tres"
	assert_int(ResourceSaver.save(PictureRef.of("frame/eel_swim_0"), path)).is_equal(OK)
	var back := load(path) as PictureRef
	assert_str(back.key).is_equal("frame/eel_swim_0")
	assert_that(PicturesShelf.color_of(back)).is_equal(PicturesShelf.GREEN)
	DirAccess.remove_absolute(path)


func test_a_pack_with_no_table_is_still_read_by_its_files() -> void:
	_shelf.remove()                                                                         # (the chain is the dev pack again: no picture table)
	_shelf = PicturesShelf.new()
	assert_bool(Packs.dev().picture_table().present).is_false()
	var ref := PictureRef.of("frame/sub_00")
	assert_object(ref.resolved()).is_not_null()
	assert_object(ref.resolved()).is_same(Assets.picture_by_key("frame/sub_00"))
	assert_object(Pictures.resolve("ui_picture/title_sky")).is_same(Assets.ui_picture(&"title_sky"))
