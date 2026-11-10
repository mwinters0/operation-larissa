class_name TestSectorOverviewChecksLegacy
extends GdUnitTestSuite
## The overview's checks and comparison for the original's sectors: only findings that are how the original is (allowed, grey), the comparison with the original's
## tables. The same joint on dev's sectors is in `tests/engine/test_sector_overview_checks.gd`.
##
## Teaches: testing the joint between two tools by their data. The sector overview now shows what the playability checks and the
## what-changed report found, and jumps to a creature's label. The tests put findings on the map the way the overview does
## (`SectorOverviewChecks`) and read WHERE they landed: an original sector has only findings that are how the original is (allowed, grey),
## a copy broken in memory (a label that does not exist, a piece outside the playfield, a one-way door, a changed screen) has them at the
## screen and the object that are wrong. The scene is tried with its check box and its list; the reachability search runs on a worker
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


# --- the originals ---------------------------------------------------------------------------------------------------------

## Waits (frame by frame, so the main thread keeps running) until `signal_` is emitted; false after `timeout_ms`. (gdUnit's `assert_signal`
## matches the arguments of a signal too, and these carry a report.)
func _emitted(signal_: Signal, timeout_ms: int) -> bool:
	var seen := [false]
	signal_.connect(func(..._args: Array) -> void: seen[0] = true, CONNECT_ONE_SHOT)
	var started := Time.get_ticks_msec()
	while not seen[0] and Time.get_ticks_msec() - started < timeout_ms:
		await get_tree().process_frame
	return seen[0]



func test_every_finding_of_an_original_is_allowed_or_a_remark_and_placed_or_about_the_sector() -> void:
	var allowed_marks := 0
	for index in Catalog.ORIGINAL_SECTOR_COUNT:
		var result := _model_and_marks(Catalog.sector(index))
		assert_bool(result.checked and result.compared).is_true()
		assert_int(result.marks.size() + result.unplaced.size()).override_failure_message("sector %d" % index).is_equal(result.findings.size())
		for mark in result.marks:
			assert_bool(mark.muted()).override_failure_message("sector %d: %s" % [index, mark.finding.text()]).is_true()
			assert_bool(mark.screen >= 0 and mark.screen < SectorData.SCREEN_COUNT).is_true()
			if not mark.finding.allowed.is_empty():
				allowed_marks += 1
		for screen in SectorData.SCREEN_COUNT:
			assert_int(result.count_on(screen)).override_failure_message("sector %d screen %d has a mark that is not muted" % [index, screen]).is_equal(0)
			assert_int(result.worst_on(screen)).is_less_equal(CheckFinding.Severity.INFO)
	assert_int(allowed_marks).is_greater_equal(4)                    # the one-way doors of sectors 7, 13 and 15 (reach: sector 31)



func test_an_allowed_one_way_door_is_marked_on_its_side_of_its_screen_with_the_reason() -> void:
	var result := _model_and_marks(Catalog.sector(15))
	var doors := _marks_of(result, "link.one_way")
	assert_int(doors.size()).is_equal(1)
	assert_int(doors[0].screen).is_equal(7)
	assert_int(doors[0].placed).is_equal(SectorOverviewChecks.Placed.SIDE)
	assert_str(doors[0].finding.allowed).contains("screen 7 left -> 4")
	assert_str(SectorOverviewChecks.describe(doors[0].finding)).contains("allowed, the original is like this")
	# a strip along the left edge of the screen
	assert_float(doors[0].rect.position.x).is_equal(0.0)
	assert_float(doors[0].rect.size.y).is_equal(float(TileGrid.PLAYFIELD_SIZE.y))
	assert_bool(result.unplaced.is_empty()).is_true()



func test_the_original_differs_from_itself_nowhere_but_the_deliberate_changes() -> void:
	for index in [0, 3, 15]:
		var result := _model_and_marks(Catalog.sector(index))
		for screen: int in result.changed_screens:
			assert_str(result.changed_screens[screen][0]).contains("on purpose")          # only what a test lists as DELIBERATE



func test_a_changed_screen_is_named_by_the_comparison() -> void:
	var sector := _copy_of(3)
	sector.screens[5] = sector.screens[5].duplicate_deep() as ScreenData
	sector.screens[5].tiles[0] ^= 0x01
	var result := _model_and_marks(sector)
	assert_bool(result.is_changed(5)).is_true()
	assert_str(result.changed_screens[5][0]).contains("screen 5")
	assert_bool(result.is_changed(4)).is_false()
	assert_str(result.summary()).contains("differ from the original")



func test_an_original_in_the_scene_shows_only_what_the_original_is_like() -> void:
	var overview := _overview()
	await get_tree().process_frame
	overview.load_sector(15)
	overview.set_overlay(SectorOverviewCanvas.Overlay.CHECKS, true)
	assert_bool(await _emitted(overview.checks_finished, 20000)).override_failure_message("checks_finished did not come").is_true()
	var result := overview.checks_result()
	assert_bool(SectorChecks.passes(result.findings)).is_true()
	assert_int(result.count_on(7)).is_equal(0)                                        # nothing that is not muted
	assert_int(result.count_on(7, true)).is_equal(1)                                  # but the door is marked
	assert_str(overview._findings_list.get_item_text(0)).contains("(allowed)")
	# a new sector forgets the result and checks the new one
	overview.load_sector(16)
	assert_bool(overview.checks_result() == null).is_true()
	assert_bool(await _emitted(overview.checks_finished, 20000)).override_failure_message("checks_finished did not come").is_true()
	assert_int(overview.checks_result().sector_index).is_equal(16)



func test_switching_reachable_on_after_the_checks_searches_again_and_shows_the_allowed_unreachable_canister() -> void:
	var overview := _overview()
	await get_tree().process_frame
	overview.load_sector(31)
	overview.set_overlay(SectorOverviewCanvas.Overlay.CHECKS, true)
	assert_bool(await _emitted(overview.checks_finished, 20000)).is_true()
	assert_bool(overview.checks_result().with_reach).is_false()
	assert_array(_marks_of(overview.checks_result(), "reach.piece")).is_empty()
	var before := overview.checks_result()
	overview.set_overlay(SectorOverviewCanvas.Overlay.REACHABILITY, true)
	assert_bool(overview.checking()).is_true()                                  # the old result lacks the reach findings: search
	assert_bool(await _emitted(overview.checks_finished, 60000)).is_true()
	var result := overview.checks_result()
	assert_object(result).is_not_same(before)
	assert_bool(result.with_reach).is_true()
	var canister := _marks_of(result, "reach.piece")
	assert_int(canister.size()).is_equal(1)
	assert_int(canister[0].object["kind"]).is_equal(SectorOverviewModel.Kind.CANISTER)
	assert_int(canister[0].screen).is_equal(0)
	assert_bool(canister[0].muted()).is_true()
	assert_str(canister[0].finding.allowed).contains("pocket of the start station")
	assert_bool(SectorChecks.passes(result.findings)).is_true()
	# the tool scene's own "Reachable" picture and the checks agree: it is the piece the overlay rings in red
	assert_bool(overview.canvas().model.reach().piece_reachable[0]).is_false()


