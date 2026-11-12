class_name TestMenusDuringProblem
extends GdUnitTestSuite
## The menu bar answers while a math problem is up. The original's menu is the window's own, so File, Options and Help work in the middle of
## every answer loop (`MenuReturnToSignInSave` and `SaveAndExit` are reached from them); the port's `GameMenuBar` is a node, so the screens that play
## (`ProblemLayer`) must not lie over it. The test sends real mouse and key events through the viewport, as the player's hands do, in every
## state of a problem: answering, after a wrong answer (the screen's click catcher is up), the success message or replay, and after it closes.
##
## Teaches: a click-through test goes through `Viewport.push_input` and asks `gui_get_hovered_control`, so a control that covers another
## (a `Control` is `MOUSE_FILTER_STOP` by default, and a screen on a higher `CanvasLayer` is over everything below) shows up as the wrong node.

const GAME_SCENE := "res://src/gameplay/game.tscn"
const ROSTER := "user://test_menus_roster.json"
const HALL := "user://test_menus_hall.json"
const TRIGGER_SCREEN := 5

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]
var _runner: GdUnitSceneRunner



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
	var player := SaveStore.add_player("Menus", 0)
	player.hints_enabled = false
	GameState.profile = player
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


func _open_problem() -> Game:
	_runner = scene_runner(GAME_SCENE)
	var game := _runner.scene() as Game
	await await_idle_frame()
	while game.messages.is_open():
		game.messages.close_current()
	game.world.load_screen(TRIGGER_SCREEN)
	game.world.foes_active = false
	var trigger: MathTriggerData = game.world.sector.screens[TRIGGER_SCREEN].triggers[0]
	game.world.sim.sub.position = Vector2(trigger.pos) - Sub.PLAYFIELD_ORIGIN
	game.world.tick()
	for i in Tuning.resolve().pending_ticks:
		GameClock.step()
	await await_idle_frame()
	return game


func _title_point() -> Vector2:
	return Vector2(Catalog.menu_layout().popup_x(0) + 6, 10)          # (on the File title)


func _move_mouse_to_the_file_title(game: Game) -> Control:
	var p := _title_point()
	var motion := InputEventMouseMotion.new()
	motion.position = p
	motion.global_position = p
	game.get_viewport().push_input(motion)
	return game.get_viewport().gui_get_hovered_control()


func _click_the_file_title(game: Game) -> void:
	var p := _title_point()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = p
		click.global_position = p
		game.get_viewport().push_input(click)
	await await_idle_frame()


func _press_f10(game: Game) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_F10
	key.physical_keycode = KEY_F10
	key.pressed = true
	game.get_viewport().push_input(key)
	await await_idle_frame()


## The mouse reaches the menu bar, a click opens File, F10 opens it too; then the menu is closed again.
func _assert_menus_answer(game: Game, state: String) -> void:
	game.menu_bar.file_menu.hide()
	var hovered := _move_mouse_to_the_file_title(game)
	assert_object(hovered).override_failure_message("%s: the mouse over the File title is over %s, not the menu bar" % [state, hovered]).is_same(game.menu_bar)
	await _click_the_file_title(game)
	assert_bool(game.menu_bar.file_menu.visible).override_failure_message("%s: a click on File did not open the menu" % state).is_true()
	game.menu_bar.file_menu.hide()
	await await_idle_frame()
	await _press_f10(game)
	assert_bool(game.menu_bar.file_menu.visible).override_failure_message("%s: F10 did not open the File menu" % state).is_true()
	game.menu_bar.file_menu.hide()
	await await_idle_frame()


func _answer_wrongly(screen: ProblemScreen) -> void:
	if screen.session.instance.input_kind == ProblemInstance.InputKind.DENOMINATIONS:
		screen.submit_answer(0)
	else:
		screen.submit_answer(NumberValue.parse("98765"))


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


func test_the_menus_answer_while_the_problem_waits_for_an_answer() -> void:
	var game := await _open_problem()
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	assert_bool(screen.is_answering()).is_true()
	await _assert_menus_answer(game, "answering")


func test_the_menus_answer_after_a_wrong_answer() -> void:
	var game := await _open_problem()
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	_answer_wrongly(screen)
	assert_bool(screen.is_answering()).is_false()                      # ("Error!": the click catcher is up, a click anywhere goes on)
	var step_before := screen.step()
	await _assert_menus_answer(game, "after a wrong answer")
	assert_int(screen.step()).override_failure_message("a click on the menu bar went on through the catcher").is_equal(step_before)


func test_the_menus_answer_after_a_right_answer() -> void:
	var game := await _open_problem()
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	_answer_correctly(screen)
	assert_bool(screen.session.solved).is_true()
	var step_before := screen.step()
	await _assert_menus_answer(game, "after a right answer (the replay or the success message)")
	assert_int(screen.step()).is_equal(step_before)


func test_a_menu_item_chosen_in_the_problem_asks_and_the_problem_goes_on_after_no() -> void:
	var game := await _open_problem()
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	game.menu_bar.file_menu.id_pressed.emit(GameMenuBar.FileItem.EXIT)          # (the menu's own signal: the item chosen with the mouse)
	assert_str(game.messages.current.title).is_equal(Catalog.text(&"exit_title"))
	assert_bool(game.modals.is_open()).is_true()
	game.messages.close_current(1)                                                # No
	await await_idle_frame()
	assert_bool(game.modals.is_open()).is_false()
	assert_bool(screen.is_answering()).is_true()
	await _assert_menus_answer(game, "after the question was answered No")


func test_the_menus_answer_after_the_problem_closed() -> void:
	var game := await _open_problem()
	var screen: ProblemScreen = game.problem_layer.get_child(0)
	_answer_correctly(screen)
	for i in 6:                                                                    # (Enter: the replay, the message, the log screen of a canister)
		if not is_instance_valid(screen) or screen.is_queued_for_deletion():
			break
		screen.press_continue()
		await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	assert_int(game.problem_layer.get_child_count()).is_equal(0)
	assert_bool(game.modals.is_open()).is_false()
	assert_int(GameClock.holds).is_equal(0)
	await _assert_menus_answer(game, "after the problem closed")
