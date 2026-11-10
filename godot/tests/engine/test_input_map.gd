class_name TestInputMap
extends GdUnitTestSuite


func test_game_actions_exist() -> void:
	for action in ["sub_left", "sub_right", "sub_up", "sub_down", "fire_ink", "show_problem", "lock_stop", "quit_to_menu"]:
		assert_bool(InputMap.has_action(action)).override_failure_message("missing action " + action).is_true()
		assert_int(InputMap.action_get_events(action).size()).is_greater(0)


func test_arrow_keys_are_bound() -> void:
	var left := InputEventKey.new()
	left.keycode = KEY_LEFT
	assert_bool(InputMap.event_is_action(left, "sub_left")).is_true()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	assert_bool(InputMap.event_is_action(space, "fire_ink")).is_true()
