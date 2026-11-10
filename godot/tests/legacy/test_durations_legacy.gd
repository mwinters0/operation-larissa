class_name TestDurationsLegacy
extends GdUnitTestSuite
## Teaches: the base game's durations are the original's numbers (the project's `data/rules/durations.json`), and with them the rules play the original's visit
## of sector 0 (launch 30 ticks, dock 31, balloon 44, dissolve 21). The mechanism, on dev's numbers: tests/engine/test_durations.gd.

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const PACK_FILE := "user://test_durations_pack.json"
## Every key of the base file and its original number. The file may hold no other number (`test_the_base_file_holds_nothing_else`).
const ORIGINAL := {
	"station.launch.opening_ticks": 3, "station.launch.closing_ticks": 3, "station.launch.from_x": 0, "station.launch.to_x": 96,
	"station.launch.pixels_per_tick": 4,
	"station.dock.opening_ticks": 3, "station.dock.closing_ticks": 3, "station.dock.from_x": 352, "station.dock.to_x": 452,
	"station.dock.pixels_per_tick": 4,
	"station.balloon.x": 560, "station.balloon.from_y": 144, "station.balloon.to_y": -32, "station.balloon.pixels_per_tick": 4,
	"dissolve.ticks": 21,
	"log_scan.ticks_per_picture": 5, "log_scan.sweeps": 6,
	"sign_in.pre_scan_ticks": 18, "sign_in.pressed_ticks": 36, "sign_in.scan_ticks_per_picture": 5, "sign_in.scan_sweeps": 6,
	"problem.message_ticks": 146,
	"speech.silent_ticks": 146,
	"calculator.key_flash_ticks": 12,
	"surface_ship.wait_ticks": 1460,
	"news.speech_start_delay_ticks": 219,
	"fade.ticks": 13,
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


func test_the_base_file_has_the_originals_numbers() -> void:
	for path: String in ORIGINAL:
		assert_int(Durations.at(path)).override_failure_message(path).is_equal(ORIGINAL[path])
	assert_array(Durations.list_at("news.group_pauses")).is_equal([0, 248, 248, 248, 0])


func test_the_base_file_holds_nothing_else() -> void:
	var found: Array[String] = []
	_leaves(JSON.parse_string(FileAccess.get_file_as_string(Durations.BASE_PATH)), "", found)
	for path in found:
		assert_bool(ORIGINAL.has(path) or path == "news.group_pauses").override_failure_message("'%s' is in the file but not in this test" % path).is_true()
	assert_int(found.size()).is_equal(ORIGINAL.size() + 1)


func _leaves(node: Variant, path: String, into: Array[String]) -> void:
	if node is Dictionary:
		for key: String in node:
			if not key.begins_with("_"):                                   # ("_about" is the file's note to its reader)
				_leaves(node[key], path + ("." if not path.is_empty() else "") + key, into)
	else:
		into.append(path)


func test_the_rules_give_the_originals_timing_with_the_default_data() -> void:
	assert_array([StationSequence.launch().ticks, StationSequence.dock().ticks, StationSequence.balloon().ticks]).is_equal([30, 31, 44])
	assert_int(SimWorld.dissolve_length()).is_equal(21)
	assert_int(SimWorld.launched_x()).is_equal(96)
	assert_int(CanisterLog.scan_ticks()).is_equal(240)
	assert_int(ProblemFlow.message_ticks()).is_equal(146)
	assert_int(Audio.silent_speech_ticks()).is_equal(146)
	assert_int(SceneRouter.fade_ticks()).is_equal(13)
	assert_int(SurfaceShipScreen.wait_ticks()).is_equal(1460)
	assert_int(CalculatorModel.key_flash_ticks()).is_equal(12)
	assert_int(NewsCartoon.speech_start_delay_ticks()).is_equal(219)
	assert_array(NewsCartoon.speech_groups()).is_equal([[0, 2], [248, 3], [248, 1], [248, 1], [0, 4]])
	assert_array([SignIn.pre_scan_ticks(), SignIn.pressed_ticks()]).is_equal([18, 36])


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


func test_the_default_data_plays_the_original_visit() -> void:
	# (the same sentence as `test_plays_identically.gd`, in this file so that a change to the base file shows up here first)
	var timings := _play().trace.lines.filter(func(line: String) -> bool: return line.contains(" took ") or line.begins_with("-- dissolve"))
	for expected in ["-- launch took 30 ticks", "-- dock took 31 ticks", "-- balloon took 44 ticks", "-- dissolve of 21 ticks"]:
		assert_bool(timings.has(expected)).override_failure_message("no '%s' in %s" % [expected, timings]).is_true()
