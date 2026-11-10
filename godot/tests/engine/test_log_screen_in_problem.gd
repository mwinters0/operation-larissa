class_name TestLogScreenInProblem
extends GdUnitTestSuite
## Teaches: testing how two scenes meet. The data canister's problem ends with the log screen on top of it
## (`ShowSuccessMessage` (0x4272f1) -> `do_access_closing` (0x417f56) -> `DoDataBank` (0x41e18f)), after a right
## answer at once and after a second miss once the worked solution has been read.

const SCREEN_SCENE := "res://src/problems/problem_screen.tscn"

var _screen: ProblemScreen
var _finished: Array


func before_test() -> void:
	GameState.reset()
	GameClock.paused = false
	_screen = scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	_finished = []
	_screen.finished.connect(func(session: ProblemSession) -> void: _finished.append(session))


func after_test() -> void:
	Audio.stop_voice()
	Audio.stop_sfx()
	GameClock.paused = false
	GameState.reset()


func _canister(sector: int) -> ProblemInstance:
	var problem := ProblemFactory.for_canister(Catalog.sector(sector), 0, null)
	_screen.start(problem)
	return problem


func test_a_right_answer_opens_the_log_screen_and_closing_it_ends_the_problem() -> void:
	var problem := _canister(2)
	_screen.submit_answer(problem.expected)
	assert_object(_screen.log_screen).is_not_null()
	assert_bool(_screen.content.visible).is_false()                               # the log is a screen of its own
	assert_int(_finished.size()).is_equal(0)
	assert_int(_screen.log_screen.sector).is_equal(2)
	_screen.log_screen.press(&"escape")
	assert_int(_finished.size()).is_equal(1)
	assert_bool(_finished[0].solved).is_true()


## `GameState.hold_losses` is a count: a screen that is started twice (the debug menu, "a second problem on the same screen") still
## holds the lost tanks once, and closing it gives them back.
func test_starting_a_screen_twice_holds_the_losses_once() -> void:
	var lost: Array[int] = []
	var on_lost := func(code: int) -> void: lost.append(code)
	GameState.tank_lost.connect(on_lost)
	_canister(0)
	_canister(0)
	GameState.update_oxygen(-4)
	assert_array(lost).is_empty()                              # held while the problem is open
	_screen.close()
	GameState.tank_lost.disconnect(on_lost)
	assert_array(lost).is_equal([OxygenModel.OUT_WITH_SPARE_TANKS])     # announced when it closed, and nothing is held any more
	assert_bool(GameState.has_held_loss()).is_false()
	GameState.update_oxygen(-4)
	assert_bool(GameState.has_held_loss()).is_false()


## The flow leaves the replay when the log screen opens: the ticks that pass while the log is up (the scan, the speech) must not
## end the replay again and open the log screen once more on every tick (one scanner sound and one speech, not one per frame).
func test_ticks_while_the_log_is_up_do_not_open_it_again() -> void:
	var problem := _canister(0)
	_screen.submit_answer(problem.expected)
	var first := _screen.log_screen
	assert_object(first).is_not_null()
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.LOG)
	for i in 20:
		_screen.advance_ticks(1)
	assert_object(_screen.log_screen).is_same(first)
	assert_int(_screen.get_children().filter(func(c: Node) -> bool: return c is LogScreen).size()).is_equal(1)


func test_a_second_miss_shows_the_solution_first_and_the_log_screen_after_it() -> void:
	var problem := _canister(1)
	var wrong := NumberValue.parse("123456")
	_screen.submit_answer(wrong)
	_screen.advance_ticks(ProblemFlow.message_ticks())                           # "Error!"
	assert_bool(_screen.is_answering()).is_true()                                # the hint, second try
	_screen.submit_answer(wrong)
	_screen.advance_ticks(ProblemFlow.message_ticks())                           # "Error!"
	while _screen.step() == ProblemScreen.Step.MESSAGE:                          # (the note that the problem went to the ship)
		_screen.advance_ticks(ProblemFlow.message_ticks())
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.SOLUTION)
	assert_str(_screen.text_label.text).is_equal(problem.solution)
	assert_object(_screen.log_screen).is_null()
	_screen.press_continue()
	assert_object(_screen.log_screen).is_not_null()
	assert_int(_screen.log_screen.sector).is_equal(1)
	_screen.log_screen.press(&"escape")
	assert_int(_finished.size()).is_equal(1)
	assert_bool(_finished[0].solved).is_false()


func test_other_problems_have_no_log_screen() -> void:
	var problem := ProblemFactory.make(6, 2)
	_screen.start(problem)
	_screen.submit_answer(problem.expected)
	assert_object(_screen.log_screen).is_null()


# --- a replay with nothing to wait for ends inside the step change ----------------------------------------------------

## The overlay types (6, 11, 16) replay in one step at tick 0: the diagram reports `animation_finished` while the view starts the
## replay, i.e. INSIDE the flow's change to the replay step. The success text (or the canister's log screen) must come once.
const ZERO_TICK_REPLAY_TYPES: Array[int] = [6, 11, 16]


## The first level (0-3) where `type_id` has a problem, as a problem started on the screen (the build-up skipped).
func _start_type(type_id: int) -> ProblemInstance:
	for level in 4:
		var problem := ProblemFactory.make(type_id, level, null, 0)
		if problem != null:
			_screen.start(problem)
			if _screen.step() == ProblemScreen.Step.INTRO:
				_screen.diagram.skip_animation()
			return problem
	return null


func _log_screens() -> Array:
	return _screen.get_children().filter(func(c: Node) -> bool: return c is LogScreen)


func test_a_replay_of_zero_ticks_posts_the_success_text_once() -> void:
	for type_id in ZERO_TICK_REPLAY_TYPES:
		after_test()
		before_test()
		var problem := _start_type(type_id)
		assert_object(problem).is_not_null()
		assert_int(_screen.diagram.success_replay_length()).is_equal(0)               # (the premise: nothing to wait for)
		var texts: Array[String] = []
		var steps: Array[int] = []
		_screen._flow.message_shown.connect(func(text: String) -> void: texts.append(text))
		_screen._flow.step_changed.connect(func(step: ProblemFlow.Step) -> void: steps.append(step))
		_screen.submit_answer(problem.expected)
		assert_int(_screen.step()).is_equal(ProblemScreen.Step.MESSAGE)
		assert_array(texts.filter(func(t: String) -> bool: return t == problem.success)).has_size(1)
		assert_array(steps.filter(func(s: int) -> bool: return s == ProblemScreen.Step.MESSAGE)).has_size(1)
		_screen.advance_ticks(ProblemFlow.message_ticks() - 1)                        # one timer, not re-armed by a second call
		assert_int(_screen.step()).is_equal(ProblemScreen.Step.MESSAGE)
		_screen.advance_ticks(1)
		assert_int(_finished.size()).is_equal(1)
		assert_bool(_finished[0].solved).is_true()


func test_a_replay_of_zero_ticks_before_the_canister_log_opens_one_log_screen() -> void:
	for type_id in ZERO_TICK_REPLAY_TYPES:
		after_test()
		before_test()
		var problem := _start_type(type_id)
		problem.log_index = CanisterLog.newest(2) - 1   # as `for_canister` does
		problem.log_sector = 2
		var requests: Array[int] = []
		_screen._flow.log_screen_requested.connect(func(sector: int) -> void: requests.append(sector))
		_screen.submit_answer(problem.expected)
		assert_array(requests).is_equal([2])
		assert_int(_log_screens().size()).is_equal(1)
		assert_int(_screen.step()).is_equal(ProblemScreen.Step.LOG)
		_screen.advance_ticks(10)
		assert_int(_log_screens().size()).is_equal(1)
