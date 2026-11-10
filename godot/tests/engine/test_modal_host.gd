extends GdUnitTestSuite
## `ModalHost`: a modal borrows the keyboard focus and gives it back, keeps the arrow keys and Tab inside itself, and puts the screen
## below to sleep. Driven with real key events through a scene runner on a small screen: a list and a button, the message box beside
## them under the same root (as in Math Practice: Godot's arrow-key search stays under one top-level control, so only a modal that
## shares the screen's root can lose the arrows to it), and a `CanvasLayer` for dialogs.
##
## Teaches: testing focus through the viewport (`simulate_key_pressed`, `gui_get_focus_owner`) rather than by calling handlers.

var _runner: GdUnitSceneRunner
var _screen: Control
var _list: ItemList
var _below: Button
var _layer: CanvasLayer
var _messages: MessageQueue
var _view: MessageBoxView
var _modals: ModalHost


func before_test() -> void:
	_screen = auto_free(Control.new())
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_list = ItemList.new()
	_list.position = Vector2(20, 20)
	_list.size = Vector2(200, 100)
	for item in ["a", "b"]:
		_list.add_item(item)
	_screen.add_child(_list)
	_below = Button.new()
	_below.text = "below"
	_below.position = Vector2(20, 300)                     # under the list and under the dialog: the arrows would reach it
	_screen.add_child(_below)
	_layer = CanvasLayer.new()
	_screen.add_child(_layer)
	_view = load("res://src/ui/message_box.tscn").instantiate()
	_screen.add_child(_view)
	_runner = scene_runner(_screen)
	_messages = MessageQueue.new(GameClock)
	_modals = ModalHost.new(_screen, [_list, _below], _list)
	_modals.attach(_messages, _view)
	_list.grab_focus()
	await await_idle_frame()


func after_test() -> void:
	_messages.discard()


func _focus() -> Control:
	return _screen.get_viewport().gui_get_focus_owner()


## A dialog with two buttons side by side, in the middle of the screen.
func _dialog() -> Control:
	var dialog := HBoxContainer.new()
	dialog.position = Vector2(200, 180)
	for label in ["One", "Two"]:
		var button := Button.new()
		button.text = label
		dialog.add_child(button)
	dialog.ready.connect(func() -> void: (dialog.get_child(0) as Button).grab_focus())
	return dialog


func test_a_message_gives_the_focus_back_to_the_control_that_had_it() -> void:
	_messages.post("Q", "?", PackedStringArray(["Yes", "No"]))
	assert_bool(_view.button_row.get_child(0).has_focus()).is_true()
	assert_bool(_modals.is_open()).is_true()
	_runner.simulate_key_pressed(KEY_ENTER)
	await await_idle_frame()
	assert_bool(_messages.is_open()).is_false()
	assert_object(_focus()).is_same(_list)
	assert_bool(_modals.is_open()).is_false()


func test_the_arrows_and_tab_stay_inside_a_message() -> void:
	_messages.post("Q", "?", PackedStringArray(["Yes", "No"]))
	for key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB, KEY_UP, KEY_DOWN]:
		_runner.simulate_key_pressed(key)
		await await_idle_frame()
		assert_bool(_view.is_ancestor_of(_focus())).override_failure_message("key %s took the focus to %s" % [key, _focus()]).is_true()


func test_the_arrows_and_tab_stay_inside_a_dialog_and_closing_it_gives_the_focus_back() -> void:
	var dialog := _dialog()
	_modals.open(dialog, _screen)                                           # (under the screen's own root, as Math Practice's overlay)
	await await_idle_frame()
	assert_bool(dialog.is_ancestor_of(_focus())).is_true()
	for key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB, KEY_DOWN]:
		_runner.simulate_key_pressed(key)
		await await_idle_frame()
		assert_bool(dialog.is_ancestor_of(_focus())).override_failure_message("key %s took the focus to %s" % [key, _focus()]).is_true()
	dialog.queue_free()
	await await_idle_frame()
	assert_object(_focus()).is_same(_list)


func test_the_screen_below_sleeps_while_a_modal_is_open() -> void:
	_messages.post("Q", "?")
	assert_int(_list.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_int(_below.get_focus_mode_with_override()).is_equal(Control.FOCUS_NONE)
	_messages.close_current()
	assert_int(_list.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	assert_int(_below.get_focus_mode_with_override()).is_equal(Control.FOCUS_ALL)


func test_a_message_over_a_dialog_gives_the_focus_back_to_the_dialog() -> void:
	var dialog := _dialog()
	_modals.open(dialog, _layer)
	await await_idle_frame()
	var second := dialog.get_child(1) as Button
	second.grab_focus()
	_messages.post("Q", "?")
	_runner.simulate_key_pressed(KEY_ENTER)
	await await_idle_frame()
	assert_object(_focus()).is_same(second)
	assert_int(_list.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)    # (the dialog is still open: the screen still sleeps)
	dialog.queue_free()
	await await_idle_frame()
	assert_object(_focus()).is_same(_list)
	assert_int(_list.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)


func test_a_dialog_opened_by_the_answer_to_a_message_keeps_its_focus() -> void:
	# (sign-in: No to "exit?" with no player opens the new-player dialog again inside the answer handler)
	var message := _messages.post("Q", "?")
	var dialog := _dialog()
	message.closed.connect(func(_choice: int) -> void: _modals.open(dialog, _layer))
	_runner.simulate_key_pressed(KEY_ENTER)
	await await_idle_frame()
	assert_bool(dialog.is_ancestor_of(_focus())).is_true()
	assert_bool(_modals.is_open()).is_true()


func test_a_dialog_freed_under_its_message_leaves_the_focus_to_the_message() -> void:
	# (sign-in: Esc in the new-player dialog with no player frees it and asks "exit?" at once)
	var dialog := _dialog()
	_modals.open(dialog, _layer)
	await await_idle_frame()
	dialog.queue_free()
	_messages.post("Q", "?")
	await await_idle_frame()
	assert_bool(_view.is_ancestor_of(_focus())).is_true()
	_runner.simulate_key_pressed(KEY_ENTER)
	await await_idle_frame()
	assert_object(_focus()).is_same(_list)                                   # (its own focus owner is gone: the home control)


func test_the_next_message_of_the_queue_gives_the_focus_back_once_to_the_first_owner() -> void:
	_messages.post("A", "1")
	_messages.post("B", "2")
	_runner.simulate_key_pressed(KEY_ENTER)
	await await_idle_frame()
	assert_str(_messages.current.title).is_equal("B")
	assert_bool(_view.is_ancestor_of(_focus())).is_true()
	_runner.simulate_key_pressed(KEY_ENTER)
	await await_idle_frame()
	assert_object(_focus()).is_same(_list)
