class_name TestLogScreenLegacy
extends GdUnitTestSuite
## The ORIGINAL's log screen (`DoDataBank` 0x41e18f): the eight scanner lights it draws (bundle 476, 228 x 26 each) and the entries of its second
## game. The screen's behaviour is tested on dev in tests/engine/test_log_screen.gd.

const SCENE := "res://src/ui/log_screen.tscn"

var _screen: LogScreen


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	_screen = scene_runner(SCENE).scene() as LogScreen


func test_the_scan_pictures_are_the_eight_lights_of_bundle_476() -> void:
	assert_int(LogScreen.scan_pictures().size()).is_equal(9)
	for picture in LogScreen.scan_pictures():
		assert_object(picture.get_size()).is_equal(Vector2(228, 26))
	assert_object(_screen.lights.position).is_equal(Vector2(368, 278))


func test_the_expert_game_lists_entries_of_game_two() -> void:
	_screen.start(15)
	_screen.advance_scan(CanisterLog.scan_ticks())
	assert_str((_screen.rows.get_child(0) as Label).text).is_equal("ENTRY 2.02")
	assert_str(_screen.entry_text.text).starts_with("ENTRY 2.02")
