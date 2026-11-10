class_name TestProblemSession
extends GdUnitTestSuite
## Teaches: testing a state machine by walking every path through it
## (DESIGN 5.2: right / wrong+right / wrong+wrong, each wrong answer costs 1 oxygen).

var _session: ProblemSession


func before_test() -> void:
	# Type 6, level 2, record 0 of the chain's pack: whatever its answer is, `_right()` types it.
	_session = ProblemSession.new(ProblemFactory.make(6, 2, null, 0))


func _answer(text: String) -> NumberValue:
	return NumberValue.parse(text)


## The right answer of the problem on the table, typed as the player would.
func _right() -> NumberValue:
	return _session.instance.expected


## Two numbers no record stores as an answer (the stored ones are small).
func _wrong(second: bool = false) -> NumberValue:
	return _answer("98766" if second else "98765")


func test_correct_at_the_first_try_costs_nothing() -> void:
	assert_int(_session.submit(_right())).is_equal(ProblemSession.Outcome.CORRECT_FIRST)
	assert_int(_session.oxygen_lost()).is_equal(0)
	assert_bool(_session.finished).is_true()
	assert_bool(_session.solved).is_true()


func test_wrong_then_right_loses_one_oxygen_and_shows_the_hint_in_between() -> void:
	assert_int(_session.submit(_wrong())).is_equal(ProblemSession.Outcome.WRONG_HINT)
	assert_int(_session.oxygen_lost()).is_equal(1)
	assert_bool(_session.finished).is_false()
	assert_int(_session.submit(_right())).is_equal(ProblemSession.Outcome.CORRECT_SECOND)
	assert_int(_session.oxygen_lost()).is_equal(1)          # no further penalty
	assert_bool(_session.solved).is_true()


func test_wrong_wrong_loses_two_oxygen_and_ends_the_problem() -> void:
	_session.submit(_wrong())
	assert_int(_session.submit(_wrong(true))).is_equal(ProblemSession.Outcome.WRONG_SOLUTION)
	assert_int(_session.oxygen_lost()).is_equal(2)
	assert_bool(_session.finished).is_true()
	assert_bool(_session.solved).is_false()


func test_nothing_more_can_be_submitted_after_the_end() -> void:
	_session.submit(_right())
	assert_int(_session.submit(_wrong())).is_equal(ProblemSession.Outcome.ALREADY_OVER)
	assert_int(_session.oxygen_lost()).is_equal(0)


func test_unparseable_input_does_not_use_up_an_attempt() -> void:
	assert_int(_session.submit(null)).is_equal(ProblemSession.Outcome.INVALID)
	assert_int(_session.oxygen_lost()).is_equal(0)
	assert_int(_session.submit(_right())).is_equal(ProblemSession.Outcome.CORRECT_FIRST)


func test_ballast_session_uses_a_selection_mask() -> void:
	# Dev's ballast 28, level 0, record 0: target 4 with the weights 1, 2, 3, ... 10 (`dev_problems.ballast_record`).
	var session := ProblemSession.new(ProblemFactory.make(28, 0, null, 0))
	assert_int(session.instance.record.int_at(0)).is_equal(4)
	assert_int(session.submit(0b0000110)).is_equal(ProblemSession.Outcome.WRONG_HINT)   # 2 + 3
	assert_int(session.submit(0b0000101)).is_equal(ProblemSession.Outcome.CORRECT_SECOND)   # 1 + 3
