class_name TestPackCampaign
extends GdUnitTestSuite
## Teaches: a student's campaign that is nothing but a folder of JSON (a pack in the data form). `test_campaign.gd`
## plays a campaign that is a `.tres` of the project; here the campaign, its three sectors and its finale picture live in a scratch DATA pack in
## `user://` (`PackShelf`: `pack.json`, `campaigns/orchard_pack.json`, `sectors/sector_40..42/*.json` + `.foe`, `pictures/...`), are mounted like a
## player's pack, and are played through the same code: `Catalog` finds them, `PlayerProfile` names the campaign by id, `GameFlow` steps through
## the sectors and ends at the generic finale, and every sector flies in the rules (`SectorScenario`). Unmounting the pack takes everything away again.
##
## The sectors are copies of the dev pack's 0, 1 and finale 180 written by `SectorFactory.copied_script_text` (so their scripts mean the same in the new
## numbers); that is test data built at run time, never committed.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const ID := &"orchard_pack"
const SECTORS := [40, 41]
const FINALE := 42

var _shelf: PackShelf


func before_test() -> void:
	_shelf = PackShelf.new(&"orchard_box")
	_shelf.add_sector_copy(0, 40)
	_shelf.add_sector_copy(1, 41)
	_shelf.add_sector_copy(DevPack.test_sector("e", 0), FINALE)
	_shelf.add_picture("pictures/ui_picture/orchard_finale.png", Color.ORANGE, Vector2i(8, 4))
	# the campaign as a person would write it: only the fields that differ from the defaults, in JSON
	_shelf.write_json("campaigns/%s.json" % ID, {
		"class": "Campaign",
		"id": String(ID),
		"title": "Orchard of Packs",
		"sectors": SECTORS,
		"finales": [FINALE],
		"default_edu_levels": [0, 1],
		"log_unlock_order": [2, 1],
		"finale_log_counts": [2],
		"log_texts": ["Apples.", "Pears."],
		"log_voices": ["", ""],
		"supply_texts": ["Well picked.", "Well picked again."],
		"supply_voices": ["", ""],
		"finale_text": "The orchard is yours.",
		"finale_picture": "orchard_finale",
		"provenance": "test data: copies of dev sectors 0, 1 and 180",
	})
	assert_object(_shelf.mount()).override_failure_message(str(Packs.fallback_reason())).is_not_null()


func after_test() -> void:
	_shelf.remove()
	Audio.stop_voice()


# --- the pack is found ---------------------------------------------------------------------------------------------------------------

func test_the_campaign_is_installed_next_to_the_base_packs_and_has_nothing_wrong() -> void:
	var ids: Array = Catalog.campaigns().map(func(c: Campaign) -> StringName: return c.id)
	assert_bool(ids.has(DevPack.TOUR)).is_true()
	assert_bool(ids.has(ID)).is_true()
	var campaign := Catalog.campaign(ID)
	assert_str(campaign.pack_id).is_equal(&"orchard_box")
	assert_array(campaign.problems()).is_empty()
	assert_array(Catalog.campaign_problems()).is_empty()
	assert_array(Array(campaign.sectors)).is_equal(SECTORS)
	assert_array(Array(campaign.finales)).is_equal([FINALE])
	assert_str(campaign.display_title()).is_equal("Orchard of Packs")
	assert_str(campaign.new_game_label()).is_equal("Orchard of Packs")
	assert_int(campaign.log_count(FINALE)).is_equal(2)
	assert_str(campaign.log_entry_text(1)).is_equal("Apples.")
	assert_str(campaign.supply_message_text(41)).is_equal("Well picked again.")
	assert_str(campaign.finale_message()).is_equal("The orchard is yours.")
	assert_vector(campaign.finale_texture().get_size()).is_equal(Vector2(8, 4))               # the pack's own picture, by its name
	for sector in SECTORS + [FINALE]:
		assert_object(Catalog.campaign_of_sector(sector)).is_same(campaign)
		assert_bool(Catalog.is_original_sector(sector)).is_false()                           # the importer and the fidelity tests never see them
	assert_array(Array(Catalog.campaign(DevPack.TOUR).sectors)).is_equal(DevPack.TOUR_SECTORS)  # the base pack's campaign is what it was


func test_the_sectors_are_the_packs_and_play_like_their_sources() -> void:
	for pair in [[40, 0], [41, 1], [FINALE, DevPack.test_sector("e", 0)]]:
		var from_pack := Catalog.sector(pair[0])
		var source := Catalog.sector(pair[1])
		assert_int(from_pack.index).is_equal(pair[0])
		assert_array(Array(from_pack.foe_bytecode)).override_failure_message("sector %d" % pair[0]).is_equal(Array(source.foe_bytecode))
		assert_int(from_pack.zone).is_equal(source.zone)
		assert_int(from_pack.finale_screen).is_equal(source.finale_screen)
		for m in SectorData.SCREEN_COUNT:
			assert_array(Array(from_pack.screens[m].tiles)).is_equal(Array(source.screens[m].tiles))
		var found := SectorChecks.check(from_pack)
		assert_array(SectorChecks.failures(found)).override_failure_message("sector %d:\n%s" % [pair[0], SectorChecks.text(found)]).is_empty()
	assert_str(Catalog.sector(41).music_name).is_equal(Catalog.sector(1).music_name)
	assert_str(Catalog.campaign(ID).song_for(41)).is_equal(Catalog.campaign(DevPack.TOUR).song_for(1))


func test_the_player_of_the_pack_campaign_finds_it_by_its_id() -> void:
	var campaign := Catalog.campaign(ID)
	var player := PlayerProfile.new_player_in("Pip", campaign)
	assert_str(player.campaign_id).is_equal(ID)
	assert_int(player.progress).is_equal(40 * 2)
	assert_int(player.sector()).is_equal(40)
	assert_object(player.campaign()).is_same(campaign)
	assert_bool(player.is_playable()).is_true()
	Packs.start()                                        # the pack is not in use any more: the save is kept but cannot be played
	assert_object(player.campaign()).is_same(Catalog.default_campaign())                # what a screen draws for a campaign that is not installed
	assert_bool(player.is_playable()).is_false()
	assert_str(player.campaign_id).is_equal(ID)


# --- played ---------------------------------------------------------------------------------------------------------------------------

func test_every_sector_is_flown_by_the_rules_alone() -> void:
	for sector in SECTORS + [FINALE]:
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.reset()
		var scenario := SectorScenario.new(HeadlessStage.new(run), run)
		scenario.play(sector)
		var trace := scenario.trace
		assert_int(trace.events_like("trip_finished 0").size()).override_failure_message("sector %d: the launch" % sector).is_greater_equal(1)     # (and one for each respawn on the station)
		if sector == FINALE:
			assert_array(trace.events_like("finale")).override_failure_message("sector %d: the closing never started" % sector).has_size(1)
			continue
		assert_array(trace.events_like("requested")).override_failure_message("sector %d: no problem" % sector).is_not_empty()
		assert_array(trace.events_like("dissolve_finished")).override_failure_message("sector %d: no tank lost" % sector).is_not_empty()
		assert_array(trace.events_like("dock")).override_failure_message("sector %d: not docked" % sector).has_size(1)
		assert_array(trace.events_like("trip_finished 2")).has_size(1)


func test_the_flow_plays_the_pack_campaign_from_its_first_sector_to_its_finale() -> void:
	var run: Object = auto_free(load(GAME_STATE_SCRIPT).new())
	var campaign := Catalog.campaign(ID)
	var player := PlayerProfile.new_player_in("Tester", campaign)
	player.hints_enabled = false
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
	assert_object(flow.campaign).is_same(campaign)             # the flow asks the player's profile, which asks Catalog: nothing named a pack
	await flow.begin_mission()
	assert_int(stage.sector_index).is_equal(40)
	var path: Array[int] = [player.sector()]
	for step in SECTORS.size():
		await flow.complete_sector()
		path.append(player.sector())
		assert_int(stage.sector_index).is_equal(player.sector())
	assert_array(path).is_equal([40, 41, FINALE])
	assert_bool(player.progress & 1 == 0).is_true()
	log.clear()
	stage.finale_reached.emit()
	assert_str(log[1]).starts_with("closing  at")               # no closing scene of its own: the generic finale
	assert_array(store.hall).is_equal([player])
	flow.leave()


func test_the_end_of_the_pack_campaign_is_the_generic_finale_with_the_packs_picture() -> void:
	var finale: GenericFinale = auto_free(load("res://src/story/generic_finale.tscn").instantiate())
	add_child(finale)
	finale.show_finale(Catalog.campaign(ID))
	assert_str(finale.title_label.text).is_equal("Orchard of Packs")
	assert_str(finale.message_label.text).is_equal("The orchard is yours.")
	assert_vector(finale.picture.texture.get_size()).is_equal(Vector2(8, 4))


# --- and gone ---------------------------------------------------------------------------------------------------------------------------

func test_choosing_another_pack_takes_the_sectors_and_the_campaign_away() -> void:
	assert_bool(Catalog.has_sector(40)).is_true()
	Packs.start()
	assert_object(Catalog.campaign(ID)).is_null()
	assert_bool(Catalog.has_sector(40)).is_false()
	assert_array(Catalog.sector_ids()).not_contains([40, 41, FINALE])
	assert_array(Catalog.sector_ids()).contains(DevPack.TOUR_SECTORS)
	assert_array(Catalog.campaign_problems()).is_empty()
	assert_int(SimWorld.finale_screen(FINALE)).is_equal(-1)
