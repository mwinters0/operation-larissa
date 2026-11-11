class_name TestSkin
extends GdUnitTestSuite
## Teaches: testing an override table. A skin maps the NAMES of the registry to its own resources and everything it does not map
## falls back to the original; the original maps nothing and so is today's game exactly. The tests use the tiny skin of
## `tests/skins/tiny/` (a one-colour square in place of a creature picture, the title sky and the first zone's name box) and skins made
## in the test, never a shipped one.

const TINY := "res://tests/skins/tiny/skin.tres"
const MARKER := "res://tests/skins/tiny/marker.png"

var _tiny: GameSkin
var _marker: Texture2D


func before_test() -> void:
	_tiny = load(TINY) as GameSkin
	_marker = load(MARKER) as Texture2D
	SkinChoice.forced = &""
	SkinChoice.select(SkinChoice.original())


func after_test() -> void:
	SkinChoice.forced = &""
	SkinChoice.select(SkinChoice.original())


# --- the original maps nothing --------------------------------------------------------------------

func test_the_original_skin_maps_nothing_and_has_no_fallback() -> void:
	var original := SkinChoice.original()
	assert_object(original).is_same(load("res://skins/original/skin.tres"))
	assert_str(String(original.id)).is_equal("original")
	assert_dict(original.pictures).is_empty()
	assert_dict(original.resources).is_empty()
	assert_object(original.presenter_scene).is_null()
	assert_object(original.hud_labels).is_null()
	assert_object(original.next_skin()).is_null()
	assert_bool(original.has_pictures()).is_false()


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
	assert_str(Assets.ui_picture(&"title_sky").resource_path).is_equal(DevPack.ROOT + "assets/ui/title/title_sky_1039.png")
	assert_str(Assets.problem_art(&"log_scan_0").resource_path).starts_with(DevPack.ROOT + "assets/problem_art/")
	assert_str(Assets.background(0, 0).resource_path).is_equal(DevPack.ROOT + "assets/backgrounds/bg_s00_00.png")
	assert_object(Assets.background(30, 11)).is_null()                  # (a finale screen without a picture stays without)
	assert_object(Assets.texture_at("")).is_null()


func test_the_original_skin_is_what_a_run_asks_for_by_default() -> void:
	assert_str(String(SkinChoice.requested())).is_equal("original")
	var ids := SkinChoice.available()                                              # (the original first, then every skin in res://skins/)
	assert_str(String(ids[0])).is_equal("original")
	for id in ids:
		assert_str(String(SkinChoice.load_skin(id).id)).is_equal(String(id))     # (a skin's id is its folder's name)


# --- the key of a picture file ---------------------------------------------------------------------

func test_the_key_of_a_file_is_its_kind_and_its_registry_name() -> void:
	assert_str(GameSkin.key_of(DevPack.ROOT + "assets/ui/title/title_sky_1039.png")).is_equal("ui_picture/title_sky")
	assert_str(GameSkin.key_of(DevPack.ROOT + "assets/ui/hud/ui_1189.png")).is_equal("ui_picture/ui_1189")        # (nobody named it: the made-up name has the number)
	assert_str(GameSkin.key_of(DevPack.ROOT + "assets/problem_art/single/pa_1780.png")).is_equal("problem_art/pa_1780")
	assert_str(GameSkin.key_of(DevPack.ROOT + "assets/sprites/foes/dolphin_swim_0_0.png")).is_equal("frame/dolphin_swim_0")
	assert_str(GameSkin.key_of(DevPack.ROOT + "assets/sprites/decos/anemone_blue_37.png")).is_equal("deco/anemone_blue")
	assert_str(GameSkin.key_of(DevPack.ROOT + "assets/sprites/sub/sub_00.png")).is_equal("frame/sub_00")        # (no registry name: "sub_00" stays)
	assert_str(GameSkin.key_of(DevPack.ROOT + "assets/tiles/zone0_tiles.png")).is_equal("tile/zone0_tiles")
	assert_str(GameSkin.key_of(DevPack.ROOT + "assets/backgrounds/bg_s00_00.png")).is_equal("background/bg_s00_00")
	assert_str(GameSkin.key_of(DevPack.ROOT + "assets/audio/sfx/lock_tick_3.ogg")).is_equal("")        # (not a picture)
	assert_str(GameSkin.key_of("res://somewhere/else.png")).is_equal("")
	var kinds := {}                                                                                              # (the kinds are the table's values, each once: one table, read twice)
	for kind: String in GameSkin.KIND_FOLDERS.values():
		kinds[kind] = true
	assert_array(GameSkin.KEY_KINDS).contains_exactly_in_any_order(kinds.keys())


func test_the_key_of_every_ui_and_problem_picture_is_its_registry_name() -> void:
	# `Assets` goes from a name to a file; the key must go back from the file to the same name, for every file there is
	var registry := NameRegistry.original()
	var checked := 0
	for kind: StringName in [&"ui_picture", &"problem_art"]:
		for number in range(1000, 3000):
			var path := Assets.ui_picture_path(number) if kind == &"ui_picture" else Assets.problem_art_path(number)
			if path.is_empty() or not ResourceLoader.exists(path):
				continue
			assert_str(GameSkin.key_of(path)).override_failure_message(path).is_equal("%s/%s" % [kind, registry.name_of(kind, number)])
			checked += 1
	assert_int(checked).is_greater(300)


# --- a skin that maps some pictures ------------------------------------------------------------------

func test_a_skin_changes_a_picture_by_name_and_nothing_else() -> void:
	SkinChoice.select(_tiny)
	assert_object(Assets.ui_picture(&"title_sky")).is_same(_marker)
	assert_str(Assets.ui_picture(&"title_sea").resource_path).is_equal(DevPack.ROOT + "assets/ui/title/title_sea_1040.png")      # (not mapped: the original's)


func test_the_pictures_a_data_file_holds_by_path_come_through_the_skin() -> void:
	SkinChoice.select(_tiny)
	var frames := Catalog.foes_frames(0)
	assert_object(frames.get_frame_texture(&"all", 0)).is_same(_marker)               # dolphin_swim_0 is slot 0 of the creature sets
	var raw := load(DevPack.ROOT + "data/sprite_frames/foes_zone0.tres") as SpriteFrames
	assert_int(frames.get_frame_count(&"all")).is_equal(raw.get_frame_count(&"all"))
	for slot in range(1, raw.get_frame_count(&"all")):
		assert_object(frames.get_frame_texture(&"all", slot)).is_same(raw.get_frame_texture(&"all", slot))
	# the original's resource is not touched: the very same file read again is still the original's
	assert_object(raw.get_frame_texture(&"all", 0)).is_not_same(_marker)
	assert_object(Catalog.foes_frames(0)).is_same(frames)                             # (one copy per skin, not one per call)


func test_a_layout_keeps_everything_but_the_mapped_picture() -> void:
	var raw := load(DevPack.ROOT + "data/ui/hud_layout.tres") as HudLayout
	SkinChoice.select(_tiny)
	var layout := Catalog.hud_layout()
	assert_object(layout).is_not_same(raw)
	assert_object(layout.zone_textures[0]).is_same(_marker)                          # ui_1195: the first zone's name box
	assert_object(layout.zone_textures[1]).is_same(raw.zone_textures[1])
	assert_object(layout.bezel).is_same(raw.bezel)
	assert_object(layout.zone_position).is_equal(raw.zone_position)
	assert_object(layout.zone_size).is_equal(raw.zone_size)
	assert_array(layout.frame_rects).is_equal(raw.frame_rects)
	assert_object(raw.zone_textures[0]).is_not_same(_marker)
	assert_int(layout.zone_textures.size()).is_equal(raw.zone_textures.size())


func test_the_tileset_the_problems_and_the_paths_in_data_come_through_the_skin() -> void:
	var skin := GameSkin.new()
	skin.id = &"zone0_floor"
	skin.pictures = {"tile/zone0_tiles": _marker, "problem_art/pa_1780": _marker}
	SkinChoice.select(skin)
	var atlas := Catalog.tileset().get_source(0) as TileSetAtlasSource
	assert_object(atlas.texture).is_same(_marker)
	var raw := load(DevPack.ROOT + "data/neptune_tileset.tres") as TileSet
	assert_object((raw.get_source(0) as TileSetAtlasSource).texture).is_not_same(_marker)
	assert_int(Catalog.tileset().get_source_count()).is_equal(raw.get_source_count())
	assert_object((Catalog.tileset().get_source(1) as TileSetAtlasSource).texture).is_same((raw.get_source(1) as TileSetAtlasSource).texture)
	assert_object(Catalog.screen_layout().background).is_same(_marker)                # the problem screen's panel (`problem_art/pa_1780`)
	assert_int(Catalog.screen_layout().line_height).is_equal((load(DevPack.ROOT + "data/problems/screen_layout.tres") as ProblemScreenLayout).line_height)
	var type := Catalog.problem_type(0)                                              # art_files holds PATHS; the skin answers for each
	assert_object(Assets.texture_at(type.art_files[0])).is_not_null()


func test_a_picture_named_by_a_problem_types_path_is_the_skins_too() -> void:
	var type := Catalog.problem_type(0)
	var path := type.art_files[0]
	var skin := GameSkin.new()
	skin.id = &"one_art"
	skin.pictures = {GameSkin.key_of(path): _marker}
	SkinChoice.select(skin)
	assert_object(Assets.texture_at(path)).is_same(_marker)
	assert_object(Assets.texture_at(type.art_files[1])).is_not_same(_marker)


func test_a_background_comes_through_the_skin() -> void:
	var skin := GameSkin.new()
	skin.id = &"sky_background"
	skin.pictures = {"background/bg_s00_00": _marker}
	SkinChoice.select(skin)
	assert_object(Assets.background(0, 0)).is_same(_marker)
	assert_str(Assets.background(0, 1).resource_path).is_equal(DevPack.ROOT + "assets/backgrounds/bg_s00_01.png")


# --- falling back to the original ----------------------------------------------------------------------

func test_what_a_skin_does_not_map_falls_back_to_the_original() -> void:
	var empty := GameSkin.new()                                   # (a skin with nothing in it, not even an id)
	assert_object(empty.next_skin()).is_same(SkinChoice.original())
	SkinChoice.select(empty)
	assert_object(Catalog.hud_layout()).is_same(load(DevPack.ROOT + "data/ui/hud_layout.tres"))
	assert_object(Catalog.foes_frames(1)).is_same(load(DevPack.ROOT + "data/sprite_frames/foes_zone1.tres"))
	assert_str(Assets.ui_picture(&"title_sky").resource_path).is_equal(DevPack.ROOT + "assets/ui/title/title_sky_1039.png")
	assert_int(empty.render_settings().texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	assert_object(empty.labels()).is_null()
	assert_object(empty.presenter_scene_or_null()).is_null()


func test_a_skin_may_build_on_another_skin() -> void:
	var child := GameSkin.new()
	child.id = &"child"
	child.fallback = _tiny
	child.pictures = {"ui_picture/title_sea": _marker}
	SkinChoice.select(child)
	assert_object(Assets.ui_picture(&"title_sea")).is_same(_marker)                # its own
	assert_object(Assets.ui_picture(&"title_sky")).is_same(_marker)                # the parent's
	assert_str(Assets.ui_picture(&"title_cloud_0").resource_path).starts_with(DevPack.ROOT + "assets/ui/title/title_cloud_0")      # the original's, behind both
	assert_object(child.labels()).is_same(_tiny.hud_labels)
	assert_object(child.render_settings()).is_same(_tiny.render)


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


func test_a_resource_that_is_not_a_file_of_the_data_is_only_given_the_pictures() -> void:
	var layout := HudLayout.new()                                 # (made in code: no path, so no skin can replace it as a whole)
	layout.zone_textures = [load(DevPack.ROOT + "assets/ui/hud/ui_1195.png") as Texture2D]
	SkinChoice.select(_tiny)
	var skinned := Catalog.skinned(layout) as HudLayout
	assert_object(skinned.zone_textures[0]).is_same(_marker)
	assert_object(layout.zone_textures[0]).is_not_same(_marker)


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
	assert_str(Assets.ui_picture(&"title_sky").resource_path).is_equal(DevPack.ROOT + "assets/ui/title/title_sky_1039.png")


func test_a_forced_choice_wins_and_a_skin_is_found_by_its_id() -> void:
	SkinChoice.forced = &"original"
	assert_str(String(SkinChoice.requested())).is_equal("original")
	assert_object(SkinChoice.load_skin(&"original")).is_same(SkinChoice.original())
	assert_str(SkinChoice.path_of(&"creatures")).is_equal("res://skins/creatures/skin.tres")
	SkinChoice.forced = &"anything"
	assert_str(String(SkinChoice.requested())).is_equal("anything")


# --- what a skin may replace -------------------------------------------------------------------------

func test_a_skin_may_replace_presentation_data_and_nothing_else() -> void:
	for key in ["ui/hud_layout", "ui/story_layout", "sprite_frames/foes_zone2", "neptune_tileset", "problems/screen_layout"]:
		assert_bool(GameSkin.is_replaceable(key)).override_failure_message(key).is_true()
	for key in ["zones", "trigger_table", "bubble_rules", "problems/problem_type_00", "problems/hints", "sprite_meta/sprite_meta_zone2",
			"sectors/sector_00/sector_00", "story/story_script", "sfx_catalog"]:
		assert_bool(GameSkin.is_replaceable(key)).override_failure_message(key).is_false()
	var skin := GameSkin.new()
	skin.id = &"asks_too_much"
	skin.resources = {"ui/hud_layout": HudLayout.new(), "zones": ZoneTable.new()}
	assert_object(skin.resource_for("ui/hud_layout")).is_not_null()
	assert_object(skin.resource_for("zones")).is_null()
	assert_array(skin.refused_resources()).contains_exactly(["zones"])


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


func test_without_the_art_folder_the_originals_pictures_answer() -> void:
	var skin := GameSkin.new()
	skin.id = &"no_art"
	skin.art_folder = "res://skins/original/no_such_folder"
	skin.art_scale = 4
	assert_object(skin.picture("frame/sub_00")).is_null()
	SkinChoice.select(skin)
	var original := load(DevPack.ROOT + "assets/sprites/sub/sub_00.png") as Texture2D
	assert_object(Catalog.sub_frames().get_frame_texture(&"all", 0)).is_same(original)
