class_name TestCalculator
extends GdUnitTestSuite
## Teaches: driving a model with key sequences ("press 7, +, 8, =") and checking the display,
## which is exactly how a player uses the calculator.

var _calc: CalculatorModel


func before_test() -> void:
	_calc = CalculatorModel.new()


func _keys(sequence: String) -> void:
	for key in sequence:
		_calc.press(key)


## Presses the keys and returns every notice the model asked for (in order).
func _notices(sequence: String) -> Array:
	var notices: Array = []
	for key in sequence:
		var notice := _calc.press(key)
		if notice != CalculatorModel.Notice.NONE:
			notices.append(notice)
	return notices


func test_typing_digits_shows_them() -> void:
	_keys("123")
	assert_str(_calc.display_text()).is_equal("123")
	assert_float(_calc.value().to_double()).is_equal(123.0)


func test_addition_and_chaining() -> void:
	_keys("7+8=")
	assert_str(_calc.display_text()).is_equal("15")
	_keys("*2=")
	assert_str(_calc.display_text()).is_equal("30")


func test_operator_chaining_without_equals() -> void:
	_keys("2+3*4=")                 # left to right, like a pocket calculator: (2+3)*4
	assert_str(_calc.display_text()).is_equal("20")


func test_decimals() -> void:
	_keys("0.1+0.2=")
	assert_str(_calc.display_text()).is_equal("0.3")
	_calc.press("C")
	_calc.press("C")
	_keys(".5*4=")
	assert_str(_calc.display_text()).is_equal("2")


func test_division_gives_a_decimal_with_at_most_nine_digits() -> void:
	_keys("1/3=")
	assert_str(_calc.display_text()).is_equal("0.333333333")


func test_divide_by_zero_asks_for_a_notice_and_clears_the_calculator() -> void:
	# GetAnswer (0x41ade0): ShowCalcNoticeDialog(0), then Zero(), both operators dropped, the display shows 0
	assert_array(_notices("5/0=")).is_equal([CalculatorModel.Notice.DIVIDE_BY_ZERO])
	assert_str(_calc.display_text()).is_equal("0")
	assert_float(_calc.value().to_double()).is_equal(0.0)
	assert_str(_calc.pending_operator()).is_empty()
	_keys("7")                       # no error state: the next key just types
	assert_str(_calc.display_text()).is_equal("7")


func test_divide_by_zero_is_noticed_when_the_next_operator_comes_too() -> void:
	assert_array(_notices("8/0+")).is_equal([CalculatorModel.Notice.DIVIDE_BY_ZERO])
	assert_str(_calc.pending_operator()).is_empty()              # the + that triggered it is dropped as well


func test_the_memory_survives_a_notice() -> void:
	_keys("42S")
	_notices("5/0=")
	assert_bool(_calc.has_memory()).is_true()
	_keys("R")
	assert_str(_calc.display_text()).is_equal("42")


func test_too_large_result_asks_for_a_notice() -> void:
	assert_array(_notices("999999999*9=")).is_equal([CalculatorModel.Notice.TOO_LARGE])
	assert_str(_calc.display_text()).is_equal("0")


func test_the_negative_limit_is_one_digit_shorter() -> void:
	# NormalizeDecimal (0x427fe8): -99999999 .. 999999999
	assert_array(_notices("99999999N*1=")).is_empty()
	_calc.press("C")
	_calc.press("C")
	assert_array(_notices("99999999N*2=")).is_equal([CalculatorModel.Notice.TOO_LARGE])
	assert_array(_notices("999999999*1=")).is_empty()


func test_an_operator_inside_a_fraction_asks_for_a_notice_and_changes_nothing() -> void:
	# GetNumber state 1 (numerator): + - * = (calculator mode) -> ShowCalcNoticeDialog(2)
	_keys("3F1")
	for operator in ["+", "-", "*", "="]:
		assert_array(_notices(operator)).override_failure_message(operator).is_equal([CalculatorModel.Notice.FRACTION_OPERATOR])
	assert_str(_calc.display_text()).is_equal("3 1")            # the entry is still there, still in the numerator
	assert_bool(_calc.in_fraction_mode()).is_true()


func test_the_bar_goes_on_to_the_denominator_and_a_second_f_does_nothing() -> void:
	_keys("3F1F")
	assert_str(_calc.display_text()).is_equal("3 1")
	assert_array(_notices("/")).is_empty()                      # in the numerator "/" is the bar, not "divide"
	_keys("4")
	assert_str(_calc.display_text()).is_equal("3 1/4")


func test_the_bar_needs_a_numerator() -> void:
	_keys("3F")
	assert_array(_notices("/")).is_empty()                      # nothing happens, no dialog (0x420387)
	assert_str(_calc.display_text()).is_equal("3 ")


func test_in_the_denominator_an_operator_needs_a_usable_denominator() -> void:
	# state 2 (0x420641 ...): the denominator must have a first digit that is not 0, else notice 2; with one the key works
	_keys("F1/")
	assert_array(_notices("+")).is_equal([CalculatorModel.Notice.FRACTION_OPERATOR])
	_keys("0")
	assert_array(_notices("+")).is_equal([CalculatorModel.Notice.FRACTION_OPERATOR])      # "0" is no denominator
	_calc.press("C")
	_keys("F1/")
	_keys("2")
	assert_array(_notices("+")).is_empty()
	assert_str(_calc.pending_operator()).is_equal("+")


func test_a_denominator_starting_with_zero_is_refused_even_when_a_digit_follows() -> void:
	_keys("F1/05")
	assert_object(_calc.value()).is_null()                       # the original looks at the first digit only
	_calc.press("C")
	_keys("F1/50")
	assert_float(_calc.value().to_double()).is_equal(0.02)


func test_f_is_only_taken_after_at_most_two_characters_of_the_whole_part() -> void:
	_keys("123F")
	assert_bool(_calc.in_fraction_mode()).is_false()             # 0x41ff9f: digits + sign <= 2
	_calc.press("C")
	_keys("12F")
	assert_bool(_calc.in_fraction_mode()).is_true()
	_calc.press("C")
	_keys("1.5F")
	assert_bool(_calc.in_fraction_mode()).is_false()             # not after a decimal point


func test_only_nine_digits_can_be_typed() -> void:
	_keys("12345678901")
	assert_str(_calc.display_text()).is_equal("123456789")


func test_negate() -> void:
	_keys("5N")
	assert_str(_calc.display_text()).is_equal("-5")
	_keys("+3=")
	assert_str(_calc.display_text()).is_equal("-2")
	_keys("N")                       # negating a result
	assert_str(_calc.display_text()).is_equal("2")


func test_clear_once_removes_the_entry_twice_removes_everything() -> void:
	_keys("5+7")
	_calc.press("C")
	assert_str(_calc.display_text()).is_equal("5")      # the 7 is gone, 5 + is still pending
	_keys("1=")
	assert_str(_calc.display_text()).is_equal("6")
	_keys("+9")
	_calc.press("C")
	_calc.press("C")
	assert_str(_calc.display_text()).is_equal("0")
	_keys("4=")
	assert_str(_calc.display_text()).is_equal("4")      # the pending "+" is gone


func test_store_and_recall() -> void:
	_keys("42S")
	_keys("C")
	_keys("9+")
	_keys("R=")                      # R puts 42 in place of the second number
	assert_str(_calc.display_text()).is_equal("51")


func test_mixed_fraction_entry() -> void:
	_keys("3F1/4")
	assert_str(_calc.display_text()).is_equal("3 1/4")
	assert_bool(_calc.in_fraction_mode()).is_true()
	var v := _calc.value()
	assert_bool(v.is_fraction()).is_true()
	assert_float(v.to_double()).is_equal(3.25)
	assert_str(v.to_text()).is_equal("3  1/4")      # a value prints with two spaces (NumberToString), the entry above with one


func test_simple_fraction_has_no_whole_part() -> void:
	_keys("F3/4")
	assert_str(_calc.value().to_text()).is_equal("3/4")


func test_fraction_limits_two_digit_numerator_three_digit_denominator() -> void:
	_keys("F123/4567")
	assert_str(_calc.display_text()).is_equal("12/456")


func test_unfinished_fraction_has_no_value_and_blocks_operators() -> void:
	_keys("F3")
	assert_object(_calc.value()).is_null()
	assert_array(_notices("+")).is_equal([CalculatorModel.Notice.FRACTION_OPERATOR])


func test_negative_fraction_negates_whole_and_numerator() -> void:
	_keys("6F2/3N")
	var v := _calc.value()
	assert_int(v.whole).is_equal(-6)
	assert_int(v.numerator).is_equal(-2)


func test_two_fractions_stay_a_fraction() -> void:
	# UnifyNumberKinds (0x428264) -> AddFractions (0x4284bf) ... NormalizeFraction (0x4281b3)
	_keys("F1/2+")
	_keys("F1/4=")
	assert_bool(_calc.value().is_fraction()).is_true()
	assert_str(_calc.display_text()).is_equal("3/4")
	_keys("*")
	_keys("F2/3=")
	assert_str(_calc.display_text()).is_equal("1/2")                 # 3/4 * 2/3
	_keys("/")
	_keys("F1/4=")
	assert_str(_calc.display_text()).is_equal("2")                   # 1/2 / 1/4
	_calc.press("C")
	_calc.press("C")
	_keys("1F1/2+")
	_keys("2F3/4=")
	assert_str(_calc.display_text()).is_equal("4  1/4")              # a result has two spaces (NumberToString), one 16 px cell each: 1 1/2 + 2 3/4
	_keys("-")
	_keys("5F1/2=")
	assert_str(_calc.display_text()).is_equal("-1  1/4")             # a negative mixed number: whole and numerator both negative
	assert_float(_calc.value().to_double()).is_equal(-1.25)


func test_a_fraction_and_a_whole_number_stay_a_fraction() -> void:
	_keys("F1/2+1=")                  # 1 is a whole number in -9 .. 99: it becomes 1/1
	assert_bool(_calc.value().is_fraction()).is_true()
	assert_str(_calc.display_text()).is_equal("1  1/2")


func test_a_fraction_and_a_real_decimal_make_a_decimal() -> void:
	_keys("F1/2+0.25=")
	assert_bool(_calc.value().is_fraction()).is_false()
	assert_str(_calc.display_text()).is_equal("0.75")
	_calc.press("C")
	_calc.press("C")
	_keys("F1/2+100=")                # 100 is outside -9 .. 99: both become decimals
	assert_bool(_calc.value().is_fraction()).is_false()
	assert_str(_calc.display_text()).is_equal("100.5")


func test_a_fraction_result_must_fit_the_fraction_limits() -> void:
	# NormalizeFraction: whole -9 .. 99, numerator within 99, denominator up to 999
	assert_array(_notices("99F1/2+1=")).is_equal([CalculatorModel.Notice.TOO_LARGE])        # 100 1/2
	assert_array(_notices("F1/10+F1/20=")).is_empty()
	assert_str(_calc.display_text()).is_equal("3/20")
	_calc.press("C")
	_calc.press("C")
	assert_array(_notices("F1/99*F1/98=")).is_equal([CalculatorModel.Notice.TOO_LARGE])        # denominator 9702 > 999
	_calc.press("C")
	_calc.press("C")
	assert_array(_notices("9N-5F1/2=")).is_equal([CalculatorModel.Notice.TOO_LARGE])        # -14 1/2 (whole below -9)


func test_dividing_by_a_zero_fraction_is_a_division_by_zero() -> void:
	assert_array(_notices("1F1/2/F0/5=")).is_equal([CalculatorModel.Notice.DIVIDE_BY_ZERO])


func test_the_lcd_leaves_out_a_whole_part_of_zero_in_a_fraction() -> void:
	# FormatEntryText (0x4208d9)
	_keys("0F1/2")
	assert_str(_calc.display_text().strip_edges()).is_equal("1/2")
	_calc.press("C")
	_keys("F")
	assert_str(_calc.display_text()).is_equal("0")                   # nothing typed after the F: "0" (the buffer starts as " 0")
	_keys("3")
	assert_str(_calc.display_text()).is_equal("3")
	_keys("/45")
	assert_str(_calc.display_text()).is_equal("3/45")
	_calc.press("C")
	_keys("7F3")
	assert_str(_calc.display_text()).is_equal("7 3")


func test_nothing_happens_for_operators_and_enter_until_a_digit_is_typed() -> void:
	# GetNumber state 0: + - * / = and Enter need a digit of the entry (bf0 < 9), unless a result is shown
	for key in ["+", "-", "*", "/", "=", "Enter"]:
		assert_array(_notices(key)).is_empty()
		assert_str(_calc.pending_operator()).override_failure_message(key).is_empty()
		assert_bool(_calc.submit_ready).override_failure_message(key).is_false()
	_keys(".")
	_keys("+")                                                         # a point is no digit
	assert_str(_calc.pending_operator()).is_empty()
	_calc.press("C")
	_keys("5+")
	_keys("+")                                                         # the second + finds an empty entry: ignored
	_keys("=")
	assert_str(_calc.pending_operator()).is_equal("+")                 # still waiting for its second number
	assert_str(_calc.display_text()).is_equal("5")


func test_enter_submits_only_with_a_digit_or_a_result() -> void:
	_calc.press("Enter")
	assert_bool(_calc.submit_ready).is_false()
	_keys("7")
	_calc.press("Enter")
	assert_bool(_calc.submit_ready).is_true()
	_calc.press("Enter")                                               # the result is on the display: Enter submits it again
	assert_bool(_calc.submit_ready).is_true()
	_calc.press("C")
	_calc.press("C")                                                   # a fresh display again
	_calc.press("Enter")
	assert_bool(_calc.submit_ready).is_false()


func test_a_digit_after_a_result_starts_a_new_entry_also_after_recall() -> void:
	_keys("42S")
	_keys("C")
	_keys("R")
	_keys("5")
	assert_str(_calc.display_text()).is_equal("5")                     # not "425"


# G18: NormalizeDecimal (0x427fe8) keeps a mantissa of -99999999 .. 999999999, so a negative result has at most 8 digits.
func test_a_negative_result_keeps_eight_digits() -> void:
	_keys("0-1234567.89=")
	assert_str(_calc.display_text()).is_equal("-1234567.9")
	_keys("CC")
	_keys("1234567.89+0=")
	assert_str(_calc.display_text()).is_equal("1234567.89")        # the positive one keeps all nine
	_keys("CC")
	_keys("0-1/3=")
	assert_str(_calc.display_text()).is_equal("-0.33333333")
	_keys("CC")
	_keys("1/3=")
	assert_str(_calc.display_text()).is_equal("0.333333333")


func test_a_negative_result_rounds_a_tie_to_the_even_digit() -> void:
	_keys("0-12345678.5=")
	assert_str(_calc.display_text()).is_equal("-12345678")
	_keys("CC")
	_keys("0-12345679.5=")
	assert_str(_calc.display_text()).is_equal("-12345680")


func test_negate_ignores_the_overflow_of_normalize_decimal() -> void:
	# Negate (0x428845) throws away NormalizeDecimal's "too large": 999999999 -> exponent -1, mantissa -100000000
	_keys("999999999+0=")
	assert_array(_notices("N")).is_empty()
	assert_str(_calc.display_text()).is_equal("-100000000")
	assert_float(_calc.value().to_double()).is_equal(-1000000000.0)
	_keys("N")                                                      # back: 1000000000 is out of range again, same text shape
	assert_str(_calc.display_text()).is_equal("100000000")
	assert_float(_calc.value().to_double()).is_equal(1000000000.0)
	_keys("CC")
	_keys("99999999*10=")
	assert_str(_calc.display_text()).is_equal("999999990")
	_keys("N")
	assert_str(_calc.display_text()).is_equal("-99999999")          # the last digit of -999999990 is gone from the text
	assert_float(_calc.value().to_double()).is_equal(-999999990.0)


func test_negate_within_the_limit_is_exact() -> void:
	_keys("99999999+0=N")
	assert_str(_calc.display_text()).is_equal("-99999999")
	assert_float(_calc.value().to_double()).is_equal(-99999999.0)
	_keys("CC")
	_keys("1.50+0=N")
	assert_str(_calc.display_text()).is_equal("-1.5")


func test_negate_of_a_fraction_cancels_it_and_ignores_the_limit() -> void:
	# Negate (0x428845) -> NormalizeFraction (0x4281b3): cancels; a whole part of -99 is below -9 but is kept
	_keys("F2/4=N")
	assert_str(_calc.display_text()).is_equal("-1/2")
	_keys("CC")
	_keys("99F1/2=N")
	assert_str(_calc.display_text()).is_equal("-99  1/2")
