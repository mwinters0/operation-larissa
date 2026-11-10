class_name TestOwnerBetweenTicks
extends GdUnitTestSuite
## Nothing the owner of the rules does runs inside a tick (docs/engine/ARCHITECTURE.md, "Nothing the owner does runs inside a tick").
## `SimWorld.tick` runs its steps on the state the tick began with; whoever runs it (`SectorWorld`, a test stage) and the flow behind it
## (`GameFlow`) go on only between two ticks: the end of a trip comes as `SimWorld.sequence_over` and the dock reaches the flow through
## `SimWorld.after_tick`, both said when the tick is over. So a load (a sector start, a respawn, the next sector), the reload of the
## creatures and a station trip always begin between ticks.
##
## Teaches: testing a property of a whole design instead of one call. Two checks that do not depend on which call broke it:
##   * every load and every trip of whole visits and missions (a stage of plain objects, the `SectorWorld` scene, a flow whose view
##     answers at once) is watched, and one that begins while the rules' steps run fails with the step it came in;
##   * the source is read: whoever `await`s a signal of the rules or of the playfield must await one that is said between ticks.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
## The scripted visits: launch, flight, problems, a lost tank and its respawn, the dock, the balloon; the closing in a finale.
const SECTORS := [DevCreatures.ARENA, 3, DevCreatures.CLOSING]
## The signals of the rules that are said between two ticks, and so may be awaited. (The playfield's `dock_reached` is said between ticks
## too, but the rules' signal of the same name is not, and the scan reads names only: nobody awaits either.)
const SAID_BETWEEN_TICKS: Array[StringName] = [&"sequence_over"]
## Where code that awaits the rules lives: the game and the stages of the tests.
const SCANNED_DIRS := ["res://src", "res://addons/screen_editor", "res://addons/sector_editor"]
const SCANNED_FILES := ["res://tests/headless_stage.gd", "res://tests/sector_scenario.gd"]


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false              # (the trips are the point)
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


## Writes into `into` every load or trip of `sim` that begins while the steps of a tick run.
func _watch(sim: SimWorld, into: Array[String]) -> void:
	sim.trace_ticks = true
	var step := func() -> String: return String(sim.tick_trace.back()) if not sim.tick_trace.is_empty() else "?"
	sim.sector_loaded.connect(func(index: int) -> void:
		if sim.is_ticking():
			into.append("sector %d loaded in step '%s' of tick %d" % [index, step.call(), sim.tick_number]))
	sim.sequence_started.connect(func(trip: StationSequence) -> void:
		if sim.is_ticking():
			into.append("trip %d began in step '%s' of tick %d" % [trip.kind, step.call(), sim.tick_number]))


func test_no_load_or_trip_of_a_visit_begins_inside_a_tick() -> void:
	for sector in SECTORS:
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.reset()
		var stage := HeadlessStage.new(run)
		var inside: Array[String] = []
		_watch(stage.sim, inside)
		SectorScenario.new(stage, run).play(sector)
		assert_array(inside).override_failure_message("sector %d, plain objects:\n%s" % [sector, "\n".join(inside)]).is_empty()
		GameState.reset()
		var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
		var in_world: Array[String] = []
		_watch(world.sim, in_world)
		SectorScenario.new(world, GameState).play(sector)
		assert_array(in_world).override_failure_message("sector %d, SectorWorld:\n%s" % [sector, "\n".join(in_world)]).is_empty()


## The flow's view answers at once (the lock is opened the moment it is asked for): the harshest case, since nothing but the rules
## then stands between the dock and the next sector. A whole mission: start, dock, lock, reload, dock trip, balloon, next sector.
func test_a_flow_whose_view_answers_at_once_still_goes_on_between_ticks() -> void:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	var player := PlayerProfile.new_player("Tester", PlayerProfile.Game.VOYAGER)
	player.hints_enabled = false
	run.profile = player
	var store := FakeSaveStore.new()
	store.watched = player
	var stage := HeadlessStage.new(run)
	var flow := GameFlow.new(run, store, MessageQueue.new(StubClock.new()))
	flow.world = stage
	flow.view = FakeFlowView.new([], run)
	flow.defer_call = func(action: Callable) -> void: action.call()
	flow.enter(0, 1)
	var inside: Array[String] = []
	_watch(stage.sim, inside)
	await flow.begin_mission()
	for i in stage.sector.pieces.size():
		run.collect_piece(i)
	stage.sim.load_screen(SimWorld.DOCK_SCREEN)
	stage.sim.start_flight(400, 200, 6)
	stage.tick()
	assert_int(stage.sector_index).is_equal(1)
	assert_array(inside).override_failure_message("\n".join(inside)).is_empty()
	flow.leave()


## Every `await` in the game and the stages on a signal of the rules (`SimWorld`, its copies for a skin `SimView`) or of the playfield
## (`SectorWorld`, `HeadlessStage`) waits for one that is said between two ticks. One said inside a tick (`sequence_finished`,
## `problem_requested`, `ticked` ...) would let the waiting code go on in the middle of the tick, on a state that the rest of the tick
## still changes.
func test_whoever_awaits_the_rules_awaits_a_signal_said_between_ticks() -> void:
	var said_inside := {}
	for script: Script in [SimWorld, SimView, SectorWorld, HeadlessStage]:
		for sig: Dictionary in script.get_script_signal_list():
			if not SAID_BETWEEN_TICKS.has(StringName(sig["name"])):
				said_inside[String(sig["name"])] = true
	assert_bool(said_inside.has("sequence_finished")).is_true()
	var paths: Array[String] = []
	for dir: String in SCANNED_DIRS:
		paths.append_array(SourceScan.scripts_under(dir))
	paths.append_array(SCANNED_FILES)
	var awaited := RegEx.create_from_string("\\bawait\\s+(?:[\\w\\.]+\\.)?(\\w+)\\s*(?:$|[^\\w\\s\\(\\.])")
	var found: Array[String] = []
	for path in paths:
		var lines := SourceScan.code_lines_of(path)
		for i in lines.size():
			for match_ in awaited.search_all(lines[i]):
				if said_inside.has(match_.get_string(1)):
					found.append("%s:%d  await %s" % [path, i + 1, match_.get_string(1)])
	assert_array(found).override_failure_message("awaits a signal said inside a tick:\n" + "\n".join(found)).is_empty()
