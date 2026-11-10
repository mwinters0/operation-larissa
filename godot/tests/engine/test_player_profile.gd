class_name TestPlayerProfile
extends GdUnitTestSuite
## Teaches: testing a data class: defaults, a save/load round trip and forgiving loading.


func test_a_new_player_has_the_defaults_and_starts_at_the_first_sector_of_the_packs_first_campaign() -> void:
	var first := Catalog.default_campaign()
	var p := PlayerProfile.new_player("Ann", PlayerProfile.Game.VOYAGER)
	assert_str(p.name).is_equal("Ann")
	assert_str(p.campaign_id).is_equal(first.id)
	assert_int(p.progress).is_equal(first.start_progress())
	assert_int(p.sector()).is_equal(first.sectors[0])
	assert_int(p.tanks).is_equal(PlayerProfile.NEW_SUPPLY)
	assert_int(p.oxygen).is_equal(PlayerProfile.NEW_SUPPLY)
	assert_int(p.ink).is_equal(PlayerProfile.NEW_SUPPLY)                    # (the run says how many: test_tuning.gd)
	assert_int(p.tries).is_equal(1)
	assert_int(p.pieces_mask).is_equal(0)
	assert_int(p.hints_unseen).is_equal(0xFFFF)
	assert_bool(p.hints_enabled).is_true()
	assert_bool(p.calculator_on).is_true()
	assert_bool(p.customized).is_false()
	assert_str(PlayerProfile.new().campaign_id).is_equal(first.id)           # even a blank record names a campaign that is there
	assert_str(HallEntry.new().campaign_id).is_equal(first.id)


func test_a_player_of_a_campaign_starts_where_it_starts() -> void:
	var tour := Catalog.campaign(DevPack.TOUR)
	var p := PlayerProfile.new_player_in("Bob", tour)
	assert_str(p.campaign_id).is_equal(DevPack.TOUR)
	assert_int(p.progress).is_equal(tour.sectors[0] * 2)
	assert_bool(p.hints_enabled).is_true()


func test_names_are_cut_to_eight_characters_and_leading_blanks_dropped() -> void:
	assert_str(PlayerProfile.clean_name("  Christopher Columbus ")).is_equal("Christop")
	assert_str(PlayerProfile.clean_name("   ")).is_equal("")
	assert_str(PlayerProfile.clean_name("Ann ")).is_equal("Ann ")                 # trailing blanks are kept, as typed
	assert_str(PlayerProfile.clean_name("Christopher", PlayerProfile.NAME_FIELD_MAX)).is_equal("Christoph")


func test_the_name_box_rules_of_the_original() -> void:
	# EnterNewPlayerNameDialog (0x4305ae): at most 8 characters, the first one upper case, no blank first,
	# control characters ignored
	assert_int(PlayerProfile.NAME_MAX).is_equal(8)
	assert_str(PlayerProfile.typed_name("christopher")).is_equal("Christop")
	assert_str(PlayerProfile.typed_name("ann marie")).is_equal("Ann marie".left(8))
	assert_str(PlayerProfile.typed_name("   bob")).is_equal("Bob")                 # blanks before the first character are refused
	assert_str(PlayerProfile.typed_name("a\tb\nc")).is_equal("Abc")               # controls ignored
	assert_str(PlayerProfile.typed_name("zed")).is_equal("Zed")
	assert_str(PlayerProfile.typed_name("aBC")).is_equal("ABC")                    # only the first character is changed
	assert_str(PlayerProfile.typed_name("9lives")).is_equal("9lives")
	assert_str(PlayerProfile.typed_name("\u00e9cole")).is_equal("\u00e9cole")       # toupper in the C locale leaves it alone
	assert_str(PlayerProfile.typed_name("a\u20acb")).is_equal("Ab")                # above 0xFF no key exists
	assert_str(PlayerProfile.typed_name("Ann ")).is_equal("Ann ")                  # a trailing blank is typed text too
	assert_str(PlayerProfile.typed_name("a       b")).is_equal("A       ")         # eight characters, blanks count
	assert_str(PlayerProfile.typed_name("")).is_equal("")


func test_round_trip_through_a_dictionary_and_json() -> void:
	var p := PlayerProfile.new_player("Cleo", PlayerProfile.Game.EXPERT)
	p.progress = Progression.with_midpoint(DevPack.TOUR_SECTORS[2] * 2, true)       # sector 2, past its midpoint
	p.customized = true
	p.edu_level = 2
	p.tanks = 5
	p.oxygen = 3
	p.ink = 7
	p.pieces_mask = 0b1011
	p.tries = 4
	p.hints_unseen = 0xFF0F
	p.music_on = false
	var json := JSON.stringify(p.to_dict())                     # all the way to text and back: numbers become floats
	var back := PlayerProfile.from_dict(JSON.parse_string(json))
	assert_dict(back.to_dict()).is_equal(p.to_dict())


func test_an_entry_without_a_name_is_dropped() -> void:
	assert_object(PlayerProfile.from_dict({"tanks": 3})).is_null()
	assert_object(PlayerProfile.from_dict({"name": "   "})).is_null()




func test_a_damaged_dictionary_falls_back_to_defaults_and_clamps() -> void:
	var first := Catalog.default_campaign()
	var p := PlayerProfile.from_dict({"name": "Dee", "tanks": 99, "ink": "lots", "oxygen": -5, "campaign": String(first.id), "progress": 100000})
	assert_int(p.tanks).is_equal(99)                                # (the limits are the run's: GameState.begin_run holds a record to them, test_tuning.gd)
	assert_int(p.ink).is_equal(PlayerProfile.NEW_SUPPLY)
	assert_int(p.oxygen).is_equal(1)
	assert_int(p.game).is_equal(-1)                                # (the tour has no number of the old kind)
	assert_int(p.progress).is_equal(first.start_progress())        # no such sector in the campaign: its start


func test_the_math_level_follows_the_zone_until_the_game_is_customized() -> void:
	var p := PlayerProfile.new_player("Eli", PlayerProfile.Game.VOYAGER)
	assert_int(p.effective_edu_level()).is_equal(0)             # the tour's first zone: level 0
	p.progress = Progression.with_midpoint(DevPack.TOUR_SECTORS[3] * 2, false)           # sector 3: zone 3, level 2 in the tour's own list
	assert_int(p.effective_edu_level()).is_equal(2)
	p.customized = true
	p.edu_level = 3
	assert_int(p.effective_edu_level()).is_equal(3)
