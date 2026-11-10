class_name TestDurations
extends GdUnitTestSuite
## Teaches: a duration that holds up play is DATA the rules read. The project's `data/rules/durations.json` is the lowest layer and a pack's
## `rules/durations.json` lies over it key by key; this test lays one more file over them - a longer dock, a slower balloon, a longer dissolve, a longer
## message - and watches the rules change their timing and nothing else: the trips take the new number of ticks, `sequence_finished` comes in the tick
## the data says, and every skin (`SkinRoster.all()`) plays the longer game exactly as the plain objects do (`test_skins_dont_change_the_game.gd` with other numbers). (The base file's
## own numbers, the original's: tests/legacy/test_durations_legacy.gd.)

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const PACK_FILE := "user://test_durations_pack.json"

## A file that changes some of them: a dock of 37 ticks (7 opening, 5 closing, 4 px per tick over the pack's 100), a balloon at 11 px per
## tick, a dissolve of 30 ticks, messages of 100. It leaves the rest (and the launch) alone.
const PACK := {
	"station": {
		"dock": {"opening_ticks": 7, "closing_ticks": 5, "pixels_per_tick": 4},
		"balloon": {"pixels_per_tick": 11},
	},
	"dissolve": {"ticks": 30},
	"problem": {"message_ticks": 100},
}


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	Durations.use_base()
	GameState.reset()


func after_test() -> void:
	Durations.use_base()
	GameClock.paused = false
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	if FileAccess.file_exists(PACK_FILE):
		DirAccess.remove_absolute(PACK_FILE)


## Lays the pack `layer` (a Dictionary, written as the JSON file it would be) over the base game's durations.
func _mount(layer: Dictionary = PACK) -> void:
	var file := FileAccess.open(PACK_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(layer))
	file.close()
	Durations.extra_files = [PACK_FILE]
	Durations.read_files()


# --- the base game ------------------------------------------------------------------------------------

func _leaves(node: Variant, path: String, into: Array[String]) -> void:
	if node is Dictionary:
		for key: String in node:
			if not key.begins_with("_"):                                   # ("_about" is the file's note to its reader)
				_leaves(node[key], path + ("." if not path.is_empty() else "") + key, into)
	else:
		into.append(path)


func test_no_moved_duration_is_a_constant_in_code_any_more() -> void:
	var names := ["DISSOLVE_TICKS", "SCAN_TICKS", "SCAN_PICTURE_TICKS", "SCAN_SWEEPS", "FADE_TICKS", "OPENING_TICKS", "CLOSING_TICKS", "PIXELS_PER_TICK",
			"LAUNCH_FROM_X", "LAUNCH_TO_X", "DOCK_FROM_X", "DOCK_TO_X", "BALLOON_X", "BALLOON_FROM_Y", "BALLOON_TO_Y", "BALLOON_WINDOW_X",
			"BALLOON_TOP_Y", "LAUNCHED_X", "MESSAGE_TICKS", "WAIT_TICKS", "KEY_FLASH_TICKS", "FLASH_TICKS", "SPEECH_START_DELAY_TICKS",
			"SPEECH_GROUPS", "PRE_SCAN_TICKS", "PRESSED_TICKS", "SILENT_SPEECH_TICKS"]
	var found := SourceScan.find_in(SourceScan.scripts_under("res://src"), names)
	assert_array(found).override_failure_message("a duration is a constant again:\n" + "\n".join(found)).is_empty()


# --- another pack ---------------------------------------------------------------------------------------

func test_the_packs_file_lies_over_the_base_key_by_key() -> void:
	var files := Durations.files()
	assert_str(files[0]).is_equal(Durations.BASE_PATH)
	assert_int(files.size()).is_greater(1)                                   # (the pack in use has a file of its own)
	var base: Array[String] = []
	_leaves(JSON.parse_string(FileAccess.get_file_as_string(files[0])), "", base)
	var pack: Array[String] = []
	var pack_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(files[1]))
	_leaves(pack_data, "", pack)
	assert_array(pack).is_not_empty()
	for path in pack:
		var value: Variant = _value_at(pack_data, path)
		if value is Array:
			assert_array(Durations.list_at(path)).override_failure_message(path).is_equal((value as Array).map(func(each: Variant) -> int: return int(each)))
		else:
			assert_int(Durations.at(path)).override_failure_message(path).is_equal(int(value))
	var kept := base.filter(func(path: String) -> bool: return not pack.has(path) and not path.begins_with("news.group"))
	assert_array(kept).is_not_empty()                                         # (the pack leaves some keys out: they keep the base file's number)
	var base_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(files[0]))
	for path in kept:
		assert_int(Durations.at(path)).override_failure_message(path).is_equal(int(_value_at(base_data, path)))


func _value_at(data: Variant, path: String) -> Variant:
	for key in path.split("."):
		data = (data as Dictionary)[key]
	return data


func test_a_file_laid_over_overrides_key_by_key_and_keeps_the_rest() -> void:
	var before_dock := Durations.at("station.dock.opening_ticks")
	var from_x := Durations.at("station.dock.from_x")
	var launch := Durations.at("station.launch.opening_ticks")
	var fade := Durations.at("fade.ticks")
	_mount()
	assert_int(Durations.at("station.dock.opening_ticks")).is_equal(7)
	assert_int(Durations.at("station.dock.from_x")).is_equal(from_x)           # (not in the file: the layer below's)
	assert_int(Durations.at("station.launch.opening_ticks")).is_equal(launch)
	assert_int(Durations.at("fade.ticks")).is_equal(fade)
	Durations.use_base()
	assert_int(Durations.at("station.dock.opening_ticks")).is_equal(before_dock)


func test_a_longer_dock_takes_longer_in_the_rules_and_nothing_else_changes() -> void:
	var launch_ticks := StationSequence.launch().ticks
	_mount()
	var dock := StationSequence.dock()
	assert_int(dock.drive_ticks()).is_equal(25)                             # 100 px at 4 px per tick
	assert_int(dock.ticks).is_equal(7 + 25 + 5)
	assert_array([StationSequence.launch().ticks, StationSequence.balloon().ticks]).is_equal([launch_ticks, 16])      # (the balloon: 176 px at 11)
	# the door follows: picture 3, 4, open for the rest of the opening; closing 4, 3, closed
	assert_array([dock.door_picture(0), dock.door_picture(1), dock.door_picture(2), dock.door_picture(6), dock.door_picture(31)]) \
			.is_equal([3, 4, StationSequence.DOOR_OPEN, StationSequence.DOOR_OPEN, StationSequence.DOOR_OPEN])
	assert_array([dock.door_picture(32), dock.door_picture(33), dock.door_picture(34), dock.door_picture(36)]) \
			.is_equal([4, 3, StationSequence.DOOR_CLOSED, StationSequence.DOOR_CLOSED])
	assert_int(dock.door_sound_tick()).is_equal(33)
	assert_array([dock.sub_x(7), dock.sub_x(8), dock.sub_x(32)]).is_equal([dock.from_x, dock.from_x + 4, dock.to_x])

	var sim := SimWorld.new(GameState)
	sim.load_sector(0, 11)
	sim.start_flight(400, 200, 6)
	var seen: Array[String] = []
	sim.sequence_started.connect(func(trip: StationSequence) -> void: seen.append("started %d" % trip.ticks))
	sim.sequence_finished.connect(func(_trip: StationSequence) -> void: seen.append("finished at tick %d" % sim.tick_number))
	sim.sound_requested.connect(func(sfx: StringName) -> void: seen.append("sound %s at %d" % [sfx, sim.tick_number]))
	sim.start_dock()
	for t in 36:
		sim.tick()
	assert_bool(sim.sub.active).is_true()                                   # still driving in
	sim.tick()                                                              # the 37th
	assert_bool(sim.sub.active).is_false()
	assert_int(sim.sub.original_position().x).is_equal(dock.to_x)
	assert_array(seen).is_equal(["started 37", "sound station_door at 32", "finished at tick 36"])


## A trip copies its numbers when it begins, and the view of it (`SimView.SequenceState`) copies the trip's, not the data's: a change of
## the durations in the middle of a trip changes neither the trip nor what a skin is told of it.
func test_the_view_of_a_trip_keeps_the_trips_own_numbers_when_the_data_changes() -> void:
	var dock := StationSequence.dock()
	var balloon := StationSequence.balloon()
	while dock.elapsed < dock.opening_ticks + dock.drive_ticks():         # (the door starts to close: picture 4)
		dock.advance()
	balloon.advance()
	balloon.advance()
	_mount({"station": {"dock": {"opening_ticks": 9, "from_x": 0}, "balloon": {"x": 7, "from_y": 999, "pixels_per_tick": 2}}})
	for trip: StationSequence in [dock, balloon]:
		var view := SimView.SequenceState.of(trip)
		var different: Array[String] = []
		for property in trip.get_script().get_script_property_list():
			if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and view._schedule.get(property["name"]) != trip.get(property["name"]):
				different.append("%s: %s, the trip has %s" % [property["name"], view._schedule.get(property["name"]), trip.get(property["name"])])
		assert_array(different).override_failure_message("the view of %s:\n%s" % [StationSequence.Kind.keys()[trip.kind], "\n".join(different)]) \
				.is_empty()
	assert_int(SimView.SequenceState.of(dock).door_picture()).is_equal(4)
	assert_vector(SimView.SequenceState.of(balloon).balloon_position(1.0)) \
			.is_equal(Vector2(balloon.balloon_x, balloon.balloon_y()) - SubModel.PLAYFIELD_ORIGIN)


func test_a_longer_dissolve_is_counted_out_by_the_rules() -> void:
	_mount()
	var sim := SimWorld.new(GameState)
	sim.load_sector(0, 0)
	var told: Array[int] = []
	sim.dissolve_started.connect(func(ticks: int) -> void: told.append(ticks))
	sim.begin_dissolve()
	assert_array(told).is_equal([30])                                         # (the base file's 21 is passed over)
	sim.advance_dissolve(29)
	assert_bool(sim.is_dissolving()).is_true()
	sim.advance_dissolve(1)
	assert_bool(sim.is_dissolving()).is_false()


func test_a_longer_message_holds_the_problem_machine_for_longer() -> void:
	_mount({"problem": {"message_ticks": 200}})
	var flow := ProblemFlow.new()
	var problem := ProblemFactory.make(6, 2, null, 0)
	flow.begin(problem)
	flow.submit_answer(problem.expected)
	assert_int(flow.step).is_equal(ProblemFlow.Step.MESSAGE)
	flow.advance_ticks(199)
	assert_int(flow.step).is_equal(ProblemFlow.Step.MESSAGE)                # (the base file's shorter message would be over)
	flow.advance_ticks(1)
	assert_int(flow.step).is_equal(ProblemFlow.Step.OVER)


func test_the_log_scan_and_the_fade_follow_the_data() -> void:
	_mount({"log_scan": {"ticks_per_picture": 2, "sweeps": 3}, "fade": {"ticks": 20}})
	assert_int(CanisterLog.scan_ticks()).is_equal(2 * 8 * 3)
	assert_int(CanisterLog.scan_picture(3)).is_equal(1)
	assert_int(CanisterLog.scan_picture(47)).is_equal(7)
	assert_int(CanisterLog.scan_picture(48)).is_equal(CanisterLog.SCAN_RESTING_PICTURE)
	assert_int(SceneRouter.fade_ticks()).is_equal(20)


func test_a_missing_key_is_reported_and_reads_as_zero() -> void:
	assert_int(Durations.at("station.dock.no_such_key")).is_equal(0)         # (and `push_error`, which gdUnit would only list)
	assert_array(Durations.list_at("news.no_such_list")).is_empty()


# --- skins and presenters ---------------------------------------------------------------------------------

## The trace of a scripted visit of sector 0 (`SectorScenario`) in plain objects, or in a `SectorWorld` wearing `skin`.
func _play(skin: GameSkin = null) -> SectorScenario:
	GameState.reset()
	if skin == null:
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.reset()
		var scenario := SectorScenario.new(HeadlessStage.new(run), run)
		scenario.play(0)
		return scenario
	SkinChoice.select(skin)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var fraction := [0.0]
	world.sim.ticked.connect(func() -> void:
		fraction[0] = fmod(fraction[0] + 0.37, 1.0)
		world.presenter.show_between_ticks(fraction[0]))
	var scenario := SectorScenario.new(world, GameState)
	scenario.play(0)
	SkinChoice.select(SkinChoice.original())
	return scenario


func test_every_skin_plays_the_longer_game_as_the_plain_objects_do() -> void:
	var launch_ticks := StationSequence.launch().ticks
	_mount()
	var plain := _play()
	var timings := plain.trace.lines.filter(func(line: String) -> bool: return line.contains(" took ") or line.begins_with("-- dissolve"))
	# the visit's own steps took the new numbers (launch unchanged, dock 37, balloon 16, dissolve 30) ...
	for expected in ["-- launch took %d ticks" % launch_ticks, "-- dock took 37 ticks", "-- balloon took 16 ticks", "-- dissolve of 30 ticks"]:
		assert_bool(timings.has(expected)).override_failure_message("no '%s' in %s" % [expected, timings]).is_true()
	# ... and so did every skin's
	for skin in SkinRoster.all():
		var lines := _play(skin).trace.lines
		assert_int(lines.size()).override_failure_message("skin %s: another number of lines" % skin.id).is_equal(plain.trace.lines.size())
		for i in mini(lines.size(), plain.trace.lines.size()):
			if lines[i] != plain.trace.lines[i]:
				fail("skin %s: the rules differ at line %d\n  plain: %s\n  skin:  %s" % [skin.id, i, plain.trace.lines[i], lines[i]])
				break




func test_the_pack_plays_its_own_visit_with_its_own_numbers() -> void:
	# (the same sentence as `test_plays_identically.gd`, in this file so that a change to a durations file shows up here first)
	var timings := _play().trace.lines.filter(func(line: String) -> bool: return line.contains(" took ") or line.begins_with("-- dissolve"))
	var expected := ["-- launch took %d ticks" % StationSequence.launch().ticks, "-- dock took %d ticks" % StationSequence.dock().ticks,
			"-- balloon took %d ticks" % StationSequence.balloon().ticks, "-- dissolve of %d ticks" % SimWorld.dissolve_length()]
	for line in expected:
		assert_bool(timings.has(line)).override_failure_message("no '%s' in %s" % [line, timings]).is_true()
	assert_array([StationSequence.launch().ticks, StationSequence.dock().ticks, StationSequence.balloon().ticks]).is_not_equal([30, 31, 44])
