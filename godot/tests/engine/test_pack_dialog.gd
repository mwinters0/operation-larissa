class_name TestPackDialog
extends GdUnitTestSuite
## Teaches: the player-facing side of packs. The pack screen lists what `PackChoice` knows (every pack found, which of them the game
## uses, and why) and calls the same functions the tests of `test_pack_install.gd` call; it is reached from the sign-in screen by the P key, and a small "Packs"
## button appears there only once a pack is installed in the player's folder, so a game with no pack installed looks as the original did (the screen's four
## buttons are untouched either way). There is nothing to switch on: the game uses the pack `--pack=<id>` names, else the first pack found. Checking a pack shows
## its report, and a pack with an error says why. No pack asks for trust: nothing a pack holds runs.

const SIGN_IN_SCENE := "res://src/ui/sign_in.tscn"
const ID := &"harvest_box"
const ROSTER := "user://test_pack_dialog_roster.json"
const HALL := "user://test_pack_dialog_hall.json"
const EXPORTS := "user://test_pack_dialog_exports"

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]
var _shelves: Array[PackShelf] = []
var _baseline: int                                  ## how many packs the screen lists before the test installs any (the game's own: more or less, whatever is on disk)


func before_test() -> void:
	_old_roster = SaveStore.roster_path
	_old_hall = SaveStore.hall_path
	_old_players = SaveStore.players.duplicate()
	SaveStore.roster_path = ROSTER
	SaveStore.hall_path = HALL
	SaveStore.players = []
	SceneRouter.dry_run = true
	SignIn.welcome_enabled = false
	SignIn.prompt_when_empty = false
	Packs.start()
	_clean()
	_baseline = PackChoice.entries().size()


func after_test() -> void:
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	_clean()
	Packs.start()
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SceneRouter.dry_run = false
	SignIn.welcome_enabled = true
	SignIn.prompt_when_empty = true
	Audio.stop_voice()


func _clean() -> void:
	PackFiles.remove_tree("%s/%s" % [PackInstall.DIR, ID])
	PackFiles.remove_tree(EXPORTS)
	for path in [ROSTER, HALL]:
		DirAccess.remove_absolute(path)


## A campaign pack `ID` (copies of the dev pack's sectors 0, 1, 180 as 60, 61, 62) installed in `user://packs/`, laid over the pack the suite runs on (not chosen).
func _install_harvest() -> void:
	var shelf := PackShelf.new(ID)
	_shelves.append(shelf)
	shelf.add_sector_copy(0, 60)
	shelf.add_sector_copy(1, 61)
	shelf.add_sector_copy(DevPack.test_sector("e", 0), 62)
	shelf.write_json("pack.json", {"id": String(ID), "title": "Harvest Moon", "version": "1.2", "author": "Pip", "description": "A pack of apples.",
			"base": String(PackShelf.base_id())})
	shelf.write_json("campaigns/%s.json" % ID, {
		"class": "Campaign", "id": String(ID), "title": "Harvest Moon", "sectors": [60, 61], "finales": [62], "default_edu_levels": [0, 1],
		"log_unlock_order": [2, 1], "finale_log_counts": [2], "log_texts": ["Apples.", "Pears."], "log_voices": ["", ""],
		"supply_texts": ["Well picked.", "Well picked again."], "supply_voices": ["", ""], "finale_text": "The harvest is in.",
	})
	var result := PackInstall.install(shelf.root)
	assert_bool(result.ok).override_failure_message(result.message).is_true()


func _screen() -> SignIn:
	var screen := scene_runner(SIGN_IN_SCENE).scene() as SignIn
	screen.quits_program = false
	return screen


func _open(screen: SignIn) -> PackDialog:
	screen.show_packs()
	var dialog := screen.overlay.get_child(0) as PackDialog
	assert_object(dialog).is_not_null()
	return dialog


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


# --- reaching it ----------------------------------------------------------------------------------------------------------------

func test_with_no_installed_pack_the_sign_in_screen_is_unchanged_and_the_p_key_still_opens_the_pack_screen() -> void:
	var screen := _screen()
	assert_bool(screen.packs_button.visible).is_false()
	assert_int(screen.practice_button.get_parent().get_child_count()).is_equal(4)         # Start, New, Practice, Exit: untouched
	screen._unhandled_key_input(_key(KEY_P))
	assert_int(screen.overlay.get_child_count()).is_equal(1)
	var dialog := screen.overlay.get_child(0) as PackDialog
	assert_int(dialog.entry_count()).is_equal(_baseline)                                  # the project's own packs, whichever are on disk
	dialog.select(PackShelf.base_id())
	assert_str(dialog.selected_id()).is_equal(PackShelf.base_id())
	assert_str(dialog.tree.get_selected().get_text(2)).is_equal("in use")
	assert_str(dialog.intro.text).contains("In use: " + PackShelf.base_id()).contains("Chosen with --pack=" + PackShelf.base_id())
	assert_bool(dialog.check_button.disabled).is_false()
	assert_bool(dialog.remove_button.disabled).is_true()                                  # (a pack of the project cannot be removed)
	assert_str(dialog.folder_label.text).contains("packs")
	# Escape closes it and the list is the screen's again
	dialog._unhandled_key_input(_key(KEY_ESCAPE))
	await await_idle_frame()
	assert_int(screen.overlay.get_child_count()).is_equal(0)


func test_an_installed_pack_makes_the_small_button_appear_and_it_opens_the_same_screen() -> void:
	_install_harvest()
	var screen := _screen()
	assert_bool(screen.packs_button.visible).is_true()
	assert_bool(screen.packs_button.get_global_rect().intersects(screen.start_button.get_global_rect())).is_false()      # (it covers none of the screen's buttons)
	assert_bool(Rect2(Vector2.ZERO, Vector2(640, 400)).encloses(screen.packs_button.get_global_rect())).is_true()
	screen.packs_button.pressed.emit()
	assert_int(screen.overlay.get_child_count()).is_equal(1)
	screen.show_packs()                                                                    # (a dialog is open: no second one)
	assert_int(screen.overlay.get_child_count()).is_equal(1)


func test_the_screen_shows_the_chain_in_use_and_why() -> void:
	_install_harvest()
	var screen := _screen()
	var dialog := _open(screen)
	assert_int(dialog.entry_count()).is_equal(_baseline + 1)
	assert_str(dialog.intro.text).contains("In use: " + PackShelf.base_id())
	Packs.start(PackedStringArray(["--pack=" + String(ID)]))
	dialog.refresh()
	assert_str(dialog.intro.text).contains("In use: harvest_box > " + PackShelf.base_id()).contains("--pack=harvest_box")
	dialog.select(ID)
	assert_str(dialog.tree.get_selected().get_text(2)).is_equal("in use")
	assert_str(dialog.details.text).contains("In use (the chosen pack)").contains("laid over the pack '%s'" % PackShelf.base_id())
	dialog.select(PackShelf.base_id())
	assert_str(dialog.tree.get_selected().get_text(2)).is_equal("base")
	Packs.start(PackedStringArray(["--pack=nope"]))
	dialog.refresh()
	assert_str(dialog.intro.text).contains("There is no pack 'nope'").contains("dev")


func test_an_installed_dev_is_left_out_when_the_project_has_its_own_and_the_screen_says_so() -> void:
	PackFiles.write_text("%s/dev/pack.json" % PackInstall.DIR, JSON.stringify({"id": "dev", "title": "Installed dev", "version": "1"}))
	Packs.forget_dev()
	Packs.dev()                                                                              # (looks for dev again: the project's wins, the installed one is noted)
	var screen := _screen()
	var dialog := _open(screen)
	var text := dialog.intro.text
	PackFiles.remove_tree("%s/dev" % PackInstall.DIR)
	Packs.forget_dev()
	assert_str(text).contains("user://packs/dev").contains("dev is res://packs/dev").contains("left out")


# --- using it -------------------------------------------------------------------------------------------------------------------

func test_the_records_of_a_campaign_are_playable_only_while_its_pack_is_in_use() -> void:
	_install_harvest()
	var screen := _screen()
	var player := PlayerProfile.new_player_in("Pip", Catalog.campaign_for_game(0))
	player.campaign_id = ID                                                                 # a record of the pack's campaign, made while the pack was in use
	player.progress = 60 * 2
	SaveStore.players = [player]
	screen.refresh()
	assert_str(screen.tree.get_selected().get_text(3)).is_equal("not installed")
	assert_bool(screen.start_button.disabled).is_true()
	var dialog := _open(screen)
	assert_int(dialog.entry_count()).is_equal(_baseline + 1)
	dialog.select(ID)
	assert_str(dialog.tree.get_selected().get_text(0)).is_equal("Harvest Moon")
	assert_str(dialog.tree.get_selected().get_text(1)).is_equal("installed")
	assert_str(dialog.tree.get_selected().get_text(2)).is_empty()
	assert_str(dialog.details.text).contains("version 1.2 by Pip").contains("A pack of apples.").contains("holds 1 campaign, 3 sectors")
	Packs.choose(ID)                                                                        # (what `--pack=harvest_box` does at the start of the game)
	screen.refresh()
	assert_bool(screen.start_button.disabled).override_failure_message("the record is playable now").is_false()
	assert_str(screen.tree.get_selected().get_text(3)).is_equal("1 of 2")
	Packs.start()
	screen.refresh()
	assert_bool(screen.start_button.disabled).is_true()
	assert_bool(Catalog.campaigns().any(func(c: Campaign) -> bool: return c.id == ID)).is_false()


func test_checking_a_pack_shows_its_report_and_a_pack_with_an_error_says_why() -> void:
	_install_harvest()
	var screen := _screen()
	var dialog := _open(screen)
	dialog.select(ID)
	dialog.check_button.pressed.emit()
	assert_str(dialog.details.text).contains("passes the check")
	assert_bool(Packs.in_chain(ID)).override_failure_message("checking uses nothing").is_false()
	FileAccess.open("user://packs/%s/sectors/sector_61/sector_61.foe" % ID, FileAccess.WRITE).store_string("not a creature script\n")
	dialog.check()
	assert_str(dialog.details.text).contains("has errors").contains("sector 61")
	assert_array(Packs.chain_ids()).is_equal([PackShelf.base_id()])


func test_installing_from_a_path_selects_the_pack_and_a_bad_path_says_so() -> void:
	var source := EXPORTS + "/source"                                        # (a plain folder: a shelf would be found as a pack by itself)
	PackFiles.write_text(source + "/pack.json", JSON.stringify({"id": String(ID), "title": "Harvest Moon", "version": "1", "base": String(PackShelf.base_id())}))
	PackFiles.write_text(source + "/texts.json", JSON.stringify({"harvest_hello": "Hello."}))
	var screen := _screen()
	var dialog := _open(screen)
	dialog.install_from("user://no_such_pack_anywhere")
	assert_str(dialog.details.text).contains("Not installed")
	assert_int(dialog.entry_count()).is_equal(_baseline)
	dialog.install_from(source)
	assert_int(dialog.entry_count()).is_equal(_baseline + 1)
	assert_str(dialog.selected_id()).is_equal(ID)
	assert_str(dialog.details.text).contains("installed 'harvest_box'")
	assert_bool(Packs.in_chain(ID)).is_false()                                              # installing chooses nothing
	assert_bool(dialog.remove_button.disabled).is_false()                                   # a pack of the player's own can be removed
	# Remove asks once
	dialog.remove_button.pressed.emit()
	assert_str(dialog.remove_button.text).is_equal("Really remove")
	assert_bool(DirAccess.dir_exists_absolute("user://packs/%s" % ID)).is_true()
	dialog.remove_button.pressed.emit()
	assert_bool(DirAccess.dir_exists_absolute("user://packs/%s" % ID)).is_false()
	assert_int(dialog.entry_count()).is_equal(_baseline)
