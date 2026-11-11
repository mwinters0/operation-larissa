class_name TestSkinTheme
extends GdUnitTestSuite
## Teaches: a look as data. A skin's `theme` (fonts, colours, panel and button styles, pictures by key: `SkinTheme`) is checked in the manifest, read by `ModSkin.make` and laid on the engine's theme by `ThemeBuilder` when the skin is selected;
## the sign-in screen, a dialog and the message box (none of them knows of skins) take it from the project theme, open ones change when the skin does, and the engine's own theme comes back with the original. Wearing a theme moves
## no control: the scenes' rectangles and the order of their controls are the same under every theme (`test_plays_identically.gd` and `test_skins_dont_change_the_game.gd` play the fixture with every other skin).
## The example pack's theme is `test_example_pack_modern.gd`'s.

const FIXTURE := "res://tests/mods/skin_data"
const FONT := "skin/hud.ttf"
const KEY := "ui_picture/ui_1195"
const SIGN_IN := "res://src/ui/sign_in.tscn"
const DIALOG := "res://src/ui/new_player_dialog.tscn"
const ROSTER := "user://test_skin_theme_roster.json"
const HALL := "user://test_skin_theme_hall.json"

var _shelves: Array[PackShelf] = []
var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_old_roster = SaveStore.roster_path
	_old_hall = SaveStore.hall_path
	_old_players = SaveStore.players.duplicate()
	SaveStore.roster_path = ROSTER
	SaveStore.hall_path = HALL
	SaveStore.players = []
	SceneRouter.dry_run = true
	SignIn.welcome_enabled = false
	SignIn.prompt_when_empty = false


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	ModSkinShelf.release(_shelves)
	SkinChoice.select(SkinChoice.original())
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SceneRouter.dry_run = false
	SignIn.welcome_enabled = true
	SignIn.prompt_when_empty = true
	GameState.reset()
	for path in [ROSTER, HALL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


func _data(theme: Dictionary, api := ModSpec.DRAWS_THE_GAME_API_VERSION) -> Dictionary:
	return {"requires_api": api, "skin": {"theme": theme}}


## The data skin fixture, mounted and running.
func _mount() -> PackShelf:
	_shelves = ModSkinShelf.mount(["skin_data"] as Array[String])
	return _shelves[0]


## The `mod` override of `PackShelf.add_mod_fixture` that is the fixture's `skin` with `changes` laid over its keys (the override replaces whole keys of `mod`).
func _fixture_skin(changes: Dictionary) -> Dictionary:
	var skin: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("%s/pack.json" % FIXTURE))["mod"]["skin"] as Dictionary).duplicate(true)
	skin.merge(changes, true)
	return {"skin": skin}


func _skin(shelf: PackShelf) -> ModSkin:
	return SkinChoice.load_skin(shelf.id) as ModSkin


# --- the manifest ---------------------------------------------------------------------------------------------------------

func test_a_theme_is_a_font_colours_and_styles_and_it_round_trips() -> void:
	var theme := {
		"font": {"file": FONT, "weight": 600, "size": 16},
		"colors": {"text": "#ddeeff", "title": "#9fe8ff", "button_pressed": "#ffee6680"},
		"panel": {"fill": "#102030", "border": "#4488aa", "border_width": 2, "radius": 6, "margin": [8, 6]},
		"console": {"picture": KEY, "slice": [4, 4, 4, 4]},
		"button": {"normal": {"fill": "#183048"}, "pressed": {"radius": 0}},
		"input": {"focus": {"border": "#ffee66"}},
	}
	var got := _parse(_data(theme))
	assert_array(got[1]).is_empty()
	var spec: ModSpec = got[0]
	assert_str(spec.theme_font.file).is_equal(FONT)
	assert_int(spec.theme_font.weight).is_equal(600)
	assert_int(spec.theme.font_size).is_equal(16)
	assert_object(spec.theme.font).is_null()                                                        # (the file is read when the skin is made)
	assert_str(spec.theme.colors["title"].to_html(false)).is_equal("9fe8ff")
	assert_float(spec.theme.colors["button_pressed"].a).is_equal_approx(0x80 / 255.0, 0.001)
	assert_dict(spec.theme.styles["panel"]).is_equal({"fill": Color("#102030"), "border": Color("#4488aa"), "border_width": 2, "radius": 6, "margin": Vector2i(8, 6)})
	assert_dict(spec.theme.styles["console"]).is_equal({"picture": KEY, "slice": Vector4i(4, 4, 4, 4)})
	assert_array(spec.theme.styles.keys()).contains_exactly_in_any_order(["panel", "console", "button/normal", "button/pressed", "input/focus"])
	assert_dict(spec.to_dict()["skin"]["theme"]).is_equal(theme)
	assert_dict((_parse(spec.to_dict())[0] as ModSpec).to_dict()).is_equal(spec.to_dict())
	assert_array(spec.font_files()).is_equal([FONT])
	assert_array(spec.theme_pictures()).is_equal([KEY])


func test_a_theme_may_say_a_little_or_nothing() -> void:
	var empty: ModSpec = _parse(_data({}))[0]
	assert_object(empty.theme).is_not_null()
	assert_bool(empty.theme.is_empty()).is_true()
	assert_dict(empty.to_dict()["skin"]).is_equal({"theme": {}})
	var size_only: ModSpec = _parse(_data({"font": {"size": 15}}))[0]                               # (a size with no file: the engine's font, larger)
	assert_int(size_only.theme.font_size).is_equal(15)
	assert_str(size_only.theme_font.file).is_empty()
	assert_dict(size_only.to_dict()["skin"]["theme"]).is_equal({"font": {"size": 15}})
	assert_object((_parse({"requires_api": 5, "skin": {}})[0] as ModSpec).theme).is_null()
	assert_array((_parse(_data({"colors": {"text": "#ffffff"}}))[0] as ModSpec).font_files()).is_empty()


func test_every_mistake_in_a_theme_is_a_sentence() -> void:
	var bad := {
		"the API before drawing the game": [_data({}, ModSpec.RULE_API_VERSION), "requires_api\": %d" % ModSpec.DRAWS_THE_GAME_API_VERSION],
		"not an object": [{"requires_api": 5, "skin": {"theme": "dark"}}, "\"theme\" must be an object"],
		"a key it does not know": [_data({"sounds": {}}), "no \"sounds\""],
		"a font that is not an object": [_data({"font": FONT}), "\"font\" must be an object"],
		"a font key it does not know": [_data({"font": {"file": FONT, "color": "#ffffff"}}), "no \"color\""],
		"a font outside skin/": [_data({"font": {"file": "fonts/a.ttf"}}), "must be a file"],
		"a size too small": [_data({"font": {"size": ModSpec.MIN_THEME_FONT_SIZE - 1}}), "\"size\""],
		"a size too large": [_data({"font": {"size": ModSpec.MAX_THEME_FONT_SIZE + 1}}), "\"size\""],
		"a weight too light": [_data({"font": {"file": FONT, "weight": FontSpec.MIN_WEIGHT - 1}}), "\"weight\""],
		"a weight too heavy": [_data({"font": {"file": FONT, "weight": FontSpec.MAX_WEIGHT + 1}}), "\"weight\""],
		"a weight not whole": [_data({"font": {"file": FONT, "weight": 450.5}}), "\"weight\""],
		"a weight with no file": [_data({"font": {"weight": 600}}), "needs a \"file\""],
		"a weight of the API before drawing the game": [{"requires_api": ModSpec.RULE_API_VERSION, "skin": {"hud_font": {"file": FONT, "weight": 600}}}, "requires_api\": %d" % ModSpec.DRAWS_THE_GAME_API_VERSION],
		"colors not an object": [_data({"colors": ["#ffffff"]}), "\"colors\" must be an object"],
		"a colour it does not know": [_data({"colors": {"sky": "#ffffff"}}), "no \"sky\""],
		"a colour that is none": [_data({"colors": {"text": "white"}}), "colour \"text\""],
		"a style that is not an object": [_data({"panel": "dark"}), "\"panel\" must be an object"],
		"buttons that are not states": [_data({"button": "dark"}), "\"button\" must be an object of its states"],
		"a state it does not know": [_data({"button": {"active": {}}}), "no \"active\""],
		"a style key it does not know": [_data({"panel": {"shadow": 3}}), "no \"shadow\""],
		"a fill that is none": [_data({"panel": {"fill": 3}}), "\"fill\""],
		"a border width too wide": [_data({"panel": {"border_width": ModSpec.MAX_BORDER_WIDTH + 1}}), "\"border_width\""],
		"a negative radius": [_data({"panel": {"radius": -1}}), "\"radius\""],
		"a radius too round": [_data({"panel": {"radius": ModSpec.MAX_RADIUS + 1}}), "\"radius\""],
		"a margin of one number": [_data({"panel": {"margin": [4]}}), "\"margin\""],
		"a margin too wide": [_data({"panel": {"margin": [ModSpec.MAX_MARGIN + 1, 2]}}), "\"margin\""],
		"a margin not whole": [_data({"panel": {"margin": [2.5, 2]}}), "\"margin\""],
		"a slice of three": [_data({"panel": {"picture": KEY, "slice": [1, 2, 3]}}), "\"slice\""],
		"a slice too wide": [_data({"panel": {"picture": KEY, "slice": [1, 2, 3, ModSpec.MAX_SLICE + 1]}}), "\"slice\""],
		"a picture with no slice": [_data({"panel": {"picture": KEY}}), "needs a \"slice\""],
		"a slice with no picture": [_data({"panel": {"slice": [1, 1, 1, 1]}}), "which it has not"],
		"a picture key of no kind": [_data({"panel": {"picture": "sky", "slice": [1, 1, 1, 1]}}), "picture key"],
		"a picture that is a file": [_data({"panel": {"picture": "skin/sky.png", "slice": [1, 1, 1, 1]}}), "picture key"],
	}
	for what: String in bad:
		var got := _parse(bad[what][0])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_bool((got[1] as Array[String]).any(func(e: String) -> bool: return e.contains(bad[what][1]))) \
				.override_failure_message("%s: %s" % [what, got[1]]).is_true()


func test_a_scripted_skin_may_have_a_theme_too_because_it_is_data() -> void:
	var spec: ModSpec = _parse({"entry": "reef.sgd", "requires_api": 5, "skin": {"theme": {"colors": {"title": "#ffffff"}}}})[0]
	assert_object(spec).is_not_null()
	assert_bool(spec.has_entry()).is_true()
	assert_bool(spec.theme.colors.has("title")).is_true()


func test_a_hud_font_may_have_a_weight_and_no_file() -> void:
	var weighted: ModSpec = _parse({"requires_api": 5, "skin": {"hud_font": {"file": FONT, "weight": 700, "size": 12}}})[0]
	assert_int(weighted.hud_font_spec.weight).is_equal(700)
	assert_int(weighted.hud_font.font_size).is_equal(12)
	assert_dict(weighted.to_dict()["skin"]["hud_font"]).is_equal({"file": FONT, "weight": 700, "size": 12})
	var fileless: ModSpec = _parse({"requires_api": 5, "skin": {"hud_font": {"size": 12, "color": "#ffffff"}}})[0]
	assert_str(fileless.hud_font_spec.file).is_empty()
	assert_array(fileless.font_files()).is_empty()
	assert_dict(fileless.to_dict()["skin"]["hud_font"]).is_equal({"size": 12, "color": "#ffffff"})


# --- the pack and the skin the host makes ------------------------------------------------------------------------------------

func test_the_check_passes_a_theme_and_names_what_is_wrong() -> void:
	var sound := PackShelf.new()
	_shelves.append(sound)
	sound.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(sound)
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(sound.root), options)
	assert_bool(report.passes()).override_failure_message(report.text()).is_true()
	assert_array(report.warnings().filter(func(f: PackReport.Finding) -> bool: return f.area == "mod" and not f.message.contains("stretched"))).override_failure_message(report.text()).is_empty()      # (the fixture's one small picture stands in for several)
	var unnamed := PackShelf.new()                                                                      # (a theme's picture that nothing holds: the style is flat, and the author hears of it)
	_shelves.append(unnamed)
	unnamed.add_mod_fixture(FIXTURE, {"skin": {"theme": {"panel": {"picture": "ui_picture/no_such_picture", "slice": [1, 1, 1, 1]}}}})
	ModSkinShelf.add_files(unnamed)
	var warned := PackCheck.run(Pack.open(unnamed.root), options)
	assert_bool(warned.passes()).is_true()
	assert_bool(warned.warnings().any(func(f: PackReport.Finding) -> bool: return f.message.contains("ui_picture/no_such_picture") and f.message.contains("drawn flat"))).override_failure_message(warned.text()).is_true()
	var spoiled := PackShelf.new()                                                                      # (the font of the theme is no font)
	_shelves.append(spoiled)
	spoiled.add_mod_fixture(FIXTURE, _fixture_skin({"hud_font": {"size": 12}}))
	ModSkinShelf.add_files(spoiled)
	spoiled.write_text(FONT, "not a font at all")
	assert_bool(PackCheck.run(Pack.open(spoiled.root), options).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("theme font") and f.message.contains("not a TrueType font"))).is_true()


func test_a_font_that_only_the_theme_names_is_used() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE, _fixture_skin({"hud_font": {"size": 12}}))                                # (the HUD's lettering has no file of its own: the theme's font is the one in use)
	ModSkinShelf.add_files(shelf)
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(shelf.root), options)
	assert_bool(report.warnings().any(func(f: PackReport.Finding) -> bool: return f.message.contains("never used"))).override_failure_message(report.text()).is_false()


func test_the_host_makes_the_theme_with_its_font_read_through_the_pack() -> void:
	var shelf := _mount()
	var skin := _skin(shelf)
	var data := skin.menu_theme_in_use()
	assert_object(data).is_not_null()
	assert_object(SkinChoice.original().menu_theme_in_use()).is_null()
	var font := data.font as FontVariation
	assert_object(font).is_not_null()
	assert_object(font.base_font).is_same(shelf.pack.font(FONT))                                         # (`Pack.font`: the one door)
	assert_float(font.variation_opentype[FontSpec.WEIGHT_TAG]).is_equal(600.0)
	assert_int(data.font_size).is_equal(16)
	assert_str(data.colors["title"].to_html(false)).is_equal("9fe8ff")
	assert_object(shelf.pack.mod.theme.font).override_failure_message("the manifest's own record is not changed").is_null()
	assert_object(skin.hud_labels.font).is_not_null()
	assert_float((skin.hud_labels.font as FontVariation).variation_opentype[FontSpec.WEIGHT_TAG]).is_equal(600.0)


func test_a_theme_whose_font_is_no_font_refuses_the_skin() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE, _fixture_skin({"hud_font": {"size": 12}}))
	ModSkinShelf.add_files(shelf)
	shelf.write_text(FONT, "not a font")
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure(String(shelf.id))).contains("theme font").contains("not a TrueType font")
	assert_array(SkinChoice.available()).not_contains([shelf.id])


# --- the theme is the project theme's, derived from the skin ----------------------------------------------------------------

func test_the_engines_own_theme_is_what_a_skin_with_no_theme_wears() -> void:
	var project := ThemeDB.get_project_theme()
	var font := project.default_font
	var size := project.default_font_size
	var title := project.get_color("font_color", "ConsoleTitle")
	var normal := project.get_stylebox("normal", "Button") as StyleBoxFlat
	var fill := normal.bg_color
	SkinChoice.select(SkinChoice.original())
	assert_object(project.default_font).is_same(font)
	assert_object(ThemeBuilder.engine_font()).is_same(font)
	assert_object(Catalog.screen_layout().make_font()).is_same(font)
	var shelf := _mount()
	SkinChoice.select(_skin(shelf))
	assert_object(project.default_font).is_not_same(font)
	assert_object(Catalog.screen_layout().make_font()).override_failure_message("the diagrams' text is the engine's whatever the skin says").is_same(font)
	assert_object(ModLayer.theme_font()).override_failure_message("the text a mod draws is the theme in use's font").is_same(project.default_font)
	SkinChoice.select(SkinChoice.original())
	assert_object(project.default_font).is_same(font)
	assert_object(ModLayer.theme_font()).is_same(font)
	assert_int(project.default_font_size).is_equal(size)
	assert_str(project.get_color("font_color", "ConsoleTitle").to_html()).is_equal(title.to_html())
	assert_str((project.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color.to_html()).is_equal(fill.to_html())
	assert_bool(project.is_type_variation("ConsolePanel", "PanelContainer")).is_true()
	assert_bool(project.is_type_variation("CalcKey", "Button")).is_true()


func test_every_item_a_skin_may_say_is_one_the_engine_has() -> void:
	var engine := ThemeBuilder.engine()
	for name: String in SkinTheme.COLORS:
		assert_bool(ThemeBuilder.COLOR_ITEMS.has(name)).override_failure_message("colour %s has no items" % name).is_true()
		for item: Array in ThemeBuilder.COLOR_ITEMS[name]:
			assert_bool(engine.has_color(item[1], item[0])).override_failure_message("%s of %s" % [item[1], item[0]]).is_true()
	for name in SkinTheme.style_names():
		assert_bool(ThemeBuilder.STYLE_ITEMS.has(name)).override_failure_message("style %s has no items" % name).is_true()
		for item: Array in ThemeBuilder.STYLE_ITEMS[name]:
			assert_bool(engine.get_stylebox(item[1], item[0]) is StyleBoxFlat and engine.has_stylebox(item[1], item[0])).override_failure_message("%s of %s" % [item[1], item[0]]).is_true()
	assert_int(ThemeBuilder.COLOR_ITEMS.size()).is_equal(SkinTheme.COLORS.size())
	assert_int(ThemeBuilder.STYLE_ITEMS.size()).is_equal(SkinTheme.style_names().size())


func test_the_skin_lays_only_what_it_says_over_the_engines_theme() -> void:
	var shelf := _mount()
	var engine := ThemeBuilder.engine()
	var derived := ThemeBuilder.derive(_skin(shelf).menu_theme_in_use(), _skin(shelf))
	assert_str(derived.get_color("font_color", "ConsoleTitle").to_html(false)).is_equal("9fe8ff")                  # (said)
	assert_str(derived.get_color("font_color", "Hint").to_html(false)).is_equal("9fe8ff")
	assert_str(derived.get_color("font_color", "Label").to_html(false)).is_equal("ddeeff")
	assert_str(derived.get_color("font_color", "LineEdit").to_html(false)).is_equal("ddeeff")
	assert_str(derived.get_color("font_disabled_color", "Button").to_html(false)).is_equal("667788")
	assert_str(derived.get_color("font_color", "MenuBar").to_html()).is_equal(engine.get_color("font_color", "MenuBar").to_html())   # (not said: the engine's)
	assert_str(derived.get_color("font_color", "HudLabel").to_html(false)).is_equal("9fe8ff")
	var panel := derived.get_stylebox("panel", "ConsolePanel") as StyleBoxFlat
	assert_str(panel.bg_color.to_html(false)).is_equal("06121c")
	assert_int(panel.corner_radius_top_left).is_equal(8)
	assert_int(panel.border_width_left).is_equal(2)
	assert_float(panel.content_margin_left).is_equal(10.0)
	assert_float(panel.content_margin_top).is_equal(8.0)
	var hover := derived.get_stylebox("hover", "Button") as StyleBoxFlat
	var engine_hover := engine.get_stylebox("hover", "Button") as StyleBoxFlat
	assert_str(hover.bg_color.to_html(false)).is_equal("285070")                                                  # (the fill said)
	assert_str(hover.border_color.to_html()).is_equal(engine_hover.border_color.to_html())                          # (the border not: the engine's)
	assert_float(hover.content_margin_left).is_equal(engine_hover.content_margin_left)
	assert_object(engine_hover).override_failure_message("the engine's own style is never changed").is_not_same(hover)
	var pressed := derived.get_stylebox("pressed", "Button") as StyleBoxTexture                                     # (a picture by key)
	assert_object(pressed).is_not_null()
	assert_object(pressed.texture).is_same(_skin(shelf).pictures[KEY])
	assert_float(pressed.texture_margin_left).is_equal(4.0)
	var engine_pressed := engine.get_stylebox("pressed", "Button") as StyleBoxFlat
	assert_float(pressed.content_margin_left).override_failure_message("a picture keeps the engine's content margins").is_equal(engine_pressed.content_margin_left)
	assert_int(derived.default_font_size).is_equal(16)
	assert_bool(derived.default_font is FontVariation).is_true()
	assert_bool(derived.is_type_variation("ConsolePanel", "PanelContainer")).is_true()


func test_a_style_whose_picture_nothing_holds_is_drawn_flat() -> void:
	var data := SkinTheme.new()
	data.styles["panel"] = {"picture": "ui_picture/no_such_picture", "slice": Vector4i(2, 2, 2, 2), "fill": Color.RED}
	var derived := ThemeBuilder.derive(data, SkinChoice.original())
	var panel := derived.get_stylebox("panel", "Panel") as StyleBoxFlat
	assert_object(panel).is_not_null()
	assert_str(panel.bg_color.to_html(false)).is_equal("ff0000")


# --- what the screens show ---------------------------------------------------------------------------------------------------

## Every control under `node` by its path: the rectangle it has and the order it comes in.
func _rects(node: Node) -> Dictionary:
	var found := {}
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var each: Node = stack.pop_back()
		for child in each.get_children():
			stack.append(child)
		if each is Control:
			found[node.get_path_to(each)] = (each as Control).get_rect()
	return found


func _order(node: Node) -> Array[String]:
	var found: Array[String] = []
	for each in node.find_children("*", "Control", true, false):
		found.append(String(node.get_path_to(each)))
	return found


## The fixture's theme without its font: colours, styles and a picture, whose margins and border widths are the engine's.
func _look_only() -> Dictionary:
	var theme: Dictionary = (_fixture_skin({})["skin"]["theme"] as Dictionary).duplicate(true)
	theme.erase("font")
	return _fixture_skin({"theme": theme})


## Does the control sit at a place its scene gave it (a parent that is no container lays it out by the sizes the scene wrote)?
func _is_placed_by_scene(control: Control) -> bool:
	return not control.get_parent() is Container


func test_the_sign_in_screen_wears_a_look_and_not_one_control_moves() -> void:
	var screen := scene_runner(SIGN_IN).scene() as SignIn
	await await_idle_frame()
	await await_idle_frame()
	var plain_rects := _rects(screen)
	var plain_order := _order(screen)
	var plain_title := screen.get_node("Heading").get_theme_color(&"font_color") as Color
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE, _look_only())
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	SkinChoice.select(_skin(shelf))                                                                       # (selected while the screen is open: bound mid-anything)
	await await_idle_frame()
	assert_str(screen.start_button.get_theme_color(&"font_color").to_html(false)).is_equal("aaccee")
	assert_str(screen.start_button.get_theme_color(&"font_hover_color").to_html(false)).is_equal("ffffff")
	assert_str((screen.start_button.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color.to_html(false)).is_equal("183048")
	assert_str(screen.get_node("Heading").get_theme_color(&"font_color").to_html(false)).is_equal("ddeeff")
	assert_object(screen.start_button.get_theme_font(&"font")).is_same(ThemeBuilder.engine_font())        # (no font said: the engine's)
	assert_str(plain_title.to_html(false)).is_not_equal("ddeeff")
	assert_array(_order(screen)).is_equal(plain_order)
	var worn := _rects(screen)
	for path: NodePath in plain_rects:
		assert_object(worn[path]).override_failure_message("%s moved: %s -> %s" % [path, plain_rects[path], worn[path]]).is_equal(plain_rects[path])
	SkinChoice.select(SkinChoice.original())                                                              # (taken off again: the engine's)
	await await_idle_frame()
	assert_str(screen.get_node("Heading").get_theme_color(&"font_color").to_html()).is_equal(plain_title.to_html())
	assert_array(_order(screen)).is_equal(plain_order)
	var again := _rects(screen)
	for path: NodePath in plain_rects:
		assert_object(again[path]).override_failure_message("%s moved" % path).is_equal(plain_rects[path])


## A font of its own changes what a container makes of its children (a button is as wide as its text, down to its minimum), never what a scene placed or the order: the controls a scene placed keep their rectangles.
func test_a_font_moves_no_control_the_scene_placed_and_changes_no_order() -> void:
	var screen := scene_runner(SIGN_IN).scene() as SignIn
	await await_idle_frame()
	var plain_rects := _rects(screen)
	var plain_order := _order(screen)
	var shelf := _mount()
	SkinChoice.select(_skin(shelf))
	await await_idle_frame()
	assert_object(screen.start_button.get_theme_font(&"font")).is_same(ThemeDB.get_project_theme().default_font)
	assert_int(screen.start_button.get_theme_font_size(&"font_size")).is_equal(16)
	assert_array(_order(screen)).is_equal(plain_order)
	var placed := 0
	for path: NodePath in plain_rects:
		var control := screen.get_node(path) as Control
		if _is_placed_by_scene(control):
			placed += 1
			assert_object(control.get_rect()).override_failure_message("%s moved" % path).is_equal(plain_rects[path])
	assert_int(placed).is_greater(5)


func test_a_screen_opened_after_the_skin_wears_it_too() -> void:
	var shelf := _mount()
	SkinChoice.select(_skin(shelf))
	var screen := scene_runner(SIGN_IN).scene() as SignIn
	await await_idle_frame()
	assert_str(screen.start_button.get_theme_color(&"font_color").to_html(false)).is_equal("aaccee")


func test_a_button_pressed_when_the_skin_changes_is_pressed_in_the_new_look() -> void:
	var screen := scene_runner(SIGN_IN).scene() as SignIn
	await await_idle_frame()
	screen._show_pressed(screen.exit_button)
	var engine_pressed := (screen.exit_button.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color
	var shelf := _mount()
	SkinChoice.select(_skin(shelf))
	await await_idle_frame()
	assert_bool(screen.looks_pressed(screen.exit_button)).is_true()
	var worn := screen.exit_button.get_theme_stylebox(&"normal")
	assert_object(worn).is_instanceof(StyleBoxTexture)                                                      # (the skin's pressed picture)
	assert_str(screen.exit_button.get_theme_color(&"font_color").to_html(false)).is_equal("ffee66")
	assert_str(engine_pressed.to_html(false)).is_not_equal("ffee66")


func test_a_dialog_on_a_canvas_layer_wears_the_theme_and_keeps_its_order() -> void:
	var holder := auto_free(Control.new()) as Control
	var layer := CanvasLayer.new()                                                                          # (a canvas layer breaks the chain of a theme set on a node: the project theme is not)
	holder.add_child(layer)
	var dialog := load(DIALOG).instantiate() as NewPlayerDialog
	layer.add_child(dialog)
	add_child(holder)
	await await_idle_frame()
	var order := _order(dialog)
	assert_str(dialog.name_title.get_theme_color(&"font_color").to_html(false)).is_not_equal("9fe8ff")
	var shelf := _mount()
	SkinChoice.select(_skin(shelf))
	await await_idle_frame()
	assert_str(dialog.name_title.get_theme_color(&"font_color").to_html(false)).is_equal("9fe8ff")          # (ConsoleTitle: `title`)
	assert_str((dialog.name_panel.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color.to_html(false)).is_equal("06121c")   # (ConsolePanel: `console`)
	assert_str((dialog.name_edit.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color.to_html(false)).is_equal("000a12")
	assert_str(dialog.name_text.get_theme_color(&"font_color").to_html(false)).is_equal("ddeeff")
	assert_array(_order(dialog)).is_equal(order)
	SkinChoice.select(SkinChoice.original())
	await await_idle_frame()
	assert_str(dialog.name_title.get_theme_color(&"font_color").to_html(false)).is_not_equal("9fe8ff")
	holder.queue_free()


func test_the_message_box_wears_the_theme_and_its_buttons_stay_in_order() -> void:
	var screen := scene_runner(SIGN_IN).scene() as SignIn
	await await_idle_frame()
	screen.messages.post("Exit", "Do you want to exit?", PackedStringArray(["Yes", "No"]))
	await await_idle_frame()
	var view := screen.message_view
	assert_bool(view.visible).is_true()
	var plain_title := view.title_label.get_theme_color(&"font_color").to_html(false)
	var shelf := _mount()
	SkinChoice.select(_skin(shelf))
	await await_idle_frame()
	assert_str(view.title_label.get_theme_color(&"font_color").to_html(false)).is_equal("9fe8ff")
	assert_str(plain_title).is_not_equal("9fe8ff")
	assert_str((view.get_node("Center/Panel").get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color.to_html(false)).is_equal("06121c")
	assert_str(view.body_label.get_theme_color(&"default_color").to_html(false)).is_equal("ddeeff")
	var buttons := view.button_row.get_children().map(func(b: Node) -> String: return (b as Button).text)
	assert_array(buttons).is_equal(["Yes", "No"])
	assert_str((view.button_row.get_child(0) as Button).get_theme_color(&"font_color").to_html(false)).is_equal("aaccee")
	screen.messages.close_current(1)


func test_the_huds_lettering_without_a_font_of_its_own_takes_the_themes() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE, _fixture_skin({"hud_font": {"size": 12}}))
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	GameState.customized = true
	GameState.set_sector(0, 9)
	var hud := scene_runner("res://src/ui/hud.tscn").scene() as Hud
	SkinChoice.select_id(shelf.id)
	assert_object(_skin(shelf).labels().font).is_null()
	for text: Label in [hud.game_text, hud.zone_text, hud.sector_text, hud.custom_text]:
		assert_bool(text.visible).is_true()
		assert_object(text.get_theme_font(&"font")).is_same(ThemeDB.get_project_theme().default_font)       # (no `hud_font` file: the theme's font)
		assert_int(text.get_theme_font_size(&"font_size")).is_equal(12)


func test_the_fixture_under_the_modern_pack_does_not_leave_a_theme_behind() -> void:
	var shelf := _mount()
	SkinChoice.select(_skin(shelf))
	ModSkinShelf.release(_shelves)                                                                          # (the pack leaves the chain: the original is put on, and with it the engine's theme)
	assert_object(SkinChoice.current()).is_same(SkinChoice.original())
	assert_str(ThemeDB.get_project_theme().get_color("font_color", "ConsoleTitle").to_html(false)).is_equal(ThemeBuilder.engine().get_color("font_color", "ConsoleTitle").to_html(false))
