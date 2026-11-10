class_name TestGameSceneLegacy
extends GdUnitTestSuite
## Teaches: the free-play Game wears the original's menus and words (the scene's wiring: tests/engine/test_game_scene.gd).

const GAME_SCENE := "res://src/gameplay/game.tscn"


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	SectorWorld.skip_animations = true
	GameState.profile = null


func after_test() -> void:
	SectorWorld.skip_animations = false
	GameState.profile = null
	GameClock.paused = false
	GameState.hints.reset()
	GameState.reset()


func test_menu_has_the_original_menus() -> void:
	var game := scene_runner(GAME_SCENE).scene() as Game
	assert_int(game.menu_bar.get_menu_count()).is_equal(3)
	assert_str(game.menu_bar.get_menu_title(0)).is_equal("File")
	assert_int(game.menu_bar.options_menu.item_count).is_equal(6)
	assert_str(game.menu_bar.options_menu.get_item_text(0)).is_equal("New Player Hints")


func test_the_first_hint_and_the_exit_question_use_the_original_words() -> void:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	assert_str(game.messages.current.title).is_equal("New Player Hint")
	game.messages.close_current()
	game.ask_to_exit()
	assert_str(game.messages.current.title).is_equal("Exit")
	game.messages.close_current(1)
