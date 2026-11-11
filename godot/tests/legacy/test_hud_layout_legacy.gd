class_name TestHudLayoutLegacy
extends GdUnitTestSuite
## Teaches: checking generated data against its source. The original's `HudLayout` is produced from numbers decompiled with Ghidra (`extracted/tables/hud_gauges.json`); these
## tests re-read the JSON and compare, so a wrong generator or a hand edit shows up here. (The rules every layout keeps: tests/engine/test_hud_layout.gd.)

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


const WINDOW := Rect2i(0, 0, 640, 400)

var _layout: HudLayout = load(LegacyPack.ROOT + "data/ui/hud_layout.tres")


func _json(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://../extracted/tables/%s.json" % name))


func test_gauge_positions_are_the_decompiled_ones() -> void:
	var gauges := _json("hud_gauges")
	for i in 6:
		assert_object(_layout.tank_positions[i]).is_equal(Vector2(gauges.tanks.x[i], gauges.tanks.y))
	for i in 4:
		assert_object(_layout.oxygen_positions[i]).is_equal(Vector2(gauges.oxygen.x0 + gauges.oxygen.step_x * i, gauges.oxygen.y))
	assert_int(_layout.ink_positions.size()).is_equal(21)
	for i in 21:
		assert_object(_layout.ink_positions[i]).is_equal(Vector2(gauges.ink_pellets.xy[i][0], gauges.ink_pellets.xy[i][1]))




func test_the_original_console_ends_four_lines_above_the_window_bottom_and_is_616_wide() -> void:
	var console := Rect2i(_layout.bezel_position, _layout.bezel.get_size())
	assert_int(console.end.y).is_equal(396)             # the frame paints the last 4 lines
	assert_int(_layout.bezel_position.x).is_equal(12)
	assert_float(_layout.bezel.get_size().x).is_equal(616.0)         # 12 .. 628: the playfield plus 4 px frame each side
