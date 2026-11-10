class_name TestCalculatorLayoutLegacy
extends GdUnitTestSuite
## The original's calculator layout (docs/data/console_layout.json from the decompiled hotspot table): where the picture sits, the 22 key
## rectangles, the LCD cell, the answer box. These check the legacy pack's data; the widget's behaviour on any layout is tests/engine/test_calculator_layout.gd.

var _layout: CalculatorLayout = load(LegacyPack.ROOT + "data/ui/calculator_layout.tres") if LegacyPack.present() else null


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_calculator_sits_at_the_bottom_right_inside_the_window() -> void:
	var picture := Rect2i(_layout.picture_position, _layout.picture.get_size())
	assert_object(picture).is_equal(Rect2i(336, 266, 292, 130))
	assert_bool(Rect2i(0, 0, 640, 400).encloses(picture)).is_true()


func test_digit_keys_form_the_grid_of_the_picture() -> void:
	# 7 8 9 / on the top row; 0 . = + on the bottom row; same column x for 7 4 1 0
	assert_int(_layout.key_rect("7").position.x).is_equal(_layout.key_rect("0").position.x)
	assert_int(_layout.key_rect("7").position.y).is_less(_layout.key_rect("4").position.y)
	assert_int(_layout.key_rect("8").position.x).is_greater(_layout.key_rect("7").position.x)
	assert_int(_layout.key_rect("+").position.x).is_equal(_layout.key_rect("/").position.x)
	assert_int(_layout.key_rect("Enter").position.x).is_equal(_layout.key_rect("F").position.x)   # left column


func test_hotspots_match_the_original_json() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/data/console_layout.json"))
	for entry in data.calculator.keys:
		var r: Array = entry.rect
		assert_object(_layout.key_rect(entry.key)).is_equal(Rect2i(r[0], r[1], r[2], r[3]))


func test_the_display_cell_and_the_answer_box_are_the_originals() -> void:
	assert_object(_layout.display_origin_calculator).is_equal(Vector2i(352, 282))
	assert_int(_layout.digits_right).is_equal(160)
	assert_int(_layout.advance).is_equal(16)
	assert_object(_layout.answer_position).is_equal(Vector2i(332, 270))
