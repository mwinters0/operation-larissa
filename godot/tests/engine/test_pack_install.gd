class_name TestPackInstall
extends GdUnitTestSuite
## Teaches: "a student campaign installs as a separate pack", in the chain of packs. A campaign is built (copies of
## the dev pack's sectors, as `test_pack_campaign.gd` does), EXPORTED to a folder (laid over the pack in use), taken away completely, INSTALLED into
## `user://packs/<id>/`, CHOSEN (`Packs.choose`, what `--pack=<id>` does) and played through `GameFlow` from its first sector to its generic finale; then the game
## "restarts" (`Packs.start` with the option, as `main.gd` calls it) and the campaign is back, and choosing the pack the suite runs on and uninstalling takes it away again.
## Installing never changes which pack the game uses. The installed pack is in the real `user://packs/` under an id no one else uses.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const ID := &"harvest_box"                    # the campaign's id and (by default) the pack's
const SOURCE := &"harvest_scratch"            # the scratch pack the campaign is built in
const SECTORS := [60, 61]
const FINALE := 62
const SETTINGS := "user://test_pack_install_settings.cfg"      # (the machine settings file: a scratch one, so a test never writes the player's)
const EXPORTS := "user://test_pack_install_exports"
const TONE_SHORT := "res://tests/fixtures/pack_tone_short.ogg.bin"
const PROJECT_PACK := &"zz_install_probe"      # a pack folder the test makes in `res://packs/` for a moment (the project's own packs are no installs)

var _old_settings_path: String
var _shelf: PackShelf
var _more: Array[PackShelf] = []


func before_test() -> void:
	_old_settings_path = MachineSettings.settings_path
	MachineSettings.settings_path = SETTINGS
	Packs.start()
	_clean()


func after_test() -> void:
	if _shelf != null:
		_shelf.remove()
		_shelf = null
	for shelf in _more:
		shelf.remove()
	_more.clear()
	_clean()
	Packs.start()                                      # (after the installed packs are gone: the default choice would be one of them)
	MachineSettings.settings_path = _old_settings_path
	Audio.stop_voice()


func _clean() -> void:
	PackFiles.remove_tree("res://packs/%s" % PROJECT_PACK)
	for id in [ID, &"harvest_two", &"harvest_bad", &"harvest_zip", &"harvest_arc"]:
		PackFiles.remove_tree("%s/%s" % [PackInstall.DIR, id])
		DirAccess.remove_absolute("%s/%s.%s" % [PackInstall.DIR, id, Pack.FILE_EXTENSION])
	PackFiles.remove_tree(EXPORTS)
	DirAccess.remove_absolute(SETTINGS)


## The scratch pack `SOURCE` with the campaign `ID` of the sectors 60, 61 and the finale 62 (copies of dev's 0, 1 and 180), used. As a person would write it.
func _build_campaign(pack_id: StringName = SOURCE, campaign_id: StringName = ID, first := 60, mount := true) -> PackShelf:
	var shelf := PackShelf.new(pack_id)
	shelf.add_sector_copy(0, first)
	shelf.add_sector_copy(1, first + 1)
	shelf.add_sector_copy(DevPack.test_sector("e", 0), first + 2)
	shelf.add_picture("pictures/ui_picture/harvest_finale.png", Color.ORANGE, Vector2i(8, 4))
	shelf.write_json("campaigns/%s.json" % campaign_id, {
		"class": "Campaign", "id": String(campaign_id), "title": "Harvest Moon", "sectors": [first, first + 1], "finales": [first + 2],
		"default_edu_levels": [0, 1], "log_unlock_order": [2, 1], "finale_log_counts": [2], "log_texts": ["Apples.", "Pears."], "log_voices": ["", ""],
		"supply_texts": ["Well picked.", "Well picked again."], "supply_voices": ["", ""], "finale_text": "The harvest is in.", "finale_picture": "harvest_finale",
	})
	if mount:
		assert_object(shelf.mount()).override_failure_message(str(Packs.fallback_reason())).is_not_null()
	return shelf


func _quick() -> PackExport.Options:
	var options := PackExport.Options.new()
	options.reach = false
	return options


func _export_and_forget() -> String:
	_shelf = _build_campaign()
	var result := PackExport.campaign(ID, EXPORTS, _quick())
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	_shelf.remove()                                                     # the student's scratch pack is gone: nothing of the campaign is left in the game
	_shelf = null
	assert_object(Catalog.campaign(ID)).is_null()
	assert_bool(Catalog.has_sector(60)).is_false()
	return result.path


# --- the done-when: export, install, choose, play to the finale ---------------------------------------------------------------------

func test_a_student_campaign_installs_as_a_separate_pack_and_is_played_to_its_finale() -> void:
	var exported := _export_and_forget()
	# 1. install: a copy in user://packs/<id>/, laid over the pack that was in use; the game does not use it yet
	var installed := PackInstall.install(exported)
	assert_bool(installed.ok).override_failure_message(installed.message).is_true()
	assert_str(installed.path).is_equal("user://packs/%s" % ID)
	assert_bool(FileAccess.file_exists("user://packs/%s/pack.json" % ID)).is_true()
	assert_bool(Packs.in_chain(ID)).is_false()
	assert_object(Catalog.campaign(ID)).is_null()
	var listed := PackChoice.entry(ID)
	assert_object(listed).is_not_null()
	assert_bool(listed.in_use()).is_false()
	assert_str(listed.pack.title).is_equal("Harvest Moon")
	assert_str(listed.pack.base).is_equal(PackShelf.base_id())
	# 2. choose it, as `--pack=harvest_box` does
	Packs.start(PackedStringArray(["--pack=" + String(ID)]))
	assert_array(Packs.chain_ids()).is_equal([ID, PackShelf.base_id()])
	assert_object(Packs.fallback_reason()).is_null()
	assert_bool(PackChoice.entry(ID).in_use()).is_true()
	var report := PackCheck.run(Packs.chosen(), PackChoice.check_options())
	assert_bool(report.passes()).override_failure_message(report.text()).is_true()
	# 3. the campaign is in the new-player dialog, among the others
	var dialog: NewPlayerDialog = auto_free(load("res://src/ui/new_player_dialog.tscn").instantiate())
	add_child(dialog)
	var captions: Array = []
	for child in dialog.voyager_button.get_parent().get_children():
		if child is Button:
			captions.append((child as Button).text)
	assert_array(captions).contains(["Harvest Moon"])
	assert_int(captions.size()).is_equal(Catalog.campaigns().size())
	# 4. play it: sign in a player of it and walk the flow from its first sector to the finale
	var campaign := Catalog.campaign(ID)
	assert_str(campaign.pack_id).is_equal(ID)
	assert_array(campaign.problems()).is_empty()
	var run: Object = auto_free(load(GAME_STATE_SCRIPT).new())
	var player := PlayerProfile.new_player_in("Tester", campaign)
	player.hints_enabled = false
	run.profile = player
	var log: Array = []
	var store := FakeSaveStore.new()
	store.watched = player
	var stage := HeadlessStage.new(run)
	stage.log = log
	var flow := GameFlow.new(run, store, MessageQueue.new(StubClock.new()))
	flow.world = stage
	flow.view = FakeFlowView.new(log, run)
	flow.defer_call = func(action: Callable) -> void: pass
	flow.enter(0, 0)
	assert_object(flow.campaign).is_same(campaign)
	await flow.begin_mission()
	assert_int(stage.sector_index).is_equal(SECTORS[0])
	var path: Array[int] = [player.sector()]
	for step in SECTORS.size():
		await flow.complete_sector()
		path.append(player.sector())
		assert_int(stage.sector_index).is_equal(player.sector())
	assert_array(path).is_equal([60, 61, FINALE])
	log.clear()
	stage.finale_reached.emit()
	assert_str(log[1]).starts_with("closing  at")                       # no closing scene of its own: the generic finale, then the Hall of Fame
	assert_array(store.hall).is_equal([player])
	flow.leave()
	# every sector of it also flies in the rules alone
	for sector in SECTORS + [FINALE]:
		var scenario_run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		scenario_run.reset()
		var scenario := SectorScenario.new(HeadlessStage.new(scenario_run), scenario_run)
		scenario.play(sector)
		assert_int(scenario.trace.events_like("trip_finished 0").size()).override_failure_message("sector %d: the launch" % sector).is_greater_equal(1)     # (and one for each respawn on the station)
	# 5. the game restarts without the option: the pack the suite runs on, alone (installing never chose anything), and with the option the campaign is back
	Packs.start()
	assert_object(Catalog.campaign(ID)).is_null()
	Packs.start(PackedStringArray(["--pack=" + String(ID)]))
	assert_str(Catalog.campaign(ID).display_title()).is_equal("Harvest Moon")
	# 6. another pack is chosen: the campaign goes, the record of a player of it stays (unplayable)
	Packs.start()
	assert_object(Catalog.campaign(ID)).is_null()
	assert_bool(player.is_playable()).is_false()
	# 7. uninstall: gone from user://packs/
	assert_str(PackInstall.uninstall(ID)).is_empty()
	assert_bool(DirAccess.dir_exists_absolute("user://packs/%s" % ID)).is_false()
	assert_object(PackChoice.entry(ID)).is_null()


func test_uninstalling_the_pack_in_use_chooses_again() -> void:
	var exported := _export_and_forget()
	assert_bool(PackInstall.install(exported).ok).is_true()
	Packs.choose(ID)
	assert_bool(Packs.in_chain(ID)).is_true()
	assert_str(PackInstall.uninstall(ID)).is_empty()
	assert_bool(Packs.in_chain(ID)).is_false()                                # (the choice made again: the same id asked for is not there now, so dev stands in)
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.NOT_FOUND)


func test_the_machine_settings_no_longer_keep_a_list_of_packs() -> void:
	var config := ConfigFile.new()
	config.set_value("packs", "enabled", PackedStringArray(["harvest_box"]))           # what an earlier version wrote
	config.set_value("ONWINCD", "Collision", false)
	config.save(SETTINGS)
	MachineSettings.load_settings()
	assert_bool(MachineSettings.collision_enabled).is_false()
	assert_int(MachineSettings.save_settings()).is_equal(OK)
	config = ConfigFile.new()
	config.load(SETTINGS)
	assert_bool(config.has_section("packs")).is_false()
	assert_bool(config.get_value("ONWINCD", "Collision")).is_false()           # the original's own setting is still there
	MachineSettings.collision_enabled = true


# --- installing -------------------------------------------------------------------------------------------------------------------------

func test_a_pack_file_installs_as_a_file_and_is_read_in_place() -> void:
	_shelf = _build_campaign()
	var options := _quick()
	options.archive = true
	options.pack_id = &"harvest_zip"
	var result := PackExport.campaign(ID, EXPORTS, options)
	assert_bool(result.ok()).override_failure_message(result.text()).is_true()
	_shelf.remove()
	_shelf = null
	var installed := PackInstall.install(result.path)
	assert_bool(installed.ok).override_failure_message(installed.message).is_true()
	assert_str(installed.id).is_equal(&"harvest_zip")
	assert_str(installed.path).is_equal("%s/harvest_zip.larissa" % PackInstall.DIR)
	assert_bool(FileAccess.file_exists(installed.path)).is_true()
	assert_bool(DirAccess.dir_exists_absolute("%s/harvest_zip" % PackInstall.DIR)).override_failure_message("a pack file is copied, never extracted").is_false()
	assert_bool(Packs.choose(&"harvest_zip")).is_true()
	assert_bool(Packs.chosen().is_archive()).is_true()
	assert_object(Catalog.campaign(ID)).is_not_null()
	assert_str(PackInstall.uninstall(&"harvest_zip")).is_empty()
	assert_bool(FileAccess.file_exists(installed.path)).is_false()
	assert_bool(Packs.in_chain(&"harvest_zip")).is_false()


func test_what_is_not_a_pack_is_not_installed() -> void:
	assert_bool(PackInstall.install("user://no_such_thing").ok).is_false()
	DirAccess.make_dir_recursive_absolute(EXPORTS + "/empty")
	var result := PackInstall.install(EXPORTS + "/empty")
	assert_bool(result.ok).is_false()
	assert_str(result.message).contains("not a pack")
	# a Godot archive is not a pack
	FileAccess.open(EXPORTS + "/harvest_bad.pck", FileAccess.WRITE).store_string("x")
	assert_str(PackInstall.install(EXPORTS + "/harvest_bad.pck").message).contains("not a folder or a .larissa pack file")
	assert_bool(FileAccess.file_exists("user://packs/harvest_bad.pck")).is_false()
	assert_str(PackInstall.uninstall(&"never_installed")).contains("is not installed")


func test_the_ids_of_the_projects_own_packs_are_not_installed() -> void:
	# dev is a pack of the project here, like any other id that is a folder of `res://packs/`: it would win over a copy in `user://packs/` (a project with no dev takes the installed one)
	DirAccess.make_dir_recursive_absolute(EXPORTS + "/fake_dev")
	FileAccess.open(EXPORTS + "/fake_dev/pack.json", FileAccess.WRITE).store_string(JSON.stringify({"id": "dev", "title": "Fake", "version": "1", "base": "ghost"}))
	var result := PackInstall.install(EXPORTS + "/fake_dev")
	assert_bool(result.ok).is_false()
	assert_str(result.message).contains("the project itself has a pack called 'dev'")
	assert_bool(DirAccess.dir_exists_absolute("%s/dev" % PackInstall.DIR)).is_false()
	var project_pack := "res://packs/%s" % PROJECT_PACK
	PackFiles.write_text(project_pack + "/pack.json", JSON.stringify({"id": String(PROJECT_PACK), "title": "Project pack", "version": "1"}))
	DirAccess.make_dir_recursive_absolute(EXPORTS + "/fake_project")
	FileAccess.open(EXPORTS + "/fake_project/pack.json", FileAccess.WRITE).store_string(JSON.stringify({"id": String(PROJECT_PACK), "title": "Fake", "version": "1", "base": "dev"}))
	var message := PackInstall.install(EXPORTS + "/fake_project").message
	PackFiles.remove_tree(project_pack)
	assert_str(message).contains("the project itself has a pack called '%s'" % PROJECT_PACK)


func test_uninstall_only_ever_touches_a_pack_folder_of_user_packs() -> void:
	var outside := "user://harvest_outside"
	DirAccess.make_dir_recursive_absolute(outside)
	FileAccess.open(outside + "/keep.txt", FileAccess.WRITE).store_string("mine")
	for bad in ["../harvest_outside", "../../x", "a/b", "", "Upper"]:
		assert_str(PackInstall.uninstall(StringName(bad))).contains("not a pack id")
	assert_bool(FileAccess.file_exists(outside + "/keep.txt")).is_true()
	PackFiles.remove_tree(outside)


func test_a_pack_in_use_can_be_installed_over_and_the_game_looks_at_the_new_copy() -> void:
	var exported := _export_and_forget()
	assert_bool(PackInstall.install(exported).ok).is_true()
	Packs.choose(ID)
	var before := Packs.chosen()
	assert_bool(PackInstall.install(exported).ok).is_true()
	assert_bool(Packs.in_chain(ID)).is_true()
	assert_object(Packs.chosen()).is_not_same(before)                          # the chain was made again from the files


# --- using a pack is not checking it -----------------------------------------------------------------------------------------------

func test_the_check_of_the_pack_screen_finds_the_errors_of_an_installed_pack() -> void:
	var exported := _export_and_forget()
	assert_bool(PackInstall.install(exported).ok).is_true()
	FileAccess.open("user://packs/%s/sectors/sector_61/sector_61.foe" % ID, FileAccess.WRITE).store_string("not a creature script\n")
	var report := PackCheck.run(PackCheck.open(String(ID)), PackChoice.check_options())
	assert_bool(report.passes()).is_false()
	assert_bool(report.errors().any(func(f: PackReport.Finding) -> bool: return f.area == "sector 61")).is_true()
	assert_bool(Packs.in_chain(ID)).is_false()                                 # (checking leaves the chain alone)
	assert_bool(PackChoice.entry(ID).in_use()).is_false()


func test_a_pack_whose_base_is_gone_is_chosen_with_dev_under_it_and_a_reason() -> void:
	var exported := _export_and_forget()
	assert_bool(PackInstall.install(exported).ok).is_true()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://packs/%s/pack.json" % ID))
	manifest["base"] = "ghost_pack"
	FileAccess.open("user://packs/%s/pack.json" % ID, FileAccess.WRITE).store_string(JSON.stringify(manifest))
	assert_bool(Packs.choose(ID)).is_false()
	assert_array(Packs.chain_ids()).is_equal([ID, Packs.DEV])
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.MISSING_BASE)
	assert_str(Packs.fallback_reason().detail).is_equal("ghost_pack")
	assert_bool(PackChoice.entry(ID).in_use()).is_true()
	assert_str(PackChoice.summary()).contains("ghost_pack")
