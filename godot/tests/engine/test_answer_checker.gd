class_name TestAnswerChecker
extends GdUnitTestSuite
## Teaches: testing the comparison rules (DESIGN 5.2 item 7) one rule at a time, each on a problem type the test makes itself (`ProblemKit`): the
## rules are the engine's, the numbers are the test's. `ProblemKit.accepts(type, "typed text")` plays the player.
## The original's own types (which of its 34 are compared by kind or by a tolerance) are checked in tests/legacy/test_answer_checker_legacy.gd.

const K = preload("res://tests/engine/problem_kit.gd")


# --- exact: fractions and decimals are interchangeable --------------------------

func test_exact_answer_accepts_any_spelling_of_the_same_number() -> void:
	var type := K.type_of("exact", "n", 0, [K.flat([K.decimal(40.0)])])
	assert_bool(K.accepts(type, "40")).is_true()
	assert_bool(K.accepts(type, "40.0")).is_true()
	assert_bool(K.accepts(type, "80/2")).is_true()
	assert_bool(K.accepts(type, "39")).is_false()
	var quarter := K.type_of("exact", "n", 0, [K.flat([K.fraction(0, 1, 4)])])
	assert_bool(K.accepts(quarter, "2/8")).is_true()              # the same number ...
	assert_bool(K.accepts(quarter, "0.25")).is_true()             # ... and the same value in decimals (the kind is not checked)
	assert_bool(K.accepts(quarter, ".25")).is_true()
	assert_bool(K.accepts(quarter, "0.26")).is_false()


func test_a_tiny_difference_is_a_wrong_answer_for_exact_types() -> void:
	var type := K.type_of("exact", "n", 0, [K.flat([K.decimal(40.0)])])
	assert_bool(K.accepts(type, "40.000001")).is_false()


func test_the_answer_field_is_the_one_the_type_names() -> void:
	var type := K.type_of("exact", "cnn", 2, [K.flat([7, K.decimal(1.0), K.decimal(2.5)])])
	assert_bool(K.accepts(type, "2.5")).is_true()
	assert_bool(K.accepts(type, "7")).is_false()
	assert_bool(K.accepts(type, "1")).is_false()


# --- kind rules -----------------------------------------------------------------

func test_a_kind_checked_level_must_be_typed_as_a_fraction_when_the_record_is_one() -> void:
	var type := K.type_of("exact", "n", 0, [K.flat([K.fraction(0, 3, 7)])], 0.0, true)
	assert_bool(K.accepts(type, "3/7")).is_true()
	assert_bool(K.accepts(type, "6/14")).is_true()
	assert_bool(K.accepts(type, "0.428571428")).is_false()         # the right value, the wrong kind
	assert_bool(K.accepts(type, "0.4285714286")).is_false()


func test_a_kind_checked_level_must_be_typed_as_a_decimal_when_the_record_is_one() -> void:
	var type := K.type_of("exact", "n", 0, [K.flat([K.decimal(0.5)])], 0.0, true)
	assert_bool(K.accepts(type, "0.5")).is_true()
	assert_bool(K.accepts(type, "1/2")).is_false()


func test_a_level_that_is_not_kind_checked_takes_either_kind() -> void:
	var type := K.type_of("exact", "n", 0, [K.flat([K.decimal(75.0, 0)])])
	assert_bool(K.accepts(type, "75")).is_true()
	assert_bool(K.accepts(type, "3/4")).is_false()                 # that is 0.75, not 75: wrong by value
	var by_level := K.type_of("exact", "n", 0, [K.flat([K.fraction(0, 1, 2)]), K.flat([K.fraction(0, 1, 2)])], 0.0, false, [0, 1])
	by_level.kind_checked_levels = PackedInt32Array([1])           # only level 1 insists
	assert_bool(K.accepts(by_level, "0.5", 0)).is_true()
	assert_bool(K.accepts(by_level, "0.5", 1)).is_false()
	assert_bool(K.accepts(by_level, "1/2", 1)).is_true()


# --- tolerances -------------------------------------------------------------------

func test_close_tolerance_is_absolute() -> void:
	var type := K.type_of("close", "n", 0, [K.flat([K.decimal(10.0, 0)])], 0.01)
	assert_bool(K.accepts(type, "10.01")).is_true()
	assert_bool(K.accepts(type, "9.99")).is_true()
	assert_bool(K.accepts(type, "10.02")).is_false()
	assert_bool(K.accepts(type, "9.98")).is_false()


func test_near_tolerance_is_relative_to_the_stored_answer() -> void:
	var type := K.type_of("near", "n", 0, [K.flat([K.decimal(4.0, 0)])], 0.03)
	assert_bool(K.accepts(type, "4.1")).is_true()                  # 4 +- 0.12
	assert_bool(K.accepts(type, "3.9")).is_true()
	assert_bool(K.accepts(type, "4.2")).is_false()
	var large := K.type_of("near", "n", 0, [K.flat([K.decimal(400.0, 0)])], 0.03)
	assert_bool(K.accepts(large, "411")).is_true()                 # 400 +- 12
	assert_bool(K.accepts(large, "413")).is_false()


func test_a_tolerance_of_zero_is_exact_even_in_a_tolerant_mode() -> void:
	for mode in ["near", "close"]:
		var type := K.type_of(mode, "n", 0, [K.flat([K.decimal(9.0, 0)])], 0.0)
		assert_bool(K.accepts(type, "9")).is_true()
		assert_bool(K.accepts(type, "9.1")).is_false()


func test_each_level_has_its_own_tolerance() -> void:
	var type := K.type_of("close", "n", 0, [K.flat([K.decimal(6.0, 0)]), K.flat([K.decimal(6.0, 0)]), K.flat([K.decimal(6.0, 0)])], 0.0, false, [0, 1, 2])
	type.tolerances = PackedFloat64Array([0.0, 0.5, 0.2, 0.0])
	assert_bool(K.accepts(type, "6.1", 0)).is_false()              # level 0 is exact
	assert_bool(K.accepts(type, "6.5", 1)).is_true()
	assert_bool(K.accepts(type, "6.6", 1)).is_false()
	assert_bool(K.accepts(type, "6.2", 2)).is_true()
	assert_bool(K.accepts(type, "6.3", 2)).is_false()


func test_the_edge_of_a_tolerance_is_inside_in_spite_of_floating_point() -> void:
	# 2.2 - 2.0 is 0.20000000000000018 in floating point: a player who types exactly the edge is right
	var type := K.type_of("close", "n", 0, [K.flat([K.decimal(2.0, 0)])], 0.2)
	assert_bool(K.accepts(type, "2.2")).is_true()
	assert_bool(K.accepts(type, "1.8")).is_true()
	assert_bool(K.accepts(type, "2.3")).is_false()


func test_a_mixed_number_with_a_tolerance() -> void:
	# the record stores -6 2/3 (= -6.6667): -6.67 is within 0.01, -6.7 is not
	var type := K.type_of("close", "n", 0, [K.flat([K.fraction(-6, -2, 3)])], 0.01)
	assert_bool(K.accepts(type, "-6.67")).is_true()
	assert_bool(K.accepts(type, "-6 2/3")).is_true()
	assert_bool(K.accepts(type, "-6.7")).is_false()


func test_a_tolerance_and_a_kind_rule_together() -> void:
	var type := K.type_of("close", "n", 0, [K.flat([K.decimal(33.0, 0)])], 0.7, true)
	assert_bool(K.accepts(type, "33.6")).is_true()
	assert_bool(K.accepts(type, "32.2")).is_false()
	assert_bool(K.accepts(type, "33")).is_true()
	assert_bool(K.accepts(type, "66/2")).is_false()                # the right value, but a fraction where a decimal is stored


# --- a range -----------------------------------------------------------------------

func test_a_range_takes_anything_strictly_between_the_stored_bounds_above_level_0() -> void:
	# fields: depth, the exact answer of level 0, the low and the high bound
	var type := K.type_of("range", "wwww", 1, [K.flat([40, 15, 10, 20]), K.flat([40, 15, 10, 20])], 0.0, false, [0, 1])
	type.extras = {"range_fields": PackedInt32Array([2, 3])}
	assert_bool(K.accepts(type, "15", 0)).is_true()                # level 0 is the exact field
	assert_bool(K.accepts(type, "16", 0)).is_false()
	assert_bool(K.accepts(type, "15", 1)).is_true()                # level 1: anything between
	assert_bool(K.accepts(type, "10.1", 1)).is_true()
	assert_bool(K.accepts(type, "19.9", 1)).is_true()
	assert_bool(K.accepts(type, "10", 1)).is_false()               # the bounds themselves are out
	assert_bool(K.accepts(type, "20", 1)).is_false()
	assert_bool(K.accepts(type, "25", 1)).is_false()


func test_a_range_level_has_no_single_expected_answer() -> void:
	var type := K.type_of("range", "wwww", 1, [K.flat([40, 15, 10, 20])])
	type.answer_fields = PackedInt32Array([1, -1, -1, -1])
	assert_object(AnswerChecker.expected(type, 0, type.record(0, 0))).is_not_null()
	assert_object(AnswerChecker.expected(type, 1, type.record(0, 0))).is_null()


func test_nothing_typed_is_wrong() -> void:
	var type := K.type_of("exact", "n", 0, [K.flat([K.decimal(1.0, 0)])])
	assert_bool(AnswerChecker.check(type, 0, type.record(0, 0), null)).is_false()


# --- ballast (the sum of the chosen weights) ------------------------------------------

func test_ballast_accepts_any_selection_with_the_right_sum() -> void:
	# dev's type 28, level 0, record 0: target 4 with the weights 1, 2, 3 ... 10 (`dev_problems.ballast_record`)
	var type := Catalog.problem_type(28)
	var r := type.record(0, 0)
	assert_int(r.int_at(0)).is_equal(4)
	assert_bool(AnswerChecker.check_selection(type, 0, r, 0b101)).is_true()          # 1 + 3
	assert_bool(AnswerChecker.check_selection(type, 0, r, 0b1000)).is_true()         # 4 alone
	assert_bool(AnswerChecker.check_selection(type, 0, r, 0b110)).is_false()         # 2 + 3 = 5
	assert_bool(AnswerChecker.check_selection(type, 0, r, 0)).is_false()


func test_ballast_sums_what_the_levels_denominations_are() -> void:
	var type := Catalog.problem_type(28)
	assert_array(Array(AnswerChecker.denominations(type, 0))).is_equal(range(1, 11))
	assert_array(Array(AnswerChecker.denominations(type, 1))).is_equal([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])
	assert_int(AnswerChecker.selection_sum(type, 1, 0b1011)).is_equal(1 + 2 + 8)
	assert_str(AnswerChecker.denomination_labels(type, 2)[7]).is_equal("80")


func test_a_ballast_type_of_the_tests_own_reads_its_denominations_from_its_extras() -> void:
	var type := K.type_of("sum", "ww", -1, [K.flat([6, 0b11])])
	type.extras = {"mode_by_level": PackedInt32Array([0, 1, 0, 0]),
			"values": {"0": PackedInt32Array([1, 5, 10]), "1": PackedInt32Array([2, 2, 2])},
			"labels": {"0": PackedStringArray(["a", "b", "c"]), "1": PackedStringArray(["x", "y", "z"])}}
	assert_array(Array(AnswerChecker.denominations(type, 0))).is_equal([1, 5, 10])
	assert_array(Array(AnswerChecker.denominations(type, 1))).is_equal([2, 2, 2])
	assert_str(AnswerChecker.denomination_labels(type, 1)[2]).is_equal("z")
	assert_bool(AnswerChecker.check_selection(type, 0, type.record(0, 0), 0b011)).is_true()    # 1 + 5 = 6
	assert_bool(AnswerChecker.check_selection(type, 0, type.record(0, 0), 0b101)).is_false()   # 1 + 10
