class_name TestTickOrder
extends GdUnitTestSuite
## Teaches: pinning the ORDER of a game loop. The rules of the playfield run in `SimWorld.tick`, in the order of the
## original's `DoAction` (0x417ffc) (the fire presses of the snapshot come first, see `SimWorld.TICK_ORDER`): a waiting problem opens, the dock test, the pieces (`CheckProbeCollision` 0x42dbb2, with the
## sub where the last tick left it), the sub, the finale test, the math triggers (`DetectMathTrigger` 0x427744, with the sub where
## it is now), the creatures and their contacts, the pellets, all in one tick: not on every 60 Hz physics frame, and not from
## separate `GameClock` connections.
##
## The ground sector (`Ground.MAIN`): screen 9 holds piece 6 (a rock) at window (400, 150); screen 5 holds a trigger at window (400, 240), slot 10; screen 7 a trigger
## that tests the sub's x (table entry 4) at (300, 200), slot 12; screen 4 a creature.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const TRIGGER_POS := Vector2i(400, 240)
const TRIGGER_SLOT := 10

var _world: SectorWorld
var _taken: Array[int]
var _requested: Array[Vector2i]            # the sub's SubX / SubY at the moment a problem was asked for


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.foes_active = false
	_world.problem_requested.connect(func(_slot: int) -> void: _requested.append(_world.sim.sub.original_position()))
	_requested = []


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func _start(screen: int) -> void:
	_world.load_sector(Ground.MAIN, screen)
	_world.tile_grid.clear()                # open water: nothing stops the sub or sets a current
	_world.start_flight()


func test_one_tick_runs_the_steps_in_the_order_of_the_original() -> void:
	_start(9)
	_world.sim.trace_ticks = true
	_world.tick()
	assert_array(_world.sim.tick_trace).is_equal(SimWorld.TICK_ORDER)
	assert_array(SimWorld.TICK_ORDER).is_equal([
		&"fire", &"pending_problem", &"dock", &"pieces", &"sub", &"finale", &"triggers", &"creatures", &"contacts", &"pellets"])
	_world.tick()
	assert_array(_world.sim.tick_trace).is_equal(SimWorld.TICK_ORDER)      # (cleared at the start of each tick, not appended to)


func test_the_clock_runs_the_rules_through_the_one_connection_of_the_world() -> void:
	_start(9)
	_world.sim.trace_ticks = true
	GameClock.step()
	assert_array(_world.sim.tick_trace).is_equal(SimWorld.TICK_ORDER)
	var connected := 0
	for connection in GameClock.tick.get_connections():
		var owner := (connection["callable"] as Callable).get_object()
		if owner == _world.original.sub or owner == _world.sim.sub or owner is InkPellet or owner is PelletModel:
			connected += 1
	assert_int(connected).is_equal(0)                                     # neither the sub nor a pellet listens to the clock itself


func test_a_piece_is_not_taken_between_ticks() -> void:
	_start(9)
	var piece := _world.sector.pieces[6]
	_world.original.sub.place_original(piece.pos.x - 40, piece.pos.y - 25, 6)     # the picture box covers the piece
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_bool(GameState.has_piece(6)).is_false()                        # (a 60 Hz check would have taken it by now)
	_world.tick()
	assert_bool(GameState.has_piece(6)).is_true()


func test_the_pieces_are_looked_at_before_the_sub_moves() -> void:
	# `CheckProbeCollision` comes before the sub's move in `DoAction`: a sub that drifts INTO the box of a piece takes it one
	# tick later (the check sees where the last tick left it); one that drifts OUT of the box still takes it.
	_start(9)
	var piece := _world.sector.pieces[6]
	_world.original.sub.place_original(piece.pos.x - 96, piece.pos.y - 20, 6)    # one pixel short of touching
	assert_bool(PieceModel.touched_by(_world.sim.sub.original_position(), piece.pos)).is_false()
	_world.sim.sub.velocity_units = Vector2i(48, 0)                          # 6 px right in this tick
	_world.tick()
	assert_bool(PieceModel.touched_by(_world.sim.sub.original_position(), piece.pos)).is_true()
	assert_bool(GameState.has_piece(6)).is_false()                        # it touches now, but the check ran before the move
	_world.tick()
	assert_bool(GameState.has_piece(6)).is_true()


func test_a_piece_the_sub_leaves_behind_in_this_tick_is_still_taken() -> void:
	_start(9)
	var piece := _world.sector.pieces[6]
	_world.original.sub.place_original(piece.pos.x - 95, piece.pos.y - 20, 6)    # touches with the last column of its box
	_world.sim.sub.velocity_units = Vector2i(-48, 0)                         # and leaves to the left in this tick
	_world.tick()
	assert_bool(PieceModel.touched_by(_world.sim.sub.original_position(), piece.pos)).is_false()
	assert_bool(GameState.has_piece(6)).is_true()


## Screen 7 of the ground sector holds a trigger that tests the sub's x (table entry 4, `MathTriggerTable`): the box must reach the trigger's x only by this tick's move.
const X_TRIGGER_SCREEN := 7


func test_the_triggers_are_looked_at_after_the_sub_moved() -> void:
	# `DetectMathTrigger` comes after the sub's move in `DoAction`: a sub that drifts into the trigger's x range fires it IN
	# THE SAME tick (a piece would have to wait for the next one).
	_world.load_sector(Ground.MAIN, X_TRIGGER_SCREEN)
	_world.tile_grid.clear()
	_world.start_flight()
	var trigger := _world.sector.screens[X_TRIGGER_SCREEN].triggers[0]
	assert_int(trigger.test_nibble).is_equal(4)
	var fired: Array[int] = []
	_world.problem_pending.connect(func(slot: int) -> void: fired.append(slot))
	_world.original.sub.place_original(trigger.pos.x - 96, 100, 6)               # its box ends one pixel before the trigger's x
	_world.sim.sub.velocity_units = Vector2i(48, 0)
	_world.tick()
	assert_array(fired).is_equal([trigger.slot])
	assert_bool(_world.is_trigger_armed(X_TRIGGER_SCREEN, 0)).is_false()


func test_a_trigger_is_not_looked_at_between_ticks() -> void:
	_start(5)
	_world.sim.sub.position = Vector2(TRIGGER_POS) - Sub.PLAYFIELD_ORIGIN
	var fired: Array[int] = []
	_world.problem_pending.connect(func(slot: int) -> void: fired.append(slot))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_array(fired).is_empty()
	_world.tick()
	assert_array(fired).is_equal([TRIGGER_SLOT])


func test_a_waiting_problem_opens_before_the_sub_moves() -> void:
	# The loop top of `DoAction` opens the problem (countdown 1) before anything of the tick has happened: the sub is where
	# the previous tick left it. (The rest of that tick waits for the problem, see the next test.)
	_start(5)
	_world.original.sub.place_original(300, 200, 6)
	_world.sim.take_piece(0)                                          # the canister
	_world.sim.pending_ticks = 2                                      # (the problem opens next tick, whatever the run's countdown)
	_world.sim.sub.velocity_units = Vector2i(48, 0)
	var before := _world.sim.sub.original_position()
	_world.tick()
	assert_array(_requested).is_equal([before])
	assert_that(_world.sim.sub.original_position()).is_equal(before)


func test_the_rest_of_the_tick_runs_when_the_problem_is_resolved() -> void:
	# In the original `DoAction` is inside `DoMathProblem` until the problem is over and then goes on with the pass. The problem
	# screen of the port outlives the call, so the steps after the loop top wait: nothing moves or touches the sub beside the
	# problem, `ticked` is not said yet, and `problem_resolved` runs them (after `problem_finished`, as the owner has the outcome first).
	_start(5)
	_world.original.sub.place_original(300, 200, 6)
	_world.sim.take_piece(0)
	_world.sim.pending_ticks = 2                                      # (the problem opens next tick, whatever the run's countdown)
	_world.sim.sub.velocity_units = Vector2i(48, 0)
	var before := _world.sim.sub.original_position()
	_world.sim.trace_ticks = true
	var seen: Array[String] = []
	_world.sim.ticked.connect(func() -> void: seen.append("ticked"))
	_world.sim.problem_finished.connect(func(_slot: int, _session: ProblemSession) -> void: seen.append("finished"))
	_world.tick()
	assert_array(_world.sim.tick_trace).is_equal([&"fire", &"pending_problem"])
	assert_array(seen).is_empty()
	assert_that(_world.sim.sub.original_position()).is_equal(before)
	_world.sim.problem_resolved(SimWorld.CANISTER_SLOT, ProblemSession.new(_world.make_problem(SimWorld.CANISTER_SLOT)))
	assert_array(_world.sim.tick_trace).is_equal(SimWorld.TICK_ORDER)
	assert_array(seen).is_equal(["finished", "ticked"])               # ticked once, after the last step
	assert_int(_world.sim.sub.original_position().x).is_greater(before.x)


func test_the_rest_of_the_tick_steers_by_the_keys_held_when_the_problem_closes() -> void:
	# `DoAction` reads the keys after `DoMathProblem` returns: a key let go during the problem does not move the sub.
	_start(5)
	_world.original.sub.place_original(300, 200, 6)
	_world.sim.take_piece(0)
	_world.sim.pending_ticks = 2                                      # (the problem opens next tick, whatever the run's countdown)
	_world.sim.steer_source = func() -> Vector2i: return Vector2i.ZERO         # (nothing is held now)
	_world.sim.sub.velocity_units = Vector2i.ZERO
	_world.tick(InputSnapshot.steering(1))                                     # (right was held when the tick began)
	var before := _world.sim.sub.original_position()
	_world.sim.problem_resolved(SimWorld.CANISTER_SLOT, ProblemSession.new(_world.make_problem(SimWorld.CANISTER_SLOT)))
	assert_int(_world.sim.sub.velocity_units.x).is_less_equal(0)
	assert_that(_world.sim.sub.original_position()).is_equal(before)


func test_a_sector_change_drops_the_rest_of_a_tick_that_waited() -> void:
	_start(5)
	_world.sim.take_piece(0)
	_world.sim.pending_ticks = 2                                      # (the problem opens next tick, whatever the run's countdown)
	_world.tick()
	var ticked: Array[bool] = []
	_world.sim.ticked.connect(func() -> void: ticked.append(true))
	_world.load_sector(0, 5)                                                   # a game over, a respawn, another sector
	_world.sim.problem_resolved(SimWorld.CANISTER_SLOT, ProblemSession.new(_world.make_problem(SimWorld.CANISTER_SLOT)))
	assert_array(ticked).is_empty()


func test_a_problem_the_owner_settles_inside_the_request_does_not_hold_the_tick_up() -> void:
	# (a plain owner, as in the headless runs: it answers at once, so nothing covers the playfield and the tick goes on)
	_start(5)
	_world.original.sub.place_original(300, 200, 6)
	_world.sim.take_piece(0)
	_world.sim.pending_ticks = 2                                      # (the problem opens next tick, whatever the run's countdown)
	_world.sim.sub.velocity_units = Vector2i(48, 0)
	var before := _world.sim.sub.original_position()
	_world.sim.problem_requested.connect(func(slot: int) -> void: _world.sim.problem_resolved(slot, ProblemSession.new(_world.make_problem(SimWorld.CANISTER_SLOT))))
	_world.tick()
	assert_int(_world.sim.sub.original_position().x).is_greater(before.x)


func test_a_trigger_that_fires_in_the_tick_of_a_pick_up_still_wins() -> void:
	# Pieces, then the sub, then the triggers: the trigger overwrites the canister's countdown in the same tick, so the
	# canister is gone for good and asks for nothing (also pinned in test_collectibles.gd with a trigger on the canister).
	_start(5)
	_world.sim.sub.position = Vector2(TRIGGER_POS) - Sub.PLAYFIELD_ORIGIN
	var data := _world.sector.pieces[0].duplicate() as PieceData
	data.pos = TRIGGER_POS
	_world.sim.pieces.append(PieceModel.new(data, 0))
	_world.tick()
	assert_bool(GameState.has_piece(0)).is_true()
	assert_int(_world.pending_slot).is_equal(TRIGGER_SLOT)
	assert_int(_world.pending_ticks).is_equal(Tuning.resolve().pending_ticks)


func test_the_pellets_move_after_the_contacts_look_at_them() -> void:
	# `update_animals` tests the pellets before `UpdateStunGun` moves them: a creature is hit when a pellet is on it at the END of
	# a tick, not on the way. A pellet that flies 24 px per tick and starts 16 px left of a creature (boxes not touching) is
	# on top of it after the first tick and hits it in the second.
	_world.foes_active = false
	_start(4)                                                              # (screen 4 holds creature 0)
	var foe := _world.original.foes[0]
	var pellet := PelletModel.new()
	var rect := foe.model.hit_rect_window()
	var top_left := Vector2(rect.position) - Sub.PLAYFIELD_ORIGIN + Vector2(-20, 0)     # its box ends 5 px before the creature's
	pellet.launch(top_left, 6, _world.sim.sub.tuning, _world.tile_grid)
	_world.sim.pellets.append(pellet)
	_world.stop_flight()                                                  # (a sub that touches nothing: the pellet test is the ELSE branch)
	foe.refresh(true)
	assert_bool(FoeModel.rects_touch(pellet.window_rect(), rect)).is_false()
	_world.tick()
	assert_bool(foe.vm.interrupted).is_false()                            # the pellet was not on the creature when the contacts looked
	assert_bool(FoeModel.rects_touch(pellet.window_rect(), rect)).is_true()    # ... it is, now that it has moved
	_world.tick()
	assert_bool(foe.vm.interrupted).is_true()
