class_name TestLayoutFromData
extends GdUnitTestSuite
## Teaches: keeping a promise with two kinds of test ("layout from data, not from textures or fonts").
## The promise: where a hit area is, how big a panel is and what a random draw is made from never depends on the
## pictures or the font that happen to be loaded, so a skin with other pictures or another font cannot move a button or
## change a draw. Test 1 PINS each number that is data now to what the textures and the font say today (the numbers did not
## change when they moved into the data). Test 2 READS THE SOURCE and fails if layout code asks a texture or a font for a size again.

# --- the numbers equal the pictures' and the font's today ------------------------------------------------

func test_the_calculator_and_answer_box_sizes_are_the_pictures_sizes() -> void:
	var layout: CalculatorLayout = Catalog.calculator_layout()
	assert_object(layout.picture_size).is_equal(Vector2i(layout.picture.get_size()))
	assert_object(layout.answer_size).is_equal(Vector2i(layout.answer_panel.get_size()))


func test_the_problem_screens_size_is_the_pictures_size() -> void:
	var layout := Catalog.screen_layout()
	assert_object(layout.background_size).is_equal(Vector2i(layout.background.get_size()))


func test_the_consoles_sizes_are_the_pictures_sizes_and_each_gauges_area_holds_its_icons() -> void:
	var layout: HudLayout = Catalog.hud_layout()
	assert_object(layout.bezel_size).is_equal(Vector2i(layout.bezel.get_size()))
	for pair: Array in [[layout.ship_textures, layout.ship_size], [layout.computer_textures, layout.computer_size]]:
		for texture: Texture2D in pair[0]:
			assert_object(pair[1]).is_equal(Vector2i(texture.get_size()))
	for gauge: Array in [[layout.tank_positions, layout.tank_rect, layout.tank_full, layout.tank_empty], [layout.oxygen_positions, layout.oxygen_rect, layout.oxygen_full, layout.oxygen_empty],
			[layout.ink_positions, layout.ink_rect, layout.ink_full, layout.ink_empty]]:
		assert_object((gauge[2] as Texture2D).get_size()).is_equal((gauge[3] as Texture2D).get_size())
		for position in gauge[0] as PackedVector2Array:
			assert_bool(Rect2(gauge[1]).encloses(Rect2(position, (gauge[2] as Texture2D).get_size()))).override_failure_message("an icon at %s is not inside %s" % [position, gauge[1]]).is_true()


func test_the_lcd_glyph_sizes_are_the_glyph_pictures_sizes() -> void:
	var layout: CalculatorLayout = Catalog.calculator_layout()
	assert_int(layout.digit_sizes.size()).is_equal(10)
	for digit in 10:
		assert_object(layout.digit_sizes[digit]).is_equal(Vector2i(layout.digit_textures[digit].get_size()))
	assert_object(layout.point_size).is_equal(Vector2i(layout.point_texture.get_size()))
	assert_object(layout.slash_size).is_equal(Vector2i(layout.slash_texture.get_size()))
	assert_object(layout.minus_size).is_equal(Vector2i(layout.minus_texture.get_size()))


func test_the_ballast_panels_hit_areas_are_the_buttons_pictures_sizes() -> void:
	for type_id in [28, 29]:
		var panel := _diagram(type_id) as BallastPanelDiagram
		var weights: Dictionary = panel.spec["weights"]
		var total: Dictionary = panel.spec["total"]
		assert_object(panel.slot_size()).is_equal(panel._textures[weights["slot_pic"]].get_size())
		assert_object(panel.done_size()).is_equal(panel._textures[total["idle_pic"]].get_size())
		# the edges of the rectangles: the last pixel inside is a hit, the next one is not
		var corner := panel.slot_position(4) + panel.slot_size()
		assert_int(panel.button_at(corner - Vector2(1, 1))).is_equal(4)
		assert_int(panel.button_at(corner)).is_equal(-1)
		var done := panel.vector(total["pos"]) + panel.done_size()
		assert_int(panel.button_at(done - Vector2(1, 1))).is_equal(panel.slot_count())
		assert_int(panel.button_at(done)).is_equal(-1)


func test_the_lock_wheels_centre_and_radius_come_from_the_datas_size_not_from_the_picture() -> void:
	var lock := _diagram(0) as LockDiagram
	var wheel: Dictionary = lock.spec["answer_wheel"]
	assert_object(lock.answer_wheel_centre()).is_equal(lock.vector(wheel["pos"]) + lock.vector(wheel["size"]) / 2.0)
	assert_float(lock.answer_wheel_radius()).is_equal(float(wheel["size"][0]) / 2.0)
	wheel["size"] = [100, 100]                                                # another size in the data, the same pictures
	assert_object(lock.answer_wheel_centre()).is_equal(lock.vector(wheel["pos"]) + Vector2(50, 50))
	assert_float(lock.answer_wheel_radius()).is_equal(50.0)


func test_a_wheel_label_is_centred_by_the_drawing_not_by_the_font() -> void:
	var lock := _diagram(0) as LockDiagram
	var labels := lock.items.filter(func(item: DiagramItem) -> bool: return item.kind == DiagramItem.Kind.TEXT and item.align == DiagramItem.Align.MIDDLE)
	assert_int(labels.size()).is_equal(16)                                    # eight labels on each wheel
	var first: DiagramItem = labels[0]
	assert_object(first.position).is_equal(lock.label_position("operand", 0, 0))   # the item holds the spot itself


func test_the_bubble_rules_hold_the_pictures_sizes() -> void:
	var rules := Catalog.bubble_rules()
	var frames := Catalog.fx_frames()
	assert_int(rules.picture_sizes.size()).is_equal(8)
	for picture in 8:
		var texture := frames.get_frame_texture(&"all", picture)
		assert_object(rules.picture_sizes[picture]).is_equal(Vector2i(texture.get_size()))
		assert_int(rules.picture_height(picture)).is_equal(int(texture.get_height()))
	for slot in rules.slot_count():
		var first := frames.get_frame_texture(&"all", rules.slot_first_picture[slot])
		assert_int(rules.spawn_width(slot)).is_equal(int(first.get_width()) & ~1)


func test_the_line_separation_is_the_line_height_minus_the_theme_fonts_height() -> void:
	var layout := Catalog.screen_layout()
	var font := ThemeDB.get_project_theme().default_font
	assert_int(layout.line_separation).is_equal(layout.line_height - int(font.get_height(layout.font_size())))


# --- layout code does not ask a texture or a font ---------------------------------------------------------

## Folders and files whose code is layout or rules. A picture's or font's size may not be read here (but see ALLOWED).
const LAYOUT_CODE: Array[String] = [
	"res://src/problems", "res://src/ui", "res://src/gameplay/bubbles.gd", "res://src/story/surface_ship_screen.gd",
]
## What asks a texture or a font for a size or a metric.
const FORBIDDEN: Array[String] = [
	".get_size(", ".get_width(", ".get_height(", "get_string_size", "get_ascent", "get_descent", "get_line_height",
	"get_theme_default_font", "get_theme_font(", "get_frame_texture", "get_minimum_size", ".get_rect(",
]
## "file::function": code that DRAWS. Drawing is the view: it may ask the font how wide a string is to centre it, and the
## picture how wide it is to mirror it, because it moves no hit area and decides no rule.
const ALLOWED: Dictionary = {
	"res://src/problems/diagrams/diagram_base.gd::_draw_picture": "mirrors a picture about its own right edge",
	"res://src/problems/diagrams/diagram_base.gd::_draw_text": "centres, right-aligns and baselines a string with the font that draws it",
}


func test_layout_code_reads_no_texture_or_font_size() -> void:
	var found: Array[String] = []
	for path in _scripts():
		var function := ""
		var line_number := 0
		for code in SourceScan.code_lines_of(path):               # (without comments and strings; the line numbers are the file's)
			line_number += 1
			var line := code
			if line.begins_with("func ") or line.begins_with("static func "):
				function = line.get_slice("(", 0).get_slice("func ", 1).strip_edges()
			for token in FORBIDDEN:
				if code.contains(token) and not ALLOWED.has("%s::%s" % [path, function]):
					found.append("%s:%d (%s)  %s" % [path, line_number, function, line.strip_edges()])
	assert_array(found).override_failure_message("layout code asks a texture or a font for a size:\n" + "\n".join(found)).is_empty()


func test_every_exception_is_still_needed() -> void:
	for key: String in ALLOWED:
		var path := key.get_slice("::", 0)
		var function := key.get_slice("::", 1)
		var source := FileAccess.get_file_as_string(path)
		assert_bool(source.contains("func " + function + "(")).override_failure_message("%s is gone: remove the exception" % key).is_true()


func _scripts() -> Array[String]:
	var found: Array[String] = []
	for root in LAYOUT_CODE:
		if root.ends_with(".gd"):
			found.append(root)
		else:
			_collect(root, found)
	found.sort()
	return found


func _collect(dir: String, found: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), found)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))


func _diagram(type_id: int) -> DiagramBase:
	var type := Catalog.problem_type(type_id)
	var level := type.levels_available.find(1)
	return auto_free(DiagramFactory.plain(ProblemInstance.build(type, level, 0, 0))) as DiagramBase
