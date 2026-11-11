class_name TestLayoutFromDataLegacy
extends GdUnitTestSuite
## Teaches: the original's numbers that became data equal what its pictures say (the importer wrote them from the pictures). The promise that layout code
## reads the data and not the pictures: tests/engine/test_layout_from_data.gd.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_lock_wheels_centre_and_radius_are_the_pictures() -> void:
	var type := Catalog.problem_type(0)
	var lock := auto_free(DiagramFactory.create(ProblemInstance.build(type, type.levels_available.find(1), 0, 0))) as LockDiagram
	var picture: Texture2D = lock._textures[int(lock.spec["answer_wheel"]["first_pic"])]
	assert_object(lock.answer_wheel_centre()).is_equal(lock.vector(lock.spec["answer_wheel"]["pos"]) + picture.get_size() / 2.0)
	assert_float(lock.answer_wheel_radius()).is_equal(picture.get_size().x / 2.0)


## The sizes of the console the importer wrote from the pictures equal what the pictures say, and the area of each gauge (the rectangle the original redraws, `docs/data/hud_gauges.json`) holds its icons.
func test_the_consoles_sizes_are_the_pictures_and_each_gauges_area_holds_its_icons() -> void:
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


func test_the_menu_popups_open_where_the_titles_are() -> void:
	var layout: MenuBarLayout = load("res://data/ui/menu_layout.tres")
	for practice in [false, true]:
		var bar := GameMenuBar.new()
		bar.practice_mode = practice
		add_child(bar)
		var x := 0.0
		for index in bar.get_menu_count():
			assert_int(layout.popup_x(index)).override_failure_message("menu %d, practice %s" % [index, practice]).is_equal(int(x))
			# the width the MenuBar gives a title: the text, the button style's margins and the gap between titles
			x += bar.get_theme_font(&"font").get_string_size(bar.get_menu_title(index), HORIZONTAL_ALIGNMENT_LEFT, -1, bar.get_theme_font_size(&"font_size")).x \
					+ bar.get_theme_stylebox(&"normal").get_minimum_size().x + bar.get_theme_constant(&"h_separation")
		bar.queue_free()


## `GetFontLineHeight` (0x414dc4): `SetFont` stores max(Arial cell 19, bitmap font height 20) = 20, and every text line advances by it.
func test_the_text_lines_are_20_px_apart_with_no_extra_separation() -> void:
	var layout := Catalog.screen_layout()
	assert_int(layout.font_cell_height).is_equal(19)
	assert_int(layout.line_height).is_equal(20)
	assert_int(layout.line_separation).is_equal(0)
