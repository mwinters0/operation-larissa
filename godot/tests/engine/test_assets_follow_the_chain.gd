class_name TestAssetsFollowTheChain
extends GdUnitTestSuite
## Teaches: one way to hold a picture. `Assets` hands out a `PictureRef` for every key (one per key), so a screen that keeps what `Assets` gave it in a node shows the chain as it is NOW: when a pack is installed or taken away
## (`PackInstall` -> `Packs.reset` -> `Pictures.forget`), the picture on the screen is the other pack's with nothing rebuilt. The packs of `PicturesShelf` name their files at random, so a colour is found through the table only.

var _shelf: PicturesShelf


func before_test() -> void:
	GameState.reset()
	_shelf = PicturesShelf.new()
	_shelf.mount_base()


func after_test() -> void:
	_shelf.remove()
	GameState.reset()


func test_a_picture_asked_by_name_is_a_reference_to_its_key_and_the_same_one_each_time() -> void:
	var sky := Assets.ui_picture(&"title_sky")
	assert_str(sky.key).is_equal("ui_picture/title_sky")
	assert_object(Assets.ui_picture(&"title_sky")).is_same(sky)
	assert_object(Assets.picture_by_key("ui_picture/title_sky")).is_same(sky)
	assert_object(Assets.problem_art(&"log_scan_0")).is_same(Assets.picture_by_key("problem_art/log_scan_0"))
	assert_object(Assets.background(0, 0)).is_null()                                                   # (no pack of this chain draws behind that screen: no reference, no trouble)
	assert_bool(Assets.has_background(0, 0)).is_false()
	assert_bool(Assets.holds("ui_picture/title_sky")).is_true()
	assert_bool(Assets.holds("ui_picture/zz_nobody_has_me")).is_false()


func test_a_screen_that_holds_a_picture_shows_the_new_chain_when_a_pack_is_laid_over() -> void:
	var sprite := Sprite2D.new()
	var rect := TextureRect.new()
	add_child(sprite)
	add_child(rect)
	sprite.texture = Assets.ui_picture(&"title_sky")                                                   # (what a screen does in `_ready` and never again)
	rect.texture = Assets.picture_by_key("ui_picture/coral_noon")                                      # (an alias)
	var told := [0]
	sprite.texture.changed.connect(func() -> void: told[0] += 1)
	assert_that(PicturesShelf.color_of(sprite.texture)).is_equal(PicturesShelf.RED)
	assert_that(PicturesShelf.color_of(rect.texture)).is_equal(PicturesShelf.RED)
	_shelf.mount_over()                                                                               # (the chain changes under the screen)
	assert_that(PicturesShelf.color_of(sprite.texture)).override_failure_message("the sprite keeps the picture of the pack that was").is_equal(PicturesShelf.WHITE)
	assert_that(PicturesShelf.color_of(rect.texture)).is_equal(PicturesShelf.WHITE)
	assert_int(told[0]).override_failure_message("the holder hears of the change as it hears of an updated texture").is_greater(0)
	assert_object(Assets.ui_picture(&"title_sky")).is_same(sprite.texture)
	_shelf.mount_base()
	assert_that(PicturesShelf.color_of(sprite.texture)).is_equal(PicturesShelf.RED)
	sprite.free()
	rect.free()


func test_a_picture_nobody_holds_draws_nothing_and_is_told_by_the_reference_once_per_run() -> void:
	var nothing := Assets.ui_picture(&"zz_nobody_has_me")
	assert_array(TroubleLog.session.told).is_empty()                                                   # (asking says nothing: the holder draws, and then the reference says so)
	assert_int(nothing.get_width()).is_equal(0)
	assert_int(nothing.get_height()).is_equal(0)
	nothing.get_size()
	var lines := TroubleLog.session.told.filter(func(line: String) -> bool: return line.contains("'ui_picture/zz_nobody_has_me'"))
	assert_array(lines).has_size(1)
	assert_str(lines[0]).is_equal(Pictures.unheld_line("ui_picture/zz_nobody_has_me"))
