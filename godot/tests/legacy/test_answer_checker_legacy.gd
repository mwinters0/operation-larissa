class_name TestAnswerCheckerLegacy
extends GdUnitTestSuite
## The comparison rules of the ORIGINAL's 34 types (DESIGN 5.2 item 7), each on a real stored problem of the legacy pack: which types are compared
## exactly, by kind, by a relative or an absolute tolerance, and what their stored records answer. The rules themselves (the four comparisons, the
## kind rule, the boundary) are tested on made-up types in tests/engine/test_answer_checker.gd.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _check(type_id: int, level: int, record_index: int, typed: String) -> bool:
	var type := Catalog.problem_type(type_id)
	return AnswerChecker.check(type, level, type.record(level, record_index), NumberValue.parse(typed))


# --- exact: fractions and decimals are interchangeable --------------------------

func test_exact_answer_accepts_any_spelling_of_the_same_number() -> void:
	# Type 6 (sounder) level 2, record 0: echo after 0.2 s, 0.2 * 5000 / 2 = 500 feet.
	assert_bool(_check(6, 2, 0, "500")).is_true()
	assert_bool(_check(6, 2, 0, "500.0")).is_true()
	assert_bool(_check(6, 2, 0, "1000/2")).is_false()           # cannot even be typed: numerators have 2 digits
	assert_bool(_check(6, 2, 0, "499")).is_false()
	# Type 32 level 1 record 0 expects the fraction 1/4: "2/8" is the same number and kind
	assert_bool(_check(32, 1, 0, "2/8")).is_true()


func test_tiny_difference_is_a_wrong_answer_for_exact_types() -> void:
	assert_bool(_check(6, 2, 0, "500.000001")).is_false()


# --- kind rules -----------------------------------------------------------------

func test_barnacles_level_1_must_be_typed_as_a_fraction() -> void:
	# type 14 level 1 record 0: 3 of 7 barnacles are unhealthy
	assert_bool(_check(14, 1, 0, "3/7")).is_true()
	assert_bool(_check(14, 1, 0, "6/14")).is_true()
	assert_bool(_check(14, 1, 0, "0.428571428")).is_false()
	assert_bool(_check(14, 1, 0, "0.4285714286")).is_false()      # too many digits to type anyway


func test_barnacles_level_2_is_a_percent_not_checked_for_kind() -> void:
	# type 14 level 2 record 0: 6 of 8 unhealthy = 75 percent
	assert_bool(_check(14, 2, 0, "75")).is_true()
	assert_bool(_check(14, 2, 0, "75.0")).is_true()
	assert_bool(_check(14, 2, 0, "3/4")).is_false()               # that is 0.75, not 75


func test_search_grid_fraction_vs_decimal_kind_is_enforced() -> void:
	# type 32 level 1 record 0 stores the FRACTION 1/4; level 2 record 0 stores the DECIMAL 0.10
	assert_bool(_check(32, 1, 0, "1/4")).is_true()
	assert_bool(_check(32, 1, 0, "0.25")).is_false()
	assert_bool(_check(32, 2, 0, "0.1")).is_true()
	assert_bool(_check(32, 2, 0, "1/10")).is_false()
	assert_bool(_check(33, 1, 0, "3/4")).is_true()


func test_food_pie_chart_kind_must_match_the_stored_answer() -> void:
	# type 17 level 1 record 0 stores the fraction 1/3
	assert_bool(_check(17, 1, 0, "1/3")).is_true()
	assert_bool(_check(17, 1, 0, "2/6")).is_true()
	assert_bool(_check(17, 1, 0, "0.333333333")).is_false()


# --- tolerances -------------------------------------------------------------------

func test_speed_graph_close_tolerance_is_absolute_0_01() -> void:
	# type 2 level 1 record 0: average 10
	assert_bool(_check(2, 1, 0, "10.01")).is_true()
	assert_bool(_check(2, 1, 0, "9.99")).is_true()
	assert_bool(_check(2, 1, 0, "10.02")).is_false()


func test_data_canister_level_1_is_relative_3_percent() -> void:
	# type 1 level 1 record 0: answer 4 -> 4 +- 0.12
	assert_bool(_check(1, 1, 0, "4.1")).is_true()
	assert_bool(_check(1, 1, 0, "3.9")).is_true()
	assert_bool(_check(1, 1, 0, "4.2")).is_false()
	# level 0 is exact: record 0 answer 9
	assert_bool(_check(1, 0, 0, "9")).is_true()
	assert_bool(_check(1, 0, 0, "9.1")).is_false()


func test_navigation_chart_tolerances_differ_by_level() -> void:
	# level 1 record 0 answer 6 (+-0.5); level 0 is exact (record 0 answer 5)
	assert_bool(_check(9, 1, 0, "6.5")).is_true()
	assert_bool(_check(9, 1, 0, "6.6")).is_false()
	assert_bool(_check(9, 0, 0, "5")).is_true()
	assert_bool(_check(9, 0, 0, "5.1")).is_false()
	# level 2 record 0 answer 2 (+-0.2)
	assert_bool(_check(9, 2, 0, "2.2")).is_true()
	assert_bool(_check(9, 2, 0, "2.3")).is_false()


func test_radio_telephone_tolerance_0_3() -> void:
	# level 1 record 0: 10 minutes
	assert_bool(_check(11, 1, 0, "10.3")).is_true()
	assert_bool(_check(11, 1, 0, "10.4")).is_false()


func test_temperature_conversion_tolerance_0_01() -> void:
	# type 13 level 3 record 1 stores -6 2/3 (= -6.6667): typing -6.67 is within 0.01
	assert_bool(_check(13, 3, 1, "-6.67")).is_true()
	assert_bool(_check(13, 3, 1, "-6 2/3")).is_true()
	assert_bool(_check(13, 3, 1, "-6.7")).is_false()


func test_speed_indicator_relative_tolerance_at_levels_1_and_3_only() -> void:
	# type 26 level 1 record 0: new speed 4 (+-3%); level 2 is exact (record 0: answer 6)
	assert_bool(_check(26, 1, 0, "4.1")).is_true()
	assert_bool(_check(26, 1, 0, "4.2")).is_false()
	assert_bool(_check(26, 2, 0, "6")).is_true()
	assert_bool(_check(26, 2, 0, "6.1")).is_false()


func test_pie_chart_percent_level_2_tolerance_0_7() -> void:
	# type 17 level 2 record 0 stores 33 (percent)
	assert_bool(_check(17, 2, 0, "33.6")).is_true()
	assert_bool(_check(17, 2, 0, "32.2")).is_false()


func test_nothing_typed_is_wrong() -> void:
	var type := Catalog.problem_type(2)
	assert_bool(AnswerChecker.check(type, 1, type.record(1, 0), null)).is_false()


# --- ballast ------------------------------------------------------------------------

func test_ballast_accepts_any_selection_with_the_right_sum() -> void:
	# type 28 level 0 record 0: target 15 with weights 1 1 1 1 5 5 10 25 25 25 (cents)
	var type := Catalog.problem_type(28)
	var r := type.record(0, 0)
	assert_int(r.int_at(0)).is_equal(15)
	assert_bool(AnswerChecker.check_selection(type, 0, r, 0b1010000)).is_true()      # first 5 + 10
	assert_bool(AnswerChecker.check_selection(type, 0, r, 0b1100000)).is_true()      # second 5 + 10
	assert_bool(AnswerChecker.check_selection(type, 0, r, 0b0110000)).is_false()     # 5 + 5 = 10
	assert_bool(AnswerChecker.check_selection(type, 0, r, 0)).is_false()


func test_ballast_binary_levels_use_powers_of_two() -> void:
	var type := Catalog.problem_type(28)
	var weights := AnswerChecker.denominations(type, 1)
	assert_array(Array(weights)).is_equal([1, 2, 4, 8, 16, 32, 64, 128, 256, 512])
	assert_array(Array(AnswerChecker.denominations(type, 0))).is_equal([1, 1, 1, 1, 5, 5, 10, 25, 25, 25])
	assert_str(AnswerChecker.denomination_labels(type, 2)[7]).is_equal("0.25")
