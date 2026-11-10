class_name TestProblemFlowMachine
extends GdUnitTestSuite
## Teaches: testing rules WITHOUT a scene. `ProblemFlow` is the step machine of one math problem; it holds the
## state and the order of the steps and says what it wants shown as named events. Here a whole problem is played with
## plain objects: no `ProblemScreen`, no calculator, no diagram, no scene tree. The view (`tests/engine/test_problem_flow.gd`) is
## tested separately with the real screen.

var _flow: ProblemFlow
var _events: Array


func before_test() -> void:
	_events = []
	_flow = ProblemFlow.new()
	_flow.rng.seed = 7
	_flow.oxygen_sink = func(_delta: int) -> int:
		_events.append(&"oxygen -1")
		return OxygenModel.OK
	_flow.message_shown.connect(func(text: String) -> void: _events.append("message " + text))
	_flow.feedback_shown.connect(func(text: String, is_error: bool) -> void: _events.append("feedback %s %s" % [text, is_error]))
	_flow.sfx_requested.connect(func(sfx: StringName) -> void: _events.append("sound " + sfx))
	_flow.reacted.connect(func(kind: StringName) -> void: _events.append("react " + kind))
	_flow.input_changed.connect(func(enabled: bool) -> void: _events.append("input " + ("on" if enabled else "off")))
	_flow.prompt_shown.connect(func() -> void: _events.append(&"prompt"))
	_flow.go_on_changed.connect(func(shown: bool) -> void: _events.append("go on " + str(shown)))


func _begin(type_id: int, level: int) -> ProblemInstance:
	var problem := ProblemFactory.make(type_id, level, null, 0)
	_flow.begin(problem)
	return problem


func _wrong_answer(problem: ProblemInstance) -> NumberValue:
	return NumberValue.parse(str(problem.expected.to_int() + 1000))


func test_it_is_a_plain_object_without_nodes_textures_fonts_or_input() -> void:
	var flow := ProblemFlow.new()
	assert_bool(flow is RefCounted).is_true()                              # (the parser would refuse `flow is Node`: it knows it is not one)
	# and its source never names what a view is made of (comments and strings do not count; see tests/engine/test_rules_are_plain_objects.gd)
	var found := SourceScan.find("res://src/problems/problem_flow.gd", TestRulesArePlainObjects.FORBIDDEN)
	assert_array(found).override_failure_message("the step machine names a view or an autoload:\n" + "\n".join(found)).is_empty()


func test_a_right_answer_at_the_first_try() -> void:
	var problem := _begin(6, 2)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.ANSWERING)
	assert_array(_events).is_equal([&"prompt"])
	_events.clear()
	_flow.submit_answer(problem.expected)
	assert_array(_events).is_equal(["sound correct", "react right", "input off", "input off", "message " + problem.success])
	assert_int(_flow.step).is_equal(ProblemFlow.Step.MESSAGE)
	var done: Array = []
	_flow.finished.connect(func(session: ProblemSession) -> void: done.append(session))
	_flow.advance_ticks(ProblemFlow.message_ticks() - 1)
	assert_array(done).is_empty()                                              # 145 ticks: still up
	_flow.advance_ticks(1)
	assert_int(done.size()).is_equal(1)
	assert_bool((done[0] as ProblemSession).solved).is_true()
	assert_int(_flow.step).is_equal(ProblemFlow.Step.OVER)


func test_two_misses_give_the_hint_then_the_solution_then_the_success_text() -> void:
	var problem := _begin(6, 2)
	_events.clear()
	_flow.submit_answer(_wrong_answer(problem))
	assert_array(_events).is_equal(["sound wrong", "react wrong", &"oxygen -1", "input off", "message " + Catalog.text(ProblemFlow.STRING_ERROR)])
	_events.clear()
	_flow.press_continue()                                                      # Enter ends "Error!" early
	assert_array(_events).is_equal(["message " + problem.hint, "input on"])
	assert_int(_flow.step).is_equal(ProblemFlow.Step.ANSWERING)
	_events.clear()
	_flow.submit_answer(_wrong_answer(problem))                                 # the second miss
	_flow.advance_ticks(ProblemFlow.message_ticks())                              # "Error!" times out
	while _flow.step == ProblemFlow.Step.MESSAGE:                               # (the note that the problem went to the ship)
		_flow.advance_ticks(ProblemFlow.message_ticks())
	assert_int(_flow.step).is_equal(ProblemFlow.Step.SOLUTION)
	assert_array(_events.slice(-2)).is_equal(["message " + problem.solution, "go on true"])
	_flow.advance_ticks(100000)                                                 # the solution has no time-out
	assert_int(_flow.step).is_equal(ProblemFlow.Step.SOLUTION)
	_flow.press_continue()
	assert_int(_flow.step).is_equal(ProblemFlow.Step.MESSAGE)
	assert_str(_events[-1]).is_equal("message " + problem.success)
	assert_bool(_flow.session.solved).is_false()
	assert_int(_flow.session.misses).is_equal(2)


func test_running_out_of_air_ends_the_problem_after_the_error_message() -> void:
	var problem := _begin(6, 2)
	_flow.oxygen_sink = func(_delta: int) -> int: return OxygenModel.OUT_WITH_SPARE_TANKS
	_flow.submit_answer(_wrong_answer(problem))
	assert_bool(_flow.closed).is_false()
	_flow.advance_ticks(ProblemFlow.message_ticks())
	assert_bool(_flow.closed).is_true()
	assert_bool(_flow.session.finished).is_true()
	assert_int(_flow.session.oxygen_code).is_equal(OxygenModel.OUT_WITH_SPARE_TANKS)


func test_practice_costs_no_oxygen_and_ends_with_a_phrase() -> void:
	_flow.practice = true
	var problem := _begin(6, 2)
	_events.clear()
	_flow.submit_answer(_wrong_answer(problem))
	assert_bool(_events.has(&"oxygen -1")).is_false()
	_flow.press_continue()
	_events.clear()
	_flow.submit_answer(problem.expected)
	assert_bool(String(_events[-1]).begins_with("message ")).is_true()
	assert_str(_events[-1]).is_not_equal("message " + problem.success)          # a short phrase, not the success text
	var done: Array = []
	_flow.finished.connect(func(session: ProblemSession) -> void: done.append(session))
	_flow.press_continue()
	assert_int(done.size()).is_equal(1)


func test_nothing_is_judged_while_a_message_is_up_or_the_build_up_runs() -> void:
	var problem := _begin(6, 2)
	_flow.start_intro(144)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.INTRO)
	assert_array(_events.slice(-2)).is_equal(["message ", "input off"])
	_flow.submit_answer(problem.expected)                                       # a late Enter does nothing
	_flow.press_continue()
	_flow.advance_ticks(143)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.INTRO)
	assert_bool(_flow.session.solved).is_false()
	var intro_done: Array = []
	_flow.intro_finished.connect(func() -> void: intro_done.append(true))
	_events.clear()
	_flow.animation_finished()                                                  # (the diagram was skipped: the step ends at once)
	assert_array(_events).is_equal([&"prompt", "input on"])
	assert_int(_flow.step).is_equal(ProblemFlow.Step.ANSWERING)
	assert_int(intro_done.size()).is_equal(1)


func test_a_build_up_that_ends_after_the_problem_was_closed_changes_nothing() -> void:
	_begin(6, 2)
	_flow.start_intro(144)
	_flow.close()
	_events.clear()
	_flow.animation_finished()
	assert_array(_events).is_empty()
	assert_int(_flow.step).is_equal(ProblemFlow.Step.OVER)


func test_the_build_up_lasts_exactly_the_ticks_it_is_told() -> void:
	_begin(6, 2)
	_flow.start_intro(60)
	_flow.advance_ticks(59)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.INTRO)
	assert_int(_flow.presentation_elapsed()).is_equal(59)
	_flow.advance_ticks(1)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.ANSWERING)
	assert_int(_flow.presentation_elapsed()).is_equal(60)                       # (still counted: the view shows the last picture)


func test_a_build_up_of_no_ticks_is_over_at_once() -> void:
	_begin(6, 2)
	_flow.start_intro(0)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.ANSWERING)


func test_the_success_replay_takes_no_input_and_lasts_the_ticks_the_view_says() -> void:
	_flow.replay_ticks = func() -> int: return 88
	var problem := _begin(6, 2)
	_flow.submit_answer(problem.expected)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.REPLAY)
	assert_bool(_flow.replaying).is_true()
	_flow.press_continue()
	_flow.advance_ticks(87)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.REPLAY)
	_flow.advance_ticks(1)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.MESSAGE)
	assert_str(_events[-1]).is_equal("message " + problem.success)


func test_a_replay_of_no_ticks_goes_straight_to_the_success_text() -> void:
	_flow.replay_ticks = func() -> int: return 0
	var problem := _begin(6, 2)
	_flow.submit_answer(problem.expected)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.MESSAGE)
	assert_str(_events[-1]).is_equal("message " + problem.success)


func test_the_pressed_done_button_is_held_then_the_selection_is_judged() -> void:
	var problem := _begin(28, 0)
	_flow.hold_ballast(0, 73)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.HOLD)
	_flow.submit_answer(problem.expected)                                       # nothing is judged meanwhile
	_flow.press_continue()
	_flow.advance_ticks(72)
	assert_int(_flow.step).is_equal(ProblemFlow.Step.HOLD)
	assert_int(_flow.session.misses).is_equal(0)
	_flow.advance_ticks(1)
	assert_int(_flow.session.misses).is_equal(1)                                # an empty selection is wrong
	assert_int(_flow.step).is_equal(ProblemFlow.Step.MESSAGE)


func test_the_data_canister_opens_its_log_screen_instead_of_a_success_text() -> void:
	var problem := ProblemFactory.for_canister(Catalog.sector(2), 0, null)
	_flow.begin(problem)
	var asked: Array = []
	_flow.log_screen_requested.connect(func(sector: int) -> void: asked.append(sector))
	_flow.submit_answer(problem.expected)
	assert_array(asked).is_equal([2])
	assert_bool(_flow.closed).is_false()
	_flow.close()                                                               # the log screen is done
	assert_bool(_flow.closed).is_true()


func test_a_lock_miss_costs_one_oxygen_and_says_whether_the_air_is_gone() -> void:
	var problem := _begin(0, 0)
	_events.clear()
	assert_bool(_flow.lock_missed()).is_false()
	assert_array(_events).is_equal(["sound wrong", "react wrong", &"oxygen -1", "feedback -1 oxygen true"])
	_flow.oxygen_sink = func(_delta: int) -> int: return OxygenModel.GAME_OVER
	assert_bool(_flow.lock_missed()).is_true()
	_flow.lock_finished(2)
	assert_bool(_flow.session.solved).is_false()
	assert_bool(_flow.closed).is_true()
	assert_object(problem).is_not_null()
