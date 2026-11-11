class_name TestExamplePackModern
extends GdUnitTestSuite
## Teaches: testing an example the way a stranger's pack is tested. `examples/packs/modern/` is a folder outside the project, a skin pack with no script: the test loads that very folder as a pack (laid over the dev pack here,
## over the legacy pack in play), has `PackCheck` judge it, and wears it, so what the docs show a creator to copy is known to work. What it proves: the water shimmer is on the `background` layer and moves with the game's time, the walls
## stay sharp under a smooth filter, the HUD is lettered in Exo 2 (whose licence sits next to the font), the HUD's pictures are the templates at the original's sizes, and wearing it changes no rule (`test_plays_identically.gd`,
## `test_skins_dont_change_the_game.gd` and `test_presenter_binds_late.gd` play it through `SkinRoster`).

## The id the pack has in a test (`ModSkinShelf`: the id of its manifest and `_test`, so that a copy of it installed for playing is not the one found).
const ID := &"modern_test"
const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const HUD_SCENE := "res://src/ui/hud.tscn"
const WATER := "skin/water_shimmer.gdshader"
const WALLS := "skin/sharp_walls.gdshader"
const FONT := "skin/fonts/Exo2.ttf"
## The pictures of the console the templates cover (`SkinTemplates`): the manifest maps each key to the template of that name.
const PICTURE_COUNT := 24

var _shelves: Array[PackShelf] = []


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	ModSkinShelf.release(_shelves)
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


## The example pack, mounted over the suite's pack and running.
func _mount() -> PackShelf:
	_shelves = ModSkinShelf.mount([ModSkinShelf.EXAMPLE_MODERN] as Array[String])
	return _shelves[0]


func _skin() -> ModSkin:
	return SkinChoice.load_skin(ID) as ModSkin


func _folder() -> String:
	return ModSkinShelf.example_folder("modern")


# --- the folder -------------------------------------------------------------------------------------------------------------

func test_the_folder_is_a_skin_pack_with_no_script() -> void:
	var pack := Pack.open(_folder())
	assert_array(pack.errors).is_empty()
	assert_str(String(pack.id)).is_equal("modern")
	assert_str(String(pack.base)).is_equal("legacy")                                           # (laid over the original's content: the templates are its sizes)
	assert_bool(pack.mod.is_skin).is_true()
	assert_bool(pack.mod.has_entry()).is_false()                                               # (a data skin: no Sandbox)
	assert_int(pack.mod.render.texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
	assert_bool(pack.mod.render.snap_transforms).is_false()
	assert_bool(pack.mod.render.snap_vertices).is_false()
	assert_dict(pack.mod.layers).contains_keys([&"background", &"walls"])
	assert_int(pack.mod.pictures.size()).is_equal(PICTURE_COUNT)
	assert_str(pack.mod.hud_font_spec.file).is_equal(FONT)


func test_the_font_ships_with_its_licence() -> void:
	assert_bool(FileAccess.file_exists("%s/%s" % [_folder(), FONT])).is_true()
	var licence := FileAccess.get_file_as_string("%s/%s/OFL.txt" % [_folder(), FONT.get_base_dir()])
	assert_str(licence).contains("SIL Open Font License")


func test_every_picture_of_the_manifest_is_a_template_file_of_the_folder() -> void:
	var pack := Pack.open(_folder())
	for key: String in pack.mod.pictures:
		var file: String = pack.mod.pictures[key]
		assert_str(key).starts_with("ui_picture/")
		assert_str(file).is_equal("skin/ui_picture/%s.png" % key.get_slice("/", 1))
		var image := Image.load_from_file("%s/%s" % [_folder(), file])
		assert_object(image).override_failure_message(file).is_not_null()
		assert_bool(image.get_width() > 0 and image.get_height() > 0).is_true()
		assert_int(image.get_pixel(0, 0).a8).is_equal(255)                                        # (flat colour: the template has no art in it)


func test_the_pack_check_passes_it_and_has_nothing_to_say() -> void:
	var shelf := _mount()
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(shelf.root), options)
	assert_bool(report.passes()).override_failure_message(report.text()).is_true()
	assert_array(report.warnings().filter(func(f: PackReport.Finding) -> bool: return f.area == "mod")).override_failure_message(report.text()).is_empty()


func test_it_is_a_skin_of_the_game_while_its_pack_runs_and_not_after() -> void:
	_mount()
	assert_array(SkinChoice.available()).contains([&"original", ID])
	assert_object(_skin()).is_not_null()
	assert_str(ModHost.failure(String(ID))).is_empty()
	ModSkinShelf.release(_shelves)
	assert_array(SkinChoice.available()).not_contains([ID])


# --- what wearing it changes ----------------------------------------------------------------------------------------------

func test_it_draws_smooth_and_does_not_snap() -> void:
	_mount()
	var render := _skin().render_settings()
	assert_int(render.texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
	SkinChoice.select(_skin())
	assert_bool(render.is_applied_to(get_tree().root)).is_true()
	assert_bool(get_tree().root.snap_2d_transforms_to_pixel).is_false()
	assert_bool(get_tree().root.snap_2d_vertices_to_pixel).is_false()


func test_the_hud_is_lettered_in_exo_2_and_its_boxes_keep_their_rectangles() -> void:
	_mount()
	GameState.customized = true
	GameState.set_sector(0, 9)
	var hud := scene_runner(HUD_SCENE).scene() as Hud
	var boxes: Array[TextureRect] = [hud.game_label, hud.zone_label, hud.sector_label, hud.custom_label]
	var texts: Array[Label] = [hud.game_text, hud.zone_text, hud.sector_text, hud.custom_text]
	var plain := boxes.map(func(box: TextureRect) -> Rect2: return box.get_rect())
	SkinChoice.select(_skin())
	for i in boxes.size():
		assert_bool(texts[i].visible).is_true()
		assert_str(texts[i].get_theme_font(&"font").get_font_name()).contains("Exo")
		assert_int(texts[i].get_theme_font_size(&"font_size")).is_equal(14)
		assert_str(texts[i].get_theme_color(&"font_color").to_html(false)).is_equal("dbf7ff")
		assert_object(boxes[i].get_rect().position).override_failure_message("box %d" % i).is_equal(plain[i].position)
	SkinChoice.select(SkinChoice.original())
	for i in boxes.size():
		assert_bool(texts[i].visible).is_false()
		assert_object(boxes[i].get_rect()).is_equal(plain[i])


func test_the_templates_are_worn_only_while_the_skin_is() -> void:
	var shelf := _mount()
	var skin := _skin()
	assert_int(skin.pictures.size()).is_equal(PICTURE_COUNT)
	var key := "ui_picture/ui_1195"                                                                 # (the first zone's name box of the console)
	var mapped: Texture2D = skin.pictures[key]
	var image := Image.load_from_file("%s/skin/ui_picture/ui_1195.png" % _folder())
	assert_object(mapped.get_size()).is_equal(Vector2(image.get_size()))
	var plain := Catalog.hud_layout().zone_textures[0]
	assert_object(plain).is_not_same(mapped)
	SkinChoice.select_id(shelf.id)
	assert_object(Catalog.hud_layout().zone_textures[0]).is_same(mapped)
	SkinChoice.select(SkinChoice.original())
	assert_object(Catalog.hud_layout().zone_textures[0]).is_same(plain)


func _shader_code(node: CanvasItem) -> String:
	var material := node.material as ShaderMaterial
	return "" if material == null else material.shader.code


func test_the_water_is_on_the_background_and_the_walls_stay_sharp() -> void:
	_mount()
	var skin := _skin()
	SkinChoice.select(skin)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	var presenter := world.original
	assert_object(presenter).is_not_null()                                                         # (the original presenter: a data skin brings no scene)
	assert_object(presenter.background.material).is_instanceof(ShaderMaterial)
	assert_str(_shader_code(presenter.background)).is_equal(skin.assets.shaders[WATER].code).contains("uniform float phase")
	assert_str(_shader_code(presenter.walls)).is_equal(skin.assets.shaders[WALLS].code)
	for layer: StringName in SkinLayers.NODES:
		if not [&"background", &"walls"].has(layer):
			assert_object(presenter.layer_node(layer).material).override_failure_message(String(layer)).is_null()    # (the sub, the creatures, the decorations: untouched)


func _phase(presenter: OriginalPresenter) -> float:
	return (presenter.background.material as ShaderMaterial).get_shader_parameter(&"phase")


func test_the_water_moves_with_the_ticks_and_stands_still_without_them() -> void:
	_mount()
	SkinChoice.select(_skin())
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	world.presenter.show_between_ticks(0.0)
	var start := _phase(world.original)
	world.presenter.show_between_ticks(0.5)
	assert_float(_phase(world.original)).is_equal_approx(start + 0.5, 0.0001)                       # (half a tick on: half a unit of phase)
	for i in 3:
		world.tick()
	world.presenter.show_between_ticks(0.0)
	assert_float(_phase(world.original)).is_equal_approx(start + 3.0, 0.0001)
	var held := _phase(world.original)                                                              # (the clock held: no ticks, the water stands still)
	for i in 10:
		world.presenter.show_between_ticks(0.0)
	assert_float(_phase(world.original)).is_equal(held)


func test_the_skin_goes_and_the_water_goes_with_it() -> void:
	var shelf := _mount()
	SkinChoice.select_id(shelf.id)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	assert_object(world.original.background.material).is_instanceof(ShaderMaterial)
	SkinChoice.select(SkinChoice.original())
	for layer: StringName in SkinLayers.NODES:
		assert_object(world.original.layer_node(layer).material).override_failure_message(String(layer)).is_null()


func test_the_menus_are_in_exo_2_at_weight_600_in_a_theme_of_cool_blues() -> void:
	var shelf := _mount()
	var pack := Pack.open(_folder())
	assert_int(pack.mod.theme_font.weight).is_equal(600)
	assert_int(pack.mod.hud_font_spec.weight).is_equal(600)                                         # (the old project skin's weight, which a data skin could not say)
	assert_array(pack.mod.font_files()).is_equal([FONT])
	SkinChoice.select_id(shelf.id)
	var project := ThemeDB.get_project_theme()
	var font := project.default_font as FontVariation
	assert_object(font).is_not_null()
	assert_str(font.base_font.get_font_name()).contains("Exo 2")
	assert_float(font.variation_opentype[FontSpec.WEIGHT_TAG]).is_equal(600.0)
	assert_bool((font.base_font as FontFile).get_supported_variation_list().has(FontSpec.WEIGHT_TAG)).override_failure_message("Exo 2 has a weight axis").is_true()
	assert_int(project.default_font_size).is_equal(16)
	assert_str(project.get_color("font_color", "ConsoleTitle").to_html(false)).is_equal("7fe0ff")
	assert_str((project.get_stylebox("panel", "ConsolePanel") as StyleBoxFlat).bg_color.to_html(false)).is_equal("07151f")
	assert_int((project.get_stylebox("normal", "Button") as StyleBoxFlat).corner_radius_top_left).is_equal(6)
	assert_float((project.get_stylebox("normal", "Button") as StyleBoxFlat).content_margin_left).is_equal(ThemeBuilder.engine().get_stylebox("normal", "Button").content_margin_left)   # (it says no margin: the controls keep their sizes)
	SkinChoice.select(SkinChoice.original())
	assert_object(project.default_font).is_same(ThemeBuilder.engine().default_font)


func test_the_problem_screens_frame_wears_the_theme() -> void:
	var shelf := _mount()
	SkinChoice.select_id(shelf.id)
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.start(ProblemFactory.make(1, 0, null, 0))
	assert_str(screen.title_label.get_theme_color(&"font_color").to_html(false)).is_equal("dbf7ff")                  # (`text`)
	assert_str(screen.text_label.get_theme_color(&"default_color").to_html(false)).is_equal("dbf7ff")
	assert_str(screen.calculator.display.get_theme_color(&"field", &"LcdDisplay").to_html(false)).is_equal("041018")   # (`display`)
	var key := screen.calculator.keys.get_child(0) as Button
	assert_str((key.get_theme_stylebox(&"hover") as StyleBoxFlat).border_color.to_html(false)).is_equal("7fe0ff")      # (`key`)
	assert_str((key.get_theme_stylebox(&"pressed") as StyleBoxFlat).bg_color.to_html()).is_equal("ffe27a60")
	assert_object(screen.title_label.get_theme_font(&"font")).is_same(ThemeDB.get_project_theme().default_font)
	assert_object(screen.title_label.get_theme_font(&"font")).is_not_same(ThemeBuilder.engine_font())              # (the diagrams' text keeps the engine's font: `DiagramBase.font`)
	assert_object(screen.diagram.font).is_same(ThemeBuilder.engine_font())
	screen.free()


## The templates of the problem screen's frame ship in `skin/problem_art/` and the sender's two in `skin/ui_picture/`, unmapped: a flat calculator would hide its keys, so the author maps the ones drawn over.
func test_the_templates_of_the_problem_screens_frame_are_in_the_folder_and_not_mapped() -> void:
	var pack := Pack.open(_folder())
	var found := DirAccess.get_files_at("%s/skin/problem_art" % _folder())
	assert_array(found).is_not_empty()
	for file in found:
		var name := file.get_basename()
		assert_bool(NameRegistry.original().index_of(&"problem_art", name) >= 0).override_failure_message(file).is_true()
		assert_bool(pack.mod.pictures.has("problem_art/%s" % name)).override_failure_message(file).is_false()
		var image := Image.load_from_file("%s/skin/problem_art/%s" % [_folder(), file])
		assert_int(image.get_pixel(0, 0).a8).is_equal(255)
	for sender in [PromptSender.PICTURE_SHIP, PromptSender.PICTURE_CONTROL_ROOM]:
		var image := Image.load_from_file("%s/skin/ui_picture/%s.png" % [_folder(), sender])
		assert_object(Vector2i(image.get_size())).is_equal(PromptSender.PICTURE_SIZE)
		assert_bool(pack.mod.pictures.has("ui_picture/%s" % sender)).is_false()
	assert_bool(FileAccess.file_exists("%s/problems/problem_layer/window.png" % _folder())).is_true()
