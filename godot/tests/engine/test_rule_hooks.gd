class_name TestRuleHooks
extends GdUnitTestSuite
## Teaches: a rule that can be extended and still be proved unchanged. The rules hold one plain table (`RuleHooks`) whose only way to a mod is a `Callable`, so these tests stand a scripted double where the sandbox would
## be and check everything the GAME promises on its side of it: what is validated and cut, the defaults of a fault, the bounded memory, the budget of a tick, the mod that is switched off, a load that starts over,
## the creature instruction in the VM, the sub ability in the tick, the verdict on an answer, and that a run with no hooks (every original campaign, free play, the tools) asks nobody anything.
## (The same promises with a real sandboxed mod, a hostile one included, are in `test_mod_rules.gd`; these tests need no extension.)

const Op := FoeOps.Op
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const MOD := &"fake_mod"

## What the double was asked: [mod, function, the state it was given].
var _asked: Array = []


func before_test() -> void:
	_asked = []
	GameState.reset()


func after_test() -> void:
	GameState.reset()


# --- the double ---------------------------------------------------------------------------------------------

static func _ok(value: Variant) -> Dictionary:
	return {"ok": true, "value": value}


static func _failed(why: String = "it raised an error") -> Dictionary:
	return {"ok": false, "why": why}


## A table whose mod `MOD` defines instructions 0 and 1, judges type 41 and has the sub ability, answered by `reply(function, state) -> Dictionary`.
func _table(reply: Callable) -> RuleHooks:
	var hooks := RuleHooks.none()
	assert_bool(hooks.claim_instruction(0, MOD)).is_true()
	assert_bool(hooks.claim_instruction(1, MOD)).is_true()
	assert_bool(hooks.claim_judge(41, MOD)).is_true()
	assert_bool(hooks.claim_sub(MOD)).is_true()
	hooks.declared = [MOD]
	hooks.set_caller(func(mod_id: StringName, function: String, state: Dictionary) -> Dictionary:
		_asked.append([mod_id, function, state.duplicate(true)])
		return reply.call(function, state))
	hooks.begin_load()
	return hooks


func _vm(bytes: Array) -> FoeVM:
	var data := FoeData.new()
	data.frame_min = 0
	data.frame_max = 255
	data.pos = Vector2i(100, 50)
	var vm := FoeVM.new()
	vm.setup(data, PackedByteArray(bytes), 0)
	return vm


func _ctx(hooks: RuleHooks = null, vms: Array[FoeVM] = []) -> FoeVM.Context:
	var ctx := FoeVM.Context.new()
	ctx.foes = vms
	ctx.rng.seed = 1
	ctx.hooks = hooks
	return ctx


func _problem(record: int = 0) -> ProblemInstance:
	return ProblemInstance.build(ModRuleShelf.problem_type(), 0, record)


# --- the empty table ----------------------------------------------------------------------------------------

func test_the_empty_table_defines_nothing_and_answers_everything_at_once() -> void:
	var hooks := RuleHooks.none()
	hooks.set_caller(func(_mod: StringName, _function: String, _state: Dictionary) -> Dictionary:
		_asked.append("asked")
		return _ok(true))
	assert_bool(hooks.is_empty()).is_true()
	assert_bool(hooks.runs_instructions()).is_false()
	assert_bool(hooks.has_instruction(0)).is_false()
	assert_bool(hooks.judges(41)).is_false()
	assert_bool(hooks.has_sub_ability()).is_false()
	assert_array(hooks.mod_ids()).is_empty()
	assert_object(hooks.judge_answer(_problem(), NumberValue.parse("3"))).is_null()
	assert_dict(hooks.creature_instruction(0, 0, _vm([Op.YIELD]), _ctx(hooks))).is_empty()
	assert_dict(hooks.sub_ability(SubModel.new(Tuning.original().sub), InputSnapshot.new(), 0, 0)).is_empty()
	assert_array(_asked).is_empty()
	assert_int(hooks.calls).is_equal(0)


func test_a_run_has_the_empty_table_until_a_campaign_declares_a_mod() -> void:
	assert_bool(GameState.hooks.is_empty()).is_true()
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	assert_bool(run.hooks.is_empty()).is_true()
	run.begin_run(PlayerProfile.new_player_in("Test", Catalog.default_campaign()))
	assert_bool(run.hooks.is_empty()).is_true()
	assert_bool(run.hooks.campaign_id == &"").is_true()


func test_the_original_and_dev_campaigns_declare_no_mod_and_their_runs_resolve_the_empty_table() -> void:
	assert_array(Catalog.campaigns()).is_not_empty()
	for campaign in Catalog.campaigns():
		assert_array(campaign.mods).override_failure_message("campaign '%s' declares a mod" % campaign.id).is_empty()
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.begin_run(PlayerProfile.new_player_in("Test", campaign))
		assert_bool(run.hooks.is_empty()).override_failure_message("a run of '%s' has a hook" % campaign.id).is_true()
		assert_array(run.hooks.declared).is_empty()
		assert_dict(run.hooks.unresolved).is_empty()


## The strongest form of "the originals run none": a whole scripted visit of a sector, as a player of a campaign that declares no mod, with the table's way to a mod wired to a counter. Nothing is claimed, so nobody may call it.
func test_a_whole_visit_of_a_sector_makes_no_hook_call() -> void:
	for sector in [DevCreatures.ARENA, DevCreatures.CLOSING, 3]:
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		var player := PlayerProfile.new_player_in("Test", Catalog.default_campaign())
		player.progress = sector * 2
		run.begin_run(player)
		var counted := [0]
		run.hooks.set_caller(func(_mod: StringName, _function: String, _state: Dictionary) -> Dictionary:
			counted[0] += 1
			return _ok(true))
		var scenario := SectorScenario.new(HeadlessStage.new(run), run)
		scenario.play(sector, player)
		assert_int(scenario.trace.lines.size()).is_greater(100)
		assert_int(counted[0]).override_failure_message("sector %d: a mod was asked" % sector).is_equal(0)
		assert_int(run.hooks.calls).is_equal(0)
		assert_array(run.hooks.fault_log).is_empty()


# --- claims -------------------------------------------------------------------------------------------------

func test_a_number_a_type_and_the_ability_have_one_owner() -> void:
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({}))
	assert_bool(hooks.claim_instruction(0, &"other")).is_false()
	assert_bool(hooks.claim_judge(41, &"other")).is_false()
	assert_bool(hooks.claim_sub(&"other")).is_false()
	assert_bool(hooks.claim_instruction(RuleHooks.MAX_INSTRUCTIONS, &"other")).is_false()
	assert_bool(hooks.claim_instruction(-1, &"other")).is_false()
	assert_bool(hooks.claim_instruction(2, &"other")).is_true()
	assert_bool(hooks.is_empty()).is_false()
	assert_array(hooks.mod_ids()).is_equal([MOD])


# --- what a mod may answer --------------------------------------------------------------------------------------

func test_an_instruction_answer_is_validated_and_cut_to_its_bounds() -> void:
	var cases := {
		"{}": [{}, {}],
		"every key": [{"condition": false, "end_turn": true, "set_flags": 5, "clear_flags": 2, "frame": 130, "dx": 3, "dy": -4, "memory": {"a": 1}},
				{"condition": false, "end_turn": true, "set_flags": 5, "clear_flags": 2, "frame": 130, "dx": 3, "dy": -4, "memory": {"a": 1}}],
		"cut": [{"set_flags": 70000, "clear_flags": -5, "frame": 1000, "dx": 1000, "dy": -1000}, {"set_flags": 65535, "clear_flags": 0, "frame": 255, "dx": 16, "dy": -16}],
	}
	for name: String in cases:
		assert_dict(RuleHooks.validate_instruction(cases[name][0])).override_failure_message(name).is_equal(cases[name][1])
	for garbage: Variant in [null, 12, "yes", [1], {"oxygen": 99}, {"condition": 1}, {"end_turn": "yes"}, {"set_flags": 1.5}, {"frame": "3"}, {"dx": 1.0},
			{"memory": 5}, {"memory": {"a": {}}}, {1: 2}, {"condition": true, "oxygen": 1}]:
		assert_object(RuleHooks.validate_instruction(garbage)).override_failure_message("accepted %s" % str(garbage)).is_null()


func test_an_answer_with_more_keys_than_any_hook_has_is_garbage_unread() -> void:
	var many := {}
	for i in RuleHooks.MAX_ANSWER_KEYS + 1:
		many["k%d" % i] = i
	assert_object(RuleHooks.validate_instruction(many)).is_null()
	assert_object(RuleHooks.validate_sub(many, Vector2i(10, 10), 5)).is_null()


func test_a_sub_answer_is_cut_to_the_runs_limits() -> void:
	var limit := Vector2i(100, 60)
	assert_dict(RuleHooks.validate_sub({}, limit, 30)).is_empty()
	assert_dict(RuleHooks.validate_sub({"vx": 99999, "vy": -99999, "invulnerability": 99999}, limit, 30)).is_equal({"vx": 100, "vy": -60, "invulnerability": 30})
	assert_dict(RuleHooks.validate_sub({"vx": -5, "invulnerability": -3}, limit, 30)).is_equal({"vx": -5, "invulnerability": 0})
	for garbage: Variant in [null, "fast", {"vx": 1.5}, {"vx": "1"}, {"speed": 1}, {"dx": 1}, {"invulnerability": true}, {"memory": []}]:
		assert_object(RuleHooks.validate_sub(garbage, limit, 30)).override_failure_message("accepted %s" % str(garbage)).is_null()


func test_a_memory_is_a_small_dictionary_of_plain_values() -> void:
	var good := {"count": 3, "ratio": 0.5, "on": true, "name": "x", "list": [1, 2.5, "a", false]}
	assert_dict(RuleHooks.validate_memory(good)).is_equal(good)
	assert_dict(RuleHooks.validate_memory({})).is_empty()
	var many := {}
	for i in RuleHooks.MAX_MEMORY_KEYS:
		many["k%d" % i] = i
	assert_dict(RuleHooks.validate_memory(many)).is_equal(many)
	many["one more"] = 1
	assert_object(RuleHooks.validate_memory(many)).is_null()
	assert_object(RuleHooks.validate_memory({"x".repeat(RuleHooks.MAX_MEMORY_KEY + 1): 1})).is_null()
	assert_object(RuleHooks.validate_memory({"t": "x".repeat(RuleHooks.MAX_MEMORY_TEXT + 1)})).is_null()
	assert_dict(RuleHooks.validate_memory({"t": "x".repeat(RuleHooks.MAX_MEMORY_TEXT)})).is_not_empty()
	var items: Array = []
	items.resize(RuleHooks.MAX_MEMORY_ITEMS + 1)
	items.fill(1)
	assert_object(RuleHooks.validate_memory({"l": items})).is_null()
	for garbage: Variant in [null, 3, "x", [1], {"a": {"b": 1}}, {"a": [[1]]}, {"a": Vector2.ZERO}, {"a": NAN}, {"a": INF}, {1: 2}, {"a": null}, {"a": Callable()}]:
		assert_object(RuleHooks.validate_memory(garbage)).override_failure_message("accepted %s" % str(garbage)).is_null()
	var copy: Variant = RuleHooks.validate_memory(good)
	assert_bool(is_same(copy, good)).is_false()                        # (the game keeps a copy of its own, not the mod's object)


# --- the three hooks, through the table ---------------------------------------------------------------------------

func test_a_creature_instruction_is_told_the_creature_and_gets_its_memory_back() -> void:
	var hooks := _table(func(_f: String, state: Dictionary) -> Dictionary:
		var seen: int = state["memory"].get("seen", 0)
		return _ok({"set_flags": 4, "memory": {"seen": seen + 1}}))
	var vm := _vm([Op.YIELD])
	vm.index = 7
	vm.screen = 3
	vm.frame = 9
	var ctx := _ctx(hooks, [])
	ctx.sub_x = 40
	ctx.sub_y = 60
	ctx.semaphore = 0b101
	ctx.current_screen = 3
	hooks.begin_tick()
	assert_dict(hooks.creature_instruction(1, 200, vm, ctx)).is_equal({"set_flags": 4})
	var state: Dictionary = _asked[0][2]
	assert_str(_asked[0][1]).is_equal(RuleHooks.FUNCTION_INSTRUCTION)
	assert_dict(state).is_equal({"number": 1, "value": 200, "tick": 0, "creature": 7, "position": Vector2i(100, 50), "frame": 9, "mirrored": false, "screen": 3,
			"shown_screen": 3, "sub": Vector2i(40, 60), "flags": 5, "memory": {}})
	hooks.begin_tick()
	hooks.creature_instruction(1, 200, vm, ctx)
	assert_dict(_asked[1][2]["memory"]).is_equal({"seen": 1})          # (what it answered last time is what it is told now)
	assert_int(_asked[1][2]["tick"]).is_equal(1)
	assert_dict(hooks.memory_of(MOD, RuleHooks.FUNCTION_INSTRUCTION)).is_equal({"seen": 2})
	assert_int(hooks.calls).is_equal(2)


func test_a_number_nobody_defines_is_no_call_and_no_effect() -> void:
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({"end_turn": true}))
	hooks.begin_tick()
	assert_dict(hooks.creature_instruction(5, 0, _vm([Op.YIELD]), _ctx(hooks))).is_empty()
	assert_array(_asked).is_empty()


func test_a_sub_ability_is_told_where_the_sub_is_and_what_the_player_does() -> void:
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({"vx": 7}))
	var model := SubModel.new(Tuning.original().sub)
	model.place_original(100, 120, 6)
	model.velocity_units = Vector2i(3, -4)
	model.invulnerability = 2
	var input := InputSnapshot.new()
	input.steer = Vector2i(1, -1)
	input.fire_presses = 2
	hooks.begin_tick()
	assert_dict(hooks.sub_ability(model, input, 5, 2)).is_equal({"vx": 7})
	var state: Dictionary = _asked[0][2]
	var tuning := Tuning.original().sub
	assert_dict(state).is_equal({"tick": 0, "sector": 5, "screen": 2, "position": Vector2i(100, 120), "velocity": Vector2i(3, -4), "cell": 6, "invulnerability": 2,
			"steer": Vector2i(1, -1), "fire": 2, "max_velocity": Vector2i(tuning.max_speed_x_units, tuning.max_speed_y_units), "max_invulnerability": tuning.invulnerability_ticks, "memory": {}})


func test_the_verdict_on_an_answer_is_true_false_or_nobodys() -> void:
	var verdict: Array = [true]
	var hooks := _table(func(function: String, _s: Dictionary) -> Dictionary:
		assert_str(function).is_equal(RuleHooks.FUNCTION_JUDGE)
		return _ok(verdict[0]))
	assert_bool(hooks.judge_answer(_problem(), NumberValue.parse("99"))).is_true()
	verdict[0] = false
	assert_bool(hooks.judge_answer(_problem(), NumberValue.parse("3"))).is_false()
	var state: Dictionary = _asked[0][2]
	assert_dict(state).is_equal({"type": 41, "level": 0, "fields": [3, {"text": "3", "value": 3.0, "fraction": false}], "typed": {"text": "99", "value": 99.0, "fraction": false}})
	assert_bool(state.has("memory")).is_false()                      # (an answer is judged from the problem and the answer alone)
	for garbage: Variant in ["yes", 1, null, {}, [true]]:
		verdict[0] = garbage
		assert_object(hooks.judge_answer(_problem(), NumberValue.parse("3"))).override_failure_message("took %s as a verdict" % str(garbage)).is_null()
	assert_int(hooks.fault_log.size()).is_equal(5)


func test_an_answer_is_judged_only_for_a_type_a_mod_claimed_and_a_typed_number() -> void:
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok(true))
	var other := ProblemKit.type_of("exact", "cn", 1, [ProblemKit.flat([3, ProblemKit.decimal(3.0, 0)])])
	other.id = 40
	other.texts = PackedStringArray(ModRuleShelf.WORDS)
	other.diagram = {"family": "items", "items": []}
	assert_object(hooks.judge_answer(ProblemInstance.build(other, 0, 0), NumberValue.parse("3"))).is_null()
	assert_object(hooks.judge_answer(_problem(), 12)).is_null()                  # (a ballast mask is no typed number)
	assert_array(_asked).is_empty()


# --- faults: the default, the record, the budget, the switch ----------------------------------------------------------------

func test_a_fault_has_the_default_is_recorded_and_costs_the_mod_its_place_after_enough_of_them() -> void:
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _failed("it ran past its instruction limit"))
	var heard: Array[String] = []
	hooks.faulted.connect(func(mod_id: StringName, function: String, why: String) -> void: heard.append("%s %s %s" % [mod_id, function, why]))
	var vm := _vm([Op.YIELD])
	var ctx := _ctx(hooks)
	hooks.begin_tick()
	for i in RuleHooks.MAX_FAULTS:
		assert_dict(hooks.creature_instruction(0, 0, vm, ctx)).is_empty()
	assert_int(hooks.calls).is_equal(RuleHooks.MAX_FAULTS)
	assert_bool(hooks.is_switched_off(MOD)).is_true()
	assert_int(heard.size()).is_equal(RuleHooks.MAX_FAULTS)
	assert_str(heard[0]).is_equal("fake_mod creature_instruction it ran past its instruction limit")
	assert_str(hooks.fault_log[0]).contains("fake_mod").contains("it ran past its instruction limit")
	# switched off: not asked again, in any tick, by any hook of the tick
	hooks.begin_tick()
	assert_dict(hooks.creature_instruction(0, 0, vm, ctx)).is_empty()
	assert_dict(hooks.sub_ability(SubModel.new(Tuning.original().sub), InputSnapshot.new(), 0, 0)).is_empty()
	assert_int(hooks.calls).is_equal(RuleHooks.MAX_FAULTS)
	# ...until the creatures are made again: a load is a fresh start
	hooks.begin_load()
	assert_bool(hooks.is_switched_off(MOD)).is_false()
	hooks.begin_tick()
	hooks.creature_instruction(0, 0, vm, ctx)
	assert_int(hooks.calls).is_equal(RuleHooks.MAX_FAULTS + 1)


func test_garbage_is_a_fault_with_the_default_too() -> void:
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({"oxygen": 99}))
	hooks.begin_tick()
	assert_dict(hooks.creature_instruction(0, 0, _vm([Op.YIELD]), _ctx(hooks))).is_empty()
	assert_dict(hooks.sub_ability(SubModel.new(Tuning.original().sub), InputSnapshot.new(), 0, 0)).is_empty()
	assert_int(hooks.fault_log.size()).is_equal(2)
	assert_str(hooks.fault_log[0]).contains("does not accept")


func test_a_tick_makes_at_most_so_many_calls_and_the_next_tick_makes_them_again() -> void:
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({"set_flags": 1}))
	var vm := _vm([Op.YIELD])
	var ctx := _ctx(hooks)
	hooks.begin_tick()
	var answered := 0
	for i in RuleHooks.MAX_CALLS_PER_TICK + 10:
		if not hooks.creature_instruction(0, 0, vm, ctx).is_empty():
			answered += 1
	assert_int(answered).is_equal(RuleHooks.MAX_CALLS_PER_TICK)
	assert_int(_asked.size()).is_equal(RuleHooks.MAX_CALLS_PER_TICK)
	assert_array(hooks.fault_log).is_empty()                         # (a skipped call is no fault)
	hooks.begin_tick()
	assert_dict(hooks.creature_instruction(0, 0, vm, ctx)).is_not_empty()


func test_the_memory_the_ticks_and_the_faults_start_over_with_a_load() -> void:
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({"memory": {"n": 1}}))
	hooks.begin_tick()
	hooks.begin_tick()
	hooks.creature_instruction(0, 0, _vm([Op.YIELD]), _ctx(hooks))
	assert_dict(hooks.memory_of(MOD, RuleHooks.FUNCTION_INSTRUCTION)).is_equal({"n": 1})
	assert_int(hooks.tick()).is_equal(1)
	hooks.begin_load()
	assert_dict(hooks.memory_of(MOD, RuleHooks.FUNCTION_INSTRUCTION)).is_empty()
	assert_int(hooks.tick()).is_equal(-1)
	hooks.begin_tick()
	hooks.creature_instruction(0, 0, _vm([Op.YIELD]), _ctx(hooks))
	assert_int(_asked.back()[2]["tick"]).is_equal(0)
	assert_dict(_asked.back()[2]["memory"]).is_empty()


func test_a_hook_that_answers_differently_to_the_same_state_is_a_fault_when_purity_is_checked() -> void:
	var counter := [0]
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary:
		counter[0] += 1
		return _ok({"dx": counter[0]}))
	hooks.verify_pure = true
	hooks.begin_tick()
	assert_dict(hooks.creature_instruction(0, 0, _vm([Op.YIELD]), _ctx(hooks))).is_empty()
	assert_str(hooks.fault_log[0]).contains("differently")
	var steady := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({"dx": 1}))
	steady.verify_pure = true
	steady.begin_tick()
	assert_dict(steady.creature_instruction(0, 0, _vm([Op.YIELD]), _ctx(steady))).is_equal({"dx": 1})
	assert_array(steady.fault_log).is_empty()


# --- the creature VM -------------------------------------------------------------------------------------------

## `Mod_Instruction` is no opcode where nothing gives it a meaning: the original's behaviour for a byte it does not know.
func test_without_a_mod_the_instruction_is_an_unknown_opcode_as_for_any_byte() -> void:
	for ctx in [_ctx(null), _ctx(RuleHooks.none())]:
		var vm := _vm([Op.MOD_INSTRUCTION, 0, 0, Op.YIELD])
		vm.tick(ctx)
		assert_str(vm.fault).contains("unknown opcode %d" % Op.MOD_INSTRUCTION)
	# a table that defines only the sub ability gives the creatures no instruction either
	var sub_only := RuleHooks.none()
	sub_only.claim_sub(MOD)
	var vm2 := _vm([Op.MOD_INSTRUCTION, 0, 0, Op.YIELD])
	vm2.tick(_ctx(sub_only))
	assert_str(vm2.fault).contains("unknown opcode")
	# and an If_ in front of it, which would skip it, faults as it does for an unknown opcode
	var vm3 := _vm([Op.IF_SEM, 0, Op.MOD_INSTRUCTION, 0, 0, Op.YIELD])
	vm3.tick(_ctx(null))
	assert_str(vm3.fault).contains("after a condition")


## The player is told, once, about every way a pack's creature stops or a mod's instruction is missing (`TroubleLog`; the warning is `push_warning`, which a test reads through `told`).
func test_a_creature_that_faults_is_warned_about_once() -> void:
	var ctx := _ctx(null)
	var vm := _vm([Op.MOD_INSTRUCTION, 5, 0, Op.YIELD])
	vm.index = 2
	vm.sector_index = 77
	for tick in 5:
		vm.tick(ctx)
	assert_array(ctx.trouble.told).has_size(1)
	assert_str(ctx.trouble.told[0]).starts_with("[creatures] sector 77: foe 2: unknown opcode %d at 0" % Op.MOD_INSTRUCTION) \
			.contains("Mod_Instruction 5").contains("no mod of this run defines creature instructions").contains("stays where it is")
	# the same cause met again by a creature made again (a respawn) says nothing new; another creature says its own
	var again := _vm([Op.MOD_INSTRUCTION, 5, 0, Op.YIELD])
	again.index = 2
	again.sector_index = 77
	again.tick(ctx)
	assert_array(ctx.trouble.told).has_size(1)
	var other := _vm([Op.IF_SEM, 0, Op.MOD_INSTRUCTION, 6, 0, Op.YIELD])
	other.index = 3
	other.sector_index = 77
	other.tick(ctx)
	assert_array(ctx.trouble.told).has_size(2)
	assert_str(ctx.trouble.told[1]).contains("sector 77: foe 3: unknown opcode").contains("after a condition").contains("Mod_Instruction 6")
	# any other fault is told as well: the script reads outside itself
	var lost := _vm([Op.JMP, 100, 0])
	lost.index = 4
	lost.sector_index = 77
	lost.tick(ctx)
	assert_array(ctx.trouble.told).has_size(3)
	assert_str(ctx.trouble.told[2]).contains("foe 4: script read outside the buffer")


## A creature made with a fault (the sector's script did not compile) is told of in its first tick, on whatever screen it is, in ONE line for the sector.
func test_a_script_that_did_not_compile_is_warned_about_once_for_the_sector() -> void:
	var ctx := _ctx(null)
	for index in 3:
		var vm := _vm([Op.YIELD])
		vm.index = index
		vm.sector_index = 12
		vm.fault = "the script of SectorData x (sector 12) did not compile (1 problems), first: line 3"
		vm.screen = 9                                                           # (not the shown screen)
		vm.tick(ctx)
	assert_array(ctx.trouble.told).has_size(1)
	assert_str(ctx.trouble.told[0]).starts_with("[creatures] sector 12: the script of SectorData x (sector 12) did not compile").contains("does nothing")


func test_a_mod_instruction_no_mod_defines_is_warned_about_once() -> void:
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({}))
	hooks.campaign_id = &"the_campaign"
	var ctx := _ctx(hooks)
	var vm := _vm([Op.MOD_INSTRUCTION, 5, 0, Op.YIELD])
	vm.index = 1
	vm.sector_index = 40
	for tick in 4:
		hooks.begin_tick()
		vm.pc = 0
		vm.tick(ctx)
	assert_str(vm.fault).is_empty()                                             # (it does nothing, as the table says)
	assert_array(ctx.trouble.told).has_size(1)
	assert_str(ctx.trouble.told[0]).is_equal("[rules] sector 40: foe 1 runs Mod_Instruction 5, which no mod of this run defines (campaign 'the_campaign'); the instruction does nothing and the script goes on")
	# a number the mod defines says nothing
	vm = _vm([Op.MOD_INSTRUCTION, 0, 0, Op.YIELD])
	vm.tick(ctx)
	assert_array(ctx.trouble.told).has_size(1)


func test_the_instruction_applies_what_the_game_accepted() -> void:
	var cases := {
		"flags": [{"set_flags": 0b110, "clear_flags": 0b010}, 0b001, 0b101],
		"nothing": [{}, 0b001, 0b001],
	}
	for name: String in cases:
		var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok(cases[name][0]))
		var vm := _vm([Op.MOD_INSTRUCTION, 0, 7, Op.SET_FRAME, 5, Op.YIELD])
		var ctx := _ctx(hooks)
		ctx.semaphore = cases[name][1]
		hooks.begin_tick()
		vm.tick(ctx)
		assert_int(ctx.semaphore).override_failure_message(name).is_equal(cases[name][2])
		assert_int(vm.frame).override_failure_message(name).is_equal(5)                  # (it went on to the next instruction)
		assert_str(vm.fault).is_empty()


func test_a_false_condition_skips_the_next_instruction_a_true_one_does_not() -> void:
	var verdict := [false]
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({"condition": verdict[0]}))
	var bytes := [Op.MOD_INSTRUCTION, 1, 0, Op.SET_FRAME, 5, Op.SET_FRAME, 6, Op.YIELD]
	var skipped := _vm(bytes)
	hooks.begin_tick()
	skipped.tick(_ctx(hooks))
	assert_int(skipped.frame).is_equal(6)
	verdict[0] = true
	var run_on := _vm(bytes)
	run_on.tick(_ctx(hooks))
	assert_int(run_on.frame).is_equal(6)                       # (5 then 6: the guarded one ran too)
	assert_int(run_on.pc).is_equal(8)
	var guarded := _vm([Op.MOD_INSTRUCTION, 1, 0, Op.SET_FRAME, 5, Op.YIELD])
	verdict[0] = false
	guarded.tick(_ctx(hooks))
	assert_int(guarded.frame).is_equal(0)


func test_an_instruction_may_show_a_picture_move_the_creature_or_end_its_turn() -> void:
	var answer := [{"frame": 130}]
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok(answer[0]))
	var vm := _vm([Op.MOD_INSTRUCTION, 0, 0, Op.SET_FRAME, 9, Op.YIELD])
	hooks.begin_tick()
	vm.tick(_ctx(hooks))
	assert_int(vm.frame).is_equal(9)                           # (the next instruction ran after it and set the picture again)
	var only := _vm([Op.MOD_INSTRUCTION, 0, 0, Op.YIELD])
	only.tick(_ctx(hooks))
	assert_int(only.frame).is_equal(2)
	assert_bool(only.flip).is_true()                           # (bit 7 mirrors, as for Set_Frame)
	answer[0] = {"dx": 3, "dy": -2}
	var moved := _vm([Op.MOD_INSTRUCTION, 0, 0, Op.SET_FRAME, 9, Op.YIELD])
	moved.tick(_ctx(hooks))
	assert_that(Vector2i(moved.x, moved.y)).is_equal(Vector2i(106, 46))        # (2-pixel steps, as Move_Foe_Relative_XY)
	assert_int(moved.frame).is_equal(0)                        # (and it ended the turn: SET_FRAME did not run)
	answer[0] = {"end_turn": true}
	var ended := _vm([Op.MOD_INSTRUCTION, 0, 0, Op.SET_FRAME, 9, Op.YIELD])
	ended.tick(_ctx(hooks))
	assert_int(ended.frame).is_equal(0)
	assert_int(ended.pc).is_equal(3)                           # (it resumes after the instruction next tick)


func test_a_failed_or_undefined_instruction_does_nothing_and_the_script_goes_on() -> void:
	var failing := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _failed())
	var vm := _vm([Op.MOD_INSTRUCTION, 0, 0, Op.SET_FRAME, 9, Op.YIELD])
	failing.begin_tick()
	vm.tick(_ctx(failing))
	assert_int(vm.frame).is_equal(9)
	assert_str(vm.fault).is_empty()
	var undefined := _vm([Op.MOD_INSTRUCTION, 6, 0, Op.SET_FRAME, 9, Op.YIELD])
	undefined.tick(_ctx(failing))
	assert_int(undefined.frame).is_equal(9)
	assert_str(undefined.fault).is_empty()
	assert_int(failing.calls).is_equal(1)                      # (the number nobody defines was not asked)


func test_a_run_of_ticks_is_the_same_each_time() -> void:
	var traces: Array = []
	for round in 2:
		_asked = []
		var hooks := _table(func(_f: String, state: Dictionary) -> Dictionary:
			var n: int = state["memory"].get("n", 0)
			return _ok({"dx": (n % 3) - 1, "set_flags": 1 << (n % 4), "memory": {"n": n + 1}}))
		var vm := _vm([Op.MOD_INSTRUCTION, 0, 0, Op.YIELD, Op.JMP, 249, 255])
		var ctx := _ctx(hooks, [vm])
		var trace: Array[String] = []
		for t in 12:
			hooks.begin_tick()
			vm.tick(ctx)
			trace.append("%d,%d,%d,%d" % [vm.x, vm.y, ctx.semaphore, vm.pc])
		traces.append(trace)
	assert_array(traces[0]).is_equal(traces[1])
	assert_array(traces[0]).is_not_empty()


# --- the sub in the tick ------------------------------------------------------------------------------------------

func test_the_sub_adjusts_what_the_ability_asks_for_and_nothing_else() -> void:
	var model := SubModel.new(Tuning.original().sub)
	model.place_original(100, 100, 6)
	model.adjust({"vx": 12, "vy": -7, "invulnerability": 9})
	assert_that(model.velocity_units).is_equal(Vector2i(12, -7))
	assert_int(model.invulnerability).is_equal(9)
	model.adjust({"vx": 1})
	assert_that(model.velocity_units).is_equal(Vector2i(1, -7))
	model.adjust({})
	assert_that(model.velocity_units).is_equal(Vector2i(1, -7))


## A sim on the dev pack with a table whose sub ability dashes: it is asked once per tick, after the sub moved, and the order of the tick is the original's.
func test_the_tick_asks_the_sub_ability_once_after_the_sub_moved_and_keeps_its_order() -> void:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.reset()
	run.hooks = _table(func(function: String, state: Dictionary) -> Dictionary:
		return _ok({"vx": state["max_velocity"].x, "invulnerability": 5}))
	var sim := SimWorld.new(run)
	sim.trace_ticks = true
	sim.begin_sector(0)
	sim.end_launch()
	_asked.clear()
	sim.tick(InputSnapshot.steering(1, 0))
	assert_array(sim.tick_trace).is_equal(SimWorld.TICK_ORDER)
	assert_int(_asked.size()).is_equal(1)
	assert_str(_asked[0][1]).is_equal(RuleHooks.FUNCTION_SUB)
	assert_int(_asked[0][2]["tick"]).is_equal(0)
	assert_int(sim.sub.velocity_units.x).is_equal(run.tuning.sub.max_speed_x_units)
	assert_int(sim.sub.invulnerability).is_equal(5)
	sim.tick(InputSnapshot.steering(1, 0))
	assert_int(_asked.size()).is_equal(2)
	assert_int(_asked[1][2]["tick"]).is_equal(1)
	# not asked for a sub nobody steers
	sim.sub.controlled = false
	sim.tick(null)
	assert_int(_asked.size()).is_equal(2)


## The creature instruction in a sim: the context has the run's table, `load_sector` starts what the hooks keep over, and a creature runs the instruction in the creatures' step.
func test_a_sim_hands_the_context_the_runs_table_and_starts_the_hooks_over_with_the_creatures() -> void:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.reset()
	var hooks := _table(func(_f: String, _s: Dictionary) -> Dictionary: return _ok({"memory": {"n": 1}}))
	run.hooks = hooks
	var sim := SimWorld.new(run)
	assert_object(sim.foe_context.hooks).is_same(hooks)
	sim.load_sector(DevCreatures.ARENA)
	hooks.begin_tick()
	hooks.creature_instruction(0, 0, sim.foes[0].vm, sim.foe_context)
	assert_dict(hooks.memory_of(MOD, RuleHooks.FUNCTION_INSTRUCTION)).is_not_empty()
	sim.load_sector(DevCreatures.ARENA)                         # (a respawn)
	assert_dict(hooks.memory_of(MOD, RuleHooks.FUNCTION_INSTRUCTION)).is_empty()
	hooks.begin_tick()
	hooks.creature_instruction(0, 0, sim.foes[0].vm, sim.foe_context)
	sim.reload_creatures()                                     # (the reload at the dock)
	assert_dict(hooks.memory_of(MOD, RuleHooks.FUNCTION_INSTRUCTION)).is_empty()


# --- the judging of an answer ---------------------------------------------------------------------------------------

func test_a_session_takes_the_mods_verdict_and_otherwise_the_types_own() -> void:
	var problem := _problem()                                   # the stored answer is 3
	var plain := ProblemSession.new(problem)
	assert_int(plain.submit(NumberValue.parse("6"))).is_equal(ProblemSession.Outcome.WRONG_HINT)
	var right := ProblemSession.new(problem)
	right.judge = func(_p: ProblemInstance, _a: Variant) -> Variant: return true
	assert_int(right.submit(NumberValue.parse("6"))).is_equal(ProblemSession.Outcome.CORRECT_FIRST)
	var wrong := ProblemSession.new(problem)
	wrong.judge = func(_p: ProblemInstance, _a: Variant) -> Variant: return false
	assert_int(wrong.submit(NumberValue.parse("3"))).is_equal(ProblemSession.Outcome.WRONG_HINT)
	var nobody := ProblemSession.new(problem)
	nobody.judge = func(_p: ProblemInstance, _a: Variant) -> Variant: return null
	assert_int(nobody.submit(NumberValue.parse("3"))).is_equal(ProblemSession.Outcome.CORRECT_FIRST)
	assert_int(ProblemSession.new(problem).submit(NumberValue.parse("3"))).is_equal(ProblemSession.Outcome.CORRECT_FIRST)
	assert_int(plain.submit(null)).is_equal(ProblemSession.Outcome.INVALID)


func test_a_flow_points_its_session_at_the_judge_it_is_given() -> void:
	var flow := ProblemFlow.new()
	flow.answer_judge = func(_p: ProblemInstance, _a: Variant) -> Variant: return true
	flow.begin(_problem())
	flow.submit_answer(NumberValue.parse("6"))
	assert_bool(flow.session.solved).is_true()
	var data_judges := ProblemFlow.new()
	data_judges.begin(_problem())
	data_judges.submit_answer(NumberValue.parse("6"))
	assert_bool(data_judges.session.solved).is_false()
