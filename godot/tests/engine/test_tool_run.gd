class_name TestToolRun
extends GdUnitTestSuite
## Teaches: testing WHEN something happens, not only what. `ToolRun` answers a lost tank the way `GameFlow` does, a little later and
## outside the signal (`defer_call`); the test collects the deferred calls itself, so it can look at the state in between: inside the
## signal nothing has moved, and the rules still finish the problem that cost the tank on the sector it belongs to.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _deferred: Array[Callable] = []


func before_test() -> void:
	_deferred.clear()
	GameClock.paused = true
	SectorWorld.skip_animations = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SectorWorld.skip_animations = false
	GameState.reset()


func _run() -> ToolRun:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var run := ToolRun.new(world, world)
	run.defer_call = func(action: Callable) -> void: _deferred.append(action)
	run.begin_sector(Ground.MAIN)
	world.start_flight()
	return run


func _run_deferred() -> void:
	var calls := _deferred.duplicate()
	_deferred.clear()
	for action: Callable in calls:
		await action.call()


func test_a_sector_starts_with_nothing_collected_and_the_midpoint_forgotten() -> void:
	var run := _run()
	GameState.collect_piece(0)
	GameState.past_midpoint = true
	run.begin_sector(Ground.MAIN, 3)
	assert_int(GameState.pieces_mask).is_equal(0)
	assert_bool(GameState.past_midpoint).is_false()
	assert_int(run.world.screen_index).is_equal(3)


func test_a_lost_tank_is_answered_later_with_the_respawn() -> void:
	var run := _run()
	run.world.load_screen(4)
	GameState.oxygen_model.oxygen = 1
	GameState.update_oxygen(-1)
	assert_int(_deferred.size()).is_equal(1)                       # inside the signal: nothing yet
	assert_int(run.world.screen_index).is_equal(4)
	await _run_deferred()
	assert_int(run.world.screen_index).is_equal(0)                 # the sector starts again (before the midpoint)
	assert_int(GameState.oxygen()).is_equal(Tuning.resolve().max_oxygen)


func test_a_game_over_is_answered_later_and_the_sector_starts_over() -> void:
	var run := _run()
	GameState.collect_piece(2)
	GameState.oxygen_model.tanks = 0
	GameState.oxygen_model.oxygen = 1
	GameState.update_oxygen(-1)
	assert_int(_deferred.size()).is_equal(1)
	assert_bool(GameState.has_piece(2)).is_true()
	await _run_deferred()
	assert_bool(GameState.has_piece(2)).is_false()
	assert_int(run.world.screen_index).is_equal(0)


## The canister's problem cost the tank: the loss is announced while the problem screen closes, then the rules hear how it went
## (`problem_resolved` takes the canister back and ends the tick), and only then does the sub respawn.
func test_the_problem_that_cost_the_tank_is_finished_before_the_respawn() -> void:
	var run := _run()
	var sim := run.world.sim
	GameState.collect_piece(0)
	GameState.collect_piece(1)
	sim.problem_active = true
	GameState.oxygen_model.oxygen = 1
	GameState.hold_losses()
	var session := ProblemSession.new(null)
	session.oxygen_code = GameState.update_oxygen(-1)
	GameState.release_losses()
	assert_int(_deferred.size()).is_equal(1)
	sim.problem_resolved(SimWorld.CANISTER_SLOT, session)
	assert_bool(GameState.has_piece(0)).is_false()                 # the canister must be collected again
	await _run_deferred()
	assert_bool(GameState.has_piece(0)).is_false()
	assert_bool(GameState.has_piece(1)).is_true()                  # (a respawn keeps the other pieces)
	assert_bool(sim.problem_active).is_false()
