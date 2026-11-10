class_name TestLogScreen
extends GdUnitTestSuite
## Teaches: testing a screen whose animation is a function of TICKS. The scan is 240 ticks (3.3 s) and the rules own that length
## (`CanisterLog.scan_ticks()`), so the tests do not wait: they hand the screen the ticks (`advance_scan`) and read which picture the
## rules (`CanisterLog.scan_picture`) show at each tick.
## The screen is `DoDataBank` (0x41e18f) with `AnimateLogScan` (0x41e092) and `PlayLogEntrySpeech` (0x41dfc8).
## The log is dev's test campaign `test_c` (tools/dev_pack/test_sectors/batch_c.py): sectors 140-148 unlock the entries 3 1 4 9 2 6 5 8 7 in that order, so
## sector 142 lists the entries 1 3 4 (newest 4), sector 143 lists 1 3 4 9 (newest 9) and sector 148 lists all nine (newest 7).
## The original's scanner lights and its second game are tests/legacy/test_log_screen_legacy.gd.

const SCENE := "res://src/ui/log_screen.tscn"

var _runner: GdUnitSceneRunner
var _screen: LogScreen
var _probe: AudioProbe


func before_test() -> void:
	_runner = scene_runner(SCENE)
	_screen = _runner.scene() as LogScreen
	_probe = AudioProbe.new()


func after_test() -> void:
	_probe.stop()
	Audio.stop_voice()
	Audio.stop_sfx()


## Opens the log of `sector` and lets the whole scan pass.
func _open(sector: int) -> void:
	_screen.start(sector)
	_screen.advance_scan(CanisterLog.scan_ticks())


func test_the_scan_is_48_pictures_of_5_ticks_and_ends_all_green() -> void:
	assert_int(CanisterLog.scan_ticks()).is_equal(240)                              # 240 ticks = 3.29 s
	for step in 48:
		for tick in range(step * 5, step * 5 + 5):
			assert_int(CanisterLog.scan_picture(tick)).override_failure_message("tick %d" % tick).is_equal(step % 8)
	assert_int(CanisterLog.scan_picture(239)).is_equal(7)
	assert_int(CanisterLog.scan_picture(240)).is_equal(8)                         # the all-green picture
	assert_int(CanisterLog.scan_picture(100000)).is_equal(8)


func test_the_screen_shows_the_picture_of_the_tick_the_rules_give_it() -> void:
	_screen.start(142)
	assert_object(_screen.lights.texture).is_same(LogScreen.scan_pictures()[0])  # the red light starts at the left
	_screen.advance_scan(5)
	assert_object(_screen.lights.texture).is_same(LogScreen.scan_pictures()[1])
	_screen.advance_scan(4)                                                      # tick 9: still the second picture
	assert_object(_screen.lights.texture).is_same(LogScreen.scan_pictures()[1])
	assert_bool(_screen.scanning).is_true()
	_screen.advance_scan(CanisterLog.scan_ticks() - 9 - 1)                         # one tick before the end
	assert_bool(_screen.scanning).is_true()
	_screen.advance_scan(1)
	assert_bool(_screen.scanning).is_false()
	assert_object(_screen.lights.texture).is_same(LogScreen.scan_pictures()[8])


func test_the_scanner_has_eight_lights_and_the_all_green_picture() -> void:
	assert_int(LogScreen.scan_pictures().size()).is_equal(CanisterLog.SCAN_PICTURES_PER_SWEEP + 1)
	for picture in LogScreen.scan_pictures():
		assert_object(picture).is_not_null()
	assert_object(_screen.lights.position).is_equal(Vector2(368, 278))


func test_the_screen_opens_on_the_newest_entry_with_the_scanner_sound() -> void:
	_screen.start(142)                                                              # entries 1, 3, 4; the newest is 4
	assert_bool(_screen.scanning).is_true()
	assert_int(_screen.shown_entry()).is_equal(4)
	assert_str(_screen.entry_text.text).starts_with("Test log entry 4")
	assert_int(_screen.row_count()).is_equal(4)                                  # three entries + DONE
	assert_int(_screen.selected_row()).is_equal(2)
	assert_array(_probe.sfx).is_equal([&"scanner"])
	_screen.advance_scan(CanisterLog.scan_ticks())
	assert_bool(_screen.scanning).is_false()
	assert_object(_screen.lights.texture).is_same(LogScreen.scan_pictures()[8])    # all green at the end
	assert_int(_probe.voice.size()).is_equal(1)                                  # ... and the entry is read aloud
	assert_array(Array(_probe.voice[0])).is_equal(Array(Catalog.voice_cues().clips("log_3")))


func test_the_menu_lists_captions_and_done_at_their_places() -> void:
	await _open(143)
	var labels: Array[String] = []
	for label in _screen.rows.get_children():
		labels.append((label as Label).text)
	var word := Catalog.text(LogScreen.STRING_ENTRY)
	assert_array(labels).is_equal(["%s 3.01" % word, "%s 3.03" % word, "%s 3.04" % word, "%s 3.09" % word, Catalog.text(LogScreen.STRING_DONE)])
	assert_object((_screen.rows.get_child(0) as Label).position).is_equal(Vector2(362, 88))
	assert_object((_screen.rows.get_child(4) as Label).position).is_equal(Vector2(362, 168))
	assert_str(_screen.title_label.text).is_equal(Catalog.text(LogScreen.STRING_TITLE))
	assert_str(_screen.menu_title.text).is_equal(Catalog.text(LogScreen.STRING_MENU))


func test_the_highlight_is_a_white_box_under_black_text() -> void:
	await _open(142)
	assert_object(_screen.cursor.position).is_equal(Vector2(360, 128))           # 2 px left of the text of row 2
	assert_object(_screen.cursor.size).is_equal(Vector2(CanisterLog.ROW_SIZE.x, Catalog.screen_layout().line_height))     # (a line high, see `_build_rows`)
	var selected := _screen.rows.get_child(2) as Label
	var other := _screen.rows.get_child(0) as Label
	assert_object(selected.get_theme_color("font_color")).is_equal(Color.BLACK)
	assert_object(other.get_theme_color("font_color")).is_not_equal(Color.BLACK)


func test_keys_do_nothing_during_the_scan() -> void:
	_screen.start(142)
	_runner.simulate_key_pressed(KEY_UP)
	_runner.simulate_key_pressed(KEY_ESCAPE)
	assert_int(_screen.selected_row()).is_equal(2)
	var closed := [false]
	_screen.finished.connect(func() -> void: closed[0] = true)
	assert_bool(closed[0]).is_false()
	_screen.advance_scan(CanisterLog.scan_ticks())


func test_arrows_move_the_highlight_and_wrap() -> void:
	await _open(142)
	Audio.stop_voice()
	_runner.simulate_key_pressed(KEY_DOWN)
	assert_int(_screen.selected_row()).is_equal(3)                               # DONE
	_runner.simulate_key_pressed(KEY_DOWN)
	assert_int(_screen.selected_row()).is_equal(0)                               # wraps to the first entry
	_runner.simulate_key_pressed(KEY_UP)
	assert_int(_screen.selected_row()).is_equal(3)
	_runner.simulate_key_pressed(KEY_LEFT)
	assert_int(_screen.selected_row()).is_equal(3)                               # no second column with 3 entries: stays on DONE
	assert_object(_screen.cursor.position).is_equal(Vector2(360, 148))


func test_the_highlight_move_does_not_change_the_entry_until_enter() -> void:
	await _open(142)
	_screen.press(&"up")
	assert_int(_screen.selected_row()).is_equal(1)
	assert_int(_screen.shown_entry()).is_equal(4)                                # still the newest
	_probe.clear()
	_screen.press(&"enter")
	assert_int(_screen.shown_entry()).is_equal(3)                                # entries 1 3 4: row 1 is entry 3
	assert_str(_screen.entry_text.text).starts_with("Test log entry 3")
	assert_array(Array(_probe.voice[0])).is_equal(Array(Catalog.voice_cues().clips("log_2")))


func test_the_digit_keys_8_2_4_6_move_like_arrows() -> void:
	await _open(148)                                                             # nine entries and DONE: two columns of eight rows
	Audio.stop_voice()
	assert_int(_screen.selected_row()).is_equal(6)                               # entry 7 is the newest: the 7th row
	_runner.simulate_key_pressed(KEY_6)
	assert_int(_screen.selected_row()).is_equal(9)                               # right column: row 6 + 8 is past the end, so DONE
	_runner.simulate_key_pressed(KEY_4)
	assert_int(_screen.selected_row()).is_equal(1)                               # left column, row 9 - 8
	_runner.simulate_key_pressed(KEY_8)
	assert_int(_screen.selected_row()).is_equal(0)
	_runner.simulate_key_pressed(KEY_2)
	assert_int(_screen.selected_row()).is_equal(1)


func test_digits_are_thrown_away_while_the_speech_plays_but_arrows_cut_it() -> void:
	await _open(148)
	if not Audio.is_voice_playing():
		return                                                                   # (voice off in this environment: nothing to throw away)
	_runner.simulate_key_pressed(KEY_8)
	assert_int(_screen.selected_row()).is_equal(6)                               # swallowed, the speech goes on
	assert_bool(Audio.is_voice_playing()).is_true()
	_runner.simulate_key_pressed(KEY_UP)
	assert_bool(Audio.is_voice_playing()).is_false()                             # an arrow cuts the speech ...
	assert_int(_screen.selected_row()).is_equal(5)                               # ... and then moves


func test_enter_on_done_and_escape_leave() -> void:
	await _open(142)
	var closed := [0]
	_screen.finished.connect(func() -> void: closed[0] += 1)
	_screen.press(&"down")                                                       # DONE
	_runner.simulate_key_pressed(KEY_ENTER)
	assert_int(closed[0]).is_equal(1)
	assert_bool(Audio.is_voice_playing()).is_false()


func test_escape_leaves_from_any_row() -> void:
	await _open(140)
	var closed := [0]
	_screen.finished.connect(func() -> void: closed[0] += 1)
	_runner.simulate_key_pressed(KEY_ESCAPE)
	assert_int(closed[0]).is_equal(1)
	_runner.simulate_key_pressed(KEY_ESCAPE)                                     # once only
	assert_int(closed[0]).is_equal(1)


func test_a_click_on_another_row_selects_it_and_a_second_click_shows_the_entry() -> void:
	await _open(143)                                                               # entries 1 3 4 9, newest 9 on row 3
	assert_int(_screen.shown_entry()).is_equal(9)
	_probe.clear()
	_screen.click_row(2)
	assert_int(_screen.selected_row()).is_equal(2)
	assert_int(_screen.shown_entry()).is_equal(9)                                # selecting does not show
	assert_int(_probe.voice.size()).is_equal(0)
	_screen.click_row(2)
	assert_int(_screen.shown_entry()).is_equal(4)
	assert_str(_screen.entry_text.text).starts_with("Test log entry 4")
	assert_int(_probe.voice.size()).is_equal(1)


func test_a_click_on_done_twice_leaves() -> void:
	await _open(143)
	var closed := [0]
	_screen.finished.connect(func() -> void: closed[0] += 1)
	_screen.click_row(4)
	assert_int(closed[0]).is_equal(0)
	_screen.click_row(4)
	assert_int(closed[0]).is_equal(1)


func test_the_row_labels_catch_mouse_clicks() -> void:
	await _open(143)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	(_screen.rows.get_child(1) as Label).gui_input.emit(event)
	assert_int(_screen.selected_row()).is_equal(1)


## The scanner pictures depend on the skin and the pack chain: nothing keeps them, so a skin chosen later (or a pack) is seen.
func test_the_scanner_pictures_are_the_skins_in_use() -> void:
	var original := LogScreen.scan_pictures()                         # (asked first in the original skin)
	var marker := load("res://tests/skins/tiny/marker.png") as Texture2D
	var skin := GameSkin.new()
	skin.pictures = {GameSkin.key_of(Assets.problem_art_path(Assets.number_of(&"problem_art", &"log_scan_0"))): marker}
	var skinned: Array[Texture2D] = SkinChoice.within(skin, LogScreen.scan_pictures)
	assert_object(skinned[0]).is_same(marker)
	assert_object(SkinChoice.within(skin, LogScreen.scan_picture.bind(0))).is_same(marker)
	assert_object(original[0]).is_not_same(marker)
	assert_object(LogScreen.scan_pictures()[0]).is_same(original[0])          # (and the original's again outside the skin)
