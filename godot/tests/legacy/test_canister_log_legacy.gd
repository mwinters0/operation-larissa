class_name TestCanisterLogLegacy
extends GdUnitTestSuite
## The ORIGINAL's log: its two games of 15 entries, the unlock order and the menu captions of the legacy pack. Teaches: testing a rule table. `CanisterLog` is pure data and arithmetic, so every claim about the
## original's unlock order and menu layout is a one-line assertion. The numbers are the bytes of
## ONWIN32.EXE (`PrepareCanisterLog` 0x41e787, tables 0x4419d5 / 0x4419e4 / 0x4419f4 / 0x441a34).


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_each_game_unlocks_all_15_entries_exactly_once() -> void:
	for game in 2:
		var order: Array = Array(Catalog.campaign_for_game(game).log_unlock_order)
		order.sort()
		assert_array(order).is_equal(range(1, 16))


func test_a_sector_lists_sector_mod_15_plus_one_entries() -> void:
	assert_int(CanisterLog.count(0)).is_equal(1)
	assert_int(CanisterLog.count(14)).is_equal(15)
	assert_int(CanisterLog.count(15)).is_equal(1)           # the first sector of Expert starts again
	assert_int(CanisterLog.count(29)).is_equal(15)
	assert_int(CanisterLog.count(30)).is_equal(1)           # the finales count as 0 and 1 of their game
	assert_int(CanisterLog.count(31)).is_equal(2)


func test_the_campaign_of_a_sector() -> void:
	for sector in [0, 14, 30]:
		assert_str(CanisterLog.campaign_of(sector).id).is_equal(&"voyager")
	for sector in [15, 29, 31]:
		assert_str(CanisterLog.campaign_of(sector).id).is_equal(&"expert")


func test_the_newest_entry_is_not_simply_the_sector_number() -> void:
	assert_int(CanisterLog.newest(0)).is_equal(4)            # sector 0 delivers ENTRY 1.04
	assert_int(CanisterLog.newest(1)).is_equal(3)
	assert_int(CanisterLog.newest(14)).is_equal(13)
	assert_int(CanisterLog.newest(15)).is_equal(2)           # Expert: ENTRY 2.02 first
	assert_int(CanisterLog.newest(29)).is_equal(12)
	assert_int(CanisterLog.newest(31)).is_equal(7)


func test_the_list_is_sorted_and_opens_on_the_newest_entry() -> void:
	assert_array(Array(CanisterLog.entries(0))).is_equal([4])
	assert_array(Array(CanisterLog.entries(2))).is_equal([3, 4, 7])
	assert_int(CanisterLog.initial_row(2)).is_equal(2)       # 7 is the newest and the last of the sorted three
	assert_array(Array(CanisterLog.entries(3))).is_equal([1, 3, 4, 7])
	assert_int(CanisterLog.initial_row(3)).is_equal(0)       # the newest, 1, sorts first
	assert_array(Array(CanisterLog.entries(14))).is_equal(range(1, 16))
	assert_int(CanisterLog.initial_row(14)).is_equal(12)     # 13 is the 13th entry
	assert_array(Array(CanisterLog.entries(31))).is_equal([2, 7])
	assert_int(CanisterLog.initial_row(31)).is_equal(1)


func test_every_entry_of_a_sector_comes_from_the_same_game() -> void:
	for sector in 30:
		var campaign := CanisterLog.campaign_of(sector)
		assert_int(CanisterLog.entries(sector).size()).is_equal(CanisterLog.count(sector))
		assert_bool(CanisterLog.entries(sector).has(CanisterLog.newest(sector))).is_true()
		assert_str(CanisterLog.text_name(campaign, CanisterLog.newest(sector))).starts_with("log_entry_")
		assert_str(campaign.log_voice_name(CanisterLog.newest(sector))).starts_with("log_")


func test_the_caption_patches_game_and_number_into_the_template() -> void:
	assert_str(CanisterLog.label("ENTRY", Catalog.campaign_for_game(0), 4)).is_equal("ENTRY 1.04")
	assert_str(CanisterLog.label("ENTRY", Catalog.campaign_for_game(1), 15)).is_equal("ENTRY 2.15")


func test_the_entry_text_and_speech_index_match_the_caption() -> void:
	var expert := Catalog.campaign_for_game(1)
	var text := Catalog.text(CanisterLog.text_name(expert, 7))
	assert_str(text).starts_with("ENTRY 2.07")
	assert_str(expert.log_voice_name(7)).is_equal(&"log_21")


func test_the_canister_problem_carries_the_sectors_entry() -> void:
	var problem := ProblemFactory.for_canister(Catalog.sector(0), 0)
	assert_int(problem.log_index).is_equal(3)                # ENTRY 1.04: its number - 1
	assert_int(problem.log_sector).is_equal(0)
	assert_str(problem.success).starts_with("ENTRY 1.04")
	var expert := ProblemFactory.for_canister(Catalog.sector(16), 0)
	assert_int(expert.log_index).is_equal(6)                 # sector 16 = 2nd of Expert: ENTRY 2.07
	assert_str(expert.success).starts_with("ENTRY 2.07")
