class_name TestHintPersistence
extends GdUnitTestSuite
## Teaches: a bit mask surviving a save: the mask in the profile keeps the original's upper 9 bits set.


func test_the_saved_mask_keeps_the_original_upper_bits() -> void:
	var hints := HintSystem.new()
	assert_int(hints.mask_for_save()).is_equal(0xFFFF)
	hints.take(HintSystem.LOW_OXYGEN)
	assert_int(hints.mask_for_save()).is_equal(0xFFFF & ~(1 << HintSystem.LOW_OXYGEN))


func test_loading_a_mask_restores_which_hints_were_shown() -> void:
	var hints := HintSystem.new()
	hints.load_mask(0xFFFF & ~(1 << HintSystem.CONTROLS))
	assert_bool(hints.take(HintSystem.CONTROLS)).is_false()           # already seen
	assert_bool(hints.take(HintSystem.CALCULATOR)).is_true()


func test_hints_seen_by_one_player_come_back_after_a_save_and_load() -> void:
	var player := PlayerProfile.new_player("Ann", PlayerProfile.Game.VOYAGER)
	GameState.apply_profile(player)
	GameState.hints.take(HintSystem.DATA_CANISTER)
	GameState.capture_profile()
	var back := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(player.to_dict())))
	GameState.apply_profile(back)
	assert_bool(GameState.hints.take(HintSystem.DATA_CANISTER)).is_false()
	assert_bool(GameState.hints.take(HintSystem.CONTROLS)).is_true()
	GameState.profile = null
	GameState.hints.reset()
	GameState.reset()
