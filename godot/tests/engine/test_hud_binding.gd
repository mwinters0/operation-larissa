class_name TestHudBinding
extends GdUnitTestSuite
## Teaches: testing a view by changing the model and reading the view. The HUD is instanced as a
## scene; the tests set `GameState` values (through its methods, which emit the signals) and
## look at the gauges, the labels and the lights. No frame has to pass: the HUD reacts in the
## signal handler (acceptance 1: no polling in `_process`).

const HUD_SCENE := "res://src/ui/hud.tscn"

var _hud: Hud


func before_test() -> void:
	GameState.reset()
	GameState.customized = false
	GameState.set_sector(0, 9)
	_hud = scene_runner(HUD_SCENE).scene() as Hud


func after_test() -> void:
	GameState.reset()
	GameState.customized = false
	GameState.sector = -1
	GameState.piece_total = 0


func test_starts_like_a_new_player() -> void:
	assert_int(_hud.tanks.value).is_equal(Tuning.resolve().refill_tanks)
	assert_int(_hud.oxygen.value).is_equal(Tuning.resolve().max_oxygen)
	assert_int(_hud.ink.value).is_equal(Tuning.resolve().ink_max)


func test_oxygen_loss_empties_cells_at_once() -> void:
	var full := GameState.tuning.max_oxygen
	GameState.update_oxygen(-1)
	assert_int(_hud.oxygen.value).is_equal(full - 1)
	assert_object(_hud.oxygen.texture_for_slot(full - 1)).is_same(_hud.layout.oxygen_empty)
	assert_object(_hud.oxygen.texture_for_slot(full - 2)).is_same(_hud.layout.oxygen_full)


func test_one_cell_left_shows_the_warning_picture() -> void:
	GameState.update_oxygen(-(GameState.tuning.max_oxygen - 1))
	assert_int(_hud.oxygen.value).is_equal(1)
	assert_bool(_hud.oxygen.is_low()).is_true()
	assert_object(_hud.oxygen.texture_for_slot(0)).is_same(_hud.layout.oxygen_low)
	assert_object(_hud.oxygen.texture_for_slot(1)).is_same(_hud.layout.oxygen_empty)
	assert_str(_hud.air_animations.current_animation).is_equal("low_oxygen")
	GameState.update_oxygen(1)                         # a refill ends the warning
	assert_bool(_hud.oxygen.is_low()).is_false()
	assert_bool(_hud.air_animations.is_playing()).is_false()


func test_spare_tanks() -> void:
	var tanks := GameState.tanks()
	GameState.update_oxygen(-4)                        # last cell gone with spare tanks: the code says "tank lost"
	GameState.update_oxygen(4)                         # the respawn: one tank is used
	assert_int(_hud.tanks.value).is_equal(tanks - 1)
	GameState.update_oxygen(1)                         # Zoom's tank: oxygen is full so +1 tank
	assert_int(_hud.tanks.value).is_equal(tanks)


func test_ink_pellets_follow_the_supply() -> void:
	GameState.fire_ink()
	GameState.fire_ink()
	var full := GameState.tuning.ink_max
	assert_int(_hud.ink.value).is_equal(full - 2)
	assert_object(_hud.ink.texture_for_slot(full - 1)).is_same(_hud.layout.ink_empty)
	GameState.refill_ink()
	assert_int(_hud.ink.value).is_equal(full)


func test_the_console_has_no_piece_read_out() -> void:
	# The original console shows no pieces; the port's row of boxes lives in the F3 overlay (test_game_debug).
	assert_object(_hud.find_child("Pieces", true, false)).is_null()


func test_labels_follow_the_sector() -> void:
	GameState.set_sector(2, 8)                         # the third sector of the tour
	var sector := Catalog.sector(2)
	assert_object(_hud.game_label.texture).is_same(_hud.layout.game_textures[sector.game])
	assert_object(_hud.zone_label.texture).is_same(_hud.layout.zone_texture(sector.zone))
	assert_object(_hud.sector_label.texture).is_same(_hud.layout.sector_textures[2 % 3])
	GameState.set_sector(DevPack.TOUR_FINALE, 8)       # the finale
	assert_object(_hud.sector_label.texture).is_same(_hud.layout.sector_final_texture)


func test_customized_games_say_cust() -> void:
	assert_bool(_hud.custom_label.visible).is_false()
	GameState.customized = true
	assert_bool(_hud.custom_label.visible).is_true()


func test_message_lights() -> void:
	assert_bool(_hud.ship_glow.visible).is_false()
	GameState.set_message_light(true, false)
	assert_bool(_hud.ship_glow.visible).is_true()
	assert_bool(_hud.computer_glow.visible).is_false()
	assert_bool(_hud.light_animations.is_playing()).is_true()
	GameState.set_message_light(false, true)
	assert_bool(_hud.ship_glow.visible).is_false()
	assert_bool(_hud.computer_glow.visible).is_true()
	GameState.set_message_light(false, false)
	assert_bool(_hud.light_animations.is_playing()).is_false()


func test_which_light_a_trigger_slot_lights() -> void:
	assert_object(GameState.light_for_slot(1)).is_equal(Vector2i(0, 1))      # the data canister: computer
	assert_object(GameState.light_for_slot(2)).is_equal(Vector2i(1, 0))
	assert_object(GameState.light_for_slot(19)).is_equal(Vector2i(1, 0))
	assert_object(GameState.light_for_slot(20)).is_equal(Vector2i(0, 1))
	assert_object(GameState.light_for_slot(59)).is_equal(Vector2i(0, 1))
	assert_object(GameState.light_for_slot(60)).is_equal(Vector2i(1, 0))
