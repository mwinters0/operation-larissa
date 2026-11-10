class_name TestCombinationLock
extends GdUnitTestSuite
## Teaches: driving a controller by its public methods and by time that the test controls
## (`advance_ticks`), while watching its signals. The lock is dev's type 0, level 0, record 0 (`dev_problems.lock_record`): its two numbers are the sum
## of two operand labels, 1 + 2 = 3 (the answer wheel's label 3 is its slot 1). Where a test needs the sum or the texts it asks the program and the type.

var _lock: CombinationLock
var _diagram: LockDiagram
var _problem: ProblemInstance
var _said: Array
var _events: Array


func before_test() -> void:
	_problem = ProblemFactory.make(0, 0, null, 0)
	_diagram = auto_free(DiagramFactory.create(_problem)) as LockDiagram
	add_child(_diagram)
	_lock = auto_free(CombinationLock.new())
	add_child(_lock)
	_lock.set_process(false)                       # only the test moves time
	_said = []
	_events = []
	_lock.say.connect(func(text: String) -> void: _said.append(text))
	_lock.stage_right.connect(func() -> void: _events.append("right"))
	_lock.stage_missed.connect(func(reason: String) -> void: _events.append(reason))
	_lock.finished.connect(func() -> void: _events.append("finished"))
	_lock.setup(_problem, _diagram)


## Runs ticks until `condition` holds (at most `limit` ticks, so a bug cannot hang the test).
func _until(condition: Callable, limit: int = 5000) -> void:
	var n := 0
	while not condition.call() and n < limit:
		_lock.advance_ticks(1)
		n += 1
	assert_bool(condition.call()).is_true()


func _to_answer_wheel() -> void:
	_lock.press_key()                                                        # Enter: begin
	_until(func() -> bool: return _lock.phase == CombinationLock.Phase.ANSWER)


func _to_right_position() -> void:
	var target := LockWheel.target_position(_lock.answer_wheel.target_slot)
	_until(func() -> bool: return _lock.answer_wheel.is_waiting_for_key() and _lock.answer_wheel.position == target)


func test_it_starts_with_the_instruction_and_waits_for_enter() -> void:
	assert_str(_said[0]).is_equal(_problem.type.text_at(0))                 # the instruction
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.INTRO)
	_lock.advance_ticks(2000)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.INTRO)


func test_the_operand_wheel_builds_the_sum_in_the_long_box() -> void:
	_to_answer_wheel()
	assert_str(_diagram.expression_text).is_equal(_program().expression() + " =")
	assert_str(_diagram.operator_text).is_equal("=")


func _program(stage: int = 0) -> LockProgram:
	return LockProgram.from_record(_problem.type, _problem.record, stage)


func _until_reveal() -> void:
	_until(func() -> bool: return _lock.phase == CombinationLock.Phase.REVEAL)


## Original (`LockRevealOperator` (0x422176)): after a number settles the operator box goes dark for 146 ticks (`DelayTicks(0x92)`),
## shows the operator for 24, blanks for 24 and shows it for good; only then does the operator join the sum.
func test_a_settled_number_holds_back_its_operator_for_146_ticks_then_blinks_it_in() -> void:
	_lock.press_key()
	_until_reveal()
	var program := _program()
	var op := program.operators[0]
	assert_str(_diagram.expression_text).is_equal(program.operands[0])   # the number is in the sum at once
	assert_str(_diagram.operator_text).is_equal("")
	_lock.advance_ticks(145)
	assert_str(_diagram.operator_text).is_equal("")
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.REVEAL)
	_lock.advance_ticks(1)                                              # tick 146: the operator blinks on
	assert_str(_diagram.operator_text).is_equal(op)
	assert_str(_diagram.expression_text).is_equal(program.operands[0])
	_lock.advance_ticks(23)
	assert_str(_diagram.operator_text).is_equal(op)
	_lock.advance_ticks(1)                                              # tick 170: off
	assert_str(_diagram.operator_text).is_equal("")
	_lock.advance_ticks(23)
	assert_str(_diagram.operator_text).is_equal("")
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.REVEAL)
	_lock.advance_ticks(1)                                              # tick 194: on for good, in the sum, wheel turns on
	assert_str(_diagram.operator_text).is_equal(op)
	assert_str(_diagram.expression_text).is_equal("%s %s" % [program.operands[0], op])
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.OPERANDS)


func test_the_pause_is_194_ticks_after_every_number_the_last_one_included() -> void:
	assert_int(CombinationLock.OPERATOR_REVEAL.reduce(func(sum: int, step: Array) -> int: return sum + step[0], 0)).is_equal(194)
	_lock.press_key()
	var program := LockProgram.from_record(_problem.type, _problem.record, 0)
	for number in program.operands.size():
		_until_reveal()
		var last := number == program.operands.size() - 1
		_lock.advance_ticks(193)
		assert_int(_lock.phase).is_equal(CombinationLock.Phase.REVEAL)
		_lock.advance_ticks(1)
		assert_int(_lock.phase).is_equal(CombinationLock.Phase.ANSWER if last else CombinationLock.Phase.OPERANDS)
	assert_str(_diagram.expression_text).is_equal(program.expression() + " =")
	assert_str(_diagram.operator_text).is_equal("=")


func test_the_answer_wheel_waits_for_the_last_pause_and_keys_do_not_skip_any_pause() -> void:
	_lock.press_key()
	_until_reveal()
	for i in 10:
		_lock.press_key()                                               # busy wait in the original: nothing is read
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.REVEAL)
	_lock.advance_ticks(193)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.REVEAL)
	_until(func() -> bool: return _lock.phase == CombinationLock.Phase.ANSWER)
	assert_int(_lock.answer_wheel.position).is_equal(0)                 # the answer wheel only starts now
	assert_int(_lock.answer_wheel.elapsed_ticks).is_equal(0)


func test_the_whole_showing_takes_the_spins_plus_194_ticks_per_number() -> void:
	_lock.press_key()
	var program := LockProgram.from_record(_problem.type, _problem.record, 0)
	var expected := 0
	var at := 0
	for i in program.operand_slots.size():
		var target := LockWheel.target_position(program.operand_slots[i])
		expected += LockWheel.Spin.new(at, target, 1 if i % 2 == 0 else -1, Tuning.original()).total_ticks() + 194
		at = target
	var ticks := 0
	while _lock.phase != CombinationLock.Phase.ANSWER and ticks < 5000:
		_lock.advance_ticks(1)
		ticks += 1
	assert_int(ticks).is_equal(expected)


func test_the_operand_wheel_ends_with_the_last_number_under_the_arrow() -> void:
	_to_answer_wheel()
	var program := LockProgram.from_record(_problem.type, _problem.record, 0)
	assert_int(_lock.operand_position).is_equal(LockWheel.target_position(program.operand_slots[program.operand_slots.size() - 1]))


func test_stopping_the_answer_wheel_on_the_result_opens_the_first_number() -> void:
	_to_answer_wheel()
	_to_right_position()
	_lock.press_key()
	assert_array(_events).is_equal(["right"])
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.NOTICE)
	assert_str(_said.back()).is_equal(_problem.type.text_at(2))                # the notice of the first number
	assert_int(_lock.misses).is_equal(0)


func _to_miss() -> void:
	_to_answer_wheel()
	_until(func() -> bool: return _lock.answer_wheel.is_waiting_for_key())    # label 7 is under the arrow, not label 0
	_lock.press_key()


## Original (`LockRunStage`): ERROR for 146 ticks or Enter / a click, the hint for 146 ticks or Enter / a click,
## then the worked solution with "Click to go on." until Enter. Three screens, not one.
func test_a_wrong_stop_is_an_error_then_the_hint_then_the_solution_and_no_second_try() -> void:
	var prompts := []
	_lock.go_on_prompt.connect(func(shown: bool) -> void: prompts.append(shown))
	_to_miss()
	assert_array(_events).is_equal(["ERROR"])
	assert_int(_lock.misses).is_equal(1)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_REASON)
	assert_str(_said.back()).is_equal("ERROR")
	_lock.press_key()                                                         # Enter: on to the hint
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_HINT)
	assert_str(_said.back()).is_equal(_problem.type.text_at(1))
	assert_str(_said.back()).is_equal(_problem.type.text_at(1))
	assert_array(prompts).is_empty()
	_lock.press_key()                                                         # Enter: on to the solution
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_SOLUTION)
	assert_str(_said.back()).is_equal(ProblemTexts.lock_solution(_problem.type, _problem.record, 0))     # the worked solution of the first number
	assert_array(prompts).is_equal([true])
	_lock.advance_ticks(5000)                                                 # the solution has no time-out
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_SOLUTION)
	_lock.press_key()                                                         # read it, continue: NOT the same number again
	assert_array(prompts).is_equal([true, false])
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.NOTICE)
	assert_int(_lock.stage).is_equal(0)


func test_the_error_and_the_hint_time_out_after_146_ticks_each() -> void:
	_to_miss()
	_lock.advance_ticks(ProblemFlow.message_ticks() - 1)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_REASON)
	_lock.advance_ticks(1)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_HINT)
	_lock.advance_ticks(ProblemFlow.message_ticks() - 1)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_HINT)
	_lock.advance_ticks(1)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_SOLUTION)


func test_no_stop_for_two_revolutions_is_out_of_time() -> void:
	_to_answer_wheel()
	_until(func() -> bool: return _lock.phase == CombinationLock.Phase.MISS_REASON, 3 * LockWheel.new(0, Tuning.original()).ticks_per_revolution())
	assert_array(_events).is_equal(["OUT OF TIME"])
	assert_str(_said.back()).is_equal("OUT OF TIME")
	assert_int(_lock.answer_wheel.passes).is_equal(2)


func test_the_notice_closes_by_itself_after_146_ticks_and_the_second_number_follows() -> void:
	_to_answer_wheel()
	_to_right_position()
	_lock.press_key()
	_lock.advance_ticks(ProblemFlow.message_ticks() - 1)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.NOTICE)
	_lock.advance_ticks(1)
	assert_int(_lock.stage).is_equal(1)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.OPERANDS)


func test_the_second_answer_wheel_starts_where_the_first_was_stopped() -> void:
	# (the record's first answer is on a slot other than the wheel's rest position 0, or there would be nothing to see)
	assert_int(_program().answer_slot).is_not_equal(0)
	var diagram := _diagram
	var lock := _lock
	lock.press_key()
	while lock.phase != CombinationLock.Phase.ANSWER:
		lock.advance_ticks(1)
	var target := LockWheel.target_position(lock.answer_wheel.target_slot)
	while not (lock.answer_wheel.is_waiting_for_key() and lock.answer_wheel.position == target):
		lock.advance_ticks(1)
	assert_int(target).is_not_equal(0)
	lock.press_key()
	lock.press_key()                                                          # Enter skips the notice
	lock.advance_ticks(1)
	assert_int(diagram.answer_position).is_equal(target)                      # the drawing keeps it while the operands turn
	while lock.phase != CombinationLock.Phase.ANSWER:
		lock.advance_ticks(1)
	assert_int(lock.answer_wheel.position).is_equal(target)
	assert_int(diagram.answer_position).is_equal(target)


func test_the_answer_wheel_stays_where_it_was_stopped_after_a_miss_too() -> void:
	_to_miss()
	var stopped_at := _lock.answer_wheel.position
	_lock.press_key()
	_lock.press_key()
	_lock.press_key()                                                         # ERROR, hint, solution read: the notice
	_lock.press_key()
	_until(func() -> bool: return _lock.phase == CombinationLock.Phase.ANSWER)
	assert_int(_lock.answer_wheel.position).is_equal(stopped_at)


func test_the_messages_end_with_a_click_anywhere_on_release() -> void:
	_to_miss()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(600, 390)
	_lock._unhandled_input(click)                                             # `PollInput` (0x410c7d): only the left-button-UP gives the hotspot id
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_REASON)
	click.pressed = false
	click.position = Vector2(600, 390)                                        # far from the wheel
	_lock._unhandled_input(click)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_HINT)
	_lock._unhandled_input(click)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_SOLUTION)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	_lock._unhandled_input(space)                                             # Space is only read by the answer wheel
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_SOLUTION)
	_lock._unhandled_input(click)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.NOTICE)


func test_both_numbers_right_opens_the_lock() -> void:
	for stage in 2:
		if stage == 0:
			_to_answer_wheel()
		else:
			_until(func() -> bool: return _lock.phase == CombinationLock.Phase.ANSWER)
		_to_right_position()
		_lock.press_key()
		_lock.press_key()                                                     # Enter skips the notice
	assert_array(_events).is_equal(["right", "right", "finished"])
	assert_bool(_said.has(_problem.type.text_at(3))).is_true()               # the notice of the second number: the lock is open
	assert_int(_lock.misses).is_equal(0)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.DONE)


func test_when_the_air_ran_out_the_lock_ends_after_the_error_was_read() -> void:
	_to_answer_wheel()
	_until(func() -> bool: return _lock.answer_wheel.is_waiting_for_key())
	_lock.press_key()                                                         # a miss
	_lock.abort_after_miss = true
	_lock.press_key()                                                         # ERROR read: no hint, no solution
	assert_array(_events).is_equal(["ERROR", "finished"])
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.DONE)


func test_the_directions_of_the_operand_wheel_alternate() -> void:
	_lock.press_key()
	var positions: Array[int] = []
	var last := 0
	while _lock.phase != CombinationLock.Phase.ANSWER:
		_lock.advance_ticks(1)
		if _lock.operand_position != last:
			positions.append(_lock.operand_position)
			last = _lock.operand_position
	# one step is +1 (the wheel counts up, the first number) or -1 (the other way round, the second); 31 is -1 modulo the 32 positions
	var deltas: Array[int] = []
	var previous := 0
	for position in positions:
		deltas.append(posmod(position - previous, LockWheel.POSITIONS))
		previous = position
	assert_int(deltas[0]).is_equal(1)
	var turn := deltas.find(LockWheel.POSITIONS - 1)
	assert_int(turn).is_greater(0)                                          # the second number turns back
	for i in deltas.size():
		assert_int(deltas[i]).is_equal(1 if i < turn else LockWheel.POSITIONS - 1)
	assert_int(positions.back()).is_equal(LockWheel.target_position(_program().operand_slots[_program().operand_slots.size() - 1]))


func test_the_wheels_move_the_labels_in_the_drawing() -> void:
	var at_rest := _diagram.label_position("answer", 0, 0)
	var spots: Array = _diagram.spec["answer_labels"]                          # [quarter-turn phase][spot] of the layout's data
	assert_vector(at_rest).is_equal(_diagram.vector(spots[0][0]))             # label 0 is under the arrow (spot 0) at rest
	assert_vector(_diagram.label_position("answer", 0, 4)).is_equal(_diagram.vector(spots[0][1]))   # one label on: spot 1
	assert_vector(_diagram.label_position("answer", 1, 31)).is_equal(_diagram.vector(_diagram.spec["answer_labels"][3][0]))
	assert_vector(_diagram.label_position("answer", 7, 4)).is_equal(at_rest)    # label 7 arrives at the arrow


func test_every_stored_lock_builds_a_clean_sum_and_ends_with_the_wheel_on_the_last_number() -> void:
	for level in 4:
		for index in Catalog.problem_type(0).record_count(level):
			var problem := ProblemFactory.make(0, level, null, index)
			var diagram := auto_free(DiagramFactory.create(problem)) as LockDiagram
			add_child(diagram)
			var lock: CombinationLock = auto_free(CombinationLock.new())
			add_child(lock)
			lock.set_process(false)
			lock.setup(problem, diagram)
			lock.press_key()
			for stage in 2:
				var n := 0
				while lock.phase != CombinationLock.Phase.ANSWER and n < 5000:
					lock.advance_ticks(1)
					n += 1
				var program := LockProgram.from_record(problem.type, problem.record, stage)
				assert_str(diagram.expression_text).is_equal(program.expression() + " =")
				assert_int(lock.operand_position).is_equal(LockWheel.target_position(program.operand_slots[-1]))
				# solve it the quick way: the right label comes by itself and we stop it
				var target := LockWheel.target_position(program.answer_slot)
				while not (lock.answer_wheel.is_waiting_for_key() and lock.answer_wheel.position == target):
					lock.advance_ticks(1)
				lock.press_key()
				lock.press_key()                                          # skip the notice
			assert_int(lock.misses).is_equal(0)
			assert_int(lock.phase).is_equal(CombinationLock.Phase.DONE)


func test_the_first_wheel_of_every_stage_turns_forward() -> void:
	_to_answer_wheel()
	_to_right_position()
	_lock.press_key()
	_lock.press_key()                                                         # Enter skips the notice: stage 2 begins
	var start := _lock.operand_position
	var program := LockProgram.from_record(_problem.type, _problem.record, 1)
	var target := LockWheel.target_position(program.operand_slots[0])
	_lock.advance_ticks(Tuning.original().lock_ticks_per_position)
	assert_int(_lock.operand_position).is_equal(posmod(start + 1, LockWheel.POSITIONS))
	assert_int(posmod((target - start), LockWheel.POSITIONS)).is_greater(0)   # (so "forward" is the short way here)


# --- G21: what survives the answer wheel's motion, and the stop button ----------------------------------

func _key(keycode: int) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	return key


func _click(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = at
	return click


## Runs to the start of an answer wheel motion (the wheel has just left a key window, or just started).
func _to_motion_start() -> void:
	_to_answer_wheel()
	assert_int(_lock.answer_wheel.state).is_equal(LockWheel.State.MOVING)
	assert_int(_lock.answer_wheel.ticks_in_state()).is_equal(0)


## `LockAdvanceAnswerWheel` (0x421d6c): each of the 4 sub-steps loads sound 0x26 (`GetResource` -> `PumpMessages`), which
## throws away queued input. A Space in sub-steps 1-3 of the motion is lost; the wheel stays in its window.
func test_a_key_in_the_first_three_substeps_of_the_motion_is_lost() -> void:
	_to_motion_start()
	_lock.advance_ticks(26)                                                   # still in sub-step 3 (ticks 18-26)
	_lock._unhandled_input(_key(KEY_SPACE))
	_lock.advance_ticks(10)                                                   # the motion ends, the window opens
	assert_int(_lock.answer_wheel.state).is_equal(LockWheel.State.WAITING)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.ANSWER)            # nobody stopped it
	assert_array(_events).is_empty()


## A key typed in the last sub-step (the final 9 ticks of the 36) is still queued when the window opens and
## stops the wheel at once.
func test_a_key_in_the_last_substep_stops_the_wheel_when_the_window_opens() -> void:
	_to_motion_start()
	_lock.advance_ticks(27)                                                   # sub-step 4 begins (its sound has been loaded)
	_lock._unhandled_input(_key(KEY_SPACE))
	assert_int(_lock.answer_wheel.state).is_equal(LockWheel.State.MOVING)    # not yet: the window is closed
	_lock.advance_ticks(8)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.ANSWER)
	_lock.advance_ticks(1)                                                    # tick 36: the window opens and takes the key
	assert_array(_events).is_equal(["ERROR"])                                 # (label 7 is under the arrow, not the answer)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.MISS_REASON)


func test_with_the_sound_off_a_key_survives_the_whole_motion() -> void:
	_lock.sound_is_on = func() -> bool: return false                          # `PlaySoundEffect` loads nothing: no `PumpMessages`
	_to_motion_start()
	_lock._unhandled_input(_key(KEY_ENTER))
	_lock.advance_ticks(35)
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.ANSWER)
	_lock.advance_ticks(1)
	assert_array(_events).is_equal(["ERROR"])


func test_the_sound_on_default_follows_the_sfx_bus() -> void:
	assert_bool(_lock.sound_is_on.call()).is_equal(Audio.is_bus_enabled(Audio.SFX))


## `AddHotspot(0xd, 116, 58, 113, 47)`: the stop button is a rectangle, a click counts when the left button is released in it.
func test_the_stop_button_is_the_rectangle_116_58_113_47_and_acts_on_release() -> void:
	_to_answer_wheel()
	_until(func() -> bool: return _lock.answer_wheel.is_waiting_for_key())
	assert_object(CombinationLock.STOP_BUTTON).is_equal(Rect2(116, 58, 113, 47))
	_lock._unhandled_input(_click(Vector2(60, 100), false))                   # on the wheel disc but outside the rectangle
	_lock._unhandled_input(_click(Vector2(230, 80), false))                   # just right of it
	_lock._unhandled_input(_click(Vector2(150, 106), false))                  # just below it
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.ANSWER)
	_lock._unhandled_input(_click(Vector2(150, 80), true))                    # the press alone does nothing
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.ANSWER)
	_lock._unhandled_input(_click(Vector2(116, 58), false))                   # the release inside stops it
	assert_int(_lock.phase).is_not_equal(CombinationLock.Phase.ANSWER)
	assert_array(_events).is_equal(["ERROR"])


# --- Space outside the answer wheel's key window ----------------------------------------------------------

## Parses a press and a release of Space through the viewport, like the window.
func _type_space() -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.physical_keycode = KEY_SPACE
		key.pressed = pressed
		Input.parse_input_event(key)
		await await_idle_frame()


## Original: nothing reads Space outside the answer wheel's key window (`LockRunStage` (0x421dc9) peeks at the keys only there;
## `WaitForInput` (0x415b6c) in the intro and `WaitKeyOrTicks` (0x423549) in the messages drop it; `FlushInput` (0x410c6c) clears
## what is left before the wheel starts and after each window). The lock does nothing with it; that it does not reach the sub is
## `Sub`'s rule (test_game_flow.gd: nothing fires while the clock is held).
func test_space_before_the_answer_wheel_does_nothing() -> void:
	await _type_space()                                                       # the intro
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.INTRO)
	_lock.press_key()
	_lock.advance_ticks(1)
	await _type_space()                                                       # the operand wheel turns
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.OPERANDS)
	_until_reveal()
	await _type_space()                                                       # the operator is held back
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.REVEAL)
	_until(func() -> bool: return _lock.phase == CombinationLock.Phase.ANSWER)
	assert_array(_events).is_empty()
	assert_bool(_lock._stop_pending).is_false()                               # (nothing waits for the key window)


func test_space_in_the_messages_does_not_end_them() -> void:
	_to_answer_wheel()
	var target := LockWheel.target_position(_lock.answer_wheel.target_slot)
	_until(func() -> bool: return _lock.answer_wheel.is_waiting_for_key() and _lock.answer_wheel.position == target)
	_lock.press_key()                                                         # stop on the right label: "First number accepted ..."
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.NOTICE)
	await _type_space()
	assert_int(_lock.phase).is_equal(CombinationLock.Phase.NOTICE)            # only Enter, a click or the 2 s end it


# --- the operand wheel's window --------------------------------------------------------------------------

func _window_items() -> Array:
	return _diagram.items.filter(func(item: DiagramItem) -> bool: return item.kind == DiagramItem.Kind.PICTURE and item.pic == 10)


## `LockSpinOperandWheel` (0x421c6c) draws the window (item 10 of the bundle, 80 x 44, dark) over the top of the wheel once it has stopped, then the
## chosen label on it; the window stays while the operator is revealed. The next spin's first `LockDrawOperandWheel` (0x421a81) paints over
## it, and so does the redraw `LockRunStage` (0x421dc9) makes after the "=" and before the answer wheel turns.
func test_the_window_is_over_the_operand_wheel_between_its_stop_and_its_next_move() -> void:
	assert_array(_window_items()).is_empty()                                  # the resting lock has none
	_lock.press_key()
	_until_reveal()
	var window := _window_items()
	assert_int(window.size()).is_equal(1)
	assert_vector((window[0] as DiagramItem).position).is_equal(Vector2(_diagram.spec["operand_wheel"]["window"]["pos"][0], _diagram.spec["operand_wheel"]["window"]["pos"][1]))
	# it is drawn after every label of the wheels (the 16 are the 8 + 8 before it), and the chosen number is written over it
	var window_index := _diagram.items.find(window[0])
	var labels_before := _diagram.items.slice(0, window_index).filter(func(item: DiagramItem) -> bool: return item.kind == DiagramItem.Kind.TEXT)
	assert_int(labels_before.size()).is_equal(16)
	var chosen := _diagram.items[window_index + 1] as DiagramItem
	assert_int(chosen.kind).is_equal(DiagramItem.Kind.TEXT)
	assert_str(chosen.text).is_equal(_program().operands[0])
	_until(func() -> bool: return _lock.phase == CombinationLock.Phase.OPERANDS)
	assert_array(_window_items()).is_empty()                                  # the second number's wheel moves
	_until_reveal()
	assert_int(_window_items().size()).is_equal(1)
	_until(func() -> bool: return _lock.phase == CombinationLock.Phase.ANSWER)
	assert_array(_window_items()).is_empty()                                  # the answer wheel's turn: the operand wheel was redrawn
