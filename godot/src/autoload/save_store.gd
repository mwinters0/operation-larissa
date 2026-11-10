extends Node
## The roster of players and the Hall of Fame, saved as JSON in `user://` (autoload "SaveStore").
##
## Teaches: persistence with `FileAccess` + `JSON`, and defensive loading. `user://` is the per-user
## writable folder Godot maps to the right place on every platform (on Linux
## `~/.local/share/godot/app_userdata/Operation Larissa/`; Project > Open User Data Folder shows it).
## Each file carries a `"version"` so a later release can read old saves (`FORMAT_VERSION`, below). Saving writes to a
## temporary file first and then renames it, so a crash in the middle never leaves a half-written
## roster. Loading never trusts the file: unreadable, corrupt or odd content gives an empty roster
## and a warning in the log, never a crash.
##
## The original keeps two files, `ONUSERS.DAT` (36 bytes per player, 99 players) and
## `HALLFAME.DAT` (9 rows); here they are `roster.json` and `hall_of_fame.json`.
##
## Signals tell the sign-in screen when to redraw (the model emits, the view observes).
##
## Two behaviours come straight from the original's code (DESIGN 6):
##   * the roster is kept in BYTE order of the names, upper case before lower case (`RosterOpenSortedSlot`
##     0x4307ec: a new name goes before the first name that is strictly greater, so after any equal one). Nothing in
##     the original refuses a name that is already taken (`AddNewPlayer` 0x430851 has no such check), so two players
##     may share a name, in any capitalisation.
##   * a write that fails is reported to the player with a dialog (`write_users_dat` 0x41bce2 and `write_hof_dat`
##     0x41be42, strings 11018 / 11017); the game carries on with the data it has in memory.

signal roster_changed
signal hall_changed
## A save did not reach the disk. Screens that own a `MessageQueue` answer with `post_write_error`.
signal write_failed(path: String)

const MAX_PLAYERS := 99
## The version the files are written with. 1: the first release (a player and a Hall of Fame row name their game by `game`, 0 Voyager /
## 1 Expert, and nothing else). 2: they name it by `campaign` (an id), a player also keeps `pieces_total`. A version 1 file is read
## by the same code as a version 2 one - a row without a `campaign` takes it from its `game`, a player without `pieces_total` has none -
## and is written as version 2 the next time it is saved, so there is no separate migration step to forget. A file of a LATER version is
## read as far as it is understood and warned about.
const FORMAT_VERSION := 2

## Where the files live. Tests point these at a scratch folder (and never at the real save).
var roster_path: String = "user://roster.json"
var hall_path: String = "user://hall_of_fame.json"

## The players, sorted by name in byte order (case matters: "Zed" comes before "amy").
var players: Array[PlayerProfile] = []
var hall := HallOfFame.new()


func _ready() -> void:
	load_all()


# --- loading -------------------------------------------------------------------------

func load_all() -> void:
	var roster_data: Variant = _read_json(roster_path)
	_check_version(roster_data, roster_path)
	players = _parse_roster(roster_data)
	hall = HallOfFame.new()
	var hall_data: Variant = _read_json(hall_path)
	_check_version(hall_data, hall_path)
	if hall_data is Dictionary and (hall_data as Dictionary).get("entries") is Array:
		hall.from_array((hall_data as Dictionary)["entries"])
	roster_changed.emit()
	hall_changed.emit()


## The parsed JSON of `path`; null when the file is missing or damaged (the latter warns).
func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_warning("SaveStore: %s is empty, starting with nothing." % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("SaveStore: %s is not valid JSON (%s, line %d), starting with nothing." % [path, json.get_error_message(), json.get_error_line()])
		return null
	return json.data


## A file of a release newer than this one is still read (what is understood is kept), but the log says so.
func _check_version(data: Variant, path: String) -> void:
	if data is Dictionary and PlayerProfile._int(data as Dictionary, "version", 1) > FORMAT_VERSION:
		push_warning("SaveStore: %s is version %s, newer than this release's %d: reading what is understood." % [path, (data as Dictionary)["version"], FORMAT_VERSION])


func _parse_roster(data: Variant) -> Array[PlayerProfile]:
	var result: Array[PlayerProfile] = []
	if data == null:
		return result
	if not (data is Dictionary) or not ((data as Dictionary).get("players") is Array):
		push_warning("SaveStore: %s has no player list, starting with nothing." % roster_path)
		return result
	for row in (data as Dictionary)["players"]:
		if result.size() >= MAX_PLAYERS:
			break
		if row is Dictionary:
			var profile := PlayerProfile.from_dict(row)
			if profile != null:
				result.insert(_sorted_index(result, profile.name), profile)     # (also puts a save of an older release in order)
	return result


# --- saving ----------------------------------------------------------------------------

## Writes the roster. Returns false (and warns) if the disk refuses.
func save_roster() -> bool:
	var rows: Array = []
	for profile in players:
		rows.append(profile.to_dict())
	return _write_json(roster_path, {"version": FORMAT_VERSION, "players": rows})


func save_hall() -> bool:
	return _write_json(hall_path, {"version": FORMAT_VERSION, "entries": hall.to_array()})


## Write to "<path>.tmp", then rename over the real file. Any failure warns in the log and emits `write_failed`
## (the original's `write_users_dat` / `write_hof_dat` show their dialog when the file cannot be opened or fewer
## bytes than asked were written).
func _write_json(path: String, data: Dictionary) -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: cannot write %s (error %d)." % [temp_path, FileAccess.get_open_error()])
		write_failed.emit(path)
		return false
	var stored := file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if not stored:
		push_warning("SaveStore: could not store all of %s." % temp_path)
		write_failed.emit(path)
		return false
	var error := DirAccess.rename_absolute(temp_path, path)
	if error != OK:
		push_warning("SaveStore: cannot replace %s (error %d)." % [path, error])
		write_failed.emit(path)
		return false
	return true


## The dialog the original shows after a failed write (`RunModalDialog` 0x4174ec on the record at 0x441450): title
## string 11018 "Write Error", text 11017 "Writing to the disk has failed. Your game cannot be saved.", one OK button.
## Pressing OK changes nothing: the player stays in the roster in memory.
func post_write_error(queue: MessageQueue) -> MessageQueue.Message:
	return queue.post(Catalog.text(&"disk_write_failed_title"), Catalog.text(&"disk_write_failed_text").replace("\r", "\n"))


# --- the roster ------------------------------------------------------------------------

func is_full() -> bool:
	return players.size() >= MAX_PLAYERS


## The first player called exactly `player_name` (names are case sensitive), or null.
func find(player_name: String) -> PlayerProfile:
	for profile in players:
		if profile.name == player_name:
			return profile
	return null


## Creates, stores and saves a new player. Returns null when the name is empty or the roster is full. A name that is
## already taken is fine (as in the original); the newcomer goes after the players with that name.
func add_player(player_name: String, game: int, sound_on: bool = true, music_on: bool = true, voice_on: bool = true) -> PlayerProfile:
	return add_player_in(player_name, Catalog.campaign_for_game(game), sound_on, music_on, voice_on)


## `add_player` for any campaign (`Catalog.campaigns()`), not only the original's two numbered by `game`.
func add_player_in(player_name: String, campaign: Campaign, sound_on: bool = true, music_on: bool = true, voice_on: bool = true) -> PlayerProfile:
	var profile := PlayerProfile.new_player_in(player_name, campaign)
	if profile.name.is_empty() or is_full():
		return null
	profile.sound_on = sound_on                                             # `AddNewPlayer` (0x430851) copies the Sound / Music / Voice
	profile.music_on = music_on                                             # switches that are on at this moment into the new record
	profile.voice_on = voice_on
	players.insert(_sorted_index(players, profile.name), profile)
	save_roster()
	roster_changed.emit()
	return profile


func remove_player(profile: PlayerProfile) -> void:
	players.erase(profile)
	save_roster()
	roster_changed.emit()


## A finished game goes into the Hall of Fame and the player leaves the roster (`add_player_to_hall` 0x4315ac:
## the Hall row, then `RemoveRosterSlot` 0x42f6eb, which writes both files; `Main` then calls `SaveRosterData`).
func add_to_hall(profile: PlayerProfile) -> void:
	hall.add(HallEntry.from_profile(profile))
	players.erase(profile)
	save_hall()
	save_roster()
	roster_changed.emit()
	hall_changed.emit()


## Where a new name goes: before the first name that is strictly greater, else at the end (`RosterOpenSortedSlot`
## 0x4307ec, `strcmp` 0x43434c compares bytes, so "Z" < "a"; GDScript compares Strings character by character, the
## same thing for the original's one-byte characters). Equal names are not "greater": the newcomer goes after them.
static func _sorted_index(list: Array[PlayerProfile], player_name: String) -> int:
	for i in list.size():
		if list[i].name > player_name:
			return i
	return list.size()
