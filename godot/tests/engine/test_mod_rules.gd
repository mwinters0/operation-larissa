class_name TestModRules
extends GdUnitTestSuite
## Teaches: gameplay from a stranger's code that the game can still PROVE it controls. A mod pack adds rule hooks (a problem type's answer check, a creature instruction, a sub ability), a campaign DECLARES the mod (`Campaign.mods`),
## and the run resolves the declaration once into the table the rules consult (`ModHooks.resolve`, `RuleHooks`): so a campaign that does not declare it, the originals first, never calls it, a hook that raises, never returns or answers
## garbage has the default of the original's behaviour, and the same inputs are the same play. Here the real sandbox: the manifest, the pack check, the resolution, each hook end to end, the faults of a misbehaving mod, the
## hostile mod `tests/mods/rules_chaos`, a whole scripted visit played twice (and under every presenter), and what installing a mod pack asks (nothing).
## These tests need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`, docs/SETUP.md). The promises that need no extension are in `test_rule_hooks.gd`.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const PACK := ModRuleShelf.PACK
const TYPE := ModRuleShelf.TYPE

var _shelf: PackShelf


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func before_test() -> void:
	GameClock.paused = false
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	ModRuleShelf.release(_shelf)
	_shelf = null
	GameState.reset()


func _mount(fixture: String = "rules") -> PackShelf:
	_shelf = ModRuleShelf.mount(fixture)
	return _shelf


## The mod node, with a clean bill of health (a test that makes it fault leaves the count behind).
func _mod() -> Node:
	return ModHost.mod(String(PACK))


func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


## A run (a `GameState` of its own) of a new player of `campaign`, begun as the sign-in screen begins it.
func _run(campaign: StringName = ModRuleShelf.CAMPAIGN) -> Node:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.begin_run(ModRuleShelf.player(campaign))
	return run


## A sim on the sector of `campaign` flying (the launch over), with the run's table.
func _sim(run: Node, sector: int = ModRuleShelf.SECTOR) -> SimWorld:
	var sim := SimWorld.new(run)
	sim.foe_rng.seed = 5
	sim.begin_sector(sector)
	sim.end_launch()
	return sim


# --- the manifest ----------------------------------------------------------------------------------------------------

func test_a_rules_entry_makes_the_mod_add_hooks_under_the_lowest_instruction_limit() -> void:
	var parsed := _parse({"entry": "r.sgd", "requires_api": 4, "rules": {"answers": [41, 50], "instructions": [0, 3], "sub": true}})
	var spec: ModSpec = parsed[0]
	assert_array(parsed[1]).is_empty()
	assert_bool(spec.has_rules).is_true()
	assert_array(spec.rule_answers).is_equal([41, 50])
	assert_array(spec.rule_instructions).is_equal([0, 3])
	assert_bool(spec.rule_sub).is_true()
	assert_int(spec.limits["execution_timeout"]).is_equal(ModSpec.MAX_RULE_EXECUTION_TIMEOUT)         # (it asked for none: it got the lowest)
	assert_int(ModSpec.API_VERSION).is_greater_equal(ModSpec.RULE_API_VERSION)
	assert_dict(spec.to_dict()).is_equal({"entry": "r.sgd", "requires_api": 4, "rules": {"answers": [41, 50], "instructions": [0, 3], "sub": true}})
	# a limit asked for is cut to the ceiling of a mod with rule hooks, and 0 is raised to the lowest: counting cannot be turned off
	for asked in [0, 1, 5, 200, 100000]:
		var limited: ModSpec = _parse({"entry": "r.sgd", "requires_api": 4, "limits": {"execution_timeout": asked}, "rules": {"sub": true}})[0]
		assert_int(limited.limits["execution_timeout"]).override_failure_message("asked for %d" % asked).is_equal(1)
	# a mod that is a skin and has hooks takes the lowest of the two ceilings
	var both: ModSpec = _parse({"entry": "r.sgd", "requires_api": 4, "skin": {}, "rules": {"sub": true}})[0]
	assert_int(both.limits["execution_timeout"]).is_equal(1)
	assert_int(_parse({"entry": "r.sgd", "requires_api": 2, "skin": {}})[0].limits["execution_timeout"]).is_equal(ModSpec.MAX_DRAWING_EXECUTION_TIMEOUT)


func test_every_mistake_in_a_rules_entry_is_a_sentence() -> void:
	var cases := {
		"not an object": [{"entry": "r.sgd", "requires_api": 4, "rules": 3}, "\"rules\" must be an object"],
		"api too old": [{"entry": "r.sgd", "requires_api": 3, "rules": {"sub": true}}, "needs \"requires_api\": 4"],
		"default api": [{"entry": "r.sgd", "rules": {"sub": true}}, "needs \"requires_api\": 4"],
		"unknown key": [{"entry": "r.sgd", "requires_api": 4, "rules": {"sub": true, "oxygen": 1}}, "has no \"oxygen\""],
		"nothing": [{"entry": "r.sgd", "requires_api": 4, "rules": {}}, "defines nothing"],
		"sub false": [{"entry": "r.sgd", "requires_api": 4, "rules": {"sub": false}}, "defines nothing"],
		"sub text": [{"entry": "r.sgd", "requires_api": 4, "rules": {"sub": "yes"}}, "\"sub\" must be true or false"],
		"answers not a list": [{"entry": "r.sgd", "requires_api": 4, "rules": {"answers": 41}}, "\"answers\" must be a list"],
		"an original type": [{"entry": "r.sgd", "requires_api": 4, "rules": {"answers": [3]}}, "must be a whole number from 34"],
		"a type past the last": [{"entry": "r.sgd", "requires_api": 4, "rules": {"answers": [256]}}, "to 255"],
		"a fraction": [{"entry": "r.sgd", "requires_api": 4, "rules": {"answers": [41.5]}}, "must be a whole number"],
		"a type twice": [{"entry": "r.sgd", "requires_api": 4, "rules": {"answers": [41, 41]}}, "listed twice"],
		"too many types": [{"entry": "r.sgd", "requires_api": 4, "rules": {"answers": range(40, 40 + ModSpec.MAX_PROBLEM_TYPES + 1)}}, "at most"],
		"instructions not a list": [{"entry": "r.sgd", "requires_api": 4, "rules": {"instructions": "0"}}, "\"instructions\" must be a list"],
		"instruction out of range": [{"entry": "r.sgd", "requires_api": 4, "rules": {"instructions": [RuleHooks.MAX_INSTRUCTIONS]}}, "from 0 to 7"],
		"instruction negative": [{"entry": "r.sgd", "requires_api": 4, "rules": {"instructions": [-1]}}, "from 0 to 7"],
		"instruction twice": [{"entry": "r.sgd", "requires_api": 4, "rules": {"instructions": [1, 1]}}, "listed twice"],
	}
	for name: String in cases:
		var parsed := _parse(cases[name][0])
		assert_object(parsed[0]).override_failure_message(name).is_null()
		assert_bool(parsed[1].any(func(line: String) -> bool: return line.contains(cases[name][1]))).override_failure_message("%s: %s" % [name, parsed[1]]).is_true()
	# the older entries are as they were: a mod that asks for an older API runs, and a skin or problem screen needs no rules
	for old in [1, 2, 3]:
		assert_array(_parse({"entry": "old.sgd", "requires_api": old})[1]).is_empty()
	assert_array(_parse({"entry": "old.sgd", "requires_api": ModSpec.API_VERSION + 1})[1]).is_not_empty()


func test_the_api_a_mod_with_hooks_is_given_holds_plain_facts_and_nothing_else() -> void:
	_mount()
	var api: Dictionary = _mod().get("api")
	assert_int(api["api_version"]).is_equal(ModSpec.API_VERSION)
	assert_array(api.keys()).contains_exactly_in_any_order(["api_version", "id", "log", "load", "rules"])
	var facts: Dictionary = api["rules"]
	assert_array(facts["answers"]).is_equal([TYPE])
	assert_array(facts["instructions"]).is_equal([0, 1])
	assert_bool(facts["sub"]).is_true()
	assert_int(facts["max_calls_per_tick"]).is_equal(RuleHooks.MAX_CALLS_PER_TICK)
	for value: Variant in facts.values():
		assert_bool(value is int or value is bool or value is Array).is_true()                       # (numbers and lists of numbers: no object, no Callable)
	assert_bool(api.is_read_only()).is_true()


# --- the pack check and the loader -----------------------------------------------------------------------------------

func _report(shelf: PackShelf) -> PackReport:
	var options := PackCheck.Options.new()
	options.reach = false
	return PackCheck.run(Pack.open(shelf.root), options)


func _says(report: PackReport, severity: PackReport.Severity, fragment: String) -> bool:
	return report.findings.any(func(f: PackReport.Finding) -> bool: return f.severity == severity and f.message.contains(fragment))


func test_a_good_rules_mod_passes_the_check_and_its_campaigns_declare_what_is_there() -> void:
	var shelf := _mount()
	var report := _report(shelf)
	assert_bool(report.passes()).override_failure_message(report.text()).is_true()
	assert_array(report.warnings().filter(func(f: PackReport.Finding) -> bool: return not f.message.contains("no finale"))).override_failure_message(report.text()).is_empty()
	assert_array(Catalog.campaign(ModRuleShelf.CAMPAIGN).mods).is_equal([PACK])
	assert_array(Catalog.campaign(ModRuleShelf.BYSTANDER).mods).is_empty()
	assert_array(Catalog.campaign(ModRuleShelf.CAMPAIGN).problems()).is_empty()
	assert_str(ModHost.failure(String(PACK))).is_empty()


func test_the_check_names_a_missing_function_a_missing_type_and_an_undeclared_mod() -> void:
	var shelf := _mount()
	var source := FileAccess.get_file_as_string("%s/rules.sgd" % shelf.root)
	shelf.write_text("rules.sgd", source.replace("func sub_ability", "func sub_abilityy"))
	assert_bool(_says(_report(shelf), PackReport.Severity.ERROR, "defines no sub_ability(state)")).is_true()
	shelf.write_text("rules.sgd", source)
	DirAccess.remove_absolute("%s/data/problems/problem_type_%02d.json" % [shelf.root, TYPE])
	var report := _report(shelf)
	assert_bool(_says(report, PackReport.Severity.ERROR, "problem type %d: the pack holds no" % TYPE)).is_true()
	# a campaign that names a pack of the chain that is no mod with hooks
	var named := ModRuleShelf.campaign(&"names_nothing", 192, [&"no_such_mod"])
	shelf.add_campaign(named)
	shelf.add_sector_copy(DevCreatures.ARENA, 192)
	Packs.refresh()
	assert_bool(_says(_report(shelf), PackReport.Severity.WARNING, "mod 'no_such_mod' is no mod pack with rule hooks")).is_true()


func test_a_mod_that_lacks_a_function_it_lists_is_refused_with_the_reason() -> void:
	var shelf := PackShelf.new(PACK)
	shelf.add_mod_fixture("res://tests/mods/rules")
	var source := FileAccess.get_file_as_string("%s/rules.sgd" % shelf.root)
	shelf.write_text("rules.sgd", source.replace("func judge_answer", "func judge_it"))
	shelf.write_json("data/problems/problem_type_%02d.json" % TYPE, ResourceJson.new().data_of(ModRuleShelf.problem_type()))
	shelf.mount()
	Mods.sync()
	_shelf = shelf
	assert_object(_mod()).is_null()
	assert_str(ModHost.failure(String(PACK))).contains("judge_answer(state)")


# --- the declaration -------------------------------------------------------------------------------------------------

func test_a_campaign_declares_the_mod_and_its_run_resolves_the_table_once() -> void:
	_mount()
	var run := _run()
	var hooks: RuleHooks = run.hooks
	assert_bool(hooks.is_empty()).is_false()
	assert_array(hooks.declared).is_equal([PACK])
	assert_bool(hooks.campaign_id == ModRuleShelf.CAMPAIGN).is_true()
	assert_bool(hooks.has_instruction(0) and hooks.has_instruction(1) and not hooks.has_instruction(2)).is_true()
	assert_bool(hooks.judges(TYPE) and not hooks.judges(40)).is_true()
	assert_bool(hooks.has_sub_ability()).is_true()
	assert_dict(hooks.unresolved).is_empty()
	assert_array(hooks.mod_ids()).is_equal([PACK])
	assert_int(hooks.calls).is_equal(0)                                         # (resolving asks the mod nothing)
	assert_int(int(_mod().call("times_asked"))).is_equal(0)


func test_a_campaign_that_does_not_declare_the_mod_never_reaches_it() -> void:
	_mount()
	var run := _run(ModRuleShelf.BYSTANDER)                                      # (the mod is in the chain; the campaign declares none)
	assert_bool(run.hooks.is_empty()).is_true()
	assert_object(_mod()).is_not_null()
	assert_array(Mods.loaded_ids()).contains([String(PACK)])
	var sim := _sim(run, ModRuleShelf.BYSTANDER_SECTOR)
	for t in 20:
		sim.tick(InputSnapshot.firing(1))
	assert_int(run.hooks.calls).is_equal(0)
	assert_int(int(_mod().call("times_asked"))).is_equal(0)                      # (no hook of it was called, by anything)
	# the creature that would run the instruction is a creature with an unknown opcode, as in the original
	assert_str(sim.foes[ModRuleShelf.CREATURE].vm.fault).contains("unknown opcode")
	# and the answer to a problem of its type is the type's own
	GameState.begin_run(ModRuleShelf.player(ModRuleShelf.BYSTANDER))
	assert_object(GameState.hooks.judge_answer(ProblemFactory.make(TYPE, 0, null, 0), NumberValue.parse("6"))).is_null()
	assert_int(int(_mod().call("times_asked"))).is_equal(0)


func test_a_declared_mod_that_is_not_there_is_recorded_and_the_run_plays_on_without_it() -> void:
	_mount()
	var cases := {
		"absent": [&"no_such_mod", "no pack 'no_such_mod' is in the chain"],
		"a data pack": [&"dev", "no mod with rule hooks"],
	}
	for name: String in cases:
		var campaign := ModRuleShelf.campaign(&"x_%s" % name.replace(" ", "_"), 193, [cases[name][0]])
		var hooks := ModHooks.resolve(campaign)
		assert_bool(hooks.is_empty()).override_failure_message(name).is_true()
		assert_array(hooks.declared).is_equal([cases[name][0]])
		assert_str(hooks.unresolved.get(cases[name][0], "")).override_failure_message(name).contains(cases[name][1])
	# a mod pack of the chain with no rule hooks (a plain mod) is no hook either
	var plain := PackShelf.new(&"plain_mod_box", PACK)
	plain.add_mod_fixture("res://tests/mods/hello")
	plain.mount()
	Mods.sync()
	var hooks2 := ModHooks.resolve(ModRuleShelf.campaign(&"x_plain", 194, [&"plain_mod_box"]))
	assert_bool(hooks2.is_empty()).is_true()
	assert_str(hooks2.unresolved[&"plain_mod_box"]).contains("no mod with rule hooks")
	plain.remove()
	_shelf.mount()
	Mods.sync()
	# a mod listed twice is declared once
	var twice := ModHooks.resolve(ModRuleShelf.campaign(&"x_twice", 195, [PACK, PACK]))
	assert_array(twice.declared).is_equal([PACK])


func test_a_mod_that_loses_a_number_to_another_mod_is_told_so() -> void:
	_mount()
	var second := PackShelf.new(&"rules_box_2", PACK)
	second.add_mod_fixture("res://tests/mods/rules")
	second.write_json("data/problems/problem_type_%02d.json" % TYPE, ResourceJson.new().data_of(ModRuleShelf.problem_type()))
	second.mount()
	Mods.sync()
	var hooks := ModHooks.resolve(ModRuleShelf.campaign(&"x_two", 196, [PACK, &"rules_box_2"]))
	assert_array(hooks.declared).is_equal([PACK, &"rules_box_2"])
	assert_bool(hooks.judges(TYPE)).is_true()
	var notes: String = hooks.unresolved[&"rules_box_2"]
	assert_str(notes).contains("problem type %d is judged by another mod" % TYPE).contains("instruction 0 is defined by another mod").contains("the sub ability is another mod's")
	second.remove()
	_shelf.mount()
	Mods.sync()


func test_free_play_of_a_sector_takes_the_hooks_of_the_campaign_it_belongs_to() -> void:
	_mount()
	for sector in [ModRuleShelf.SECTOR, ModRuleShelf.BYSTANDER_SECTOR]:
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.reset()
		var flow := GameFlow.new(run, FakeSaveStore.new(), MessageQueue.new(StubClock.new()))
		flow.world = HeadlessStage.new(run)
		flow.view = FakeFlowView.new([], run)
		flow.enter(sector, 0)
		assert_bool(run.hooks.is_empty()).override_failure_message("sector %d" % sector).is_equal(sector == ModRuleShelf.BYSTANDER_SECTOR)
		flow.leave()
	# and a run of another sector, free play of a dev sector, has none even after a run that had them
	var run2 := _run()
	assert_bool(run2.hooks.is_empty()).is_false()
	run2.profile = null
	var flow2 := GameFlow.new(run2, FakeSaveStore.new(), MessageQueue.new(StubClock.new()))
	flow2.world = HeadlessStage.new(run2)
	flow2.view = FakeFlowView.new([], run2)
	flow2.enter(DevCreatures.ARENA, 0)
	assert_bool(run2.hooks.is_empty()).is_true()
	flow2.leave()


# --- the three hooks, end to end --------------------------------------------------------------------------------------

## The answer check: the mod says any positive multiple of the number is right; the type's data (one stored answer) says only the stored one is.
func test_a_mod_judges_the_answers_of_a_type_it_added_and_the_data_does_when_nobody_is_declared() -> void:
	_mount()
	GameState.begin_run(ModRuleShelf.player())
	var cases := {"3": true, "6": true, "9": true, "4": false, "0": false, "-3": false, "3.5": false}
	for typed: String in cases:
		var problem := ProblemFactory.make(TYPE, 0, null, 0)                  # (the stored answer is 3, the number is 3)
		var flow := ProblemFlow.new()
		flow.answer_judge = func(p: ProblemInstance, a: Variant) -> Variant: return GameState.hooks.judge_answer(p, a)
		flow.begin(problem)
		flow.submit_answer(NumberValue.parse(typed))
		assert_bool(flow.session.solved).override_failure_message("the mod on %s" % typed).is_equal(cases[typed])
	assert_int(GameState.hooks.calls).is_equal(cases.size())
	assert_int(GameState.hooks.fault_log.size()).is_equal(0)
	# the same problem for the same numbers, with the data alone judging: only the stored answer is right
	GameState.begin_run(ModRuleShelf.player(ModRuleShelf.BYSTANDER))
	var by_data := ProblemFlow.new()
	by_data.answer_judge = func(p: ProblemInstance, a: Variant) -> Variant: return GameState.hooks.judge_answer(p, a)
	by_data.begin(ProblemFactory.make(TYPE, 0, null, 0))
	by_data.submit_answer(NumberValue.parse("6"))
	assert_bool(by_data.session.solved).is_false()


func test_the_problem_screen_asks_the_runs_table_and_a_mods_verdict_is_all_it_changes() -> void:
	_mount()
	for declared in [true, false]:
		GameState.begin_run(ModRuleShelf.player(ModRuleShelf.CAMPAIGN if declared else ModRuleShelf.BYSTANDER))
		var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
		add_child(screen)
		var done: Array[String] = []
		screen.finished.connect(func(session: ProblemSession) -> void: done.append("solved %s misses %d" % [session.solved, session.misses]))
		screen.start(ProblemFactory.make(TYPE, 0, null, 1))                       # (the number is 5, the stored answer 5)
		var oxygen := GameState.oxygen()
		screen.submit_answer(NumberValue.parse("10"))
		if declared:
			assert_int(GameState.oxygen()).is_equal(oxygen)                      # (right at the first try: nothing lost)
			screen.advance_ticks(ProblemFlow.message_ticks())
			assert_array(done).is_equal(["solved true misses 0"])
		else:
			assert_int(GameState.oxygen()).is_equal(oxygen - 1)                  # (wrong: one oxygen, as for any wrong answer)
			assert_array(done).is_empty()
		screen.free()


func test_math_practice_is_of_no_campaign_and_the_types_data_judges() -> void:
	_mount()
	GameState.begin_run(ModRuleShelf.player())                                 # (a game was played before: its table is still the run's)
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	screen.practice = true
	add_child(screen)
	var done: Array[String] = []
	screen.finished.connect(func(session: ProblemSession) -> void: done.append("solved %s misses %d" % [session.solved, session.misses]))
	screen.start(ProblemFactory.make(TYPE, 0, null, 1))
	screen.submit_answer(NumberValue.parse("10"))                              # (a multiple of 5 that is not 5)
	assert_int(GameState.hooks.calls).is_equal(0)
	assert_int(int(_mod().call("times_asked"))).is_equal(0)
	screen.submit_answer(NumberValue.parse("5"))
	assert_int(GameState.hooks.calls).is_equal(0)
	screen.advance_ticks(ProblemFlow.message_ticks())
	screen.free()


## The creature instruction: the post runs `Mod_Instruction 0 3` and `Mod_Instruction 1 40` every tick; instruction 0 raises flag 3 the third time it runs.
func test_a_creature_instruction_is_run_by_the_mod_with_its_memory_in_the_game() -> void:
	_mount()
	var run := _run()
	var sim := _sim(run)
	var hooks: RuleHooks = run.hooks
	var post := sim.foes[ModRuleShelf.CREATURE].vm
	assert_str(post.fault).is_empty()
	var flag := 1 << ModRuleShelf.FLAG
	sim.tick(null)
	sim.tick(null)
	assert_int(sim.foe_context.semaphore & flag).is_equal(0)
	assert_dict(hooks.memory_of(PACK, RuleHooks.FUNCTION_INSTRUCTION)).is_equal({"visits": 2})
	sim.tick(null)
	assert_int(sim.foe_context.semaphore & flag).is_equal(flag)                    # (the third visit)
	sim.tick(null)
	assert_dict(hooks.memory_of(PACK, RuleHooks.FUNCTION_INSTRUCTION)).is_equal({"visits": 4})
	assert_str(post.fault).is_empty()
	assert_int(hooks.calls).is_equal(12)                                          # (four ticks of two instructions and the sub ability, which answers `{}` without fire)
	# a respawn is a fresh start: the memory, the flags and the tick start over
	sim.load_sector(ModRuleShelf.SECTOR)
	sim.end_launch()
	assert_dict(hooks.memory_of(PACK, RuleHooks.FUNCTION_INSTRUCTION)).is_empty()
	assert_int(sim.foe_context.semaphore & flag).is_equal(0)
	sim.tick(null)
	assert_dict(hooks.memory_of(PACK, RuleHooks.FUNCTION_INSTRUCTION)).is_equal({"visits": 1})


func test_the_condition_instruction_follows_what_the_mod_computes_from_the_snapshot() -> void:
	_mount()
	var run := _run()
	var sim := _sim(run)
	var post := sim.foes[ModRuleShelf.CREATURE].vm
	var closed := post.frame
	for t in 6:
		sim.tick(null)
		var near := absi(post.x - sim.sub.original_position().x) < 4 * 40
		# instruction 1 guards `Set_Frame clam_open_mid`: the picture changed to the open one exactly when the sub is near
		assert_bool(post.frame != closed).override_failure_message("tick %d (near %s, frame %d, closed %d)" % [t, near, post.frame, closed]).is_equal(near)


func test_the_sub_ability_dashes_on_the_mods_say_within_the_runs_limits() -> void:
	_mount()
	var run := _run()
	var sim := _sim(run)
	var top: int = run.tuning.sub.max_speed_x_units
	var hooks: RuleHooks = run.hooks
	sim.tick(InputSnapshot.steering(1, 0))                                         # (no fire: the mod answers {})
	assert_int(sim.sub.invulnerability).is_equal(0)
	assert_dict(hooks.memory_of(PACK, RuleHooks.FUNCTION_SUB)).is_empty()
	var dash := InputSnapshot.steering(-1, 0)
	dash.fire_presses = 1
	sim.tick(dash)
	assert_int(sim.sub.velocity_units.x).is_equal(-top)
	assert_int(sim.sub.invulnerability).is_equal(4)
	assert_dict(hooks.memory_of(PACK, RuleHooks.FUNCTION_SUB)).is_equal({"dashes": 1})
	sim.tick(InputSnapshot.steering(-1, 0))
	assert_int(sim.sub.invulnerability).is_equal(3)                                # (the game counts it down as any invulnerability)
	assert_int(sim.sub.velocity_units.x).is_greater_equal(-top)
	# the dash is a velocity: the walls and the screen's edge still apply to it
	for t in 40:
		sim.tick(dash)
	assert_int(sim.sub.original_position().x).is_greater_equal(-32)


func test_the_order_of_the_tick_is_the_originals_with_a_mod_in_it() -> void:
	_mount()
	var run := _run()
	var sim := _sim(run)
	sim.trace_ticks = true
	sim.tick(null)
	assert_array(sim.tick_trace).is_equal(SimWorld.TICK_ORDER)


# --- a mod that misbehaves --------------------------------------------------------------------------------------------

## The post runs the instructions for `ticks` ticks of a sim of the campaign, with the mod `chaos` in `mode`; returns what it did to the run.
func _chaos_run(mode: String, ticks: int = 30) -> Dictionary:
	_mount("rules_chaos")
	var mod := _mod()
	mod.call("set_mode", mode)
	var run := _run()
	var sim := _sim(run)
	var started := Time.get_ticks_msec()
	for t in ticks:
		var input := InputSnapshot.steering(1, 0)
		input.fire_presses = 1
		sim.tick(input)
	return {"run": run, "sim": sim, "ms": Time.get_ticks_msec() - started, "mod": mod}


func test_a_mod_that_raises_never_returns_or_answers_garbage_leaves_the_play_as_the_original_plays_it() -> void:
	# the baseline: the same sector played with a mod that answers nothing at all (`{}`) for both hooks of the tick
	var baseline := _chaos_run("good", 30)
	var plain_lines: Array[String] = []
	for line in _state_lines(baseline["sim"], baseline["run"], 30):
		plain_lines.append(line)
	assert_int(baseline["run"].hooks.fault_log.size()).is_equal(0)
	ModRuleShelf.release(_shelf)
	for mode in ["raise", "spin", "garbage", "nothing", "claims", "float", "oversize", "long_text"]:
		var played := _chaos_run(mode, 30)
		var hooks: RuleHooks = played["run"].hooks
		assert_array(_state_lines(played["sim"], played["run"], 30)).override_failure_message("mode %s changed the play" % mode).is_equal(plain_lines)
		assert_int(hooks.fault_log.size()).override_failure_message("mode %s: nothing was recorded" % mode).is_greater(0)
		assert_bool(hooks.is_switched_off(PACK)).override_failure_message("mode %s: the mod was not switched off" % mode).is_true()
		# it was asked MAX_FAULTS times (in the creatures' step and the sub's) and then never again in this load
		assert_int(hooks.calls).override_failure_message("mode %s" % mode).is_equal(RuleHooks.MAX_FAULTS)
		assert_int(played["ms"]).override_failure_message("mode %s took %d ms for 30 ticks" % [mode, played["ms"]]).is_less(8000)
		Mods.loader().forgive(String(PACK))
		ModRuleShelf.release(_shelf)


## The rules' state for a few ticks, for comparing two plays: the sub and the creatures after `ticks` ticks.
func _state_lines(sim: SimWorld, run: Node, ticks: int) -> Array[String]:
	return [SimTrace.state_line(sim, run, ticks)]


func test_a_mod_that_never_returns_costs_a_tick_a_little_and_no_more() -> void:
	_mount("rules_chaos")
	var mod := _mod()
	mod.call("set_mode", "spin")
	assert_int(mod.get("execution_timeout")).is_equal(1)                                       # (it asked for 100000 million: it got the lowest)
	var timeouts := int(mod.get("monitor_execution_timeouts"))
	var run := _run()
	var sim := _sim(run)
	var started := Time.get_ticks_msec()
	sim.tick(null)
	var one_tick := Time.get_ticks_msec() - started
	assert_int(int(mod.get("monitor_execution_timeouts"))).is_greater(timeouts)
	# a tick makes at most the calls of a tick, whatever they cost, and a mod that times out is switched off after MAX_FAULTS of them
	assert_int(one_tick).override_failure_message("a tick of a mod that never returns took %d ms" % one_tick).is_less(4000)
	assert_str(run.hooks.fault_log[0]).contains("instruction limit")
	for t in 6:
		sim.tick(null)
	assert_bool(run.hooks.is_switched_off(PACK)).is_true()
	started = Time.get_ticks_msec()
	sim.tick(null)
	assert_int(Time.get_ticks_msec() - started).override_failure_message("a tick after the mod was switched off took %d ms" % (Time.get_ticks_msec() - started)).is_less(500)
	Mods.loader().forgive(String(PACK))


func test_what_a_mod_asks_beyond_the_bounds_is_cut_to_them_and_garbage_is_a_fault() -> void:
	var played := _chaos_run("wild", 3)
	var run: Node = played["run"]
	var sim: SimWorld = played["sim"]
	var tuning: SubTuning = run.tuning.sub
	# the sub ability asked for 99999 and 99999 ticks of invulnerability, the instruction for a move of 1000 steps and flags above the 16
	assert_int(sim.sub.velocity_units.x).is_between(-tuning.max_speed_x_units, tuning.max_speed_x_units)
	assert_int(sim.sub.velocity_units.y).is_between(-tuning.max_speed_y_units, tuning.max_speed_y_units)
	assert_int(sim.sub.invulnerability).is_less_equal(tuning.invulnerability_ticks)
	assert_int(sim.foe_context.semaphore).is_between(0, RuleHooks.FLAG_MASK)
	var post := sim.foes[ModRuleShelf.CREATURE].vm
	assert_str(post.fault).is_empty()
	assert_int(absi(post.x - sim.sector.foes[ModRuleShelf.CREATURE].pos.x)).is_less_equal(RuleHooks.MAX_MOVE * 2 * 3)      # (a move of at most 16 steps of 2 pixels, once in each of the 3 ticks)
	assert_array(run.hooks.fault_log).is_empty()                                          # (cutting is not a fault)
	# the judge may answer only true or false
	GameState.begin_run(ModRuleShelf.player())
	assert_object(GameState.hooks.judge_answer(ProblemFactory.make(TYPE, 0, null, 0), NumberValue.parse("3"))).is_null()
	assert_int(GameState.hooks.fault_log.size()).is_equal(1)
	Mods.loader().forgive(String(PACK))


func test_a_hook_that_depends_on_how_often_it_was_asked_is_caught_when_purity_is_checked() -> void:
	_mount("rules_chaos")
	var mod := _mod()
	mod.call("set_mode", "impure")
	var run := _run()
	run.hooks.verify_pure = true
	var sim := _sim(run)
	for t in 4:
		sim.tick(null)
	assert_bool(run.hooks.fault_log.any(func(line: String) -> bool: return line.contains("differently"))).is_true()
	Mods.loader().forgive(String(PACK))


func test_a_faulting_hook_is_recorded_for_the_creator_and_the_player_of_the_run_plays_on() -> void:
	var played := _chaos_run("raise", 6)
	var hooks: RuleHooks = played["run"].hooks
	assert_str(hooks.fault_log[0]).contains(String(PACK)).contains("raised an error")
	assert_bool(hooks.fault_log.size() <= RuleHooks.MAX_LOG).is_true()
	assert_bool(played["sim"].sub.active and played["sim"].sub.controlled).is_true()
	Mods.loader().forgive(String(PACK))


func test_a_hostile_rules_mod_reaches_nothing_of_the_game() -> void:
	_mount("rules_chaos")
	var mod := _mod()
	var run := _run()
	var sim := _sim(run)
	var state := HookState.sub(sim.sub, InputSnapshot.new(), ModRuleShelf.SECTOR, 0, 0)
	state["memory"] = {"visits": 1}
	ModLoader.freeze(state)
	var before := {"root": get_tree().root.get_children().map(func(c: Node) -> String: return c.name), "oxygen": run.oxygen(), "chain": Packs.chain_ids(), "mods": Mods.loaded_ids(),
			"state": state.duplicate(true), "calls": run.hooks.calls, "mem": run.hooks.memory_of(PACK, RuleHooks.FUNCTION_INSTRUCTION), "sub": sim.sub.original_position()}
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
	assert_int(run.oxygen()).is_equal(before["oxygen"])
	assert_array(Packs.chain_ids()).is_equal(before["chain"])
	assert_array(Mods.loaded_ids()).is_equal(before["mods"])
	assert_int(run.hooks.calls).is_equal(before["calls"])
	assert_dict(run.hooks.memory_of(PACK, RuleHooks.FUNCTION_INSTRUCTION)).is_equal(before["mem"])
	assert_that(sim.sub.original_position()).is_equal(before["sub"])
	for name in ["check_load_a_file_of_another_pack"]:
		var faults2 := int(mod.get("monitor_exceptions"))
		assert_object(mod.call(name)).override_failure_message(name).is_null()
		assert_int(int(mod.get("monitor_exceptions"))).is_equal(faults2)
	Mods.loader().forgive(String(PACK))


# --- the same inputs, the same play ------------------------------------------------------------------------------------

func _visit(shell_run: Node, sector: int, player: PlayerProfile) -> SectorScenario:
	var scenario := SectorScenario.new(HeadlessStage.new(shell_run), shell_run)
	scenario.play(sector, player)
	return scenario


## A whole scripted visit (the launch, a flight with the creatures awake, a problem, a lost tank and its dissolve with the respawn, the dock, the balloon and the reload of the creatures) of the campaign's
## sector, played twice from the same inputs: every event and every tick's state are the same. The mod's hooks ran in it (the trace shows the flag and the dash), across the respawn and the reload.
func test_a_whole_visit_with_a_mod_is_the_same_play_every_time() -> void:
	_mount()
	var traces: Array = []
	var asked: Array[int] = []
	for round in 2:
		var player := ModRuleShelf.player()
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.begin_run(player)
		var scenario := _visit(run, ModRuleShelf.SECTOR, player)
		traces.append(scenario.trace.lines)
		asked.append(run.hooks.calls)
		assert_array(run.hooks.fault_log).is_empty()
	assert_int(traces[0].size()).is_greater(100)
	assert_array(traces[1]).is_equal(traces[0])
	assert_int(asked[0]).is_greater(100)
	assert_int(asked[1]).is_equal(asked[0])
	var text := "\n".join(traces[0])
	var flagged: Array = traces[0].filter(func(line: String) -> bool: return line.contains(" sem=") and (int(line.split(" sem=")[1].split(" ")[0]) & (1 << ModRuleShelf.FLAG)) != 0)
	assert_int(flagged.size()).is_greater(10)                                     # (the flag the mod raised, in several loads)
	assert_str(text).contains("inv=4 ")                                           # (a dash)
	assert_int(traces[0].filter(func(line: String) -> bool: return line.contains("dissolve_started")).size()).is_greater(0)     # (the respawn the memory started over in)
	assert_int(traces[0].filter(func(line: String) -> bool: return line.begins_with("T") and line.contains("sector_loaded")).size()).is_greater(1)


func test_the_visit_is_the_same_with_the_mod_and_the_pack_in_another_order_and_after_a_visit_that_failed() -> void:
	_mount()
	var lines: Array = []
	for bad_first in [false, true]:
		if bad_first:                                                              # a visit of a campaign that declares none, in the same process, before: nothing of it may remain
			var other := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
			var bystander := ModRuleShelf.player(ModRuleShelf.BYSTANDER)
			other.begin_run(bystander)
			_visit(other, ModRuleShelf.BYSTANDER_SECTOR, bystander)
		var player := ModRuleShelf.player()
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.begin_run(player)
		lines.append(_visit(run, ModRuleShelf.SECTOR, player).trace.lines)
	assert_array(lines[1]).is_equal(lines[0])


func test_a_respawn_and_a_reload_derive_the_hooks_state_like_a_first_load() -> void:
	_mount()
	var run := _run()
	var fresh := _sim(run)
	fresh.tick(InputSnapshot.steering(1, 0))
	fresh.tick(InputSnapshot.steering(1, 0))
	var first := SimTrace.state_line(fresh, run, 0)
	var first_memory: Dictionary = run.hooks.memory_of(PACK, RuleHooks.FUNCTION_INSTRUCTION)
	# the same sector loaded again in the same sim (a respawn) and played the same: the same state
	fresh.begin_sector(ModRuleShelf.SECTOR)
	fresh.end_launch()
	fresh.foe_rng.seed = 5
	fresh.tick(InputSnapshot.steering(1, 0))
	fresh.tick(InputSnapshot.steering(1, 0))
	assert_dict(run.hooks.memory_of(PACK, RuleHooks.FUNCTION_INSTRUCTION)).is_equal(first_memory)
	assert_str(SimTrace.state_line(fresh, run, 0)).is_equal(first)
	# the reload of the creatures at the dock starts the memory over too
	fresh.reload_creatures()
	assert_dict(run.hooks.memory_of(PACK, RuleHooks.FUNCTION_INSTRUCTION)).is_empty()
	assert_int(run.hooks.tick()).is_equal(-1)
	# a second sim on the same run (a new scene) reads the same table
	var again := SimWorld.new(run)
	again.load_sector(ModRuleShelf.SECTOR)
	assert_object(again.foe_context.hooks).is_same(run.hooks)


## The mod, the presenter and the skin: nothing a presenter or a skin is made of names the table, so a skin that draws (or scribbles) cannot reach a hook. Played with every presenter and skin in `test_plays_identically.gd`.
func test_no_presenter_and_no_skin_names_the_rule_hooks() -> void:
	var files: Array[String] = []
	for folder in ["res://src/gameplay", "res://src/skins"]:
		files.append_array(SourceScan.scripts_under(folder))
	for name in ["mod_presenter", "mod_skin", "skin_state", "mod_layer", "mod_draw"]:
		files.append("res://src/mods/%s.gd" % name)
	assert_int(files.size()).is_greater(10)
	assert_array(SourceScan.find_in(files, ["RuleHooks", "ModHooks", "HookState"])).is_empty()


# --- installing a mod pack ---------------------------------------------------------------------------------------------

## A mod pack is installed like any pack and the game asks nothing: no confirmation, no trust dialog, no warning on the pack screen, because everything it can do is bounded by the sandbox, the limits and the hook table.
func test_installing_a_mod_pack_asks_no_trust_question() -> void:
	const SOURCE := "user://test_mod_rules_stranger"
	const ID := &"mod_rules"
	PackFiles.remove_tree(SOURCE)
	PackFiles.remove_tree("%s/%s" % [PackInstall.DIR, ID])             # (a run that failed half way leaves nothing behind)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/mods/rules/pack.json"))
	manifest["base"] = String(PackShelf.base_id())
	PackFiles.write_text(SOURCE + "/pack.json", JSON.stringify(manifest))
	PackFiles.write_text(SOURCE + "/rules.sgd", FileAccess.get_file_as_string("res://tests/mods/rules/rules.sgd"))
	PackFiles.write_text(SOURCE + "/data/problems/problem_type_%02d.json" % TYPE, JSON.stringify(ResourceJson.new().data_of(ModRuleShelf.problem_type())))
	var dialog: PackDialog = load("res://src/ui/pack_dialog.tscn").instantiate()
	add_child(dialog)
	var before := dialog.entry_count()
	dialog.install_from(SOURCE)
	assert_int(dialog.entry_count()).override_failure_message(dialog.details.text).is_equal(before + 1)
	assert_str(dialog.selected_id()).is_equal(ID)
	assert_str(dialog.details.text).contains("installed 'mod_rules'")
	for word in ["trust", "allow", "permission", "confirm", "sure"]:
		assert_bool(dialog.details.text.to_lower().contains(word)).override_failure_message("the pack screen says '%s'" % word).is_false()
	# no question was asked: no dialog of any kind is open on the screen, over it or in the tree
	assert_array(dialog.find_children("*", "Window", true, false).filter(func(node: Node) -> bool: return (node as Window).visible)).is_empty()
	assert_array(get_tree().root.find_children("*", "AcceptDialog", true, false).filter(func(node: Node) -> bool: return (node as Window).visible)).is_empty()
	# it is data to the game (not trusted: read as plain files), and installing chose and ran nothing
	assert_bool(Packs.in_chain(ID)).is_false()
	var pack := Pack.open("%s/%s" % [PackInstall.DIR, ID])
	assert_bool(pack.trusted).is_false()
	assert_array(pack.errors).is_empty()
	assert_object(ModHost.mod(String(ID))).is_null()
	# choosing it runs its mod, in the sandbox, with no question either
	Packs.choose(ID)
	Mods.sync()
	assert_object(ModHost.mod(String(ID))).override_failure_message(ModHost.failure(String(ID))).is_not_null()
	assert_bool(Packs.in_chain(ID)).is_true()
	# taken away again
	dialog.free()
	assert_str(PackInstall.uninstall(ID)).is_empty()
	PackFiles.remove_tree(SOURCE)
	Packs.start()
	Mods.sync()
