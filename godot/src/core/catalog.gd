class_name Catalog
extends RefCounted
## Static loaders for all generated game data.
##
## Teaches: `static` functions and `static var` (a cache shared by everyone),
## and one door for the resources of the packs (`Packs.resource`). Nothing here is an autoload:
## a class with only static members needs no node in the scene tree.
##
## Usage:  var sector := Catalog.sector(0)
##
## SKINS. The data that holds PICTURES (the sprite sets, the tileset, the problem types and layouts, the layouts of `data/ui/`) is
## asked for through `_skinned`: the original's resource as the pack holds it is made and cached once (`_door`), and the skin in use
## (`SkinChoice.current()`) says what to show instead (`GameSkin.skinned`): its own resource, or the same one with its pictures put in.
## The rules' data (sectors, zones, triggers, tuning, texts) never goes through a skin. With the original skin every `_skinned` is
## the very object `_door` gives.
##
## PACKS. The game is made of a chain of packs (`Packs.chain()`: the chosen pack, the pack it is laid over, and so on). Every resource named here
## is a file of a pack, `data/zones.tres`, and `Packs.resource(rel)` (`_door`) makes it from the first pack of the chain that provides it: loaded when the
## pack is the project's own (trusted), made from its data form (`data/zones.json`, `ResourceJson`) when it is not. The sectors (`sector`, `sector_ids`), the
## campaigns (`campaigns`), the words of a text (`text`) and the speech groups (`voice_cues`) also come from a pack's own layout (JSON), wherever in the chain
## it is. What the door made is kept by its pack (`Pack.forget` drops it); the sectors and campaigns made from a pack's own layout are kept in `_pack_cache` until the chain changes (`packs_changed`). The only `load()` here is of the project's
## own files and of the authoring `.tres` of sectors and campaigns (`_load`), which the editors write.

## The sectors that come from the original game: 0 to 31, the ones with original bytes (the fidelity tests, the importer, the reset
## tools). There is no fixed number of sectors any more: the sectors are the folders under `SECTORS_DIR` (`sector_ids`), and a
## sector with a higher number is one the designers made (`SectorFactory`): its files are its own source.
const ORIGINAL_SECTOR_COUNT := 32
## The highest sector number: the creature script names creatures, screens and flags per sector and the registry has 256 sector
## scopes (`NameRegistry.SECTOR_SCOPES`), and the folder name is `sector_%02d`, which simply widens for 100 and up.
const MAX_SECTOR := NameRegistry.SECTOR_SCOPES - 1
const ZONE_COUNT := 7          # 5 normal zones + Voyager finale + Expert finale
const PROBLEM_TYPE_COUNT := 34
## The largest problem type number a pack can add (the trigger table holds a type in one byte).
const LAST_PROBLEM_TYPE := 255
const SCREENS_PER_SECTOR := 12

## The project's own data, committed in `res://data/`: the rules (`rules/durations.json`, `rules/tuning.json`), the cutscene timelines, the menu layout, and the
## sectors and campaigns the designers make (under every pack of the chain).
const PROJECT_DATA_DIR := "res://data/"
## The string tables, in the order they are searched for a string id (the ids of all of them are one number space).
const TEXT_TABLES: Array[String] = ["ui_strings", "story", "hints", "log_entries", "supply_messages", "closing",
		"calc_notices", "help"]
## Where the sector folders of the PROJECT are: the sectors the designers made. The packs' are in their own `data/sectors` (`own_sector_dirs`).
const SECTORS_DIR := PROJECT_DATA_DIR + "sectors"
## Where the campaigns of the PROJECT live: `<id>.tres` for each (`Campaign`). The packs' are in their own `data/campaigns` (`own_campaign_dirs`).
const CAMPAIGNS_DIR := PROJECT_DATA_DIR + "campaigns"
## The ids of the original's two games, in the order of the old saves' `game` (0 = Voyager, 1 = Expert): the bridge between a saved `game` and a
## campaign. A save stores the campaign id; `game` is only read from files that have no id, and written next to it for these two.
const ORIGINAL_CAMPAIGNS: Array[StringName] = [&"voyager", &"expert"]

## Where the sector folders are looked for by everything that is not given a `dir` of its own: the project's `SECTORS_DIR`, and with it the packs' of the chain
## (a sector that a pack holds is read from there). A test or a tool may point it at a copy (in `user://`) for a while and put it back: it is then the
## ONLY folder (the packs' sectors are not looked at), and the game, the checks and the viewers follow.
static var sectors_dir: String = SECTORS_DIR
## Where `campaigns()` looks, as `sectors_dir` is for the sectors: `CAMPAIGNS_DIR` and the packs', unless a test (or a tool) points it at a folder of its
## own (then it is the only one) and calls `reload_campaigns`.
static var campaigns_dir: String = CAMPAIGNS_DIR

## path -> Resource. Loading the same path twice returns the same object anyway
## (ResourceLoader caches), but a Dictionary makes the idea explicit.
static var _cache: Dictionary = {}
## string id -> the name of the table that holds it; filled the first time a string is asked for by name.
static var _text_table_of: Dictionary = {}
## `campaigns()`, once read.
static var _campaign_list: Array[Campaign] = []
## "<pack id>/<file>" -> the resource a pack's JSON made (a sector, a campaign, a problem type); emptied by `packs_changed`.
static var _pack_cache: Dictionary = {}
## `voice_cues()` with the packs' groups put in; made the first time it is asked for while a pack has groups.
static var _merged_cues: VoiceCues


## A file of the PROJECT (`res://data/...`) or an authoring `.tres` of a sector or campaign (the editors write those), loaded and kept. Not for a file of a
## pack that is not one of those: that is `_door`.
static func _load(path: String) -> Resource:
	if not _cache.has(path):
		var loaded := load(path)
		if loaded == null:
			return null                  # not kept: a file that is made later (a new sector) must be found by the next call
		_cache[path] = loaded
	return _cache[path]


## The resource `rel` ("data/zones.tres") of the first pack of the chain that provides it (`Packs.resource`; the pack keeps what it made, null when
## none provides it).
static func _door(rel: String) -> Resource:
	return Packs.resource(rel)


## The resource `rel` as the skin in use shows it (see the class comment).
static func _skinned(rel: String) -> Resource:
	return SkinChoice.current().skinned(_door(rel))


## The file `file` of the project's own data folder (`res://data/`) as the skin in use shows it.
static func _skinned_project(file: String) -> Resource:
	return SkinChoice.current().skinned(_load(PROJECT_DATA_DIR + file))


## The resource `rel` ("data/ui/hud_layout.tres") of the first pack of the chain that provides it, as the pack holds it (no skin). For a scene that holds a layout
## of its own and shows it through `skinned`.
static func pack_resource(rel: String) -> Resource:
	return _door(rel)


## `resource` (one a scene or a script holds by itself, such as the HUD's layout) as the skin in use shows it. The same object with
## the original skin; for a scene that keeps its own reference to a layout and asks again when the skin changes.
static func skinned(resource: Resource) -> Resource:
	return SkinChoice.current().skinned(resource)


## `dir`, or `sectors_dir` when none is given: the folder that holds the sector folders.
static func resolve_dir(dir: String = "") -> String:
	return dir if not dir.is_empty() else sectors_dir


## Does the default arrangement hold (nobody pointed `sectors_dir` at a copy)? Then the sectors are in the packs' folders and the project's.
static func _default_dirs() -> bool:
	return sectors_dir == SECTORS_DIR


## The folder of sector folders that holds sector `index` when no `dir` is given: the first pack of the chain that has the sector, else `sectors_dir` (the
## project's, where a sector that does not exist yet is made).
static func home_dir(index: int) -> String:
	if _default_dirs():
		return own_sector_home(index)
	return sectors_dir


## The folders of sector folders of the game as it is, the chain's first: what a tool that looks at "the game's sectors" walks, whatever `sectors_dir` was
## pointed at. Each pack's `data/sectors` that is there, the chosen pack's first, then the project's own.
static func own_sector_dirs() -> Array[String]:
	return _pack_dirs("data/sectors") + [SECTORS_DIR]


## The campaign folders of the game as it is, the chain's first.
static func own_campaign_dirs() -> Array[String]:
	return _pack_dirs("data/campaigns") + [CAMPAIGNS_DIR]


## The folder `rel` of each pack of the chain that has one, the chosen pack's first.
static func _pack_dirs(rel: String) -> Array[String]:
	var found: Array[String] = []
	for each in Packs.chain():
		if each.trusted and DirAccess.dir_exists_absolute(each.path_of(rel)):         # (a `.tres` is only read from the project's own packs: no pack file, which is read-only, is ever among these folders)
			found.append(each.path_of(rel))
	return found


## The pack that holds sector `index` only as data (JSON: a pack file, an installed pack), or null. The editors write the `.tres` sector files of the packs in the project (`own_sector_dirs`,
## `home_dir`: a pack file is never one of those, `Pack.trusted`), so they never write into a pack that is not a folder of the project; this is who to name when one is asked for.
static func data_only_holder(index: int) -> Pack:
	var held := Packs.sector_owner(index)
	return held if held != null and not ResourceLoader.exists(sector_path(index, "")) else null


## The folder of sector folders that really holds sector `index` in the game as it is (a pack's, else the project's own), whatever `sectors_dir` says.
static func own_sector_home(index: int) -> String:
	for dir in own_sector_dirs():
		if ResourceLoader.exists("%s/sector_%02d/sector_%02d.tres" % [dir, index, index]):
			return dir
	return SECTORS_DIR


## Where the campaign file `<id>.tres` is in the game as it is (a pack's folder when it is there, else the project's), whatever `campaigns_dir` says.
static func own_campaign_path(id: StringName) -> String:
	for dir in own_campaign_dirs():
		if ResourceLoader.exists("%s/%s.tres" % [dir, id]):
			return "%s/%s.tres" % [dir, id]
	return "%s/%s.tres" % [CAMPAIGNS_DIR, id]


## Where a sector lives: "res://packs/legacy/data/sectors/sector_03/sector_03.tres" (or the project's own, "res://data/sectors/sector_36/..."), its creature
## script "sector_03.foe" and its screens "screen_00.tres" .. beside it. `dir` is the folder that holds the sector folders (a copy of it in a test,
## for example); without it the sector is where `home_dir` says.
static func sector_dir(index: int, dir: String = "") -> String:
	return "%s/sector_%02d" % [dir if not dir.is_empty() else home_dir(index), index]


static func sector_path(index: int, dir: String = "") -> String:
	return "%s/sector_%02d.tres" % [sector_dir(index, dir), index]


static func foe_path(index: int, dir: String = "") -> String:
	return "%s/sector_%02d.foe" % [sector_dir(index, dir), index]


# --- which sectors there are ---------------------------------------------------------------------------------------------

## Is `index` one of the original game's sectors (0 to 31)? Those have original bytes behind them; the others are the designers' own. (Only the editors and
## the fidelity checks ask; no pack is held to it.)
static func is_original_sector(index: int) -> bool:
	return index >= 0 and index < ORIGINAL_SECTOR_COUNT


## The sector number of a file under a `sector_NN/` folder (the sector, a screen, the script; a sub resource's `::` part is ignored), or -1.
static func sector_of_path(path: String) -> int:
	var folder := path.get_slice("::", 0).get_base_dir().get_file()
	if folder.begins_with("sector_") and folder.trim_prefix("sector_").is_valid_int():
		return folder.trim_prefix("sector_").to_int()
	return -1


## Is there a sector `index` (its `sector_NN.tres` under `dir`, or, for the default folder, one a mounted pack holds)?
static func has_sector(index: int, dir: String = "") -> bool:
	if index < 0 or index > MAX_SECTOR:
		return false
	return ResourceLoader.exists(sector_path(index, dir)) or (dir.is_empty() and Packs.sector_owner(index) != null)


## The numbers of the sectors found under `dir`, in order: every folder `sector_NN` that holds its `sector_NN.tres`. The folder name is
## exactly what `sector_dir` makes (two digits at least), so `sector_7` or `sector_007` are not sectors. Looked up on every call, so a
## sector made while the editor runs (`SectorFactory`) is there at once. For the default folders (no `dir`) the sectors of the packs of the chain are in the
## list too, and the sectors the packs of the chain hold as JSON.
static func sector_ids(dir: String = "") -> Array[int]:
	var found: Array[int] = []
	var with_packs := dir.is_empty()
	var folders: Array[String] = []
	if with_packs and _default_dirs():
		folders.append_array(_pack_dirs("data/sectors"))
	folders.append(resolve_dir(dir))
	for each in folders:
		for folder in DirAccess.get_directories_at(each):
			var number := folder.trim_prefix("sector_")
			if folder.begins_with("sector_") and number.is_valid_int() and not number.begins_with("-") and not number.begins_with("+"):
				var index := number.to_int()
				if folder == "sector_%02d" % index and ResourceLoader.exists("%s/%s/%s.tres" % [each, folder, folder]) and not found.has(index):
					found.append(index)
	if with_packs:
		for index in Packs.sector_ids():
			if not found.has(index):
				found.append(index)
	found.sort()
	return found


## How many sectors there are under `dir` (32 in the project as shipped).
static func sector_count(dir: String = "") -> int:
	return sector_ids(dir).size()


## The sector `step` places further along the sectors that exist (negative: back), wrapping round at both ends; for a key that steps
## through the sectors. `index` need not exist: the step then starts from where it would stand. With no sector at all it is `index`.
static func step_sector(index: int, step: int, dir: String = "") -> int:
	var ids := sector_ids(dir)
	if ids.is_empty():
		return index
	var at := ids.bsearch(index)                       # where `index` is or would be
	if at < ids.size() and ids[at] == index:
		return ids[posmod(at + step, ids.size())]
	return ids[posmod(at + step - (1 if step > 0 else 0), ids.size())]


## The existing sector whose number is closest to `index` (the lower one on a tie); `index` itself when it exists.
static func nearest_sector(index: int, dir: String = "") -> int:
	var best := index
	var best_distance := -1
	for candidate in sector_ids(dir):
		var distance := absi(candidate - index)
		if best_distance < 0 or distance < best_distance:
			best = candidate
			best_distance = distance
	return best


## The number of the last sector (31 in the project as shipped); -1 when there is none.
static func last_sector(dir: String = "") -> int:
	var ids := sector_ids(dir)
	return ids[-1] if not ids.is_empty() else -1


## The number a NEW sector gets: the lowest free one from `ORIGINAL_SECTOR_COUNT` up (the originals are never replaced), or -1 when all
## the numbers up to `MAX_SECTOR` are taken.
static func next_free_sector(dir: String = "") -> int:
	var taken := sector_ids(dir)
	for index in range(ORIGINAL_SECTOR_COUNT, MAX_SECTOR + 1):
		if not taken.has(index):
			return index
	return -1


## A sector. Its creature script (stored as text) is compiled here, once, so every
## caller sees the bytes and each creature's pc / script_hit / script_ink.
static func sector(index: int) -> SectorData:
	var holder := Packs.sector_owner(index)
	var data: SectorData
	if holder != null:
		data = _from_pack(holder, SectorJson.json_rel(index), func() -> Resource: return SectorJson.read(holder, index)) as SectorData
	else:
		data = _load(sector_path(index)) as SectorData
	if data != null:
		data.ensure_compiled()
	return data


## All campaigns, the original's two first (Voyager, Expert), then the others by id. Read once: the campaigns of each pack of the chain (its `data/campaigns`
## `.tres` files and its JSON ones), the chosen pack's first, and then `campaigns_dir`; a campaign of an id that is held already is hidden. `reload_campaigns`
## forgets them.
static func campaigns() -> Array[Campaign]:
	if _campaign_list.is_empty():
		var found: Array[Campaign] = []
		var files := Packs.campaign_files()
		for each in Packs.chain():
			if campaigns_dir == CAMPAIGNS_DIR and each.trusted:    # (a test that points `campaigns_dir` elsewhere sees only that folder's, and the packs' JSON)
				_add_campaigns(found, each.path_of("data/campaigns"))
			for file in files:
				if file["pack"] == each:
					var from_pack := _pack_campaign(each, file["id"], file["rel"])
					if from_pack != null and not found.any(func(c: Campaign) -> bool: return c.id == from_pack.id):
						found.append(from_pack)
		_add_campaigns(found, campaigns_dir)
		found.sort_custom(func(a: Campaign, b: Campaign) -> bool:
			var first := ORIGINAL_CAMPAIGNS.find(a.id) if ORIGINAL_CAMPAIGNS.has(a.id) else ORIGINAL_CAMPAIGNS.size()
			var second := ORIGINAL_CAMPAIGNS.find(b.id) if ORIGINAL_CAMPAIGNS.has(b.id) else ORIGINAL_CAMPAIGNS.size()
			return first < second or (first == second and String(a.id) < String(b.id)))
		_campaign_list = found
	return _campaign_list


## Adds the campaigns of the folder `folder` (`<id>.tres` files) to `found`, those whose id is not in it yet.
static func _add_campaigns(found: Array[Campaign], folder: String) -> void:
	for entry in ResourceLoader.list_directory(folder):
		if entry.ends_with(".tres"):
			var loaded := _load(folder + "/" + entry) as Campaign
			if loaded != null and not found.any(func(c: Campaign) -> bool: return c.id == loaded.id):
				found.append(loaded)


## The campaign called `id` ("voyager", "expert", ...), or null.
static func campaign(id: StringName) -> Campaign:
	for each in campaigns():
		if each.id == id:
			return each
	return null


## The campaign a sector belongs to (to play or a finale), or null for a sector in none. A sector is in one campaign (`Campaign.problems`).
static func campaign_of_sector(sector: int) -> Campaign:
	for each in campaigns():
		if each.contains(sector):
			return each
	return null


## The name of the game a sector belongs to ("Voyager", "Expert": the campaign's id, capitalised), for the titles of the debug views, which also
## run inside the editor, where the string tables cannot be read; "no campaign" for a sector in none.
static func campaign_name_of_sector(sector: int) -> String:
	var owner_campaign := campaign_of_sector(sector)
	return String(owner_campaign.id).capitalize() if owner_campaign != null else "no campaign"


## The campaign of an old save's `game` number (0 Voyager, 1 Expert; anything else is clamped to those): how a record without a campaign id finds
## its campaign (`PlayerProfile.campaign_id_of`). When the pack in use does not have that campaign (dev has neither) it answers the pack's first one
## (`default_campaign`), so a caller always has a campaign to start from. The player's own campaign is `PlayerProfile.campaign()`.
static func campaign_for_game(game: int) -> Campaign:
	var found := campaign(ORIGINAL_CAMPAIGNS[clampi(game, 0, ORIGINAL_CAMPAIGNS.size() - 1)])
	return found if found != null else default_campaign()


## The campaign a new player or a new Hall of Fame row gets when nothing else says: the first of `campaigns()` (the original's two lead the list,
## then the ids in order), that is, the chosen pack's own first campaign. Null only when no campaign is installed at all.
static func default_campaign() -> Campaign:
	var all := campaigns()
	return all[0] if not all.is_empty() else null


## The id of `default_campaign`; before any campaign exists, `voyager` (the id the first release wrote).
static func default_campaign_id() -> StringName:
	var found := default_campaign()
	return found.id if found != null else ORIGINAL_CAMPAIGNS[0]


## The `game` number of the campaign `id` (0 Voyager, 1 Expert), or -1 for any other: the original's way of naming the two.
static func game_of_campaign(id: StringName) -> int:
	return ORIGINAL_CAMPAIGNS.find(id)


## Forgets the campaigns read so far (a test or the editor changed the folder).
static func reload_campaigns() -> void:
	_campaign_list = []
	for path: String in _cache.keys():
		if _cache[path] is Campaign:
			_cache.erase(path)
	for key: String in _pack_cache.keys():
		if _pack_cache[key] is Campaign:
			_pack_cache.erase(key)


# --- packs ------------------------------------------------------------------------------------------------------------

## The resource `make` builds from the file `rel` of `holder`, built once and kept (null is not kept: a file that is written later is found).
static func _from_pack(holder: Pack, rel: String, make: Callable) -> Resource:
	var key := "%s/%s" % [holder.id, rel]
	if not _pack_cache.has(key):
		var made: Resource = make.call()
		if made == null:
			return null
		_pack_cache[key] = made
	return _pack_cache[key]


## The campaign in `campaigns/<id>.json` of `holder`: its id is the file's name (a file that says another id is refused), and it knows its
## pack (`Campaign.pack_id`). Null for a file that is not a campaign.
static func _pack_campaign(holder: Pack, campaign_id: StringName, rel: String) -> Campaign:
	var campaign := _from_pack(holder, rel, func() -> Resource:
		var reader := ResourceJson.new(holder)
		var read := reader.read(rel, Campaign) as Campaign
		if read == null:
			return null
		if read.id == &"":
			read.id = campaign_id
		elif read.id != campaign_id:
			push_warning("Catalog: %s/%s says the campaign is '%s'; the file's name is its id" % [holder.id, rel, read.id])
			return null
		read.pack_id = holder.id
		return read) as Campaign
	return campaign


## The chain of packs changed (`Packs.choose`, `use`, `refresh`): what was made from packs, and what depends on it, is forgotten.
static func packs_changed() -> void:
	_pack_cache.clear()
	_merged_cues = null
	_text_table_of = {}
	_campaign_list = []
	Assets.forget_folders()
	SpriteMeta.forget()
	for path: String in _cache.keys():
		if _cache[path] is Campaign:
			_cache.erase(path)
	SkinChoice.forget_all()


## What is wrong with the set of campaigns: each one's `problems()` and a sector claimed by two (the rule that lets a sector find its campaign).
static func campaign_problems() -> Array[String]:
	var found: Array[String] = []
	var owner_of := {}
	for each in campaigns():
		for problem in each.problems():
			found.append("campaign '%s': %s" % [each.id, problem])
		for sector in each.sectors + each.finales:
			if owner_of.has(sector):
				found.append("sector %d is in both '%s' and '%s'" % [sector, owner_of[sector], each.id])
			owner_of[sector] = each.id
	return found


static func zones() -> ZoneTable:
	return _door("data/zones.tres") as ZoneTable


static func zone(index: int) -> ZoneData:
	return zones().zones[index]


static func trigger_table() -> TriggerTable:
	return _door("data/trigger_table.tres") as TriggerTable


static func problem_type(index: int) -> ProblemType:
	return skinned(problem_type_unskinned(index)) as ProblemType


## Problem type `index` as its pack holds it, no skin asked (the first pack of the chain that has the type, as JSON or as a trusted pack's `.tres`). For code that
## runs where a skin is only a placeholder (the editor) or that must not depend on one (`PackNeeds`).
static func problem_type_unskinned(index: int) -> ProblemType:
	return _door(problem_type_rel(index)) as ProblemType


## The authoring path of problem type `index` in a pack (`data/problems/problem_type_05.tres`; the data form of a pack outside the project is the `.json` beside it).
static func problem_type_rel(index: int) -> String:
	return "data/problems/problem_type_%02d.tres" % index


## The problem types the chain in use has: the original's `PROBLEM_TYPE_COUNT` (0 to 33) and then the numbers (up to 255, the byte of the trigger table) of the types a pack adds, in order. A type added by a pack is
## asked only where the chain has it: a trigger table (`data/trigger_table.tres`) or a practice set of this chain names it, and the original's campaigns, which run on a chain without it, never do.
static func problem_type_ids() -> Array[int]:
	var ids: Array[int] = []
	for index in PROBLEM_TYPE_COUNT:
		ids.append(index)
	var extra := RegEx.create_from_string("^problem_type_(\\d+)\\.(?:json|tres)$")
	var added := {}
	for pack in Packs.chain():
		for file in pack.files_in("data/problems"):
			var found := extra.search(file)
			if found == null:
				continue
			var number := found.get_string(1).to_int()
			if number >= PROBLEM_TYPE_COUNT and number <= LAST_PROBLEM_TYPE and Packs.has(problem_type_rel(number)):
				added[number] = true
	var numbers := added.keys()
	numbers.sort()
	for number: int in numbers:
		ids.append(number)
	return ids


## The parts of the problem screen shared by all types (background, text box, font, palette).
static func screen_layout() -> ProblemScreenLayout:
	return _skinned("data/problems/screen_layout.tres") as ProblemScreenLayout


## The layouts of the console, the calculator, the menu bar and the story screens (where everything goes, and which pictures).
static func hud_layout() -> HudLayout:
	return _skinned("data/ui/hud_layout.tres") as HudLayout


static func calculator_layout() -> CalculatorLayout:
	return _skinned("data/ui/calculator_layout.tres") as CalculatorLayout


static func menu_layout() -> MenuBarLayout:
	return _skinned_project("ui/menu_layout.tres") as MenuBarLayout


static func story_layout() -> StoryLayout:
	return _skinned("data/ui/story_layout.tres") as StoryLayout


static func tileset() -> TileSet:
	return _skinned("data/neptune_tileset.tres") as TileSet


## SpriteFrames of the zone's decorations (slot == frame index, animation "all").
## Finale zones share the decos of art zone 4.
static func decos_frames(zone_index: int) -> SpriteFrames:
	return _skinned(_decos_rel(zone_index)) as SpriteFrames


## The same pictures as the pack in use holds them (no skin): what the skin keys of the decorations are made from (`GameSkin.key_of`).
static func pack_decos_frames(zone_index: int) -> SpriteFrames:
	return _door(_decos_rel(zone_index)) as SpriteFrames


static func _decos_rel(zone_index: int) -> String:
	return "data/sprite_frames/decos_zone%d.tres" % zone(zone_index).tile_zone


## SpriteFrames of the zone's creatures (slot == frame index, animation "all").
static func foes_frames(zone_index: int) -> SpriteFrames:
	return _skinned("data/sprite_frames/foes_zone%d.tres" % zone_index) as SpriteFrames


static func sub_frames() -> SpriteFrames:
	return _skinned("data/sprite_frames/sub_frames.tres") as SpriteFrames


static func fx_frames() -> SpriteFrames:
	return _skinned("data/sprite_frames/fx_frames.tres") as SpriteFrames


static func bubble_rules() -> BubbleRules:
	return _door("data/bubble_rules.tres") as BubbleRules


## The six sailors of the Expert closing's deck shot (`ExpertCraneTable`).
static func closing_crew() -> ClosingCrewScripts:
	return _load(PROJECT_DATA_DIR + "closing_crew.tres") as ClosingCrewScripts


static func pieces_frames() -> SpriteFrames:
	return _skinned("data/sprite_frames/pieces_frames.tres") as SpriteFrames


static func station_frames() -> SpriteFrames:
	return _skinned("data/sprite_frames/station_frames.tres") as SpriteFrames


## The station's pictures as the pack in use holds them (no skin), for their skin keys.
static func pack_station_frames() -> SpriteFrames:
	return _door("data/sprite_frames/station_frames.tres") as SpriteFrames


static func sfx_catalog() -> SfxCatalog:
	return _door("data/sfx_catalog.tres") as SfxCatalog


static func voice_index() -> VoiceIndex:
	return _door("data/voice_index.tres") as VoiceIndex


## The speech groups: the original's, with the groups of the mounted packs' `voice_cues.json` put in (a group of the same name is the pack's).
static func voice_cues() -> VoiceCues:
	var original_cues := _door("data/voice_cues.tres") as VoiceCues
	if Packs.voice_groups().is_empty():
		return original_cues
	if _merged_cues == null:
		_merged_cues = original_cues.duplicate() as VoiceCues
		_merged_cues.groups = original_cues.groups.duplicate()
		_merged_cues.groups.merge(Packs.voice_groups(), true)
	return _merged_cues


static func music_catalog() -> MusicCatalog:
	return _door("data/music_catalog.tres") as MusicCatalog


## Story / log / hint strings. `name` is one of: log_entries, supply_messages,
## hints, story, ui_strings, help, calc_notices (the three "Calculator Error" messages).
static func texts(table_name: String) -> TextTable:
	return _door("data/problems/%s.tres" % table_name) as TextTable


## A string of the original by NAME (`Catalog.text(&"click_to_go_on")`), whichever table holds it. The name is a `text`
## name of the registry (names/original.json); an unknown one is an error that says what was meant, and gives "". A mounted pack's
## `texts.json` is asked first: it can say a text of the original in other words, or have texts of its own.
## This is the resolver of the `text` kind: nothing else needs to know a string id or a table.
static func text(text_name: StringName) -> String:
	var packs_words: Variant = Packs.text(String(text_name))
	if packs_words != null:
		return packs_words
	var registry := NameRegistry.original()
	var id := registry.index_of(&"text", String(text_name))
	if id < 0:
		push_error("Catalog: " + registry.explain_unknown(&"text", String(text_name)))
		return ""
	if _text_table_of.is_empty():
		for table_name in TEXT_TABLES:
			for table_id: int in texts(table_name).ids():
				_text_table_of[table_id] = table_name
	if not _text_table_of.has(id):
		push_warning("Catalog: the string '%s' (%d) is not in any table" % [text_name, id])
		return ""
	return texts(_text_table_of[id]).text(id)


## Does the string called `text_name` exist (a name of the registry whose string the data has)? For the few that do not
## (the calculator hint has no text in the data).
static func has_text(text_name: StringName) -> bool:
	if Packs.text(String(text_name)) != null:
		return true
	var id := NameRegistry.original().index_of(&"text", String(text_name))
	if id < 0:
		return false
	for table_name in TEXT_TABLES:
		if texts(table_name).texts.has(id):
			return true
	return false
