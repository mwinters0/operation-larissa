class_name TestModProblems
extends GdUnitTestSuite
## Teaches: a stranger's code that draws the screen of a problem and is never its judge. A mod pack adds a problem type as DATA (words, records, how an answer is judged: the same file as the original's 34) and its script draws the
## picture of that type (`problem_frame(state)` returns a draw list that `ModDraw` checks and `ModLayer` draws); the calculator, `AnswerChecker`, `ProblemSession` and `ProblemFlow` stay the game's, so what a mod returns, hostile or
## broken, changes no answer, no oxygen and no duration: the tests play the same problem under a good mod, a hostile one, a faulty one and none, and the plays are the same. They also cover the manifest, the type as data, the
## text command of the shared validator, the plain picture a screen falls back to, the one builder every way of opening a problem goes through, and the hostile mod `tests/mods/tides_hostile`.
## These tests need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`, docs/SETUP.md).

const TYPE := ModProblemShelf.TYPE

var _shelves: Array[PackShelf] = []


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func before_test() -> void:
	GameClock.paused = false
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	ModLoader.pretend_no_sandbox = false
	ModProblemShelf.release(_shelves)
	GameState.reset()


func _mount(names: Array[String]) -> PackShelf:
	_shelves = ModProblemShelf.mount(names)
	return _shelves.back()


func _plain() -> PackShelf:
	var shelf := ModProblemShelf.plain()
	_shelves.append(shelf)
	return shelf


## A problem screen with problem 40's record `record` (level 0) started; the caller frees it.
func _screen(record: int = 0) -> ProblemScreen:
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.start(ProblemFactory.make(TYPE, 0, null, record))
	return screen


func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


func _lines(screen: ProblemScreen) -> Array[String]:
	return (screen.diagram as ModDiagram).drawn_lines()


func _count(lines: Array[String], prefix: String) -> int:
	return lines.filter(func(line: String) -> bool: return line.begins_with(prefix)).size()


func _report(shelf: PackShelf) -> PackReport:
	var options := PackCheck.Options.new()
	options.reach = false
	return PackCheck.run(Pack.open(shelf.root), options)


# --- the manifest ---------------------------------------------------------------------------------------------------------

func test_a_problems_entry_makes_the_mod_draw_problem_types() -> void:
	var got := _parse({"entry": "tides.sgd", "requires_api": 3, "problems": {"types": [40, 41], "shaders": ["problems/glow.gdshader"]}})
	var spec: ModSpec = got[0]
	assert_array(got[1]).is_empty()
	assert_bool(spec.has_problems).is_true()
	assert_bool(spec.is_skin).is_false()
	assert_bool(spec.draws()).is_true()
	assert_array(spec.problem_types).is_equal([40, 41])
	assert_array(spec.problem_shaders).is_equal(["problems/glow.gdshader"])
	assert_dict(spec.to_dict()).is_equal({"entry": "tides.sgd", "requires_api": 3, "problems": {"types": [40, 41], "shaders": ["problems/glow.gdshader"]}})
	var both: ModSpec = _parse({"entry": "a.sgd", "requires_api": 3, "skin": {"shaders": ["skin/a.gdshader"]}, "problems": {"types": [34]}})[0]
	assert_bool(both.is_skin and both.has_problems).is_true()
	assert_array(both.shaders).is_equal(["skin/a.gdshader"])                              # (each kind lists its own shaders)
	assert_array(both.problem_shaders).is_empty()
	assert_int(ModSpec.API_VERSION).is_greater_equal(ModSpec.PROBLEM_API_VERSION)
	for older in [1, 2]:
		assert_object(_parse({"entry": "a.sgd", "requires_api": older})[0]).override_failure_message("a mod of API %d is refused" % older).is_not_null()


func test_a_mod_that_draws_problems_gets_a_lower_instruction_limit_and_cannot_turn_counting_off() -> void:
	var asked := {"entry": "a.sgd", "requires_api": 3, "problems": {"types": [40]}}
	assert_int((_parse(asked)[0] as ModSpec).limits["execution_timeout"]).is_equal(ModSpec.MAX_DRAWING_EXECUTION_TIMEOUT)
	asked["limits"] = {"execution_timeout": 0}
	assert_int((_parse(asked)[0] as ModSpec).limits["execution_timeout"]).is_equal(1)
	asked["limits"] = {"execution_timeout": 150}
	assert_int((_parse(asked)[0] as ModSpec).limits["execution_timeout"]).is_equal(ModSpec.MAX_DRAWING_EXECUTION_TIMEOUT)


func test_every_mistake_in_a_problems_entry_is_a_sentence() -> void:
	var count := Catalog.PROBLEM_TYPE_COUNT
	var bad := {
		"the first API": [{"entry": "a.sgd", "problems": {"types": [40]}}, "requires_api"],
		"not an object": [{"entry": "a.sgd", "requires_api": 3, "problems": [40]}, "must be an object"],
		"no types": [{"entry": "a.sgd", "requires_api": 3, "problems": {}}, "needs \"types\""],
		"no types listed": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": []}}, "needs \"types\""],
		"types not a list": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": 40}}, "needs \"types\""],
		"an unknown key": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": [40], "fonts": []}}, "no \"fonts\""],
		"a type of the original": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": [count - 1]}}, "must be a whole number from %d" % count],
		"a type past the trigger table's byte": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": [256]}}, "to 255"],
		"a type that is not a number": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": ["forty"]}}, "must be a whole number"],
		"a type twice": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": [40, 40]}}, "listed twice"],
		"too many types": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": range(count, count + ModSpec.MAX_PROBLEM_TYPES + 1)}}, "at most"],
		"a shader of the skin folder": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": [40], "shaders": ["skin/a.gdshader"]}}, "must be a file"],
		"a shader climbing out": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": [40], "shaders": ["problems/../a.gdshader"]}}, "must be a file"],
		"a shader twice": [{"entry": "a.sgd", "requires_api": 3, "problems": {"types": [40], "shaders": ["problems/a.gdshader", "problems/a.gdshader"]}}, "twice"],
		"a skin shader in the problems folder": [{"entry": "a.sgd", "requires_api": 3, "skin": {"shaders": ["problems/a.gdshader"]}}, "must be a file"],
	}
	for what: String in bad:
		var got := _parse(bad[what][0])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_bool((got[1] as Array[String]).any(func(e: String) -> bool: return e.contains(bad[what][1]))).override_failure_message("%s: %s" % [what, got[1]]).is_true()


func test_a_problem_mod_is_given_the_problem_facts_and_other_mods_are_not() -> void:
	var tides := _mount(["tides"] as Array[String])
	var api: Dictionary = ModApi.new(Mods.loader()).build("x", tides.pack)
	assert_int(api["api_version"]).is_equal(ModSpec.API_VERSION)
	assert_dict(api["problems"]).is_equal({"types": [TYPE], "window": Vector2(640, 400), "max_commands": ModDraw.MAX_COMMANDS, "max_layers": ModDraw.MAX_LAYERS, "max_uniforms": ModDraw.MAX_UNIFORMS,
			"max_texts": ModDraw.MAX_TEXTS, "max_text": ModDraw.MAX_TEXT, "min_font_size": ModDraw.MIN_FONT_SIZE, "max_font_size": ModDraw.MAX_FONT_SIZE, "shaders": ["problems/glow.gdshader"]})
	assert_bool(api.has("skin")).is_false()
	for value: Variant in api["problems"].values():
		assert_bool(value is Object).is_false()                                                      # (numbers and names: nothing to reach through)
	assert_bool(ModApi.new(Mods.loader()).build("x", null).has("problems")).is_false()
	assert_that(ProblemState.WINDOW_SIZE).is_equal(Vector2i(DiagramBase.WINDOW_SIZE))


# --- the text command of the shared validator -----------------------------------------------------------------------------

func test_the_text_command_is_checked_cut_and_copied() -> void:
	var assets := ModAssets.new()
	assets.folder = ModSpec.PROBLEM_FOLDER
	var drawn := ModDraw.validate([
		["text", "plain", Vector2(1, 2), 17, Color.WHITE],
		["text", "width", Vector2(1, 2), 17.4, Color.RED, 120.0],
		["text", "aligned", Vector2(1, 2), 20, Color.RED, "right"],
		["text", "both", Vector2(1, 2), 20, Color.RED, 120, "center"],
		["text", "tiny", Vector2(0, 0), 1, Color.WHITE],
		["text", "huge", Vector2(0, 0), 100000, Color.WHITE],
		["text", "a\tb\nc" + char(27) + "d", Vector2(0, 0), 17, Color.WHITE],
	], null, assets)
	assert_int(drawn.dropped).is_equal(0)
	var texts: Array = drawn.layers[0].commands
	assert_array(texts[0]).is_equal(["text", "plain", Vector2(1, 2), 17, Color.WHITE, -1.0, HORIZONTAL_ALIGNMENT_LEFT])
	assert_array(texts[1]).is_equal(["text", "width", Vector2(1, 2), 17, Color.RED, 120.0, HORIZONTAL_ALIGNMENT_LEFT])
	assert_array(texts[2]).is_equal(["text", "aligned", Vector2(1, 2), 20, Color.RED, -1.0, HORIZONTAL_ALIGNMENT_RIGHT])
	assert_array(texts[3]).is_equal(["text", "both", Vector2(1, 2), 20, Color.RED, 120.0, HORIZONTAL_ALIGNMENT_CENTER])
	assert_int(texts[4][3]).is_equal(ModDraw.MIN_FONT_SIZE)
	assert_int(texts[5][3]).is_equal(ModDraw.MAX_FONT_SIZE)
	assert_str(texts[6][1]).is_equal("a b c d")                                                      # (control characters become spaces)
	var long := ModDraw.validate([["text", "x".repeat(ModDraw.MAX_TEXT + 50), Vector2(0, 0), 17, Color.WHITE]], null, assets)
	assert_int((long.layers[0].commands[0][1] as String).length()).is_equal(ModDraw.MAX_TEXT)
	var many: Array = []
	for i in ModDraw.MAX_TEXTS + 30:
		many.append(["text", "t", Vector2(0, i), 17, Color.WHITE])
	var capped := ModDraw.validate(many, null, assets)
	assert_int(capped.layers[0].commands.size()).is_equal(ModDraw.MAX_TEXTS)
	assert_int(capped.dropped).is_equal(30)
	for garbage in [["text"], ["text", "no place"], ["text", 5, Vector2(0, 0), 17, Color.WHITE], ["text", "x", Vector2(0, 0), 17], ["text", "x", Vector2(0, 0), "big", Color.WHITE],
			["text", "x", Vector2(0, 0), NAN, Color.WHITE], ["text", "x", Vector2(INF, 0), 17, Color.WHITE], ["text", "x", Vector2(0, 0), 17, Color.WHITE, -5.0],
			["text", "x", Vector2(0, 0), 17, Color.WHITE, 50.0, "justify"], ["text", "x", Vector2(0, 0), 17, Color.WHITE, "center", 50.0], ["text", "x", Vector2(0, 0), 17, Color.WHITE, 50.0, "left", "font.ttf"]]:
		assert_bool(ModDraw.is_empty(ModDraw.validate([garbage], null, assets))).override_failure_message("%s was drawn" % [garbage]).is_true()


func test_a_picture_is_a_file_of_the_folder_of_the_assets_and_of_the_mods_own_pack() -> void:
	var tides := _mount(["tides"] as Array[String])
	var screens := ModHost.problem_screen(TYPE)
	assert_object(screens).is_not_null()
	assert_str(screens.assets.folder).is_equal("problems/")
	var drawn := ModDraw.validate([
		["picture", "problems/fish.png", Vector2(0, 0)],
		["picture", "skin/dot.png", Vector2(0, 0)],
		["picture", "problems/missing.png", Vector2(0, 0)],
		["picture", "problems/../pack.json", Vector2(0, 0)],
		["layer", "skin/glow.gdshader"],
		["rect", Rect2(0, 0, 1, 1), Color.RED],
	], tides.pack, screens.assets)
	assert_int(drawn.layers[0].commands.size()).is_equal(1)
	assert_int(drawn.dropped).is_equal(5)                                                         # (three pictures, the shader it does not list, and the rectangle after it: what follows a refused layer is not drawn)
	assert_bool(ModDraw.is_empty(ModDraw.validate([["picture", "problems/fish.png", Vector2(0, 0)]], tides.pack, null))).is_true()


# --- a problem type of a pack, as data ------------------------------------------------------------------------------------

func test_the_chain_without_the_pack_has_the_originals_types_and_no_mod_draws_one() -> void:
	assert_array(Catalog.problem_type_ids()).is_equal(range(Catalog.PROBLEM_TYPE_COUNT))
	assert_object(Catalog.problem_type(TYPE)).is_null()
	assert_object(ModHost.problem_screen(TYPE)).is_null()
	assert_object(ProblemFactory.make(TYPE, 0)).is_null()
	assert_bool(PracticeSet.available_types(0).has(TYPE)).is_false()


func test_a_mod_pack_adds_a_problem_type_through_the_same_door_as_a_data_pack() -> void:
	_mount(["tides"] as Array[String])
	assert_array(Catalog.problem_type_ids()).is_equal(range(Catalog.PROBLEM_TYPE_COUNT) + [TYPE])
	var type := Catalog.problem_type(TYPE)
	assert_str(type.title).is_equal("Fish in rows")
	assert_int(type.record_count(0)).is_equal(2)
	assert_str(String(type.diagram["family"])).is_equal(ModProblems.FAMILY)
	var problem := ProblemFactory.make(TYPE, 0, null, 0)
	assert_str(problem.prompt).is_equal("How many fish are in 3 rows of 4?")                             # (worded by the data: text 0 with the record's fields in the slots)
	assert_str(problem.hint).is_equal("Count one row, then count the rows.")
	assert_str(problem.solution).is_equal("3 rows of 4 make 12.")
	assert_str(problem.success).is_equal("Well fished!")
	assert_bool(problem.check(NumberValue.parse("12"))).is_true()                                   # (judged by the game's checker, from the type's data)
	assert_bool(problem.check(NumberValue.parse("13"))).is_false()
	assert_object(ProblemFactory.make(TYPE, 3)).is_null()                                         # (no record at that level)
	assert_object(ModHost.problem_screen(TYPE)).is_not_null()
	assert_array(PracticeSet.available_types(0).slice(-1)).is_equal([TYPE])                       # (the practice set "All" asks it after the originals)
	assert_bool(PracticeSet.available_types(2).has(TYPE)).is_false()
	ModProblemShelf.release(_shelves)
	assert_object(Catalog.problem_type(TYPE)).is_null()
	assert_array(Catalog.problem_type_ids()).is_equal(range(Catalog.PROBLEM_TYPE_COUNT))


func test_a_trigger_asks_an_added_type_only_in_a_chain_that_has_it() -> void:
	var table := Catalog.trigger_table().duplicate() as TriggerTable
	var other := table.type_for(5, 0, 1)
	var bytes := table.table.duplicate()
	bytes[(5 * TriggerTable.LEVELS + 0) * TriggerTable.PICKS + 0] = TYPE
	table.table = bytes
	var without := PackShelf.new()
	_shelves.append(without)
	without.write_json("data/trigger_table.json", ResourceJson.new().data_of(table))
	without.mount()
	for seed in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var asked := ProblemFactory.for_trigger_slot(5, 0, rng)
		assert_object(asked).override_failure_message("a trigger named a type the chain lacks and asked nothing").is_not_null()
		assert_int(asked.type.id).is_equal(other)                                                 # (the other candidate: the type is absent from this chain)
	var with := PackShelf.new(&"", without.id)
	_shelves.append(with)
	with.write_json("data/problems/problem_type_%02d.json" % TYPE, ResourceJson.new().data_of(ModProblemShelf.problem_type()))
	with.mount()
	var types := {}
	for seed in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		types[ProblemFactory.for_trigger_slot(5, 0, rng).type.id] = true
	assert_array(types.keys()).contains_exactly_in_any_order([TYPE, other])


func test_the_practice_set_of_the_original_picks_only_original_types() -> void:
	_mount(["tides"] as Array[String])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 20:
		assert_bool(PracticeSet.build(PracticeSet.Kind.FIVE, 0, rng).size() == PracticeSet.FIVE_PROBLEMS).is_true()
		for type_id in PracticeSet.build(PracticeSet.Kind.FIVE, 0, rng):
			assert_int(type_id).is_less_equal(PracticeSet.LAST_TYPE)
	assert_array(PracticeSet.build(PracticeSet.Kind.ALL, 0).slice(-2)).is_equal([PracticeSet.LAST_TYPE, TYPE])


# --- the screen -----------------------------------------------------------------------------------------------------------

func test_the_mod_draws_the_screen_of_its_type_from_the_problem_and_the_entry() -> void:
	var tides := _mount(["tides"] as Array[String])
	var screen := _screen(0)
	assert_object(screen.diagram).is_instanceof(ModDiagram)
	var lines := _lines(screen)
	assert_int(_count(lines, "picture fish.png")).is_equal(12)                                         # (3 rows of 4)
	assert_int(_count(lines, "text Typed: 0")).is_equal(1)                                              # (the calculator shows 0 before anything is typed)
	assert_int(_count(lines, "text Fish in rows")).is_equal(1)
	assert_int(_count(lines, "layer shaded")).is_equal(0)
	screen.calculator.press("7")
	lines = _lines(screen)
	assert_int(_count(lines, "text Typed: 7")).is_equal(1)
	assert_int(_count(lines, "layer shaded")).is_equal(1)                                              # (the glow layer, through the mod's own shader)
	assert_int(_count(lines, "region fish.png")).is_equal(1)
	var shaded := (screen.diagram as ModDiagram).layers().filter(func(layer: ModLayer) -> bool: return layer.material is ShaderMaterial)
	assert_int(shaded.size()).is_equal(1)
	assert_object((shaded[0] as ModLayer).material.shader).is_same(ModHost.problem_screen(TYPE).assets.shaders["problems/glow.gdshader"])
	assert_str(ModHost.mod(String(tides.id)).get("last_step")).is_equal("answering")
	var other := _screen(1)                                                                         # (a second problem on the same game: its own values)
	assert_int(_count(_lines(other), "picture fish.png")).is_equal(10)                                # (2 rows of 5)
	other.free()
	screen.free()


func test_the_mod_is_asked_again_only_when_what_it_is_told_changes() -> void:
	var tides := _mount(["tides"] as Array[String])
	var mod := ModHost.mod(String(tides.id))
	var screen := _screen(0)
	var diagram := screen.diagram as ModDiagram
	var asked: int = mod.call("times_asked")
	diagram.entry_changed("0")                                                                      # (what it already was told)
	diagram.entry_changed("0")
	assert_int(mod.call("times_asked")).is_equal(asked)
	diagram.entry_changed("12")
	assert_int(mod.call("times_asked")).is_equal(asked + 1)
	screen.answer_box.visible = true
	screen.free()


func test_the_state_a_problem_mod_gets_is_plain_data_without_a_verdict() -> void:
	_mount(["tides"] as Array[String])
	var problem := ProblemFactory.make(TYPE, 0, null, 0)
	var state := ProblemState.build(problem, "12", ProblemFlow.Step.ANSWERING)
	assert_array(state.keys()).contains_exactly_in_any_order(["type", "level", "title", "prompt", "fields", "entry", "step", "window"])
	assert_int(state["type"]).is_equal(TYPE)
	assert_str(state["entry"]).is_equal("12")
	assert_str(state["step"]).is_equal("answering")
	assert_array(state["fields"].slice(0, 2)).is_equal([3, 4])
	assert_dict(state["fields"][2]).is_equal({"text": "12", "value": 12.0, "fraction": false})
	assert_bool(state.is_read_only() and (state["fields"] as Array).is_read_only() and (state["fields"][2] as Dictionary).is_read_only()).is_true()
	var bad: Array[String] = []
	_plain_only(state, "state", bad)
	assert_array(bad).is_empty()
	for flow_step in ProblemFlow.Step.values():
		assert_bool(ProblemState.STEPS.has(ProblemState.step_name(flow_step))).is_true()
	assert_str(ProblemState.step_name(ProblemFlow.Step.INTRO)).is_equal("intro")
	assert_str(ProblemState.step_name(ProblemFlow.Step.MESSAGE)).is_equal("waiting")
	for key: String in state:                                                                         # (no verdict, no tries, no oxygen, no hint or solution)
		assert_bool(["correct", "right", "wrong", "misses", "tries", "oxygen", "hint", "solution", "success", "expected"].has(key)).is_false()
	var fractions := ProblemKit.type_of("exact", "cn", 1, [ProblemKit.flat([2, ProblemKit.fraction(0, 1, 4)])])
	fractions.id = TYPE
	var fraction := ProblemState.build(ProblemInstance.build(fractions, 0, 0), "", ProblemFlow.Step.INTRO)
	assert_dict(fraction["fields"][1]).is_equal({"text": "1/4", "value": 0.25, "fraction": true})


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


func test_a_type_with_no_mod_shows_the_plain_picture_of_its_data_and_completes() -> void:
	_plain()
	var screen := _screen(0)
	assert_object(screen.diagram).is_instanceof(ModDiagram)
	assert_array(_lines(screen)).is_equal(["plain 1 items"])
	var finished: Array = []
	screen.finished.connect(func(session: ProblemSession) -> void: finished.append(session))
	screen.submit_answer(NumberValue.parse("12"))
	screen.advance_ticks(ProblemFlow.message_ticks())
	assert_int(finished.size()).is_equal(1)
	assert_bool(finished[0].solved).is_true()
	screen.free()


func test_the_plain_picture_is_what_a_screen_shows_before_the_mod_has_drawn_and_after_it_is_gone() -> void:
	var tides := _mount(["tides"] as Array[String])
	var screen := _screen(0)
	var diagram := screen.diagram as ModDiagram
	assert_int(_count(_lines(screen), "picture fish.png")).is_equal(12)
	ModProblemShelf.release(_shelves)                                                               # (the pack leaves the chain in the middle of the problem)
	assert_bool(Mods.loaded_ids().has(String(tides.id))).is_false()
	diagram.entry_changed("5")
	assert_array(_lines(screen)).is_equal(["plain 1 items"])
	assert_int(diagram.layers().size()).is_equal(0)
	screen.free()


# --- the same everywhere ----------------------------------------------------------------------------------------------------

func test_every_way_of_opening_a_problem_reaches_the_mod_screen_through_one_builder() -> void:
	_mount(["tides"] as Array[String])
	# the problem runner (the game, practice mode, the tools)
	var host := Control.new()
	add_child(host)
	var problem := ProblemFactory.make(TYPE, 0, null, 0)
	var sessions: Array = []
	(func() -> void: sessions.append(await ProblemRunner.run(host, problem))).call()
	var screen := host.get_child(0) as ProblemScreen
	assert_int(_count(_lines(screen), "picture fish.png")).is_equal(12)
	screen.close()
	await await_idle_frame()
	assert_int(sessions.size()).is_equal(1)
	host.queue_free()
	# the debug menu
	var menu: Control = (load("res://src/debug/problem_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	var index := (menu.get("_type_ids") as Array).find(TYPE)
	assert_int(index).is_greater(33)
	assert_str(menu.type_list.get_item_text(index)).contains("Fish in rows")
	menu.call("_on_type_selected", index)
	assert_str(menu.info_label.text).contains("L0: 2")
	menu.call("_play", 0, TYPE)
	var shown: ProblemScreen = null
	for child in menu.get_children():
		if child is ProblemScreen:
			shown = child
	assert_object(shown).is_not_null()
	assert_int(_count(_lines(shown), "picture fish.png")).is_greater(0)
	shown.close()
	await await_idle_frame()
	menu.queue_free()
	# the factory itself, for the tools that draw a diagram without a screen
	var diagram := DiagramFactory.create(ProblemFactory.make(TYPE, 0, null, 1))
	assert_object(diagram).is_instanceof(ModDiagram)
	assert_int(_count((diagram as ModDiagram).drawn_lines(), "picture fish.png")).is_equal(10)
	diagram.free()


func test_only_the_factory_makes_a_diagram_and_only_the_problem_screen_asks_it() -> void:
	var offenders: Array[String] = []
	for path in _scripts("res://src") + _scripts("res://addons") + _scripts("res://tests"):
		if path.ends_with("/diagram_factory.gd") or path.ends_with("/test_mod_problems.gd"):
			continue
		var source := "\n".join(Array(FileAccess.get_file_as_string(path).split("\n")).filter(func(line: String) -> bool: return not line.strip_edges().begins_with("#")))
		for needle in ["ModDiagram.new(", "DiagramFactory.create("]:
			if source.contains(needle) and not (needle == "DiagramFactory.create(" and (path.ends_with("/problem_screen.gd") or path.contains("/tests/"))):
				offenders.append("%s makes a diagram with %s" % [path, needle])
	assert_array(offenders).is_empty()


func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			found.append("%s/%s" % [dir, file])
	for folder in DirAccess.get_directories_at(dir):
		found.append_array(_scripts("%s/%s" % [dir, folder]))
	return found


# --- the mod decides nothing ------------------------------------------------------------------------------------------------

## What happens when `answers` are given to problem `record` on a fresh screen: the step, the words, the oxygen after each, the sounds and the session.
func _play(answers: Array, record: int = 0) -> Array[String]:
	GameState.reset()
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	add_child(screen)
	var problem := ProblemFactory.make(TYPE, 0, null, record)
	var sounds: Array[String] = []
	var done: Array[String] = []
	screen.sfx_requested.connect(func(sfx: StringName) -> void:
		if sfx != Calculator.SFX_KEY:
			sounds.append(String(sfx)))
	screen.finished.connect(func(session: ProblemSession) -> void: done.append("solved %s misses %d" % [session.solved, session.misses]))
	screen.start(problem)
	var trace: Array[String] = []
	for answer: String in answers:
		match answer:
			"right":
				screen.submit_answer(problem.expected)
			"wrong":
				screen.submit_answer(NumberValue.decimal(-1))
			"type":
				screen.calculator.press("1")
				screen.calculator.press("2")
				screen.calculator.press("Enter")
			"continue":
				screen.press_continue()
			"wait":
				screen.advance_ticks(ProblemFlow.message_ticks())
		trace.append("%s: %s | %s | oxygen %d" % [answer, ProblemFlow.Step.keys()[screen.step()], screen.text_label.text.replace("\n", " / "), GameState.oxygen()])
	trace.append("sounds %s, finished %s, clock held %s" % [sounds, done, GameClock.paused])
	screen.free()
	return trace


const PLAYS: Array = [
	["right", "wait"],
	["wrong", "continue", "right", "wait"],
	["wrong", "continue", "wrong", "continue", "continue", "continue", "continue"],
	["type", "wait"],
]


func test_the_plays_of_a_problem_are_the_same_whichever_mod_draws_it_or_none() -> void:
	_plain()
	var baseline: Array = []
	for play: Array in PLAYS:
		baseline.append(_play(play))
	assert_str("\n".join(baseline[0])).contains("solved true misses 0")
	assert_str("\n".join(baseline[2])).contains("solved false misses 2")
	ModProblemShelf.release(_shelves)
	for name in ["tides", "tides_hostile", "tides_faulty"]:
		_mount([name] as Array[String])
		var mod := ModHost.mod(String(_shelves.back().id))
		assert_object(mod).override_failure_message("%s did not load: %s" % [name, ModHost.failure(String(_shelves.back().id))]).is_not_null()
		for i in PLAYS.size():
			assert_array(_play(PLAYS[i])).override_failure_message("%s changed the play %s" % [name, PLAYS[i]]).is_equal(baseline[i])
		Mods.loader().forgive(String(_shelves.back().id))
		ModProblemShelf.release(_shelves)


func test_a_hostile_mod_that_claims_to_have_judged_the_answer_judges_nothing() -> void:
	var shelf := _mount(["tides_hostile"] as Array[String])
	var screen := _screen(0)
	var lines := _lines(screen)
	assert_int(_count(lines, "rect")).is_equal(1)                                                    # (its one good rectangle; none of the nine claims after it is a command)
	assert_int(_count(lines, "text The answer is right")).is_equal(1)
	assert_array(lines.filter(func(line: String) -> bool: return line.begins_with("answer") or line.begins_with("correct") or line.begins_with("submit") or line.begins_with("close"))).is_empty()
	var finished: Array = []
	screen.finished.connect(func(session: ProblemSession) -> void: finished.append(session))
	screen.submit_answer(NumberValue.parse("13"))
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 1)                       # (wrong is wrong, and costs what it costs)
	assert_bool(screen.is_answering()).is_false()
	assert_int(finished.size()).is_equal(0)
	screen.free()
	Mods.loader().forgive(String(shelf.id))


func test_a_faulty_mod_leaves_the_plain_picture_and_is_quarantined_and_the_problem_completes() -> void:
	var shelf := _mount(["tides_faulty"] as Array[String])
	var mod := ModHost.mod(String(shelf.id))
	var screen := _screen(0)
	var diagram := screen.diagram as ModDiagram
	assert_array(_lines(screen)).is_equal(["plain 1 items"])                                       # (its first frame raised: nothing drawn, the picture of the data stays)
	var faults := int(mod.get("monitor_exceptions"))
	for i in ModLoader.MAX_FAULTS + 5:
		diagram.entry_changed(str(i))
	assert_int(int(mod.get("monitor_exceptions"))).is_greater(faults)
	assert_array(_lines(screen)).is_equal(["plain 1 items"])
	Mods.loader().check_health()
	assert_bool(ModHost.is_quarantined(String(shelf.id))).is_true()
	assert_object(ModHost.problem_screen(TYPE)).override_failure_message("a quarantined mod still draws").is_null()
	diagram.entry_changed("quarantined")
	assert_array(_lines(screen)).is_equal(["plain 1 items"])
	var finished: Array = []
	screen.finished.connect(func(session: ProblemSession) -> void: finished.append(session))
	screen.submit_answer(NumberValue.parse("12"))
	screen.advance_ticks(ProblemFlow.message_ticks())
	assert_int(finished.size()).is_equal(1)
	assert_bool(finished[0].solved).is_true()
	screen.free()
	Mods.loader().resume(String(shelf.id))
	assert_object(ModHost.problem_screen(TYPE)).is_not_null()                                       # (it draws again when it is let run)


func test_a_mod_that_never_returns_costs_a_screen_a_little_and_no_more() -> void:
	var shelf := _mount(["tides_spinner"] as Array[String])
	var mod := ModHost.mod(String(shelf.id))
	assert_int(mod.get("execution_timeout")).is_equal(1)                                           # (it asked for none: it got the lowest)
	var timeouts := int(mod.get("monitor_execution_timeouts"))
	var started := Time.get_ticks_msec()
	var screen := _screen(0)
	assert_int(Time.get_ticks_msec() - started).override_failure_message("opening a problem whose mod never returns took %d ms" % (Time.get_ticks_msec() - started)).is_less(2000)
	assert_int(int(mod.get("monitor_execution_timeouts"))).is_greater(timeouts)
	assert_array(_lines(screen)).is_equal(["plain 1 items"])
	screen.free()
	Mods.loader().forgive(String(shelf.id))


# --- the hostile mod --------------------------------------------------------------------------------------------------------

func test_a_hostile_problem_mod_reaches_nothing_of_the_game() -> void:
	var shelf := _mount(["tides_hostile"] as Array[String])
	var mod := ModHost.mod(String(shelf.id))
	assert_object(mod).is_not_null()
	var problem := ProblemFactory.make(TYPE, 0, null, 0)
	var state := ProblemState.build(problem, "3", ProblemFlow.Step.ANSWERING)
	var screen := _screen(0)
	var before := {"root": get_tree().root.get_children().map(func(c: Node) -> String: return c.name), "oxygen": GameState.oxygen(), "chain": Packs.chain_ids(), "mods": Mods.loaded_ids(),
			"state": state.duplicate(true), "lines": _lines(screen), "step": screen.step(), "text": screen.text_label.text}
	var attempts := 0
	for method in mod.get_method_list():
		var attempt: String = method["name"]
		if not attempt.begins_with("try_"):
			continue
		attempts += 1
		var arguments: Array = []
		for argument: Dictionary in method["args"]:
			arguments.append(state)
		var faults := int(mod.get("monitor_exceptions"))
		var result: Variant = mod.callv(attempt, arguments)
		assert_bool(int(mod.get("monitor_exceptions")) > faults).override_failure_message("%s was not refused: %s" % [attempt, result]).is_true()
	assert_int(attempts).is_greater_equal(8)
	assert_dict(state).is_equal(before["state"])
	assert_array(get_tree().root.get_children().map(func(c: Node) -> String: return c.name)).is_equal(before["root"])
	assert_int(GameState.oxygen()).is_equal(before["oxygen"])
	assert_array(Packs.chain_ids()).is_equal(before["chain"])
	assert_array(Mods.loaded_ids()).is_equal(before["mods"])
	assert_array(_lines(screen)).is_equal(before["lines"])
	assert_int(screen.step()).is_equal(before["step"])
	assert_str(screen.text_label.text).is_equal(before["text"])
	assert_bool(screen.is_answering()).is_true()                                                  # (it neither answered nor closed the problem)
	screen.free()
	Mods.loader().forgive(String(shelf.id))


func test_the_api_answers_a_hostile_problem_mod_with_nothing() -> void:
	var shelf := _mount(["tides_hostile"] as Array[String])
	var mod := ModHost.mod(String(shelf.id))
	var faults := int(mod.get("monitor_exceptions"))
	for name in ["check_load_a_picture_of_another_pack", "check_load_a_picture_of_the_chain"]:
		assert_object(mod.call(name)).override_failure_message(name).is_null()
	assert_int(int(mod.get("monitor_exceptions"))).is_equal(faults)


func test_a_hostile_problem_mod_that_draws_garbage_has_only_the_good_commands_drawn() -> void:
	var shelf := _mount(["tides_hostile"] as Array[String])
	var mod := ModHost.mod(String(shelf.id))
	var screens := ModHost.problem_screen(TYPE)
	var commands := ModDraw.validate(mod.call("bad_commands"), shelf.pack, screens.assets)
	assert_bool(ModDraw.is_empty(commands)).is_true()                                             # (no claim, no picture of another folder or pack, no shader of the other kind; the rectangle after the refused layer goes with it)
	assert_int(commands.dropped).is_equal(8)
	var texts := ModDraw.validate(mod.call("bad_texts"), shelf.pack, screens.assets)
	assert_int(texts.layers[0].commands.size()).is_equal(1)
	assert_str(texts.layers[0].commands[0][1]).is_equal("good")
	assert_int(texts.dropped).is_equal(11)
	var sizes := ModDraw.validate(mod.call("bad_text_sizes"), shelf.pack, screens.assets)
	assert_array(sizes.layers[0].commands.map(func(c: Array) -> int: return c[3])).is_equal([ModDraw.MIN_FONT_SIZE, ModDraw.MAX_FONT_SIZE, 17])
	assert_str(sizes.layers[0].commands[2][1]).is_equal("tab and newline escape")
	var long := ModDraw.validate(mod.call("bad_long_text"), shelf.pack, screens.assets)
	assert_int((long.layers[0].commands[0][1] as String).length()).is_equal(ModDraw.MAX_TEXT)
	var many := ModDraw.validate(mod.call("bad_many_texts"), shelf.pack, screens.assets)
	assert_int(many.layers[0].commands.size()).is_equal(ModDraw.MAX_TEXTS)
	Mods.loader().forgive(String(shelf.id))


# --- refusals ----------------------------------------------------------------------------------------------------------------

## A scratch pack of the fixture `tides` whose problem type 40 is `type` (null: no type file) and whose script is `script` (null: the fixture's).
func _refused(type: ProblemType, script: Variant = null) -> PackShelf:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture("res://tests/mods/tides")
	ModProblemShelf.add_files(shelf, type)
	if type == null:
		DirAccess.remove_absolute("%s/data/problems/problem_type_%02d.json" % [shelf.root, TYPE])
	if script != null:
		shelf.write_text("tides.sgd", script)
	shelf.mount()
	Mods.sync()
	return shelf


func test_a_mod_whose_type_is_missing_or_not_drawn_by_a_mod_is_refused_and_the_check_says_why() -> void:
	var wrong_family := ModProblemShelf.problem_type("items")
	var wrong_id := ModProblemShelf.problem_type()
	wrong_id.id = 41
	var no_records := ModProblemShelf.problem_type()
	no_records.records = []
	no_records.record_levels = PackedInt32Array()
	var cases := {
		"no type file": [null, "holds no"],
		"a type of another family": [wrong_family, "family must be \"mod\""],
		"a type that says another id": [wrong_id, "says its id is 41"],
		"a type with no records": [no_records, "no records"],
	}
	for what: String in cases:
		var shelf := _refused(cases[what][0])
		assert_array(Mods.loaded_ids()).override_failure_message("%s: the mod runs" % what).not_contains([String(shelf.id)])
		assert_str(ModHost.failure(String(shelf.id))).override_failure_message(what).contains(cases[what][1])
		assert_object(ModHost.problem_screen(TYPE)).is_null()
		assert_bool(_report(shelf).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains(cases[what][1]))).override_failure_message(what).is_true()
		ModProblemShelf.release(_shelves)


func test_a_mod_without_problem_frame_is_refused_and_a_picture_that_is_no_png_too() -> void:
	var shelf := _refused(ModProblemShelf.problem_type(), "var api = {}\nfunc mod_init(a):\n\tapi = a\n")
	assert_bool(_report(shelf).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("problem_frame"))).is_true()
	assert_str(ModHost.failure(String(shelf.id))).contains("problem_frame")
	assert_array(Mods.loaded_ids()).not_contains([String(shelf.id)])
	ModProblemShelf.release(_shelves)
	var broken := PackShelf.new()
	_shelves.append(broken)
	broken.add_mod_fixture("res://tests/mods/tides")
	ModProblemShelf.add_files(broken)
	broken.write_text("problems/broken.png", "not a picture")
	broken.mount()
	Mods.sync()
	assert_str(ModHost.failure(String(broken.id))).contains("problems/broken.png")


func test_a_good_problem_mod_passes_the_pack_check_and_its_shader_is_judged_as_a_skins_is() -> void:
	var good := _refused(ModProblemShelf.problem_type())
	assert_array(_report(good).errors()).is_empty()
	assert_array(Mods.loaded_ids()).contains([String(good.id)])
	ModProblemShelf.release(_shelves)
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture("res://tests/mods/tides")
	ModProblemShelf.add_files(shelf)
	shelf.write_text(ModProblemShelf.GLOW, "shader_type canvas_item;\nvoid fragment() { while (true) { } }")
	shelf.mount()
	Mods.sync()
	assert_str(ModHost.failure(String(shelf.id))).contains("no loops")
	assert_bool(_report(shelf).errors().any(func(f: PackReport.Finding) -> bool: return f.message.contains("no loops"))).is_true()


func test_the_manifest_form_and_the_docs_agree() -> void:
	var doc := FileAccess.get_file_as_string("res://../docs/create/CONTENT.md")
	for key in ["type", "level", "title", "prompt", "fields", "entry", "step", "window"]:
		assert_bool(doc.contains("`%s`" % key)).override_failure_message("CONTENT.md does not mention the key `%s` of the state of a problem screen" % key).is_true()
	for fact in ["types", "window", "max_commands", "max_texts", "max_text", "min_font_size", "max_font_size", "shaders"]:
		assert_bool(doc.contains("`%s`" % fact)).override_failure_message("CONTENT.md does not mention api[\"problems\"][\"%s\"]" % fact).is_true()
	assert_bool(doc.contains("`%s`" % ModProblems.FUNCTION)).is_true()
	assert_bool(doc.contains("`%s`" % ModProblems.FAMILY)).is_true()
	for step in ProblemState.STEPS:
		assert_bool(doc.contains("`%s`" % step)).override_failure_message("CONTENT.md does not name the step `%s`" % step).is_true()
