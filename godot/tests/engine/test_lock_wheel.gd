class_name TestLockWheel
extends GdUnitTestSuite
## Teaches: testing time-based logic by stepping a counter. No real seconds pass here: `advance(ticks)`
## is the clock, so 872 ticks (one revolution, 11.95 s) take a fraction of a millisecond.


func test_the_original_timing_numbers() -> void:
	var wheel := LockWheel.new(0, Tuning.original())
	assert_int(wheel.ticks_per_position).is_equal(9)
	assert_int(wheel.key_window_ticks).is_equal(73)
	assert_int(wheel.max_passes).is_equal(2)
	assert_int(wheel.motion_ticks()).is_equal(36)
	assert_int(wheel.ticks_per_label()).is_equal(109)
	assert_int(wheel.ticks_per_revolution()).is_equal(872)
	assert_float(wheel.ticks_per_revolution() / LockWheel.TICKS_PER_SECOND).is_equal_approx(11.95, 0.01)
	assert_float(wheel.ticks_per_label() / LockWheel.TICKS_PER_SECOND).is_equal_approx(1.49, 0.01)


func test_the_target_position_of_each_label() -> void:
	assert_int(LockWheel.target_position(0)).is_equal(0)
	assert_int(LockWheel.target_position(1)).is_equal(28)
	assert_int(LockWheel.target_position(7)).is_equal(4)


func test_the_wheel_moves_one_label_in_36_ticks_then_waits_73() -> void:
	var wheel := LockWheel.new(7, Tuning.original())
	assert_int(wheel.state).is_equal(LockWheel.State.MOVING)
	wheel.advance(35)
	assert_int(wheel.state).is_equal(LockWheel.State.MOVING)
	assert_int(wheel.position).is_equal(3)                     # a quarter label per 9 ticks
	wheel.advance(1)
	assert_int(wheel.state).is_equal(LockWheel.State.WAITING)
	assert_int(wheel.position).is_equal(4)
	wheel.advance(72)
	assert_int(wheel.state).is_equal(LockWheel.State.WAITING)
	wheel.advance(1)
	assert_int(wheel.state).is_equal(LockWheel.State.MOVING)   # the window closed, the next label comes
	assert_int(wheel.elapsed_ticks).is_equal(109)


func test_keys_are_ignored_while_the_wheel_moves() -> void:
	var wheel := LockWheel.new(7, Tuning.original())
	wheel.advance(20)
	assert_bool(wheel.press_stop()).is_false()
	assert_int(wheel.state).is_equal(LockWheel.State.MOVING)


func test_stopping_on_the_right_label_is_right() -> void:
	var wheel := LockWheel.new(7, Tuning.original())                              # label 7 is under the arrow at position 4
	wheel.advance(36 + 10)
	assert_bool(wheel.press_stop()).is_true()
	assert_int(wheel.state).is_equal(LockWheel.State.RIGHT)
	assert_bool(wheel.is_finished()).is_true()


func test_stopping_on_another_label_is_an_error() -> void:
	var wheel := LockWheel.new(6, Tuning.original())                              # needs position 8; the first window is at 4
	wheel.advance(36 + 10)
	wheel.press_stop()
	assert_int(wheel.state).is_equal(LockWheel.State.WRONG)


func test_label_zero_comes_after_a_whole_revolution() -> void:
	var wheel := LockWheel.new(0, Tuning.original())
	wheel.advance(wheel.ticks_per_revolution() - wheel.key_window_ticks + 1)   # 8th motion done: position 0 again
	assert_int(wheel.position).is_equal(0)
	assert_int(wheel.state).is_equal(LockWheel.State.WAITING)
	assert_int(wheel.label_under_arrow()).is_equal(0)
	assert_bool(wheel.press_stop()).is_true()
	assert_int(wheel.state).is_equal(LockWheel.State.RIGHT)


func test_two_unused_passes_of_the_right_position_end_in_out_of_time() -> void:
	var wheel := LockWheel.new(7, Tuning.original())
	wheel.advance(109)                                         # first pass: window at position 4 closes unused
	assert_int(wheel.passes).is_equal(1)
	assert_int(wheel.state).is_equal(LockWheel.State.MOVING)
	wheel.advance(wheel.ticks_per_revolution())              # a whole revolution later: second pass
	assert_int(wheel.state).is_equal(LockWheel.State.TIMED_OUT)
	assert_int(wheel.passes).is_equal(2)


func test_wrong_windows_do_not_count_as_passes() -> void:
	var wheel := LockWheel.new(7, Tuning.original())
	wheel.advance(109 * 3)                                     # windows at 4, 8, 12 (only 4 is right)
	assert_int(wheel.passes).is_equal(1)


func test_the_operand_wheel_spins_nine_ticks_per_quarter_in_a_direction() -> void:
	var spin := LockWheel.Spin.new(0, 12, 1, Tuning.original())
	assert_int(spin.steps).is_equal(12)
	assert_int(spin.total_ticks()).is_equal(108)
	spin.advance(27)
	assert_int(spin.position()).is_equal(3)
	spin.advance(1000)
	assert_bool(spin.is_finished()).is_true()
	assert_int(spin.position()).is_equal(12)
	var back := LockWheel.Spin.new(4, 28, -1, Tuning.original())                   # the long way round the other direction: 8 steps
	assert_int(back.steps).is_equal(8)
	back.advance(back.total_ticks())
	assert_int(back.position()).is_equal(28)


func test_a_spin_to_the_number_already_under_the_arrow_is_a_full_revolution() -> void:
	# `LockSpinOperandWheel` moves first and compares afterwards: 32 steps of 9 ticks, not none.
	var spin := LockWheel.Spin.new(12, 12, 1, Tuning.original())
	assert_int(spin.total_ticks()).is_equal(32 * 9)
	spin.advance(32 * 9)
	assert_int(spin.position()).is_equal(12)
	assert_bool(spin.is_finished()).is_true()
