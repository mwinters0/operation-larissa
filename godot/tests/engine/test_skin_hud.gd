class_name TestSkinHud
extends GdUnitTestSuite
## Teaches: "text as text" without moving anything (built on the layout from data). The zone, sector and game words of the
## console are PICTURES in the original; a skin with `HudLabels` shows them as `Label` nodes in its own font. The test measures the
## rectangle of every label before (pictures) and after (text, a huge font, back again) and says they are the same, and that they are
## the rectangles the layout DATA holds, which in turn are the sizes of the original's pictures.

const HUD_SCENE := "res://src/ui/hud.tscn"
const TINY := "res://tests/skins/tiny/skin.tres"
## One sector of each kind: the tour's sectors (a zone each: first, second, third, fourth) and its finale.
const SECTORS := [0, 1, 2, 3, 4]

var _hud: Hud


func before_test() -> void:
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	GameState.customized = false
	GameState.set_sector(0, 9)
	_hud = scene_runner(HUD_SCENE).scene() as Hud


func after_test() -> void:
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	GameState.customized = false
	GameState.sector = -1
	GameState.piece_total = 0


## The four boxes of the lettering and what shows in each: the TextureRect (the box) and its Label (the skin's text).
func _boxes() -> Array[TextureRect]:
	return [_hud.game_label, _hud.zone_label, _hud.sector_label, _hud.custom_label]


## The rectangles of the four boxes, for every sector of SECTORS (the custom label is shown too: a customised game).
func _rectangles() -> Dictionary:
	GameState.customized = true
	var found := {}
	for sector in SECTORS:
		GameState.set_sector(sector, 8)
		found[sector] = _boxes().map(func(box: TextureRect) -> Rect2: return box.get_rect())
	return found


# --- the boxes are data, and the data is the pictures' sizes -------------------------------------------

func test_the_layout_holds_the_size_of_every_lettering_picture() -> void:
	var layout := _hud.layout
	for texture in layout.game_textures:
		assert_object(layout.game_size).is_equal(Vector2i(texture.get_size()))
	for texture in layout.zone_textures:
		assert_object(layout.zone_size).is_equal(Vector2i(texture.get_size()))
	for texture in layout.sector_textures:
		assert_object(layout.sector_size).is_equal(Vector2i(texture.get_size()))
	assert_object(layout.sector_size).is_equal(Vector2i(layout.sector_final_texture.get_size()))
	assert_object(layout.custom_size).is_equal(Vector2i(layout.custom_texture.get_size()))


func test_with_pictures_each_box_is_where_and_as_large_as_the_layout_says() -> void:
	var layout := _hud.layout
	var rectangles := _rectangles()
	for sector in SECTORS:
		var rects: Array = rectangles[sector]
		assert_object(rects[0]).is_equal(Rect2(Vector2(layout.game_position), Vector2(layout.game_size)))
		assert_object(rects[1]).is_equal(Rect2(Vector2(layout.zone_position), Vector2(layout.zone_size)))
		assert_object(rects[2]).is_equal(Rect2(Vector2(layout.sector_position), Vector2(layout.sector_size)))
		assert_object(rects[3]).is_equal(Rect2(Vector2(layout.custom_position), Vector2(layout.custom_size)))
		for text: Label in [_hud.game_text, _hud.zone_text, _hud.sector_text, _hud.custom_text]:
			assert_bool(text.visible).is_false()                   # (the pictures are shown, the text is not)


# --- a skin with text ----------------------------------------------------------------------------------------

func test_text_labels_keep_the_layouts_rectangles() -> void:
	var before := _rectangles()
	SkinChoice.select(load(TINY) as GameSkin)
	var after := _rectangles()
	for sector in SECTORS:
		assert_array(after[sector]).override_failure_message("sector %d" % sector).is_equal(before[sector])


func test_a_huge_font_moves_and_resizes_nothing() -> void:
	var before := _rectangles()
	var labels := HudLabels.new()
	labels.font_size = 60                                        # (three times the height of the box)
	var skin := GameSkin.new()
	skin.id = &"huge_letters"
	skin.hud_labels = labels
	SkinChoice.select(skin)
	var after := _rectangles()
	for sector in SECTORS:
		assert_array(after[sector]).override_failure_message("sector %d" % sector).is_equal(before[sector])
	for box in _boxes():
		assert_bool(box.clip_contents).is_true()                 # (what sticks out of the box is cut off, not drawn over the console)
	assert_int(_hud.game_text.get_theme_font_size(&"font_size")).is_equal(60)


func test_the_text_is_the_words_the_pictures_say() -> void:
	SkinChoice.select(load(TINY) as GameSkin)
	GameState.customized = true
	GameState.set_sector(0, 8)
	assert_str(_hud.game_text.text).is_equal("Tiny Voyager")           # (the tiny skin's own word for the first banner)
	assert_str(_hud.zone_text.text).is_equal("Dragon Reef")           # (the default words are the pictures' of the original: HudLabels is not pack data)
	assert_str(_hud.sector_text.text).is_equal("First")
	assert_str(_hud.custom_text.text).is_equal("Cust")
	GameState.set_sector(1, 8)                                        # a zone further, the second sector
	assert_str(_hud.zone_text.text).is_equal(HudLabels.new().zone_word(Catalog.sector(1).zone))
	assert_str(_hud.zone_text.text).is_not_equal("Dragon Reef")
	assert_str(_hud.sector_text.text).is_equal("Second")
	GameState.set_sector(DevPack.TOUR_FINALE, 8)
	assert_str(_hud.sector_text.text).is_equal("Final")
	for text: Label in [_hud.game_text, _hud.zone_text, _hud.sector_text, _hud.custom_text]:
		assert_bool(text.visible).is_true()
	for box in _boxes():
		assert_object(box.texture).is_null()
	assert_object(_hud.game_text.get_rect().size).is_equal(_hud.game_label.size)     # (the text fills its box)


func test_the_text_follows_the_sector_like_the_pictures_did() -> void:
	SkinChoice.select(load(TINY) as GameSkin)
	GameState.set_sector(-1, 0)                                       # no sector: nothing is shown
	for box in [_hud.game_label, _hud.zone_label, _hud.sector_label]:
		assert_bool((box as TextureRect).visible).is_false()
	GameState.set_sector(2, 8)
	for box in [_hud.game_label, _hud.zone_label, _hud.sector_label]:
		assert_bool((box as TextureRect).visible).is_true()


# --- switching while the HUD is on screen -------------------------------------------------------------------------

func test_the_hud_changes_with_the_skin_and_comes_back() -> void:
	GameState.set_sector(1, 8)
	var layout := _hud.layout
	var banner := Catalog.campaign_of_sector(1).banner_index
	assert_object(_hud.game_label.texture).is_same(layout.game_textures[banner])
	SkinChoice.select(load(TINY) as GameSkin)
	assert_object(_hud.game_label.texture).is_null()
	assert_str(_hud.game_text.text).is_equal("Tiny Voyager")
	assert_object(_hud.layout.zone_textures[0]).is_same(load("res://tests/skins/tiny/marker.png"))        # (the skin's picture in the layout)
	SkinChoice.select(SkinChoice.original())
	assert_object(_hud.layout).is_same(layout)                               # (the original's own resource again)
	assert_object(_hud.game_label.texture).is_same(layout.game_textures[banner])
	assert_object(_hud.zone_label.texture).is_same(layout.zone_texture(Catalog.sector(1).zone))
	assert_bool(_hud.game_text.visible).is_false()
	assert_object(_hud.game_label.get_rect()).is_equal(Rect2(Vector2(layout.game_position), Vector2(layout.game_size)))


func test_the_gauges_and_lights_are_not_disturbed_by_a_switch() -> void:
	GameState.set_message_light(true, false)
	var ink := _hud.ink.value
	var oxygen := _hud.oxygen.value
	SkinChoice.select(load(TINY) as GameSkin)
	assert_int(_hud.ink.value).is_equal(ink)
	assert_int(_hud.oxygen.value).is_equal(oxygen)
	assert_bool(_hud.ship_glow.visible).is_true()
	assert_object(_hud.bezel.texture).is_same(_hud.layout.bezel)
