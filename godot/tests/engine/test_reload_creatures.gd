class_name TestReloadCreatures
extends GdUnitTestSuite
## Teaches: a rebuilt copy of the rules' state is filled from its owner, every field. `SimWorld.reload_creatures` (the open lock at
## the end station: every creature starts over from its start record) refills the `FoeVM.Context` from the sim; the context holds the
## screen that is shown, and the creatures that are on it are the ones drawn. A context that forgot the screen (its default is screen 0)
## made the creatures of screen 0 appear while the sub docked and the balloon rose, on a screen where they are not; one that made new
## dice started the scripts' random numbers over.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
## Where the sub is when the sector ends in play; any screen with no creature of screen 0 will do for the rules.
const SHOWN_SCREEN := DevCreatures.RUNNER_SCREEN


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SectorWorld.skip_animations = false
	GameState.reset()


func _new_sim() -> SimWorld:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node          # the script of the autoload, not in any tree
	run.reset()
	var sim := SimWorld.new(run)
	sim.load_sector(DevCreatures.ARENA, SHOWN_SCREEN)
	return sim


func test_the_reloaded_creatures_know_the_screen_that_is_shown() -> void:
	var sim := _new_sim()
	sim.reload_creatures()
	assert_int(sim.foe_context.current_screen).is_equal(SHOWN_SCREEN)


func test_creatures_of_other_screens_stay_hidden_while_the_trips_tick() -> void:
	var sim := _new_sim()
	sim.reload_creatures()
	for t in 60:
		sim.tick()
		for foe in sim.foes:
			assert_bool(foe.is_shown()).override_failure_message(
					"tick %d: creature %d (screen %d) is shown while screen %d is" % [t, foe.vm.index, foe.vm.screen, SHOWN_SCREEN]
					).is_equal(foe.vm.screen == SHOWN_SCREEN and not foe.vm.hidden)


func test_the_creature_nodes_of_other_screens_stay_invisible_while_the_balloon_rises() -> void:
	var world := scene_runner("res://src/gameplay/sector_world.tscn").scene() as SectorWorld
	world.sim.load_sector(DevCreatures.ARENA, SHOWN_SCREEN)
	world.sim.reload_creatures()
	world.sim.start_balloon()
	for t in 30:
		world.tick()
	for i in world.sim.foes.size():
		if world.sim.foes[i].vm.screen != SHOWN_SCREEN:
			assert_bool(world.original.foes[i].visible).override_failure_message(
					"creature %d (screen %d) is drawn on screen %d" % [i, world.sim.foes[i].vm.screen, SHOWN_SCREEN]).is_false()


## The creature scripts' dice belong to the sim, not to the context a rebuild makes: the original's `rand` state is one global. A seeded
## sim rolls one sequence through the reload after the lock and a respawn (a sector load), as if neither had happened.
func test_the_dice_go_on_through_a_reload_and_a_respawn() -> void:
	var sim := _new_sim()
	var twin := _new_sim()
	sim.foe_rng.seed = 4242
	twin.foe_rng.seed = 4242
	assert_object(sim.foe_context.rng).is_same(sim.foe_rng)
	var rolls := [sim.foe_context.rng.randi(), sim.foe_context.rng.randi()]
	sim.reload_creatures()
	assert_object(sim.foe_context.rng).is_same(sim.foe_rng)
	rolls.append(sim.foe_context.rng.randi())
	sim.begin_sector(DevCreatures.ARENA, false)                           # (the respawn: `GameFlow.respawn` begins the sector again)
	assert_object(sim.foe_context.rng).is_same(sim.foe_rng)
	rolls.append(sim.foe_context.rng.randi())
	var expected := []
	for i in 4:
		expected.append(twin.foe_context.rng.randi())
	assert_array(rolls).is_equal(expected)
