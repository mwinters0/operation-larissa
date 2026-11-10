class_name TestCalculatorInput
extends GdUnitTestSuite
## Teaches: testing time and input without waiting. The key flash is a `Timer`, so the tests look at what the timer
## guards (a lit key, a queue of waiting keys) and end it with `end_flash()`; only one test waits for the real time.
##
## What is tested comes from `GetNumber` (0x41fb34) / `BlinkButton` (0x41b411): a pressed key is lit for 12 ticks (1/73 s each)
## and the calculator takes no input meanwhile; Backspace clicks even on an empty entry; the notice dialogs
## (`ShowCalcNoticeDialog` (0x420d8f)) come from the keys listed in DESIGN 5.2.

const NOTICE := CalculatorModel.Notice

var _sfx: Array = []


func _calculator() -> Calculator:
	var calc := scene_runner("res://src/problems/calculator.tscn").scene() as Calculator
	_sfx.clear()
	calc.sfx_requested.connect(func(id: StringName) -> void: _sfx.append(id))
	return calc


func _answer_box() -> AnswerBox:
	var box := scene_runner("res://src/problems/answer_box.tscn").scene() as AnswerBox
	_sfx.clear()
	box.sfx_requested.connect(func(id: StringName) -> void: _sfx.append(id))
	return box


# --- the key flash -----------------------------------------------------------------------------------------

func test_a_pressed_key_is_lit_for_twelve_ticks() -> void:
	var calc := _calculator()
	assert_float(calc._flash_timer.wait_time).is_equal_approx(12.0 / 73.0, 0.0001)
	var button := calc.button_for("7")
	assert_bool(button.has_theme_stylebox_override("normal")).is_false()
	calc.input_key("7")
	assert_bool(calc.is_flashing()).is_true()
	assert_bool(button.has_theme_stylebox_override("normal")).is_true()           # the "pressed" look, also under the mouse
	assert_bool(button.has_theme_stylebox_override("hover")).is_true()
	assert_str(calc.display.text).is_equal("7")                                  # the display answers at once
	calc.end_flash()
	assert_bool(calc.is_flashing()).is_false()
	assert_bool(button.has_theme_stylebox_override("normal")).is_false()


func test_the_flash_ends_by_itself_after_its_time() -> void:
	var calc := _calculator()
	calc.input_key("5")
	assert_bool(calc.is_flashing()).is_true()
	await await_millis(int(CalculatorModel.key_flash_ticks() / Calculator.TICKS_PER_SECOND * 1000.0) + 120)
	assert_bool(calc.is_flashing()).is_false()


func test_a_key_pressed_during_the_flash_waits_and_is_taken_afterwards() -> void:
	var calc := _calculator()
	calc.input_key("1")
	calc.input_key("2")                                                           # too early: queued, no click yet
	calc.input_key("3")
	assert_str(calc.display.text).is_equal("1")
	assert_array(_sfx).is_equal([&"calc_backspace"])
	calc.end_flash()                                                              # 12 ticks later: "2" is taken and lit
	assert_str(calc.display.text).is_equal("12")
	assert_bool(calc.is_flashing()).is_true()
	assert_array(_sfx).is_equal([&"calc_backspace", &"calc_backspace"])
	calc.end_flash()
	calc.end_flash()
	assert_str(calc.display.text).is_equal("123")
	assert_bool(calc.is_flashing()).is_false()
	assert_array(_sfx).is_equal([&"calc_backspace", &"calc_backspace", &"calc_backspace"])


func test_the_mouse_clicks_on_the_press_not_on_the_release() -> void:
	var calc := _calculator()
	for key: String in calc.layout.key_names:
		assert_int(calc.button_for(key).action_mode).override_failure_message(key).is_equal(BaseButton.ACTION_MODE_BUTTON_PRESS)
	var nine := calc.button_for("9")
	var at := nine.global_position + nine.size / 2.0
	var viewport := calc.get_viewport()
	var move := InputEventMouseMotion.new()                                       # (the button must know the mouse is over it)
	move.position = at
	move.global_position = at
	viewport.push_input(move, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(press, true)                                              # the button is still held down
	assert_array(_sfx).is_equal([&"calc_backspace"])
	assert_str(calc.display.text).is_equal("9")
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.button_mask = 0
	viewport.push_input(release, true)
	assert_array(_sfx).is_equal([&"calc_backspace"])                                           # the release adds nothing


func test_the_keyboard_goes_through_the_same_flash() -> void:
	var calc := _calculator()
	var key := InputEventKey.new()
	key.keycode = KEY_4
	key.unicode = "4".unicode_at(0)
	key.pressed = true
	calc._unhandled_key_input(key)
	assert_bool(calc.is_flashing()).is_true()
	assert_bool(calc.button_for("4").has_theme_stylebox_override("normal")).is_true()


func test_space_is_the_fraction_key() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.unicode = 32
	assert_str(Calculator.key_for_event(key)).is_equal("F")


## An `InputEventKey` as the keyboard delivers it: the physical `keycode` plus the typed character.
func _key(keycode: Key, character: String = "", shift: bool = false) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.unicode = character.unicode_at(0) if not character.is_empty() else 0
	key.shift_pressed = shift
	key.pressed = true
	return key


func test_a_typed_plus_works_whatever_key_makes_it() -> void:
	# The original reads WM_CHAR (`MainWindowProc` (0x41312f) -> `PostKeyEvent` (0x410b78)): the character counts, not the key.
	assert_str(Calculator.key_for_event(_key(KEY_EQUAL, "+", true))).is_equal("+")      # Shift+= on a US layout
	assert_str(Calculator.key_for_event(_key(KEY_KP_ADD, "+"))).is_equal("+")           # the number pad
	assert_str(Calculator.key_for_event(_key(KEY_KP_ADD))).is_equal("+")                # (synthetic: no character)
	assert_str(Calculator.key_for_event(_key(KEY_BRACKETRIGHT, "+"))).is_equal("+")      # a layout with a plain "+" key
	assert_str(Calculator.key_for_event(_key(KEY_EQUAL, "="))).is_equal("=")


func test_the_typed_character_beats_the_key_for_the_other_symbols_too() -> void:
	assert_str(Calculator.key_for_event(_key(KEY_8, "*", true))).is_equal("*")          # Shift+8 on a US layout
	assert_str(Calculator.key_for_event(_key(KEY_7, "/", true))).is_equal("/")          # Shift+7 on a German layout
	assert_str(Calculator.key_for_event(_key(KEY_1, "1", false))).is_equal("1")
	assert_str(Calculator.key_for_event(_key(KEY_AMPERSAND, "1", false))).is_equal("1")  # AZERTY digits come from the character
	assert_str(Calculator.key_for_event(_key(KEY_SLASH, "?", true))).is_empty()         # a character the original ignores
	assert_str(Calculator.key_for_event(_key(KEY_MINUS, "_", true))).is_empty()


func test_the_letter_keys_work_in_either_case_and_control_codes_two_to_six_too() -> void:
	# `CalcHotkeys` (0x441444) "FfSsNnRrCc."; `TranslateCalcKey` (0x41b843) also maps the codes 2-6 to F S N R C
	for letter in "FSNRC":
		assert_str(Calculator.key_for_event(_key(OS.find_keycode_from_string(letter), letter.to_lower()))).is_equal(letter)
		assert_str(Calculator.key_for_event(_key(OS.find_keycode_from_string(letter), letter, true))).is_equal(letter)
	assert_str(Calculator.key_for_event(_key(KEY_X, "x"))).is_empty()
	var ctrl_b := _key(KEY_B)
	ctrl_b.ctrl_pressed = true
	assert_str(Calculator.key_for_event(ctrl_b)).is_equal("F")
	var ctrl_f := _key(KEY_F)
	ctrl_f.ctrl_pressed = true
	assert_str(Calculator.key_for_event(ctrl_f)).is_equal("C")


func test_shift_equals_adds_through_the_keyboard_handler() -> void:
	var calc := _calculator()
	calc.keyboard_enabled = true
	calc._unhandled_key_input(_key(KEY_3, "3"))
	calc.end_flash()
	calc._unhandled_key_input(_key(KEY_EQUAL, "+", true))
	assert_str(calc.model.pending_operator()).is_equal("+")


func test_reset_ends_the_flash_and_forgets_waiting_keys() -> void:
	var calc := _calculator()
	calc.input_key("1")
	calc.input_key("2")
	calc.reset()
	assert_bool(calc.is_flashing()).is_false()
	assert_str(calc.display.text).is_equal("0")


func test_after_a_result_a_command_key_acts_when_its_flash_is_over() -> void:
	# BlinkButton (0x41b411): click and highlight first, the key's work after the 12 ticks (the LCD and the pending
	# operator change then); entry keys (GetNumber) act at once
	var calc := _calculator()
	for key in "7+8=":
		calc.press(key)
	assert_str(calc.display.text).is_equal("15")                 # a result is shown now
	_sfx.clear()
	calc.input_key("*")
	assert_array(_sfx).is_equal([&"calc_backspace"])                          # the click is immediate ...
	assert_bool(calc.button_for("*").has_theme_stylebox_override("normal")).is_true()
	assert_str(calc.model.pending_operator()).is_empty()         # ... the operator is not set yet
	calc.end_flash()
	assert_str(calc.model.pending_operator()).is_equal("*")
	assert_array(_sfx).is_equal([&"calc_backspace"])                          # (the click is not played twice)
	calc.end_flash()
	calc.input_key("3")                                          # an entry key: no wait
	assert_str(calc.display.text).is_equal("3")


func test_a_command_key_while_typing_acts_at_once() -> void:
	var calc := _calculator()
	calc.input_key("7")
	calc.end_flash()
	calc.input_key("+")                                          # a number is being typed: GetNumber handles the key
	assert_str(calc.model.pending_operator()).is_equal("+")


func test_a_delayed_enter_submits_after_the_flash() -> void:
	var calc := _calculator()
	var submitted: Array = []
	calc.submitted.connect(func(value: NumberValue) -> void: submitted.append(value.to_double()))
	for key in "7=":
		calc.press(key)
	_sfx.clear()
	calc.input_key("Enter")
	assert_array(submitted).is_empty()
	calc.end_flash()
	assert_array(submitted).is_equal([7.0])


func test_a_reset_drops_a_delayed_key() -> void:
	var calc := _calculator()
	for key in "7=":
		calc.press(key)
	calc.input_key("+")
	calc.reset()
	assert_str(calc.model.pending_operator()).is_empty()


func test_enter_on_a_fresh_calculator_clicks_and_submits_nothing() -> void:
	var calc := _calculator()
	var submitted: Array = []
	calc.submitted.connect(func(value: NumberValue) -> void: submitted.append(value))
	calc.press("Enter")
	assert_array(_sfx).is_equal([&"calc_backspace"])
	assert_array(submitted).is_empty()


# --- the calculator's notices ----------------------------------------------------------------------------------

func test_enter_does_the_pending_operation_then_submits() -> void:
	var calc := _calculator()
	var submitted: Array = []
	calc.submitted.connect(func(value: NumberValue) -> void: submitted.append(value.to_double()))
	for key in "5+3":
		calc.press(key)
	calc.press("Enter")                                                           # 5 + 3 is 8, not 3
	assert_array(submitted).is_equal([8.0])


func test_enter_with_a_division_by_zero_shows_the_notice_and_submits_nothing() -> void:
	var calc := _calculator()
	var submitted: Array = []
	var notices: Array = []
	calc.submitted.connect(func(value: NumberValue) -> void: submitted.append(value))
	calc.notice_requested.connect(func(notice: int) -> void: notices.append(notice))
	for key in "5/0":
		calc.press(key)
	calc.press("Enter")
	assert_array(notices).is_equal([NOTICE.DIVIDE_BY_ZERO])
	assert_array(submitted).is_empty()
	assert_str(calc.display.text).is_equal("0")


func test_enter_inside_a_fraction_shows_the_notice_and_submits_nothing() -> void:
	var calc := _calculator()
	var submitted: Array = []
	var notices: Array = []
	calc.submitted.connect(func(value: NumberValue) -> void: submitted.append(value))
	calc.notice_requested.connect(func(notice: int) -> void: notices.append(notice))
	for key in "F3":
		calc.press(key)
	calc.press("Enter")
	assert_array(notices).is_equal([NOTICE.FRACTION_OPERATOR])
	assert_array(submitted).is_empty()
	for key in "/4":
		calc.press(key)
	calc.press("Enter")                                                           # 3/4 is complete
	assert_int(submitted.size()).is_equal(1)


# --- the answer box (no calculator) ------------------------------------------------------------------------------

func test_backspace_always_clicks() -> void:
	var box := _answer_box()
	var key := InputEventKey.new()
	key.keycode = KEY_BACKSPACE
	key.pressed = true
	box._unhandled_key_input(key)                                                 # empty entry
	assert_array(_sfx).is_equal([&"calc_backspace"])
	box.type_character("5")
	box._unhandled_key_input(key)
	box._unhandled_key_input(key)
	assert_array(_sfx).is_equal([&"calc_backspace", &"calc_backspace", &"calc_backspace"])
	assert_str(box.text).is_empty()


func test_the_answer_box_follows_the_entry_rules_of_the_original() -> void:
	var box := _answer_box()
	for c in "1234567890":
		box.type_character(c)
	assert_str(box.text).is_equal("123456789")                                    # nine digits
	box.reset()
	for c in "12 345/6789":                                                       # whole at most 2, numerator 2, denominator 3
		box.type_character(c)
	assert_str(box.text).is_equal("12 34/678")
	box.reset()
	assert_bool(box.type_character("1")).is_true()
	assert_bool(box.type_character(".")).is_true()
	assert_bool(box.type_character(".")).is_false()                              # one point
	assert_bool(box.type_character(" ")).is_false()                              # no F after a point
	box.reset()
	for c in "123":
		box.type_character(c)
	assert_bool(box.type_character(" ")).is_false()                              # no F after three digits
	assert_bool(box.type_character("/")).is_false()                              # nor a bare bar
	box.reset()
	assert_bool(box.type_character("/")).is_false()                              # a bar needs a numerator
	for c in "3/4":
		assert_bool(box.type_character(c)).is_true()
	assert_str(box.text).is_equal("3/4")


func test_the_sign_key_flips_the_sign_when_there_is_room() -> void:
	var box := _answer_box()
	box.type_character("5")
	assert_bool(box.type_character("-")).is_true()
	assert_str(box.text).is_equal("-5")
	assert_bool(box.type_character("-")).is_true()                               # again: off
	assert_str(box.text).is_equal("5")
	box.type_character("N")
	assert_str(box.text).is_equal("-5")
	box.reset()
	for c in "12 ":
		box.type_character(c)
	assert_bool(box.type_character("N")).is_false()                              # sign + two digits + F: no room
	assert_str(box.text).is_equal("12 ")


func test_enter_on_an_empty_answer_box_does_nothing() -> void:
	var box := _answer_box()
	var submitted: Array = []
	var notices: Array = []
	box.submitted.connect(func(text: String) -> void: submitted.append(text))
	box.notice_requested.connect(func(notice: int) -> void: notices.append(notice))
	box.submit()
	assert_array(submitted).is_empty()
	assert_array(notices).is_empty()
	box.type_character(".")                                                       # a point alone is no digit either
	box.submit()
	assert_array(submitted).is_empty()


func test_enter_in_a_fraction_without_a_denominator_shows_the_fraction_help() -> void:
	var box := _answer_box()
	var submitted: Array = []
	var notices: Array = []
	box.submitted.connect(func(text: String) -> void: submitted.append(text))
	box.notice_requested.connect(func(notice: int) -> void: notices.append(notice))
	for c in "1 2":
		box.type_character(c)
	box.submit()                                                                  # still typing the numerator
	for c in "/":
		box.type_character(c)
	box.submit()                                                                  # the denominator is empty
	box.type_character("0")
	box.submit()                                                                  # "0" is no denominator
	assert_array(notices).is_equal([NOTICE.FRACTION_HELP, NOTICE.FRACTION_HELP, NOTICE.FRACTION_HELP])
	assert_array(submitted).is_empty()
	box.type_character("0")
	box.text = "1 2/5"
	box.submit()
	assert_array(submitted).is_equal(["1 2/5"])


func test_operators_in_the_denominator_show_the_fraction_help_elsewhere_they_are_ignored() -> void:
	var box := _answer_box()
	var notices: Array = []
	box.notice_requested.connect(func(notice: int) -> void: notices.append(notice))
	for c in "7+*=":
		box.type_character(c)                                                    # a plain number: nothing happens
	assert_str(box.text).is_equal("7")
	assert_array(notices).is_empty()
	box.reset()
	for c in "1 2":
		box.type_character(c)
	for c in "+-*=":
		box.type_character(c)                                                    # the numerator: still nothing
	assert_array(notices).is_empty()
	box.type_character("/")
	for c in "+-*=/":
		assert_bool(box.type_character(c)).is_false()
	assert_int(notices.size()).is_equal(5)                                        # the denominator: the help each time
	assert_str(box.text).is_equal("1 2/")


# --- the dialog ---------------------------------------------------------------------------------------------------

func test_each_notice_has_its_own_body_and_the_help_its_own_title() -> void:
	var divide := CalcNoticeDialog.texts_for(NOTICE.DIVIDE_BY_ZERO)
	var large := CalcNoticeDialog.texts_for(NOTICE.TOO_LARGE)
	var operator := CalcNoticeDialog.texts_for(NOTICE.FRACTION_OPERATOR)
	var help := CalcNoticeDialog.texts_for(NOTICE.FRACTION_HELP)
	for texts in [divide, large, operator, help]:
		assert_str(texts[0]).is_not_empty()
		assert_str(texts[1]).is_not_empty()
	assert_str(divide[0]).is_equal(Catalog.text(CalcNoticeDialog.TITLE_ERROR))
	assert_str(large[0]).is_equal(divide[0])                                    # the three errors share a title ...
	assert_str(operator[0]).is_equal(divide[0])
	assert_str(help[0]).is_equal(Catalog.text(CalcNoticeDialog.TITLE_FRACTION_HELP))
	assert_str(help[0]).is_not_equal(divide[0])                                 # ... and the help has its own
	var bodies := {}
	for texts in [divide, large, operator, help]:
		bodies[texts[1]] = true
	assert_int(bodies.size()).is_equal(4)                                       # four notices, four texts


func test_the_dialog_writes_key_pictures_and_line_breaks_out() -> void:
	# The pack's text keeps the original's markup: a key picture is the character 0x91 (the fraction bar), a line break is CR.
	assert_str(CalcNoticeDialog.printable("press \u0091 now")).is_equal("press / now")
	assert_str(CalcNoticeDialog.printable("one\rtwo")).is_equal("one\ntwo")


func test_the_dialog_takes_the_keys_and_closes_with_enter_space_or_escape() -> void:
	var dialog := scene_runner("res://src/problems/calc_notice_dialog.tscn").scene() as CalcNoticeDialog
	assert_bool(dialog.is_open()).is_false()
	var closed := [0]
	dialog.closed.connect(func() -> void: closed[0] += 1)
	for keycode in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]:
		dialog.show_notice(NOTICE.TOO_LARGE)
		assert_bool(dialog.is_open()).is_true()
		var digit := InputEventKey.new()
		digit.keycode = KEY_7
		digit.pressed = true
		dialog._input(digit)                                                     # swallowed, the dialog stays
		assert_bool(dialog.is_open()).is_true()
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = true
		dialog._input(key)
		assert_bool(dialog.is_open()).is_false()
	assert_int(closed[0]).is_equal(3)


func test_a_notice_from_the_calculator_opens_the_dialog_on_the_problem_screen() -> void:
	var screen := scene_runner("res://src/problems/problem_screen.tscn").scene() as ProblemScreen
	screen.start(ProblemFactory.make(6, 2, null, 0))
	var dialog := screen.find_children("*", "CalcNoticeDialog", true, false)[0] as CalcNoticeDialog
	assert_bool(dialog.is_open()).is_false()
	for key in "5/0=":
		screen.calculator.press(key)
	assert_bool(dialog.is_open()).is_true()
	assert_str(dialog.title_label.text).is_equal(Catalog.text(CalcNoticeDialog.TITLE_ERROR))
	screen.calculator.keyboard_enabled = true
	var seven := InputEventKey.new()
	seven.keycode = KEY_7
	seven.unicode = 55
	seven.pressed = true
	dialog._input(seven)                                                         # the dialog is first in line: the key never gets to the calculator
	assert_str(screen.calculator.display.text).is_equal("0")
