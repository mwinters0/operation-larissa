class_name TestHintSystem
extends GdUnitTestSuite
## Teaches: the "bit mask as a set" idiom and testing pure logic without any node.

var _hints: HintSystem


func before_test() -> void:
	_hints = HintSystem.new()


func test_a_new_player_has_not_seen_any_hint() -> void:
	assert_int(_hints.unseen_mask).is_equal(0x7F)
	for id in HintSystem.COUNT:
		assert_bool(_hints.has_been_shown(id)).is_false()


func test_each_hint_is_shown_once() -> void:
	assert_bool(_hints.take(HintSystem.LOW_OXYGEN)).is_true()
	assert_bool(_hints.take(HintSystem.LOW_OXYGEN)).is_false()
	assert_bool(_hints.has_been_shown(HintSystem.LOW_OXYGEN)).is_true()
	assert_bool(_hints.take(HintSystem.CONTROLS)).is_true()             # others are untouched
	assert_int(_hints.unseen_mask).is_equal(0x7F & ~0b11)


func test_switching_hints_off_shows_nothing_and_keeps_them_unseen() -> void:
	_hints.enabled = false
	assert_bool(_hints.take(HintSystem.CONTROLS)).is_false()
	assert_bool(_hints.has_been_shown(HintSystem.CONTROLS)).is_false()
	_hints.enabled = true
	assert_bool(_hints.take(HintSystem.CONTROLS)).is_true()


func test_unknown_ids_are_ignored() -> void:
	assert_bool(_hints.take(-1)).is_false()
	assert_bool(_hints.take(HintSystem.COUNT)).is_false()


func test_reset_makes_every_hint_new_again() -> void:
	_hints.take(2)
	_hints.reset()
	assert_bool(_hints.take(2)).is_true()


func test_texts_are_readable() -> void:
	for id in HintSystem.COUNT:
		var text := HintSystem.text_for(id)
		assert_str(text).is_not_empty()
		for c in text:
			assert_bool(c.unicode_at(0) >= 32 or c == "\n").override_failure_message("hint %d has a control character" % id).is_true()

	# a hint's text keeps the original's key pictures as characters 1-31; `printable` writes them out
	assert_str(HintSystem.printable("Press \u0011 to fire, \u0017 to go on.")).is_equal("Press Space to fire, Enter to go on.")
	assert_str(HintSystem.printable("a\u001ab")).is_equal("a→b")
	# the four arrows are the glyphs 0x19 left, 0x1a right, 0x1b down, 0x1c up (Help "Using the Keyboard" lists down, up, left, right)
	assert_str(HintSystem.printable("\u0019\u001a\u001b\u001c")).is_equal("←→↓↑")
	# the calculator's key caps: tab (the original turns it into glyph 0x13), 0x15 and 0x0f are N, S and R
	assert_str(HintSystem.printable("Press \t, then \u0015 or \u000f.")).is_equal("Press N, then S or R.")
	assert_str(HintSystem.printable("two\nlines")).is_equal("two\nlines")


func test_game_state_owns_one_hint_set() -> void:
	GameState.hints.reset()
	assert_bool(GameState.hints.take(5)).is_true()
	assert_bool(GameState.hints.take(5)).is_false()
	GameState.hints.reset()
