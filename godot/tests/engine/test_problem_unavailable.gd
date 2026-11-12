class_name TestProblemUnavailable
extends GdUnitTestSuite
## A problem the chain in use cannot make never freezes the game. The world enters "a problem is open" when it asks for one (`SimWorld.open_problem`: the countdown and the beacon stop, the console's lights go out, `problem_active`
## is set), and only `problem_resolved` leaves it. So the flow (`GameFlow.open_problem`) answers with `ProblemSession.not_made` when `ProblemFactory` has nothing to give (a pack whose trigger table names types it does not hold;
## the factory tells the player why, once, `test_pack_trouble`), and the sub goes on, no screen having been shown. A data canister stays taken, so the sector can still be finished.
##
## Teaches: state that is entered before an operation that can fail needs a way out for the failure, and a test that makes the operation fail through the data (a trigger table of a scratch pack), not through a stub.
## The dev's ground sector (`Ground.MAIN`): the canister lies on screen 9, screen 5 has a math trigger.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const NO_SUCH_TYPE := 250

var _run: Object
var _player: PlayerProfile
var _store: FakeSaveStore
var _stage: HeadlessStage
var _view: FakeFlowView
var _flow: GameFlow
var _log: Array
var _shelf: PackShelf


func before_test() -> void:
	_log = []
	_run = auto_free(load(GAME_STATE_SCRIPT).new())
	_run.reset()                                                   # (a run begins: the session's `TroubleLog` is a new one)
	_player = PlayerProfile.new_player("Tester", PlayerProfile.Game.VOYAGER)
	_player.hints_enabled = false
	_player.progress = Ground.MAIN * 2
	_run.profile = _player
	_store = FakeSaveStore.new()
	_store.watched = _player
	_stage = HeadlessStage.new(_run)
	_stage.log = _log
	_stage.sim.ignore_currents = true
	_view = FakeFlowView.new(_log, _run)
	_flow = GameFlow.new(_run, _store, MessageQueue.new(StubClock.new()))
	_flow.world = _stage
	_flow.view = _view
	_flow.defer_call = func(_action: Callable) -> void: pass


func after_test() -> void:
	_flow.leave()
	if _shelf != null:
		_shelf.remove()
		_shelf = null


## The trigger table of the chain in use names a type no pack holds for `slot` at every level.
func _empty_the_slot(slot: int) -> void:
	_shelf = PackShelf.new()
	var table := Catalog.trigger_table().duplicate(true) as TriggerTable
	for level in TriggerTable.LEVELS:
		for pick in TriggerTable.PICKS:
			table.table[(slot * TriggerTable.LEVELS + level) * TriggerTable.PICKS + pick] = NO_SUCH_TYPE
	_shelf.write_json("data/trigger_table.json", ResourceJson.new().data_of(table))
	_shelf.mount()
	assert_object(ProblemFactory.for_trigger_slot(slot, 0)).is_null()


## Ticks until the countdown of the waiting problem is over (a problem that opens would show on the view's `log`).
func _tick_past_the_countdown() -> void:
	for i in Tuning.resolve().pending_ticks + 2:
		_stage.tick()


func test_a_canister_whose_problem_cannot_be_made_lets_the_sub_go_on_and_says_why() -> void:
	_empty_the_slot(SimWorld.CANISTER_SLOT)
	_flow.enter(0, 1)
	await _flow.begin_mission()
	var sim := _stage.sim
	sim.load_screen(Ground.MAIN_PIECES[0].x)
	sim.start_flight(Ground.MAIN_PIECES[0].y - 40, Ground.MAIN_PIECES[0].z - 20)
	_stage.tick()                                                  # (the canister is taken, countdown 2)
	assert_bool(_run.has_piece(0)).is_true()
	_tick_past_the_countdown()
	assert_bool(sim.problem_active).override_failure_message("the world is still inside a problem that was never shown").is_false()
	assert_int(sim.pending_slot).is_equal(-1)
	assert_bool(_run.computer_light).is_false()
	assert_bool(_log.any(func(line: String) -> bool: return line.begins_with("problem "))).is_false()
	assert_bool(_run.has_piece(0)).override_failure_message("the canister stays taken: no problem was asked, so none was failed").is_true()
	# the sub is free again: the tick runs to its end and the next one too
	var ticks := sim.tick_number
	_stage.tick()
	assert_int(sim.tick_number).is_greater(ticks)
	assert_array(TroubleLog.session.told).has_size(1)              # (one cause, one line: the factory's, which says what the player sees)
	assert_str(TroubleLog.session.told[0]).contains("for slot 1").contains("without its log entry")


func test_a_math_trigger_whose_problem_cannot_be_made_lets_the_sub_go_on_and_says_why_once() -> void:
	var slot: int = Catalog.sector(Ground.MAIN).screens[5].triggers[0].slot
	_empty_the_slot(slot)
	_flow.enter(0, 1)
	await _flow.begin_mission()
	var sim := _stage.sim
	sim.load_screen(5)
	var trigger: TriggerModel = sim.triggers_on_screen(5)[0]
	assert_int(trigger.data.slot).is_equal(slot)
	sim.start_flight()
	sim.sub.position = Vector2(trigger.data.pos) - SubModel.PLAYFIELD_ORIGIN
	sim.touch_trigger(trigger)
	assert_int(sim.pending_slot).is_equal(slot)
	_tick_past_the_countdown()
	assert_bool(sim.problem_active).is_false()
	assert_int(sim.pending_slot).is_equal(-1)
	assert_bool(_run.ship_light).is_false()
	assert_bool(_log.any(func(line: String) -> bool: return line.begins_with("problem "))).is_false()
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("for slot %d" % slot).contains("the sub goes on")
	var ticks := sim.tick_number
	_stage.tick()
	assert_int(sim.tick_number).is_greater(ticks)
