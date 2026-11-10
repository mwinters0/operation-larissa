class_name TestGameDebug
extends GdUnitTestSuite
## Teaches: testing a debug tool the same way as any view. The F3 overlay is a child of the real
## `Game` scene, so the test starts the game, "presses F3" by handing the overlay an
## `InputEventAction`, and reads the piece boxes after changing `GameState`.

const GAME_SCENE := "res://src/gameplay/game.tscn"


func before_test() -> void:
	SectorWorld.skip_animations = true
	GameState.profile = null


func after_test() -> void:
	SectorWorld.skip_animations = false
	GameState.profile = null
	GameClock.paused = false
	GameState.hints.reset()
	GameState.reset()


func _press_f3(debug: GameDebug) -> void:
	var event := InputEventAction.new()
	event.action = &"debug_overlay"
	event.pressed = true
	debug._unhandled_input(event)


func test_piece_boxes_show_only_while_the_overlay_is_shown() -> void:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var debug := game.get_node("GameDebug") as GameDebug
	assert_bool(debug.pieces.visible).is_false()
	_press_f3(debug)
	assert_bool(debug.pieces.visible).is_true()
	_press_f3(debug)
	assert_bool(debug.pieces.visible).is_false()


func test_piece_boxes_follow_the_collected_pieces() -> void:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var debug := game.get_node("GameDebug") as GameDebug
	assert_int(debug.pieces.total).is_equal(game.world.sector.pieces.size())
	assert_int(debug.pieces.collected_count()).is_equal(0)
	var last := debug.pieces.total - 1                                  # (the first sector of the game has at least the canister and one more piece)
	assert_int(last).is_greater(0)
	GameState.collect_piece(0)
	GameState.collect_piece(last)
	assert_int(debug.pieces.collected_count()).is_equal(2)
	GameState.clear_piece(0)
	assert_int(debug.pieces.collected_count()).is_equal(1)


func test_key_r_swaps_the_original_look_for_the_debug_rectangles_and_back() -> void:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var debug := game.get_node("GameDebug") as GameDebug
	while game.messages.is_open():                                      # (a hint box would swallow the key)
		game.messages.close_current()
	_press_f3(debug)                                                    # (the keys work while the overlay is shown)
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	var sector := game.world.sector_index
	debug._unhandled_input(key)
	assert_object(game.world.presenter).is_instanceof(DebugRectPresenter)
	assert_int(game.world.sector_index).is_equal(sector)                # the game goes on as it was
	assert_array((game.world.presenter as DebugRectPresenter).boxes()).is_not_empty()
	debug._unhandled_input(key)
	assert_object(game.world.original).is_not_null()


func test_key_s_puts_on_the_next_skin_and_the_game_goes_on() -> void:
	SkinChoice.select(SkinChoice.original())
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var debug := game.get_node("GameDebug") as GameDebug
	while game.messages.is_open():
		game.messages.close_current()
	_press_f3(debug)
	var key := InputEventKey.new()
	key.keycode = KEY_S
	key.pressed = true
	var sector := game.world.sector_index
	var presenter := game.world.presenter
	debug._unhandled_input(key)
	assert_str(String(SkinChoice.current().id)).is_equal(String(SkinChoice.after(SkinChoice.ORIGINAL)))
	assert_object(game.world.presenter).is_not_same(presenter)          # the world dressed itself again
	assert_int(game.world.sector_index).is_equal(sector)
	SkinChoice.select(SkinChoice.original())


func test_key_3_takes_the_next_piece_through_the_rules_so_the_screen_and_the_run_agree() -> void:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var debug := game.get_node("GameDebug") as GameDebug
	while game.messages.is_open():
		game.messages.close_current()
	_press_f3(debug)
	var sim := game.world.sim
	game.world.load_screen(sim.sector.pieces[0].screen)               # (the canister's screen: its picture is shown)
	assert_bool(sim.pieces.any(func(p: PieceModel) -> bool: return p.index == 0)).is_true()
	var key := InputEventKey.new()
	key.keycode = KEY_3
	key.pressed = true
	debug._unhandled_input(key)
	assert_bool(GameState.has_piece(0)).is_true()                      # the run
	assert_bool(sim.pieces.any(func(p: PieceModel) -> bool: return p.index == 0)).is_false()     # the rules
	assert_bool(game.world.original.collectibles.get_children().any(func(c: Collectible) -> bool: return c.index == 0)).is_false()   # the picture
	assert_int(sim.pending_slot).is_equal(SimWorld.CANISTER_SLOT)       # the canister's problem waits, as when the sub touches it
	assert_int(debug.pieces.collected_count()).is_equal(1)


func _press(debug: GameDebug, keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	debug._unhandled_input(key)


## The finale is the next sector as the game starts one (`GameState.begin_sector`, then `GameFlow.begin_sector`): the pieces and the
## midpoint of the sector the player jumped from stay behind.
func test_key_8_starts_the_finale_with_nothing_collected() -> void:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var debug := game.get_node("GameDebug") as GameDebug
	while game.messages.is_open():
		game.messages.close_current()
	_press_f3(debug)
	game.profile.campaign_id = &"dev_tour"                              # (a campaign with a finale: sector 4)
	var finale: int = game.profile.campaign().finales[0]
	GameState.collect_piece(0)
	GameState.collect_piece(1)
	GameState.past_midpoint = true
	while game.messages.is_open():                                      # (the canister's hint)
		game.messages.close_current()
	_press(debug, KEY_8)
	await await_idle_frame()
	assert_int(game.world.sector_index).is_equal(finale)
	assert_int(GameState.sector).is_equal(finale)
	assert_int(GameState.pieces_mask).is_equal(0)
	assert_bool(GameState.past_midpoint).is_false()
	assert_int(game.world.screen_index).is_equal(0)                    # (the launch from the station, not the respawn point)

## Key 6 opens a problem through the rules' entry (`SimWorld.open_problem`, which `open_pending_problem` is built from): a problem that
## was waiting is taken over, so the countdown, the beacon on the sub and the console's light go out, as when the problem opens by
## itself. While a problem is open the key does nothing.
func test_key_6_opens_the_problem_through_the_rules_and_the_waiting_one_is_taken() -> void:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var debug := game.get_node("GameDebug") as GameDebug
	while game.messages.is_open():
		game.messages.close_current()
	_press_f3(debug)
	var sim := game.world.sim
	var opened: Array[int] = []
	sim.problem_requested.connect(func(slot: int) -> void: opened.append(slot))
	var trigger: TriggerModel = sim.triggers[0]
	sim.touch_trigger(trigger)                                          # a problem waits: the countdown runs, the lights are on
	assert_int(sim.pending_slot).is_greater(-1)
	assert_bool(sim.sub.message_light).is_true()
	while game.messages.is_open():                                      # (the blinking light's hint)
		game.messages.close_current()
	_press(debug, KEY_6)
	assert_array(opened).is_equal([2])
	assert_bool(sim.problem_active).is_true()
	assert_int(sim.pending_slot).is_equal(-1)
	assert_bool(sim.sub.message_light).is_false()
	assert_bool(GameState.ship_light or GameState.computer_light).is_false()
	_press(debug, KEY_6)                                                # a problem is open: the key does nothing
	assert_array(opened).is_equal([2])
	assert_array(SourceScan.find("res://src/debug/game_debug.gd", ["pending_slot", "pending_ticks", "problem_active"])) \
			.override_failure_message("F3 6 opens a problem through SimWorld.open_problem and writes no state of the rules").is_empty()
