class_name TestDockWithoutLock
extends GdUnitTestSuite
## A chain whose combination lock (problem type 0) has no records at the player's level, or any level below, does not leave the sub parked at the end station. At the dock the flow enters `busy` and asks for the lock; when
## `ProblemFactory` has none to give, there is nothing to put on screen and nothing that would end the wait. So the flow says so through the `TroubleLog` (the sector and the campaign) and finishes the sector as
## if the lock had opened: the supply message, the balloon and the next sector follow, and `busy` is let go.
##
## Teaches: a state that is entered before an operation that can fail (`busy`, taken before the lock is made) needs the way out written next to the way in, and a test that makes the operation fail through the data (a problem
## type of a scratch pack with no records), not through a stub. The same technique as `test_problem_unavailable`, for the dock.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"

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
	_run.profile = _player
	_store = FakeSaveStore.new()
	_store.watched = _player
	_stage = HeadlessStage.new(_run)
	_stage.log = _log
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


## Type 0 of the chain in use keeps its words and its picture but holds no record at any level.
func _empty_the_lock() -> void:
	_shelf = PackShelf.new()
	var lock := Catalog.problem_type_unskinned(0).duplicate(true) as ProblemType
	lock.records = [] as Array[PackedInt64Array]
	lock.record_levels = PackedInt32Array()
	_shelf.write_json("data/problems/problem_type_00.json", ResourceJson.new().data_of(lock))
	_shelf.mount()
	for level in 4:
		assert_object(ProblemFactory.make(0, level)).is_null()


func test_a_dock_whose_lock_cannot_be_made_finishes_the_sector_and_says_why() -> void:
	_empty_the_lock()
	_player.progress = 0
	_flow.enter(0, 1)
	await _flow.begin_mission()
	for i in _stage.sector.pieces.size():
		_run.collect_piece(i)
	_log.clear()
	_stage.dock_reached.emit()
	assert_bool(_log.any(func(line: Variant) -> bool: return str(line).begins_with("problem "))).is_false()
	assert_bool(_log.has("supply message 0")).override_failure_message("the sector was not finished: %s" % [_log]).is_true()
	assert_int(_player.sector()).is_equal(1)
	assert_int(_stage.sector_index).is_equal(1)                    # (the next sector began)
	assert_bool(_flow.busy).override_failure_message("the flow is still busy at a dock that did nothing").is_false()
	assert_array(TroubleLog.session.told).has_size(1)              # (the factory says nothing of a type that holds no records: the flow says what the player sees)
	assert_str(TroubleLog.session.told[0]).contains("combination lock").contains("sector 0").contains("campaign '%s'" % _flow.campaign.id)
