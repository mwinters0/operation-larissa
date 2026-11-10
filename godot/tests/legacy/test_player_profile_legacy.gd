class_name TestPlayerProfileLegacy
extends GdUnitTestSuite
## Teaches: the original's two games, Voyager and Expert, as a new player is made for each (the rest of the data class: tests/engine/test_player_profile.gd).


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_a_new_voyager_player_takes_the_runs_supply() -> void:
	var p := PlayerProfile.new_player("Ann", PlayerProfile.Game.VOYAGER)
	assert_str(p.name).is_equal("Ann")
	assert_int(p.tanks).is_equal(PlayerProfile.NEW_SUPPLY)
	assert_int(p.oxygen).is_equal(PlayerProfile.NEW_SUPPLY)
	assert_int(p.ink).is_equal(PlayerProfile.NEW_SUPPLY)             # (the run says how many: 2 tanks, 4 oxygen, 21 pellets under the original's tuning)
	assert_int(p.progress).is_equal(0)
	assert_int(p.tries).is_equal(1)
	assert_int(p.pieces_mask).is_equal(0)
	assert_int(p.hints_unseen).is_equal(0xFFFF)
	assert_bool(p.hints_enabled).is_true()                      # hints are on for Voyager ...
	assert_bool(p.calculator_on).is_true()
	assert_bool(p.customized).is_false()


func test_a_new_expert_player_starts_in_sector_15_with_hints_off() -> void:
	var p := PlayerProfile.new_player("Bob", PlayerProfile.Game.EXPERT)
	assert_int(p.progress).is_equal(0x1E)
	assert_int(p.sector()).is_equal(15)
	assert_bool(p.hints_enabled).is_false()


func test_a_damaged_dictionary_falls_back_to_defaults_and_clamps() -> void:
	var p := PlayerProfile.from_dict({"name": "Dee", "tanks": 99, "ink": "lots", "oxygen": -5, "game": 7, "progress": 100000})
	assert_int(p.tanks).is_equal(99)                                # (the limits are the run's: GameState.begin_run holds a record to them)
	assert_int(p.ink).is_equal(PlayerProfile.NEW_SUPPLY)
	assert_int(p.oxygen).is_equal(1)
	assert_int(p.game).is_equal(1)
	assert_int(p.progress).is_equal(Progression.EXPERT_START)      # (no sector 50000 in Expert: the campaign's start; there is no clamp to 0x3E)


func test_the_math_level_follows_the_zone_until_the_game_is_customized() -> void:
	var p := PlayerProfile.new_player("Eli", PlayerProfile.Game.VOYAGER)
	assert_int(p.effective_edu_level()).is_equal(0)             # zone 1: whole numbers
	p.progress = Progression.with_midpoint(18, false)           # sector 9: zone 4
	assert_int(p.effective_edu_level()).is_equal(1)
	p.customized = true
	p.edu_level = 3
	assert_int(p.effective_edu_level()).is_equal(3)
