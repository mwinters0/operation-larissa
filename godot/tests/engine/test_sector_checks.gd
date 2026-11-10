class_name TestSectorChecks
extends GdUnitTestSuite
## Teaches: testing a checker from both sides. `SectorChecks` (the playability checks) must pass a sector that is fine, and it must catch what is wrong
## with one that is not: the file breaks a copy of the ground sector (`Ground.MAIN`) in memory, one thing at a time (a label that does not exist, a one-way
## door, a piece the sub cannot reach, too many pieces ...), and looks for the finding that names it. (The original's 32 sectors, with the findings that are
## simply how the original is, are checked by `tests/legacy/test_sector_checks_legacy.gd`.)
##
## The reachability search is the slow part (a few seconds per sector).

## A copy of a sector of the dev pack (by default the ground sector) that is safe to change: the loaded resources are shared and cached, and `duplicate_deep` copies only
## what the .tres holds inside itself (pieces, creatures), not the screen files or the .foe file, which are replaced when changed.
func _copy_of(index: int = Ground.MAIN) -> SectorData:
	return Catalog.sector(index).duplicate_deep() as SectorData


func _screen_copy(sector: SectorData, m: int) -> ScreenData:
	sector.screens[m] = sector.screens[m].duplicate_deep() as ScreenData
	return sector.screens[m]


func _options(reach: bool) -> SectorChecks.Options:
	var options := SectorChecks.Options.new()
	options.reach = reach
	return options


## The findings with this check id (an Array of CheckFinding).
func _of(found: Array[CheckFinding], check_id: String) -> Array[CheckFinding]:
	var out: Array[CheckFinding] = []
	for finding in found:
		if finding.check == check_id:
			out.append(finding)
	return out


func _texts(found: Array[CheckFinding]) -> String:
	return SectorChecks.text(found)


## One finding with this check id, severity and a message that contains `part`; fails the test with all findings listed otherwise.
func _expect(found: Array[CheckFinding], check_id: String, severity: CheckFinding.Severity, part: String) -> CheckFinding:
	for finding in found:
		if finding.check == check_id and finding.severity == severity and (finding.object + " " + finding.message).contains(part):
			return finding
	assert_bool(false).override_failure_message("expected a %s finding [%s] containing '%s', got:\n%s" % [CheckFinding.SEVERITY_NAMES[severity], check_id, part, _texts(found)]).is_true()
	return null


## A screen whose tiles are all solid rock, except the box of tiles columns 15-25, rows 6-11 (playfield (240, 96) to (416, 192)).
func _rock_with_pocket(sector: SectorData, m: int, pocket: bool) -> void:
	var screen := _screen_copy(sector, m)
	for i in ScreenData.TILE_BYTES:
		screen.tiles[i] = 0x41
	if pocket:
		for row in range(6, 12):
			for column in range(15, 26):
				screen.tiles[row * ScreenData.TILE_COLUMNS + column] = 0


# --- the originals ---------------------------------------------------------------------------------------------------

# --- a sector that is not fine: one thing wrong at a time ---------------------------------------------------------------

func test_an_unmodified_copy_has_no_findings_at_all() -> void:
	for index in [Ground.MAIN, Ground.LEDGE, Ground.MAP, DevPack.TOUR_FINALE]:
		var found := SectorChecks.check(_copy_of(index), _options(true))
		assert_array(found).override_failure_message("sector %d: %s" % [index, _texts(found)]).is_empty()


func test_a_finale_is_not_asked_for_pieces_or_for_all_its_screens() -> void:
	var found := SectorChecks.check(_copy_of(Ground.FINALE), _options(true))
	assert_bool(SectorChecks.passes(found)).override_failure_message(_texts(found)).is_true()
	assert_int(_of(found, "link.unreachable").size()).is_equal(7)                 # screens 5-11
	for finding in _of(found, "link.unreachable"):
		assert_int(finding.severity).is_equal(CheckFinding.Severity.INFO)
	assert_int(_of(found, "piece.canister").size()).is_equal(1)
	assert_int(_of(found, "piece.canister")[0].severity).is_equal(CheckFinding.Severity.INFO)


func test_findings_are_data_with_a_severity_a_check_a_sector_and_a_place() -> void:
	var finding := _expect(SectorChecks.check(_copy_of(Ground.TANGLE), _options(false)), "link.one_way", CheckFinding.Severity.WARNING, "up link")
	assert_int(finding.sector).is_equal(Ground.TANGLE)
	assert_int(finding.screen).is_equal(4)
	assert_str(finding.object).is_equal("up link")
	assert_str(finding.text()).starts_with("warning: sector %d screen 4 up link:" % Ground.TANGLE).contains("[link.one_way]")


func test_a_label_that_does_not_exist_is_found() -> void:
	var sector := _copy_of()
	sector.foes[4].ink_label = "no_such_label"
	sector.foes[5].start_label = ""
	var found := SectorChecks.check(sector, _options(false))
	var finding := _expect(found, "script.entry", CheckFinding.Severity.ERROR, "creature 4 ink_label")
	assert_str(finding.message).contains("no_such_label")
	assert_int(finding.screen).is_equal(sector.foes[4].screen)
	_expect(found, "script.entry", CheckFinding.Severity.ERROR, "creature 5 start_label is empty")
	assert_bool(SectorChecks.passes(found)).is_false()
	# the original is untouched
	assert_bool(SectorChecks.passes(SectorChecks.check(Ground.main(), _options(false)))).is_true()


func test_a_script_that_does_not_assemble_is_found_with_its_line() -> void:
	var sector := _copy_of()
	sector.foe_script = FoeScript.new()
	sector.foe_script.source = "foe0_start:\n    Wait_Next_Tick\n    Jump_To nowhere\n    Bogus 3\n"
	var found := SectorChecks.check(sector, _options(false))
	assert_int(_of(found, "script.assemble").size()).is_equal(2)
	var finding := _expect(found, "script.assemble", CheckFinding.Severity.ERROR, "unknown label 'nowhere'")
	assert_str(finding.object).is_equal("script line 3")
	_expect(found, "script.assemble", CheckFinding.Severity.ERROR, "unknown instruction 'Bogus'")


func test_a_script_longer_than_the_entry_points_can_address_is_found() -> void:
	var sector := _copy_of()
	sector.foe_script = FoeScript.new()
	sector.foe_script.source = Ground.main().foe_script.source + "\nfiller:\n    Padding 65535\n"
	var found := SectorChecks.check(sector, _options(false))
	_expect(found, "script.size", CheckFinding.Severity.ERROR, "16-bit")


func test_code_nothing_reaches_is_a_warning() -> void:
	var sector := _copy_of()
	sector.foe_script = FoeScript.new()
	sector.foe_script.source = Ground.main().foe_script.source + "\nunused_code:\n    Move_Foe_Relative_XY 2 0 0\n    Return\n"
	var found := SectorChecks.check(sector, _options(false))
	_expect(found, "script.dead_code", CheckFinding.Severity.WARNING, "never executed")


func test_a_one_way_neighbour_is_a_warning_that_names_the_screen_and_side() -> void:
	var sector := _copy_of()
	var target := sector.neighbors_right[0]
	assert_int(target).is_greater_equal(0)
	assert_int(sector.neighbors_left[target]).is_equal(0)
	sector.neighbors_left[target] = -1
	var found := SectorChecks.check(sector, _options(false))
	var finding := _expect(found, "link.one_way", CheckFinding.Severity.WARNING, "right link")
	assert_int(finding.screen).is_equal(0)
	assert_str(finding.message).contains("leads to screen %d" % target).contains("no way back")
	assert_bool(finding.fails()).is_true()
	assert_bool(SectorChecks.passes(found)).is_false()


func test_a_neighbour_that_is_not_a_screen_is_found() -> void:
	var sector := _copy_of()
	sector.neighbors_up[2] = 12
	var found := SectorChecks.check(sector, _options(true))
	_expect(found, "header", CheckFinding.Severity.ERROR, "neighbors_up of screen 2: 12 is not a screen")
	assert_int(_of(found, "header")[0].screen).is_equal(2)
	_expect(found, "reach.skipped", CheckFinding.Severity.INFO, "leads to screen 12")


func test_a_screen_no_chain_of_links_leads_to_is_found_by_the_links_and_by_the_search() -> void:
	var sector := _copy_of()
	for table in [sector.neighbors_left, sector.neighbors_right, sector.neighbors_up, sector.neighbors_down]:
		for screen in 12:
			if table[screen] == 5:
				table[screen] = -1
	var found := SectorChecks.check(sector, _options(true))
	var by_links := _expect(found, "link.unreachable", CheckFinding.Severity.ERROR, "no chain of neighbour links")
	assert_int(by_links.screen).is_equal(5)
	var by_search := _expect(found, "reach.screen", CheckFinding.Severity.ERROR, "cannot enter this screen")
	assert_int(by_search.screen).is_equal(5)


func test_a_piece_the_sub_cannot_reach_is_found() -> void:
	var sector := _copy_of()
	_rock_with_pocket(sector, 5, true)
	sector.pieces[3].screen = 5
	sector.pieces[3].pos = Vector2i(300, 150)
	var found := SectorChecks.check(sector, _options(true))
	var finding := _expect(found, "reach.piece", CheckFinding.Severity.ERROR, "piece 3")
	assert_int(finding.screen).is_equal(5)
	assert_str(finding.message).contains("no position the sub can reach touches it")
	# the pocket is open air, so the piece is not buried (the other piece of the screen, in the rock, is)
	for buried in _of(found, "piece.buried"):
		assert_str(buried.object).is_not_equal("piece 3")


func test_a_math_trigger_the_sub_cannot_reach_is_a_warning() -> void:
	var sector := _copy_of()
	_rock_with_pocket(sector, 5, true)
	var trigger := MathTriggerData.new()
	trigger.pos = Vector2i(300, 150)
	trigger.slot = 4
	trigger.test_nibble = 15                         # TriggerModel.TABLE: needs the sub's box to contain the point in both x and y
	_screen_copy(sector, 5).triggers.append(trigger)
	var found := SectorChecks.check(sector, _options(true))
	var name := "trigger %d" % (sector.screens[5].triggers.size() - 1)                  # (the screen's old trigger, in the rock, is named too)
	var named := _of(found, "reach.trigger").filter(func(f: CheckFinding) -> bool: return f.object == name)
	assert_int(named.size()).is_equal(1)
	assert_int(named[0].screen).is_equal(5)
	assert_int(named[0].severity).is_equal(CheckFinding.Severity.WARNING)
	assert_str(named[0].message).contains("no position the sub can reach fires")


func test_an_end_station_the_sub_cannot_enter_is_found() -> void:
	var sector := _copy_of()
	_rock_with_pocket(sector, SimWorld.DOCK_SCREEN, false)
	var found := SectorChecks.check(sector, _options(true))
	_expect(found, "reach.dock", CheckFinding.Severity.ERROR, "cannot get into the end station")


func test_too_many_pieces_are_found() -> void:
	var sector := _copy_of()
	for i in 5:
		var piece := PieceData.new()
		piece.screen = 1
		piece.pos = Vector2i(100, 100)
		sector.pieces.append(piece)
	var found := SectorChecks.check(sector, _options(false))
	_expect(found, "header", CheckFinding.Severity.ERROR, "pieces: %d, but the header has room for %d" % [sector.pieces.size(), SectorData.MAX_PIECES])
	assert_bool(SectorChecks.passes(found)).is_false()


func test_pieces_on_no_screen_outside_the_playfield_or_in_the_rock_are_found() -> void:
	var sector := _copy_of()
	sector.pieces[1].screen = 14
	sector.pieces[2].pos = Vector2i(2, 2)
	_rock_with_pocket(sector, 4, false)
	sector.pieces[3].screen = 4
	sector.pieces[3].pos = Vector2i(300, 150)
	sector.pieces[0].is_canister = false
	sector.pieces[5].is_canister = true
	var found := SectorChecks.check(sector, _options(true))
	_expect(found, "piece.screen", CheckFinding.Severity.ERROR, "piece 1 on screen 14")
	_expect(found, "piece.place", CheckFinding.Severity.ERROR, "piece 2")
	_expect(found, "piece.buried", CheckFinding.Severity.ERROR, "piece 3")
	_expect(found, "piece.canister", CheckFinding.Severity.ERROR, "piece 0 is the data canister but is not marked")
	_expect(found, "piece.canister", CheckFinding.Severity.WARNING, "only piece 0 is the data canister")
	_expect(found, "reach.skipped", CheckFinding.Severity.INFO, "not on a screen of the sector")


func test_a_sector_without_pieces_needs_a_canister() -> void:
	var sector := _copy_of()
	sector.pieces.clear()
	_expect(SectorChecks.check(sector, _options(false)), "piece.canister", CheckFinding.Severity.ERROR, "piece 0 must be the data canister")


func test_a_start_inside_a_wall_or_outside_the_screen_is_found() -> void:
	var sector := _copy_of()
	var screen := _screen_copy(sector, Tuning.resolve().midpoint_screen)
	var cell := Vector2i(10, 8)
	screen.tiles[cell.y * ScreenData.TILE_COLUMNS + cell.x] = 0x40             # a wall tile on the respawn screen
	sector.start_pos = Vector2i(cell.x * 16, cell.y * 16 + 10)
	var found := SectorChecks.check(sector, _options(false))
	var finding := _expect(found, "start.position", CheckFinding.Severity.ERROR, "overlaps")
	assert_int(finding.screen).is_equal(Tuning.resolve().midpoint_screen)
	sector.start_pos = Vector2i(2000, 4)
	_expect(SectorChecks.check(sector, _options(false)), "start.position", CheckFinding.Severity.ERROR, "outside the screen")
	sector = _copy_of()
	sector.start_frame = 9
	_expect(SectorChecks.check(sector, _options(false)), "start.frame", CheckFinding.Severity.ERROR, "start frame 9")


func test_a_launch_spot_in_the_rock_is_found() -> void:
	var sector := _copy_of()
	var screen := _screen_copy(sector, 0)
	for row in range(11, 15):
		for column in range(4, 10):
			screen.tiles[row * ScreenData.TILE_COLUMNS + column] = 0x41
	_expect(SectorChecks.check(sector, _options(false)), "start.launch", CheckFinding.Severity.ERROR, "launch spot")


func test_creatures_on_no_screen_or_with_no_such_picture_are_found() -> void:
	var sector := _copy_of()
	sector.foes[0].screen = 12
	sector.foes[1].frame = 200
	var found := SectorChecks.check(sector, _options(false))
	_expect(found, "creature.screen", CheckFinding.Severity.ERROR, "creature 0 starts on screen 12")
	_expect(found, "creature.frame", CheckFinding.Severity.ERROR, "frame 200 is not a picture")


func test_a_zone_that_does_not_exist_and_a_song_that_does_not_exist_are_found() -> void:
	var sector := _copy_of()
	sector.zone = 9
	sector.music_name = "nothing"
	var found := SectorChecks.check(sector, _options(true))
	_expect(found, "sector.zone", CheckFinding.Severity.ERROR, "zone 9 does not exist")
	_expect(found, "sector.music", CheckFinding.Severity.WARNING, "'nothing'")
	_expect(found, "reach.skipped", CheckFinding.Severity.INFO, "zone does not exist")


func test_a_screen_that_does_not_fit_its_record_is_found_with_its_number() -> void:
	var sector := _copy_of()
	_screen_copy(sector, 7).tiles.resize(10)
	var found := SectorChecks.check(sector, _options(true))
	var finding := _expect(found, "screen.record", CheckFinding.Severity.ERROR, "tiles: 10 bytes")
	assert_int(finding.screen).is_equal(7)
	_expect(found, "reach.skipped", CheckFinding.Severity.INFO, "screen 7 has no complete tile map")


func test_the_finale_checks_ask_for_the_treasure() -> void:
	var sector := _copy_of(Ground.FINALE)
	var found := SectorChecks.check(sector, _options(true))
	assert_bool(SectorChecks.passes(found)).override_failure_message(_texts(found)).is_true()
	sector.foes.clear()
	found = SectorChecks.check(sector, _options(true))
	_expect(found, "reach.skipped", CheckFinding.Severity.INFO, "needs creature 0")


func test_without_the_search_no_reach_finding_is_made() -> void:
	var sector := _copy_of()
	_rock_with_pocket(sector, SimWorld.DOCK_SCREEN, false)
	for finding in SectorChecks.check(sector, _options(false)):
		assert_bool(finding.check.begins_with("reach.")).is_false()


func test_the_text_and_the_summary_list_what_was_found() -> void:
	var sector := _copy_of()
	sector.foes[0].start_label = "gone"
	sector.start_frame = 9
	var found := SectorChecks.check(sector, _options(false))
	assert_str(SectorChecks.summary(found)).is_equal("2 errors, 0 warnings, 0 allowed, 0 notes")
	assert_str(SectorChecks.text(found)).contains("error: sector %d" % Ground.MAIN).contains("[script.entry]").contains("[start.frame]")
	assert_int(found[0].severity).is_equal(CheckFinding.Severity.ERROR)
	var report := SectorReport.make(sector, false, true, false)
	assert_bool(report.passes()).is_false()
	assert_str(report.text()).contains("Playability checks of sector %d: FAIL (2 errors" % Ground.MAIN)
	assert_str(report.bbcode()).contains("[color=#e04040]FAIL[/color]").contains("[lb]script.entry]")
