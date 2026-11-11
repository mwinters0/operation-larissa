class_name TestModSkin
extends GdUnitTestSuite
## Teaches: a skin that is a stranger's code. A mod pack whose manifest says `skin` is an entry of `SkinChoice` like the project's own skins (the same `GameSkin`, chosen, bound and swapped
## the same way); its sandboxed script is handed the sector as plain data and returns a draw list, and the game checks and draws that (`ModDraw`, `ModLayer`), so nothing of the game is
## ever granted to it. The tests cover: the manifest, the shader text, the draw list (every kind of garbage a script can return), a skin that draws, its lifetime (it ends with its mod and the
## skin in use falls back), a skin that faults, and the hostile skin mod (`tests/mods/skin_hostile`): every attempt to reach the game is refused. That a skin of any kind does not change a
## rule is `test_plays_identically.gd` and `test_skins_dont_change_the_game.gd`, which play the mod skins of this suite too (`SkinRoster.mount_mod_skins`).
## These tests need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`, docs/SETUP.md).

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const PRESENTER_SCENE := "res://src/gameplay/original_presenter.tscn"

## The dev pack's sector with decorations of every layer, and the screen that has an animated one.
const DECORATED_SECTOR := 100
const DECORATED_SCREEN := 6

var _shelves: Array[PackShelf] = []


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	ModLoader.pretend_no_sandbox = false
	ModSkinShelf.release(_shelves)
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


## The skin mod fixtures `names`, mounted and running; the first of them.
func _mount(names: Array[String]) -> PackShelf:
	_shelves = ModSkinShelf.mount(names)
	return _shelves[0]


## A sim in the arena with the sub flying, one tick run.
func _sim() -> SimWorld:
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(200, 150, 6)
	sim.tick()
	return sim


## A sim on screen `screen` of the sector of the dev pack that has all four kinds of decorations (`DECORATED_SECTOR`), the sub flying, `ticks` ticks run.
func _decorated_sim(screen: int, ticks: int = 0) -> SimWorld:
	var sim := SimWorld.new(GameState)
	sim.load_sector(DECORATED_SECTOR, screen)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(200, 150, 6)
	for i in ticks:
		sim.tick()
	return sim


## The original presenter in the tree, bound to `sim`, dressed in `skin` (what `SectorWorld` does with the skin in use): it hosts the layers the skin's script draws.
func _presenter(sim: SimWorld, skin: GameSkin) -> OriginalPresenter:
	var presenter := (load(PRESENTER_SCENE) as PackedScene).instantiate() as OriginalPresenter
	presenter.skin = skin
	auto_free(presenter)
	presenter.run_in_skin(func() -> void:
		add_child(presenter)
		presenter.bind(sim))
	return presenter


## The commands of every layer node the script's answers are shown in, in order: [[layer node, commands]].
func _layers(presenter: OriginalPresenter) -> Array:
	var found: Array = []
	for layer in presenter.mod_layers():
		found.append([layer, layer.commands])
	return found


## The commands of the presenter's layers whose first element is `op`.
func _commands(presenter: OriginalPresenter, op: String) -> Array:
	var found: Array = []
	for layer: Array in _layers(presenter):
		for command: Array in layer[1]:
			if command[0] == op:
				found.append(command)
	return found


# --- the manifest ---------------------------------------------------------------------------------------------------------

func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


func test_a_skin_entry_makes_the_mod_a_skin_and_lists_its_shaders() -> void:
	var got := _parse({"entry": "reef.sgd", "requires_api": 2, "skin": {"shaders": ["skin/glow.gdshader", "skin/deep/wave.gdshader"]}})
	var spec: ModSpec = got[0]
	assert_array(got[1]).is_empty()
	assert_bool(spec.is_skin).is_true()
	assert_array(spec.shaders).is_equal(["skin/glow.gdshader", "skin/deep/wave.gdshader"])
	assert_dict(spec.to_dict()).is_equal({"entry": "reef.sgd", "requires_api": 2, "skin": {"shaders": ["skin/glow.gdshader", "skin/deep/wave.gdshader"]}})
	var plain: ModSpec = _parse({"entry": "reef.sgd", "requires_api": 2, "skin": {}})[0]
	assert_bool(plain.is_skin).is_true()
	assert_array(plain.shaders).is_empty()
	assert_bool((_parse({"entry": "orchard.sgd"})[0] as ModSpec).is_skin).is_false()
	assert_int(ModSpec.API_VERSION).is_greater_equal(ModSpec.SKIN_API_VERSION)
	assert_int((_parse({"entry": "orchard.sgd", "requires_api": 1})[0] as ModSpec).requires_api).is_equal(1)          # (a mod of the first API still runs)


func test_a_skin_gets_a_lower_instruction_limit_and_cannot_turn_counting_off() -> void:
	var asked := {"entry": "a.sgd", "requires_api": 2, "skin": {}}
	assert_int((_parse(asked)[0] as ModSpec).limits["execution_timeout"]).is_equal(ModSpec.MAX_DRAWING_EXECUTION_TIMEOUT)
	asked["limits"] = {"execution_timeout": 0}
	assert_int((_parse(asked)[0] as ModSpec).limits["execution_timeout"]).is_equal(1)                # (0 is "no counting": not for a skin)
	asked["limits"] = {"execution_timeout": 150}
	var spec: ModSpec = _parse(asked)[0]
	assert_int(spec.limits["execution_timeout"]).is_equal(ModSpec.MAX_DRAWING_EXECUTION_TIMEOUT)
	assert_dict(spec.to_dict()).is_equal({"entry": "a.sgd", "requires_api": 2, "skin": {}})        # (the ceiling is the default: nothing to write)
	assert_int((_parse({"entry": "a.sgd", "limits": {"execution_timeout": 500}})[0] as ModSpec).limits["execution_timeout"]).is_equal(ModSpec.MAX_EXECUTION_TIMEOUT)


func test_every_mistake_in_a_skin_entry_is_a_sentence() -> void:
	var bad := {
		"a skin of the first API": [{"entry": "a.sgd", "skin": {}}, "requires_api"],
		"not an object": [{"entry": "a.sgd", "requires_api": 2, "skin": true}, "must be an object"],
		"an unknown key": [{"entry": "a.sgd", "requires_api": 2, "skin": {"fonts": []}}, "no \"fonts\""],
		"shaders not a list": [{"entry": "a.sgd", "requires_api": 2, "skin": {"shaders": "skin/a.gdshader"}}, "must be a list"],
		"a shader not a string": [{"entry": "a.sgd", "requires_api": 2, "skin": {"shaders": [3]}}, "must be a file"],
		"a shader outside skin/": [{"entry": "a.sgd", "requires_api": 2, "skin": {"shaders": ["shaders/a.gdshader"]}}, "must be a file"],
		"a shader climbing out": [{"entry": "a.sgd", "requires_api": 2, "skin": {"shaders": ["skin/../a.gdshader"]}}, "must be a file"],
		"a shader of the game": [{"entry": "a.sgd", "requires_api": 2, "skin": {"shaders": ["res://src/gameplay/sub_dissolve.gdshader"]}}, "must be a file"],
		"a shader with another extension": [{"entry": "a.sgd", "requires_api": 2, "skin": {"shaders": ["skin/a.gd"]}}, "must be a file"],
		"a shader twice": [{"entry": "a.sgd", "requires_api": 2, "skin": {"shaders": ["skin/a.gdshader", "skin/a.gdshader"]}}, "twice"],
		"too many shaders": [{"entry": "a.sgd", "requires_api": 2, "skin": {"shaders": range(ModSpec.MAX_SHADERS + 1).map(func(i: int) -> String: return "skin/s%d.gdshader" % i)}}, "at most"],
	}
	for what: String in bad:
		var got := _parse(bad[what][0])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_bool((got[1] as Array[String]).any(func(e: String) -> bool: return e.contains(bad[what][1]))) \
				.override_failure_message("%s: %s" % [what, got[1]]).is_true()


func test_a_skin_mod_is_given_the_skin_facts_and_other_mods_are_not() -> void:
	var skinny := _mount(["skinny"] as Array[String])
	var api: Dictionary = ModApi.new(Mods.loader()).build("x", skinny.pack)
	assert_int(api["api_version"]).is_equal(ModSpec.API_VERSION)
	assert_dict(api["skin"]).is_equal({"columns": 38, "rows": 18, "tile": 16, "playfield": Vector2(608, 288), "max_commands": ModDraw.MAX_COMMANDS,
			"max_layers": ModDraw.MAX_LAYERS, "max_uniforms": ModShader.MAX_UNIFORMS, "max_texts": ModDraw.MAX_TEXTS, "max_text": ModDraw.MAX_TEXT,
			"min_font_size": ModDraw.MIN_FONT_SIZE, "max_font_size": ModDraw.MAX_FONT_SIZE, "shaders": ["skin/glow.gdshader"]})
	for value: Variant in api["skin"].values():
		assert_bool(value is Object).is_false()                                                      # (numbers and names: nothing to reach through)
	var hello := PackShelf.new(&"", skinny.id)
	_shelves.append(hello)
	hello.add_mod_fixture("res://tests/mods/hello")
	hello.mount()
	assert_bool(ModApi.new(Mods.loader()).build("y", hello.pack).has("skin")).is_false()
	assert_bool(ModApi.new(Mods.loader()).property_allowed("x", skinny.pack, "id", false)).is_false()   # (still no grant: nothing a mod holds can be asked anything)
	assert_bool(ModApi.new(Mods.loader()).method_allowed("x", skinny.pack, "has")).is_false()


func test_the_document_names_every_key_of_the_state_every_command_and_every_cap() -> void:
	var doc := FileAccess.get_file_as_string("res://../docs/create/SKIN_API.md")
	doc = doc.substr(doc.find("## Writing a skin mod"))
	assert_str(doc).is_not_empty()
	_mount(["skinny"] as Array[String])
	var state := SkinState.build(SimView.new(_sim()))
	var named: Array[String] = []
	for key: String in state:
		named.append(key)
	for group in ["sub", "dissolve"]:
		for key: String in state[group]:
			named.append(key)
	var sim := _sim()
	sim.tick(InputSnapshot.firing())
	var fired := SkinState.build(SimView.new(sim))
	for group in ["creatures", "pellets"]:
		assert_array(fired[group]).override_failure_message("no %s to read the keys of" % group).is_not_empty()
		for key: String in fired[group][0]:
			named.append(key)
	for screen in 12:                                                              # (a screen with a piece on it)
		sim.load_screen(screen)
		if not sim.pieces.is_empty():
			break
	var pieces: Array = SkinState.build(SimView.new(sim))["pieces"]
	assert_array(pieces).is_not_empty()
	for key: String in pieces[0]:
		named.append(key)
	sim.start_launch()
	sim.tick()
	for key: String in SkinState.build(SimView.new(sim))["sequence"]:
		named.append(key)
	var at_the_station := SimWorld.new(GameState)
	at_the_station.load_sector(DevCreatures.ARENA, 0)
	var launching := SkinState.build(SimView.new(at_the_station))
	for key: String in launching["station"]:
		named.append(key)
	for key: String in launching["station"]["parts"][0]:
		named.append(key)
	var decorated := SkinState.build(SimView.new(_decorated_sim(DECORATED_SCREEN)))
	for layer: String in decorated["decos"]:
		named.append(layer)
		for key: String in decorated["decos"][layer]:
			named.append(key)
	for key: String in decorated["anim_decos"]:
		named.append(key)
	for key in named:
		assert_bool(doc.contains("`%s`" % key)).override_failure_message("SKIN_API.md does not mention the key `%s` of the state" % key).is_true()
	for op in ModDraw.OPS:
		assert_bool(doc.contains("[\"%s\"," % op)).override_failure_message("SKIN_API.md does not show the command \"%s\"" % op).is_true()
	for fact in ["max_commands", "max_layers", "max_uniforms", "max_texts", "max_text", "min_font_size", "max_font_size", "columns", "rows", "tile", "playfield", "shaders"]:
		assert_bool(doc.contains("`%s`" % fact)).override_failure_message("SKIN_API.md does not mention api[\"skin\"][\"%s\"]" % fact).is_true()
	assert_bool(doc.contains("%d) commands" % ModDraw.MAX_COMMANDS)).is_true()
	assert_bool(doc.contains("`max_layers` (%d)" % ModDraw.MAX_LAYERS)).is_true()
	assert_bool(doc.contains("`max_uniforms` (%d)" % ModShader.MAX_UNIFORMS)).is_true()
	assert_bool(doc.contains("`max_texts` (%d)" % ModDraw.MAX_TEXTS) and doc.contains("`max_text` (%d)" % ModDraw.MAX_TEXT)).is_true()
	assert_bool(doc.contains("%d to %d" % [ModDraw.MIN_FONT_SIZE, ModDraw.MAX_FONT_SIZE])).is_true()
	assert_bool(doc.contains("%d bytes" % ModShader.MAX_BYTES)).is_true()
	assert_bool(doc.contains("`SkinState.MAX_EVENTS`")).is_true()
	for kind in GameSkin.KEY_KINDS:                                                                        # (pictures by key: every kind, the longest key, the API version a mod that names one says)
		assert_bool(doc.contains("`%s`" % kind)).override_failure_message("SKIN_API.md does not name the kind of picture key `%s`" % kind).is_true()
	assert_bool(doc.contains("`ModSpec.MAX_KEY` (%d)" % ModSpec.MAX_KEY)).is_true()
	assert_bool(doc.contains("\"requires_api\": %d" % ModSpec.API_VERSION)).is_true()


# --- the shader text -----------------------------------------------------------------------------------------------------

const GOOD_SHADER := "shader_type canvas_item;\nuniform float strength = 0.5;\nvoid fragment() {\n\tCOLOR = texture(TEXTURE, UV) * strength;\n}\n"


func test_a_shader_is_text_the_game_checks_before_it_compiles_it() -> void:
	assert_str(ModShader.problem(GOOD_SHADER.to_utf8_buffer())).is_empty()
	assert_str(ModShader.problem("// for while do\n/* for (;;) */ shader_type canvas_item;\nvoid vertex() { VERTEX.x += 1.0; }".to_utf8_buffer())).override_failure_message("a loop word in a comment is no loop").is_empty()
	assert_str(ModShader.problem("shader_type canvas_item;\nuniform float for_x;\nvoid fragment() { COLOR = vec4(for_x); }".to_utf8_buffer())).override_failure_message("a name that holds a loop word is no loop").is_empty()
	var bad := {
		"a spatial shader": ["shader_type spatial;\nvoid fragment() { ALBEDO = vec3(1.0); }", "shader_type canvas_item"],
		"a particles shader": ["shader_type particles;\nvoid start() { }", "shader_type canvas_item"],
		"no type": ["void fragment() { COLOR = vec4(1.0); }", "shader_type canvas_item"],
		"an include": ["shader_type canvas_item;\n#include \"res://src/gameplay/x.gdshaderinc\"\nvoid fragment() { }", "preprocessor"],
		"a define": ["shader_type canvas_item;\n#define W wh##ile\nvoid fragment() { }", "preprocessor"],
		"a for loop": ["shader_type canvas_item;\nvoid fragment() { for (int i = 0; i < 4; i++) { COLOR.r += 0.1; } }", "no loops"],
		"a while loop": ["shader_type canvas_item;\nvoid fragment() { while (true) { } }", "no loops"],
		"a do loop": ["shader_type canvas_item;\nvoid fragment() { do { } while (true); }", "no loops"],
		"no function": ["shader_type canvas_item;\nuniform float x;", "no fragment"],
		"unbalanced": ["shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0;", "brackets"],
		"closing too many": ["shader_type canvas_item;\nvoid fragment() { } }", "brackets"],
		"a control character": ["shader_type canvas_item;\nvoid fragment() { }\u0001", "control character"],
	}
	for what: String in bad:
		assert_str(ModShader.problem(bad[what][0].to_utf8_buffer())).override_failure_message(what).contains(bad[what][1])
	var not_utf8 := GOOD_SHADER.to_utf8_buffer()
	not_utf8.append(0xff)
	assert_str(ModShader.problem(not_utf8)).contains("UTF-8")
	var huge := (GOOD_SHADER + " ".repeat(ModShader.MAX_BYTES)).to_utf8_buffer()
	assert_str(ModShader.problem(huge)).contains("bytes")


func test_a_skin_with_a_bad_shader_is_refused_before_it_runs_and_the_check_says_why() -> void:
	var big := " ".repeat(1 << 20)                                                                     # a megabyte of shader: never read whole
	var cases := {
		"a loop": ["shader_type canvas_item;\nvoid fragment() { while (true) { } }", "no loops"],
		"an include": ["shader_type canvas_item;\n#include \"res://x\"\nvoid fragment() { }", "preprocessor"],
		"huge source": [GOOD_SHADER + big, "bytes"],
	}
	for what: String in cases:
		var shelf := PackShelf.new(&"", _shelves.back().id if not _shelves.is_empty() else &"")
		_shelves.append(shelf)
		shelf.add_mod_fixture("res://tests/mods/skinny")
		ModSkinShelf.add_files(shelf)
		shelf.write_text(ModSkinShelf.GLOW, cases[what][0])
		shelf.mount()
		Mods.sync()
		assert_array(Mods.loaded_ids()).override_failure_message("%s: the mod runs" % what).not_contains([String(shelf.id)])
		assert_str(ModHost.failure(String(shelf.id))).override_failure_message(what).contains(cases[what][1])
		assert_array(SkinChoice.available()).not_contains([shelf.id])
		var options := PackCheck.Options.new()
		options.reach = false
		var report := PackCheck.run(Pack.open(shelf.root), options)
		assert_bool(report.errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains(cases[what][1]))).override_failure_message("%s: %s" % [what, report.text()]).is_true()


func test_a_skin_that_takes_the_id_of_a_skin_of_the_game_is_refused() -> void:
	var shelf := PackShelf.new(&"creatures")
	_shelves.append(shelf)
	shelf.add_mod_fixture("res://tests/mods/skinny")
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure("creatures")).contains("id of a skin that comes with the game")
	assert_object(SkinChoice.load_skin(&"creatures").get("pack_id")).is_null()                       # (the game's `creatures`, not a mod's)


func test_a_skin_without_skin_frame_is_refused() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture("res://tests/mods/skinny")
	ModSkinShelf.add_files(shelf)
	shelf.write_text("skinny.sgd", "var api = {}\nfunc mod_init(a):\n\tapi = a\n")
	var options := PackCheck.Options.new()
	options.reach = false
	assert_bool(PackCheck.run(Pack.open(shelf.root), options).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("skin_frame"))).is_true()
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure(String(shelf.id))).contains("skin_frame")
	assert_array(Mods.loaded_ids()).not_contains([String(shelf.id)])


func test_a_skin_with_a_picture_that_is_no_png_is_refused() -> void:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture("res://tests/mods/skinny")
	ModSkinShelf.add_files(shelf)
	shelf.write_text("skin/broken.png", "not a picture")
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure(String(shelf.id))).contains("skin/broken.png")


# --- the draw list ---------------------------------------------------------------------------------------------------------

## The mod pack `shelf` as the checker sees it, with the skin the host made of it.
func _checker(shelf: PackShelf) -> Array:
	return [Packs.pack(shelf.id), SkinChoice.load_skin(shelf.id)]


func test_a_draw_list_is_checked_command_by_command() -> void:
	var skinny := _mount(["skinny"] as Array[String])
	var pack := skinny.pack
	var skin := SkinChoice.load_skin(skinny.id) as ModSkin
	var drawn := ModDraw.validate([
		["rect", Rect2(1, 2, 3, 4), Color.RED],
		["line", Vector2(0, 0), Vector2(5, 5), Color.RED, 2.0],
		["picture", "skin/dot.png", Vector2(10, 10)],
		["picture", "skin/dot.png", Rect2(0, 0, 8, 8), true, Color(1, 1, 1, 0.5)],
		["picture", "skin/dot.png", Vector2(10, 10), Color.RED],
		["region", "skin/sub.png", Rect2(0, 0, 16, 16), Rect2(0, 0, 8, 8)],
		["layer", "skin/glow.gdshader", {"strength": 0.5, "tint": Color.RED}],
		["rect", Rect2(0, 0, 1, 1), Color.GREEN],
	], pack, skin.assets)
	assert_int(drawn.dropped).is_equal(0)
	assert_int(drawn.layers.size()).is_equal(2)
	assert_int(drawn.layers[0].commands.size()).is_equal(6)
	assert_array(drawn.layers[0].commands[2]).is_equal(["picture", pack.texture("skin/dot.png"), Vector2(10, 10), false, Color.WHITE])
	assert_array(drawn.layers[0].commands[3]).is_equal(["picture", pack.texture("skin/dot.png"), Rect2(0, 0, 8, 8), true, Color(1, 1, 1, 0.5)])
	assert_array(drawn.layers[0].commands[4]).is_equal(["picture", pack.texture("skin/dot.png"), Vector2(10, 10), false, Color.RED])
	assert_str(drawn.layers[1].shader).is_equal("skin/glow.gdshader")
	assert_dict(drawn.layers[1].uniforms).is_equal({"strength": 0.5, "tint": Color.RED})
	assert_int(drawn.layers[1].commands.size()).is_equal(1)
	assert_object(ModDraw.validate("a string", pack, skin.assets)).is_null()                             # (not a list: no frame at all, the last one stays)
	assert_object(ModDraw.validate(null, pack, skin.assets)).is_null()
	assert_bool(ModDraw.is_empty(ModDraw.validate([], pack, skin.assets))).is_true()


func test_a_draw_lists_uniforms_are_judged_as_a_manifests_are() -> void:
	var skinny := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(skinny.id) as ModSkin
	var good := {"strength": 0.5, "tint": "#ff8800"}                                                   # (a colour string, as a manifest says it)
	var layer := func(uniforms: Dictionary) -> ModDraw.Drawn:
		return ModDraw.validate([["layer", "skin/glow.gdshader", uniforms], ["rect", Rect2(0, 0, 1, 1), Color.RED]], skinny.pack, skin.assets)
	var drawn: ModDraw.Drawn = layer.call(good)
	assert_int(drawn.dropped).is_equal(0)
	assert_that(drawn.layers[1].uniforms["tint"]).is_equal(Color("#ff8800"))
	assert_dict(layer.call({"strength": 1}).layers[1].uniforms).is_equal({"strength": 1.0})
	var refused := {
		"phase, which the game sets": {"phase": 1.0},
		"a uniform the shader does not declare": {"glint": 1.0},
		"a value of another type": {"strength": Vector2(1, 2)},
		"a number a manifest would refuse": {"strength": ModShader.MAX_VALUE + 1.0},
		"a name that is no name": {"two words": 1.0},
		"a vector part out of bounds": {"tint": Color(ModShader.MAX_VALUE * 2.0, 0, 0, 1)},
	}
	for what: String in refused:
		var got: ModDraw.Drawn = layer.call(refused[what])
		assert_int(got.dropped).override_failure_message("%s was drawn" % what).is_greater(0)
		var values := {}
		assert_array(ModShader.check_uniforms(refused[what], skin.assets.declared["skin/glow.gdshader"], values)).override_failure_message("%s was not named" % what).is_not_empty()
	var many := {}
	for i in ModShader.MAX_UNIFORMS + 1:
		many["u%d" % i] = 1.0
	assert_array(ModShader.check_uniforms(many, null, {})).is_not_empty()


func test_the_game_sets_phase_on_every_layer_of_a_stack_and_a_mod_never_does() -> void:
	var skinny := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(skinny.id) as ModSkin
	var stack := ModLayerStack.new()
	auto_free(stack)
	stack.set_phase(3.5)                                                                               # (before the layers: they start with it)
	var drawn := ModDraw.validate([["layer", "skin/glow.gdshader", {"strength": 0.2}], ["rect", Rect2(0, 0, 1, 1), Color.RED]], skinny.pack, skin.assets)
	stack.show_drawn(drawn, skin.assets)
	var shaded := stack.layers()[1]
	assert_float((shaded.material as ShaderMaterial).get_shader_parameter("phase")).is_equal(3.5)
	stack.set_phase(4.25)
	assert_float((shaded.material as ShaderMaterial).get_shader_parameter("phase")).is_equal(4.25)
	assert_object(stack.layers()[0].material).is_null()


func test_garbage_in_a_draw_list_is_dropped_and_the_good_commands_around_it_are_drawn() -> void:
	_mount(["skin_hostile"] as Array[String])
	var shelf := _shelves[0]
	var skin := SkinChoice.load_skin(shelf.id) as ModSkin
	var mod := ModHost.mod(String(shelf.id))
	var faults := int(mod.get("monitor_exceptions"))
	var garbage: Array = mod.call("bad_commands")
	var garbage_layers: Array = mod.call("bad_layer_commands")
	assert_int(int(mod.get("monitor_exceptions"))).override_failure_message("the hostile skin raised making its lists").is_equal(faults)
	assert_int(garbage.size()).is_greater(20)
	var drawn := ModDraw.validate(garbage, shelf.pack, skin.assets)           # nothing in it is a command the game draws
	assert_int(drawn.layers.size()).is_equal(1)
	assert_array(drawn.layers[0].commands).is_empty()
	assert_int(drawn.dropped).is_equal(garbage.size())
	drawn = ModDraw.validate(garbage_layers, shelf.pack, skin.assets)         # every layer in it but the last is refused, and what follows a refused layer goes with it
	assert_int(drawn.layers.size()).override_failure_message("a layer that should have been refused is drawn").is_equal(2)
	assert_array(drawn.layers[0].commands.map(func(c: Array) -> String: return c[0])).is_equal(["rect"])
	assert_array(drawn.layers[1].commands.map(func(c: Array) -> String: return c[0])).is_equal(["picture"])
	assert_int(drawn.dropped).is_equal(garbage_layers.size() - 3)


func test_a_draw_list_is_cut_at_the_caps() -> void:
	_mount(["skin_hostile"] as Array[String])
	var shelf := _shelves[0]
	var skin := SkinChoice.load_skin(shelf.id) as ModSkin
	var mod := ModHost.mod(String(shelf.id))
	var long: Array = mod.call("bad_huge_list", ModDraw.MAX_COMMANDS + 500)
	var drawn := ModDraw.validate(long, shelf.pack, skin.assets)
	assert_int(drawn.layers[0].commands.size()).is_equal(ModDraw.MAX_COMMANDS)
	assert_int(drawn.dropped).is_equal(500)
	var layered := ModDraw.validate(mod.call("bad_layers"), shelf.pack, skin.assets)
	assert_int(layered.layers.size()).is_equal(ModDraw.MAX_LAYERS)
	var uniforms := ModDraw.validate(mod.call("bad_uniforms"), shelf.pack, skin.assets)
	assert_bool(ModDraw.is_empty(uniforms)).override_failure_message("a layer with too many uniforms was drawn").is_true()
	var cyclic := ModDraw.validate(mod.call("bad_cycle"), shelf.pack, skin.assets)                     # (an Array that holds itself: its first element is no command)
	assert_int(cyclic.layers[0].commands.size()).is_equal(1)
	assert_object(ModDraw.validate(mod.call("bad_not_a_list"), shelf.pack, skin.assets)).is_null()
	assert_object(ModDraw.validate(mod.call("bad_a_string"), shelf.pack, skin.assets)).is_null()


func test_a_picture_of_another_pack_is_never_drawn() -> void:
	var below := _mount(["skinny"] as Array[String])
	var above := PackShelf.new(&"", below.id)
	_shelves.append(above)
	above.add_mod_fixture("res://tests/mods/skin_hostile")
	ModSkinShelf.add_files(above)
	above.mount()
	Mods.sync()
	var skin := SkinChoice.load_skin(above.id) as ModSkin
	below.add_picture("skin/only_below.png", Color.RED)
	above.pack.forget()
	below.pack.forget()
	var drawn := ModDraw.validate([["picture", "skin/only_below.png", Vector2(0, 0)], ["picture", "skin/dot.png", Vector2(0, 0)]], above.pack, skin.assets)
	assert_int(drawn.layers[0].commands.size()).override_failure_message("the pack above drew a picture of the pack below").is_equal(1)
	assert_int(drawn.dropped).is_equal(1)


func test_a_draw_list_names_a_picture_of_the_game_by_its_skin_key() -> void:
	var skinny := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(skinny.id) as ModSkin
	var sky := Assets.background(0, 3)
	var sub := Assets.picture_by_key("frame/sub_00")
	var tiles := Assets.picture_by_key("tile/zone0_tiles")
	for picture in [sky, sub, tiles]:
		assert_object(picture).is_not_null()
	var drawn := ModDraw.validate([
		["picture", "background/bg_s00_03", Vector2(1, 2)],
		["picture", "frame/sub_00", Rect2(0, 0, 8, 8), true, Color(1, 1, 1, 0.5)],
		["region", "tile/zone0_tiles", Rect2(0, 0, 16, 16), Rect2(16, 0, 16, 16)],
		["picture", "skin/dot.png", Vector2(0, 0)],
	], skinny.pack, skin.assets)
	assert_int(drawn.dropped).is_equal(0)
	assert_array(drawn.layers[0].commands[0]).is_equal(["picture", sky, Vector2(1, 2), false, Color.WHITE])
	assert_array(drawn.layers[0].commands[1]).is_equal(["picture", sub, Rect2(0, 0, 8, 8), true, Color(1, 1, 1, 0.5)])
	assert_array(drawn.layers[0].commands[2]).is_equal(["region", tiles, Rect2(0, 0, 16, 16), Rect2(16, 0, 16, 16), false, Color.WHITE])
	assert_object(sky).override_failure_message("the key's picture is the one the original look asks for").is_same(Assets.background(0, 3))
	assert_array(drawn.layers[0].commands[3]).is_equal(["picture", skinny.pack.texture("skin/dot.png"), Vector2(0, 0), false, Color.WHITE])


func test_a_key_the_game_cannot_resolve_or_that_has_a_wrong_shape_draws_nothing() -> void:
	var skinny := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(skinny.id) as ModSkin
	var bad: Array = [
		"frame/no_such_picture_99", "background/bg_s99_99", "deco/", "/frame/sub_00", "frame/sub_00/", "frame//sub_00", "frame/Sub_00", "frame/sub-00", "frame/sub_00.png", "frame/0sub", "frame/sub 00",
		"sound/whoosh", "pictures/ui_picture/x", "problems/x.png", "skin/missing.png", "../frame/sub_00", "frame", "", "x".repeat(ModSpec.MAX_KEY + 1), "frame/" + "x".repeat(ModSpec.MAX_KEY),
	]
	var list: Array = []
	for key: String in bad:
		list.append(["picture", key, Vector2(0, 0)])
		list.append(["region", key, Rect2(0, 0, 4, 4), Rect2(0, 0, 4, 4)])
	list.append(["picture", 7, Vector2(0, 0)])
	list.append(["picture", ["frame/sub_00"], Vector2(0, 0)])
	list.append(["picture", &"frame/sub_00x", Vector2(0, 0)])
	list.append(["rect", Rect2(0, 0, 1, 1), Color.RED])
	var drawn := ModDraw.validate(list, skinny.pack, skin.assets)
	assert_int(drawn.layers[0].commands.size()).override_failure_message("only the rectangle is drawn").is_equal(1)
	assert_int(drawn.dropped).is_equal(list.size() - 1)
	assert_bool(ModSpec.is_drawable_key("frame/sub_00") and ModSpec.is_drawable_key("deco/coral_fan_cyan") and ModSpec.is_drawable_key("ui_picture/ui_1189")).is_true()
	assert_bool(ModSpec.is_drawable_key("tile/zone0_tiles") and ModSpec.is_drawable_key("problem_art/log_scan_0") and ModSpec.is_drawable_key("background/bg_s00_00")).is_true()
	assert_array(GameSkin.KEY_KINDS).is_equal(["ui_picture", "background", "problem_art", "frame", "deco", "tile"])
	for kind: String in ModSpec.REPLACEABLE_KINDS:                                                           # (what a skin may replace is among what a list may name)
		assert_bool(GameSkin.KEY_KINDS.has(kind)).is_true()


func test_a_picture_by_key_asks_the_chain_once_for_a_whole_list() -> void:
	var skinny := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(skinny.id) as ModSkin
	var list: Array = []
	for i in 400:
		list.append(["picture", "deco/coral_fan_cyan" if i % 2 == 0 else "frame/sub_00", Vector2(i, 0)])
	var drawn := ModDraw.validate(list, skinny.pack, skin.assets)
	assert_int(drawn.layers[0].commands.size()).is_equal(400)
	assert_object(drawn.layers[0].commands[0][1]).is_same(drawn.layers[0].commands[2][1])
	assert_object(drawn.layers[0].commands[0][1]).is_same(Assets.picture_by_key("deco/coral_fan_cyan"))


func test_a_picture_key_is_found_in_the_chain_nearest_the_top_and_forgotten_with_the_chain() -> void:
	var below := _mount(["skinny"] as Array[String])
	assert_object(Assets.picture_by_key("frame/only_in_the_top_pack")).is_null()
	var above := PackShelf.new(&"", below.id)
	_shelves.append(above)
	above.add_picture("assets/sprites/fx/only_in_the_top_pack.png", Color.GREEN, Vector2i(6, 6))
	above.mount()
	var found := Assets.picture_by_key("frame/only_in_the_top_pack")
	assert_object(found).override_failure_message("a pack laid over the chain has its pictures by key").is_not_null()
	assert_that(found.get_size()).is_equal(Vector2(6, 6))
	above.remove()
	_shelves.erase(above)
	assert_object(Assets.picture_by_key("frame/only_in_the_top_pack")).override_failure_message("a pack taken away takes its pictures").is_null()


# --- a skin that draws ---------------------------------------------------------------------------------------------------

func test_a_skin_mod_is_chosen_like_any_skin_and_the_world_wears_it() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var shipped := SkinChoice.available().filter(func(id: StringName) -> bool: return id != shelf.id)
	assert_array(SkinChoice.available()).is_equal(shipped + [shelf.id])
	var skin := SkinChoice.load_skin(shelf.id)
	assert_object(skin).is_instanceof(ModSkin)
	assert_object(skin).is_same(ModHost.skin(shelf.id))
	assert_str(String(skin.id)).is_equal(String(shelf.id))
	assert_str(skin.display_name).is_equal(shelf.pack.title)
	assert_array(skin.refused_resources()).is_empty()
	assert_object(skin.next_skin()).is_same(SkinChoice.original())
	assert_str(String(SkinChoice.after(shipped.back()))).is_equal(String(shelf.id))                   # (F3 then S reaches it)
	assert_str(String(SkinChoice.after(shelf.id))).is_equal("original")
	SkinChoice.select_id(shelf.id)                                                                    # (what `--skin=<id>` and F3 S do)
	assert_object(SkinChoice.current()).is_same(skin)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_bool(world.original.hosts_mod_layers()).is_true()
	assert_str(String(PresenterChoice.kind_of(world.presenter))).is_equal(String(PresenterChoice.ORIGINAL))
	SkinChoice.select(SkinChoice.original())                                                          # (and the other way)
	assert_bool(world.original.hosts_mod_layers()).is_false()
	SkinChoice.select_id(shelf.id)
	assert_bool(world.original.hosts_mod_layers()).is_true()


func test_a_mod_that_is_not_there_has_no_skin() -> void:
	_mount(["skinny"] as Array[String])
	assert_object(ModHost.skin(&"no_such_skin")).is_null()
	assert_array(SkinChoice.available()).not_contains([&"no_such_skin"])


func test_the_skin_draws_the_sector_from_the_state_it_is_given() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(shelf.id)
	var sim := _sim()
	var presenter := _presenter(sim, skin)
	presenter.show_between_ticks(1.0)
	var state := SkinState.build(presenter.view)
	var subs := _commands(presenter, "picture").filter(func(c: Array) -> bool: return c[1] == shelf.pack.texture("skin/sub.png"))
	assert_int(subs.size()).is_equal(1)
	var centre: Vector2 = state["sub"]["current"]
	assert_that((subs[0][2] as Rect2).position).is_equal(centre - Vector2(48, 27))
	var walls := _commands(presenter, "rect").filter(func(c: Array) -> bool: return c[2] == Color(0.35, 0.30, 0.25))
	var solid := 0
	for row in TileGrid.ROWS:
		for column in TileGrid.COLUMNS:
			solid += 1 if presenter.view.is_solid(column, row) else 0
	var covered := 0
	for wall in walls:
		covered += int((wall[1] as Rect2).get_area() / (TileGrid.TILE_SIZE * TileGrid.TILE_SIZE))
	assert_int(solid).is_greater(0)
	assert_int(covered).override_failure_message("the walls the skin drew are the tiles the rules treat as solid").is_equal(solid)
	var shown := presenter.view.creatures().filter(func(c: SimView.CreatureState) -> bool: return c.shown)
	assert_int(_commands(presenter, "picture").filter(func(c: Array) -> bool: return c[1] == shelf.pack.texture("skin/creature.png")).size()).is_equal(shown.size())
	assert_int(shown.size()).is_greater(0)


# --- the screen in the state --------------------------------------------------------------------------------------------

func test_the_state_names_the_background_the_decorations_and_the_station_of_the_screen() -> void:
	_mount(["skinny"] as Array[String])
	var sim := _decorated_sim(DECORATED_SCREEN, 5)
	var state := SkinState.build(SimView.new(sim))
	var screen := sim.sector.screens[DECORATED_SCREEN]
	var frames := Catalog.pack_decos_frames(sim.sector.zone)
	var layers := {"back_decos": screen.bg_decos, "mid_decos": screen.mid_decos, "front_decos": screen.fg_decos}
	assert_array(state["decos"].keys()).is_equal(layers.keys())                                           # (the layers in the order they are drawn)
	for layer: String in layers:
		var columns: Dictionary = state["decos"][layer]
		assert_array(layers[layer]).override_failure_message("the screen has no decoration of the %s layer to tell" % layer).is_not_empty()
		for column: String in ["slot", "key", "position", "size", "mirrored"]:
			assert_int((columns[column] as Array).size()).is_equal(layers[layer].size())
		for i in layers[layer].size():
			var placement: DecoPlacement = layers[layer][i]                                              # (each in the order of the screen's list)
			var picture := frames.get_frame_texture(&"all", placement.slot)
			assert_int(columns["slot"][i]).is_equal(placement.slot)
			assert_that(columns["position"][i]).is_equal(Vector2(placement.pos) - SubModel.PLAYFIELD_ORIGIN)
			assert_bool(columns["mirrored"][i]).is_equal(placement.flag)
			assert_str(columns["key"][i]).is_equal(GameSkin.key_of(Packs.source_of(picture)))
			assert_str(columns["key"][i]).starts_with("deco/")
			assert_that(columns["size"][i]).is_equal(Vector2(picture.get_size()))
	var records := screen.anim_decos
	assert_array(records).is_not_empty()
	var swaying: Dictionary = state["anim_decos"]
	for column: String in ["position", "size", "key", "frame", "cursor"]:
		assert_int((swaying[column] as Array).size()).is_equal(records.size())
	for i in records.size():
		var record: AnimDecoData = records[i]
		assert_int(swaying["cursor"][i]).is_equal((record.start_cursor + 5) % record.frames.size())     # (five ticks run on this screen)
		assert_int(swaying["frame"][i]).is_equal(record.frames[swaying["cursor"][i]])
		assert_that(swaying["position"][i]).is_equal(Vector2(record.pos) - SubModel.PLAYFIELD_ORIGIN)
		assert_str(swaying["key"][i]).starts_with("deco/")
	assert_str(state["background"]).is_equal("")                                                          # (the dev pack has no picture for sector 100)
	assert_object(state["station"]).is_null()                                                             # (and no station on screen 6)
	var arena := SimWorld.new(GameState)
	arena.load_sector(0, 3)                                                                                # (sector 0 of the dev pack has its pictures)
	assert_str(SkinState.build(SimView.new(arena))["background"]).is_equal("background/bg_s00_03")


func test_the_station_is_told_part_by_part_as_the_trip_has_it() -> void:
	_mount(["skinny"] as Array[String])
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(200, 150, 6)
	var station: Dictionary = SkinState.build(SimView.new(sim))["station"]
	assert_str(station["side"]).is_equal("left")
	var names := (station["parts"] as Array).map(func(part: Dictionary) -> String: return part["name"])
	assert_array(names).is_equal(["balloon", "body_a", "door"])
	var parts := {}
	for part: Dictionary in station["parts"]:
		parts[part["name"]] = part
		assert_str(part["key"]).starts_with("frame/station_")
		assert_that(part["size"]).is_equal(Vector2(Catalog.pack_station_frames().get_frame_texture(&"all", part["picture"]).get_size()))
	assert_bool(parts["balloon"]["shown"]).is_false()
	assert_bool(parts["door"]["shown"]).is_true()
	assert_int(parts["door"]["picture"]).is_equal(StationLayout.DOOR_CLOSED)
	for part: Dictionary in StationLayout.parts(true):                                                    # (where they go is the layout's)
		assert_that(parts[part["name"]]["position"]).is_equal(part["position"])
		assert_bool(parts[part["name"]]["mirrored"]).is_equal(part["mirrored"])
	sim.load_screen(5)
	assert_object(SkinState.build(SimView.new(sim))["station"]).is_null()
	sim.load_screen(SimWorld.DOCK_SCREEN)
	station = SkinState.build(SimView.new(sim))["station"]
	assert_str(station["side"]).is_equal("right")
	assert_array((station["parts"] as Array).map(func(part: Dictionary) -> String: return part["name"])).is_equal(["balloon", "body_a", "body_b", "body_c", "door"])
	# the door follows the trip: it opens, and the picture is the one `sequence` says
	sim.start_dock()
	var doors: Array[int] = []
	while not sim.sequence.is_done():
		sim.tick()
		var told := SkinState.build(SimView.new(sim))
		var door: Dictionary = told["station"]["parts"][4]
		assert_int(door["picture"]).is_equal(told["sequence"]["door"])
		assert_bool(door["shown"]).is_equal(told["sequence"]["door"] >= 0)
		doors.append(door["picture"])
	assert_array(doors).contains([-1])
	assert_int(doors.back()).is_equal(StationLayout.DOOR_CLOSED)
	# the balloon rises where the trip has it
	sim.start_balloon()
	for i in 6:
		sim.tick()
	var balloon: Dictionary = SkinState.build(SimView.new(sim))["station"]["parts"][0]
	var trip: Dictionary = SkinState.build(SimView.new(sim))["sequence"]
	assert_bool(balloon["shown"]).is_true()
	assert_that(balloon["position"]).is_equal(trip["balloon_current"])
	assert_that(balloon["previous"]).is_equal(trip["balloon_previous"])
	assert_float(balloon["position"].y).is_less(balloon["previous"].y)


## The state tells an animated decoration the entry the original look shows: with the real clock's order (the rules tick first, then the nodes of the screen step), after any number of ticks, on a screen
## laid out between ticks and on one the sub flew into in the middle of a tick, and after the lock opens (the screen is announced again).
func test_the_animated_decorations_are_at_the_entry_the_original_look_shows() -> void:
	var sim := SimWorld.new(GameState)
	var clock := func(_count: int) -> void: sim.tick(InputSnapshot.steering(1 if sim.screen_index < DECORATED_SCREEN else 0))
	GameClock.tick.connect(clock)                                       # (as `SectorWorld` does: the rules first, the decorations after)
	sim.load_sector(DECORATED_SECTOR, DECORATED_SCREEN - 1)
	sim.start_flight(560, 150, 6)
	var original := auto_free((load("res://src/gameplay/original_presenter.tscn") as PackedScene).instantiate()) as OriginalPresenter
	original.run_in_skin(func() -> void:
		add_child(original)
		original.bind(sim))
	var changed := -1
	var compared := 0
	for i in 60:
		GameClock.tick.emit(i)
		if sim.screen_index == DECORATED_SCREEN and changed < 0:
			changed = i
		if changed >= 0 and sim.screen_index == DECORATED_SCREEN:
			_assert_the_decorations_step_as_the_original_look_does(sim, original, "tick %d, %d after the sub came in" % [i, i - changed])
			compared += 1
	GameClock.tick.disconnect(clock)
	assert_int(changed).override_failure_message("the sub did not fly into screen %d" % DECORATED_SCREEN).is_greater_equal(0)
	assert_int(compared).is_greater_equal(12)
	sim.load_screen(DECORATED_SCREEN)                                   # (between ticks: the next tick is the screen's first)
	GameClock.tick.connect(clock)
	for i in 14:
		_assert_the_decorations_step_as_the_original_look_does(sim, original, "a load between ticks, %d ticks on" % i)
		GameClock.tick.emit(i)
	sim.reload_creatures()
	_assert_the_decorations_step_as_the_original_look_does(sim, original, "the creatures reloaded")
	GameClock.tick.emit(0)
	_assert_the_decorations_step_as_the_original_look_does(sim, original, "a tick after the creatures reloaded")
	GameClock.tick.disconnect(clock)
	original.unbind()


func _assert_the_decorations_step_as_the_original_look_does(sim: SimWorld, original: OriginalPresenter, when: String) -> void:
	var view := SimView.new(sim)
	var told: Array = SkinState.build(view)["anim_decos"]["frame"]
	view.close()
	var shown: Array = original.anim_decos.get_children().map(func(deco: AnimDeco) -> int: return deco.frame)
	assert_array(shown).is_not_empty()
	assert_array(told).override_failure_message("%s: the state says the entries %s, the original look shows %s" % [when, told, shown]).is_equal(shown)


func test_the_state_of_a_screen_is_the_same_for_a_skin_bound_late() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(shelf.id)
	var sim := SimWorld.new(GameState)
	var early := _presenter(sim, skin)
	sim.load_sector(DECORATED_SECTOR, DECORATED_SCREEN)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(200, 150, 6)
	for i in 7:
		sim.tick()
	var late := _presenter(sim, skin)
	for presenter: OriginalPresenter in [early, late]:
		presenter.show_between_ticks(0.5)
	assert_array(late.mod_drawn()).is_not_empty()
	assert_array(late.mod_drawn()).is_equal(early.mod_drawn())
	assert_array(_game_pictures(late, shelf)).is_not_empty()                                              # (the decorations were drawn, by key)


## The commands of the presenter's layers that draw a picture of the game (named by key), not one of the mod's own pack: the pictures of the mod are the pack's files, everything else is what the game resolved.
func _game_pictures(presenter: OriginalPresenter, shelf: PackShelf) -> Array:
	var own: Array = ModSkinShelf.PICTURES.keys().map(func(file: String) -> Texture2D: return shelf.pack.texture(file))
	return _commands(presenter, "picture").filter(func(c: Array) -> bool: return not own.has(c[1]))


## What `OriginalPresenter` shows of the screen's still decorations, in the order a skin mod draws them (back, middle, front): [texture, position, mirrored] of each. (The animated ones step with the game clock, which a test of the state alone does not run: they are compared below.)
func _originals_decorations(original: OriginalPresenter) -> Array:
	var shown: Array = []
	for layer: Node2D in [original.back_decos, original.mid_decos, original.front_decos]:
		for deco: AnimatedSprite2D in layer.get_children():
			shown.append([deco.sprite_frames.get_frame_texture(&"all", deco.frame), deco.position, deco.flip_h])
	return shown


func _the_original_look(sim: SimWorld, skin: GameSkin) -> OriginalPresenter:
	var original := auto_free((load("res://src/gameplay/original_presenter.tscn") as PackedScene).instantiate()) as OriginalPresenter
	original.skin = skin
	original.run_in_skin(func() -> void:
		add_child(original)
		original.bind(sim))
	return original


func test_the_skin_draws_the_screen_by_the_keys_the_state_tells_and_shows_what_the_original_look_shows() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(shelf.id)
	var sim := _decorated_sim(DECORATED_SCREEN, 3)
	var presenter := _presenter(sim, skin)
	presenter.show_between_ticks(1.0)
	var original := _the_original_look(sim, skin)
	var state := SkinState.build(presenter.view)
	var drawn := _game_pictures(presenter, shelf)
	var expected := _originals_decorations(original)
	assert_array(expected).override_failure_message("a screen with decorations to compare").is_not_empty()
	var swaying: Dictionary = state["anim_decos"]                                                           # (the swaying ones are drawn last, the picture of the entry they are at)
	assert_int(drawn.size() - (swaying["key"] as Array).size()).override_failure_message("a picture for each decoration the original look shows").is_equal(expected.size())
	for i in expected.size():
		assert_object(drawn[i][1]).override_failure_message("decoration %d is the texture the original look shows (%s)" % [i, ModDraw.describe(drawn[i])]).is_same(expected[i][0])
		assert_that(drawn[i][2]).is_equal(expected[i][1])
		assert_bool(drawn[i][3]).is_equal(expected[i][2])
	assert_array(swaying["key"]).is_not_empty()
	for i in (swaying["key"] as Array).size():
		var command: Array = drawn[drawn.size() - (swaying["key"] as Array).size() + i]
		assert_object(command[1]).is_same(Assets.picture_by_key(swaying["key"][i]))
		assert_that(command[2]).is_equal(swaying["position"][i])
	var arena := SimWorld.new(GameState)                                                                    # (a screen with a background and a station: the original look's background picture, and the station's parts)
	arena.load_sector(0, 0)
	arena.start_flight(200, 150, 6)
	var with_station := _presenter(arena, skin)
	with_station.show_between_ticks(1.0)
	var station_original := _the_original_look(arena, skin)
	var station_drawn := _game_pictures(with_station, shelf)
	assert_object(station_original.background.texture).is_not_null()
	assert_object(station_drawn[0][1]).override_failure_message("the first picture is the background").is_same(station_original.background.texture)
	assert_that(station_drawn[0][2]).is_equal(Vector2.ZERO)
	var parts := (SkinState.build(with_station.view)["station"]["parts"] as Array).filter(func(part: Dictionary) -> bool: return part["shown"])
	var door := parts.filter(func(part: Dictionary) -> bool: return part["name"] == "door")[0] as Dictionary
	assert_object(station_original.station.door.texture).is_not_null()
	assert_array(station_drawn.filter(func(c: Array) -> bool: return c[1] == station_original.station.door.texture and c[2] == door["position"])).has_size(1)


func test_a_picture_named_by_key_is_the_skin_in_uses_picture_and_the_original_look_shows_the_same() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(shelf.id)
	var other := ImageTexture.create_from_image(Image.create(608, 288, false, Image.FORMAT_RGBA8))
	skin.pictures["background/bg_s00_03"] = other
	skin.forget()
	var sim := SimWorld.new(GameState)
	sim.load_sector(0, 3)
	sim.start_flight(200, 150, 6)
	var presenter := _presenter(sim, skin)
	presenter.show_between_ticks(1.0)
	var original := _the_original_look(sim, skin)
	assert_object(original.background.texture).is_same(other)
	assert_object(_game_pictures(presenter, shelf)[0][1]).override_failure_message("the mod's list names the key and the game draws the skin's picture for it").is_same(other)
	skin.pictures.erase("background/bg_s00_03")
	skin.forget()
	presenter.refresh()
	assert_object(_game_pictures(presenter, shelf)[0][1]).override_failure_message("without it, the chain's own").is_same(Assets.background(0, 3))


func test_what_moves_is_drawn_between_where_it_was_and_where_it_is() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var sim := _sim()
	sim.tick(InputSnapshot.steering(1, 0))
	sim.tick(InputSnapshot.firing())
	sim.tick(InputSnapshot.steering(1, 0))
	var presenter := _presenter(sim, SkinChoice.load_skin(shelf.id))
	var sub := presenter.view.sub()
	assert_bool(sub.motion.moved()).is_true()
	var where: Array[Vector2] = []
	for fraction in [0.0, 0.5, 1.0]:
		presenter.show_between_ticks(fraction)
		var drawn := _commands(presenter, "picture").filter(func(c: Array) -> bool: return c[1] == shelf.pack.texture("skin/sub.png"))
		where.append((drawn[0][2] as Rect2).position + Vector2(48, 27))
		assert_that(where.back()).is_equal(sub.motion.at(fraction))                               # (the script did the arithmetic `SimView.Motion.at` does)
	assert_that(where[0]).is_not_equal(where[2])
	assert_int(presenter.view.pellets().size()).is_greater(0)
	assert_int(_commands(presenter, "picture").filter(func(c: Array) -> bool: return c[1] == shelf.pack.texture("skin/ink.png")).size()).is_equal(presenter.view.pellets().size())


func test_the_skins_shader_is_the_one_the_game_compiled_with_the_uniforms_the_script_chose() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(shelf.id) as ModSkin
	var presenter := _presenter(_sim(), skin)
	presenter.show_between_ticks(0.5)
	var shaded: ModLayer = null
	for layer: Array in _layers(presenter):
		if (layer[0] as ModLayer).material is ShaderMaterial:
			shaded = layer[0]
	assert_object(shaded).is_not_null()
	var material := shaded.material as ShaderMaterial
	assert_object(material.shader).is_same(skin.assets.shaders["skin/glow.gdshader"])
	assert_that(material.get_shader_parameter("tint")).is_equal(Color(1.0, 0.9, 0.3))
	assert_float(material.get_shader_parameter("strength")).is_equal(0.0)
	assert_float(material.get_shader_parameter("phase")).override_failure_message("the game sets `phase` on the shader of a layer the script draws").is_equal_approx(presenter.view.tick_number + 0.5, 0.0001)
	presenter.show_between_ticks(0.75)
	assert_float(material.get_shader_parameter("phase")).is_equal_approx(presenter.view.tick_number + 0.75, 0.0001)
	assert_str(material.shader.code).is_equal(shelf.pack.read_text("skin/glow.gdshader"))
	for layer: Array in _layers(presenter):                                                           # (only the layer that named the shader has a material)
		if layer[0] != shaded:
			assert_object((layer[0] as ModLayer).material).is_null()


func test_the_example_skin_draws_every_screen_of_every_sector_of_the_pack_without_a_fault() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var mod := ModHost.mod(String(shelf.id))
	var faults := int(mod.get("monitor_exceptions"))
	var most := 0
	var screens := 0
	for index in Catalog.sector_ids():
		var sim := SimWorld.new(GameState)
		var presenter := _presenter(sim, SkinChoice.load_skin(shelf.id))
		sim.load_sector(index, 0)
		for screen in Catalog.sector(index).screens.size():
			sim.load_screen(screen)
			presenter.refresh()
			screens += 1
			var layers := _layers(presenter)
			for layer: Array in layers:
				most = maxi(most, (layer[1] as Array).size())
		presenter.unbind()
		sim.abandon_damage()
	assert_int(screens).is_greater(10)
	assert_int(most).is_greater(2)
	assert_int(int(mod.get("monitor_exceptions"))).override_failure_message("the example skin faulted on a screen (a skin may hold about a hundred host objects at once, docs/create/SKIN_API.md)").is_equal(faults)


func test_the_skin_is_told_what_happened_in_the_order_it_happened() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var sim := _sim()
	var presenter := _presenter(sim, SkinChoice.load_skin(shelf.id))
	presenter.show_between_ticks(1.0)
	var mod := ModHost.mod(String(shelf.id))
	mod.call("heard_events")
	sim.tick(InputSnapshot.firing())
	presenter.show_between_ticks(0.0)
	var heard: Array = mod.call("heard_events")
	assert_array(heard).contains(["pellet_fired", "ticked"])
	assert_bool(heard.find("pellet_fired") < heard.rfind("ticked")).is_true()
	assert_str(heard.back()).is_equal("ticked")                                                       # (always last)


func test_the_state_a_skin_gets_is_plain_data_and_read_only() -> void:
	_mount(["skinny"] as Array[String])
	var sim := _sim()
	sim.tick(InputSnapshot.firing())
	var state := SkinState.build(SimView.new(sim))
	var bad: Array[String] = []
	_plain_only(state, "state", bad)
	assert_array(bad).is_empty()
	assert_bool(state.is_read_only()).is_true()
	assert_bool((state["sub"] as Dictionary).is_read_only()).is_true()
	assert_bool((state["creatures"] as Array).is_read_only()).is_true()
	assert_int((state["walls"] as String).length()).is_equal(SkinState.COLUMNS * SkinState.ROWS)
	assert_array(state["pellets"]).is_not_empty()
	var event := SkinState.event(&"creature_hit_by_ink", [SimView.CreatureState.new(), SimView.SubState.new(), &"name", Vector2(1, 2)])
	assert_array(event).is_equal(["creature_hit_by_ink", 0, null, "name", Vector2(1, 2)])


func _plain_only(value: Variant, path: String, bad: Array[String]) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if not key is String:
				bad.append("%s has a key %s" % [path, key])
			_plain_only(value[key], "%s.%s" % [path, key], bad)
	elif value is Array:
		for i in (value as Array).size():
			_plain_only(value[i], "%s[%d]" % [path, i], bad)
	elif not (value == null or value is int or value is float or value is bool or value is String or value is Vector2 or value is Rect2 or value is Color):
		bad.append("%s is a %s" % [path, type_string(typeof(value))])


# --- the life of a skin --------------------------------------------------------------------------------------------------

func test_a_skin_ends_with_its_mod_and_the_skin_in_use_falls_back_to_the_original() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(shelf.id) as ModSkin
	SkinChoice.select(skin)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_bool(world.original.hosts_mod_layers()).is_true()
	var gone := shelf.id
	ModSkinShelf.release(_shelves)                                                                    # (the pack leaves the chain; the mod is unloaded)
	assert_bool(skin.alive).is_false()
	assert_array(SkinChoice.available()).not_contains([gone])
	assert_object(SkinChoice.current()).is_same(SkinChoice.original())
	assert_bool(world.original.hosts_mod_layers()).is_false()
	assert_object(ModHost.skin(gone)).is_null()


func test_a_presenter_whose_mod_has_gone_draws_nothing_and_asks_nobody() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(shelf.id)
	var presenter := _presenter(_sim(), skin)
	presenter.show_between_ticks(1.0)
	assert_array(presenter.mod_drawn()).is_not_empty()
	ModSkinShelf.release(_shelves)
	presenter.show_between_ticks(1.0)
	assert_array(_layers(presenter).filter(func(l: Array) -> bool: return not (l[1] as Array).is_empty())).is_empty()
	presenter.unbind()


func test_a_mod_loaded_again_is_a_skin_again() -> void:
	var shelf := _mount(["skinny"] as Array[String])
	var first := SkinChoice.load_skin(shelf.id)
	Packs.use(Pack.open(shelf.root))
	Mods.sync()
	assert_object(SkinChoice.load_skin(shelf.id)).override_failure_message("the same running mod, the same skin").is_same(first)
	Packs.start()
	Mods.sync()
	assert_array(SkinChoice.available()).not_contains([shelf.id])
	Packs.use(Pack.open(shelf.root))
	Mods.sync()
	var second := SkinChoice.load_skin(shelf.id)
	assert_object(second).is_instanceof(ModSkin)
	assert_object(second).is_not_same(first)
	assert_bool(first.alive).is_false()
	assert_bool(second.alive).is_true()


func test_a_faulty_skin_draws_nothing_and_is_replaced_by_the_original_once_it_is_quarantined() -> void:
	var shelf := _mount(["skin_faulty"] as Array[String])
	var skin := SkinChoice.load_skin(shelf.id)
	SkinChoice.select(skin)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_bool(world.original.hosts_mod_layers()).is_true()
	world.sim.load_sector(DevCreatures.ARENA, 0)
	world.sim.start_flight(200, 150, 6)
	var mod := ModHost.mod(String(shelf.id))
	var faults := int(mod.get("monitor_exceptions"))
	for i in ModLoader.MAX_FAULTS + 5:
		world.presenter.show_between_ticks(0.5)
	assert_int(int(mod.get("monitor_exceptions"))).is_greater(faults)
	assert_array(_layers(world.original).filter(func(l: Array) -> bool: return not (l[1] as Array).is_empty())).is_empty()
	Mods.loader().check_health()
	assert_bool(ModHost.is_quarantined(String(shelf.id))).is_true()
	assert_object(SkinChoice.current()).override_failure_message("the quarantined skin is still worn").is_same(SkinChoice.original())
	assert_bool(world.original.hosts_mod_layers()).is_false()
	assert_array(SkinChoice.available()).not_contains([shelf.id])
	Mods.loader().resume(String(shelf.id))
	assert_array(SkinChoice.available()).contains([shelf.id])                                          # (it is a skin again when it is let run)


func test_a_skin_that_never_returns_costs_a_frame_a_little_and_is_replaced_in_the_end() -> void:
	var shelf := _mount(["skin_spinner"] as Array[String])
	var mod := ModHost.mod(String(shelf.id))
	assert_int(mod.get("execution_timeout")).is_equal(1)                                              # (it asked for none: it got the lowest)
	SkinChoice.select(SkinChoice.load_skin(shelf.id))
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.sim.load_sector(DevCreatures.ARENA, 0)
	world.sim.start_flight(200, 150, 6)
	var timeouts := int(mod.get("monitor_execution_timeouts"))
	var started := Time.get_ticks_msec()
	world.presenter.show_between_ticks(0.5)
	assert_int(Time.get_ticks_msec() - started).override_failure_message("one frame of a skin that never returns took %d ms" % (Time.get_ticks_msec() - started)).is_less(1000)
	assert_int(int(mod.get("monitor_execution_timeouts"))).is_equal(timeouts + 1)
	var tick := world.sim.tick_number
	for i in 10:
		world.presenter.show_between_ticks(0.5)
	assert_int(world.sim.tick_number).is_equal(tick)                                                  # (drawing never moves the rules)
	Mods.loader().forgive(String(shelf.id))


func test_the_rules_run_the_same_whatever_a_skin_mod_does() -> void:
	_mount(["skinny", "skin_faulty"] as Array[String])
	var traces: Array = []
	for skin in [null, SkinChoice.load_skin(_shelves[0].id), SkinChoice.load_skin(_shelves[1].id)]:
		GameState.reset()
		var sim := SimWorld.new(GameState)
		var presenter: OriginalPresenter = null
		if skin != null:
			presenter = _presenter(sim, skin)
		sim.load_sector(DevCreatures.ARENA, 0)
		sim.foe_context.rng.seed = 4242
		sim.start_flight(200, 150, 6)
		var lines: Array[String] = []
		for t in 120:
			sim.tick(InputSnapshot.firing() if t % 7 == 0 else InputSnapshot.new())
			if presenter != null:
				presenter.show_between_ticks(0.5)
			lines.append("%s %s %s" % [sim.sub.position, sim.foes.map(func(f: FoeModel) -> Vector2i: return Vector2i(f.vm.x, f.vm.y)), sim.pellets.size()])
		traces.append(lines)
		if presenter != null:
			presenter.unbind()
	assert_array(traces[1]).is_equal(traces[0])
	assert_array(traces[2]).is_equal(traces[0])


# --- the hostile skin ------------------------------------------------------------------------------------------------------

func test_a_hostile_skin_mod_reaches_nothing_of_the_game() -> void:
	var shelf := _mount(["skin_hostile"] as Array[String])
	var mod := ModHost.mod(String(shelf.id))
	assert_object(mod).is_not_null()
	var sim := _sim()
	var state := SkinState.build(SimView.new(sim))
	var events: Array = [["ticked"]]
	ModLoader.freeze(events)
	var before := {"root": get_tree().root.get_children().map(func(c: Node) -> String: return c.name), "oxygen": GameState.oxygen(), "ink": GameState.ink, "chain": Packs.chain_ids(), "sub": sim.sub.position,
			"mods": Mods.loaded_ids(), "skins": SkinChoice.available(), "state": state.duplicate(true)}
	var attempts := 0
	for method in mod.get_method_list():
		var attempt: String = method["name"]
		if not attempt.begins_with("try_"):
			continue
		attempts += 1
		var arguments: Array = []
		for argument: Dictionary in method["args"]:
			arguments.append(events if argument["name"] == "events" else state)
		var faults := int(mod.get("monitor_exceptions"))
		var result: Variant = mod.callv(attempt, arguments)
		assert_bool(int(mod.get("monitor_exceptions")) > faults).override_failure_message("%s was not refused: %s" % [attempt, result]).is_true()
	assert_int(attempts).is_greater_equal(15)
	assert_dict(state).is_equal(before["state"])                                                     # (the state it was given is as it was)
	assert_array(get_tree().root.get_children().map(func(c: Node) -> String: return c.name)).is_equal(before["root"])
	assert_int(GameState.oxygen()).is_equal(before["oxygen"])
	assert_int(GameState.ink).is_equal(before["ink"])
	assert_array(Packs.chain_ids()).is_equal(before["chain"])
	assert_that(sim.sub.position).is_equal(before["sub"])
	assert_array(Mods.loaded_ids()).is_equal(before["mods"])
	assert_array(SkinChoice.available()).is_equal(before["skins"])
	assert_str(String(mod.name)).is_equal(String(shelf.id))
	Mods.loader().forgive(String(shelf.id))


func test_the_api_answers_a_hostile_skin_with_nothing() -> void:
	var shelf := _mount(["skin_hostile"] as Array[String])
	var mod := ModHost.mod(String(shelf.id))
	var faults := int(mod.get("monitor_exceptions"))
	for name in ["check_load_a_picture_of_another_pack", "check_load_the_pack_of_the_chain"]:
		assert_object(mod.call(name)).override_failure_message(name).is_null()
	assert_int(int(mod.get("monitor_exceptions"))).is_equal(faults)


func test_a_hostile_skin_that_draws_garbage_changes_nothing_but_its_own_picture() -> void:
	var shelf := _mount(["skin_hostile"] as Array[String])
	var skin := SkinChoice.load_skin(shelf.id)
	var sim := _sim()
	var presenter := _presenter(sim, skin)
	presenter.show_between_ticks(0.5)
	assert_int(_commands(presenter, "rect").size()).is_equal(1)                                         # (its one good rectangle)
	var oxygen := GameState.oxygen()
	for t in 30:
		sim.tick()
		presenter.show_between_ticks(0.5)
	assert_int(GameState.oxygen()).is_equal(oxygen)
	presenter.unbind()


func test_a_mod_that_is_not_a_skin_has_no_presenter_and_no_entry_in_the_choice() -> void:
	var hello := PackShelf.new()
	_shelves.append(hello)
	hello.add_mod_fixture("res://tests/mods/hello")
	hello.mount()
	Mods.sync()
	assert_array(Mods.loaded_ids()).contains([String(hello.id)])
	assert_array(SkinChoice.available()).not_contains([hello.id])
	assert_object(ModHost.skin(hello.id)).is_null()
