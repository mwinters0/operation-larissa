class_name TestProblemEndsTheTick
extends GdUnitTestSuite
## A math problem that costs a tank ends the game tick in which it opened. `DoAction` (0x417ffc) calls `DoMathProblem` (0x423629)
## at the loop top; when it returns non-zero (1 = a tank lost, 2 = game over) `DoAction` does `PlaySectorMusic(1)` (0x43204d) and
## returns that code at once: nothing else of the tick runs (no `CheckProbeCollision`, no move, no `DetectMathTrigger`, no
## `update_animals`), and `Main` (0x427bb4) respawns the sub. Only a problem that returns 0 lets the rest of the tick go on.
## Port: `SimWorld.problem_resolved` with a session whose `oxygen_code` is not OK abandons the tick that waited for it.
##
## Teaches: a regression test that plays the whole chain - the rules (`SimWorld`), the flow (`GameFlow`), the player's run and the
## save store - with plain objects, and does the problem screen's part by hand in the order the real one does it: the run's losses
## are held while it is open, the flow hears `finished` first, and the loss is announced after (`GameState.release_losses`).
## The dev's ground sector (`Ground.MAIN`): the canister lies on screen 9, screen 5 has a math trigger, the screens are in a row.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"

var _run: Object
var _player: PlayerProfile
var _store: FakeSaveStore
var _stage: HeadlessStage
var _view: FakeFlowView
var _flow: GameFlow
var _log: Array
var _later: Array[Callable]
var _events: Array[String]


func before_test() -> void:
	_log = []
	_later = []
	_events = []
	_run = auto_free(load(GAME_STATE_SCRIPT).new())
	_player = PlayerProfile.new_player("Tester", PlayerProfile.Game.VOYAGER)
	_player.hints_enabled = false
	_player.progress = Ground.MAIN * 2
	_run.profile = _player
	_store = FakeSaveStore.new()
	_store.watched = _player
	_stage = HeadlessStage.new(_run)
	_stage.log = _log
	_stage.sim.ignore_currents = true                              # (the sub stays where the test puts it)
	_view = FakeFlowView.new(_log, _run)
	_flow = GameFlow.new(_run, _store, MessageQueue.new(StubClock.new()))
	_flow.world = _stage
	_flow.view = _view
	_flow.defer_call = func(action: Callable) -> void: _later.append(action)
	SimTrace.listen(_stage.sim, _events)


func after_test() -> void:
	_flow.leave()


func _run_deferred() -> void:
	var batch := _later.duplicate()
	_later.clear()
	for action: Callable in batch:
		action.call()


## The mission starts in the ground sector with one point of air left in a tank and a spare (2 tanks).
func _begin_with_one_point_of_air() -> void:
	_flow.enter(0, 1)
	await _flow.begin_mission()
	_run.update_oxygen(-(Tuning.resolve().max_oxygen - 1))
	assert_int(_run.oxygen()).is_equal(1)
	assert_int(_run.tanks()).is_greater_equal(2)


## Ticks until the flow has put a problem on screen (the problem screen stays up: `hold`); the rest of that tick waits for it.
func _tick_until_the_problem_opens() -> void:
	_view.hold(&"problem")
	for i in Tuning.resolve().pending_ticks + 2:
		_stage.tick()
		if _stage.sim.problem_active:
			return
	fail("no problem opened")


## The player answers wrong and that was the last air: what `ProblemScreen` does, in its order. The run holds the losses while the
## screen is up, the answer costs the point, the flow hears the finished session, and only then is the loss announced.
func _answer_wrong_with_the_last_air() -> int:
	_run.hold_losses()
	var code: int = _run.update_oxygen(-1)
	_view.oxygen_code = code
	_view.release(&"problem")                                     # (`finished`: the flow tells the world how it went)
	_run.release_losses()                                         # (then `tank_lost`, which the flow puts off)
	return code


func test_a_failed_canister_problem_that_costs_the_tank_leaves_the_canister_to_collect_again() -> void:
	await _begin_with_one_point_of_air()
	var sim := _stage.sim
	sim.load_screen(Ground.MAIN_PIECES[0].x)
	sim.start_flight(Ground.MAIN_PIECES[0].y - 40, Ground.MAIN_PIECES[0].z - 20)     # (the sub's picture box covers the canister)
	_stage.tick()                                                  # (`CheckProbeCollision`: the canister is taken, countdown 2)
	assert_bool(_run.has_piece(0)).is_true()
	await _tick_until_the_problem_opens()
	assert_str(_log.back()).starts_with("problem ")
	var code := _answer_wrong_with_the_last_air()
	assert_int(code).is_equal(OxygenModel.OUT_WITH_SPARE_TANKS)
	# `DoMathProblem` cleared bit 0 of `ProbesPickedUp` and `DoAction` returned: the sub, still over the canister, takes nothing.
	assert_bool(_run.has_piece(0)).is_false()
	assert_int(sim.pending_slot).is_equal(-1)
	_run_deferred()                                                # the respawn (`Main`: `UpdateOxygen(4)`, `DoAction` again)
	assert_bool(_run.has_piece(0)).is_false()
	assert_int(_store.saves.back()["pieces"] & 1).is_equal(0)      # the saved game has the canister still to collect


## Screen 5's trigger fires; its problem opens 36 ticks later with the sub sitting on the trigger point.
func _open_the_trigger_problem() -> TriggerModel:
	await _begin_with_one_point_of_air()
	var sim := _stage.sim
	sim.load_screen(5)
	var trigger: TriggerModel = sim.triggers_on_screen(5)[0]
	sim.start_flight()
	sim.sub.position = Vector2(trigger.data.pos) - SubModel.PLAYFIELD_ORIGIN
	sim.touch_trigger(trigger)
	await _tick_until_the_problem_opens()
	return trigger


## While the problem is up, everything the rest of the tick would do to the sub is made ready: the trigger it sits on is armed
## again, a hostile creature lies on it, and it has speed.
func _arrange_the_rest_of_the_tick(trigger: TriggerModel) -> Vector2:
	var sim := _stage.sim
	trigger.armed = true
	var hostile: FoeModel = null
	for foe in sim.foes:
		if foe.vm.damage > 0:
			hostile = foe
			break
	assert_object(hostile).is_not_null()
	hostile.vm.screen = sim.screen_index
	hostile.vm.hidden = false
	hostile.vm.x = sim.sub.original_position().x
	hostile.vm.y = sim.sub.original_position().y
	hostile.refresh(true)
	sim.sub.velocity_units = Vector2i(64, 0)
	sim.trace_ticks = true
	sim.tick_trace.clear()
	_events.clear()
	return sim.sub.position


func test_a_problem_that_costs_the_tank_ends_the_tick_no_move_no_hit_no_trigger() -> void:
	var trigger := await _open_the_trigger_problem()
	var sim := _stage.sim
	var ticks_before := sim.tick_number
	var at := _arrange_the_rest_of_the_tick(trigger)
	_answer_wrong_with_the_last_air()
	assert_array(sim.tick_trace).is_empty()                        # not one more step of the tick that opened the problem
	assert_that(sim.sub.position).is_equal(at)                     # the sub did not move
	assert_bool(trigger.armed).is_true()                           # `DetectMathTrigger` did not run
	assert_int(sim.pending_slot).is_equal(-1)
	assert_bool(sim.is_dissolving()).is_false()                    # `update_animals` did not run: no hit, no dissolve
	assert_int(sim.tick_number).is_equal(ticks_before)             # the tick was abandoned: no `ticked`
	for event in _events:
		assert_bool(event.begins_with("damaged") or event.begins_with("trigger") or event.begins_with("pending") or event.begins_with("sub_hit")) \
				.override_failure_message("the abandoned tick said '%s'" % event).is_false()
	assert_bool(_run.has_held_loss()).is_false()
	assert_array(_later).has_size(1)                               # the respawn, and nothing else, follows
	_run_deferred()
	assert_int(_run.oxygen()).is_equal(Tuning.resolve().max_oxygen)


func test_a_solved_problem_lets_the_rest_of_the_tick_go_on() -> void:
	# The same arrangement with the right answer: `DoMathProblem` returns 0 and `DoAction` goes on with the pass, so the sub moves,
	# the trigger under it fires and the creature on it hurts it (this proves the arrangement above would be seen).
	var trigger := await _open_the_trigger_problem()
	var sim := _stage.sim
	var at := _arrange_the_rest_of_the_tick(trigger)
	_view.oxygen_code = OxygenModel.OK
	_view.release(&"problem")
	assert_array(sim.tick_trace).contains([&"sub", &"triggers", &"contacts"])
	assert_bool(sim.sub.position != at).is_true()
	assert_bool(trigger.armed).is_false()
	assert_bool(_events.any(func(e: String) -> bool: return e.begins_with("damaged"))).is_true()


func test_a_problem_that_costs_the_tank_does_not_take_the_sub_into_screen_6() -> void:
	await _begin_with_one_point_of_air()
	var sim := _stage.sim
	for i in sim.sector.pieces.size():                             # (every piece before the midpoint is collected: screen 6 would pass it)
		_run.collect_piece(i)
	sim.load_screen(Tuning.resolve().midpoint_screen - 1)
	sim.start_flight()
	sim.sub.position = Vector2(SubModel.RIGHT_EDGE - 2.0, sim.sub.position.y)
	sim.touch_trigger(sim.triggers_on_screen(sim.screen_index)[0])
	await _tick_until_the_problem_opens()
	sim.sub.velocity_units = Vector2i(64, 0)                       # (the rest of the tick would carry it over the edge)
	_answer_wrong_with_the_last_air()
	assert_int(sim.screen_index).is_equal(Tuning.resolve().midpoint_screen - 1)
	assert_bool(_run.midpoint_reached).is_false()
	assert_bool(_run.past_midpoint).is_false()


func test_an_owner_that_answers_at_once_ends_the_tick_the_same_way() -> void:
	# A view with no screen answers inside `problem_requested`, in the step `pending_problem` itself.
	await _begin_with_one_point_of_air()
	var sim := _stage.sim
	sim.load_screen(5)
	var trigger: TriggerModel = sim.triggers_on_screen(5)[0]
	sim.start_flight()
	sim.sub.position = Vector2(trigger.data.pos) - SubModel.PLAYFIELD_ORIGIN
	sim.touch_trigger(trigger)
	for i in Tuning.resolve().pending_ticks - 2:
		sim.tick()
	assert_bool(sim.problem_active).is_false()
	_arrange_the_rest_of_the_tick(trigger)
	var ticks_before := sim.tick_number
	_view.oxygen_code = OxygenModel.OUT_WITH_SPARE_TANKS          # (what the screen reports; the run's own loss is not needed here)
	sim.tick()                                                     # the countdown runs out: the problem opens and is answered at once
	assert_str(_log.back()).starts_with("music ")                  # (it was shown, and the song came back)
	assert_array(sim.tick_trace).is_equal([&"fire", &"pending_problem"])
	assert_bool(sim.problem_active).is_false()
	assert_bool(trigger.armed).is_true()
	assert_int(sim.tick_number).is_equal(ticks_before)
