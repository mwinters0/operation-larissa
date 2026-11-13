class_name TestSkin
extends GdUnitTestSuite
## Teaches: testing an override table. A skin maps resources (layouts, a presenter, render settings, lettering) and everything it does not map falls back to the original; the original maps nothing and so is today's game exactly. A skin maps NO picture:
## the pictures are the packs' (`pictures.json`), so the tests that follow a picture to the screen redraw it with a scratch pack laid over the suite's pack, and show that no skin changes it. The tests use the tiny skin of `tests/skins/tiny/` (linear filtering and
## the HUD's words as text) and skins made in the test, never a shipped one.

const TINY := "res://tests/skins/tiny/skin.tres"

var _tiny: GameSkin
var _shelf: PackShelf


func before_test() -> void:
	_tiny = load(TINY) as GameSkin
	SkinChoice.forced = &""
	SkinChoice.select(SkinChoice.original())


func after_test() -> void:
	SkinChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	if _shelf != null:
		_shelf.remove()
		_shelf = null


## A pack laid over the suite's, drawing each key of `rows` (key -> colour) as a 4 x 4 picture of that colour, and chosen.
func _redraw(rows: Dictionary) -> void:
	_shelf = PackShelf.new()
	for key: String in rows:
		_shelf.add_picture_row(key, rows[key])
	_shelf.mount()


func _color(texture: Texture2D) -> Color:
	return PicturesShelf.color_of(texture)


# --- the original maps nothing --------------------------------------------------------------------

func test_the_original_skin_maps_nothing_and_has_no_fallback() -> void:
	var original := SkinChoice.original()
	assert_object(original).is_same(load("res://skins/original/skin.tres"))
	assert_str(String(original.id)).is_equal("original")
	assert_dict(original.resources).is_empty()
	assert_object(original.presenter_scene).is_null()
	assert_object(original.hud_labels).is_null()
	assert_object(original.next_skin()).is_null()


func test_no_skin_maps_a_picture() -> void:
	var fields: Array[String] = []
	for info in GameSkin.new().get_property_list():
		fields.append(info.name)
	for gone in ["pictures", "art_folder", "art_scale"]:
		assert_bool(fields.has(gone)).override_failure_message("a skin has the field '%s': the pictures are the packs' (pictures.json)" % gone).is_false()
	for gone in ["picture", "has_pictures", "texture_at", "_art_picture", "_skin_picture"]:
		assert_bool(GameSkin.new().has_method(gone)).override_failure_message("a skin has the method '%s'" % gone).is_false()


func test_with_the_original_skin_every_resource_is_the_very_object_on_disk() -> void:
	# `skinned` hands back what `Catalog` loaded, not a copy: nothing about the original look can differ
	assert_object(SkinChoice.current()).is_same(SkinChoice.original())
	assert_object(Catalog.hud_layout()).is_same(load(DevPack.ROOT + "data/ui/hud_layout.tres"))
	assert_object(Catalog.foes_frames(2)).is_same(load(DevPack.ROOT + "data/sprite_frames/foes_zone2.tres"))
	assert_object(Catalog.sub_frames()).is_same(load(DevPack.ROOT + "data/sprite_frames/sub_frames.tres"))
	assert_object(Catalog.tileset()).is_same(load(DevPack.ROOT + "data/neptune_tileset.tres"))
	assert_object(Catalog.screen_layout()).is_same(load(DevPack.ROOT + "data/problems/screen_layout.tres"))
	assert_object(Catalog.problem_type(3)).is_same(load(DevPack.ROOT + "data/problems/problem_type_03.tres"))
	assert_object(Catalog.menu_layout()).is_same(load("res://data/ui/menu_layout.tres"))


func test_with_the_original_skin_a_picture_is_the_file() -> void:
	assert_str(Assets.ui_picture(&"title_sky").resolved().resource_path).is_equal(DevPack.picture_file("ui_picture/title_sky"))
	assert_str(Assets.problem_art(&"log_scan_0").resolved().resource_path).is_equal(DevPack.picture_file("problem_art/log_scan_0"))
	assert_str(Assets.background(0, 0).resolved().resource_path).is_equal(DevPack.picture_file("background/bg_s00_00"))
	assert_object(Assets.background(30, 11)).is_null()                  # (a finale screen without a picture stays without)


func test_the_original_skin_is_what_a_run_asks_for_by_default() -> void:
	assert_str(String(SkinChoice.requested())).is_equal("original")
	var ids := SkinChoice.available()                                              # (the original first, then every skin in res://skins/)
	assert_str(String(ids[0])).is_equal("original")
	for id in ids:
		assert_str(String(SkinChoice.load_skin(id).id)).is_equal(String(id))     # (a skin's id is its folder's name)


# --- the pictures are the packs', not the skin's ------------------------------------------------------------

func test_a_skin_changes_no_picture() -> void:
	var sky := Assets.ui_picture(&"title_sky")
	var frames := Catalog.foes_frames(0)
	SkinChoice.select(_tiny)
	assert_object(Assets.ui_picture(&"title_sky")).is_same(sky)
	assert_str(sky.resolved().resource_path).is_equal(DevPack.picture_file("ui_picture/title_sky"))
	assert_object(Catalog.foes_frames(0)).is_same(frames)


func test_a_pack_changes_a_picture_by_key_under_every_skin() -> void:
	_redraw({"ui_picture/title_sky": Color.RED})
	for skin in [SkinChoice.original(), _tiny]:
		SkinChoice.select(skin)
		assert_that(_color(Assets.ui_picture(&"title_sky"))).is_equal(Color.RED)
		assert_str(Assets.ui_picture(&"title_sea").resolved().resource_path).is_equal(DevPack.picture_file("ui_picture/title_sea"))      # (not drawn: the pack under it answers)


func test_the_pictures_a_data_file_holds_come_through_the_packs_tables() -> void:
	var raw := load(DevPack.ROOT + "data/sprite_frames/foes_zone0.tres") as SpriteFrames
	_redraw({"frame/dolphin_swim_0": Color.RED})
	var frames := Catalog.foes_frames(0)
	assert_that(_color(frames.get_frame_texture(&"all", 0))).is_equal(Color.RED)               # dolphin_swim_0 is slot 0 of the creature sets
	assert_int(frames.get_frame_count(&"all")).is_equal(raw.get_frame_count(&"all"))
	assert_object(frames).is_same(raw)                                                          # (the data holds the key: the very resource, whatever the chain)
	assert_str(PictureRef.key_of(frames.get_frame_texture(&"all", 0))).is_equal("frame/dolphin_swim_0")
	SkinChoice.select(_tiny)
	assert_object(Catalog.foes_frames(0)).is_same(frames)                                       # (and no skin has a part in it)


func test_a_layout_is_the_same_resource_and_shows_the_redrawn_picture() -> void:
	var raw := load(DevPack.ROOT + "data/ui/hud_layout.tres") as HudLayout
	var before := _color(raw.zone_textures[0])
	_redraw({"ui_picture/ui_1195": Color.RED})
	var layout := Catalog.hud_layout()
	assert_object(layout).is_same(raw)                                                        # (it holds the key, not the picture)
	assert_that(_color(layout.zone_textures[0])).is_equal(Color.RED)                          # ui_1195: the first zone's name box
	assert_str(PictureRef.key_of(layout.zone_textures[0])).is_equal("ui_picture/ui_1195")
	assert_that(_color(layout.zone_textures[1])).is_not_equal(Color.RED)
	_shelf.remove()
	_shelf = null
	assert_that(_color(layout.zone_textures[0])).is_equal(before)                             # (and the pack taken away, it shows the pack under it again)


func test_the_tileset_the_problems_and_the_keys_in_data_come_through_the_packs_tables() -> void:
	_redraw({"tile/zone0_tiles": Color.RED, "problem_art/pa_1780": Color.RED})
	var atlas := Catalog.tileset().get_source(0) as TileSetAtlasSource
	assert_that(_color(atlas.texture)).is_equal(Color.RED)
	assert_that(_color((Catalog.tileset().get_source(1) as TileSetAtlasSource).texture)).is_not_equal(Color.RED)
	assert_that(_color(Catalog.screen_layout().background)).is_equal(Color.RED)               # the problem screen's panel (`problem_art/pa_1780`)
	var type := Catalog.problem_type(0)                                              # art_keys holds KEYS; the tables answer for each
	assert_bool(Assets.holds(type.art_keys[0])).is_true()


func test_a_picture_named_by_a_problem_types_key_is_the_packs_too() -> void:
	var type := Catalog.problem_type(0)
	var key := type.art_keys[0]
	_redraw({key: Color.RED})
	assert_that(_color(Assets.picture_by_key(key))).is_equal(Color.RED)
	assert_that(_color(Assets.picture_by_key(type.art_keys[1]))).is_not_equal(Color.RED)


func test_a_background_comes_through_the_packs_tables() -> void:
	_redraw({"background/bg_s00_00": Color.RED})
	assert_that(_color(Assets.background(0, 0))).is_equal(Color.RED)
	assert_str(Assets.background(0, 1).resolved().resource_path).is_equal(DevPack.picture_file("background/bg_s00_01"))


# --- falling back to the original ----------------------------------------------------------------------

func test_what_a_skin_does_not_map_falls_back_to_the_original() -> void:
	var empty := GameSkin.new()                                   # (a skin with nothing in it, not even an id)
	assert_object(empty.next_skin()).is_same(SkinChoice.original())
	SkinChoice.select(empty)
	assert_object(Catalog.hud_layout()).is_same(load(DevPack.ROOT + "data/ui/hud_layout.tres"))
	assert_object(Catalog.foes_frames(1)).is_same(load(DevPack.ROOT + "data/sprite_frames/foes_zone1.tres"))
	assert_str(Assets.ui_picture(&"title_sky").resolved().resource_path).is_equal(DevPack.picture_file("ui_picture/title_sky"))
	assert_int(empty.render_settings().texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	assert_object(empty.labels()).is_null()
	assert_object(empty.presenter_scene_or_null()).is_null()


func test_a_skin_may_build_on_another_skin() -> void:
	var child := GameSkin.new()
	child.id = &"child"
	child.fallback = _tiny
	child.render = RenderSettings.new()
	SkinChoice.select(child)
	assert_object(child.render_settings()).is_same(child.render)                    # its own
	assert_object(child.labels()).is_same(_tiny.hud_labels)                       # the parent's
	assert_object(child.presenter_scene_or_null()).is_null()                     # the original's, behind both


func test_a_skin_can_bring_a_whole_resource_instead_of_the_originals() -> void:
	var own := HudLayout.new()
	own.zone_position = Vector2i(1, 2)
	var skin := GameSkin.new()
	skin.id = &"own_layout"
	skin.resources = {"ui/hud_layout": own}
	SkinChoice.select(skin)
	assert_object(Catalog.hud_layout()).is_same(own)
	assert_object(Catalog.skinned(load(DevPack.ROOT + "data/ui/hud_layout.tres"))).is_same(own)    # also for a scene that holds the original's
	assert_object(Catalog.calculator_layout()).is_same(load(DevPack.ROOT + "data/ui/calculator_layout.tres"))


func test_a_resource_that_is_not_a_file_of_the_data_is_given_no_skin() -> void:
	var layout := HudLayout.new()                                 # (made in code: no path, so no skin can replace it as a whole)
	layout.zone_textures = [PictureRef.of("ui_picture/ui_1195")]
	_redraw({"ui_picture/ui_1195": Color.RED})
	var shown := Catalog.skinned(layout) as HudLayout
	assert_object(shown).is_same(layout)
	assert_that(_color(shown.zone_textures[0])).is_equal(Color.RED)


# --- choosing and switching ------------------------------------------------------------------------------

func test_a_switch_is_announced_and_goes_both_ways() -> void:
	var heard: Array[GameSkin] = []
	var listener := func(skin: GameSkin) -> void: heard.append(skin)
	SkinChoice.events.changed.connect(listener)
	SkinChoice.select(_tiny)
	assert_object(SkinChoice.current()).is_same(_tiny)
	SkinChoice.select(SkinChoice.original())
	SkinChoice.events.changed.disconnect(listener)
	assert_array(heard).has_size(2)
	assert_object(heard[0]).is_same(_tiny)
	assert_object(heard[1]).is_same(SkinChoice.original())
	assert_str(Assets.ui_picture(&"title_sky").resolved().resource_path).is_equal(DevPack.picture_file("ui_picture/title_sky"))


func test_a_forced_choice_wins_and_a_skin_is_found_by_its_id() -> void:
	SkinChoice.forced = &"original"
	assert_str(String(SkinChoice.requested())).is_equal("original")
	assert_object(SkinChoice.load_skin(&"original")).is_same(SkinChoice.original())
	assert_str(SkinChoice.path_of(&"creatures")).is_equal("res://skins/creatures/skin.tres")
	SkinChoice.forced = &"anything"
	assert_str(String(SkinChoice.requested())).is_equal("anything")


# --- what a skin may replace -------------------------------------------------------------------------

func test_a_skin_may_replace_presentation_data_and_nothing_else() -> void:
	for key in ["ui/hud_layout", "ui/story_layout", "problems/screen_layout"]:
		assert_bool(GameSkin.is_replaceable(key)).override_failure_message(key).is_true()
	for key in ["sprite_frames/foes_zone2", "sprite_frames/decos_zone0", "neptune_tileset", "zones", "trigger_table", "bubble_rules", "problems/problem_type_00", "problems/hints", "sprite_meta/sprite_meta_zone2",
			"sectors/sector_00/sector_00", "story/story_script", "sfx_catalog"]:
		assert_bool(GameSkin.is_replaceable(key)).override_failure_message(key).is_false()
	var skin := GameSkin.new()
	skin.id = &"asks_too_much"
	skin.resources = {"ui/hud_layout": HudLayout.new(), "zones": ZoneTable.new()}
	assert_object(skin.resource_for("ui/hud_layout")).is_not_null()
	assert_object(skin.resource_for("zones")).is_null()
	assert_array(skin.refused_resources()).contains_exactly(["zones"])


## A skin maps no picture: the sprite sets and the tile set (the picture bundles) are the packs', and a layout that carries a picture of its own is not shown.
func test_a_skin_cannot_carry_a_picture_of_its_own() -> void:
	var skin := GameSkin.new()
	skin.id = &"brings_art"
	var bundles := Catalog.foes_frames(0).duplicate() as SpriteFrames
	var with_a_file := HudLayout.new()
	with_a_file.bezel = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var nested := HudLayout.new()
	nested.zone_textures = [PictureRef.of("frame/sub_00"), with_a_file.bezel]
	var by_key := HudLayout.new()
	by_key.bezel = PictureRef.of("frame/sub_00")
	by_key.zone_textures = [PictureRef.of("frame/sub_00")]
	skin.resources = {"sprite_frames/foes_zone0": bundles, "neptune_tileset": Catalog.tileset().duplicate(), "ui/hud_layout": with_a_file, "ui/story_layout": by_key, "ui/calculator_layout": nested}
	assert_array(skin.refused_resources()).contains_exactly_in_any_order(["sprite_frames/foes_zone0", "neptune_tileset", "ui/hud_layout", "ui/calculator_layout"])
	for key in ["sprite_frames/foes_zone0", "neptune_tileset", "ui/hud_layout", "ui/calculator_layout"]:
		assert_object(skin.resource_for(key)).override_failure_message(key).is_null()
	assert_object(skin.resource_for("ui/story_layout")).override_failure_message("a layout that holds keys is the skin's").is_same(by_key)
	SkinChoice.select(skin)
	assert_object(Catalog.hud_layout()).override_failure_message("the layout with a file of its own is not shown").is_same(load(DevPack.ROOT + "data/ui/hud_layout.tres"))
	assert_object(Catalog.foes_frames(0)).is_same(load(DevPack.ROOT + "data/sprite_frames/foes_zone0.tres"))
	assert_bool(GameSkin.holds_a_picture(Catalog.hud_layout())).override_failure_message("the pack's own layouts hold keys only").is_false()


# --- a picture drawn at a fraction of its size --------------------------------------------------------------------

func test_a_scaled_texture_reports_the_size_it_is_drawn_at() -> void:
	var big := ImageTexture.create_from_image(Image.create_empty(384, 216, false, Image.FORMAT_RGBA8))
	var texture := ScaledTexture.of(big, 4)
	assert_object(texture.get_size()).is_equal(Vector2(96, 54))
	assert_int(texture.get_width()).is_equal(96)
	assert_int(texture.get_height()).is_equal(54)
	assert_bool(texture.has_alpha()).is_true()
	assert_object(ScaledTexture.of(big, 1).get_size()).is_equal(Vector2(384, 216))        # (a factor of 1 is the file as it is)


func test_a_scaled_texture_asks_the_middle_of_the_block() -> void:
	var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(4, 4, 4, 4), Color.WHITE)                    # the 2 x 2 block at (1, 1) of the reported size
	var texture := ScaledTexture.of(ImageTexture.create_from_image(image), 4)
	assert_bool(texture._is_pixel_opaque(1, 1)).is_true()
	assert_bool(texture._is_pixel_opaque(0, 0)).is_false()
	assert_bool(texture._is_pixel_opaque(1, 0)).is_false()
