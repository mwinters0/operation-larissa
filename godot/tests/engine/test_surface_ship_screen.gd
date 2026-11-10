class_name TestSurfaceShipScreen
extends GdUnitTestSuite
## Teaches: pinning a screen against its draw calls. `place_surface_ship_graphic` (0x432a67) is what both the supply station message
## (`DisplaySupplyStationMessage` 0x432e32) and the pieces-not-collected message (`PiecesNotCollectedMessage` 0x432ac4) draw: the problem screen's
## picture, the ship picture, the title and the text in the right monitor's box, all placed by the pack's problem screen layout. No map, no dots, no
## "press Enter" line. The original's own pictures, texts and coordinates are tests/legacy/test_surface_ship_screen_legacy.gd.


func _screen() -> SurfaceShipScreen:
	var screen: SurfaceShipScreen = auto_free(load("res://src/story/surface_ship_screen.tscn").instantiate())
	add_child(screen)
	return screen


func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key


func after_test() -> void:
	Audio.stop_voice()
	GameClock.paused = false


func test_it_draws_the_problem_picture_the_ship_the_title_and_the_message_box() -> void:
	var screen := _screen()
	var layout := Catalog.screen_layout()
	assert_vector(screen.background.position).is_equal(Vector2(layout.background_position))
	assert_object(screen.background.texture).is_same(layout.background)
	assert_vector(screen.ship.position).is_equal(SurfaceShipScreen.SHIP_POSITION)
	assert_object(screen.ship.texture).is_not_null()
	assert_str(screen.title_label.text).is_equal(Catalog.text(SurfaceShipScreen.STRING_TITLE))
	assert_float(screen.title_label.position.x).is_equal(float(layout.title_box_x))
	assert_float(screen.title_label.size.x).is_equal(float(layout.title_box_width))
	assert_float(screen.title_label.position.y).is_equal(float(layout.title_y))
	assert_vector(screen.message_label.position).is_equal(Vector2(layout.message_box.position))
	assert_vector(screen.message_label.size).is_equal(Vector2(layout.message_box.size))
	assert_object(screen.message_label.get_theme_color("font_color")).is_equal(layout.color(15))


func test_there_is_no_map_no_dots_and_no_prompt_line() -> void:
	var screen := _screen()
	screen.show_supply_message(5)
	var pictures := 0
	var labels := 0
	for child in screen.get_children():
		if child is TextureRect:
			pictures += 1
		elif child is Label:
			labels += 1
	assert_int(pictures).is_equal(2)                                              # the problem picture and the ship: no Pacific map (1000)
	assert_int(labels).is_equal(2)                                                # the title and the message: no "Press Enter" line, no zone title
	assert_str(screen.title_label.text).is_equal(Catalog.text(SurfaceShipScreen.STRING_TITLE))   # not "Map Screen: Zone #n"
	assert_int(screen.get_child_count()).is_equal(4)                              # (no Timer node: the wait is counted in ticks)


func test_the_supply_message_is_the_text_of_the_sector_just_completed() -> void:
	# the campaign test_c (tools/dev_pack/test_sectors/batch_c.py): "Test mission control: sector N is done."
	for sector in [140, 143, 148]:
		assert_str(SurfaceShipScreen.supply_message(sector)).is_equal("Test mission control: sector %d is done." % sector)
	assert_str(SurfaceShipScreen.supply_message(0)).is_equal("Dev mission control: sector 0 is done.")
	assert_str(SurfaceShipScreen.supply_message(99999)).is_empty()                   # a sector of no campaign
	for campaign in Catalog.campaigns():
		for sector in campaign.sectors:
			assert_bool(SurfaceShipScreen.supply_message(sector).length() > 20).override_failure_message("%s %d" % [campaign.id, sector]).is_true()
	var screen := _screen()
	screen.show_supply_message(142)
	assert_str(screen.message_label.text).is_equal(SurfaceShipScreen.supply_message(142))


func test_the_pieces_missing_text_is_the_packs_string_with_the_number_and_plural_filled_in() -> void:
	# The pack's string carries two control codes (BS + 0xD0 the number, BS + 0xD1 the plural "s"); a pack that writes the sentence plainly has none.
	var one := SurfaceShipScreen.pieces_missing_text(1)
	var three := SurfaceShipScreen.pieces_missing_text(3)
	assert_str(one).is_not_empty()
	assert_bool(three.contains("\u0008")).is_false()
	assert_str(one).is_equal(Catalog.text(SurfaceShipScreen.STRING_PIECES_MISSING).replace("\u0008Ð", "1").replace("\u0008Ñ", ""))
	var screen := _screen()
	screen.show_pieces_missing(3)
	assert_str(screen.message_label.text).is_equal(three)


func test_pieces_missing_waits_for_enter_with_no_time_out() -> void:
	var screen := _screen()
	screen.show_pieces_missing(2)
	assert_int(screen.wait_ticks_left).is_equal(-1)                                # (no wait is running)
	var count := [0]
	screen.finished.connect(func() -> void: count[0] += 1)
	screen._unhandled_input(_key(KEY_SPACE))                                       # only Enter goes on
	assert_int(count[0]).is_equal(0)
	screen._unhandled_input(_key(KEY_ENTER))
	screen._unhandled_input(_key(KEY_ENTER))
	assert_int(count[0]).is_equal(1)


func test_the_supply_message_waits_its_ticks_counted_from_the_end_of_the_speech() -> void:
	var screen := _screen()
	var ticks := SurfaceShipScreen.wait_ticks()                                        # WaitEnterOrTicks(0x5b4): the rules' number (`surface_ship.wait_ticks`)
	assert_int(ticks).is_greater(0)
	screen.show_supply_message(3)
	if Audio.is_voice_playing():
		assert_int(screen.wait_ticks_left).is_equal(-1)                            # the speech comes first
		Audio.stop_voice()
	assert_int(screen.wait_ticks_left).is_equal(ticks)
	var count := [0]
	screen.finished.connect(func() -> void: count[0] += 1)
	screen._unhandled_input(_key(KEY_SPACE))                                       # Space and clicks do nothing
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	screen._unhandled_input(click)
	assert_int(count[0]).is_equal(0)
	screen._unhandled_input(_key(KEY_KP_ENTER))
	assert_int(count[0]).is_equal(1)
	assert_bool(Audio.is_voice_playing()).is_false()
	assert_int(screen.wait_ticks_left).is_equal(-1)


func test_the_time_out_ends_the_screen_once() -> void:
	var screen := _screen()
	screen.show_supply_message(0)
	var count := [0]
	screen.finished.connect(func() -> void: count[0] += 1)
	Audio.stop_voice()                                                              # (the speech first: its end starts the wait)
	screen.advance_wait(SurfaceShipScreen.wait_ticks() - 1)
	assert_int(count[0]).is_equal(0)
	screen.advance_wait(1)                                                          # the last tick
	screen.advance_wait(1)
	assert_int(count[0]).is_equal(1)
