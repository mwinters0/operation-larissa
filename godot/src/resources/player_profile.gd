class_name PlayerProfile
extends RefCounted
## One saved player: the original's 36 byte `Player` struct (DESIGN 6) as a plain object.
##
## Teaches: a data class with `to_dict()` / `from_dict()`. JSON can only hold numbers, strings,
## booleans, arrays and dictionaries, so every save format boils down to "turn the object into a
## Dictionary, and back". `from_dict` is deliberately forgiving: a missing or silly value falls
## back to the default of a new player (and numbers are clamped), so a half-edited save file
## cannot crash the game.
##
## THE CAMPAIGN AND `progress`. A save names the game by CAMPAIGN ID (`campaign_id`: "voyager", "expert", or a student's own),
## and `progress` stays what the original made it: `sector id * 2 + midpoint flag` (`Progression`), where the sector id is the number
## of the sector's file. We kept the SECTOR ID rather than the sector's PLACE in the campaign's list (`position * 2 + flag`) because
## (1) that is the original's word, byte for byte, so Voyager and Expert saves mean exactly what they always meant and a file of the
## first release loads with no change to its progress (Expert's 0x1E would have become 0 and every old record needed rewriting),
## (2) every reader of the progress word (`Progression`, the HUD, the flow) keeps working on it, and (3) a sector's id never changes
## once it exists (the file is its name), while its place in a list changes whenever the designer reorders the campaign. The
## campaign's list is the VALIDATOR instead: a progress whose sector is not in the campaign's `sectors` / `finales` (the designer
## removed it, or the file is damaged) loads as the campaign's start (`valid_progress`). `game` is the old files' way of naming the
## campaign (0 Voyager, 1 Expert); a file without a `campaign` takes it from there, and an original campaign still writes it, so
## the original's meaning is kept next to the id.
##
## The sub's air, ink and collected pieces are copied in and out of `GameState` when a game
## starts and when it is saved (`GameState.apply_profile` / `GameState.capture_profile`).

## The name box takes at most eight characters (`EnterNewPlayerNameDialog` 0x4305ae stops at `CMP ESI,8`; its buffer
## is the nine bytes "________" + NUL at 0x442fd0). The name field of the record has ten bytes, so a file may hold nine
## characters: `NAME_FIELD_MAX` is what loading still accepts.
const NAME_MAX := 8
const NAME_FIELD_MAX := 9
## `tanks`, `oxygen` and `ink` of a player who has not played yet: what the rules of the run it begins give a new player
## (`GameState.begin_run`: `refill_tanks` spare tanks, a full tank, a full supply of ink).
const NEW_SUPPLY := -1
const HINTS_ALL_UNSEEN := 0xFFFF

enum Game { VOYAGER, EXPERT }

var name: String = ""
## The campaign being played: the id of a `Campaign` in `Catalog.campaigns()`. An id that no campaign has (a student's campaign that is not
## installed) is KEPT, so the record survives until the campaign is back: such a player is not `is_playable()` and cannot start.
var campaign_id: StringName = Catalog.default_campaign_id()
## `sector id * 2 + midpoint flag`, see `Progression` and the class header ("the campaign and `progress`").
var progress: int = 0
## 0 Voyager, 1 Expert: the original's name for the campaign (the old files' way to say it), -1 for any other campaign. Setting it chooses
## the original's campaign of that number. Ask `campaign()` for anything but the number.
var game: int:
	get:
		return Catalog.game_of_campaign(campaign_id)
	set(value):
		campaign_id = Catalog.campaign_for_game(value).id
## True once the player changed the educational level or the calculator ("(c)" in the Hall of Fame).
var customized: bool = false
## The educational level 0-3 the player chose. Only used while `customized` is true; otherwise
## the zone decides (`Progression.default_edu_level`).
var edu_level: int = 0
var sound_on: bool = true
var voice_on: bool = true
var music_on: bool = true
## Options > New Player Hints (on for a new Voyager player, off for Expert, like the original).
var hints_enabled: bool = true
## Bit i set = hint i has not been shown yet (the original's mask, starts at 0xFFFF).
var hints_unseen: int = HINTS_ALL_UNSEEN
var calculator_on: bool = true
## The sub's state when the game was left: spare tanks, oxygen (1 or more), ink pellets (each `NEW_SUPPLY` before the first game). The
## limits are the rules' (`Tuning`): `GameState.begin_run` holds a record to those of the run it enters, so the record keeps what it was saved with.
var tanks: int = NEW_SUPPLY
var oxygen: int = NEW_SUPPLY
var ink: int = NEW_SUPPLY
## Bit i set = piece i of the current sector is collected (piece 0 = the data canister).
var pieces_mask: int = 0
## How many pieces the sector had when `pieces_mask` was saved (0: not known, in a file of the first release). If the sector has a different
## number now, the designer added or removed a piece since, and the bits no longer mean the same pieces: `GameState.set_sector` starts the
## sector's collecting over instead of trusting them.
var pieces_total: int = 0
## How often the player started this game: counts up at each game over (Hall of Fame column "Tries").
var tries: int = 1


## A brand new player of the original's game number `game_kind` (0 Voyager, 1 Expert; anything else is clamped to those).
static func new_player(player_name: String, game_kind: int) -> PlayerProfile:
	return new_player_in(player_name, Catalog.campaign_for_game(game_kind))


## A brand new player of `campaign`: the new player's air and ink of the run it begins (`NEW_SUPPLY`), at the first sector of the campaign (0 for Voyager, 15 for Expert). The
## new-player hints are on, as they are for Voyager, except in Expert (the original's choice for its experienced players).
static func new_player_in(player_name: String, campaign: Campaign) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.name = clean_name(player_name)
	profile.campaign_id = campaign.id
	profile.progress = campaign.start_progress()
	profile.hints_enabled = campaign.id != Catalog.ORIGINAL_CAMPAIGNS[Game.EXPERT]
	return profile


## Drops leading blanks (the name box refuses them) and cuts to `limit` characters. Trailing blanks stay: the original
## keeps what was typed up to Enter.
static func clean_name(raw: String, limit: int = NAME_MAX) -> String:
	return raw.strip_edges(true, false).left(limit)


## What the name box of the original lets through, key by key (`EnterNewPlayerNameDialog` 0x4305ae): a character
## above the blank (0x21 - 0xFF) is taken while fewer than eight are typed, and the FIRST one is made upper case with
## `toupper` (0x438334; C locale: a-z only); a blank is taken only after the first character; control characters and
## anything above 0xFF are ignored. `raw` is what the player typed or pasted; the result is the name.
static func typed_name(raw: String) -> String:
	var typed := ""
	for character in raw:
		var code := character.unicode_at(0)
		if typed.length() >= NAME_MAX:
			break
		if code == 0x20:
			if not typed.is_empty():
				typed += character
		elif code > 0x20 and code < 0x100:
			var kept: String = character
			if typed.is_empty() and code >= 0x61 and code <= 0x7A:
				kept = char(code - 0x20)
			typed += kept
	return typed


func sector() -> int:
	return Progression.sector_of(progress)


## The campaign the player is in: the ONE place that turns what the save holds into a `Campaign` (the stored id looked up in
## `Catalog.campaigns()`). Everything that needs the game's sectors, finale, name, levels or log asks this. For an id that no campaign has it
## answers the pack's first campaign (`Catalog.default_campaign`), so that a screen always has something to draw; such a player is not `is_playable()` and never gets as far as the game.
func campaign() -> Campaign:
	var found := Catalog.campaign(campaign_id)
	return found if found != null else Catalog.default_campaign()


## Is the player's campaign installed? A record of a campaign that is not (a student's campaign was taken away) stays in the roster,
## unchanged, and can be removed, but not played.
func is_playable() -> bool:
	return Catalog.campaign(campaign_id) != null


## The name of the player's game for the lists: the campaign's title, or the saved id of one that is not installed.
func campaign_title() -> String:
	var found := Catalog.campaign(campaign_id)
	return found.display_title() if found != null else String(campaign_id)


func zone() -> int:
	return Progression.zone_of(progress)


func past_midpoint() -> bool:
	return Progression.past_midpoint(progress)


## The level the math problems are drawn from: the player's own choice or the zone's default.
func effective_edu_level() -> int:
	if customized:
		return edu_level
	return campaign().default_edu_level(zone())


## Is the player at the finale sector of the campaign, the last one of the game?
func at_finale() -> bool:
	return Progression.is_finale(progress, campaign())


func to_dict() -> Dictionary:
	var data := {
		"name": name, "campaign": String(campaign_id), "progress": progress, "customized": customized,
		"edu_level": edu_level, "sound_on": sound_on, "voice_on": voice_on, "music_on": music_on,
		"hints_enabled": hints_enabled, "hints_unseen": hints_unseen, "calculator_on": calculator_on,
		"tanks": tanks, "oxygen": oxygen, "ink": ink, "pieces_mask": pieces_mask, "pieces_total": pieces_total, "tries": tries,
	}
	if game >= 0:
		data["game"] = game                              # (the original's two keep their old number next to the id)
	return data


## The id of the campaign a saved row names: its `campaign`, or, in a file of the first release, the original's game number in `game`
## (0 Voyager, 1 Expert; a silly number is clamped to those, as it always was: such a row keeps naming the original's campaign even where it
## is not installed). A row with neither is a new player's default, the pack's first campaign. Shared by `HallEntry`.
static func campaign_id_of(data: Dictionary) -> StringName:
	var stored: Variant = data.get("campaign")
	if (stored is String or stored is StringName) and not String(stored).is_empty():
		return StringName(stored)
	if not data.has("game"):
		return Catalog.default_campaign_id()
	return Catalog.ORIGINAL_CAMPAIGNS[clampi(_int(data, "game", Game.VOYAGER), 0, Catalog.ORIGINAL_CAMPAIGNS.size() - 1)]   # (no need to load the campaign file)


## Builds a profile from a Dictionary that may come from a damaged file. Returns null when it
## has no usable name (such an entry is dropped).
static func from_dict(data: Dictionary) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.name = clean_name(str(data.get("name", "")), NAME_FIELD_MAX)
	if profile.name.is_empty():
		return null
	profile.campaign_id = campaign_id_of(data)
	profile.progress = valid_progress(_int(data, "progress", -1), Catalog.campaign(profile.campaign_id))
	profile.customized = bool(data.get("customized", false))
	profile.edu_level = clampi(_int(data, "edu_level", 0), 0, 3)
	profile.sound_on = bool(data.get("sound_on", true))
	profile.voice_on = bool(data.get("voice_on", true))
	profile.music_on = bool(data.get("music_on", true))
	profile.hints_enabled = bool(data.get("hints_enabled", profile.campaign_id != Catalog.ORIGINAL_CAMPAIGNS[Game.EXPERT]))
	profile.hints_unseen = clampi(_int(data, "hints_unseen", HINTS_ALL_UNSEEN), 0, 0xFFFF)
	profile.calculator_on = bool(data.get("calculator_on", true))
	profile.tanks = _supply(data, "tanks", 0)
	profile.oxygen = _supply(data, "oxygen", 1)
	profile.ink = _supply(data, "ink", 0)
	profile.pieces_mask = clampi(_int(data, "pieces_mask", 0), 0, 0xFFFF)
	profile.pieces_total = clampi(_int(data, "pieces_total", 0), 0, 16)
	profile.tries = clampi(_int(data, "tries", 1), 1, 9999)
	return profile


## `progress` as the campaign can use it: itself when its sector is one of the campaign's (to play or a finale), else the campaign's start
## (a new player's place: the sector was taken out of the list, or the number is damaged). A campaign that is not installed cannot say,
## so only a negative number is mended there (to 0) and the rest is kept for when the campaign is back.
static func valid_progress(progress: int, campaign: Campaign) -> int:
	if campaign == null:
		return maxi(progress, 0)
	if progress < 0 or not campaign.contains(Progression.sector_of(progress)):
		return campaign.start_progress()
	return progress


## JSON reads every number as a float; accept ints, floats and numeric strings, else the default.
## A saved tanks / oxygen / ink: `NEW_SUPPLY` (or no key: a player who has not played), else at least `least`.
static func _supply(data: Dictionary, key: String, least: int) -> int:
	var value := _int(data, key, NEW_SUPPLY)
	return NEW_SUPPLY if value == NEW_SUPPLY else maxi(value, least)


static func _int(data: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = data.get(key, fallback)
	if value is int or value is float:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return fallback
