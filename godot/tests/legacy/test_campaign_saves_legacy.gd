class_name TestCampaignSavesLegacy
extends GdUnitTestSuite
## (The legacy half: the original's two campaigns and the progress words their files hold; the format rules are in tests/engine/test_campaign_saves.gd.)
## Teaches: a SAVE FORMAT THAT GROWS. Phase F3 changed what a save says about the game: not "game 0 or 1" but the id of a campaign. The
## rules for such a change are tested here: (1) a file of the first release (version 1) loads exactly as it did, written out as a literal
## below so a change of the code cannot change the test; (2) the new thing round-trips through JSON; (3) damaged or out-of-date values are
## mended, never crash and never lose the player's record without a reason. The campaigns are made up (`CampaignShelf`), the files are
## scratch files in `user://`.

const SaveStoreScript := preload("res://src/autoload/save_store.gd")
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const ROSTER := "user://test_campaign_saves_roster.json"
const HALL := "user://test_campaign_saves_hall.json"

## A roster of the first release, byte for byte what it wrote: no `campaign`, no `pieces_total`, `game` 0 / 1, the progress words of the
## original (28 = sector 14 of Voyager; 0x3E = the Expert finale, midpoint flag off; 0x21 = Expert sector 16, flag on).
const V1_ROSTER := """{
	"version": 1,
	"players": [
		{"name": "Ann", "game": 0, "progress": 28, "customized": false, "edu_level": 0, "sound_on": true, "voice_on": true, "music_on": true,
		 "hints_enabled": true, "hints_unseen": 65535, "calculator_on": true, "tanks": 3, "oxygen": 2, "ink": 20, "pieces_mask": 5, "tries": 2},
		{"name": "Bob", "game": 1, "progress": 62, "customized": true, "edu_level": 3, "tanks": 1, "pieces_mask": 0, "tries": 7},
		{"name": "Cy", "game": 1, "progress": 33, "pieces_mask": 3}
	]
}"""
const V1_HALL := """{"version": 1, "entries": [{"name": "Dee", "game": 1, "customized": true, "tries": 4}, {"name": "Eve", "game": 0, "tries": 1}]}"""

var _shelf: CampaignShelf
var _store: Node


func before_test() -> void:
	_cleanup()
	_store = auto_free(SaveStoreScript.new())
	_store.roster_path = ROSTER
	_store.hall_path = HALL


func after_test() -> void:
	if _shelf != null:
		_shelf.remove()
		_shelf = null
	_cleanup()


func _cleanup() -> void:
	for path in [ROSTER, HALL, ROSTER + ".tmp", HALL + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _install(campaigns: Array[Campaign]) -> void:
	_shelf = CampaignShelf.new(campaigns)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _reload() -> Node:
	var fresh: Node = auto_free(SaveStoreScript.new())
	fresh.roster_path = ROSTER
	fresh.hall_path = HALL
	fresh.load_all()
	return fresh


func _file_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_the_original_campaigns_still_write_their_game_number_next_to_the_id() -> void:
	var voyager := PlayerProfile.new_player("Ann", PlayerProfile.Game.VOYAGER).to_dict()
	var expert := PlayerProfile.new_player("Bob", PlayerProfile.Game.EXPERT).to_dict()
	assert_str(voyager["campaign"]).is_equal("voyager")
	assert_int(int(voyager["game"])).is_equal(0)
	assert_str(expert["campaign"]).is_equal("expert")
	assert_int(int(expert["game"])).is_equal(1)
	assert_int(expert["progress"]).is_equal(Progression.EXPERT_START)
	assert_bool(expert["hints_enabled"]).is_false()                    # (Expert's players are experienced: the original's choice)
	var player := PlayerProfile.new()
	player.game = 1                                                   # the old way to choose: still works, and means the id
	assert_str(player.campaign_id).is_equal(&"expert")


func test_an_original_progress_is_checked_against_its_own_campaign_only() -> void:
	# Voyager 0-14 and 30, Expert 15-29 and 31. The old clamp let 0x3E into a Voyager record; now the Voyager list decides.
	assert_int(PlayerProfile.from_dict({"name": "A", "game": 0, "progress": 62}).progress).is_equal(Progression.VOYAGER_START)
	assert_int(PlayerProfile.from_dict({"name": "A", "game": 0, "progress": 60}).progress).is_equal(Progression.VOYAGER_FINALE)
	assert_int(PlayerProfile.from_dict({"name": "A", "game": 1, "progress": 28}).progress).is_equal(Progression.EXPERT_START)
	assert_int(PlayerProfile.from_dict({"name": "A", "game": 1, "progress": 62}).progress).is_equal(Progression.EXPERT_FINALE)
	assert_int(PlayerProfile.from_dict({"name": "A", "game": 1, "progress": 100000}).progress).is_equal(Progression.EXPERT_START)
	for sector in 32:                                                  # every progress word of the original's games survives a round trip
		for flag in 2:
			var progress := sector * 2 + flag
			var game := 1 if sector in range(15, 30) or sector == 31 else 0
			assert_int(PlayerProfile.from_dict({"name": "A", "game": game, "progress": progress}).progress).override_failure_message("progress %d" % progress).is_equal(progress)


# --- the collected pieces of a sector that changed -----------------------------------------------------------------------------



func test_a_version_1_roster_and_hall_of_the_originals_mean_what_they_meant() -> void:
	_write(ROSTER, V1_ROSTER)
	_write(HALL, V1_HALL)
	var fresh := _reload()
	var by_name := {}
	for player: PlayerProfile in fresh.players:
		by_name[player.name] = player
	assert_bool((by_name["Bob"] as PlayerProfile).at_finale()).is_true()          # 62: the Expert finale, midpoint flag off
	assert_int((by_name["Cy"] as PlayerProfile).sector()).is_equal(16)
	assert_bool((by_name["Cy"] as PlayerProfile).past_midpoint()).is_true()
	assert_str(fresh.hall.entries[0].level_text()).is_equal("Expert (c)")
	assert_str(fresh.hall.entries[1].level_text()).is_equal("Voyager")
