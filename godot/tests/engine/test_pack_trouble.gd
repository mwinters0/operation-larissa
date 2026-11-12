class_name TestPackTrouble
extends GdUnitTestSuite
## Teaches: "a pack's trouble is never silent" as something a test can pin. A warning is `push_warning`, which a test cannot read back, so every warning goes through a `TroubleLog` whose `told` lists what was said once; these tests check
## the line (the pack, the thing it names, what the player sees instead) and that the cause is told once however often it is met. The warnings of a mod's scripts, drawing and sounds are in the tests of those systems
## (`test_mod_rules`, `test_mod_problems`, `test_mod_problem_animation`, `test_mod_skin_layers`, `test_mod_pack`, `test_rule_hooks`); here are the log itself and the lookups with no mod behind them.

func before_test() -> void:
	GameState.reset()                                                               # (a run begins: the session's log is a new one)


func after_test() -> void:
	GameState.reset()


func test_a_log_gives_each_line_once_and_keeps_it_for_a_test() -> void:
	var log := TroubleLog.new()
	assert_bool(log.tell("[x] one")).is_true()
	assert_bool(log.tell("[x] one")).is_false()
	assert_bool(log.tell("[x] two")).is_true()
	assert_array(log.told).is_equal(["[x] one", "[x] two"])
	assert_bool(log.has("[x] two")).is_true()
	assert_bool(log.has("[x] three")).is_false()


func test_a_log_has_a_limit_and_says_so_with_its_last_line() -> void:
	var log := TroubleLog.new()
	for i in TroubleLog.MAX_LINES + 10:
		log.tell("[x] line %d" % i)
	assert_int(log.told.size()).is_equal(TroubleLog.MAX_LINES)
	assert_str(log.told.back()).ends_with("(further warnings of this kind are not given)")
	assert_bool(log.tell("[x] one more")).is_false()


func test_a_run_begins_with_a_new_session() -> void:
	TroubleLog.session.tell("[x] said in the last run")
	GameState.begin_run(null)
	assert_array(TroubleLog.session.told).is_empty()
	assert_bool(TroubleLog.session.tell("[x] said in the last run")).is_true()


func test_a_list_that_is_no_list_and_a_list_with_dropped_commands_are_told_once_per_run() -> void:
	var assets := ModAssets.new()
	assets.folder = "skin/"
	var drawn := ModDraw.validate([["rect", Rect2(0, 0, 1, 1), Color.RED], ["picture", "skin/missing.png", Vector2(0, 0)], 7, ["text", "x", "where", 12, Color.RED]], null, assets)
	assert_str(drawn.first_dropped).is_equal("picture \"skin/missing.png\"")
	for i in 3:
		ModDraw.report(drawn, &"the_pack", "skin")
		ModDraw.report_not_a_list(&"the_pack", "skin", "the original's layer shows")
	ModDraw.report(ModDraw.validate([["rect", Rect2(0, 0, 1, 1), Color.RED]], null, assets), &"clean_pack", "skin")          # (nothing dropped: nothing told)
	assert_array(TroubleLog.session.told).has_size(2)
	assert_str(TroubleLog.session.told[0]).is_equal("[mods] mod 'the_pack': its skin draw list has commands the game does not draw, the first is picture \"skin/missing.png\"; commands like that are left out (a name its pack does not hold, a shader its manifest does not list, a value out of range, or more than the limits allow) and the rest is drawn")
	assert_str(TroubleLog.session.told[1]).is_equal("[mods] mod 'the_pack': its skin answered something that is not a list of draw commands; the original's layer shows")
	# the first dropped command is named by what it is: an entry that is no command, a command with values it does not accept, a command it does not know
	assert_str(ModDraw.validate([7], null, assets).first_dropped).is_equal("an entry that is no command")
	assert_str(ModDraw.validate([["rect", "red"]], null, assets).first_dropped).is_equal("a \"rect\" with values the game does not accept")
	assert_str(ModDraw.validate([["sparkle", 1]], null, assets).first_dropped).is_equal("a command named \"sparkle\", which the game does not know")
	# a run begins: the same cause is told again
	GameState.begin_run(null)
	ModDraw.report(drawn, &"the_pack", "skin")
	assert_array(TroubleLog.session.told).has_size(1)


func test_sounds_the_game_does_not_play_are_named_for_the_warning() -> void:
	var sounds := ModSounds.new()
	sounds.now = func() -> int: return 0
	assert_array(sounds.accept(["click", "no_such_sound_anywhere", "Not A Name!", 5])).is_equal([&"click"])
	assert_array(sounds.refused).is_equal(["no_such_sound_anywhere", "Not A Name!", "5"])
	assert_bool(sounds.too_many).is_false()
	sounds.accept(["click", "click", "click", "click", "click"])                       # (one over the limit of a call)
	assert_bool(sounds.too_many).is_true()
	assert_array(sounds.refused).is_empty()
	sounds.accept([])                                                                  # (the next answer starts from nothing)
	assert_bool(sounds.too_many).is_false()


## A mod that judges a type whose answer is not a number (the player's own panel): the type's data judges, and the player is told.
func test_a_mod_that_judges_a_type_that_takes_no_number_is_told_once() -> void:
	var hooks := RuleHooks.none()
	hooks.claim_judge(41, &"judge_mod")
	hooks.set_caller(func(_mod: StringName, _function: String, _state: Dictionary) -> Dictionary: return {"ok": true, "value": true})
	var problem := ProblemInstance.build(ModRuleShelf.problem_type(), 0, 0)
	problem.input_kind = ProblemInstance.InputKind.DENOMINATIONS
	for i in 3:
		assert_object(hooks.judge_answer(problem, 12)).is_null()
	assert_array(hooks.trouble.told).has_size(1)
	assert_str(hooks.trouble.told[0]).starts_with("[rules] mod 'judge_mod' judges problem type 41, but that type is not answered with a number").contains("the type's own data judges it")


## A trigger table that names problem types the chain does not have: no problem opens, and the player is told (once).
func test_a_trigger_slot_whose_types_the_chain_lacks_is_told_once() -> void:
	var shelf := PackShelf.new()
	var table := Catalog.trigger_table().duplicate(true) as TriggerTable
	for pick in TriggerTable.PICKS:
		table.table[(5 * TriggerTable.LEVELS + 0) * TriggerTable.PICKS + pick] = 250
	shelf.write_json("data/trigger_table.json", ResourceJson.new().data_of(table))
	shelf.mount()
	assert_int(Catalog.trigger_table().type_for(5, 0, 0)).is_equal(250)
	for i in 3:
		assert_object(ProblemFactory.for_trigger_slot(5, 0)).is_null()
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).is_equal("[problems] the trigger table (of the chain in use) names problem types 250 and 250 for slot 5 at level 0, and the chain has no problem of either there; no problem opens and the sub goes on as if it were solved (a data canister counts as collected, without its log entry)")
	shelf.remove()
	assert_object(ProblemFactory.for_trigger_slot(5, 0)).is_not_null()                # (the chain's own table: a problem opens, and nothing more is told)
	assert_array(TroubleLog.session.told).has_size(1)
