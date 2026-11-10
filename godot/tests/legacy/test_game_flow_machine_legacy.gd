class_name TestGameFlowMachineLegacy
extends GdUnitTestSuite
## Teaches: the end of the original's two games through `GameFlow`, with a fake view: docking in the finale, and the closing scenes the campaigns name (Voyager's and Expert's).
## (The flow on any pack: tests/engine/test_game_flow_machine.gd.)

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"


var _run: Object
var _player: PlayerProfile
var _clock: StubClock
var _messages: MessageQueue
var _store: FakeSaveStore
var _stage: HeadlessStage
var _view: FakeFlowView
var _flow: GameFlow
var _log: Array
var _later: Array[Callable]


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	_log = []
	_later = []
	_run = auto_free(load(GAME_STATE_SCRIPT).new())               # the script of the autoload, not in any tree
	_player = PlayerProfile.new_player("Tester", PlayerProfile.Game.VOYAGER)
	_player.hints_enabled = false                                  # (no hint boxes in the way unless a test asks for them)
	_run.profile = _player
	_clock = StubClock.new()
	_messages = MessageQueue.new(_clock)
	_store = FakeSaveStore.new()
	_store.watched = _player
	_stage = HeadlessStage.new(_run)
	_stage.log = _log
	_view = FakeFlowView.new(_log, _run)
	_flow = GameFlow.new(_run, _store, _messages)
	_flow.world = _stage
	_flow.view = _view
	_flow.defer_call = func(action: Callable) -> void: _later.append(action)     # (the test decides when "a little later" is)


func after_test() -> void:
	_flow.leave()


## Runs what the flow put off ("a little later, outside the signal"), the way the idle frame does in the game.
func _run_deferred() -> void:
	var batch := _later.duplicate()
	_later.clear()
	for action: Callable in batch:
		action.call()


func _enter(sector: int = 0) -> void:
	_player.progress = sector * 2
	_flow.enter(0, 1)


## Collects every piece of the sector that is loaded.
func _collect_all() -> void:
	for i in _stage.sector.pieces.size():
		_run.collect_piece(i)


# --- what the flow is made of ---------------------------------------------------------------

func test_docking_in_a_finale_ends_the_game_with_no_closing() -> void:
	_enter(30)
	await _flow.begin_mission()
	_log.clear()
	await _flow.complete_sector()
	assert_array(_log).is_equal(["music 30", &"dock", "stop music", "supply message 30", "music 30", &"balloon", "hall of fame", "sign in"])
	assert_array(_store.hall).is_equal([_player])


# --- the finale -------------------------------------------------------------------------------------

func test_the_closing_of_the_voyager_game_gets_the_sub_and_ends_in_the_hall_of_fame() -> void:
	_enter(30)
	await _flow.begin_mission()
	_log.clear()
	var sub_at: Vector2i = _stage.sim.sub.original_position()
	var cell: int = _stage.sim.sub.cell
	_view.hold(&"closing")
	_stage.finale_reached.emit()
	assert_array(_log).is_equal(["stop music", "closing voyager at %s cell %d" % [sub_at, cell]])
	assert_bool(_stage.sim.sub.active).is_false()                  # the closing draws its own sub
	assert_bool(_flow.busy).is_true()
	_view.release(&"closing")
	assert_array(_log.slice(2)).is_equal(["hall of fame", "sign in"])
	assert_array(_store.hall).is_equal([_player])
	assert_bool(_flow.busy).is_false()


func test_the_closing_of_the_expert_game_is_told_so() -> void:
	_player.game = PlayerProfile.Game.EXPERT
	_enter(31)
	await _flow.begin_mission()
	_log.clear()
	_stage.finale_reached.emit()
	assert_str(_log[1]).starts_with("closing expert")
	assert_array(_store.hall).is_equal([_player])
