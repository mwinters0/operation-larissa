class_name TestWindowHotkeys
extends GdUnitTestSuite
## Teaches: testing a GLOBAL key through the whole input walk. The events go through `get_viewport().push_input`, the way the engine
## delivers a key, so the order of `_input` (last node of the tree first), the GUI and `_unhandled_key_input` all count. A screen that
## listens in `_input` and is added to the tree AFTER the autoload would hear Alt+Enter before it, if the autoload did not move
## itself to the end of the root's children (`WindowHotkeys._move_to_end`). A headless window does not report back the mode it was given
## (the test runner's even reads as minimized), so the tests listen to `fullscreen_toggled` and check `mode_after` on its own.

var _toggles: Array[Window.Mode] = []
var _old_mode: Window.Mode


## A node that listens in `_input` like the sign-in screen does while it scans, and takes every key.
class KeyHog extends Node:
	var heard: Array[int] = []

	func _input(event: InputEvent) -> void:
		var key := event as InputEventKey
		if key != null:
			heard.append(key.keycode)
			get_viewport().set_input_as_handled()


func before_test() -> void:
	_toggles = []
	_old_mode = get_window().mode
	WindowHotkeys.fullscreen_toggled.connect(_on_toggled)


func after_test() -> void:
	WindowHotkeys.fullscreen_toggled.disconnect(_on_toggled)
	get_window().mode = _old_mode


func _on_toggled(mode: Window.Mode) -> void:
	_toggles.append(mode)


func _key(keycode: int, alt: bool, pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.alt_pressed = alt
	event.pressed = pressed
	event.echo = echo
	return event


func _send(event: InputEvent) -> void:
	get_viewport().push_input(event)


func test_alt_enter_and_alt_keypad_enter_toggle() -> void:
	_send(_key(KEY_ENTER, true))
	_send(_key(KEY_KP_ENTER, true))
	assert_array(_toggles).has_size(2)


func test_other_keys_do_not_toggle() -> void:
	_send(_key(KEY_ENTER, false))
	_send(_key(KEY_KP_ENTER, false))
	_send(_key(KEY_F11, true))
	_send(_key(KEY_SPACE, true))
	var with_ctrl := _key(KEY_ENTER, true)
	with_ctrl.ctrl_pressed = true
	_send(with_ctrl)
	assert_array(_toggles).is_empty()


func test_key_repeat_and_release_do_not_toggle_again_but_are_swallowed() -> void:
	var hog := auto_free(KeyHog.new()) as KeyHog
	get_tree().root.add_child(hog)
	await await_idle_frame()
	_send(_key(KEY_ENTER, true, true, true))
	_send(_key(KEY_ENTER, true, false))
	assert_array(_toggles).is_empty()
	assert_array(hog.heard).is_empty()


func test_windowed_goes_to_fullscreen_and_either_fullscreen_goes_back() -> void:
	assert_int(WindowHotkeys.mode_after(Window.MODE_WINDOWED)).is_equal(Window.MODE_FULLSCREEN)
	assert_int(WindowHotkeys.mode_after(Window.MODE_MINIMIZED)).is_equal(Window.MODE_FULLSCREEN)
	assert_int(WindowHotkeys.mode_after(Window.MODE_FULLSCREEN)).is_equal(Window.MODE_WINDOWED)
	assert_int(WindowHotkeys.mode_after(Window.MODE_EXCLUSIVE_FULLSCREEN)).is_equal(Window.MODE_WINDOWED)


func test_a_screen_listening_in_input_never_sees_alt_enter() -> void:
	var hog := auto_free(KeyHog.new()) as KeyHog
	get_tree().root.add_child(hog)                              # after the autoload in the tree: it would be called first
	await await_idle_frame()
	_send(_key(KEY_ENTER, true))
	_send(_key(KEY_KP_ENTER, true))
	assert_array(hog.heard).is_empty()
	assert_int(_toggles.size()).is_equal(2)
	_send(_key(KEY_ENTER, false))                               # a plain Enter still reaches it
	assert_array(hog.heard).is_equal([KEY_ENTER])


func test_the_autoload_stays_last_when_a_scene_is_added_later() -> void:
	var root := get_tree().root
	var later := auto_free(Node.new()) as Node
	root.add_child(later)
	await await_idle_frame()
	assert_int(WindowHotkeys.get_index()).is_equal(root.get_child_count() - 1)


func test_the_calculator_notice_does_not_close_on_alt_enter() -> void:
	var dialog := auto_free(load("res://src/problems/calc_notice_dialog.tscn").instantiate()) as CalcNoticeDialog
	add_child(dialog)
	dialog.show_notice(CalculatorModel.Notice.FRACTION_HELP)
	await await_idle_frame()
	_send(_key(KEY_ENTER, true))
	assert_bool(dialog.is_open()).is_true()
	_send(_key(KEY_KP_ENTER, true))
	assert_bool(dialog.is_open()).is_true()
	_send(_key(KEY_ENTER, false))
	assert_bool(dialog.is_open()).is_false()


func test_the_ballast_panel_does_not_press_on_alt_enter() -> void:
	var problem := ProblemInstance.build(Catalog.problem_type(28), 0, 0, 0)
	var panel := auto_free(DiagramFactory.create(problem)) as BallastPanelDiagram
	add_child(panel)
	panel.keyboard_enabled = true
	_send(_key(KEY_ENTER, true))
	_send(_key(KEY_KP_ENTER, true))
	assert_int(panel.selected).is_equal(0)
	_send(_key(KEY_ENTER, false))
	assert_int(panel.selected).is_equal(1)
