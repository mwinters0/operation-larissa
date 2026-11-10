class_name TestNewSectorLegacy
extends GdUnitTestSuite
## The original's 32 sectors as the sector maker sees them: found first, never replaced, copied with the same content and the same play, their creature names turned
## into numbers. (The sector maker on dev's sectors is in `tests/engine/test_new_sector.gd`.)
##
## Teaches: testing new sectors, sectors that are found instead of counted and sectors the designers make. Every sector made here lives in a
## scratch folder under `user://` (never in `res://data/sectors` or the legacy pack's sectors, which these tests leave as they are), and `Catalog.sectors_dir` is pointed at that folder for the tests that PLAY a new sector, so the game's own
## `Catalog.sector(index)` finds it. The playability checks are the judge, as the fidelity tests are for the originals (a new sector has
## no original bytes to compare with). The Python half (the importer and the reset tools refuse such numbers) is tools/import/test_new_sectors.py.

const ROOT := "user://f4_new_sector_test"

static var _serial := 0
var _dir := ""
## The sectors the project itself holds when the test starts (the originals 0-31, then any of the designers'): what must be the same after it.
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


# --- playing a new sector ---------------------------------------------------------------------------------------------

func _new_run() -> Node:
	var run := auto_free(load("res://src/autoload/game_state.gd").new()) as Node
	run.reset()
	return run


## Launches from the station, then flies `ticks` ticks with the same scripted hands (those of sector 3), creatures awake. The trace,
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


# --- the originals ---------------------------------------------------------------------------------------------------

func test_the_project_has_the_32_original_sectors_and_discovery_finds_them_first() -> void:
	var ids := Catalog.sector_ids()
	assert_int(Catalog.ORIGINAL_SECTOR_COUNT).is_equal(32)
	assert_int(ids.size()).is_greater_equal(Catalog.ORIGINAL_SECTOR_COUNT)                # (the project's own campaigns add sectors from 32 up, F6)
	assert_array(Array(ids).slice(0, Catalog.ORIGINAL_SECTOR_COUNT)).is_equal(range(Catalog.ORIGINAL_SECTOR_COUNT))     # the originals, 0-31, first
	assert_int(Catalog.sector_count()).is_equal(ids.size())
	assert_int(Catalog.last_sector()).is_equal(ids[-1])
	assert_bool(Catalog.has_sector(0) and Catalog.has_sector(31)).is_true()
	for id in Array(ids).slice(Catalog.ORIGINAL_SECTOR_COUNT):
		assert_bool(Catalog.is_original_sector(id)).is_false()                            # every other one is a designers' sector
	assert_bool(Catalog.has_sector(-1) or Catalog.has_sector(Catalog.MAX_SECTOR)).is_false()
	assert_bool(Catalog.is_original_sector(31)).is_true()
	assert_bool(Catalog.is_original_sector(32) or Catalog.is_original_sector(-1)).is_false()
	var free := Catalog.next_free_sector()                                                # a new sector never takes an original's number, or a taken one
	assert_int(free).is_greater_equal(Catalog.ORIGINAL_SECTOR_COUNT)
	assert_bool(Catalog.has_sector(free)).is_false()



func test_the_originals_are_never_replaced_and_a_taken_number_is_refused() -> void:
	var before := FileAccess.get_file_as_string(Catalog.sector_path(5))
	for index in [0, 5, 31]:
		var made := SectorFactory.new_from_template(index, 0, 0, _dir)
		assert_str(made.error).contains("original sector")
		assert_int(made.index).is_equal(-1)
		assert_bool(DirAccess.dir_exists_absolute(Catalog.sector_dir(index, _dir))).is_false()
		assert_str(SectorFactory.new_from_copy(3, index, _dir, LegacyPack.SECTORS_DIR).error).contains("original sector")
	assert_str(SectorFactory.new_from_template(256, 0, 0, _dir).error).contains("out of range")
	assert_str(SectorFactory.new_from_template(40, 0, 0, _dir).error).is_empty()
	assert_str(SectorFactory.new_from_template(40, 0, 0, _dir).error).contains("exists already")
	assert_str(SectorFactory.new_from_template(41, 9, 0, _dir).error).contains("zone 9")
	assert_str(SectorFactory.new_from_template(41, 0, 2, _dir).error).contains("game 2")
	assert_bool(DirAccess.dir_exists_absolute(Catalog.sector_dir(41, _dir))).is_false()     # a refusal leaves nothing behind
	assert_str(SectorFactory.new_from_copy(77, 50, _dir, _dir).error).contains("no sector 77 to copy")
	assert_str(SectorFactory.refusal(5)).contains("original sector")
	assert_str(SectorFactory.refusal(Catalog.next_free_sector())).is_empty()
	assert_str(SectorFactory.refusal(Catalog.last_sector())).is_not_empty()                 # taken: an original (31) or a designer's sector
	assert_str(FileAccess.get_file_as_string(Catalog.sector_path(5))).is_equal(before)
	assert_array(Catalog.sector_ids()).is_equal(_project_ids)



func test_a_copy_of_an_original_has_the_same_content_and_passes_the_checks() -> void:
	for source in [3, 5]:
		var index: int = 40 + source
		var made := SectorFactory.new_from_copy(source, index, _dir, LegacyPack.SECTORS_DIR)
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
			assert_str(FileAccess.get_file_as_string(ScreenFile.screen_path(_dir, index, m))).is_equal(FileAccess.get_file_as_string(ScreenFile.screen_path(LegacyPack.SECTORS_DIR, source, m)))
		var text := FileAccess.get_file_as_string(Catalog.sector_path(index, _dir))
		assert_bool(text.contains(Catalog.sector_dir(source) + "/")).is_false()   # nothing points back into the source's folder
		assert_str(text).contains(Catalog.sector_dir(index, _dir) + "/screen_00.tres")
		var found := _checked(sector)
		assert_str(_problems_text(found)).override_failure_message("the copy of sector %d: %s" % [source, _problems_text(found)]).is_empty()



func test_a_copy_of_a_copy_and_a_copy_from_another_folder() -> void:
	assert_str(SectorFactory.new_from_copy(3, 40, _dir, LegacyPack.SECTORS_DIR).error).is_empty()
	var second := SectorFactory.new_from_copy(40, 41, _dir)                        # the source is read from the same folder by default
	assert_str(second.error).is_empty()
	assert_array(Array(_load(41).foe_bytecode)).is_equal(Array(Catalog.sector(3).foe_bytecode))
	assert_str(_problems_text(_checked(_load(41), false))).is_empty()



func test_a_copy_keeps_the_originals_known_findings_and_a_finale_is_no_longer_one() -> void:
	# sector 7 has two one-way doors in the original's own table: the copy reports them like the original (the allow-list is by number)
	SectorFactory.new_from_copy(7, 47, _dir, LegacyPack.SECTORS_DIR)
	var failures := SectorChecks.failures(_checked(_load(47), false))
	assert_array(failures).is_not_empty()
	for finding in failures:
		assert_str(finding.check).is_equal("link.one_way")



func test_the_script_of_a_copy_names_its_creatures_by_number_where_the_name_is_the_sources() -> void:
	var original := Catalog.sector(3)
	assert_str(original.foe_script.source).contains("ray_stinger")                  # sector 3's own name for a creature
	SectorFactory.new_from_copy(3, 43, _dir, LegacyPack.SECTORS_DIR)
	var copied := _load(43)
	assert_str(copied.foe_script.source).starts_with("; Sector 43 - a copy of sector 3")
	assert_bool(copied.foe_script.source.contains("Wake_Foe ray_stinger")).is_false()
	assert_str(copied.foe_script.source).contains("Wake_Foe %d" % FoeNames.new(null, 3, original.zone).index_for(FoeOps.Kind.FOE, "ray_stinger"))
	assert_array(copied.compile_errors).is_empty()



func test_renaming_touches_only_operands_that_would_change_meaning() -> void:
	var from := FoeNames.new(null, 3, 1)
	var to := FoeNames.new(null, 43, 1)
	var number := from.index_for(FoeOps.Kind.FOE, "ray_stinger")
	assert_int(number).is_greater_equal(0)
	assert_int(to.index_for(FoeOps.Kind.FOE, "ray_stinger")).is_equal(-1)
	var text := "start:\n\tWake_Foe ray_stinger   ; ray_stinger stays in a comment\n\tWake_Foe self+1\n\tPlay_Sound begin\n\tJump_To start\n\tWake_Foe %d\n" % number
	var renamed := SectorFactory.rename_for_sector(text, from, to)
	assert_str(renamed).is_equal(text.replace("Wake_Foe ray_stinger", "Wake_Foe %d" % number))
	assert_str(SectorFactory.rename_for_sector(text, from, from)).is_equal(text)          # same scope: nothing to translate
	assert_str(renamed).contains("Play_Sound begin").contains("; ray_stinger stays in a comment").contains("Wake_Foe self+1")



func test_a_copy_of_an_original_plays_exactly_as_the_original_does() -> void:
	SectorFactory.new_from_copy(3, 43, _dir, LegacyPack.SECTORS_DIR)
	var original_trace := _flight(3, 150)
	Catalog.sectors_dir = _dir
	var copy_trace := _flight(43, 150)
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	assert_int(copy_trace.size()).is_greater(300)
	var at := 0
	while at < mini(copy_trace.size(), original_trace.size()) and copy_trace[at] == original_trace[at]:
		at += 1
	var difference := "" if at >= mini(copy_trace.size(), original_trace.size()) and copy_trace.size() == original_trace.size() else "line %d: %s  <>  %s" % [at, original_trace[at] if at < original_trace.size() else "-", copy_trace[at] if at < copy_trace.size() else "-"]
	assert_str(difference).override_failure_message("the copy's trace differs from the original's at " + difference).is_empty()



func test_the_playtest_and_the_sandbox_take_a_new_sector() -> void:
	SectorFactory.new_from_copy(3, 43, _dir, LegacyPack.SECTORS_DIR)
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


