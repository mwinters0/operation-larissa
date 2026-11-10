class_name HallEntry
extends RefCounted
## One row of the Hall of Fame: who finished which game, how many tries it took (DESIGN 6).
##
## Teaches: a tiny value object with `to_dict` / `from_dict`, like `PlayerProfile`. The game is named by CAMPAIGN ID, as in the player's
## record; `game` is the old files' number for the original's two (0 Voyager, 1 Expert; -1 for any other campaign), and a row
## without a `campaign` takes its campaign from it. A row whose campaign is not installed is kept and shown with its saved id: the
## Hall of Fame is a record, and it stays one when a student's campaign is taken away.

var name: String = ""
var campaign_id: StringName = Catalog.default_campaign_id()
var customized: bool = false
var tries: int = 1
## 0 Voyager, 1 Expert, -1 for any other campaign (setting it chooses the original's campaign of that number).
var game: int:
	get:
		return Catalog.game_of_campaign(campaign_id)
	set(value):
		campaign_id = Catalog.campaign_for_game(value).id


static func from_profile(profile: PlayerProfile) -> HallEntry:
	var entry := HallEntry.new()
	entry.name = profile.name
	entry.campaign_id = profile.campaign_id
	entry.customized = profile.customized
	entry.tries = profile.tries
	return entry


## The campaign the game was in (see `PlayerProfile.campaign`), or null when it is not installed.
func campaign() -> Campaign:
	return Catalog.campaign(campaign_id)


## "Voyager" / "Expert" (the campaign's name; the saved id for a campaign that is not installed), followed by the original's "(c)" for a
## customised game.
func level_text() -> String:
	var found := campaign()
	var text := found.display_title() if found != null else String(campaign_id)
	if customized:
		text += " " + Catalog.text(&"customized_marker")
	return text


func to_dict() -> Dictionary:
	var data := {"name": name, "campaign": String(campaign_id), "customized": customized, "tries": tries}
	if game >= 0:
		data["game"] = game                              # (the original's two keep their old number next to the id)
	return data


static func from_dict(data: Dictionary) -> HallEntry:
	var entry := HallEntry.new()
	entry.name = PlayerProfile.clean_name(str(data.get("name", "")), PlayerProfile.NAME_FIELD_MAX)
	if entry.name.is_empty():
		return null
	entry.campaign_id = PlayerProfile.campaign_id_of(data)
	entry.customized = bool(data.get("customized", false))
	entry.tries = clampi(PlayerProfile._int(data, "tries", 1), 1, 9999)
	return entry
