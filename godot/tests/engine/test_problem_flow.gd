class_name TestProblemFlow
extends GdUnitTestSuite
## Teaches: testing a UI scene by driving its public API and reading the state it leaves
## behind (texts, oxygen in the GameState autoload, emitted signals). The problem is the pack's sounder, type 6 level 2 record 0; its answer is
## whatever the record stores (`_right()` types it), and the texts are the pack's.

const SCREEN_SCENE := "res://src/problems/problem_screen.tscn"

var _screen: ProblemScreen
var _problem: ProblemInstance
var _finished: Array
var _sounds: Array


func before_test() -> void:
	GameState.reset()
	GameClock.paused = false
	_screen = scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	_finished = []
	_sounds = []
	_screen.finished.connect(func(session: ProblemSession) -> void: _finished.append(session))
	# the calculator's key clicks (0x1f) are tested in test_sfx_events.gd; here only the judgements count
	_screen.sfx_requested.connect(func(sfx: StringName) -> void:
		if sfx != Calculator.SFX_KEY:
			_sounds.append(sfx))


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func _start(type_id: int, level: int, record: int = 0) -> ProblemInstance:
	var problem := ProblemFactory.make(type_id, level, null, record)
	_problem = problem
	_screen.start(problem)
	if _screen.step() == ProblemScreen.Step.INTRO:        # the diagram builds up first (5.5); these tests answer at once
		_screen.diagram.skip_animation()
	return problem


## The stored answer of the problem on the table, as the keys of the calculator spell it.
func _right() -> String:
	return _problem.expected.to_text()


## Types a number on the calculator the way a player does, then presses Enter.
func _type_on_calculator(keys: String) -> void:
	for key in keys:
		_screen.calculator.press(key)
	_screen.calculator.press("Enter")


func test_correct_at_the_first_try() -> void:
	var problem := _start(6, 2)
	assert_str(_screen.text_label.text).is_equal(problem.prompt)
	assert_bool(GameClock.paused).is_true()                       # the playfield stands still
	_type_on_calculator(_right())
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)      # nothing lost
	assert_str(_screen.text_label.text).is_equal(problem.success)
	assert_bool(_screen.is_waiting_for_continue()).is_true()
	assert_array(_sounds).is_equal([ProblemScreen.SFX_CORRECT])
	assert_int(_finished.size()).is_equal(0)                      # the success text stays up ...
	_screen.advance_ticks(ProblemFlow.message_ticks())            # ... 146 ticks (2 s), `WaitKeyOrTicks(0x92)`
	assert_bool(GameClock.paused).is_false()
	assert_int(_finished.size()).is_equal(1)
	assert_bool(_finished[0].solved).is_true()


func test_wrong_then_right_shows_the_hint_and_costs_one_oxygen() -> void:
	var problem := _start(6, 2)
	_type_on_calculator("98765")
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 1)
	assert_str(_screen.text_label.text).is_equal(Catalog.text(ProblemFlow.STRING_ERROR))        # 2 s or Enter
	assert_bool(_screen.is_answering()).is_false()
	_screen.press_continue()
	assert_str(_screen.text_label.text).is_equal(problem.hint)
	assert_bool(_screen.is_answering()).is_true()
	_type_on_calculator(_right())
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 1)  # no further penalty
	assert_bool(_screen.is_waiting_for_continue()).is_true()
	assert_str(_screen.text_label.text).is_equal(problem.success)
	assert_array(_sounds).is_equal([ProblemScreen.SFX_WRONG, ProblemScreen.SFX_CORRECT])


func test_wrong_twice_shows_the_solution_and_costs_two_oxygen() -> void:
	var problem := _start(6, 2)
	_type_on_calculator("98765")
	_screen.press_continue()
	_type_on_calculator("98766")
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 2)
	assert_str(_screen.text_label.text).is_equal(Catalog.text(ProblemFlow.STRING_ERROR))
	_screen.press_continue()
	assert_str(_screen.text_label.text).is_equal(Catalog.text(ProblemFlow.STRING_DIRECTED_TO_SHIP))         # the second-miss note
	_screen.advance_ticks(ProblemFlow.message_ticks())            # (a time-out goes on like Enter)
	assert_str(_screen.text_label.text).is_equal(problem.solution)
	assert_str(_screen.feedback.text).is_equal(Catalog.text(ProblemScreen.STRING_GO_ON))  # the solution has no time-out
	_screen.advance_ticks(10000)
	assert_str(_screen.text_label.text).is_equal(problem.solution)
	assert_int(_finished.size()).is_equal(0)
	_screen.press_continue()                                       # Enter / a click: the success text follows (2 s)
	assert_str(_screen.text_label.text).is_equal(problem.success)
	_screen.press_continue()
	assert_int(_finished.size()).is_equal(1)
	assert_bool(_finished[0].solved).is_false()
	assert_int(_finished[0].misses).is_equal(2)


func test_running_out_of_air_is_reported_to_the_owner() -> void:
	GameState.oxygen_model.oxygen = 2
	_start(6, 2)
	_type_on_calculator("98765")
	_screen.press_continue()
	_type_on_calculator("98766")
	assert_int(_screen.session.oxygen_code).is_equal(OxygenModel.OUT_WITH_SPARE_TANKS)


func test_escape_does_not_skip_the_problem() -> void:
	_start(6, 2)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_screen._unhandled_key_input(escape)
	assert_bool(_screen.is_waiting_for_continue()).is_false()
	assert_int(_finished.size()).is_equal(0)


func test_enter_closes_a_finished_problem() -> void:
	_start(6, 2)
	_type_on_calculator(_right())
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	_screen._unhandled_key_input(enter)
	assert_int(_finished.size()).is_equal(1)


func test_keyboard_only_calculator_entry() -> void:
	_start(6, 2)
	var typed := _right()
	for character in typed:
		var event := InputEventKey.new()
		event.keycode = KEY_PERIOD if character == "." else KEY_0 + int(character)
		event.unicode = event.keycode                    # '5' is 53 in both numbering schemes
		event.pressed = true
		_screen.calculator._unhandled_key_input(event)
		_screen.calculator.end_flash()                   # a typist is slower than the key flash (12 ticks); keys that come sooner wait
	assert_str(_screen.calculator.display.text).is_equal(typed)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	_screen.calculator._unhandled_key_input(enter)
	assert_bool(_screen.is_waiting_for_continue()).is_true()


func test_keys_without_a_typed_character_work_too() -> void:
	# Remote control and tests send key codes only (no `unicode`); the number pad has its own codes.
	_start(6, 2)
	for keycode in [KEY_5, KEY_KP_0, KEY_0, KEY_PERIOD, KEY_5, KEY_KP_ADD, KEY_1, KEY_EQUAL]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = true
		_screen.calculator._unhandled_key_input(event)
		_screen.calculator.end_flash()
	assert_str(_screen.calculator.display.text).is_equal("501.5")   # 500.5 + 1


func test_calculator_off_uses_a_plain_answer_box() -> void:
	_screen.calculator_allowed = false
	_start(6, 2)
	assert_bool(_screen.calculator.visible).is_false()
	assert_bool(_screen.answer_box.visible).is_true()
	_screen.answer_box.submitted.emit(_right())
	assert_bool(_screen.is_waiting_for_continue()).is_true()


func test_lock_and_ballast_never_get_a_calculator() -> void:
	_start(0, 0)
	assert_bool(_screen.calculator.visible).is_false()
	assert_bool(_screen.answer_box.visible).is_false()          # the lock is answered with the wheels
	assert_bool(_screen.lock != null).is_true()
	_start(28, 0)
	assert_bool(_screen.calculator.visible).is_false()
	assert_bool(_screen.ballast != null).is_true()


## Presses the panel's Done button and lets the hold (in the panel's data) pass.
func _press_done() -> void:
	_screen.ballast._press(_screen.ballast.slot_count())
	_screen.advance_ticks(_screen.ballast.hold_ticks())


func test_the_pressed_done_button_is_held_for_the_ticks_in_the_panels_data() -> void:
	_start(28, 0)
	var hold: int = _problem.type.diagram["total"]["hold_ticks"]
	assert_int(hold).is_greater(1)
	_screen.ballast.toggle(4)
	_screen.ballast._press(_screen.ballast.slot_count())
	assert_int(_screen.ballast.hold_ticks()).is_equal(hold)               # `total.hold_ticks` of the type's diagram
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.HOLD)
	_screen.advance_ticks(hold - 1)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.HOLD)         # not judged yet
	assert_int(_screen.session.misses).is_equal(0)
	_screen.advance_ticks(1)
	assert_int(_screen.session.misses).is_equal(1)                       # now it is (the weight of slot 4 alone is not the target)
	assert_bool(_screen.is_waiting_for_continue()).is_true()


func test_ballast_selection_is_judged_by_its_sum() -> void:
	_start(28, 0)                                         # dev: the target 4 with the weights 1, 2, 3 ... 10 (`dev_problems.ballast_record`)
	assert_int(_problem.record.int_at(0)).is_equal(4)
	_screen.ballast.toggle(1)                             # 2
	_screen.ballast.toggle(2)                             # 3
	assert_int(_screen.ballast.sum()).is_equal(5)
	_press_done()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 1)            # 5 is not 4
	_screen.press_continue()                              # ("Error!" over)
	_screen.ballast.toggle(0)                             # + 1 = 6 -> still wrong
	_screen.ballast.toggle(1)                             # 3 + 1 = 4
	_press_done()
	assert_bool(_screen.session.solved).is_true()


func test_unreadable_entry_does_not_cost_oxygen() -> void:
	_start(6, 2)
	_screen.answer_box.submitted.emit("")
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)


func test_every_type_and_level_can_be_shown_and_answered() -> void:
	var count := 0
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		for level in 4:
			var type := Catalog.problem_type(type_id)
			if type.record_count(level) == 0:
				continue
			var problem := _start(type_id, level, 0)
			assert_str(_screen.title_label.text).is_equal(type.title)
			assert_str(_screen.text_label.text).is_not_empty()
			var answer: Variant = problem.expected
			if problem.input_kind == ProblemInstance.InputKind.DENOMINATIONS:
				answer = problem.record.int_at(1)
			elif answer == null:
				var bounds: PackedInt32Array = type.extras["range_fields"]
				answer = NumberValue.from_double((problem.record.value_at(bounds[0]) + problem.record.value_at(bounds[1])) / 2.0)
			_screen.submit_answer(answer)
			assert_bool(_screen.session.solved).override_failure_message("type %d level %d" % [type_id, level]).is_true()
			if _screen.step() == ProblemScreen.Step.REPLAY:     # (types 6, 11, 12, ...: the diagram replays the answer first)
				_screen.diagram.skip_animation()
			assert_bool(_screen.is_waiting_for_continue()).override_failure_message("type %d level %d" % [type_id, level]).is_true()
			count += 1
	assert_int(count).is_equal(Catalog.PROBLEM_TYPE_COUNT * 4 - 1)     # dev: every (type, level) has problems but the sonar at level 2


# --- the combination lock on the problem screen --------------------------------------------------

func _lock_to_answer_wheel() -> void:
	_screen.lock.press_key()                                         # Enter
	for i in 3000:
		if _screen.lock.phase == CombinationLock.Phase.ANSWER:
			return
		_screen.lock.advance_ticks(1)


func test_a_missed_lock_costs_one_oxygen_and_is_not_repeated() -> void:
	_start(0, 0)
	_lock_to_answer_wheel()
	while not _screen.lock.answer_wheel.is_waiting_for_key():
		_screen.lock.advance_ticks(1)
	_screen.lock.press_key()                                         # the first window is on the wrong label
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 1)
	assert_array(_sounds).contains([ProblemScreen.SFX_WRONG])
	assert_str(_screen.feedback.text).contains("-1 oxygen")
	assert_str(_screen.text_label.text).is_equal("ERROR")
	_screen.lock.press_key()
	assert_str(_screen.text_label.text).is_equal(_problem.type.text_at(1))      # the note that the problem goes to the ship
	_screen.lock.press_key()
	assert_str(_screen.text_label.text).is_equal(ProblemTexts.lock_solution(_problem.type, _problem.record, 0))   # the worked solution
	assert_str(_screen.feedback.text).is_equal(Catalog.text(ProblemScreen.STRING_GO_ON))     # centred on the bottom line
	assert_int(_screen.feedback.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_int(_finished.size()).is_equal(0)                         # it goes on with the second number


func test_a_lock_that_used_up_the_air_ends_after_the_error_and_holds_the_lost_tank_until_closed() -> void:
	var lost := []
	var on_lost := func(code: int) -> void: lost.append(code)
	GameState.tank_lost.connect(on_lost)
	GameState.oxygen_model.oxygen = 1
	_start(0, 0)
	_lock_to_answer_wheel()
	while not _screen.lock.answer_wheel.is_waiting_for_key():
		_screen.lock.advance_ticks(1)
	_screen.lock.press_key()                                         # miss: the last oxygen goes
	assert_array(lost).is_empty()                                    # held while the problem is open
	_screen.lock.press_key()                                         # Enter: ERROR was read, and with no air left that is the end
	assert_int(_finished.size()).is_equal(1)
	assert_int(_finished[0].oxygen_code).is_equal(OxygenModel.OUT_WITH_SPARE_TANKS)
	assert_bool(_finished[0].solved).is_false()
	assert_array(lost).has_size(1)                                   # announced right after the owner saw the result
	GameState.tank_lost.disconnect(on_lost)


func test_a_lock_opened_without_a_miss_is_solved_and_costs_nothing() -> void:
	_start(0, 0)
	for stage in 2:
		if stage == 0:
			_lock_to_answer_wheel()
		else:
			while _screen.lock.phase != CombinationLock.Phase.ANSWER:
				_screen.lock.advance_ticks(1)
		var target := LockWheel.target_position(_screen.lock.answer_wheel.target_slot)
		while not (_screen.lock.answer_wheel.is_waiting_for_key() and _screen.lock.answer_wheel.position == target):
			_screen.lock.advance_ticks(1)
		_screen.lock.press_key()
		_screen.lock.press_key()
	assert_int(_finished.size()).is_equal(1)
	assert_bool(_finished[0].solved).is_true()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)
	assert_bool(GameClock.paused).is_false()


func test_nothing_but_the_lock_messages_is_written_after_a_right_number() -> void:
	# The original writes no "Correct!" for a lock number: sound 0x20, then the notice text (`DoCombinationLock`
	# (0x421780): text 2 / 3 via `WriteMessageText`). The port once left "Correct!" on the bottom line into round 2.
	_start(0, 0)
	_lock_to_answer_wheel()
	var target := LockWheel.target_position(_screen.lock.answer_wheel.target_slot)
	while not (_screen.lock.answer_wheel.is_waiting_for_key() and _screen.lock.answer_wheel.position == target):
		_screen.lock.advance_ticks(1)
	_screen.lock.press_key()                                         # stop on the right label
	assert_array(_sounds).contains([ProblemScreen.SFX_CORRECT])
	assert_str(_screen.text_label.text).is_equal(_problem.type.text_at(2))   # the notice of the first number
	assert_str(_screen.feedback.text).is_empty()
	_screen.lock.press_key()                                         # Enter: the notice is read, round 2 starts
	while _screen.lock.phase != CombinationLock.Phase.ANSWER:
		_screen.lock.advance_ticks(1)
	assert_int(_screen.lock.stage).is_equal(1)
	assert_str(_screen.feedback.text).is_empty()


# --- the message flow of DoMathProblem (0x423629) ----------------------------------------------------

var PHRASES: Array[String]:                                       # the four phrases of the pack (`correct_phrase_0` .. `_3`)
	get:
		var found: Array[String] = []
		for i in CorrectPhrase.COUNT:
			found.append(Catalog.text(StringName("correct_phrase_%d" % i)))
		return found


## Any wrong number for the problem on screen (the stored answers are small).
func _miss() -> void:
	_screen.submit_answer(NumberValue.parse("98765"))


func test_a_message_waits_two_seconds_and_enter_or_a_click_skips_it() -> void:
	_start(6, 2)
	_miss()
	_screen.advance_ticks(ProblemFlow.message_ticks() - 1)
	assert_str(_screen.text_label.text).is_equal(Catalog.text(ProblemFlow.STRING_ERROR))           # 145 ticks: still up
	_screen.advance_ticks(1)
	assert_bool(_screen.is_answering()).is_true()                    # 146: the hint and the second try
	_miss()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	_screen._unhandled_key_input(enter)                              # Enter ends Catalog.text(ProblemFlow.STRING_ERROR) early
	assert_str(_screen.text_label.text).is_equal(Catalog.text(ProblemFlow.STRING_DIRECTED_TO_SHIP))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_bool(_screen._click_catcher.visible).is_true()            # a click anywhere counts, the calculator included
	_screen._on_catcher_input(click)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.SOLUTION)


func test_answers_are_not_read_while_a_message_is_up() -> void:
	_start(6, 2)
	_miss()
	assert_bool(_screen.calculator.keyboard_enabled).is_false()
	_screen.submit_answer(_problem.expected)                         # (what a late Enter on the calculator would do)
	assert_bool(_screen.session.solved).is_false()
	assert_int(_screen.session.misses).is_equal(1)
	_screen.press_continue()
	assert_bool(_screen.calculator.keyboard_enabled).is_true()


func test_the_success_text_goes_on_by_itself_and_enter_skips_it() -> void:
	_start(6, 2)
	_type_on_calculator(_right())
	_screen.advance_ticks(ProblemFlow.message_ticks() - 1)
	assert_int(_finished.size()).is_equal(0)
	_screen.press_continue()
	assert_int(_finished.size()).is_equal(1)


func test_running_out_of_air_at_the_first_miss_ends_the_problem_after_error() -> void:
	GameState.oxygen_model.oxygen = 1
	_start(6, 2)
	_miss()
	assert_str(_screen.text_label.text).is_equal(Catalog.text(ProblemFlow.STRING_ERROR))
	assert_int(_finished.size()).is_equal(0)
	_screen.press_continue()                                         # no hint, no second try
	assert_int(_finished.size()).is_equal(1)
	assert_int(_finished[0].misses).is_equal(1)
	assert_bool(_finished[0].finished).is_true()
	assert_int(_finished[0].oxygen_code).is_not_equal(OxygenModel.OK)


func test_running_out_of_air_at_the_second_miss_skips_the_note_and_the_solution() -> void:
	GameState.oxygen_model.oxygen = 2
	_start(6, 2)
	_miss()
	_screen.press_continue()
	_miss()
	_screen.press_continue()
	assert_int(_finished.size()).is_equal(1)
	assert_int(_finished[0].misses).is_equal(2)


func test_ten_types_skip_the_directed_to_ship_note() -> void:
	assert_array(ProblemScreen.NO_SHIP_NOTICE_TYPES).is_equal([9, 14, 17, 20, 21, 25, 30, 31, 32, 33])
	var level := 0
	while Catalog.problem_type(9).record_count(level) == 0:
		level += 1
	_start(9, level)
	_miss()
	_screen.press_continue()
	_miss()
	_screen.press_continue()                                         # Catalog.text(ProblemFlow.STRING_ERROR) over: straight to the solution
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.SOLUTION)


func test_practice_costs_no_oxygen_has_no_note_and_ends_with_the_solution() -> void:
	_screen.practice = true
	var problem := _start(6, 2)
	_miss()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)
	assert_str(_screen.text_label.text).is_equal(Catalog.text(ProblemFlow.STRING_ERROR))
	_screen.press_continue()
	assert_str(_screen.text_label.text).is_equal(problem.hint)
	_miss()
	_screen.press_continue()
	assert_str(_screen.text_label.text).is_equal(problem.solution)    # (no "directed to ship")
	_screen.press_continue()
	assert_int(_finished.size()).is_equal(1)                         # no success text after the solution
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)


func test_practice_answers_a_right_number_with_one_of_four_phrases() -> void:
	_screen.practice = true
	var seen := {}
	for seed in 40:
		_screen.rng.seed = seed
		_start(6, 2)
		_type_on_calculator(_right())
		assert_array(PHRASES).contains([_screen.text_label.text])
		seen[_screen.text_label.text] = true
		_screen.advance_ticks(ProblemFlow.message_ticks())
	assert_int(seen.size()).is_equal(4)                              # all four occur
	assert_int(_finished.size()).is_equal(40)


func test_practice_lock_says_a_phrase_for_a_right_second_number_not_lock_opened() -> void:
	_screen.practice = true
	_start(0, 0)
	for stage in 2:
		if stage == 0:
			_lock_to_answer_wheel()
		else:
			while _screen.lock.phase != CombinationLock.Phase.ANSWER:
				_screen.lock.advance_ticks(1)
		var target := LockWheel.target_position(_screen.lock.answer_wheel.target_slot)
		while not (_screen.lock.answer_wheel.is_waiting_for_key() and _screen.lock.answer_wheel.position == target):
			_screen.lock.advance_ticks(1)
		_screen.lock.press_key()
		if stage == 0:
			assert_str(_screen.text_label.text).is_equal(_screen.lock.problem.type.text_at(2))   # the notice of the first number
		else:
			assert_array(PHRASES).contains([_screen.text_label.text])
		_screen.lock.press_key()


## A diagram whose success replay is `replay_ticks` ticks long (its data). The flow gives the replay exactly that long.
class ReplayDiagram extends DiagramBase:
	func _init(replay_ticks: int = 50) -> void:
		super()
		success_replay.add_step(0, [])
		success_replay.add_step(replay_ticks, [])


func test_success_replay_lasts_as_many_ticks_as_the_diagram_says_before_the_success_text() -> void:
	var problem := _start(6, 2)                                       # the sounder: a replay type
	assert_array(ProblemScreen.SUCCESS_REPLAY_TYPES).is_equal([6, 11, 12, 16, 22, 23, 26, 27])
	var fake := ReplayDiagram.new(50)
	_screen.diagram.queue_free()
	_screen.diagram = fake
	_screen.add_child(fake)
	_type_on_calculator(_right())
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.REPLAY)
	assert_bool(fake.is_playing()).is_true()
	assert_str(_screen.text_label.text).is_not_equal(problem.success)
	_screen.press_continue()                                          # nothing can skip a replay
	_screen.advance_ticks(49)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.REPLAY)
	_screen.advance_ticks(1)
	assert_bool(fake.is_playing()).is_false()
	assert_str(_screen.text_label.text).is_equal(problem.success)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.MESSAGE)


func test_no_replay_in_a_type_without_one() -> void:
	var level := 0
	while Catalog.problem_type(2).record_count(level) == 0:
		level += 1
	var problem := _start(2, level)                                   # speed graph: no replay
	var fake := ReplayDiagram.new()
	_screen.diagram.queue_free()
	_screen.diagram = fake
	_screen.add_child(fake)
	_screen.submit_answer(problem.expected)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.MESSAGE)


# --- the diagram builds up before the prompt (DrawProblemDiagram, then ShowProblemPrompt) ----------------------

func test_the_prompt_and_the_inputs_wait_for_the_diagram_to_build_up() -> void:
	var problem := ProblemFactory.make(3, 0, null, 0)                 # sonar: the pictures come one after the other first
	var prompts := []
	_screen.intro_finished.connect(func() -> void: prompts.append(_screen.text_label.text))
	_screen.start(problem)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.INTRO)
	assert_str(_screen.text_label.text).is_empty()                    # no prompt yet
	assert_bool(_screen.calculator.keyboard_enabled).is_false()       # keys are discarded
	_screen.submit_answer(problem.expected)                           # (a late Enter / click does nothing)
	assert_bool(_screen.session.solved).is_false()
	assert_int(_screen.session.misses).is_equal(0)
	_screen.press_continue()
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.INTRO)
	_screen.diagram.skip_animation()                                  # the sweep is over
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.ANSWERING)
	assert_str(_screen.text_label.text).is_equal(problem.prompt)
	assert_array(prompts).is_equal([problem.prompt])
	assert_bool(_screen.calculator.keyboard_enabled).is_true()


func test_the_build_up_lasts_as_many_ticks_as_the_diagrams_data_say() -> void:
	var problem := ProblemFactory.make(3, 0, null, 0)                 # sonar: dev's three pictures, one every 20 ticks (`dev_problems.sonar_diagram`)
	_screen.start(problem)
	var length: int = _screen.diagram.intro_length()
	assert_int(length).is_equal(3 * int(problem.type.diagram["intro"]["interval"]))
	_screen.advance_ticks(length - 1)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.INTRO)
	assert_bool(_screen.diagram.is_playing()).is_true()
	_screen.advance_ticks(1)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.ANSWERING)
	assert_bool(_screen.diagram.is_playing()).is_false()              # the diagram played inside the flow's time
	assert_str(_screen.text_label.text).is_equal(problem.prompt)


func test_a_diagram_without_a_build_up_shows_the_prompt_at_once() -> void:
	var problem := ProblemFactory.make(6, 2, null, 0)
	_screen.start(problem)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.ANSWERING)
	assert_str(_screen.text_label.text).is_equal(problem.prompt)


func test_closing_during_the_build_up_does_not_wake_it_later() -> void:
	var problem := ProblemFactory.make(3, 0, null, 0)
	_screen.start(problem)
	var diagram := _screen.diagram
	_screen.close()
	diagram.skip_animation()
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.OVER)
