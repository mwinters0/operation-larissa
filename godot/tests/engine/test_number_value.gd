class_name TestNumberValue
extends GdUnitTestSuite
## Teaches: table-style tests with a loop over cases, for a small pure value class.


func test_parse_whole_decimal_fraction_and_mixed() -> void:
	var cases := {
		"3": 3.0, "-2.5": -2.5, ".5": 0.5, "0.50": 0.5, "3/4": 0.75, "1 3/4": 1.75,
		"-1 3/4": -1.75, "-3/4": -0.75, "27/100": 0.27, "123456789": 123456789.0,
	}
	for text in cases:
		var n := NumberValue.parse(text)
		assert_object(n).override_failure_message("parse(%s)" % text).is_not_null()
		assert_float(n.to_double()).override_failure_message("value of %s" % text).is_equal_approx(cases[text], 1e-12)


func test_parse_rejects_what_the_keys_cannot_produce() -> void:
	# empty, text, two points, 10 digits, 3-digit numerator, 4-digit denominator, denominator 0
	for text in ["", " ", "abc", "1.2.3", "1234567890", "1/2/3", "123/4", "1/1000", "1/0", "-", "1 2 3/4", "3/", "/4"]:
		assert_object(NumberValue.parse(text)).override_failure_message("'%s' must not parse" % text).is_null()


func test_one_half_is_the_same_number_however_it_is_written() -> void:
	var half := NumberValue.parse("1/2")
	for text in [".5", "0.5", "0.50", "2/4", "50/100", "0 1/2"]:
		assert_bool(half.equals(NumberValue.parse(text))).override_failure_message(text).is_true()
	assert_bool(half.equals(NumberValue.parse("0.51"))).is_false()


func test_parse_reads_one_or_two_spaces_in_a_mixed_number() -> void:
	for text in ["1 3/4", "1  3/4"]:
		assert_bool(NumberValue.fraction(1, 3, 4).equals(NumberValue.parse(text))).override_failure_message(text).is_true()
	assert_bool(NumberValue.parse(NumberValue.fraction(-6, -2, 3).to_text()).equals(NumberValue.fraction(-6, -2, 3))).is_true()


func test_equality_threshold_is_1e_minus_10() -> void:
	var a := NumberValue.decimal(333333333, 9)           # 0.333333333
	var third := NumberValue.fraction(0, 1, 3)
	assert_bool(a.equals(third)).is_false()              # differs by 3.3e-10: NOT the same answer
	assert_bool(NumberValue.decimal(5, 1).equals(NumberValue.decimal(50, 2))).is_true()


func test_kind_is_remembered_even_when_values_are_equal() -> void:
	assert_bool(NumberValue.parse("1/2").is_fraction()).is_true()
	assert_bool(NumberValue.parse(".5").is_fraction()).is_false()


func test_to_text_keeps_the_digits_of_the_original() -> void:
	assert_str(NumberValue.decimal(250, 2).to_text()).is_equal("2.50")
	assert_str(NumberValue.decimal(5, 2).to_text()).is_equal("0.05")
	assert_str(NumberValue.decimal(-5, 1).to_text()).is_equal("-0.5")
	assert_str(NumberValue.decimal(800, 0).to_text()).is_equal("800")
	assert_str(NumberValue.fraction(1, 3, 4).to_text()).is_equal("1  3/4")
	assert_str(NumberValue.fraction(0, 2, 16).to_text()).is_equal("2/16")        # not reduced
	assert_str(NumberValue.fraction(-6, -2, 3).to_text()).is_equal("-6  2/3")
	assert_str(NumberValue.fraction(0, -2, 3).to_text()).is_equal("-2/3")


func test_negative_mixed_number_stores_both_signs() -> void:
	var n := NumberValue.parse("-6 2/3")
	assert_int(n.whole).is_equal(-6)
	assert_int(n.numerator).is_equal(-2)
	assert_float(n.to_double()).is_equal_approx(-6.0 - 2.0 / 3.0, 1e-12)


func test_from_double_limits_to_nine_digits_and_drops_trailing_zeros() -> void:
	assert_str(NumberValue.from_double(2.5).to_text()).is_equal("2.5")
	assert_str(NumberValue.from_double(100.0).to_text()).is_equal("100")
	assert_str(NumberValue.from_double(-0.25).to_text()).is_equal("-0.25")
	assert_str(NumberValue.from_double(1.0 / 3.0).to_text()).is_equal("0.333333333")
	assert_str(NumberValue.from_double(12345.6789).to_text()).is_equal("12345.6789")


# --- rounding: `RoundHalfEven` (0x427f20), `NormalizeDecimal` (0x427fe8), `NumberToInt` (0x4283bc) ---------------------

func test_round_half_even_sends_exact_ties_to_the_even_neighbour() -> void:
	var ties := {0.5: 0.0, 1.5: 2.0, 2.5: 2.0, 3.5: 4.0, 4.5: 4.0, 100.5: 100.0, 101.5: 102.0,
			-0.5: 0.0, -1.5: -2.0, -2.5: -2.0, -3.5: -4.0, -4.5: -4.0, -101.5: -102.0}
	for x in ties:
		assert_float(NumberValue.round_half_even(x)).override_failure_message("round_half_even(%s)" % x).is_equal(ties[x])


func test_round_half_even_rounds_everything_else_to_the_nearest_whole_number() -> void:
	var cases := {0.0: 0.0, 0.3: 0.0, 0.49999: 0.0, 0.50001: 1.0, 1.2: 1.0, 1.7: 2.0, 2.4999: 2.0, 2.5001: 3.0,
			-0.3: 0.0, -0.50001: -1.0, -1.2: -1.0, -1.7: -2.0, -2.5001: -3.0, 5.0: 5.0, -5.0: -5.0,
			999999999.4: 999999999.0, 4503599627370495.0: 4503599627370495.0}
	for x in cases:
		assert_float(NumberValue.round_half_even(x)).override_failure_message("round_half_even(%s)" % x).is_equal(cases[x])


func test_round_half_even_every_tie_from_minus_50_to_50() -> void:
	for k in range(-50, 50):
		var even := k if k % 2 == 0 else k + 1             # of the two whole numbers around k + 0.5, the even one
		assert_float(NumberValue.round_half_even(k + 0.5)).override_failure_message("k = %d" % k).is_equal(float(even))


func test_the_old_roundf_sent_ties_away_from_zero() -> void:
	# The reason `from_double` no longer uses it: the original never does that.
	assert_float(roundf(2.5)).is_equal(3.0)
	assert_float(roundf(-2.5)).is_equal(-3.0)
	assert_float(NumberValue.round_half_even(2.5)).is_equal(2.0)


func test_to_int_is_number_to_int() -> void:
	assert_int(NumberValue.decimal(25, 1).to_int()).is_equal(2)          # 2.5 tie -> even
	assert_int(NumberValue.decimal(35, 1).to_int()).is_equal(4)          # 3.5 tie -> even
	assert_int(NumberValue.decimal(-25, 1).to_int()).is_equal(-2)
	assert_int(NumberValue.decimal(5, 1).to_int()).is_equal(0)           # 0.5
	assert_int(NumberValue.decimal(73, 2).to_int()).is_equal(1)          # 0.73
	assert_int(NumberValue.decimal(18, 1).to_int()).is_equal(2)          # 1.8: rounded, not cut
	assert_int(NumberValue.decimal(12, 1).to_int()).is_equal(1)
	assert_int(NumberValue.decimal(800).to_int()).is_equal(800)
	assert_int(NumberValue.fraction(2, 1, 2).to_int()).is_equal(2)       # 2 1/2
	assert_int(NumberValue.fraction(1, 1, 2).to_int()).is_equal(2)       # 1 1/2
	assert_int(NumberValue.fraction(-1, -1, 2).to_int()).is_equal(-2)    # -1 1/2


func test_a_number_field_of_a_record_is_read_with_number_to_int() -> void:
	var record := ProblemRecord.new("nnn", PackedInt64Array([0, 25, 1, 0,  0, 73, 2, 0,  1, 2, 1, 2]))
	assert_int(record.int_at(0)).is_equal(2)       # 2.5
	assert_int(record.int_at(1)).is_equal(1)       # 0.73 (the old cut gave 0)
	assert_int(record.int_at(2)).is_equal(2)       # 2 1/2


func test_the_sequence_step_of_the_canister_code_uses_the_rounded_integer() -> void:
	# `GetAccessHintSubst` (0x417b40) writes NumberToInt(step) into slot 4: 0.5 -> 0 (the old `roundi` gave 1), 1.5 -> 2, 2.5 -> 2, 0.73 -> 1.
	# Type 1's record is "nnnncnn" (four numbers, the pattern, the step, the answer); the test's own record in the pack's type 1.
	for pair: Array in [[0.5, "0"], [1.5, "2"], [2.5, "2"], [0.73, "1"]]:
		var record := PackedInt64Array(ProblemKit.decimal(1.0) + ProblemKit.decimal(2.0) + ProblemKit.decimal(3.0) + ProblemKit.decimal(4.0)
				+ [0] + ProblemKit.decimal(pair[0], 2) + ProblemKit.decimal(5.0))
		var type := ProblemKit.with_records(1, [record], 2)
		var wording := ProblemTexts.describe(type, 2, type.record(2, 0))
		assert_str(wording.hint_slots[4]).is_equal(pair[1])


func test_from_double_rounds_a_tie_at_the_ninth_digit_to_even() -> void:
	# exact ties in binary: ...25, ...5 and 2^-10 have a last digit 5 that the ninth digit cuts in half
	assert_str(NumberValue.from_double(12345678.25).to_text()).is_equal("12345678.2")        # 123456782.5 -> ...782 (roundf: ...783)
	assert_str(NumberValue.from_double(12345678.75).to_text()).is_equal("12345678.8")        # 123456787.5 -> ...788
	assert_str(NumberValue.from_double(123456788.5).to_text()).is_equal("123456788")         # (roundf: 123456789)
	assert_str(NumberValue.from_double(123456789.5).to_text()).is_equal("123456790")
	assert_str(NumberValue.from_double(-12345678.5).to_text()).is_equal("-12345678")         # a negative has one digit less (G18)
	assert_str(NumberValue.from_double(-12345679.5).to_text()).is_equal("-12345680")
	assert_str(NumberValue.from_double(0.0009765625).to_text()).is_equal("0.000976562")      # 2^-10: 976562.5 -> ...562 (roundf: ...563)


func test_from_double_keeps_what_is_not_a_tie() -> void:
	assert_str(NumberValue.from_double(0.5).to_text()).is_equal("0.5")
	assert_str(NumberValue.from_double(1.5).to_text()).is_equal("1.5")
	assert_str(NumberValue.from_double(-2.5).to_text()).is_equal("-2.5")
	assert_str(NumberValue.from_double(2.0 / 3.0).to_text()).is_equal("0.666666667")
	assert_str(NumberValue.from_double(123456789.4).to_text()).is_equal("123456789")
	assert_str(NumberValue.from_double(12345678.26).to_text()).is_equal("12345678.3")


# NormalizeDecimal (0x427fe8): the mantissa range is -99999999 .. 999999999, so a negative decimal keeps 8 significant
# digits where a positive one keeps 9 (DESIGN 5.2 item 7a, G18).
func test_a_negative_decimal_keeps_eight_digits_a_positive_nine() -> void:
	assert_str(NumberValue.from_double(1234567.89).to_text()).is_equal("1234567.89")
	assert_str(NumberValue.from_double(-1234567.89).to_text()).is_equal("-1234567.9")
	assert_str(NumberValue.from_double(1.0 / 3.0).to_text()).is_equal("0.333333333")
	assert_str(NumberValue.from_double(-1.0 / 3.0).to_text()).is_equal("-0.33333333")
	assert_str(NumberValue.from_double(-12345678.9).to_text()).is_equal("-12345679")
	assert_str(NumberValue.from_double(-99999999.0).to_text()).is_equal("-99999999")
	assert_str(NumberValue.from_double(-0.000123456789).to_text()).is_equal("-0.000123457")


func test_normalize_decimal_rounds_a_tie_to_even_for_negatives_too() -> void:
	assert_str(NumberValue.normalize_decimal(1, -123456785.0).to_text()).is_equal("-12345678")    # -12345678.5 -> even
	assert_str(NumberValue.normalize_decimal(1, -123456795.0).to_text()).is_equal("-12345680")    # -12345679.5 -> even
	assert_str(NumberValue.normalize_decimal(1, -123456786.0).to_text()).is_equal("-12345679")


func test_normalize_decimal_reports_too_large_as_a_negative_exponent() -> void:
	assert_bool(NumberValue.normalize_decimal(0, 1000000000.0).is_overflow()).is_true()
	assert_bool(NumberValue.normalize_decimal(0, 999999999.0).is_overflow()).is_false()
	assert_bool(NumberValue.normalize_decimal(0, -100000000.0).is_overflow()).is_true()
	assert_bool(NumberValue.normalize_decimal(0, -99999999.0).is_overflow()).is_false()
	# the number the original leaves behind: exponent -1, mantissa one digit short, rounded
	var left := NumberValue.normalize_decimal(0, -999999999.0)
	assert_int(left.decimals).is_equal(-1)
	assert_int(left.raw).is_equal(-100000000)
	assert_float(left.to_double()).is_equal(-1000000000.0)
	assert_str(left.to_text()).is_equal("-100000000")


func test_a_small_result_is_not_taken_for_zero() -> void:
	assert_str(NumberValue.normalize_decimal(6, 1.0).to_text()).is_equal("0.000001")
	assert_str(NumberValue.from_double(0.00001).to_text()).is_equal("0.00001")
