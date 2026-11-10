class_name TestNewSector
extends GdUnitTestSuite
## Teaches: testing new sectors, sectors that are found instead of counted and sectors the designers make. Every sector made here lives in a
## scratch folder under `user://` (never in `res://data/sectors`: the project's own sectors are left as they are), and `Catalog.sectors_dir` is pointed at that folder for the tests that PLAY a new sector, so the game's own
## `Catalog.sector(index)` finds it. The playability checks are the judge, as the fidelity tests are for the originals (a new sector has
## no original bytes to compare with). The Python half (the importer and the reset tools refuse such numbers) is tools/import/test_new_sectors.py.

const ROOT := "user://f4_new_sector_test"

static var _serial := 0
var _dir := ""
## The sectors the chain holds when the test starts: what must be the same after it.
var _project_ids: Array = []


func before_test() -> void:
	_serial += 1
	_dir = "%s/t%d" % [ROOT, _serial]                  # a folder of its own for every test: loaded resources are cached by path
	DirAccess.make_dir_recursive_absolute(_dir)
	_project_ids = Array(Catalog.sector_ids())


func after_test() -> void:
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	_remove_tree(ROOT)


func _remove_tree(path: String) -> void:
	for folder in DirAccess.get_directories_at(path):
		_remove_tree(path + "/" + folder)
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + file_name)
	DirAccess.remove_absolute(path)


func _load(index: int) -> SectorData:
	var sector := ResourceLoader.load(Catalog.sector_path(index, _dir), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	assert_object(sector).override_failure_message("sector %d could not be loaded from %s" % [index, _dir]).is_not_null()
	sector.ensure_compiled()
	return sector


func _checked(sector: SectorData, reach := true) -> Array[CheckFinding]:
	var options := SectorChecks.Options.new()
	options.reach = reach
	return SectorChecks.check(sector, options)


func _problems_text(found: Array[CheckFinding]) -> String:
	return "\n".join(SectorChecks.failures(found).map(func(f: CheckFinding) -> String: return f.text()))


# --- discovery ---------------------------------------------------------------------------------------------------------

func test_discovery_finds_the_sectors_of_the_chain_in_order() -> void:
	var ids := Catalog.sector_ids()
	assert_int(ids.size()).is_greater_equal(DevPack.TOUR_SECTORS.size() + 1)
	assert_array(Array(ids)).is_equal(Array(ids).duplicate())                              # (a list, found by looking at the folders)
	for k in ids.size() - 1:
		assert_int(ids[k]).is_less(ids[k + 1])                                          # in order, each once
	assert_int(Catalog.sector_count()).is_equal(ids.size())
	assert_int(Catalog.last_sector()).is_equal(ids[-1])
	assert_bool(Catalog.has_sector(0) and Catalog.has_sector(DevPack.TOUR_FINALE) and Catalog.has_sector(Ground.MAIN)).is_true()
	assert_bool(Catalog.has_sector(-1) or Catalog.has_sector(Catalog.MAX_SECTOR)).is_false()
	var free := Catalog.next_free_sector()                                                # a new sector never takes a taken number
	assert_int(free).is_greater_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	assert_bool(Catalog.has_sector(free)).is_false()


func test_a_new_sector_folder_appears_and_the_others_stay() -> void:
	# a copy of the sectors folder: two sectors' folders (files copied) and then a sector the designers made
	for index in [0, 3]:
		DirAccess.make_dir_recursive_absolute(Catalog.sector_dir(index, _dir))
		var path := Catalog.sector_path(index, _dir)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(FileAccess.get_file_as_string(Catalog.sector_path(index)))
		file.close()
	assert_array(Catalog.sector_ids(_dir)).is_equal([0, 3])
	var made := SectorFactory.new_from_template(40, 0, 0, _dir)
	assert_str(made.error).is_empty()
	assert_array(Catalog.sector_ids(_dir)).is_equal([0, 3, 40])
	assert_bool(Catalog.has_sector(40, _dir)).is_true()
	assert_bool(Catalog.has_sector(40)).is_false()                            # the project's own folder is untouched
	assert_array(Catalog.sector_ids()).is_equal(_project_ids)


func test_only_real_sector_folders_count() -> void:
	SectorFactory.new_from_template(33, 0, 0, _dir)
	for name in ["sector_7", "sector_007", "sector_x", "sector_-4", "sector_+5", "sector_300", "sector_41", "notes"]:
		DirAccess.make_dir_recursive_absolute(_dir + "/" + name)                  # (no sector_NN.tres in any of them)
	var stray := FileAccess.open(_dir + "/sector_50", FileAccess.WRITE)           # a file, not a folder
	stray.close()
	assert_array(Catalog.sector_ids(_dir)).is_equal([33])
	assert_bool(Catalog.has_sector(41, _dir)).is_false()


func test_numbers_of_three_digits_widen_the_folder_name() -> void:
	var made := SectorFactory.new_from_template(100, 0, 0, _dir)
	assert_str(made.error).is_empty()
	assert_str(Catalog.sector_dir(100, _dir)).ends_with("/sector_100")
	assert_str(made.path).ends_with("/sector_100/sector_100.tres")
	assert_array(Catalog.sector_ids(_dir)).is_equal([100])
	assert_int(Catalog.sector_of_path(made.path)).is_equal(100)
	assert_int(Catalog.sector_of_path(Catalog.foe_path(100, _dir))).is_equal(100)
	assert_int(_load(100).index).is_equal(100)


func test_stepping_through_the_sectors_wraps_round_the_ones_that_exist() -> void:
	var ids := Catalog.sector_ids()
	assert_int(Catalog.step_sector(Catalog.last_sector(), 1)).is_equal(ids[0])
	assert_int(Catalog.step_sector(ids[0], -1)).is_equal(Catalog.last_sector())
	assert_int(Catalog.step_sector(2, 1)).is_equal(3)
	assert_int(Catalog.step_sector(50, 1)).is_equal(Ground.MAIN)                  # a number between two sectors steps to its neighbours
	assert_int(Catalog.step_sector(50, -1)).is_equal(DevPack.TOUR_FINALE)
	for index in [32, 40, 100]:
		SectorFactory.new_from_template(index, 0, 0, _dir)
	assert_int(Catalog.step_sector(100, 1, _dir)).is_equal(32)
	assert_int(Catalog.step_sector(32, -1, _dir)).is_equal(100)
	assert_int(Catalog.step_sector(32, 1, _dir)).is_equal(40)
	assert_int(Catalog.step_sector(35, 1, _dir)).is_equal(40)                  # a number between two sectors steps to its neighbours
	assert_int(Catalog.step_sector(35, -1, _dir)).is_equal(32)
	assert_int(Catalog.nearest_sector(40, _dir)).is_equal(40)
	assert_int(Catalog.nearest_sector(37, _dir)).is_equal(40)
	assert_int(Catalog.nearest_sector(3, _dir)).is_equal(32)
	assert_int(Catalog.nearest_sector(250, _dir)).is_equal(100)
	assert_int(Catalog.next_free_sector(_dir)).is_equal(33)                     # the lowest free number from 32 up
	assert_int(Catalog.last_sector(_dir)).is_equal(100)


func test_the_folder_the_game_looks_in_can_be_pointed_elsewhere_and_put_back() -> void:
	SectorFactory.new_from_template(40, 2, 1, _dir)
	assert_bool(Catalog.has_sector(40)).is_false()
	Catalog.sectors_dir = _dir
	assert_array(Catalog.sector_ids()).is_equal([40])
	var sector := Catalog.sector(40)
	assert_object(sector).is_not_null()
	assert_int(sector.zone).is_equal(2)
	assert_int(sector.game).is_equal(1)
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	assert_array(Catalog.sector_ids()).is_equal(_project_ids)


# --- making a sector: refusals ----------------------------------------------------------------------------------------

func test_a_taken_or_impossible_number_is_refused_and_leaves_nothing_behind() -> void:
	var before := FileAccess.get_file_as_string(Catalog.sector_path(Ground.MAIN))
	assert_str(SectorFactory.new_from_template(Ground.MAIN, 0, 0, DevPack.SECTORS_DIR).error).contains("exists already")
	assert_str(SectorFactory.new_from_template(256, 0, 0, _dir).error).contains("out of range")
	assert_str(SectorFactory.new_from_template(40, 0, 0, _dir).error).is_empty()
	assert_str(SectorFactory.new_from_template(40, 0, 0, _dir).error).contains("exists already")
	assert_str(SectorFactory.new_from_template(41, 9, 0, _dir).error).contains("zone 9")
	assert_str(SectorFactory.new_from_template(41, 0, 2, _dir).error).contains("game 2")
	assert_bool(DirAccess.dir_exists_absolute(Catalog.sector_dir(41, _dir))).is_false()     # a refusal leaves nothing behind
	assert_str(SectorFactory.new_from_copy(77, 50, _dir, _dir).error).contains("no sector 77 to copy")
	assert_str(SectorFactory.refusal(Catalog.next_free_sector())).is_empty()
	assert_str(SectorFactory.refusal(Catalog.last_sector())).contains("exists already")
	assert_str(FileAccess.get_file_as_string(Catalog.sector_path(Ground.MAIN))).is_equal(before)
	assert_array(Catalog.sector_ids()).is_equal(_project_ids)


func test_with_no_number_the_next_free_one_is_taken() -> void:
	assert_int(SectorFactory.new_from_template(-1, 0, 0, _dir).index).is_equal(32)
	assert_int(SectorFactory.new_from_template(-1, 0, 0, _dir).index).is_equal(33)
	assert_int(SectorFactory.new_from_copy(32, -1, _dir).index).is_equal(34)
	assert_array(Catalog.sector_ids(_dir)).is_equal([32, 33, 34])


# --- the template -----------------------------------------------------------------------------------------------------

func test_the_template_sector_is_what_the_checks_accept() -> void:
	var made := SectorFactory.new_from_template(40, 0, 0, _dir)
	assert_str(made.error).is_empty()
	assert_array(made.files).has_size(2 + SectorData.SCREEN_COUNT)
	var sector := _load(40)
	assert_int(sector.index).is_equal(40)
	assert_int(sector.screens.size()).is_equal(SectorData.SCREEN_COUNT)
	assert_int(sector.foes.size()).is_equal(0)
	assert_bool(sector.pieces[0].is_canister).is_true()
	assert_array(sector.compile_errors).is_empty()
	assert_array(sector.header_problems()).is_empty()
	assert_array(sector.resource_problems()).is_empty()
	var found := _checked(sector)                                          # with the reachability search
	assert_str(_problems_text(found)).is_empty()
	assert_array(found).override_failure_message("a template has no findings at all: " + SectorChecks.text(found)).is_empty()
	var report := SectorChanges.report(sector)                               # no original: the report says so, nothing to compare
	assert_array(report.notes).has_size(1)
	assert_str(report.notes[0]).contains("not one of the original's")


func test_the_template_comes_in_every_zone_and_game() -> void:
	for zone in Catalog.ZONE_COUNT:
		var index: int = 32 + zone
		assert_str(SectorFactory.new_from_template(index, zone, zone % 2, _dir).error).is_empty()
		var sector := _load(index)
		assert_int(sector.zone).is_equal(zone)
		assert_int(sector.game).is_equal(zone % 2)
		if zone < 5:
			assert_str(sector.music_name).is_not_empty()                          # the song of the zone's first sector (the finale zones have none in dev)
		assert_str(_problems_text(_checked(sector, false))).is_empty()
	assert_str(_problems_text(_checked(_load(34)))).is_empty()                    # (a zone with the search too)


func test_the_template_can_be_edited_with_the_editors_own_writers() -> void:
	SectorFactory.new_from_template(40, 0, 0, _dir)
	var path := Catalog.sector_path(40, _dir)
	var disk := _load(40)
	var wanted := disk.duplicate_deep() as SectorData
	wanted.screens = disk.screens                                           # (the screens are files of their own)
	wanted.foe_script = disk.foe_script
	assert_array(wanted.add_foe(2, Vector2i(200, 100))).is_empty()           # a sector without creatures gets an empty one
	wanted.foes[0].start_label = "foe0_start"
	wanted.foes[0].hit_label = "foe0_hit"
	wanted.foes[0].ink_label = "foe0_ink"
	assert_array(wanted.add_piece(5, Vector2i(100, 100))).is_empty()
	var patched := ScreenFile.sector_patch(FileAccess.get_file_as_string(path), disk, wanted)
	assert_str(patched.error).is_empty()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(patched.text)
	file.close()
	var again := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	assert_int(again.foes.size()).is_equal(1)
	assert_int(again.pieces.size()).is_equal(3)
	assert_str(again.foes[0].start_label).is_equal("foe0_start")


# --- copies -----------------------------------------------------------------------------------------------------------

func test_a_copy_has_the_same_content_and_passes_the_checks() -> void:
	var target := 40
	for source in [Ground.EDIT, Ground.MAIN]:
		var index: int = target
		target += 1
		var made := SectorFactory.new_from_copy(source, index, _dir, DevPack.SECTORS_DIR)
		assert_str(made.error).is_empty()
		assert_array(made.files).has_size(2 + SectorData.SCREEN_COUNT)
		var original := Catalog.sector(source)
		var sector := _load(index)
		assert_int(sector.index).is_equal(index)
		assert_int(sector.zone).is_equal(original.zone)
		assert_int(sector.foes.size()).is_equal(original.foes.size())
		assert_array(Array(sector.foe_bytecode)).is_equal(Array(original.foe_bytecode))   # the same program, to the byte
		for k in sector.foes.size():
			assert_int(sector.foes[k].pc).is_equal(original.foes[k].pc)
			assert_int(sector.foes[k].script_hit).is_equal(original.foes[k].script_hit)
		for m in SectorData.SCREEN_COUNT:                                        # the screens are the same files, text for text
			assert_str(FileAccess.get_file_as_string(ScreenFile.screen_path(_dir, index, m))).is_equal(FileAccess.get_file_as_string(ScreenFile.screen_path(DevPack.SECTORS_DIR, source, m)))
		var text := FileAccess.get_file_as_string(Catalog.sector_path(index, _dir))
		assert_bool(text.contains(Catalog.sector_dir(source) + "/")).is_false()   # nothing points back into the source's folder
		assert_str(text).contains(Catalog.sector_dir(index, _dir) + "/screen_00.tres")
		var found := _checked(sector)
		assert_str(_problems_text(found)).override_failure_message("the copy of sector %d: %s" % [source, _problems_text(found)]).is_empty()


func test_a_copy_of_a_copy_and_a_copy_from_another_folder() -> void:
	assert_str(SectorFactory.new_from_copy(Ground.EDIT, 40, _dir, DevPack.SECTORS_DIR).error).is_empty()
	var second := SectorFactory.new_from_copy(40, 41, _dir)                        # the source is read from the same folder by default
	assert_str(second.error).is_empty()
	assert_array(Array(_load(41).foe_bytecode)).is_equal(Array(Catalog.sector(Ground.EDIT).foe_bytecode))
	assert_str(_problems_text(_checked(_load(41), false))).is_empty()


func test_a_copy_reports_the_findings_of_its_source_by_its_own_number() -> void:
	# the tangle sector has one-way doors in its tables: the copy reports them, whatever its number
	SectorFactory.new_from_copy(Ground.TANGLE, 47, _dir, DevPack.SECTORS_DIR)
	var failures := SectorChecks.failures(_checked(_load(47), false))
	assert_array(failures).is_not_empty()
	for finding in failures:
		assert_str(finding.check).is_equal("link.one_way")


# --- playing a new sector ---------------------------------------------------------------------------------------------

func _new_run() -> Node:
	var run := auto_free(load("res://src/autoload/game_state.gd").new()) as Node
	run.reset()
	return run


## Launches from the station, then flies `ticks` ticks with the same scripted hands, creatures awake. The trace,
## with the sector's number left out of it.
func _flight(index: int, ticks: int) -> Array[String]:
	var run := _new_run()
	var stage := HeadlessStage.new(run)
	var trace := SimTrace.record(stage.sim, run)
	stage.sim.foe_rng.seed = 4242                                            # (the creatures tick through the launch too)
	stage.begin_sector(index, false)
	assert_int(stage.sim.sector_index).is_equal(index)
	var requested := [-1]                                                    # the slot of the problem that is open
	stage.sim.problem_requested.connect(func(slot: int) -> void: requested[0] = slot)
	var hands := SimTrace.Hands.new(3, 0)
	for t in ticks:
		stage.tick(hands.at(t))
		if stage.sim.problem_active:
			stage.sim.problem_resolved(requested[0], ProblemSession.new(null))
		if stage.sim.is_dissolving():
			while stage.sim.is_dissolving():
				stage.sim.advance_dissolve(1)
			stage.sim.start_flight()
	trace.flush()
	var same: Array[String] = []
	for line in trace.lines:                                                  # (the events that name the sector are written with a letter for it)
		if not line.contains("sector_loaded"):
			same.append(line.replace("screen_loaded %d " % index, "screen_loaded S "))
	return same


func test_a_template_sector_is_played_headless() -> void:
	SectorFactory.new_from_template(40, 0, 0, _dir)
	Catalog.sectors_dir = _dir
	var run := _new_run()
	var stage := HeadlessStage.new(run)
	var trace := SimTrace.record(stage.sim, run)
	stage.begin_sector(40, false)                                            # the launch from the station: 30 ticks, played out
	assert_array(trace.events_like("trip_finished 0")).has_size(1)
	assert_int(stage.sim.sector.index).is_equal(40)
	var start := stage.sim.sub.original_position()
	for t in 10:
		stage.tick(InputSnapshot.steering(1, 0))
	assert_int(stage.sim.sub.original_position().x).is_greater(start.x)         # the sub swims right along the empty water
	assert_int(stage.sim.screen_index).is_equal(0)
	for t in 120:
		stage.tick(InputSnapshot.steering(1, 0))
	assert_int(stage.sim.screen_index).is_greater(0)                             # and out of the right edge into screen 1, the next of the chain
	assert_int(trace.ticks).is_greater_equal(130)


func test_a_copy_plays_exactly_as_its_source_does() -> void:
	SectorFactory.new_from_copy(Ground.EDIT, 43, _dir, DevPack.SECTORS_DIR)
	var original_trace := _flight(Ground.EDIT, 150)
	Catalog.sectors_dir = _dir
	var copy_trace := _flight(43, 150)
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	assert_int(copy_trace.size()).is_greater(150)                           # (the trace has events as well as ticks)
	var at := 0
	while at < mini(copy_trace.size(), original_trace.size()) and copy_trace[at] == original_trace[at]:
		at += 1
	var difference := "" if at >= mini(copy_trace.size(), original_trace.size()) and copy_trace.size() == original_trace.size() else "line %d: %s  <>  %s" % [at, original_trace[at] if at < original_trace.size() else "-", copy_trace[at] if at < copy_trace.size() else "-"]
	assert_str(difference).override_failure_message("the copy's trace differs from its source's at " + difference).is_empty()


func test_the_playtest_and_the_sandbox_take_a_new_sector() -> void:
	SectorFactory.new_from_copy(Ground.EDIT, 43, _dir, DevPack.SECTORS_DIR)
	var setup := PlaytestSetup.new()
	setup.sector = 43
	setup.screen = 2
	assert_str(setup.problems()[0]).contains("sector 43 does not exist")
	Catalog.sectors_dir = _dir
	assert_array(Array(setup.problems())).is_empty()
	var sim := SimWorld.new(_new_run())
	setup.apply(sim)
	assert_int(sim.sector_index).is_equal(43)
	assert_int(sim.screen_index).is_equal(2)
	# the Foe Script panel runs the sandbox for a sector of the catalog, and says why not for one that is not there
	var panel := FoeEditorPanel.new()
	add_child(panel)
	auto_free(panel)
	var requests: Array[String] = []
	panel.sandbox_requested.connect(func(arguments: String) -> void: requests.append(arguments))
	var doc := panel.open_script(ResourceLoader.load(Catalog.foe_path(43, _dir), "", ResourceLoader.CACHE_MODE_REPLACE) as FoeScript)
	assert_str(panel.run_in_sandbox()).is_empty()
	assert_str(requests[0]).contains("--sector=43")
	assert_object(doc).is_not_null()
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	assert_str(panel.run_in_sandbox()).contains("there is no sector 43")


# --- the editor entry point -------------------------------------------------------------------------------------------

func test_the_new_sector_window_offers_the_template_and_every_sector_and_refuses_a_bad_number() -> void:
	var dialog := NewSectorDialog.new()
	dialog.dir = _dir
	add_child(dialog)
	auto_free(dialog)
	dialog.open()
	assert_int(dialog.chosen_number()).is_equal(32)
	assert_int(dialog.chosen_source()).is_equal(-1)                              # the empty template, as there is no sector yet
	assert_str(dialog.problem()).is_empty()
	var made: Array = []
	dialog.sector_made.connect(func(result: SectorFactory.Made) -> void: made.append(result))
	var first := dialog.create()
	assert_str(first.error).is_empty()
	assert_array(made).has_size(1)
	assert_int((made[0] as SectorFactory.Made).index).is_equal(32)
	assert_array(Catalog.sector_ids(_dir)).is_equal([32])
	dialog.open(32)                                                              # the sector looked at is offered as the copy to make
	assert_int(dialog.chosen_source()).is_equal(32)
	assert_int(dialog.chosen_number()).is_equal(33)
	assert_str(dialog.create().error).is_empty()
	assert_array(Catalog.sector_ids(_dir)).is_equal([32, 33])
	dialog._number_box.value = 33                                                # taken
	assert_str(dialog.problem()).contains("exists already")
	assert_str(dialog.create().error).contains("exists already")
	assert_bool(dialog.get_ok_button().disabled).is_true()
	assert_array(made).has_size(2)                                               # (a refusal makes nothing and says nothing was made)
	dialog.hide()
