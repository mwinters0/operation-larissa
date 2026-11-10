class_name TestSkinModern
extends GdUnitTestSuite
## Teaches: what a shipped skin has to prove (the "modern" proof skin). It is found and switchable like any other; its water
## shimmer follows the game's clock and nothing else; its font changes no box of the HUD; and playing with it, or switching to it and back in
## the middle of a visit, gives the very trace of the original (`test_skins_dont_change_the_game.gd` compares every skin; this is the one for
## this skin). (`ScaledTexture`, the class that draws a picture at a quarter of its size, is tested below on a picture made in the test.)

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const HUD_SCENE := "res://src/ui/hud.tscn"
const SKIN := "res://skins/modern/skin.tres"
## One sector of each kind, as in `test_skin_hud.gd`.
const SECTORS := [0, 1, 2, 3, 4]


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	GameState.customized = false
	GameState.sector = -1
	GameState.piece_total = 0


func _modern() -> GameSkin:
	return load(SKIN) as GameSkin


# --- the skin is there ----------------------------------------------------------------------------------------

func test_the_skin_is_found_and_loads() -> void:
	assert_array(SkinChoice.available()).contains([&"original", &"modern"])
	var skin := SkinChoice.load_skin(&"modern")
	assert_str(String(skin.id)).is_equal("modern")
	assert_str(skin.display_name).is_not_empty()
	assert_object(skin.presenter_scene_or_null()).is_not_null()


func test_it_draws_smooth_and_does_not_snap() -> void:
	var render := _modern().render_settings()
	assert_int(render.texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
	assert_bool(render.snap_transforms).is_false()
	assert_bool(render.snap_vertices).is_false()
	SkinChoice.select(_modern())
	assert_bool(render.is_applied_to(get_tree().root)).is_true()


func test_the_font_is_the_skins_own_and_its_license_ships_with_it() -> void:
	var labels := _modern().labels()
	assert_object(labels).is_not_null()
	assert_object(labels.font).is_not_null()
	assert_bool(FileAccess.file_exists("res://skins/modern/fonts/Exo2.ttf")).is_true()
	var license := FileAccess.get_file_as_string("res://skins/modern/fonts/OFL.txt")
	assert_str(license).contains("SIL Open Font License")


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
	skin.art_folder = "res://skins/modern/no_such_folder"
	skin.art_scale = 4
	assert_object(skin.picture("frame/sub_00")).is_null()
	SkinChoice.select(skin)
	var original := load(DevPack.ROOT + "assets/sprites/sub/sub_00.png") as Texture2D
	assert_object(Catalog.sub_frames().get_frame_texture(&"all", 0)).is_same(original)


# --- the HUD's rectangles do not move with its font -------------------------------------------------------------

## The rectangles of the four lettering boxes for the sectors of SECTORS.
func _rectangles(hud: Hud) -> Dictionary:
	GameState.customized = true
	var found := {}
	for sector in SECTORS:
		GameState.set_sector(sector, 8)
		found[sector] = [hud.game_label, hud.zone_label, hud.sector_label, hud.custom_label].map(
				func(box: TextureRect) -> Rect2: return box.get_rect())
	return found


func test_the_modern_font_leaves_every_hud_rectangle_where_it_was() -> void:
	GameState.reset()
	GameState.customized = false
	GameState.set_sector(0, 9)
	var hud := scene_runner(HUD_SCENE).scene() as Hud
	var before := _rectangles(hud)
	SkinChoice.select(_modern())
	var after := _rectangles(hud)
	for sector in SECTORS:
		assert_array(after[sector]).override_failure_message("sector %d" % sector).is_equal(before[sector])
	assert_object(hud.game_label.texture).is_null()                              # (the words are text now ...)
	assert_str(hud.zone_text.text).is_equal(_modern().labels().zone_word(Catalog.sector(DevPack.TOUR_FINALE).zone))
	assert_object(hud.zone_text.get_theme_font(&"font")).is_same(_modern().labels().font)     # (... in the skin's font)
	SkinChoice.select(SkinChoice.original())
	assert_array(_rectangles(hud)[0]).is_equal(before[0])


# --- the water -------------------------------------------------------------------------------------------------------

func test_the_shimmer_is_on_the_background_and_nothing_else() -> void:
	SkinChoice.select(_modern())
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	var presenter := world.original
	assert_object(presenter).is_not_null()                                   # (it is an OriginalPresenter: the skin adds to it)
	assert_object(presenter.background.material).is_instanceof(ShaderMaterial)
	assert_str((presenter.background.material as ShaderMaterial).shader.resource_path).is_equal("res://skins/modern/water_shimmer.gdshader")
	for node: CanvasItem in [presenter.walls, presenter.currents, presenter.sub, presenter.foes_layer, presenter.front_decos, presenter.bubbles]:
		assert_object(node.material).is_null()                               # (the walls the rules read, the sub, the creatures: untouched)


func _phase(world: SectorWorld) -> float:
	return (world.original.background.material as ShaderMaterial).get_shader_parameter(&"phase")


func test_the_water_moves_with_the_ticks_and_stands_still_without_them() -> void:
	SkinChoice.select(_modern())
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	world.presenter.show_between_ticks(0.0)
	var start := _phase(world)
	world.presenter.show_between_ticks(0.0)
	assert_float(_phase(world)).is_equal(start)                            # (a frame without a tick: the same water)
	world.presenter.show_between_ticks(0.5)
	assert_float(_phase(world)).is_equal_approx(start + 0.5, 0.0001)       # (half a tick on: half a unit of phase)
	for i in 3:
		world.tick()
	world.presenter.show_between_ticks(0.0)
	assert_float(_phase(world)).is_equal_approx(start + 3.0, 0.0001)
	# The clock held (a problem, a message, the dissolve) means no ticks: the water stands still however many frames are drawn.
	var held := _phase(world)
	for i in 10:
		world.presenter.show_between_ticks(0.0)
	assert_float(_phase(world)).is_equal(held)


# --- the game is the same game --------------------------------------------------------------------------------------

func test_switching_to_the_modern_skin_and_back_in_the_middle_of_a_visit_changes_nothing() -> void:
	var plain := _visit(DevCreatures.ARENA, [])
	var switched := _visit(DevCreatures.ARENA, [_modern(), SkinChoice.original()])
	assert_int(switched.size()).is_equal(plain.size())
	for i in plain.size():
		if switched[i] != plain[i]:
			fail("the rules differ at line %d\n  original: %s\n  switching: %s" % [i, plain[i], switched[i]])
			break


func test_a_whole_visit_with_the_modern_skin_is_the_same_trace() -> void:
	var plain := _visit(DevCreatures.FISH, [])
	SkinChoice.select(_modern())
	var modern := _visit(DevCreatures.FISH, [_modern()], false)
	assert_int(modern.size()).is_equal(plain.size())
	for i in plain.size():
		if modern[i] != plain[i]:
			fail("the rules differ at line %d\n  original: %s\n  modern: %s" % [i, plain[i], modern[i]])
			break


## The trace of the scripted visit of `sector`; every 25 ticks the skin is the next of `skins` (none: it never changes).
func _visit(sector: int, skins: Array[GameSkin], reset_skin := true) -> Array[String]:
	GameState.reset()
	if reset_skin:
		SkinChoice.select(SkinChoice.original())
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var count := [0]
	var scenario := SectorScenario.new(world, GameState)
	scenario.after_tick = func() -> void:
		count[0] += 1
		if not skins.is_empty() and count[0] % 25 == 0:
			SkinChoice.select(skins[(count[0] / 25) % skins.size()])
	scenario.play(sector)
	if not skins.is_empty() and skins.size() > 1:
		assert_int(count[0]).is_greater(100)                                # (it switched, and more than once)
	return scenario.trace.lines
