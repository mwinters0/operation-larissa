@tool
class_name Campaign
extends Resource
## One game: the ordered list of its sectors, where it ends, and everything else that makes "Voyager" different from "Expert" -
## its name, its educational levels, its canister log, its supply messages, its songs, its closing scene. The two games of the
## original are two of these (`data/campaigns/voyager.tres`, `expert.tres`); a student's own game is a third.
##
## Teaches: DATA INSTEAD OF CONSTANTS. The original compares numbers where it needs to know which game a sector belongs to
## (`sector >= 30` is a finale, `sector % 15` is the place in the game, `game * 5 + zone` indexes the educational levels). That works for
## exactly two games of exactly 15 sectors, and breaks the moment a third one exists. Here every one of those questions is asked of a
## `Campaign`, and the numbers 15 and 30 live only in the data of the two campaigns that have them. A Resource with `@export` fields is
## the right shape: it is saved as a `.tres`, edited in the Inspector, and the code that reads it never learns where it came from.
##
## A SECTOR BELONGS TO ONE CAMPAIGN. That is the rule that lets code that only has a sector number (the HUD, the music, the log screen) find
## the campaign: `Catalog.campaign_of_sector`. `problems()` refuses a campaign that breaks it. The campaign the PLAYER is in is
## `PlayerProfile.campaign()` (the id the save stores, `PlayerProfile.campaign_id`).
##
## WHAT STAYS WITH THE SECTOR. The zone of a sector (`SectorData.zone`), its song (`SectorData.music_name`) and the screen where its finale
## begins (`SectorData.finale_screen`) are fields of the sector, so a copied sector brings them along; this resource only reads them.
##
## NAMES IN DATA, OR TEXT OF ITS OWN. A text below is a registry NAME (names/original.json, kind `text`: "game_voyager", "log_entry_3"; not a
## NEP.DLL number, docs/create/NAMES.md) or simply the words themselves ("Welcome aboard!"). `Campaign.text(value)` tells them apart: a value that
## is a known text name is looked up in the game's string tables, anything else is shown as written. So the originals keep their names, a
## student types the sentences straight into the Inspector, and the two can be mixed. (The price: a sentence that is exactly a text name
## shows the original's string instead; no sentence is.) The voice groups are the names of the groups in `voice_cues.tres`; a campaign with
## no recordings leaves them empty or names a group that does not exist, and the speech is simply silent (`VoiceCues.clips` gives no clips).
##
## THE ORIGINALS' FILES are written by the importer (`tools/import/step_campaigns.py`, from the program's tables), so `rename_name.py` keeps
## their names current; a campaign of a designer's own is a `.tres` of this class in the same folder that the importer leaves alone.

## The pack this campaign came from (`Pack.id`), or empty for one of the game's own `.tres` files. Set by `Catalog` when it reads a pack's
## `campaigns/<id>.json` (not a field of the file). A pack's campaign is the pack's: its pictures, speech and songs are the pack's files.
var pack_id: StringName = &""

## The song for a sector whose own song is unknown (`SectorData.music_name` empty or not one of the original's).
const DEFAULT_SONG := &"sector_song_1"

## Who made this data and where the original-derived numbers come from. A few words; the original's tables are named by address.
@export var provenance: String = ""
## The campaign's id: the file name without `.tres`, and what a save stores (`PlayerProfile.campaign_id`, `HallEntry.campaign_id`). "voyager" and
## "expert" are the originals'.
@export var id: StringName = &""

@export_group("Name and banner")
## The name of the game as a `text` name ("game_voyager"), or empty to use `title`. Sign-in, the Hall of Fame and the customised-game notice show it.
## (Either field takes a name or plain words, see `text`.)
@export var title_text: StringName = &""
## The name when `title_text` is empty (a student's campaign has no NEP.DLL string).
@export var title: String = ""
## The caption of the "choose a game" button in the new-player dialog (a `text` name), or empty to use the name of the game.
@export var new_game_text: StringName = &""
## The picture the HUD shows for the game: an index into `HudLayout.game_textures` (0 = the Voyager picture, 1 = Expert; a skin redraws them),
## or -1 to show this campaign's own `banner` (and its title as the word of a text-only skin).
@export var banner_index: int = 0
@export var banner: Texture2D

@export_group("Sectors")
## The sectors to play, in order, as sector ids (`SectorData.index`). Voyager 0-14, Expert 15-29.
@export var sectors: PackedInt32Array = PackedInt32Array()
## The sectors after the last one: the first is where the game ends (Voyager 30, Expert 31). Docking in a finale ends the game; the closing
## sequence starts on the sector's `finale_screen`.
@export var finales: PackedInt32Array = PackedInt32Array()
## The educational level (0-3) the math problems use when the player did not customise, by zone; a zone beyond the list takes the last
## entry (the finale zones use the last real zone's level). Voyager: 0, 0, 1, 1, 1. Expert: 2, 2, 2, 3, 3 (`zones.tres`, DS 0x25A8).
@export var default_edu_levels: PackedInt32Array = PackedInt32Array()

@export_group("Canister log")
## The first digit of the entry captions: "ENTRY 1.04" is of series 1, Expert's "ENTRY 2.07" of series 2.
@export var log_series: int = 1
## The order in which the entries are unlocked: the k-th number (1-based) is the entry the canister of the k-th sector delivers; the log of that
## sector lists the first k numbers. The original's tables `LogUnlockOrderVoyager` 0x4419d5 and `LogUnlockOrderExpert` 0x4419e4.
@export var log_unlock_order: PackedInt32Array = PackedInt32Array()
## For each finale, how many entries its log lists. The original computes `sector % 15 + 1` for every sector, finales included, so sector 30
## lists 1 entry and sector 31 lists 2 (a leftover that nobody sees: the finale has a canister like any sector).
@export var finale_log_counts: PackedInt32Array = PackedInt32Array()
## Entry `n` (1-based) is `log_texts[n - 1]` (a `text` name, "log_entry_3", or the words themselves) and is spoken as the voice group
## `log_voices[n - 1]` ("log_3"; a name that is empty or not a group is silent).
@export var log_texts: Array[StringName] = []
@export var log_voices: Array[StringName] = []

@export_group("Supply station")
## What mission control says after the k-th sector (parallel to `sectors`): a `text` name or the words themselves, and a voice group name
## ("supply_0"; empty or not a group means the message is only read, after the "incoming transmission" jingle).
@export var supply_texts: Array[StringName] = []
@export var supply_voices: Array[StringName] = []

@export_group("Mods")
## The mod packs this campaign uses, by pack id (`Pack.id`): the rule hooks of a mod (`ModSpec` `rules`: the judging of the answers of the problem types it adds, creature instructions, a sub ability) are reached by a run of this campaign
## and by no other. Each must be a mod pack of the chain in use; the run resolves them once when it begins (`GameState.begin_run`, `ModHooks.resolve`). The original campaigns declare none, and so run none.
@export var mods: Array[StringName] = []

@export_group("Music and closing")
## The song of a sector whose own `music_name` is empty or unknown.
@export var fallback_song: StringName = DEFAULT_SONG
## Which closing sequence plays after the finale: "voyager" or "expert" (the original's two scenes, `Game.show_closing`), or empty (or any
## other word) for the generic finale (`GenericFinale`: `finale_picture` and `finale_text`).
@export var closing_scene: StringName = &""
## The generic finale's words: a `text` name or the words themselves (see `text`). Empty shows no text.
@export_multiline var finale_text: String = ""
## The generic finale's picture: the name of a `ui_picture` of the registry ("title_sky"), the name of a picture of a pack (the file
## `pictures/ui_picture/<name>.png` of a mounted pack), or a path to a picture of the campaign's own ("res://campaigns/mine/finale.png").
## Empty (or a name / path that is nothing) shows no picture.
@export var finale_picture: String = ""


# --- the sectors ---------------------------------------------------------------------------------------------------------------

## The place of `sector` in the list of sectors to play (0-based), or -1 (a finale, or not of this campaign).
func position_of(sector: int) -> int:
	return sectors.find(sector)


func is_finale(sector: int) -> bool:
	return finales.has(sector)


## Is `sector` one of this campaign's, to play or a finale?
func contains(sector: int) -> bool:
	return sectors.has(sector) or finales.has(sector)


## How many sectors there are to play ("N of 15" on the sign-in screen).
func sector_count() -> int:
	return sectors.size()


## The first sector of the game (a new player starts here), or 0 for a campaign without sectors.
func first_sector() -> int:
	return sectors[0] if not sectors.is_empty() else 0


## The progress word (`sector * 2`, midpoint flag off, see `Progression`) of a new player.
func start_progress() -> int:
	return first_sector() * 2


## `IncrementSector` (0x42e0b2) for this campaign: the progress after finishing the sector `progress` names (midpoint flag cleared). The next sector
## of the list; after the last one the first finale; a finale stays where it is (the closing sequence ends the game); after the last sector of a
## campaign without a finale the player stays there; a sector that is not in the list simply steps on to the next number.
func next_progress(progress: int) -> int:
	var sector := progress >> 1
	if finales.has(sector):
		return progress & ~1
	var place := position_of(sector)
	if place < 0:
		return (sector + 1) * 2
	if place + 1 < sectors.size():
		return sectors[place + 1] * 2
	return (finales[0] if not finales.is_empty() else sector) * 2


## The zone (index into `zones.tres`) of `sector`: the sector's own field.
func zone_of(sector: int) -> int:
	var data := Catalog.sector(sector)
	return data.zone if data != null else 0


## The educational level when the player did not customise the game, for a zone (see `default_edu_levels`).
func default_edu_level(zone: int) -> int:
	if default_edu_levels.is_empty():
		return 0
	return default_edu_levels[clampi(zone, 0, default_edu_levels.size() - 1)]


# --- names ---------------------------------------------------------------------------------------------------------------------

## A text of the campaign: `value` is a `text` name of the registry ("game_voyager"), whose string is returned, or the words themselves,
## which are returned as they are. This is how a campaign says its title, log entries, supply messages and finale without having a
## NEP.DLL string for them. The test is "is it a known name": an unknown name gives the words back, never an error, so a typo in a name shows
## up on the screen instead of in the log.
static func text(value: String) -> String:
	if not value.is_empty() and Catalog.has_text(StringName(value)):
		return Catalog.text(StringName(value))
	return value


## The name of the game as shown to the player ("Voyager", "Expert").
func display_title() -> String:
	return text(String(title_text)) if title_text != &"" else text(title)


## The caption of this campaign's button in the new-player dialog.
func new_game_label() -> String:
	return text(String(new_game_text)) if new_game_text != &"" else display_title()


# --- the canister log ----------------------------------------------------------------------------------------------------------

## How many entries the log lists in `sector` (see `log_unlock_order`); 0 for a sector that is not of this campaign.
func log_count(sector: int) -> int:
	var place := position_of(sector)
	var count := 0
	if place >= 0:
		count = place + 1
	else:
		var finale := finales.find(sector)
		if finale < 0:
			return 0
		count = finale_log_counts[finale] if finale < finale_log_counts.size() else 1
	return mini(count, log_unlock_order.size())


## The entry number (1-based) the canister of `sector` delivers, or 0 when there is none.
func log_newest(sector: int) -> int:
	var count := log_count(sector)
	return log_unlock_order[count - 1] if count > 0 else 0


## The entry numbers the log lists in `sector`, ascending (the original's insertion sort).
func log_entries(sector: int) -> PackedInt32Array:
	var numbers := PackedInt32Array(Array(log_unlock_order).slice(0, log_count(sector)))
	numbers.sort()
	return numbers


## The `text` name (or the words) of entry `number` (1-based), as the data holds it; `log_entry_text` is what the log screen shows.
func log_text_name(number: int) -> StringName:
	return log_texts[number - 1] if number >= 1 and number <= log_texts.size() else &""


## The voice group name of entry `number` (1-based): hand it to `VoiceCues.clips` (no such group: no clips, so the entry is not spoken).
func log_voice_name(number: int) -> StringName:
	return log_voices[number - 1] if number >= 1 and number <= log_voices.size() else &""


## The words of entry `number` (1-based) as the log screen shows them: `log_text_name` through `text`.
func log_entry_text(number: int) -> String:
	return text(String(log_text_name(number)))


# --- the supply station ----------------------------------------------------------------------------------------------------------

## The `text` name (or the words) of what mission control says after `sector` is finished, as the data holds it; empty for a finale (the game
## ends there) or a stranger. `supply_message_text` is what the surface ship screen shows.
func supply_text_name(sector: int) -> StringName:
	var place := position_of(sector)
	return supply_texts[place] if place >= 0 and place < supply_texts.size() else &""


## The voice group name of the same message (a group that does not exist: the message is not spoken, see `VoiceCues.clips`).
func supply_voice_name(sector: int) -> StringName:
	var place := position_of(sector)
	return supply_voices[place] if place >= 0 and place < supply_voices.size() else &""


## The words mission control says after `sector`, as the surface ship screen shows them (`supply_text_name` through `text`).
func supply_message_text(sector: int) -> String:
	return text(String(supply_text_name(sector)))


# --- the generic finale ----------------------------------------------------------------------------------------------------------

## The generic finale's text (`finale_text` through `text`), "" for none.
func finale_message() -> String:
	return text(finale_text)


## The generic finale's picture, or null (none named, or the name / file does not exist). A name of the registry's `ui_picture` kind goes
## through `Assets` (a skin may redraw it); a "res://" path is loaded as a file, through the skin's `texture_at` like every picture file.
func finale_texture() -> Texture2D:
	if finale_picture.is_empty():
		return null
	if finale_picture.begins_with("res://"):
		return Assets.texture_at(finale_picture) if Packs.exists_at(finale_picture) else null
	if NameRegistry.original().index_of(&"ui_picture", finale_picture) >= 0 or Packs.picture("ui_picture/" + finale_picture) != null:
		return Assets.ui_picture(StringName(finale_picture))
	return null


# --- music ------------------------------------------------------------------------------------------------------------------------

## The `music` name of the song played in `sector`: the one its `music_name` (the stem of the MIDI file) names, else `fallback_song`.
func song_for(sector: int) -> StringName:
	var data := Catalog.sector(sector)
	var song: StringName = MusicCatalog.song_of_stem(data.music_name) if data != null else &""
	return song if song != &"" else fallback_song


# --- checking ---------------------------------------------------------------------------------------------------------------------

## What is wrong with this campaign, one sentence each; empty when it is playable. The sector files are not opened (a sector that does not
## exist is the sector checks' business). `Catalog.campaign_problems` adds what only the whole set can see: a sector in two campaigns.
func problems() -> Array[String]:
	var found: Array[String] = []
	if id == &"":
		found.append("the campaign has no id")
	if title_text == &"" and title.is_empty():
		found.append("the campaign has no name (title_text or title)")
	if sectors.is_empty():
		found.append("the campaign has no sectors")
	var seen := {}
	for sector in sectors:
		if seen.has(sector):
			found.append("sector %d is listed twice" % sector)
		seen[sector] = true
	for sector in finales:
		if seen.has(sector):
			found.append("sector %d is both a sector to play and a finale" % sector)
		seen[sector] = true
	if default_edu_levels.is_empty():
		found.append("default_edu_levels is empty")
	for level in default_edu_levels:
		if level < 0 or level > 3:
			found.append("default_edu_levels holds %d: an educational level is 0 to 3" % level)
	var entries := log_unlock_order.size()
	if log_texts.size() != entries or log_voices.size() != entries:
		found.append("the log has %d unlock numbers, %d texts and %d voice groups: they must be equally many" % [entries, log_texts.size(), log_voices.size()])
	var numbers := Array(log_unlock_order)
	numbers.sort()
	if numbers != range(1, entries + 1):
		found.append("log_unlock_order must hold each entry number 1 to %d exactly once" % entries)
	if entries > 0 and entries < sectors.size():
		found.append("the log has %d entries for %d sectors: a late sector would list none" % [entries, sectors.size()])
	if not finales.is_empty() and finale_log_counts.size() != finales.size():
		found.append("finale_log_counts must have one count for each of the %d finales" % finales.size())
	if supply_texts.size() != sectors.size() or supply_voices.size() != sectors.size():
		found.append("%d sectors but %d supply texts and %d supply voice groups" % [sectors.size(), supply_texts.size(), supply_voices.size()])
	if not finale_picture.is_empty() and finale_texture() == null:
		found.append("finale_picture '%s' is neither a picture name (of the registry or of a pack) nor a file that exists" % finale_picture)
	if banner_index < 0 and banner == null:
		found.append("banner_index is -1, so the campaign needs its own banner picture")
	var declared := {}
	for mod in mods:
		if mod == &"":
			found.append("mods holds an empty pack id")
		elif declared.has(mod):
			found.append("mod '%s' is declared twice" % mod)
		declared[mod] = true
	return found
