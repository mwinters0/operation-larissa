class_name TestSectorOverviewChecks
extends GdUnitTestSuite
## Teaches: testing the joint between two tools by their data. The sector overview now shows what the playability checks found, and jumps to a
## creature's label. The tests put findings on the map the way the overview does (`SectorOverviewChecks`) and read WHERE they landed: a sector that is
## fine has none, a copy of the ground sector broken in memory (a label that does not exist, a piece outside the playfield, a one-way door) has them at the
## screen and the object that are wrong. (What the original's sectors show, allowed and grey, and the comparison with the original are in
## `tests/legacy/test_sector_overview_checks_legacy.gd`.) The scene is tried with its check box and its list; the reachability search runs on a worker
## thread, so the tests wait for `checks_finished`. Clicking in the real editor is not tested.

const SCENE := "res://src/debug/sector_overview.tscn"
const PLUGIN := "res://addons/sector_overview/plugin.gd"


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func _copy_of(index: int) -> SectorData:
	return Catalog.sector(index).duplicate_deep() as SectorData


func _model_and_marks(sector: SectorData, reach: bool = false) -> SectorOverviewChecks:
	var model := SectorOverviewModel.new(sector)
	return SectorOverviewChecks.build(model, SectorReport.make(sector, true, true, reach, false), reach)


func _overview() -> SectorOverview:
	var overview := auto_free((load(SCENE) as PackedScene).instantiate()) as SectorOverview
	add_child(overview)
	return overview


## The marks with this check id.
func _marks_of(result: SectorOverviewChecks, check_id: String) -> Array[SectorOverviewChecks.Mark]:
	var found: Array[SectorOverviewChecks.Mark] = []
	for mark in result.marks:
		if mark.finding.check == check_id:
			found.append(mark)
	return found


# --- the sectors that are fine ---------------------------------------------------------------------------------------------------------


## Waits (frame by frame, so the main thread keeps running) until `signal_` is emitted; false after `timeout_ms`. (gdUnit's `assert_signal`
## matches the arguments of a signal too, and these carry a report.)
func _emitted(signal_: Signal, timeout_ms: int) -> bool:
	var seen := [false]
	signal_.connect(func(..._args: Array) -> void: seen[0] = true, CONNECT_ONE_SHOT)
	var started := Time.get_ticks_msec()
	while not seen[0] and Time.get_ticks_msec() - started < timeout_ms:
		await get_tree().process_frame
	return seen[0]


func test_a_sector_that_is_fine_has_no_mark_and_no_finding() -> void:
	for index in Ground.clean_sectors():
		if index == Ground.FINALE:
			continue                                                        # (a finale has no pieces and the checks say so, as a note)
		var result := _model_and_marks(Catalog.sector(index))
		assert_bool(result.checked).is_true()
		assert_array(result.findings).override_failure_message("sector %d: %s" % [index, SectorChecks.text(result.findings)]).is_empty()
		assert_array(result.marks).is_empty()
		assert_array(result.unplaced).is_empty()
		for screen in SectorData.SCREEN_COUNT:
			assert_int(result.count_on(screen)).is_equal(0)


# --- a broken copy ----------------------------------------------------------------------------------------------------------

func test_a_broken_copy_has_its_findings_at_the_screen_and_object_that_are_wrong() -> void:
	var sector := _copy_of(Ground.MAIN)
	sector.foes[4].ink_label = "no_such_label"
	sector.pieces[2].pos = Vector2i(2, 2)                                            # outside the playfield
	var result := _model_and_marks(sector)
	# the creature whose label is wrong: ringed on the screen its record starts it on
	var label_marks := _marks_of(result, "script.entry")
	assert_int(label_marks.size()).is_equal(1)
	assert_int(label_marks[0].placed).is_equal(SectorOverviewChecks.Placed.OBJECT)
	assert_int(label_marks[0].object["kind"]).is_equal(SectorOverviewModel.Kind.CREATURE)
	assert_int(label_marks[0].object["index"]).is_equal(4)
	assert_int(label_marks[0].screen).is_equal(sector.foes[4].screen)
	assert_bool(label_marks[0].muted()).is_false()
	assert_int(label_marks[0].finding.severity).is_equal(CheckFinding.Severity.ERROR)
	# the piece
	var piece_marks := _marks_of(result, "piece.place")
	assert_int(piece_marks.size()).is_equal(1)
	assert_int(piece_marks[0].object["kind"]).is_equal(SectorOverviewModel.Kind.PIECE)
	assert_int(piece_marks[0].object["index"]).is_equal(2)
	assert_int(piece_marks[0].screen).is_equal(sector.pieces[2].screen)
	# the screens know: a count and the worst severity
	assert_int(result.worst_on(sector.foes[4].screen)).is_equal(CheckFinding.Severity.ERROR)
	assert_int(result.count_on(sector.pieces[2].screen)).is_greater_equal(1)
	assert_bool(result.marks_of(label_marks[0].object).has(label_marks[0])).is_true()
	assert_str(result.summary()).contains("error")
	# an untouched screen has no mark
	var quiet := -1
	for screen in SectorData.SCREEN_COUNT:
		if result.marks_on(screen).is_empty():
			quiet = screen
	assert_int(quiet).is_greater_equal(0)


func test_a_one_way_door_in_a_copy_is_a_warning_on_the_side_it_leaves_through() -> void:
	var sector := _copy_of(Ground.MAIN)
	var target := sector.neighbors_right[0]
	sector.neighbors_left[target] = -1
	var result := _model_and_marks(sector)
	var doors := _marks_of(result, "link.one_way")
	assert_int(doors.size()).is_equal(1)
	assert_int(doors[0].screen).is_equal(0)
	assert_int(doors[0].placed).is_equal(SectorOverviewChecks.Placed.SIDE)
	assert_float(doors[0].rect.end.x).is_equal(float(TileGrid.PLAYFIELD_SIZE.x))           # the right edge
	assert_int(doors[0].finding.severity).is_equal(CheckFinding.Severity.WARNING)
	assert_str(doors[0].finding.allowed).is_empty()
	assert_int(result.worst_on(0)).is_equal(CheckFinding.Severity.WARNING)


func test_findings_about_the_sector_as_a_whole_are_listed_but_not_on_the_map() -> void:
	var sector := _copy_of(Ground.MAIN)
	sector.music_name = "no_such_song"
	var result := _model_and_marks(sector)
	var zone := result.unplaced.filter(func(finding: CheckFinding) -> bool: return finding.check == "sector.music")
	assert_int(zone.size()).is_equal(1)
	assert_bool(result.mark_of(zone[0]) == null).is_true()


# --- the scene ---------------------------------------------------------------------------------------------------------------

func test_the_checks_box_marks_a_broken_copy_in_the_scene_and_the_list_selects_its_object() -> void:
	var sector := _copy_of(Ground.MAIN)
	sector.foes[4].ink_label = "no_such_label"
	var overview := _overview()
	await get_tree().process_frame
	overview.show_sector(sector)
	overview.set_overlay(SectorOverviewCanvas.Overlay.CHECKS, true)
	overview.set_overlay(SectorOverviewCanvas.Overlay.CHANGES, true)
	assert_bool(overview.checking()).is_true()
	assert_bool(overview.checks_result() == null).is_true()
	assert_bool(await _emitted(overview.checks_finished, 20000)).override_failure_message("checks_finished did not come").is_true()
	var result := overview.checks_result()
	assert_bool(overview.checking()).is_false()
	assert_object(overview.canvas().checks).is_same(result)
	assert_bool(result.with_reach).is_false()
	assert_str(result.summary()).contains("without the reachability search")
	# one row per finding, the worst first (the error of the label)
	assert_int(overview._findings_list.item_count).is_equal(result.findings.size())
	assert_str(overview._findings_list.get_item_text(0)).contains("error").contains("creature 4 ink_label")
	overview._findings_list.select(0)
	overview._on_finding_picked(0)
	var mark := result.marks[0]
	assert_int(overview.canvas().selected_screen).is_equal(mark.screen)
	assert_dict(overview.canvas().selected_object).is_equal(mark.object)
	assert_object(overview.canvas().selected_finding).is_same(mark.finding)
	assert_str(overview._info.text).contains("no_such_label")
	# the object's mark is under the cursor when the map is drawn: the tooltip tells the finding
	overview.canvas().zoom = 0.5
	var at := overview.canvas().origin_of(mark.screen) + (mark.object["rect"] as Rect2).get_center() * overview.canvas().zoom
	assert_str(overview.canvas()._get_tooltip(at)).contains("no_such_label")
	await get_tree().process_frame
	# turning the box off hides the list
	overview.set_overlay(SectorOverviewCanvas.Overlay.CHECKS, false)
	assert_bool(overview._findings_box.visible).is_false()


func test_with_the_reachable_box_on_the_search_runs_in_the_background_and_adds_its_findings() -> void:
	var sector := _copy_of(Ground.MAIN)
	# a rock-filled last screen with a pocket the sub cannot get into holds piece 3 (as test_sector_checks.gd does)
	sector.screens[11] = sector.screens[11].duplicate_deep() as ScreenData
	for i in ScreenData.TILE_BYTES:
		sector.screens[11].tiles[i] = 0x41
	for row in range(6, 12):
		for column in range(15, 26):
			sector.screens[11].tiles[row * ScreenData.TILE_COLUMNS + column] = 0
	sector.pieces[3].screen = 11
	sector.pieces[3].pos = Vector2i(300, 150)
	var overview := _overview()
	await get_tree().process_frame
	overview.show_sector(sector)
	overview.set_overlay(SectorOverviewCanvas.Overlay.REACHABILITY, true)
	overview.set_overlay(SectorOverviewCanvas.Overlay.CHECKS, true)
	# the main thread is free while the search runs: frames go by
	var frames := 0
	var started := Time.get_ticks_msec()
	while overview.checking() and Time.get_ticks_msec() - started < 60000:
		await get_tree().process_frame
		frames += 1
	assert_bool(overview.checking()).is_false()
	assert_int(frames).is_greater(1)
	var result := overview.checks_result()
	assert_bool(result.with_reach).is_true()
	var lost := _marks_of(result, "reach.piece")
	assert_int(lost.size()).is_greater_equal(1)
	assert_int(lost[0].object["index"]).is_equal(3)
	assert_int(lost[0].screen).is_equal(11)
	assert_int(result.worst_on(11)).is_equal(CheckFinding.Severity.ERROR)
	# the result has the comparison too, so turning the "Changed" box on does not search again
	overview.set_overlay(SectorOverviewCanvas.Overlay.CHANGES, true)
	assert_bool(overview.checking()).is_false()
	assert_object(overview.checks_result()).is_same(result)
	assert_bool(result.compared).is_true()
	# and turning Reachable off keeps the findings (the result is a superset of what is asked for)
	overview.set_overlay(SectorOverviewCanvas.Overlay.REACHABILITY, false)
	assert_bool(overview.checking()).is_false()
	assert_object(overview.checks_result()).is_same(result)


# --- the creature script jump ---------------------------------------------------------------------------------------------

func test_show_the_creature_script_asks_the_host_for_the_start_label() -> void:
	var overview := _overview()
	await get_tree().process_frame
	overview.load_sector(Ground.MAIN)
	var asked: Array = []
	overview.foe_script_requested.connect(func(sector: int, foe_index: int, labels: PackedStringArray) -> void: asked.append([sector, foe_index, labels]))
	var creature := overview.canvas().model.objects_of(4, SectorOverviewModel.Kind.CREATURE)[0]
	overview._on_object_picked(creature)
	assert_bool(overview._script_button.visible).is_true()
	overview._script_button.pressed.emit()
	assert_int(asked.size()).is_equal(1)
	var foe := Ground.main().foes[creature["index"]]
	assert_int(asked[0][1]).is_equal(creature["index"])
	assert_str(asked[0][2][0]).is_equal(foe.start_label)                               # the first label is where the creature begins


func test_without_a_host_the_button_says_where_the_script_starts() -> void:
	var overview := _overview()
	await get_tree().process_frame
	overview.load_sector(Ground.MAIN)
	var creature := overview.canvas().model.objects_of(4, SectorOverviewModel.Kind.CREATURE)[0]
	overview._on_object_picked(creature)
	overview._script_button.pressed.emit()
	assert_str(overview._info.text).contains("opens in the Godot editor").contains(Ground.main().foes[creature["index"]].start_label)


func test_the_plugin_jumps_to_the_label_in_a_foe_script_panel() -> void:
	var panel := auto_free(FoeEditorPanel.new()) as FoeEditorPanel
	add_child(panel)
	var overview := _overview()
	await get_tree().process_frame
	overview.load_sector(Ground.MAIN)
	var asked: Array[PackedStringArray] = []
	overview.foe_script_requested.connect(func(_sector: int, _foe: int, requested: PackedStringArray) -> void: asked.append(requested))
	var creature := overview.canvas().model.objects_of(4, SectorOverviewModel.Kind.CREATURE)[0]
	overview._on_object_picked(creature)
	overview._script_button.pressed.emit()
	assert_int(asked.size()).is_equal(1)
	var labels := asked[0]
	assert_int(labels.size()).is_equal(3)
	# what the editor plugin does with the labels, with a panel of our own instead of the editor's
	var plugin := load(PLUGIN) as GDScript
	var script := Ground.main().foe_script
	assert_str(plugin.call("jump_to_label", script, labels[0], panel)).is_empty()
	var doc := panel.current_document()
	assert_str(doc.path()).is_equal(script.resource_path)
	assert_int(doc.edit.get_caret_line()).is_equal(ScreenEditorFoeJump.line_of_label(script.source, labels[0]))
	assert_str(plugin.call("jump_to_label", script, "no_such_label", panel)).contains("is not a label")
	# outside the editor there is no Foe Script screen: the reason is said, nothing breaks
	assert_str(plugin.call("jump_to_label", script, labels[0])).contains("only exists in the Godot editor")
