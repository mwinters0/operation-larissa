class_name TestSectorCheckDialog
extends GdUnitTestSuite
## Teaches: testing the thin editor part of a tool. The "Check sector" window (addons/sector_checks/) only asks for a sector and shows
## what `SectorReport` says, so the test makes the window, lets it list the sectors, runs it for one and reads the text it shows. Clicking
## it in the real editor (Project > Tools > Check sector...) is not tested.



## Waits (frame by frame, so the main thread keeps running) until `signal_` is emitted; false after `timeout_ms`. (gdUnit's `assert_signal`
## matches the arguments of a signal too, and these carry a report.)
func _emitted(signal_: Signal, timeout_ms: int) -> bool:
	var seen := [false]
	signal_.connect(func(..._args: Array) -> void: seen[0] = true, CONNECT_ONE_SHOT)
	var started := Time.get_ticks_msec()
	while not seen[0] and Time.get_ticks_msec() - started < timeout_ms:
		await get_tree().process_frame
	return seen[0]


func test_the_sector_of_a_path_is_the_number_in_its_folder() -> void:
	assert_int(SectorCheckDialog.sector_of_path("res://data/sectors/sector_07/sector_07.tres")).is_equal(7)
	assert_int(SectorCheckDialog.sector_of_path("res://data/sectors/sector_12/screen_03.tres")).is_equal(12)
	assert_int(SectorCheckDialog.sector_of_path("res://data/sectors/sector_30/sector_30.foe")).is_equal(30)
	assert_int(SectorCheckDialog.sector_of_path("res://data/sectors/sector_05/sector_05.tres::Foe_3")).is_equal(5)
	assert_int(SectorCheckDialog.sector_of_path(DevPack.ROOT + "data/zones.tres")).is_equal(-1)
	assert_int(SectorCheckDialog.sector_of_path("res://data/sectors/foe_annotations.json")).is_equal(-1)


func test_the_window_lists_every_sector_file_and_shows_the_report_of_the_chosen_one() -> void:
	var dialog := SectorCheckDialog.new()
	add_child(dialog)
	auto_free(dialog)
	dialog._reach_box.button_pressed = false                  # the search is covered below and by test_sector_checks.gd
	dialog.open(Ground.MAIN)
	assert_int(dialog._sector_box.item_count).is_greater_equal(Catalog.sector_ids().size())
	assert_int(dialog._sector_box.get_selected_id()).is_equal(Ground.MAIN)
	assert_bool(await _emitted(dialog.check_finished, 20000)).override_failure_message("check_finished did not come").is_true()
	assert_str(dialog._output.get_parsed_text()).contains("What changed in sector %d" % Ground.MAIN).contains("Playability checks of sector %d: pass" % Ground.MAIN)     # (`text` holds the BBCode)
	assert_str(dialog._last_text).contains("Playability checks of sector %d: pass" % Ground.MAIN)
	assert_bool(dialog._check_button.disabled).is_false()
	dialog.hide()


func test_the_reachability_search_runs_in_the_background_and_the_report_appears() -> void:
	var dialog := SectorCheckDialog.new()
	add_child(dialog)
	auto_free(dialog)
	dialog._reach_box.button_pressed = true
	dialog.open(Ground.LEDGE)
	# while the search runs the window says so, the button is off, and the main thread still draws frames
	assert_str(dialog._output.text).contains("Checking sector %d" % Ground.LEDGE)
	assert_bool(dialog._check_button.disabled).is_true()
	await get_tree().process_frame
	assert_bool(dialog._task.running).is_true()
	var frames := 0
	var started := Time.get_ticks_msec()
	while dialog._task != null and Time.get_ticks_msec() - started < 60000:
		await get_tree().process_frame
		frames += 1
	assert_int(frames).is_greater(1)
	assert_str(dialog._output.get_parsed_text()).contains("Playability checks of sector %d: pass" % Ground.LEDGE)
	assert_str(dialog._last_text).contains("Playability checks of sector %d: pass" % Ground.LEDGE)
	assert_bool(dialog._check_button.disabled).is_false()
	dialog.hide()


func test_a_check_asked_for_while_another_runs_replaces_it() -> void:
	var dialog := SectorCheckDialog.new()
	add_child(dialog)
	auto_free(dialog)
	dialog._reach_box.button_pressed = false
	dialog.open(Ground.MAP)
	dialog.open(Ground.LEDGE)                                             # the first one's report is dropped when it arrives
	assert_bool(await _emitted(dialog.check_finished, 20000)).override_failure_message("check_finished did not come").is_true()
	assert_str(dialog._last_text).contains("sector %d" % Ground.LEDGE)
	assert_bool(dialog._check_button.disabled).is_false()
	dialog.hide()
