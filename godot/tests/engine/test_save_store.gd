class_name TestSaveStore
extends GdUnitTestSuite
## Teaches: testing file persistence without touching the player's real save: the store's paths are
## pointed at scratch files in `user://`, and the files are deleted afterwards.

const SaveStoreScript := preload("res://src/autoload/save_store.gd")
const ROSTER := "user://test_roster.json"
const HALL := "user://test_hall.json"

var _store: Node


func before_test() -> void:
	_cleanup()
	_store = auto_free(SaveStoreScript.new())
	_store.roster_path = ROSTER
	_store.hall_path = HALL


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for path in [ROSTER, HALL, ROSTER + ".tmp", HALL + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _reload() -> Node:
	var fresh: Node = auto_free(SaveStoreScript.new())
	fresh.roster_path = ROSTER
	fresh.hall_path = HALL
	fresh.load_all()
	return fresh


func test_a_missing_file_gives_an_empty_roster() -> void:
	_store.load_all()
	assert_int(_store.players.size()).is_equal(0)
	assert_int(_store.hall.entries.size()).is_equal(0)


func test_a_new_player_is_saved_and_survives_a_restart() -> void:
	var p: PlayerProfile = _store.add_player("Ann", 0)
	p.tanks = 5
	p.progress = 9
	_store.save_roster()
	var fresh := _reload()
	assert_int(fresh.players.size()).is_equal(1)
	assert_str(fresh.players[0].name).is_equal("Ann")
	assert_int(fresh.players[0].tanks).is_equal(5)
	assert_int(fresh.players[0].progress).is_equal(9)


func test_names_are_cut_to_eight_characters_and_empty_names_refused() -> void:
	assert_object(_store.add_player("   ", 0)).is_null()
	var long: PlayerProfile = _store.add_player("Bartholomew", 0)
	assert_str(long.name).is_equal("Bartholo")                   # the name box takes eight characters (0x4305ae)


func test_the_roster_is_in_byte_order_upper_case_before_lower_case() -> void:
	for name in ["carl", "Ann", "bea", "Zed", "Bea"]:
		_store.add_player(name, 0)
	# `strcmp` (0x43434c) compares bytes: "Z" (0x5A) comes before "a" (0x61)
	assert_array(_store.players.map(func(p: PlayerProfile) -> String: return p.name)).is_equal(["Ann", "Bea", "Zed", "bea", "carl"])
	assert_array(_reload().players.map(func(p: PlayerProfile) -> String: return p.name)).is_equal(["Ann", "Bea", "Zed", "bea", "carl"])


func test_a_name_may_be_taken_twice_and_the_newcomer_goes_after_the_equal_ones() -> void:
	# `RosterOpenSortedSlot` (0x4307ec) breaks on the first name strictly GREATER; `AddNewPlayer` never checks for duplicates
	var first: PlayerProfile = _store.add_player("Ann", 0)
	var other: PlayerProfile = _store.add_player("Bea", 0)
	var again: PlayerProfile = _store.add_player("Ann", 1)
	var lower: PlayerProfile = _store.add_player("ann", 0)
	assert_array(_store.players).is_equal([first, again, other, lower])
	assert_object(_store.find("Ann")).is_same(first)             # the first of the equal names
	assert_object(_store.find("ANN")).is_null()                   # names are case sensitive
	assert_int(_reload().players.size()).is_equal(4)


func test_a_longer_name_sorts_after_its_prefix() -> void:
	for name in ["Ann B", "Ann", "Ann "]:
		_store.add_player(name, 0)
	assert_array(_store.players.map(func(p: PlayerProfile) -> String: return p.name)).is_equal(["Ann", "Ann ", "Ann B"])


func test_a_nine_character_name_of_an_older_save_still_loads() -> void:
	var file := FileAccess.open(ROSTER, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "players": [{"name": "Christoph", "tanks": 3}]}))
	file.close()
	var fresh := _reload()
	assert_str(fresh.players[0].name).is_equal("Christoph")      # the record's name field holds nine characters
	var hall := FileAccess.open(HALL, FileAccess.WRITE)
	hall.store_string(JSON.stringify({"version": 1, "entries": [{"name": "Christoph", "game": 0, "tries": 2}]}))
	hall.close()
	assert_str(_reload().hall.entries[0].name).is_equal("Christoph")


func test_a_failed_write_is_reported_and_the_data_stays_in_memory() -> void:
	# the original's `write_users_dat` / `write_hof_dat` show the "Write Error" dialog when the file cannot be written;
	# a folder that does not exist makes `FileAccess.open` fail without any test hook
	_store.roster_path = "user://no_such_folder/roster.json"
	var failed: Array[String] = []
	_store.write_failed.connect(func(path: String) -> void: failed.append(path))
	var player: PlayerProfile = _store.add_player("Ann", 0)
	assert_object(player).is_not_null()
	assert_array(_store.players).contains_exactly([player])
	assert_array(failed).is_equal(["user://no_such_folder/roster.json"])
	assert_bool(_store.save_roster()).is_false()
	assert_int(failed.size()).is_equal(2)


func test_a_player_can_be_deleted_for_good() -> void:
	var p: PlayerProfile = _store.add_player("Ann", 0)
	_store.add_player("Bea", 0)
	_store.remove_player(p)
	var fresh := _reload()
	assert_int(fresh.players.size()).is_equal(1)
	assert_str(fresh.players[0].name).is_equal("Bea")


func test_the_roster_holds_99_players_and_no_more() -> void:
	for i in 99:
		assert_object(_store.add_player("P%d" % i, 0)).is_not_null()
	assert_bool(_store.is_full()).is_true()
	assert_object(_store.add_player("One more", 0)).is_null()
	assert_int(_reload().players.size()).is_equal(99)


func test_corrupt_json_gives_an_empty_roster_instead_of_a_crash() -> void:
	var file := FileAccess.open(ROSTER, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var fresh := _reload()
	assert_int(fresh.players.size()).is_equal(0)


func test_a_wrong_shape_or_bad_entries_are_ignored() -> void:
	var file := FileAccess.open(ROSTER, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "players": [5, {"name": ""}, {"name": "Ok", "tanks": 3}, {"name": "ok"}]}))
	file.close()
	var fresh := _reload()
	assert_int(fresh.players.size()).is_equal(2)                 # (no duplicate check, as in the original)
	assert_int(fresh.players[0].tanks).is_equal(3)
	file = FileAccess.open(ROSTER, FileAccess.WRITE)
	file.store_string("[1, 2, 3]")
	file.close()
	assert_int(_reload().players.size()).is_equal(0)


func test_the_hall_of_fame_is_saved_with_the_roster() -> void:
	var p: PlayerProfile = _store.add_player_in("Ann", Catalog.campaign(DevPack.TOUR))
	p.tries = 3
	_store.add_to_hall(p)
	var fresh := _reload()
	assert_int(fresh.hall.entries.size()).is_equal(1)
	assert_int(fresh.hall.entries[0].tries).is_equal(3)
	assert_str(fresh.hall.entries[0].campaign_id).is_equal(DevPack.TOUR)


func test_the_winner_leaves_the_roster_for_the_hall_of_fame() -> void:
	# `add_player_to_hall` (0x4315ac) -> `RemoveRosterSlot` (0x42f6eb) -> `SaveRosterData`: memory and both files
	var ann: PlayerProfile = _store.add_player("Ann", 0)
	_store.add_player("Bea", 0)
	_store.add_to_hall(ann)
	assert_int(_store.players.size()).is_equal(1)
	assert_str(_store.players[0].name).is_equal("Bea")
	var fresh := _reload()
	assert_int(fresh.players.size()).is_equal(1)
	assert_str(fresh.players[0].name).is_equal("Bea")
	assert_int(fresh.hall.entries.size()).is_equal(1)


func test_a_new_record_copies_the_switches_it_is_given() -> void:
	# `AddNewPlayer` (0x430851): SoundOn / MusicOn / VoiceOn at that moment
	var p: PlayerProfile = _store.add_player("Ann", 0, false, true, false)
	assert_bool(p.sound_on).is_false()
	assert_bool(p.music_on).is_true()
	assert_bool(p.voice_on).is_false()
	assert_bool(_reload().players[0].voice_on).is_false()


func test_changes_are_announced_with_a_signal() -> void:
	var count := [0]
	_store.roster_changed.connect(func() -> void: count[0] += 1)
	_store.add_player("Ann", 0)
	assert_int(count[0]).is_equal(1)


func test_the_write_error_dialog_has_the_packs_title_and_text() -> void:
	var queue := MessageQueue.new(GameClock)
	var message: MessageQueue.Message = _store.post_write_error(queue)
	assert_str(message.title).is_equal(Catalog.text(&"disk_write_failed_title"))
	assert_str(message.body).is_equal(Catalog.text(&"disk_write_failed_text"))
	assert_int(message.buttons.size()).is_equal(1)
	queue.close_current(0)
