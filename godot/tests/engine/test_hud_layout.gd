class_name TestHudLayout
extends GdUnitTestSuite
## Teaches: checking a pack's HUD layout against the rules every layout must keep: the console sits at the bottom of the window, aligned with the playfield, every
## icon lies inside it and the pictures of a gauge have one size. (The original's gauge positions, re-read from the decompiled numbers: tests/legacy/test_hud_layout_legacy.gd.)

const WINDOW := Rect2i(0, 0, 640, 400)

var _layout: HudLayout = Catalog.hud_layout()


func test_console_bottom_is_the_window_bottom_and_inside_it() -> void:
	var console := Rect2i(_layout.bezel_position, _layout.bezel.get_size())
	assert_int(console.end.y).is_less_equal(WINDOW.end.y)
	assert_int(console.end.y).is_equal(396)             # the frame paints the last 4 lines
	assert_bool(WINDOW.encloses(console)).is_true()


func test_console_is_aligned_with_the_playfield() -> void:
	assert_object(_layout.playfield).is_equal(Rect2i(16, 32, 608, 288))
	# the playfield sits inside the frame, the console starts right under it
	assert_int(_layout.bezel_position.y).is_greater_equal(_layout.playfield.end.y)
	assert_int(_layout.bezel_position.x).is_equal(12)
	assert_float(_layout.bezel.get_size().x).is_equal(616.0)         # 12 .. 628: the playfield plus 4 px frame each side


func test_every_icon_lies_inside_the_console() -> void:
	var console := Rect2(_layout.bezel_position, _layout.bezel.get_size())
	var groups := [[_layout.tank_positions, _layout.tank_full], [_layout.oxygen_positions, _layout.oxygen_full],
			[_layout.ink_positions, _layout.ink_full]]
	for group in groups:
		for position in group[0]:
			assert_bool(console.encloses(Rect2(position, (group[1] as Texture2D).get_size()))).is_true()


func test_gauge_pictures_have_matching_sizes() -> void:
	assert_object(_layout.tank_full.get_size()).is_equal(_layout.tank_empty.get_size())
	assert_object(_layout.oxygen_full.get_size()).is_equal(_layout.oxygen_empty.get_size())
	assert_object(_layout.oxygen_full.get_size()).is_equal(_layout.oxygen_low.get_size())
	assert_object(_layout.ink_full.get_size()).is_equal(_layout.ink_empty.get_size())


func test_labels_and_lights_fit_the_bezel_art() -> void:
	# the label fields and the two light boxes are drawn in the bezel picture; the icons must not overhang
	var console := Rect2(_layout.bezel_position, _layout.bezel.get_size())
	for pair in [[_layout.game_position, _layout.game_textures[0]], [_layout.zone_position, _layout.zone_textures[0]],
			[_layout.sector_position, _layout.sector_textures[0]], [_layout.ship_position, _layout.ship_textures[0]],
			[_layout.computer_position, _layout.computer_textures[0]], [_layout.custom_position, _layout.custom_texture]]:
		assert_bool(console.encloses(Rect2(Vector2(pair[0]), (pair[1] as Texture2D).get_size()))).is_true()


func test_zone_pictures_cover_all_five_zones() -> void:
	assert_int(_layout.zone_textures.size()).is_equal(5)
	assert_object(_layout.zone_texture(6)).is_same(_layout.zone_textures[4])        # finale zones reuse the last one


func test_hud_scene_covers_exactly_the_window() -> void:
	var hud := scene_runner("res://src/ui/hud.tscn").scene() as Hud
	assert_object(hud.size).is_equal(Vector2(640, 400))
	assert_int(hud.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
