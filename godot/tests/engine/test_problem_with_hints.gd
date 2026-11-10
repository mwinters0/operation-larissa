class_name TestProblemWithHints
extends GdUnitTestSuite
## Teaches: why a flow test must run with the SETTINGS A REAL PLAYER HAS. Every other game-flow test switches the new
## player hints off ("no hint dialogs in the way"), but a fresh Voyager player has them on, and the hints are
## modal messages that stop the game clock and are put on screen right around the math problem: the blinking-light
## hint when a trigger is touched, the "type your answer" hint when the problem opens. Messages and the problem
## screen both pause the clock and both put back what they found, so their order of closing matters.
##
## The flow, driven with real key presses through the viewport: touch a math trigger -> blinking-light hint ->
## (Enter) -> problem -> answer -> Enter -> back in flight (clock running, the sub answers the arrow keys).
## The first sector of the chain's campaign (dev's: `DevPack.TOUR_SECTORS`) has a math trigger on screen 5: the test reads its place and slot from the data.

const GAME_SCENE := "res://src/gameplay/game.tscn"
const ROSTER := "user://test_hints_roster.json"
const HALL := "user://test_hints_hall.json"
const TRIGGER_SCREEN := 5

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]
var _player: PlayerProfile
var _runner: GdUnitSceneRunner
var _trigger: MathTriggerData             ## the trigger of screen 5 (read from the sector the game opens on)


func before_test() -> void:
	_old_roster = SaveStore.roster_path
	_old_hall = SaveStore.hall_path
	_old_players = SaveStore.players.duplicate()
	SaveStore.roster_path = ROSTER
	SaveStore.hall_path = HALL
	SaveStore.players = []
	SaveStore.hall = HallOfFame.new()
	SectorWorld.skip_animations = true
	SceneRouter.dry_run = true
	_player = SaveStore.add_player("Fresh", 0)              # a brand new Voyager player: every hint unseen
	assert_bool(_player.hints_enabled).is_true()
	GameState.profile = _player
	GameClock.paused = false


func after_test() -> void:
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SaveStore.hall = HallOfFame.new()
	SectorWorld.skip_animations = false
	SceneRouter.dry_run = false
	GameState.profile = null
	GameClock.paused = false
	GameState.hints.reset()
	GameState.reset()
	for path in [ROSTER, HALL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _start() -> Game:
	_runner = scene_runner(GAME_SCENE)
	var game := _runner.scene() as Game
	await await_idle_frame()
	return game


## Closes the message on screen with a real Enter key press (what the player does).
func _press_enter() -> void:
	_runner.simulate_key_pressed(KEY_ENTER)
	await await_idle_frame()


func _enter_trigger_screen(game: Game) -> void:
	game.world.load_screen(TRIGGER_SCREEN)
	game.world.foes_active = false
	_trigger = game.world.sector.screens[TRIGGER_SCREEN].triggers[0]
	game.world.sim.sub.position = Vector2(_trigger.pos) - Sub.PLAYFIELD_ORIGIN
	game.world.tick()


## The right answer to whatever problem the trigger drew (number, range or ballast weights).
func _answer_correctly(screen: ProblemScreen) -> void:
	var instance := screen.session.instance
	if instance.input_kind == ProblemInstance.InputKind.DENOMINATIONS:
		for mask in range(1, 1 << 12):
			if instance.check(mask):
				screen.submit_answer(mask)
				return
	elif instance.expected != null:
		screen.submit_answer(instance.expected)
	else:
		var fields: PackedInt32Array = instance.type.extras["range_fields"]
		var low := instance.record.value_at(fields[0])
		var high := instance.record.value_at(fields[1])
		screen.submit_answer(NumberValue.from_double((low + high) / 2.0))


func _answer_wrongly(screen: ProblemScreen) -> void:
	if screen.session.instance.input_kind == ProblemInstance.InputKind.DENOMINATIONS:
		screen.submit_answer(0)
	else:
		screen.submit_answer(NumberValue.parse("98765"))


## Closes every message that is up (the player reads the hints and presses OK).
func _dismiss_messages(game: Game) -> void:
	while game.messages.is_open():
		game.messages.close_current()
	await await_idle_frame()


## The sub is back in flight: the clock runs, the problem is forgotten, the keys steer the sub.
func _assert_flying_again(game: Game) -> void:
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(game.messages.is_open()).is_false()
	assert_int(game.problem_layer.get_child_count()).is_equal(0)
	assert_bool(game.world.problem_active).is_false()
	assert_int(GameClock.holds).is_equal(0)
	assert_bool(GameClock.paused).is_false()                            # <- the bug: it stayed true for good
	assert_int(GameClock.advance(0.5)).is_greater(0)                    # ... so no ticks came
	var before := game.world.sim.sub.position
	var ticks_before := GameClock.tick_count
	for i in 10:
		Input.action_press(&"sub_left")             # (the game's own InputReader polls the real keys: this is the whole path)
		GameClock.step()
	Input.action_release(&"sub_left")
	assert_int(GameClock.tick_count).is_equal(ticks_before + 10)
	assert_bool(game.world.sim.sub.position != before).is_true()            # ... and the sub did not move


## A fresh player: flight, the controls hint closed by Enter, then the sub reaches the trigger.
func _fly_to_trigger() -> Game:
	var game := await _start()
	assert_bool(game.messages.is_open()).is_true()                      # hint 0: the controls
	await _press_enter()
	await _enter_trigger_screen(game)
	assert_int(game.world.pending_slot).is_equal(_trigger.slot)
	assert_str(game.messages.current.title).is_equal(Catalog.text(&"new_player_hint_title"))  # hint 5: the blinking light
	return game


## The player presses Enter on the blinking-light hint ("press Enter for the problem"): that one key closes
## the hint AND opens the problem, which now starts while the hint is still up.
func test_enter_on_the_blinking_light_hint_then_a_right_answer_returns_to_flight() -> void:
	var game := await _fly_to_trigger()
	await _press_enter()
	assert_bool(game.world.problem_active).is_true()
	assert_bool(GameClock.paused).is_true()                             # the problem is up: the playfield stands still
	await _dismiss_messages(game)                                       # the "type your answer" hint
	assert_bool(GameClock.paused).is_true()                             # <- the bug: closing the hint let the clock run
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	_answer_correctly(screen)
	assert_bool(screen.session.solved).is_true()
	await _press_enter()
	await _assert_flying_again(game)


## The player waits instead: the light blinks 36 ticks, then the problem opens by itself.
func test_the_countdown_opening_the_problem_and_a_right_answer_returns_to_flight() -> void:
	var game := await _fly_to_trigger()
	await _dismiss_messages(game)                                       # OK on the hint with the mouse
	assert_bool(GameClock.paused).is_false()
	for i in Tuning.resolve().pending_ticks:
		GameClock.step()
	assert_bool(game.world.problem_active).is_true()
	await _dismiss_messages(game)
	assert_bool(GameClock.paused).is_true()
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	_answer_correctly(screen)
	await _press_enter()
	await _assert_flying_again(game)


func test_wrong_then_right_returns_to_flight() -> void:
	var game := await _fly_to_trigger()
	await _press_enter()
	await _dismiss_messages(game)
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	_answer_wrongly(screen)
	assert_bool(screen.is_answering()).is_false()                       # "Error!" for 2 s or Enter
	await _press_enter()
	assert_bool(screen.is_answering()).is_true()                        # the hint, and the second try
	assert_bool(GameClock.paused).is_true()
	_answer_correctly(screen)
	assert_bool(screen.session.solved).is_true()
	await _press_enter()
	await _assert_flying_again(game)


func test_wrong_twice_shows_the_solution_and_returns_to_flight() -> void:
	var game := await _fly_to_trigger()
	await _press_enter()
	await _dismiss_messages(game)
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	_answer_wrongly(screen)
	await _press_enter()                                                # "Error!"
	_answer_wrongly(screen)
	for i in 3:                                                         # "Error!", the note to the ship (most types), then the solution
		if screen.step() != ProblemScreen.Step.SOLUTION:
			await _press_enter()
	assert_int(screen.step()).is_equal(ProblemScreen.Step.SOLUTION)
	assert_str(screen.text_label.text).is_equal(screen.session.instance.solution)
	assert_bool(GameClock.paused).is_true()
	await _press_enter()                                                # the solution is read: the success text follows
	await _press_enter()
	await _assert_flying_again(game)


## The data canister: the pick-up hint (a message) and the canister's problem start in the same frame.
func test_the_first_canister_problem_with_its_hint_returns_to_flight() -> void:
	var game := await _start()
	await _press_enter()                                                # the controls hint
	game.world.sim.take_piece(0)
	for i in GameState.tuning.canister_pending_ticks - 1:
		game.world.tick()                                         # the canister's problem opens when its countdown has run down to 1
	await await_idle_frame()
	assert_bool(game.world.problem_active).is_true()
	assert_bool(game.messages.is_open()).is_true()                      # the canister hint, over the problem screen
	await _dismiss_messages(game)
	assert_bool(GameClock.paused).is_true()
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	_answer_correctly(screen)
	assert_object(screen.log_screen).is_not_null()                      # the canister ends with its log screen ...
	screen.log_screen.advance_scan(CanisterLog.scan_ticks())              # (the rules own the length of the scan: hand it the ticks)
	_runner.simulate_key_pressed(KEY_DOWN)                              # ... Down moves to DONE, Enter leaves
	_runner.simulate_key_pressed(KEY_ENTER)                             # (not Esc: the scene runner also calls Game's own `_unhandled_input`, where Esc asks to exit)
	await await_idle_frame()
	await _assert_flying_again(game)


## Hints off (an Expert player, or switched off in the menu): the same flow, nothing in the way.
func test_the_same_flow_without_hints() -> void:
	_player.hints_enabled = false
	GameState.profile = _player
	var game := await _start()
	await _enter_trigger_screen(game)
	assert_bool(game.messages.is_open()).is_false()
	await _press_enter()                                                # Enter opens the problem
	assert_bool(game.world.problem_active).is_true()
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	_answer_correctly(screen)
	await _press_enter()
	await _assert_flying_again(game)
