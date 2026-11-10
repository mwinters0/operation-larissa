class_name TestHeadlessSectors
extends GdUnitTestSuite
## Teaches: the point of the rules/presentation split, as a test. Whole sectors are PLAYED with the rules alone: a `SimWorld` and a `GameFlow` (with a fake
## view and a fake save store), no presenter, no scene, no node. The sub is launched from the station, swims, fires ink, touches a
## trigger and answers the problem, loses a tank to a creature and dissolves, docks, sends up the balloon, plays the next sector, and
## in the finale sectors the closing starts; and the engine counts the nodes before and after: the rules made none.
##
## Two ways to play. `SectorScenario` is a scripted visit that talks to a stage directly (the rules of a sector, at the level of
## ticks). `GameFlow` is the mission around it (the dock, the lock, the supply message, the next sector, the lost tank, the finale),
## which asks its view to show screens; the fake view answers at once.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
## Sectors of the bare scenario: the tour's (other zones and creatures, and its finale that ends by docking) and the two test sectors whose treasure starts the closing.
const SECTORS := [0, 1, 2, 3, 4, 160, 161]
const TREASURE_SECTOR := 160

var _log: Array = []
var _later: Array[Callable] = []


func before_test() -> void:
	_log = []
	_later = []


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _new_run() -> Node:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node          # the script of the autoload, not in any tree
	run.reset()
	return run


# --- a scripted visit to many sectors -----------------------------------------------------------------

func test_whole_sectors_are_played_with_no_presenter_and_no_node() -> void:
	var run := _new_run()                                                  # (the one node: the player's numbers)
	var nodes_before := _node_count()
	for sector in SECTORS:
		run.reset()
		var scenario := SectorScenario.new(HeadlessStage.new(run), run)
		scenario.play(sector)
		var trace := scenario.trace
		# the launch, and one more for every respawn before the midpoint (the flow begins the sector again on the station)
		var launches := trace.events_like("trip_finished 0").size()
		assert_int(launches).override_failure_message("sector %d: the launch" % sector).is_greater_equal(1)
		assert_int(trace.events_like("trip_started 0 ticks=28").size()).is_equal(launches)
		if SimWorld.finale_screen(sector) >= 0:
			assert_array(trace.events_like("finale")).override_failure_message("sector %d: the closing never started" % sector).has_size(1)
			continue
		assert_array(trace.events_like("requested")).override_failure_message("sector %d: no problem" % sector).is_not_empty()
		assert_array(trace.events_like("problem_finished")).is_not_empty()
		# the canister's problem cost the tank: the canister is to be taken again, and the flow respawned the sub
		assert_array(trace.events_like("problem_finished 1 solved=false")).override_failure_message("sector %d: the canister" % sector).has_size(1)
		assert_array(trace.events_like("pieces_reset")).has_size(1)
		assert_int(trace.events_like("sector_loaded %d" % sector).size()).override_failure_message("sector %d: no respawn" % sector).is_greater_equal(3)
		assert_array(trace.events_like("dissolve_finished")).override_failure_message("sector %d: no tank lost" % sector).is_not_empty()
		assert_array(trace.events_like("dissolve_started %d" % SimWorld.dissolve_length())).is_not_empty()
		assert_array(trace.events_like("dock")).override_failure_message("sector %d: not docked" % sector).has_size(1)
		assert_array(trace.events_like("trip_finished 1")).has_size(1)                      # the dock trip
		assert_array(trace.events_like("trip_finished 2")).has_size(1)                      # the balloon
	assert_int(_node_count()).override_failure_message("the rules made nodes").is_equal(nodes_before)


func test_a_scripted_visit_is_the_same_every_time() -> void:
	var traces: Array = []
	for round in 2:
		var run := _new_run()
		var scenario := SectorScenario.new(HeadlessStage.new(run), run)
		scenario.play(2)
		traces.append(scenario.trace.lines)
	assert_array(traces[1]).is_equal(traces[0])
	assert_int((traces[0] as Array).size()).is_greater(300)


# --- a mission with the flow ----------------------------------------------------------------------------

## The rig of a mission: a run that is in no tree, a profile, a clock that is a plain object, the fake store and view, and a flow
## whose "a little later" is collected in `_later`.
class Mission:
	extends RefCounted
	var run: Object
	var player: PlayerProfile
	var store := FakeSaveStore.new()
	var clock := StubClock.new()
	var messages: MessageQueue
	var stage: HeadlessStage
	var view: FakeFlowView
	var flow: GameFlow
	var log: Array
	var later: Array[Callable] = []

	func _init(game_run: Object, mission_log: Array, sector: int) -> void:
		run = game_run
		log = mission_log
		player = PlayerProfile.new_player("Headless", PlayerProfile.Game.VOYAGER)
		player.hints_enabled = false
		player.progress = sector * 2
		run.profile = player
		store.watched = player
		messages = MessageQueue.new(clock)
		stage = HeadlessStage.new(run)
		stage.log = log
		view = FakeFlowView.new(log, run)
		flow = GameFlow.new(run, store, messages)
		flow.world = stage
		flow.view = view
		flow.defer_call = func(action: Callable) -> void: later.append(action)

	## Runs what the flow put off, the way the idle frame does in the game.
	func run_deferred() -> void:
		var batch := later.duplicate()
		later.clear()
		for action: Callable in batch:
			action.call()


func test_a_mission_plays_sectors_with_the_flow_and_makes_no_node() -> void:
	var run := _new_run()
	var mission := Mission.new(run, _log, 0)
	var nodes_before := _node_count()                                      # (after the player's numbers exist)
	mission.flow.enter(0, 1)
	await mission.flow.begin_mission()
	var sector_hands := SimTrace.Hands.new(0, 0)
	for sector in 3:                                                       # sectors 0, 1 and 2 from the launch to the next launch
		assert_int(mission.stage.sector_index).is_equal(sector)
		# a flight with creatures awake, a tank lost to one (the flow respawns the sub), a problem from a trigger
		mission.stage.sim.foe_rng.seed = 7                                  # (the same dice in every sector)
		for t in 60:
			mission.stage.tick(sector_hands.at(t))
		var foe: FoeModel = mission.stage.sim.foes.filter(func(f: FoeModel) -> bool: return f.vm.damage > 0 and not f.vm.hidden and not f.vm.interrupted)[0]
		mission.stage.sim.load_screen(foe.vm.screen)
		mission.stage.sim.start_flight()                                   # (not invulnerable from an earlier hit)
		run.oxygen_model.oxygen = foe.vm.damage
		mission.stage.sim.sub_touches(foe)
		mission.stage.finish_dissolve()                                    # the sub dissolves; then the run announces the lost tank
		assert_array(mission.later).has_size(1)                            # (the flow puts the respawn off)
		mission.run_deferred()
		assert_bool(mission.stage.sim.sub.controlled).is_true()            # respawned and launched again
		var trigger: TriggerModel = mission.stage.sim.triggers.filter(func(t: TriggerModel) -> bool: return t.data.slot != SimWorld.CANISTER_SLOT)[0]
		mission.stage.sim.load_screen(trigger.screen)
		mission.stage.sim.start_flight(trigger.data.pos.x - 40, trigger.data.pos.y - 25, 6)
		var ticks := 0
		while not _log.any(func(line: Variant) -> bool: return str(line).begins_with("problem ")) and ticks < 100:
			mission.stage.tick()
			ticks += 1
		assert_int(ticks).is_less(100)                                     # the countdown ran, the flow asked its view for the problem
		# the whole sector is collected, the sub reaches the dock; the flow does the lock, the supply message, the balloon, the next sector
		for i in mission.stage.sector.pieces.size():
			run.collect_piece(i)
		mission.stage.sim.load_screen(SimWorld.DOCK_SCREEN)
		mission.stage.sim.start_flight(400, 200, 6)
		mission.stage.tick()
		assert_int(mission.player.sector()).override_failure_message("sector %d was not finished" % sector).is_equal(sector + 1)
	assert_int(mission.stage.sector_index).is_equal(3)
	assert_bool(mission.stage.sim.sub.controlled).is_true()
	assert_int(_node_count()).override_failure_message("the rules made nodes").is_equal(nodes_before)
	mission.flow.leave()


func test_the_finale_starts_the_closing_and_ends_in_the_hall_of_fame_with_no_node() -> void:
	var run := _new_run()
	var mission := Mission.new(run, _log, TREASURE_SECTOR)
	var nodes_before := _node_count()
	mission.flow.enter(0, 1)
	await mission.flow.begin_mission()
	mission.stage.sim.foe_rng.seed = 7
	for t in 60:                                                           # (the creatures' scripts get going)
		mission.stage.tick()
		mission.stage.finish_dissolve()                                    # (a creature may take a tank: dissolve, then the flow respawns)
		mission.run_deferred()
	var treasure := mission.stage.sim.foes[0]
	mission.stage.sim.load_screen(treasure.vm.screen)
	mission.stage.sim.sub.invulnerability = 100                            # (no creature takes the tank while the treasure is touched)
	mission.stage.sim.sub_touches(treasure)
	for t in 4:
		mission.stage.tick()
	mission.stage.sim.load_screen(SimWorld.finale_screen(TREASURE_SECTOR))
	mission.stage.tick()                                                   # the sim says `finale_reached`; the flow asks its view for the closing
	assert_bool(_log.any(func(line: Variant) -> bool: return str(line).begins_with("closing "))).is_true()
	assert_array(_log.slice(-2)).is_equal(["hall of fame", "sign in"])
	assert_array(mission.store.hall).is_equal([mission.player])
	assert_int(_node_count()).is_equal(nodes_before)
	mission.flow.leave()
