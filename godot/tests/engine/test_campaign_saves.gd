class_name TestCampaignSaves
extends GdUnitTestSuite
## Teaches: a SAVE FORMAT THAT GROWS. Phase F3 changed what a save says about the game: not "game 0 or 1" but the id of a campaign. The
## rules for such a change are tested here: (1) a file of the first release (version 1) loads exactly as it did, written out as a literal
## below so a change of the code cannot change the test (it names the original's campaigns by id, which a pack need not have: such a record is KEPT); (2) the new thing round-trips through JSON; (3) damaged or out-of-date values are
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


# --- a campaign that is not the original's ------------------------------------------------------------------------------------

func test_a_player_of_another_campaign_survives_json_and_asks_that_campaign() -> void:
	_install([CampaignShelf.garden()])
	var player := PlayerProfile.new_player_in("Gus", Catalog.campaign(&"garden"))
	assert_int(player.progress).is_equal(350)                         # the campaign's first sector, 175, times two
	assert_bool(player.hints_enabled).is_true()
	player.progress = 176 * 2 + 1                                     # sector 176, past its midpoint
	player.pieces_mask = 0b101
	assert_int(player.game).is_equal(-1)                              # the original's numbering has no such game
	var data := player.to_dict()
	assert_str(data["campaign"]).is_equal("garden")
	assert_bool(data.has("game")).is_false()
	var back := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(data)))
	assert_dict(back.to_dict()).is_equal(data)
	assert_str(back.campaign_id).is_equal(&"garden")
	assert_object(back.campaign()).is_same(Catalog.campaign(&"garden"))
	assert_bool(back.is_playable()).is_true()
	assert_int(back.progress).is_equal(353)                           # the number is the campaign's own
	assert_int(back.sector()).is_equal(176)
	assert_bool(back.past_midpoint()).is_true()
	assert_str(back.campaign_title()).is_equal("Garden of Tests")


func test_the_roster_of_another_campaign_is_saved_loaded_and_the_winner_enters_the_hall() -> void:
	_install([CampaignShelf.garden()])
	var player: PlayerProfile = _store.add_player_in("Gus", Catalog.campaign(&"garden"))
	player.progress = 177 * 2                                         # the campaign's finale
	player.customized = true
	_store.save_roster()
	var fresh := _reload()
	assert_int(fresh.players.size()).is_equal(1)
	assert_str(fresh.players[0].campaign_id).is_equal(&"garden")
	assert_int(fresh.players[0].progress).is_equal(354)
	assert_bool(fresh.players[0].at_finale()).is_true()
	fresh.add_to_hall(fresh.players[0])
	var again := _reload()
	assert_array(again.players).is_empty()
	assert_int(again.hall.entries.size()).is_equal(1)
	assert_str(again.hall.entries[0].campaign_id).is_equal(&"garden")
	assert_str(again.hall.entries[0].level_text()).is_equal("Garden of Tests " + Catalog.text(&"customized_marker"))
	assert_int(int(_file_json(HALL)["version"])).is_equal(SaveStoreScript.FORMAT_VERSION)


# --- a file of the first release ----------------------------------------------------------------------------------------------

func test_a_version_1_roster_loads_with_every_game_and_progress_as_it_meant() -> void:
	_write(ROSTER, V1_ROSTER)
	var fresh := _reload()
	var by_name := {}
	for player: PlayerProfile in fresh.players:
		by_name[player.name] = player
	assert_int(by_name.size()).is_equal(3)
	var ann: PlayerProfile = by_name["Ann"]
	assert_str(ann.campaign_id).is_equal(&"voyager")
	assert_int(ann.game).is_equal(0)
	assert_int(ann.progress).is_equal(28)
	assert_int(ann.pieces_mask).is_equal(5)
	assert_int(ann.pieces_total).is_equal(0)                          # (not known: the first release did not write it)
	assert_int(ann.tanks).is_equal(3)
	assert_int(ann.tries).is_equal(2)
	var bob: PlayerProfile = by_name["Bob"]
	assert_str(bob.campaign_id).is_equal(&"expert")
	assert_int(bob.progress).is_equal(62)                               # the progress word, kept as the file had it (the campaign is not installed to check it)
	assert_bool(bob.customized).is_true()
	assert_int(bob.edu_level).is_equal(3)
	var cy: PlayerProfile = by_name["Cy"]
	assert_str(cy.campaign_id).is_equal(&"expert")
	assert_int(cy.progress).is_equal(33)
	assert_bool(cy.past_midpoint()).is_true()
	assert_int(cy.sector()).is_equal(16)
	assert_bool(cy.hints_enabled).is_false()                          # (missing: Expert's default)
	assert_bool(ann.hints_enabled).is_true()


func test_a_version_1_file_is_written_back_as_version_2_with_the_campaign_added() -> void:
	_write(ROSTER, V1_ROSTER)
	_write(HALL, V1_HALL)
	var fresh := _reload()
	assert_bool(fresh.save_roster()).is_true()
	assert_bool(fresh.save_hall()).is_true()
	var roster := _file_json(ROSTER)
	assert_int(int(roster["version"])).is_equal(2)
	var rows: Array = roster["players"]
	var names: Array = rows.map(func(row: Dictionary) -> Variant: return row["name"])
	assert_array(names).is_equal(["Ann", "Bob", "Cy"])
	assert_str(rows[0]["campaign"]).is_equal("voyager")
	assert_int(int(rows[0]["game"])).is_equal(0)
	assert_int(int(rows[0]["progress"])).is_equal(28)
	assert_str(rows[1]["campaign"]).is_equal("expert")
	assert_int(int(rows[1]["progress"])).is_equal(62)
	var hall := _file_json(HALL)
	assert_int(int(hall["version"])).is_equal(2)
	assert_str(hall["entries"][0]["campaign"]).is_equal("expert")
	assert_str(hall["entries"][1]["campaign"]).is_equal("voyager")
	# and the rewritten files read back to the same players
	var third := _reload()
	assert_array(third.players.map(func(p: PlayerProfile) -> Variant: return p.to_dict())).is_equal(fresh.players.map(func(p: PlayerProfile) -> Variant: return p.to_dict()))


func test_a_version_1_hall_of_fame_loads_with_its_games() -> void:
	_write(HALL, V1_HALL)
	var fresh := _reload()
	assert_int(fresh.hall.entries.size()).is_equal(2)
	assert_str(fresh.hall.entries[0].campaign_id).is_equal(&"expert")
	assert_int(fresh.hall.entries[0].game).is_equal(1)
	assert_str(fresh.hall.entries[0].level_text()).is_equal("expert " + Catalog.text(&"customized_marker"))     # (a campaign that is not installed shows its id)
	assert_int(fresh.hall.entries[0].tries).is_equal(4)
	assert_str(fresh.hall.entries[1].level_text()).is_equal("voyager")


func test_a_row_without_a_campaign_takes_it_from_game_and_a_silly_game_is_clamped_as_before() -> void:
	assert_str(PlayerProfile.from_dict({"name": "A", "game": 1}).campaign_id).is_equal(&"expert")
	assert_str(PlayerProfile.from_dict({"name": "A", "game": 0}).campaign_id).is_equal(&"voyager")
	assert_str(PlayerProfile.from_dict({"name": "A", "game": 7}).campaign_id).is_equal(&"expert")
	assert_str(PlayerProfile.from_dict({"name": "A", "game": -3}).campaign_id).is_equal(&"voyager")
	assert_str(PlayerProfile.from_dict({"name": "A"}).campaign_id).is_equal(Catalog.default_campaign_id())      # neither: a new player's, the pack's first
	assert_str(HallEntry.from_dict({"name": "A"}).campaign_id).is_equal(Catalog.default_campaign_id())
	assert_str(PlayerProfile.from_dict({"name": "A", "game": "1"}).campaign_id).is_equal(&"expert")
	assert_str(PlayerProfile.from_dict({"name": "A", "campaign": "", "game": 1}).campaign_id).is_equal(&"expert")     # an empty id says nothing
	assert_str(PlayerProfile.from_dict({"name": "A", "campaign": 5, "game": 1}).campaign_id).is_equal(&"expert")      # nor does a number
	assert_str(PlayerProfile.from_dict({"name": "A", "campaign": "voyager", "game": 1}).campaign_id).is_equal(&"voyager")   # the id wins
	assert_str(HallEntry.from_dict({"name": "A", "game": 1}).campaign_id).is_equal(&"expert")
	assert_str(HallEntry.from_dict({"name": "A", "game": 9}).campaign_id).is_equal(&"expert")


func test_a_file_of_a_newer_release_is_still_read() -> void:
	_write(ROSTER, '{"version": 99, "players": [{"name": "Zoe", "campaign": "voyager", "progress": 4, "extra": "from the future"}]}')
	var fresh := _reload()
	assert_int(fresh.players.size()).is_equal(1)
	assert_int(fresh.players[0].progress).is_equal(4)


# --- a campaign that is not installed ----------------------------------------------------------------------------------------

func test_a_player_of_an_unknown_campaign_is_kept_but_cannot_be_played() -> void:
	_write(ROSTER, '{"version": 2, "players": [{"name": "Lost", "campaign": "vanished", "progress": 77, "tanks": 4, "pieces_mask": 3, "tries": 5}]}')
	var fresh := _reload()
	assert_int(fresh.players.size()).is_equal(1)
	var lost: PlayerProfile = fresh.players[0]
	assert_str(lost.campaign_id).is_equal(&"vanished")
	assert_bool(lost.is_playable()).is_false()
	assert_int(lost.progress).is_equal(77)                            # nothing to check it against: kept, for when the campaign is back
	assert_int(lost.game).is_equal(-1)
	assert_str(lost.campaign_title()).is_equal("vanished")
	assert_str(lost.campaign().id).is_equal(Catalog.default_campaign_id())     # (the pack's first, so that a screen has something to draw; it never gets as far as the game)
	assert_bool(fresh.save_roster()).is_true()                        # saving does not lose it either
	var row: Dictionary = _file_json(ROSTER)["players"][0]
	assert_str(row["campaign"]).is_equal("vanished")
	assert_int(int(row["progress"])).is_equal(77)
	assert_int(int(row["tanks"])).is_equal(4)
	assert_int(PlayerProfile.from_dict({"name": "L", "campaign": "vanished", "progress": -5}).progress).is_equal(0)     # only nonsense is mended


func test_the_record_comes_back_to_life_when_the_campaign_is_installed_again() -> void:
	_write(ROSTER, '{"version": 2, "players": [{"name": "Gus", "campaign": "garden", "progress": 353}]}')
	var without := _reload()
	assert_bool(without.players[0].is_playable()).is_false()
	_install([CampaignShelf.garden()])
	var with := _reload()
	assert_bool(with.players[0].is_playable()).is_true()
	assert_int(with.players[0].progress).is_equal(353)                # valid in the campaign: sector 176


func test_a_hall_row_of_an_unknown_campaign_shows_its_saved_id() -> void:
	var entry := HallEntry.from_dict({"name": "Old", "campaign": "vanished", "tries": 3, "customized": true})
	assert_str(entry.campaign_id).is_equal(&"vanished")
	assert_object(entry.campaign()).is_null()
	assert_str(entry.level_text()).is_equal("vanished " + Catalog.text(&"customized_marker"))
	assert_str(entry.to_dict()["campaign"]).is_equal("vanished")
	assert_bool(entry.to_dict().has("game")).is_false()


func test_hall_rows_round_trip_for_every_kind_of_campaign() -> void:
	_install([CampaignShelf.garden()])
	for id in [&"voyager", &"expert", &"garden", &"vanished"]:
		var entry := HallEntry.new()
		entry.name = "Row"
		entry.campaign_id = id
		entry.tries = 6
		entry.customized = id == &"expert"
		var back := HallEntry.from_dict(JSON.parse_string(JSON.stringify(entry.to_dict())))
		assert_str(back.campaign_id).is_equal(id)
		assert_int(back.tries).is_equal(6)
		assert_bool(back.customized).is_equal(entry.customized)
	var profile := PlayerProfile.new_player_in("Gus", Catalog.campaign(&"garden"))
	profile.tries = 4
	assert_str(HallEntry.from_profile(profile).campaign_id).is_equal(&"garden")
	assert_int(HallEntry.from_profile(profile).game).is_equal(-1)


# --- progress that the campaign does not have -------------------------------------------------------------------------------

func test_a_progress_that_is_not_in_the_campaign_loads_as_its_start() -> void:
	_install([CampaignShelf.garden()])
	var garden := Catalog.campaign(&"garden")
	for progress in [0, 5, 2 * 174, 2 * 178 + 1, 100000, -4]:
		var player := PlayerProfile.from_dict({"name": "Gus", "campaign": "garden", "progress": progress})
		assert_int(player.progress).override_failure_message("progress %d" % progress).is_equal(garden.start_progress())
	assert_int(PlayerProfile.from_dict({"name": "Gus", "campaign": "garden"}).progress).is_equal(350)      # none at all: the start too
	for progress in [350, 351, 352, 353, 354, 355]:                                          # sectors 175, 176 and the finale 177, flag on and off
		assert_int(PlayerProfile.from_dict({"name": "Gus", "campaign": "garden", "progress": progress}).progress).is_equal(progress)


func test_bits_for_pieces_a_sector_does_not_have_are_dropped() -> void:
	assert_int(Progression.valid_pieces_mask(0b1111111, 7)).is_equal(0b1111111)
	assert_int(Progression.valid_pieces_mask(0b11111111111, 7)).is_equal(0b1111111)
	assert_int(Progression.valid_pieces_mask(0b100000, 5)).is_equal(0)
	assert_int(Progression.valid_pieces_mask(0xFFFF, 11)).is_equal(0x7FF)
	assert_int(Progression.valid_pieces_mask(0b1, 0)).is_equal(0)


func _run_of(player: PlayerProfile) -> Object:
	var run: Object = auto_free(load(GAME_STATE_SCRIPT).new())
	run.profile = player
	run.apply_profile(player)
	return run


func test_a_saved_mask_with_bits_beyond_the_pieces_is_mended_when_the_sector_loads() -> void:
	var player := PlayerProfile.new_player("Ann", 0)
	player.progress = 2 * 3                                            # sector 3
	player.pieces_mask = 0b1100011                                     # saved when the sector had 7 pieces
	var run := _run_of(player)
	assert_int(run.pieces_mask).is_equal(0b1100011)                    # (nothing is known yet)
	run.set_sector(3, 5)                                               # ... the designer removed two since
	assert_int(run.pieces_mask).is_equal(0b0000011)
	assert_int(run.pieces_collected()).is_equal(2)
	run.capture_profile()
	assert_int(player.pieces_mask).is_equal(0b11)                      # the saved game is clean again
	assert_int(player.pieces_total).is_equal(5)


func test_a_sector_with_another_number_of_pieces_than_when_saved_starts_collecting_again() -> void:
	var player := PlayerProfile.new_player("Ann", 0)
	player.progress = 2 * 3
	player.pieces_mask = 0b101
	player.pieces_total = 7                                            # saved with 7 pieces; the sector has 8 now: a piece was added
	var run := _run_of(player)
	run.set_sector(3, 8)
	assert_int(run.pieces_mask).is_equal(0)                            # which bit is which piece can no longer be told
	# the same number of pieces: the mask is trusted
	player.pieces_mask = 0b101
	player.pieces_total = 7
	run = _run_of(player)
	run.set_sector(3, 7)
	assert_int(run.pieces_mask).is_equal(0b101)
	# a file of the first release does not know its count: only the bits beyond the pieces go
	player.pieces_total = 0
	run = _run_of(player)
	run.set_sector(3, 8)
	assert_int(run.pieces_mask).is_equal(0b101)


func test_a_mask_is_not_touched_for_a_sector_that_is_not_the_players() -> void:
	var player := PlayerProfile.new_player("Ann", 0)
	player.progress = 2 * 3
	player.pieces_mask = 0b101
	player.pieces_total = 7
	var run := _run_of(player)
	run.set_sector(9, 8)                                               # another sector (a debug jump): the saved count says nothing about it
	assert_int(run.pieces_mask).is_equal(0b101)


func test_the_piece_count_is_saved_only_once_the_players_sector_is_loaded() -> void:
	var player := PlayerProfile.new_player("Ann", 0)
	player.progress = 2 * 3
	player.pieces_total = 7
	var run := _run_of(player)
	run.capture_profile()                                              # (before any sector is loaded: GameState does not know the count)
	assert_int(player.pieces_total).is_equal(7)
	run.set_sector(3, 7)
	run.capture_profile()
	assert_int(player.pieces_total).is_equal(7)
	var json := JSON.stringify(player.to_dict())
	assert_int(PlayerProfile.from_dict(JSON.parse_string(json)).pieces_total).is_equal(7)
