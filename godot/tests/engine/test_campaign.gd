class_name TestCampaign
extends GdUnitTestSuite
## Teaches: a campaign is DATA: a list of sectors with a finale, its own log, levels and words, and everything that used to assume "15 sectors and a
## finale at 30" asks the `Campaign` instead. The pack's campaigns are checked as a whole (sound, no sector in two), and a made-up campaign of four
## sectors in a strange order with its own finale is run through the same functions and through `GameFlow`. (The original's two campaigns against
## the old formulas: tests/legacy/test_campaign_legacy.gd.)

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"

## A four-sector campaign that is nothing like the tour: sectors in a strange order (dev's sectors 3, 1, 2, 0), a finale that is one of the tour's (4), two
## educational levels, its own log of four entries (names of the registry) and no closing scene of its own.
func _tiny() -> Campaign:
	var tiny := Campaign.new()
	tiny.id = &"tiny"
	tiny.title = "Tiny"
	tiny.sectors = PackedInt32Array([3, 1, 2, 0])
	tiny.finales = PackedInt32Array([4])
	tiny.default_edu_levels = PackedInt32Array([1, 3])
	tiny.log_series = 7
	tiny.log_unlock_order = PackedInt32Array([3, 1, 4, 2])
	tiny.finale_log_counts = PackedInt32Array([2])
	tiny.log_texts = [&"log_entry_0", &"log_entry_1", &"log_entry_2", &"log_entry_3"]
	tiny.log_voices = [&"log_0", &"log_1", &"log_2", &"log_3"]
	tiny.supply_texts = [&"supply_message_5", &"supply_message_6", &"supply_message_7", &"supply_message_8"]
	tiny.supply_voices = [&"supply_5", &"supply_6", &"supply_7", &"supply_8"]
	return tiny


# --- the data itself ------------------------------------------------------------------------------------------------------

func test_the_campaigns_are_sound_and_share_no_sector() -> void:
	assert_array(Catalog.campaign_problems()).override_failure_message("\n".join(Catalog.campaign_problems())).is_empty()


func test_the_campaigns_say_where_their_numbers_come_from() -> void:
	for campaign in Catalog.campaigns():
		assert_str(campaign.provenance).is_not_empty()


func test_a_made_up_campaign_is_sound() -> void:
	assert_array(_tiny().problems()).is_empty()


func test_the_problems_of_a_broken_campaign_are_named() -> void:
	var broken := _tiny()
	broken.sectors = PackedInt32Array([2, 2, 4])
	broken.log_unlock_order = PackedInt32Array([1, 1, 3, 4])
	broken.default_edu_levels = PackedInt32Array([5])
	var text := "\n".join(broken.problems())
	assert_str(text).contains("sector 2 is listed twice").contains("both a sector to play and a finale") \
			.contains("each entry number 1 to 4 exactly once").contains("an educational level is 0 to 3").contains("3 sectors but 4 supply texts")


func test_the_sectors_come_in_the_campaigns_order_and_the_game_ends_at_its_finale() -> void:
	var tiny := _tiny()
	assert_int(tiny.start_progress()).is_equal(6)                       # the first sector, 3, times two
	assert_int(tiny.sector_count()).is_equal(4)
	var progress := tiny.start_progress()
	var visited: Array[int] = []
	for step in 6:
		visited.append(progress >> 1)
		progress = tiny.next_progress(progress | 1)             # (the midpoint flag is cleared on the way)
	assert_array(visited).is_equal([3, 1, 2, 0, 4, 4])
	assert_bool(tiny.is_finale(4)).is_true()
	assert_bool(tiny.is_finale(0)).is_false()
	assert_int(Progression.next_progress(2 * 2, tiny)).is_equal(2 * 0)
	assert_bool(Progression.is_finale(2 * 4, tiny)).is_true()
	assert_bool(Progression.is_finale(2 * 14, tiny)).is_false()                 # 14 is nothing special to this campaign
	assert_int(tiny.position_of(2) + 1).is_equal(3)


func test_a_campaign_without_a_finale_stays_on_its_last_sector() -> void:
	var open_ended := _tiny()
	open_ended.finales = PackedInt32Array()
	open_ended.finale_log_counts = PackedInt32Array()
	assert_int(open_ended.next_progress(2 * 0)).is_equal(2 * 0)


func test_the_levels_the_log_and_the_messages_are_the_campaigns_own() -> void:
	var tiny := _tiny()
	assert_int(tiny.default_edu_level(0)).is_equal(1)
	assert_int(tiny.default_edu_level(1)).is_equal(3)
	assert_int(tiny.default_edu_level(6)).is_equal(3)                          # beyond the list: the last
	assert_int(CanisterLog.count(2, tiny)).is_equal(3)
	assert_int(CanisterLog.newest(2, tiny)).is_equal(4)                        # the third of [3, 1, 4, 2]
	assert_array(Array(CanisterLog.entries(2, tiny))).is_equal([1, 3, 4])
	assert_int(CanisterLog.initial_row(2, tiny)).is_equal(2)
	assert_int(CanisterLog.count(4, tiny)).is_equal(2)                         # the finale lists what its data says
	assert_int(CanisterLog.count(7, tiny)).is_equal(0)                         # a sector of no such campaign lists nothing
	assert_str(CanisterLog.label("ENTRY", tiny, 4)).is_equal("ENTRY 7.04")
	assert_str(tiny.supply_text_name(1)).is_equal(&"supply_message_6")           # the second sector of the list
	assert_str(tiny.supply_text_name(4)).is_equal(&"")
	assert_str(tiny.display_title()).is_equal("Tiny")
	assert_str(tiny.new_game_label()).is_equal("Tiny")


func test_the_song_comes_from_the_sector_and_falls_back_to_the_campaigns() -> void:
	var tiny := _tiny()
	tiny.fallback_song = &"sector_song_5"
	assert_str(tiny.song_for(2)).is_equal(AudioService.music_for_sector(2))      # sector 2 names its own song
	var edited := Catalog.sector(1)
	var kept := edited.music_name
	edited.music_name = "no_such_song"
	assert_str(tiny.song_for(1)).is_equal(&"sector_song_5")
	edited.music_name = kept


func test_the_flow_plays_a_made_up_campaign_from_its_first_sector_to_its_finale() -> void:
	var run: Object = auto_free(load(GAME_STATE_SCRIPT).new())
	var player := PlayerProfile.new_player("Tester", PlayerProfile.Game.VOYAGER)
	player.hints_enabled = false
	player.progress = 3 * 2
	run.profile = player
	var log: Array = []
	var store := FakeSaveStore.new()
	store.watched = player
	var stage := HeadlessStage.new(run)
	stage.log = log
	var view := FakeFlowView.new(log, run)
	var flow := GameFlow.new(run, store, MessageQueue.new(StubClock.new()))
	flow.world = stage
	flow.view = view
	flow.defer_call = func(action: Callable) -> void: pass
	flow.enter(0, 0)
	flow.campaign = _tiny()                                  # the player's own campaign is the pack's first; this test plays another
	await flow.begin_mission()
	var path: Array[int] = [player.sector()]
	for step in 4:
		await flow.complete_sector()
		path.append(player.sector())
		assert_int(stage.sector_index).is_equal(player.sector())                # the next sector of the list was started
	assert_array(path).is_equal([3, 1, 2, 0, 4])
	assert_bool(player.progress & 1 == 0).is_true()
	# the finale of this campaign: the sub reaches the treasure on the sector's finale screen, the closing is asked for by campaign
	log.clear()
	stage.finale_reached.emit()
	assert_str(log[1]).starts_with("closing  at")                          # (no closing scene of its own: the generic finale)
	assert_array(store.hall).is_equal([player])
	flow.leave()


func test_the_hud_says_final_where_the_campaign_has_its_finale() -> void:
	var layout := Catalog.hud_layout()
	var words := HudLabels.new()
	var tiny := _tiny()
	assert_object(layout.sector_texture(tiny.position_of(4), tiny.is_finale(4))).is_same(layout.sector_final_texture)
	assert_str(words.sector_word(tiny.position_of(4), tiny.is_finale(4))).is_equal("Final")
	assert_object(layout.sector_texture(tiny.position_of(2), tiny.is_finale(2))).is_same(layout.sector_textures[2])     # the third sector of the list
	assert_str(words.sector_word(tiny.position_of(30), tiny.is_finale(30))).is_equal("First")                            # a sector it does not list is nothing special here


# --- the pack's own campaigns ---------------------------------------------------------------------------------------------------

func test_every_song_and_speech_group_a_campaign_names_exists() -> void:
	var missing: Array[String] = []
	var groups: Dictionary = Catalog.voice_cues().groups
	for campaign in Catalog.campaigns():
		for voice in campaign.log_voices + campaign.supply_voices:
			if voice != &"" and not groups.has(String(voice)):
				missing.append("%s: no speech group called '%s'" % [campaign.id, voice])
		if MusicCatalog.id_of(campaign.fallback_song) < 0:
			missing.append("%s: no song called '%s'" % [campaign.id, campaign.fallback_song])
	assert_array(missing).override_failure_message("\n".join(missing)).is_empty()


func test_the_chosen_pack_starts_with_its_first_campaign_which_is_what_a_new_player_gets() -> void:
	var first := Catalog.default_campaign()
	assert_object(first).is_same(Catalog.campaigns()[0])
	assert_str(first.id).is_equal(DevPack.TOUR)
	assert_str(Catalog.default_campaign_id()).is_equal(DevPack.TOUR)
	assert_object(Catalog.campaign(&"nothing")).is_null()
	# an old save's game number names a campaign the pack may not have: then the first one stands in for it
	assert_object(Catalog.campaign_for_game(PlayerProfile.Game.VOYAGER)).is_same(first)
	assert_object(Catalog.campaign_for_game(PlayerProfile.Game.EXPERT)).is_same(first)
	assert_int(Catalog.game_of_campaign(first.id)).is_equal(-1)                   # (and the tour has no number of the old kind)
	var profile := PlayerProfile.new_player("Ann", PlayerProfile.Game.EXPERT)
	assert_str(profile.campaign_id).is_equal(first.id)
	assert_int(profile.progress).is_equal(first.start_progress())
	assert_object(profile.campaign()).is_same(first)
	assert_int(profile.sector()).is_equal(first.sectors[0])
	assert_int(profile.zone()).is_equal(0)
	profile.progress = first.finales[0] * 2
	assert_bool(profile.at_finale()).is_true()
	assert_int(profile.zone()).is_equal(Catalog.sector(DevPack.TOUR_FINALE).zone)
	assert_str(HallEntry.from_profile(profile).campaign().id).is_equal(first.id)
