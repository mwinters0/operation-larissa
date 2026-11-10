class_name TestCalculatorLayout
extends GdUnitTestSuite
## Teaches: testing a widget that is built from art and from DATA. The key rectangles come from the pack's calculator layout; the tests check that a
## layout is usable (every key inside the picture, none overlapping), that the widget puts its buttons and its display where the layout says, and
## drive the widget with mouse and keyboard. The original's own coordinates are checked by tests/legacy/test_calculator_layout_legacy.gd.

var _layout: CalculatorLayout = Catalog.calculator_layout()


func test_the_calculator_sits_at_the_bottom_right_inside_the_window() -> void:
	var picture := Rect2i(_layout.picture_position, _layout.picture.get_size())
	assert_vector(Vector2(picture.size)).is_equal(Vector2(_layout.picture_size))      # (the data's size is the picture's)
	assert_bool(Rect2i(0, 0, 640, 400).encloses(picture)).is_true()


func test_every_key_is_inside_the_picture_and_none_overlap() -> void:
	var picture := Rect2i(_layout.picture_position, _layout.picture.get_size())
	assert_int(_layout.key_names.size()).is_equal(22)
	for i in _layout.key_rects.size():
		assert_bool(picture.encloses(_layout.key_rects[i])).override_failure_message(_layout.key_names[i]).is_true()
		for j in range(i + 1, _layout.key_rects.size()):
			assert_bool(_layout.key_rects[i].intersects(_layout.key_rects[j])).override_failure_message(
					"%s overlaps %s" % [_layout.key_names[i], _layout.key_names[j]]).is_false()


func test_every_calculator_key_has_a_button_area() -> void:
	for key in "0123456789.+-*/=":
		assert_bool(_layout.key_names.has(key)).override_failure_message(key).is_true()
	for key in ["F", "N", "S", "R", "C", "Enter"]:
		assert_bool(_layout.key_names.has(key)).override_failure_message(key).is_true()


func test_clicking_keys_computes_on_the_lcd() -> void:
	var calc := scene_runner("res://src/problems/calculator.tscn").scene() as Calculator
	for key in ["7", "+", "8", "="]:
		calc.button_for(key).pressed.emit()
		calc.end_flash()                                        # (a lit key holds the next one back for 12 ticks, see test_calculator_input.gd)
	assert_str(calc.display.text).is_equal("15")
	assert_str(calc.display.operator).is_equal("")
	calc.button_for("*").pressed.emit()
	calc.end_flash()                                            # (a command key after a result acts when its flash is over)
	assert_str(calc.display.operator).is_equal("*")


func test_buttons_sit_on_the_key_art() -> void:
	var calc := scene_runner("res://src/problems/calculator.tscn").scene() as Calculator
	assert_object(calc.position).is_equal(Vector2(_layout.picture_position))
	var five := calc.button_for("5")
	assert_object(Rect2(five.global_position, five.size)).is_equal(Rect2(_layout.key_rect("5")))


func test_fraction_and_memory_marks() -> void:
	var calc := scene_runner("res://src/problems/calculator.tscn").scene() as Calculator
	calc.press("F")
	assert_bool(calc.display.fraction_flag).is_true()
	calc.press("C")
	calc.press("C")
	assert_bool(calc.display.fraction_flag).is_false()
	calc.press("5")
	calc.press("S")
	assert_bool(calc.display.memory_flag).is_true()


func test_division_by_zero_clears_the_display_and_asks_for_the_notice() -> void:
	var calc := scene_runner("res://src/problems/calculator.tscn").scene() as Calculator
	var notices: Array = []
	calc.notice_requested.connect(func(notice: int) -> void: notices.append(notice))
	for key in ["5", "/", "0", "="]:
		calc.press(key)
	assert_array(notices).is_equal([CalculatorModel.Notice.DIVIDE_BY_ZERO])
	assert_str(calc.display.text).is_equal("0")
	assert_str(calc.display.operator).is_equal("")


func test_lcd_digits_are_drawn_right_to_left_from_the_original_x() -> void:
	var calc := scene_runner("res://src/problems/calculator.tscn").scene() as Calculator
	for key in ["1", "2"]:
		calc.press(key)
	var placements := calc.display.glyph_placements()
	assert_int(placements.size()).is_equal(2)
	var x_of_last_digit: float = (placements[0][0] as Rect2).position.x + _layout.picture_position.x
	assert_float(x_of_last_digit).is_equal(float(_layout.display_origin_calculator.x + _layout.digits_right))
	assert_float((placements[1][0] as Rect2).position.x + _layout.picture_position.x).is_equal(x_of_last_digit - _layout.advance)


func test_decimal_point_does_not_use_up_a_cell() -> void:
	var calc := scene_runner("res://src/problems/calculator.tscn").scene() as Calculator
	for key in ["1", ".", "5"]:
		calc.press(key)
	var placements := calc.display.glyph_placements()
	assert_int(placements.size()).is_equal(3)                               # 5, '.', 1
	var five := placements[0][0] as Rect2
	var one := placements[2][0] as Rect2
	assert_float(five.position.x - one.position.x).is_equal(float(_layout.advance))   # one cell apart


func test_answer_box_types_digits_and_submits_text() -> void:
	var box := scene_runner("res://src/problems/answer_box.tscn").scene() as AnswerBox
	var submitted: Array = []
	box.submitted.connect(func(text: String) -> void: submitted.append(text))
	for c in "1 3/4":
		assert_bool(box.type_character(c)).is_true()
	assert_bool(box.type_character("x")).is_false()
	assert_str(box.display.text).is_equal("1 3/4")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	box._unhandled_key_input(enter)
	assert_array(submitted).is_equal(["1 3/4"])
	assert_object(box.position).is_equal(Vector2(_layout.answer_position))
