class_name TestBallastPanelInput
extends GdUnitTestSuite
## Teaches: pinning an input map to the original's key codes. `GetBallastAnswer` (0x4196e8) reads '8' '2' '4' '6' and the
## arrows to move the cursor, Enter to press the button under it, and the mouse on the left button's RELEASE; the other digits
## do nothing. Space presses like Enter: a deliberate deviation (the original ignores it). The worked solution (`Prob28_SolutionSubst` 0x41937f) lists the weights largest first.

var _panel: BallastPanelDiagram


func before_test() -> void:
	var problem := ProblemInstance.build(Catalog.problem_type(28), 0, 0, 0)
	_panel = auto_free(DiagramFactory.create(problem)) as BallastPanelDiagram
	add_child(_panel)
	_panel.keyboard_enabled = true


func _press_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_panel._unhandled_key_input(event)


func _mouse(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	_panel._gui_input(event)


func test_8_and_2_and_the_arrows_move_the_cursor_up_and_down_a_column() -> void:
	assert_int(_panel.cursor).is_equal(0)
	_press_key(KEY_2)
	assert_int(_panel.cursor).is_equal(1)
	_press_key(KEY_DOWN)
	assert_int(_panel.cursor).is_equal(2)
	_press_key(KEY_8)
	assert_int(_panel.cursor).is_equal(1)
	_press_key(KEY_UP)
	assert_int(_panel.cursor).is_equal(0)
	_press_key(KEY_8)                                    # above the first weight of a column: Done
	assert_int(_panel.cursor).is_equal(10)
	_press_key(KEY_8)                                    # above Done: the last weight of the first column
	assert_int(_panel.cursor).is_equal(4)
	_press_key(KEY_2)                                    # below it: Done again
	assert_int(_panel.cursor).is_equal(10)
	_press_key(KEY_2)                                    # below Done: the first weight
	assert_int(_panel.cursor).is_equal(0)


func test_4_and_6_and_the_side_arrows_switch_the_column() -> void:
	_press_key(KEY_2)                                    # weight 1
	_press_key(KEY_6)
	assert_int(_panel.cursor).is_equal(6)
	_press_key(KEY_4)
	assert_int(_panel.cursor).is_equal(1)
	_press_key(KEY_RIGHT)
	assert_int(_panel.cursor).is_equal(6)
	_press_key(KEY_LEFT)
	assert_int(_panel.cursor).is_equal(1)
	_panel.cursor = 10
	_press_key(KEY_6)                                    # Done has no other column
	assert_int(_panel.cursor).is_equal(10)


func test_enter_toggles_the_weight_under_the_cursor() -> void:
	_press_key(KEY_2)
	_press_key(KEY_ENTER)
	assert_int(_panel.selected).is_equal(1 << 1)
	_press_key(KEY_ENTER)
	assert_int(_panel.selected).is_equal(0)


func test_space_toggles_the_weight_under_the_cursor_like_enter() -> void:
	_press_key(KEY_2)
	_press_key(KEY_SPACE)
	assert_int(_panel.selected).is_equal(1 << 1)
	_press_key(KEY_SPACE)
	assert_int(_panel.selected).is_equal(0)
	_press_key(KEY_ENTER)                                # the two keys mix freely
	_press_key(KEY_SPACE)
	assert_int(_panel.selected).is_equal(0)


func test_space_on_done_presses_it_like_enter() -> void:
	var presses := []
	_panel.done_pressed.connect(func(mask: int, ticks: int) -> void: presses.append([mask, ticks]))
	_panel.cursor = 10
	_press_key(KEY_SPACE)
	assert_bool(_panel.is_done_pressed()).is_true()
	assert_array(presses).has_size(1)


func test_space_is_taken_and_plays_the_click_like_enter() -> void:
	var sounds := []
	_panel.sfx_requested.connect(func(sfx_id: StringName) -> void: sounds.append(sfx_id))
	_press_key(KEY_SPACE)
	assert_array(sounds).is_equal([&"click"])


func test_a_key_repeat_of_space_is_ignored() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	event.echo = true
	_panel._unhandled_key_input(event)
	assert_int(_panel.selected).is_equal(0)


func test_the_digits_other_than_8_2_4_6_do_nothing() -> void:
	var sounds := []
	_panel.sfx_requested.connect(func(sfx_id: StringName) -> void: sounds.append(sfx_id))
	for keycode in [KEY_0, KEY_1, KEY_3, KEY_5, KEY_7, KEY_9, KEY_KP_1, KEY_KP_5]:
		_press_key(keycode)
	assert_int(_panel.selected).is_equal(0)
	assert_int(_panel.cursor).is_equal(0)
	assert_array(sounds).is_empty()
	assert_bool(_panel.is_done_pressed()).is_false()


func test_the_keypad_digits_8_2_4_6_are_the_same_characters() -> void:
	_press_key(KEY_KP_2)
	assert_int(_panel.cursor).is_equal(1)
	_press_key(KEY_KP_6)
	assert_int(_panel.cursor).is_equal(6)


func test_the_second_try_starts_the_cursor_on_weight_0_and_keeps_the_chosen_weights() -> void:
	_press_key(KEY_2)
	_press_key(KEY_6)
	_press_key(KEY_ENTER)                                # weight 6 on, cursor on it
	assert_int(_panel.cursor).is_equal(6)
	_panel.cursor = 10
	_press_key(KEY_ENTER)                                # Done pressed; the flow switches the keys off for the message, then on for the second try
	assert_bool(_panel.is_done_pressed()).is_true()
	_panel.keyboard_enabled = false
	_panel.keyboard_enabled = true
	assert_bool(_panel.is_done_pressed()).is_false()
	assert_int(_panel.cursor).is_equal(0)                # `GetBallastAnswer` (0x4196e8): the cursor is a local that starts at 0
	assert_int(_panel.selected).is_equal(1 << 6)         # (`BallastSelected` keeps the weights until the diagram is drawn again)
	var frame := _panel.pictures(int(_panel.spec["weights"]["cursor_pic"]))                # the red frame is drawn on weight 0
	assert_array(frame.map(func(i: DiagramItem) -> Vector2: return i.position)).contains_exactly([_panel.slot_position(0)])


func test_the_mouse_acts_on_release_not_on_press() -> void:
	var at := _panel.slot_position(3) + Vector2(5, 5)
	_mouse(at, true)
	assert_int(_panel.selected).is_equal(0)
	_mouse(at, false)
	assert_int(_panel.selected).is_equal(1 << 3)
	assert_int(_panel.cursor).is_equal(3)                # the cursor goes to the clicked weight
	_mouse(at, false)
	assert_int(_panel.selected).is_equal(0)


func test_on_the_problem_screen_space_reaches_the_panel_alone() -> void:
	# the whole walk, as the engine delivers a key: the screen's answer box and calculator must not take the Space
	# (they are off for a ballast problem), and the panel is the only thing that acts on it
	GameState.reset()
	GameClock.paused = false
	var screen := scene_runner("res://src/problems/problem_screen.tscn").scene() as ProblemScreen
	screen.start(ProblemFactory.make(28, 0))
	if screen.step() == ProblemScreen.Step.INTRO:
		screen.diagram.skip_animation()
	assert_object(screen.ballast).is_not_null()
	assert_bool(screen.answer_box.keyboard_enabled).is_false()
	assert_bool(screen.calculator.keyboard_enabled).is_false()
	assert_str(screen.answer_box.text).is_empty()
	for keycode in [KEY_SPACE, KEY_ENTER]:
		var event := InputEventKey.new()
		event.keycode = keycode as Key
		event.pressed = true
		get_viewport().push_input(event)
	assert_int(screen.ballast.selected).is_equal(0)              # Space switched weight 0 on, Enter switched it off again
	assert_str(screen.answer_box.text).is_empty()                # (a Space in the answer box would have typed a blank)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	get_viewport().push_input(space)
	assert_int(screen.ballast.selected).is_equal(1)
	assert_str(screen.answer_box.text).is_empty()
	GameClock.paused = false
	GameState.reset()
