class_name TestSurfaceShipScreenLegacy
extends GdUnitTestSuite
## The ORIGINAL's surface ship screen (`place_surface_ship_graphic` 0x432a67): its ship picture (1979, 276 x 94), the mission control text of each of its
## sectors (strings 10678-10707) and the pieces-not-collected string 11212 with its number and plural. The screen's mechanics are tested on dev in
## tests/engine/test_surface_ship_screen.gd.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func _screen() -> SurfaceShipScreen:
	var screen: SurfaceShipScreen = auto_free(load("res://src/story/surface_ship_screen.tscn").instantiate())
	add_child(screen)
	return screen


func test_the_screen_draws_the_original_ship_title_and_message_box() -> void:
	var screen := _screen()
	var layout := Catalog.screen_layout()
	assert_vector(screen.background.position).is_equal(Vector2(12, 30))          # DrawProblemBackground: picture 1780 at (12, 30)
	assert_vector(screen.ship.position).is_equal(Vector2(36, 126))                # DrawPictureMasked(0x24, 0x7e, bundle 0x1c2)
	assert_vector(screen.ship.texture.get_size()).is_equal(Vector2(276, 94))      # picture 1979
	assert_str(screen.title_label.text).is_equal("Surface Ship")                  # DisplayMathTitle(0x22) = string 11108
	assert_float(screen.title_label.position.x).is_equal(40.0)                    # centred in x 40 + (268 - width) / 2, y 36
	assert_float(screen.title_label.size.x).is_equal(268.0)
	assert_float(screen.title_label.position.y).is_equal(36.0)
	assert_vector(screen.message_label.position).is_equal(Vector2(364, 48))       # the message box (364, 48, 238 x 202)
	assert_vector(screen.message_label.size).is_equal(Vector2(238, 202))
	assert_object(screen.message_label.get_theme_color("font_color")).is_equal(layout.color(15))   # SetColor(15)


func test_the_supply_message_is_the_text_of_the_sector_just_completed() -> void:
	assert_str(SurfaceShipScreen.supply_message(0)).contains("Great progress")
	assert_str(SurfaceShipScreen.supply_message(1)).contains("collected a total of 2 data canisters")
	assert_str(SurfaceShipScreen.supply_message(2)).contains("completed the first zone")
	assert_str(SurfaceShipScreen.supply_message(14)).contains("final sector")
	assert_str(SurfaceShipScreen.supply_message(15)).contains("Great progress")   # the Expert game's own 15
	assert_str(SurfaceShipScreen.supply_message(29)).contains("final sector")
	for sector in 30:
		assert_bool(SurfaceShipScreen.supply_message(sector).length() > 20).is_true()
	var screen := _screen()
	screen.show_supply_message(2)
	assert_str(screen.message_label.text).is_equal(SurfaceShipScreen.supply_message(2))


func test_the_pieces_missing_text_is_the_whole_string_11212_with_number_and_plural() -> void:
	var one := SurfaceShipScreen.pieces_missing_text(1)
	assert_str(one).starts_with("Surface Ship Message:\n")                         # WriteMessageText prints the title line too
	assert_str(one).contains("presence of 1 object in this sector")
	assert_str(one).contains("remaining capsule piece.")
	var three := SurfaceShipScreen.pieces_missing_text(3)
	assert_str(three).contains("presence of 3 objects in this sector")
	assert_str(three).contains("remaining capsule pieces.")
	assert_bool(three.contains("\u0008")).is_false()
	var screen := _screen()
	screen.show_pieces_missing(3)
	assert_str(screen.message_label.text).is_equal(three)
