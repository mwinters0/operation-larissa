class_name TestGameScene
extends GdUnitTestSuite
## Teaches: an integration test of a whole scene: the free-play Game with its playfield, HUD,
## menu and dialogs. It checks that the pieces are connected, not the rules inside them.

const GAME_SCENE := "res://src/gameplay/game.tscn"


func before_test() -> void:
	SectorWorld.skip_animations = true                                # no door and driving animations in tests
	GameState.profile = null                                          # free play


func after_test() -> void:
	SectorWorld.skip_animations = false
	GameState.profile = null
	GameClock.paused = false
	GameState.hints.reset()
	GameState.reset()


func _start() -> Game:
	var game := scene_runner(GAME_SCENE).scene() as Game
	return game


func test_free_play_starts_in_sector_zero_with_the_controls_hint() -> void:
	var game := _start()
	await await_idle_frame()
	assert_int(game.world.sector_index).is_equal(0)
	assert_bool(game.world.sim.sub.active).is_true()
	assert_bool(game.messages.is_open()).is_true()                     # hint 0
	assert_str(game.messages.current.title).is_equal(Catalog.text(&"new_player_hint_title"))
	assert_bool(GameClock.paused).is_true()                            # the hint is modal


func test_the_hint_is_shown_only_once() -> void:
	var game := _start()
	await await_idle_frame()
	game.messages.close_current()
	var all_but_one := GameState.tuning.max_oxygen - 1
	GameState.update_oxygen(-all_but_one)                              # one cell left: hint 1
	assert_bool(game.messages.is_open()).is_true()
	game.messages.close_current()
	GameState.update_oxygen(1)
	GameState.update_oxygen(-all_but_one)
	assert_bool(game.messages.is_open()).is_false()


func test_hints_can_be_switched_off_in_the_options_menu() -> void:
	GameState.hints.reset()
	var game := _start()
	await await_idle_frame()
	game.messages.close_current()                                      # the controls hint
	game.menu_bar.options_menu.id_pressed.emit(0)                      # New Player Hints: asks first
	game.messages.close_current(1)                                     # No
	assert_bool(GameState.hints.enabled).is_false()
	GameState.hints.enabled = true


func test_hud_follows_the_world() -> void:
	var game := _start()
	var hud := game.get_node("%Hud") as Hud
	assert_int(GameState.piece_total).is_equal(game.world.sector.pieces.size())
	assert_int(hud.tanks.value).is_equal(GameState.tuning.refill_tanks)


func test_menu_has_the_packs_menus() -> void:
	var game := _start()
	assert_int(game.menu_bar.get_menu_count()).is_equal(3)
	assert_str(game.menu_bar.get_menu_title(0)).is_equal(Catalog.text(&"file_menu_title").replace("&", ""))
	var options := Catalog.text(&"options_menu_items").split("\n")
	assert_int(game.menu_bar.options_menu.item_count).is_equal(options.size() + 1)           # (and Audio Settings, which is ours)
	assert_str(game.menu_bar.options_menu.get_item_text(0)).is_equal(options[0])


func test_exit_asks_first() -> void:
	var game := _start()
	await await_idle_frame()
	game.messages.close_current()                                      # the controls hint
	game.ask_to_exit()
	assert_str(game.messages.current.title).is_equal(Catalog.text(&"exit_title"))
	assert_int(game.messages.current.buttons.size()).is_equal(2)
	game.messages.close_current(1)                                     # No
	assert_bool(game.messages.is_open()).is_false()


func test_a_problem_request_shows_the_problem_over_the_console() -> void:
	var game := _start()
	await await_idle_frame()
	game.messages.close_current()
	game.world.problem_requested.emit(2)
	assert_int(game.problem_layer.get_child_count()).is_equal(1)
	var screen := game.problem_layer.get_child(0) as ProblemScreen
	assert_bool(screen != null).is_true()
	screen.close()
	await await_idle_frame()
