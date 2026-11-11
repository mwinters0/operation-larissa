class_name TestCampaignLegacy
extends GdUnitTestSuite
## Teaches: replacing constants by data WITHOUT changing a single answer. The original knows "Voyager" and "Expert" as the numbers
## 15, 30 and 31 scattered through its code. Here those are the two `Campaign` resources
## in `data/campaigns/`. This test keeps the OLD formulas, copied here as they were, and compares them with what the campaigns answer for every
## sector 0-31 (and every progress word): if the data and the old code ever disagree, the failure names the sector.
##
## (The campaign resource's own rules, on a made-up campaign and on the pack in use: tests/engine/test_campaign.gd.)

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


## The tables the old code read are the EXE's (LogUnlockOrderVoyager 0x4419d5, LogUnlockOrderExpert 0x4419e4, the zones' default levels) and are the importer's
## `extracted/tables/databank.json` and `zone_defaults.json`.
static func _table(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://../extracted/tables/%s.json" % name))


## The unlock order of the log entries of `game` (0 Voyager, 1 Expert).
static func _old_unlock_order(game: int) -> Array:
	return _table("databank")["unlock_order_voyager" if game == 0 else "unlock_order_expert"].map(func(number: float) -> int: return int(number))


## The default educational level of `zone` (0-4) of `game`: the table holds Voyager's five zones and then Expert's.
static func _old_edu_level(game: int, zone: int) -> int:
	return int(_table("zone_defaults").default_edu_level[game * 5 + zone])


## The old code, verbatim in meaning (the sources are in the git history of progression.gd, canister_log.gd, audio.gd and
## surface_ship_screen.gd).
static func _old_game_of(sector: int) -> int:
	return sector - 30 if sector >= 30 else floori(sector / 15.0)


static func _old_zone_of(progress: int) -> int:
	var sector := progress >> 1
	if sector >= 30:
		return 5 + sector - 30
	return floori((progress % 30) / 6.0)


static func _old_next_progress(progress: int) -> int:
	var sector := progress >> 1
	if sector >= 30:
		return progress & ~1
	if sector == 14:
		return 0x3C
	if sector == 29:
		return 0x3E
	return (sector + 1) * 2


static func _old_music(sector: int) -> StringName:
	if sector >= 30:
		return &"finale"
	return StringName("sector_song_%d" % (posmod(sector, 6) + 1))


func test_the_originals_are_two_campaigns_voyager_then_expert() -> void:
	var ids: Array = Catalog.campaigns().map(func(each: Campaign) -> Variant: return each.id)
	assert_array(ids.slice(0, 2)).is_equal([&"voyager", &"expert"])
	assert_object(Catalog.campaign(&"expert")).is_same(Catalog.campaigns()[1])
	assert_object(Catalog.campaign(&"nothing")).is_null()
	assert_array(Catalog.ORIGINAL_CAMPAIGNS).is_equal([&"voyager", &"expert"])


func test_every_name_a_campaign_uses_is_a_name_of_the_registry_and_has_its_string_or_speech() -> void:
	var missing: Array[String] = []
	var groups: Dictionary = Catalog.voice_cues().groups
	for id in Catalog.ORIGINAL_CAMPAIGNS:                    # (a campaign of a designer's own may use its own words and no voices)
		var campaign := Catalog.campaign(id)
		var texts: Array[StringName] = []
		texts.append_array(campaign.log_texts)
		texts.append_array(campaign.supply_texts)
		texts.append(campaign.title_text)
		texts.append(campaign.new_game_text)
		for text_name in texts:
			if text_name != &"" and not Catalog.has_text(text_name):
				missing.append("%s: no string called '%s'" % [campaign.id, text_name])
		for voice in campaign.log_voices + campaign.supply_voices:
			if not groups.has(String(voice)):
				missing.append("%s: no speech group called '%s'" % [campaign.id, voice])
		if MusicCatalog.id_of(campaign.fallback_song) < 0:
			missing.append("%s: no song called '%s'" % [campaign.id, campaign.fallback_song])
	assert_array(missing).override_failure_message("\n".join(missing)).is_empty()


func test_the_default_levels_are_the_table_in_zones_tres() -> void:
	var zones := Catalog.zones()
	for zone in 5:
		assert_int(Catalog.campaign(&"voyager").default_edu_levels[zone]).is_equal(zones.zones[zone].default_edu_level_voyager)
		assert_int(Catalog.campaign(&"expert").default_edu_levels[zone]).is_equal(zones.zones[zone].default_edu_level_expert)


# --- the old formulas against the campaigns -------------------------------------------------------------------------------

func test_sector_membership_matches_the_old_game_of() -> void:
	for sector in 32:
		var campaign := Catalog.campaign_of_sector(sector)
		assert_object(campaign).is_not_null()
		assert_int(Catalog.game_of_campaign(campaign.id)).override_failure_message("sector %d" % sector).is_equal(_old_game_of(sector))
		assert_bool(campaign.is_finale(sector)).override_failure_message("sector %d" % sector).is_equal(sector >= 30)
		assert_int(Progression.game_of(sector * 2 + 1)).is_equal(_old_game_of(sector))
		assert_int(Catalog.sector(sector).game).is_equal(_old_game_of(sector))        # the sector's own field agrees


func test_every_progress_word_matches_the_old_zone_finale_and_next_progress() -> void:
	for progress in range(0, 0x40):
		var sector := progress >> 1
		assert_int(Progression.zone_of(progress)).override_failure_message("progress %d" % progress).is_equal(_old_zone_of(progress))
		assert_bool(Progression.is_finale(progress)).override_failure_message("progress %d" % progress).is_equal(sector >= 30)
		assert_int(Progression.next_progress(progress)).override_failure_message("progress %d" % progress).is_equal(_old_next_progress(progress))
		assert_int(Catalog.campaign_of_sector(sector).zone_of(sector)).is_equal(Catalog.sector(sector).zone)


func test_a_new_player_starts_where_the_old_constants_said() -> void:
	assert_int(Progression.start_progress(0)).is_equal(Progression.VOYAGER_START)
	assert_int(Progression.start_progress(1)).is_equal(Progression.EXPERT_START)
	assert_int(Catalog.campaign(&"voyager").finales[0] * 2).is_equal(Progression.VOYAGER_FINALE)
	assert_int(Catalog.campaign(&"expert").finales[0] * 2).is_equal(Progression.EXPERT_FINALE)


func test_default_levels_match_the_old_table_for_every_zone() -> void:
	for game in 2:
		for zone in 7:
			assert_int(Progression.default_edu_level(game, zone)).override_failure_message("game %d zone %d" % [game, zone]) \
					.is_equal(_old_edu_level(game, mini(zone, 4)))


func test_the_canister_log_matches_the_old_tables_for_every_sector() -> void:
	for sector in 32:
		var game := _old_game_of(sector)
		var count := sector % 15 + 1
		var order: Array = _old_unlock_order(game)
		assert_int(CanisterLog.count(sector)).override_failure_message("sector %d" % sector).is_equal(count)
		assert_int(CanisterLog.newest(sector)).override_failure_message("sector %d" % sector).is_equal(order[count - 1])
		var sorted: Array = order.slice(0, count)
		sorted.sort()
		assert_array(Array(CanisterLog.entries(sector))).override_failure_message("sector %d" % sector).is_equal(sorted)
		var campaign := CanisterLog.campaign_of(sector)
		var number := CanisterLog.newest(sector)
		assert_str(campaign.log_text_name(number)).is_equal("log_entry_%d" % (game * 15 + number - 1))
		assert_str(campaign.log_voice_name(number)).is_equal("log_%d" % (game * 15 + number - 1))
		assert_int(campaign.log_series).is_equal(game + 1)


func test_the_songs_match_the_old_rule_for_every_sector() -> void:
	for sector in 32:
		assert_str(AudioService.music_for_sector(sector)).override_failure_message("sector %d" % sector).is_equal(_old_music(sector))


func test_the_supply_messages_match_the_old_numbering_for_the_30_sectors() -> void:
	var cues := Catalog.voice_cues()
	for sector in 30:
		var campaign := Catalog.campaign_of_sector(sector)
		assert_str(campaign.supply_text_name(sector)).is_equal("supply_message_%d" % sector)
		assert_str(SurfaceShipScreen.supply_message(sector)).is_equal(Catalog.text(StringName("supply_message_%d" % sector)).strip_edges())
		assert_array(cues.clips(String(campaign.supply_voice_name(sector)))).is_equal(cues.clips("supply_%d" % sector))
	for finale in [30, 31]:
		assert_str(SurfaceShipScreen.supply_message(finale)).is_empty()              # (the game ends there: no message)


func test_the_hud_picture_and_the_names_follow_the_campaign() -> void:
	for sector in 32:
		assert_int(Catalog.campaign_of_sector(sector).banner_index).is_equal(Catalog.sector(sector).game)
	assert_str(Catalog.campaign(&"voyager").display_title()).is_equal(Catalog.text(&"game_voyager"))
	assert_str(Catalog.campaign(&"expert").new_game_label()).is_equal(Catalog.text(&"expert_game_button"))
	assert_str(Catalog.campaign(&"voyager").closing_scene).is_equal(&"voyager")
	assert_str(Catalog.campaign(&"expert").closing_scene).is_equal(&"expert")


func test_the_finale_screens_are_a_field_of_the_sector() -> void:
	for sector in 32:
		var expected := 2 if sector == 30 else (10 if sector == 31 else -1)
		assert_int(Catalog.sector(sector).finale_screen).override_failure_message("sector %d" % sector).is_equal(expected)
		assert_int(SimWorld.finale_screen(sector)).is_equal(expected)


func test_a_profile_finds_its_campaign_through_one_accessor() -> void:
	var voyager := PlayerProfile.new_player("Ann", PlayerProfile.Game.VOYAGER)
	var expert := PlayerProfile.new_player("Bob", PlayerProfile.Game.EXPERT)
	assert_str(voyager.campaign().id).is_equal(&"voyager")
	assert_str(expert.campaign().id).is_equal(&"expert")
	assert_int(expert.sector()).is_equal(15)
	assert_int(expert.zone()).is_equal(0)
	expert.progress = Progression.EXPERT_FINALE
	assert_bool(expert.at_finale()).is_true()
	assert_int(expert.zone()).is_equal(6)
	assert_str(HallEntry.from_profile(expert).campaign().id).is_equal(&"expert")


# --- a campaign that is nothing like the originals ----------------------------------------------------------------------------

