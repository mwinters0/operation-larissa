class_name TestSkinProblemFrame
extends GdUnitTestSuite
## Teaches: a theme that reaches a screen made of pictures and controls. The problem screen's frame is the original's pictures (the screen, the calculator, the "Ans:" panel, the sender's small picture) with controls over and
## around them (the labels, the text box, a button over each key of the calculator) and a field the digits are drawn on. A skin's `theme` says the colours of the text, the glass of a key and the field's colour (`SkinTheme`,
## `ThemeBuilder`); the pictures are the chain's (`pictures.json` of the packs, by key: `problem_art`, `ui_picture`), under every skin; every control looks the theme up and every picture is put on by one builder (`ProblemScreen._dress`, `Calculator._dress`, `AnswerBox._dress`),
## so a screen made under the skin and one the skin is put on under look the same, and none of it moves a rectangle or changes a play. `test_skin_theme.gd` is the theme of the menus; the example pack's is `test_example_pack_modern.gd`.

const FIXTURE := "res://tests/mods/skin_data"
const SKY := "skin/sky.png"
const TYPE := 1                                     # a problem whose answer is typed on the calculator

var _shelves: Array[PackShelf] = []
var _unnumbered := RegEx.create_from_string("@([A-Za-z]+)@\\d+")


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	ModSkinShelf.release(_shelves)
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


func _data(changes: Dictionary, api := ModSpec.DRAWS_THE_GAME_API_VERSION) -> Dictionary:
	return {"requires_api": api, "skin": changes}


func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


func _complains(parsed: Array, words: String) -> bool:
	return parsed[0] == null and (parsed[1] as Array[String]).any(func(e: String) -> bool: return e.contains(words))


## The fixture's `skin` with `changes` laid over its keys, as a mod override of `PackShelf.add_mod_fixture`.
func _fixture_skin(changes: Dictionary) -> Dictionary:
	var skin: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("%s/pack.json" % FIXTURE))["mod"]["skin"] as Dictionary).duplicate(true)
	skin.merge(changes, true)
	return {"skin": skin}


## The fixture's theme without its font (a font changes what a label needs, and a label that needs more is larger: the rectangles are compared) and the fixture's pictures: a skin that dresses the frame and says its colours.
func _frame_skin() -> Dictionary:
	var theme: Dictionary = (_fixture_skin({})["skin"]["theme"] as Dictionary).duplicate(true)
	theme.erase("font")
	return _fixture_skin({"theme": theme})


## The fixture as a pack in use (its pictures are flat 32 x 18 files, so nothing it dresses has the size of the original's), and its skin.
func _mount(mod: Dictionary = {}) -> ModSkin:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE, mod if not mod.is_empty() else _frame_skin())
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	return SkinChoice.load_skin(shelf.id) as ModSkin


func _screen(problem: ProblemInstance = null) -> ProblemScreen:
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.start(problem if problem != null else ProblemFactory.make(TYPE, 0, null, 0))
	return screen


## A path without the numbers the engine gives the nodes it names itself (`@Control@192731`): two screens are compared by place, not by those.
func _place(node: Node, each: Node) -> String:
	return _unnumbered.sub(String(node.get_path_to(each)), "@$1@", true)


func _rects(node: Node) -> Array[Rect2]:
	var found: Array[Rect2] = []
	for each in node.find_children("*", "Control", true, false):
		found.append((each as Control).get_rect())
	return found


func _order(node: Node) -> Array[String]:
	var found: Array[String] = []
	for each in node.find_children("*", "Control", true, false):
		found.append(_place(node, each))
	return found


## The button over the calculator's key `key`.
func _key(calculator: Calculator, key: String) -> Button:
	for button in calculator.keys.get_children():
		if (button as Button).tooltip_text == key:
			return button
	return null


# --- the manifest ---------------------------------------------------------------------------------------------------------

func test_the_keys_and_display_are_in_the_manifest_from_the_api_that_brought_them() -> void:
	var look := {"theme": {"colors": {"display": "#001a33"}, "key": {"normal": {"fill": "#00000010"}, "hover": {"fill": "#66ccee40", "border": "#66ccee"}, "pressed": {"fill": "#ffee6680"}}}}
	var got := _parse(_data(look))
	assert_array(got[1]).is_empty()
	var spec: ModSpec = got[0]
	assert_str(spec.theme.colors["display"].to_html(false)).is_equal("001a33")
	assert_array(spec.theme.styles.keys()).contains_exactly_in_any_order(["key/normal", "key/hover", "key/pressed"])
	assert_dict(spec.to_dict()["skin"]).is_equal(look)
	assert_dict((_parse(spec.to_dict())[0] as ModSpec).to_dict()).is_equal(spec.to_dict())
	var old := ModSpec.RULE_API_VERSION                                                               # (the API before: each of them is refused by name)
	assert_bool(_complains(_parse(_data({"theme": {"colors": {"display": "#001a33"}}}, old)), "requires_api\": %d" % ModSpec.DRAWS_THE_GAME_API_VERSION)).is_true()
	assert_bool(_complains(_parse(_data({"theme": {"key": {"hover": {}}}}, old)), "requires_api\": %d" % ModSpec.DRAWS_THE_GAME_API_VERSION)).is_true()
	assert_bool(_complains(_parse(_data({"theme": {"key": {"focus": {}}}})), "no \"focus\"")).is_true()   # (a key has three states)
	assert_bool(_complains(_parse(_data({"pictures": {"problem_art/pa_1780": SKY}})), "pictures.json")).is_true()   # (the frame's pictures are the pack's: rows of its table, not a skin's)


func test_the_check_passes_a_skin_that_dresses_the_frame() -> void:
	_mount()
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(_shelves[0].root), options)
	assert_bool(report.passes()).override_failure_message(report.text()).is_true()
	assert_array(report.warnings().filter(func(f: PackReport.Finding) -> bool: return f.area == "mod" and not f.message.contains("stretched"))).override_failure_message(report.text()).is_empty()


# --- the colours, the keys and the field -------------------------------------------------------------------------------------

func test_the_text_of_the_screen_and_the_glass_of_a_key_and_the_field_are_the_skins() -> void:
	var screen := _screen()
	await await_idle_frame()
	var plain_title := screen.title_label.get_theme_color(&"font_color").to_html(false)
	var plain_field := screen.calculator.display.get_theme_color(&"field", &"LcdDisplay").to_html(false)
	var plain_hover := (_key(screen.calculator, "1").get_theme_stylebox(&"hover") as StyleBoxFlat).bg_color.to_html()
	assert_str(plain_title).is_equal("ffffff")                                                         # (the engine's: the palette's white)
	assert_str(plain_field).is_equal("000000")
	SkinChoice.select(_mount())                                                                       # (put on while the screen is up)
	await await_idle_frame()
	assert_str(screen.title_label.get_theme_color(&"font_color").to_html(false)).is_equal("ddeeff")
	assert_str(screen.sender_header.get_theme_color(&"font_color").to_html(false)).is_equal("ddeeff")
	assert_str(screen.text_label.get_theme_color(&"default_color").to_html(false)).is_equal("ddeeff")
	assert_str(screen.feedback.get_theme_color(&"font_color").to_html(false)).is_equal("ddeeff")
	assert_str(screen.calculator.display.get_theme_color(&"field", &"LcdDisplay").to_html(false)).is_equal("001a33")
	assert_str(screen.answer_box.display.get_theme_color(&"field", &"LcdDisplay").to_html(false)).is_equal("001a33")
	var hover := _key(screen.calculator, "1").get_theme_stylebox(&"hover") as StyleBoxFlat
	assert_str(hover.bg_color.to_html()).is_equal("66ccee40")
	assert_str((_key(screen.calculator, "1").get_theme_stylebox(&"pressed") as StyleBoxFlat).bg_color.to_html()).is_equal("ffee6680")
	assert_int(hover.border_width_left).is_equal(1)
	assert_str((_key(screen.calculator, "1").get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color.to_html()).is_equal("00000000")    # (not said: clear, the art shows)
	SkinChoice.select(SkinChoice.original())
	await await_idle_frame()
	assert_str(screen.title_label.get_theme_color(&"font_color").to_html(false)).is_equal(plain_title)
	assert_str(screen.calculator.display.get_theme_color(&"field", &"LcdDisplay").to_html(false)).is_equal(plain_field)
	assert_str((_key(screen.calculator, "1").get_theme_stylebox(&"hover") as StyleBoxFlat).bg_color.to_html()).is_equal(plain_hover)


func test_the_line_of_an_error_wears_the_skins_bad_colour_and_the_other_lines_the_text_colour() -> void:
	var screen := _screen()
	screen.advance_ticks(2000)
	SkinChoice.select(_mount())
	await await_idle_frame()
	assert_str(String(screen.feedback.theme_type_variation)).is_empty()
	screen.submit_answer(null)                                                                        # ("Type a number first.": the engine's own line, an error)
	await await_idle_frame()
	assert_str(screen.feedback.text).is_not_empty()
	assert_str(String(screen.feedback.theme_type_variation)).is_equal("ProblemWrong")
	assert_str(screen.feedback.get_theme_color(&"font_color").to_html(false)).is_equal("ff6677")        # (`bad`)
	SkinChoice.select(SkinChoice.original())                                                          # (the line is up while the skin goes: it is the engine's wrong colour)
	await await_idle_frame()
	assert_object(screen.feedback.get_theme_color(&"font_color")).is_equal(ThemeBuilder.WRONG)
	SkinChoice.select(SkinChoice.load_skin(_shelves[0].id))
	await await_idle_frame()
	assert_str(screen.feedback.get_theme_color(&"font_color").to_html(false)).is_equal("ff6677")


func test_a_key_lit_when_the_skin_changes_is_lit_in_the_new_look() -> void:
	var screen := _screen()
	await await_idle_frame()
	var skin := _mount()
	screen.calculator.input_key("1")
	assert_bool(screen.calculator.is_flashing()).is_true()
	var plain := (_key(screen.calculator, "1").get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color.to_html()
	SkinChoice.select(skin)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(screen.calculator.is_flashing()).is_true()
	var lit := _key(screen.calculator, "1").get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_str(lit.bg_color.to_html()).is_equal("ffee6680")                                            # (the skin's `pressed`, not the engine's that was put on)
	assert_str(plain).is_not_equal(lit.bg_color.to_html())
	screen.calculator.end_flash()
	assert_str((_key(screen.calculator, "1").get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color.to_html()).is_equal("00000000")


# --- the pictures ------------------------------------------------------------------------------------------------------------

func test_the_frame_pictures_are_the_chains_in_the_layouts_rectangles() -> void:
	var screen := _screen()
	await await_idle_frame()
	var plain_rects := _rects(screen)
	var plain_order := _order(screen)
	assert_object(screen.background.texture.get_size()).is_not_equal(Vector2(32, 18))
	var skin := _mount()                                                                              # (the pack in use draws the frame's pictures: flat 32 x 18 files)
	var made := _screen()
	await await_idle_frame()
	for picture: TextureRect in [made.background, made.calculator.picture, made.answer_box.picture]:
		assert_vector(picture.texture.get_size()).is_equal(Vector2(32, 18))
		assert_that(PicturesShelf.color_of(picture.texture)).is_equal(Color.CYAN)
	assert_object((made.background.texture as PictureRef).resolved()).is_same(Assets.picture_by_key("problem_art/pa_1780").resolved())
	assert_array(_order(made)).is_equal(plain_order)
	assert_array(_rects(made)).is_equal(plain_rects)                                                   # (not one rectangle moved)
	var before := made.background.texture
	SkinChoice.select(skin)                                                                           # (a skin changes no picture: not the one it is, not the original)
	await await_idle_frame()
	assert_object(made.background.texture).is_same(before)
	SkinChoice.select(SkinChoice.original())
	await await_idle_frame()
	assert_object(made.background.texture).is_same(before)


func test_a_screen_made_under_the_skin_is_the_same_as_one_the_skin_is_put_on() -> void:
	var skin := _mount()
	var before := _screen()
	await await_idle_frame()
	SkinChoice.select(skin)
	await await_idle_frame()
	var after := _screen()                                                                            # (made while the skin is in use)
	await await_idle_frame()
	for node: String in ["%Background", "%Calculator/Picture", "%AnswerBox/Picture"]:
		assert_object((after.get_node(node) as TextureRect).texture).is_same((before.get_node(node) as TextureRect).texture)
		assert_object((after.get_node(node) as TextureRect).get_rect()).is_equal((before.get_node(node) as TextureRect).get_rect())
	assert_array(_rects(after)).is_equal(_rects(before))
	assert_str(after.title_label.get_theme_color(&"font_color").to_html()).is_equal(before.title_label.get_theme_color(&"font_color").to_html())


func test_the_senders_picture_is_the_chains() -> void:
	var problem := ProblemFactory.for_trigger_slot(2, 0)                                              # (slot 2: the research ship)
	assert_object(problem).is_not_null()
	var screen := _screen(problem)
	await await_idle_frame()
	assert_bool(screen.sender_icon.visible).is_true()
	var plain := screen.sender_icon.texture
	var plain_color := PicturesShelf.color_of(plain)
	var rect := screen.sender_icon.get_rect()
	var skin := _mount()
	var made := _screen(problem)
	await await_idle_frame()
	assert_object(made.sender_icon.texture).is_same(Assets.picture_by_key("ui_picture/prompt_sender_ship"))
	assert_that(PicturesShelf.color_of(made.sender_icon.texture)).is_not_equal(plain_color)
	assert_object(made.sender_icon.texture).override_failure_message("the reference holds the key: the screen that had it before shows the pack's picture now").is_same(plain)
	assert_object(made.sender_icon.get_rect()).is_equal(rect)                                          # (stretched to the 55 x 20 the original has)
	SkinChoice.select(skin)
	await await_idle_frame()
	assert_object(made.sender_icon.texture).is_same(Assets.picture_by_key("ui_picture/prompt_sender_ship"))


# --- the play ----------------------------------------------------------------------------------------------------------------

## A problem played the same way under whatever skin is in use: a wrong answer, then the right one. What the rules and the clock did.
func _play() -> Array:
	var screen := _screen()
	var steps: Array = []
	var oxygen := GameState.oxygen()
	var problem := screen.session.instance
	screen.advance_ticks(2000)
	steps.append([screen.session.misses, screen.session.finished, GameState.oxygen() - oxygen])
	screen.submit_answer(NumberValue.parse("9999"))
	screen.advance_ticks(2000)
	steps.append([screen.session.misses, screen.session.finished, GameState.oxygen() - oxygen])
	screen.submit_answer(problem.expected)
	screen.advance_ticks(2000)
	steps.append([screen.session.misses, screen.session.finished, screen.session.solved, GameState.oxygen() - oxygen, screen.is_waiting_for_continue()])
	screen.free()
	return steps


func test_a_problem_plays_the_same_under_the_skin() -> void:
	var plain := _play()
	GameState.reset()
	SkinChoice.select(_mount())
	var worn := _play()
	assert_array(worn).is_equal(plain)
	assert_bool((plain[2] as Array)[2]).is_true()                                                      # (it was solved: the play went all the way)
