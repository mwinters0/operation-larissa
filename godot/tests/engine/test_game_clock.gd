class_name TestGameClock
extends GdUnitTestSuite
## Teaches: testing time-dependent code without waiting. The clock is fed
## made-up frame times ("simulated frames") instead of real ones.

const GameClockScript := preload("res://src/autoload/game_clock.gd")


## A fresh clock that is not in the scene tree, so its `_process` never runs by itself.
func _new_clock() -> Node:
	return auto_free(GameClockScript.new())


## Feeds `seconds` of simulated 60 fps frames; returns the number of ticks emitted.
func _run(clock: Node, seconds: float) -> int:
	var ticks := 0
	for frame in roundi(seconds * 60.0):
		ticks += clock.advance(1.0 / 60.0)
	return ticks


func test_one_second_gives_12_or_13_ticks() -> void:
	var ticks := _run(_new_clock(), 1.0)
	assert_int(ticks).is_between(12, 13)


func test_long_run_matches_12_17_hz() -> void:
	# 100 simulated seconds must give 1216.7 ticks, within 2 %.
	var ticks := _run(_new_clock(), 100.0)
	assert_float(float(ticks)).is_between(1216.7 * 0.98, 1216.7 * 1.02)


func test_tick_signal_carries_running_count() -> void:
	var clock := _new_clock()
	var counts: Array[int] = []
	clock.tick.connect(func(count: int) -> void: counts.append(count))
	_run(clock, 0.5)
	assert_array(counts).is_equal([1, 2, 3, 4, 5, 6])


func test_no_ticks_while_paused() -> void:
	var clock := _new_clock()
	clock.paused = true
	assert_int(_run(clock, 2.0)).is_equal(0)
	assert_int(clock.tick_count).is_equal(0)
	# And it runs again afterwards, without a burst of "caught up" ticks.
	clock.paused = false
	assert_int(_run(clock, 1.0)).is_between(12, 13)


func test_stall_does_not_cause_a_burst() -> void:
	var clock := _new_clock()
	# A 10 second hiccup must not fire 120 ticks at once.
	assert_int(clock.advance(10.0)).is_equal(GameClockScript.MAX_TICKS_PER_ADVANCE)


func test_a_hold_taken_by_a_tick_stops_the_ticks_still_owed_in_the_same_frame() -> void:
	# A stalled frame owes several ticks. The listener of the first one opens a cover (a problem screen): the others must not
	# run behind it, and must not be paid back as a burst when it goes.
	var clock := _new_clock()
	var counts: Array[int] = []
	clock.tick.connect(func(count: int) -> void:
		counts.append(count)
		if count == 1:
			clock.hold())
	assert_int(clock.advance(10.0)).is_equal(1)
	assert_array(counts).is_equal([1])
	assert_float(clock.tick_fraction()).is_equal(1.0)               # (held: drawn at the logic position)
	clock.release()
	assert_int(clock.advance(0.0)).is_equal(0)                      # nothing is left over to fire at once
	assert_int(clock.advance(1.0 / 60.0)).is_equal(0)


func test_step_ticks_once_even_when_paused() -> void:
	var clock := _new_clock()
	clock.paused = true
	clock.step()
	assert_int(clock.tick_count).is_equal(1)


func test_holds_stop_the_clock_until_the_last_one_is_released() -> void:
	var clock := _new_clock()
	clock.hold()                                   # a message box
	clock.hold()                                   # a problem screen
	assert_bool(clock.paused).is_true()
	assert_int(_run(clock, 1.0)).is_equal(0)
	clock.release()                                # the box closes first, the screen is still up
	assert_bool(clock.paused).is_true()
	clock.release()
	assert_bool(clock.paused).is_false()
	assert_int(_run(clock, 1.0)).is_greater(10)


func test_the_order_of_releasing_does_not_matter_and_extra_releases_are_ignored() -> void:
	var clock := _new_clock()
	clock.release()                                # nothing held: no negative count
	clock.hold()
	clock.release()
	clock.hold()
	assert_bool(clock.paused).is_true()
	clock.release()
	assert_bool(clock.paused).is_false()


func test_the_plain_switch_and_the_holds_are_independent_and_false_clears_both() -> void:
	var clock := _new_clock()
	clock.paused = true
	clock.hold()
	clock.release()
	assert_bool(clock.paused).is_true()            # the switch is still on
	clock.hold()
	clock.paused = false                           # the hard reset of a new scene or test
	assert_bool(clock.paused).is_false()
	assert_int(clock.holds).is_equal(0)
