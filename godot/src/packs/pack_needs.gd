class_name PackNeeds
extends RefCounted
## What a chain of packs must hold for the game to be playable, and what it lacks. One definition, cheap enough to run at every start (only existence checks and the
## headers of the resources, no `SectorChecks`, no reachability search, no texture decoded), used by the start-up check and by `PackCheck`.
##
## THE CLOSURE has four layers, each derived from what the code asks for:
##   * WHOLE FILES of a complete pack that `Catalog`, `Assets`, `SpriteMeta`, `NewsCartoon` and the theme load through `Packs.path`: `FILES` (declared here, one list), the
##     sets of each zone (`PER_ZONE`, `PER_TILE_ZONE`) and the problem types (`Catalog.PROBLEM_TYPE_COUNT`; a type is a trusted pack's `.tres` or its `.json` in the data form).
##     `tests/engine/test_pack_needs.gd` keeps the list equal to what the dev pack holds under `data/`.
##   * PICTURES that code asks for by name: every `ui_picture` and `problem_art` name of the registry (`Assets` turns it into a file).
##   * THINGS THE DATA NAMES: the pictures, sounds and tiles a required resource refers to (`ResourceLoader.get_dependencies`), the files of a problem type's art, the
##     songs of the music catalog, the clips of the voice index. These live inside the pack that holds the resource, so no other pack can fill them in.
##   * WHAT THE CONTENT BRINGS: each campaign `Catalog` finds in the chain: its sectors (and what a `.tres` sector refers to, a JSON sector's script), its finale picture, the
##     speech groups of its log and supply messages. The tiles, creature pictures and sounds a sector uses are slots of its zone's sets and of the sound catalog, already
##     required above; a sector's own background is not (a screen without one is plain black on purpose in the original), nor is a MIDI file (the rendered song plays).
##
## A PICTURE a mounted pack's `pictures/` folder answers, or the skin handed in does (`GameSkin.picture`), counts as present for the pictures that `Assets` asks for by
## name and for a problem type's art. The skin is a parameter, and neither the start-up check (`Packs.choose`) nor the pack tools pass one (a pack is complete by itself, whatever skin a
## player turns on). A resource's own pictures are never covered by a skin: Godot loads them with the resource.
##
## THE CHAIN is an argument, so a chain that has no `dev` under it can be asked about (`chain_of`); a chain that is not the one in use is lent to `Packs` for the question.
##
## Teaches: a closure computed from the code's own constants and lookups instead of a second description that could drift, existence checks instead of loads (a path is
## cheap, a texture is not), and a result that is data (`Gap`) so that one caller shows a count and another a sentence.

## The groups of a gap, for a report; a campaign's own is "campaign <id>" (`CAMPAIGN_PREFIX`).
const GROUP_FILES := "files"
const GROUP_PROBLEMS := "problem types"
const GROUP_PICTURES := "pictures"
const GROUP_REFERENCES := "files the data names"
const GROUP_AUDIO := "audio"
const CAMPAIGN_PREFIX := "campaign "

## The whole files of a complete pack, relative to the pack, that the engine loads whatever the content: the one list. Each with the class it holds (the
## "class" its data form states, the `script_class` of the `.tres`; "" for a plain JSON file). The files of a folder are classed by the folder (`CLASS_OF_FOLDER`).
const FILES: Dictionary = {
	"data/zones.tres": "ZoneTable",
	"data/trigger_table.tres": "TriggerTable",
	"data/bubble_rules.tres": "BubbleRules",
	"data/neptune_tileset.tres": "TileSet",
	"data/sfx_catalog.tres": "SfxCatalog",
	"data/voice_index.tres": "VoiceIndex",
	"data/voice_cues.tres": "VoiceCues",
	"data/music_catalog.tres": "MusicCatalog",
	"data/story/news_cartoon.tres": "CutsceneTimeline",
	"data/ui/hud_layout.tres": "HudLayout",
	"data/ui/calculator_layout.tres": "CalculatorLayout",
	"data/ui/story_layout.tres": "StoryLayout",
	"data/problems/screen_layout.tres": "ProblemScreenLayout",
	"data/problems/problem_art_index.json": "",
	"data/sprite_frames/sub_frames.tres": "SpriteFrames",
	"data/sprite_frames/fx_frames.tres": "SpriteFrames",
	"data/sprite_frames/pieces_frames.tres": "SpriteFrames",
	"data/sprite_frames/station_frames.tres": "SpriteFrames",
	"data/sprite_meta/sprite_meta_common.tres": "SpriteMetaTable",
	"data/sprite_meta/sprite_meta_ink.tres": "SpriteMetaTable",
}
const CLASS_OF_FOLDER: Dictionary = {
	"data/sprite_frames/": "SpriteFrames",
	"data/sprite_meta/": "SpriteMetaTable",
	"data/problems/problem_type_": "ProblemType",
}
## The string tables are `Catalog.TEXT_TABLES`: `data/problems/<table>.tres`.
const TEXT_TABLE_REL := "data/problems/%s.tres"
## The files there is one of for each zone 0 to `Catalog.ZONE_COUNT - 1`.
const PER_ZONE: Array[String] = [
	"data/sprite_frames/foes_zone%d.tres",
	"data/sprite_meta/sprite_meta_zone%d.tres",
]
## The files there is one of for each art zone 0 to `ZoneTable.ORIGINAL_ZONES - 1` (the finale zones share the decorations of art zone 4).
const PER_TILE_ZONE: Array[String] = [
	"data/sprite_frames/decos_zone%d.tres",
]
## A problem type 0 to `Catalog.PROBLEM_TYPE_COUNT - 1`: a trusted pack's `.tres`, or its JSON in the data form.
const PROBLEM_TYPE_STEM := "data/problems/problem_type_%02d"


## One thing the chain cannot answer.
class Gap extends RefCounted:
	## `GROUP_*`, or "campaign <id>".
	var group := ""
	## The file (relative to a pack, or a `res://` path for a file a resource names), or a short name for a thing that is not a file ("sector 41", "voice group 'log_0'").
	var path := ""
	## What asks for it ("data/zones.tres", "campaign orchard"), or "".
	var needed_by := ""
	## The game goes on without it (a line that is not spoken, a picture left out) rather than breaking.
	var soft := false

	func text() -> String:
		return path if needed_by.is_empty() else "%s (%s)" % [path, needed_by]


## Everything one walk of the closure found.
class Scan extends RefCounted:
	## path -> true: every file or thing the closure asked for, present or not.
	var needed: Dictionary = {}
	var gaps: Array[Gap] = []

	func ask(path: String) -> void:
		needed[path] = true

	func lack(group: String, path: String, needed_by := "", soft := false) -> void:
		var gap := Gap.new()
		gap.group = group
		gap.path = path
		gap.needed_by = needed_by
		gap.soft = soft
		gaps.append(gap)


# --- the questions ------------------------------------------------------------------------------------------------

## The class the authoring file `rel` (`data/zones.tres`) holds, "" for a file that is none of the closure's kinds (a sector, a campaign, a file of the pack's own).
static func class_of(rel: String) -> String:
	if FILES.has(rel):
		return FILES[rel]
	for table_name in Catalog.TEXT_TABLES:
		if rel == TEXT_TABLE_REL % table_name:
			return "TextTable"
	for folder: String in CLASS_OF_FOLDER:
		if rel.begins_with(folder):
			return CLASS_OF_FOLDER[folder]
	return ""


## The chain `first` and its bases make, with nothing under it: no `dev` is appended when a link is broken (the chain then stops at the broken link; `Packs.resolve`
## says why). Empty for a pack with errors.
static func chain_of(first: Pack) -> Array[Pack]:
	return Packs.resolve(first, [], false).packs


## Everything `chain` cannot answer, in the order of the groups. `skin` (null for none) covers pictures; see the class comment.
static func gaps(chain: Array[Pack], skin: GameSkin = null) -> Array[Gap]:
	return _scan(chain, skin).gaps


## The paths (or names) of `gaps`, each once, sorted.
static func missing(chain: Array[Pack], skin: GameSkin = null) -> Array[String]:
	var found: Dictionary = {}
	for gap in gaps(chain, skin):
		found[gap.path] = true
	var sorted: Array[String] = []
	sorted.assign(found.keys())
	sorted.sort()
	return sorted


## Every file or thing the closure asks `chain` for, each once, sorted: the set a complete chain answers.
static func required(chain: Array[Pack], skin: GameSkin = null) -> Array[String]:
	var sorted: Array[String] = []
	sorted.assign(_scan(chain, skin).needed.keys())
	sorted.sort()
	return sorted


## Does `chain` answer everything?
static func is_complete(chain: Array[Pack], skin: GameSkin = null) -> bool:
	return gaps(chain, skin).is_empty()


## The gaps the game cannot go on with (not `soft`): what makes a chain incomplete.
static func hard(found: Array[Gap]) -> Array[Gap]:
	var kept: Array[Gap] = []
	kept.assign(found.filter(func(gap: Gap) -> bool: return not gap.soft))
	return kept


## The gaps the game goes on without (a line that is not spoken, a picture left out): only logged.
static func soft(found: Array[Gap]) -> Array[Gap]:
	var kept: Array[Gap] = []
	kept.assign(found.filter(func(gap: Gap) -> bool: return gap.soft))
	return kept


## The gaps by group: group -> Array[Gap], in the order the groups were found.
static func by_group(found: Array[Gap]) -> Dictionary:
	var groups: Dictionary = {}
	for gap in found:
		if not groups.has(gap.group):
			groups[gap.group] = [] as Array[Gap]
		groups[gap.group].append(gap)
	return groups


## "7 missing: data/zones.tres, data/trigger_table.tres, ... and 5 more" for a log or a label; "" for no gaps. `limit` names are shown.
static func summary(found: Array[Gap], limit := 6) -> String:
	if found.is_empty():
		return ""
	var names := PackedStringArray()
	for gap in found:
		if names.size() >= limit:
			break
		names.append(gap.path)
	var rest := found.size() - names.size()
	return "%d missing: %s%s" % [found.size(), ", ".join(names), "" if rest == 0 else " and %d more" % rest]


# --- the walk -------------------------------------------------------------------------------------------------------

static func _scan(chain: Array[Pack], skin: GameSkin) -> Scan:
	var scan := Scan.new()
	_files(chain, scan)
	_problem_types(chain, scan)
	if chain.is_empty():
		return scan
	var live := _is_live(chain)
	if live:
		_content(chain, skin, scan)
	else:
		Packs.lend(chain, func() -> void: _content(chain, skin, scan))
	return scan


static func _is_live(chain: Array[Pack]) -> bool:
	var in_use := Packs.chain()
	if in_use.size() != chain.size():
		return false
	for i in chain.size():
		if in_use[i] != chain[i]:
			return false
	return true


## The first pack of `chain` that answers for the file `rel` (`Packs.holder`, but on the given chain), or null.
static func _holder(chain: Array[Pack], rel: String) -> Pack:
	for each in chain:
		if each.provides(rel):
			return each
	return null


## Is there a file at `path`: an imported resource (picture, clip: the source file may not ship), or a plain file (a creature script)? As `Pack.has`.
static func _exists(path: String) -> bool:
	return Packs.exists_at(path) or FileAccess.file_exists(path)


static func _files(chain: Array[Pack], scan: Scan) -> void:
	var rels: Array[String] = Array(FILES.keys(), TYPE_STRING, "", null)
	for table_name in Catalog.TEXT_TABLES:
		rels.append(TEXT_TABLE_REL % table_name)
	for zone in Catalog.ZONE_COUNT:
		for pattern in PER_ZONE:
			rels.append(pattern % zone)
	for zone in ZoneTable.ORIGINAL_ZONES:
		for pattern in PER_TILE_ZONE:
			rels.append(pattern % zone)
	for rel in rels:
		scan.ask(rel)
		if _holder(chain, rel) == null:
			scan.lack(GROUP_FILES, rel)


static func _problem_types(chain: Array[Pack], scan: Scan) -> void:
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		var stem := PROBLEM_TYPE_STEM % type_id
		scan.ask(stem + ".tres")
		if not chain.any(func(each: Pack) -> bool: return each.provides(stem + ".tres")):
			scan.lack(GROUP_PROBLEMS, stem + ".tres")


## The layers that read the game's own lookups; the chain is the one in use while this runs.
static func _content(chain: Array[Pack], skin: GameSkin, scan: Scan) -> void:
	_pictures(chain, skin, scan)
	_references(chain, scan)
	_problem_art(chain, skin, scan)
	_audio(chain, scan)
	_campaigns(chain, skin, scan)


## A picture `Assets` asks for by name: the file, or a picture of a mounted pack or the skin that answers for it.
static func _picture_present(chain: Array[Pack], rel: String, skin: GameSkin) -> bool:
	if _holder(chain, rel) != null:
		return true
	return _picture_covered(chain, Packs.PROJECT_PACKS_DIR + "/_/" + rel, skin)


## Does a picture of a pack's `pictures/` folder, or the skin, answer for the picture file `path` (a path of the shape `res://packs/<id>/assets/...`)?
static func _picture_covered(chain: Array[Pack], path: String, skin: GameSkin) -> bool:
	var key := GameSkin.key_of(path)
	if key.is_empty():
		return false
	if chain.any(func(each: Pack) -> bool: return each.has("pictures/%s.png" % key)):
		return true
	return skin != null and skin.picture(key) != null


static func _pictures(chain: Array[Pack], skin: GameSkin, scan: Scan) -> void:
	var registry := NameRegistry.original()
	var ui: Dictionary = registry.entries(&"ui_picture")
	for picture_name: String in ui:
		var rel := Assets.ui_picture_rel(ui[picture_name])
		scan.ask(rel)
		if not _picture_present(chain, rel, skin):
			scan.lack(GROUP_PICTURES, rel, "ui_picture " + picture_name)
	if _holder(chain, Assets.PROBLEM_ART_INDEX_REL) == null:
		return                                                       # (the index itself is a gap above, and says which art there is)
	var art: Dictionary = registry.entries(&"problem_art")
	for picture_name: String in art:
		var rel := Assets.problem_art_rel(art[picture_name])
		if rel.is_empty():
			scan.lack(GROUP_PICTURES, "problem_art " + picture_name, Assets.PROBLEM_ART_INDEX_REL)
			continue
		scan.ask(rel)
		if not _picture_present(chain, rel, skin):
			scan.lack(GROUP_PICTURES, rel, "problem_art " + picture_name)


## What each required resource names: the pictures, tiles and sounds that Godot loads with a trusted pack's `.tres` (its header lists them), or that the
## data form of any pack names (`$ref`, `$path`: a file in the pack that holds the resource or one under it).
static func _references(chain: Array[Pack], scan: Scan) -> void:
	for rel: String in scan.needed.keys():
		if rel.get_extension() == "tres":
			var holder := _holder(chain, rel)
			if holder == null:
				continue
			if holder.trusted and holder.has(rel):
				_dependencies(holder.path_of(rel), rel, scan)
			else:
				_data_references(chain, holder, rel, scan)


## The files (and folders) the data form of `rel` (`holder`'s `.json`) names, each of which some pack of `chain` from the holder down must provide.
static func _data_references(chain: Array[Pack], holder: Pack, rel: String, scan: Scan) -> void:
	for named in ResourceJson.named_files(holder.read_json(Pack.data_rel(rel))):
		scan.ask(named)
		var below := chain.slice(maxi(chain.find(holder), 0))
		if not below.any(func(each: Pack) -> bool: return each.provides(named) or each.has_folder(named)):          # (a `$path` may name a folder: a problem type's `art_dir`)
			scan.lack(GROUP_REFERENCES, named, rel)


## The files of a pack that the resource at `path` names (the pictures, tiles and sounds Godot loads with it), as `res://packs/...` paths: its header is read, nothing is loaded.
static func named_files(path: String) -> Array[String]:
	var found: Array[String] = []
	for entry in ResourceLoader.get_dependencies(path):
		for part in entry.split("::"):                                # ("uid://...::Texture2D::res://...", or just the path)
			if part.begins_with(Packs.PROJECT_PACKS_DIR + "/"):       # (the scripts of the project are the project's)
				found.append(part)
	return found


## The files `named_files` lists that are not there.
static func absent_files(path: String) -> Array[String]:
	return named_files(path).filter(func(named: String) -> bool: return not _exists(named))


static func _dependencies(path: String, needed_by: String, scan: Scan) -> void:
	for named in named_files(path):
		scan.ask(named)
		if not _exists(named):
			scan.lack(GROUP_REFERENCES, named, needed_by)


## The files of a problem type's art (the types the chain adds too). A type is read (its art is a list of paths inside it); one that is a gap above is left alone.
static func _problem_art(chain: Array[Pack], skin: GameSkin, scan: Scan) -> void:
	for type_id in Catalog.problem_type_ids():
		var stem := PROBLEM_TYPE_STEM % type_id
		if not chain.any(func(each: Pack) -> bool: return each.provides(stem + ".tres")):
			continue
		var problem := Catalog.problem_type_unskinned(type_id)
		if problem == null:
			continue
		for path in problem.art_files:                                 # (whole paths, as the diagrams ask `Assets.texture_at`)
			scan.ask(path)
			if not _exists(path) and not _picture_covered(chain, path, skin):
				scan.lack(GROUP_REFERENCES, path, stem + ".tres")


## The songs of the music catalog (the General MIDI set; the AdLib set falls back to it) and the clips of the voice index.
static func _audio(chain: Array[Pack], scan: Scan) -> void:
	if _holder(chain, "data/music_catalog.tres") != null:
		for path in Catalog.music_catalog().gm_paths:
			scan.ask(path)
			if not _exists(path):
				scan.lack(GROUP_AUDIO, path, "data/music_catalog.tres")
	if _holder(chain, "data/voice_index.tres") != null:
		for path in Catalog.voice_index().paths:
			if path.is_empty():
				continue
			scan.ask(path)
			if not _exists(path):
				scan.lack(GROUP_AUDIO, path, "data/voice_index.tres")


## What each campaign of the chain brings.
static func _campaigns(chain: Array[Pack], skin: GameSkin, scan: Scan) -> void:
	var seen_sectors: Dictionary = {}
	for campaign in Catalog.campaigns():
		var group := CAMPAIGN_PREFIX + String(campaign.id)
		for number in campaign.sectors + campaign.finales:
			if seen_sectors.has(number):
				continue
			seen_sectors[number] = true
			_sector(chain, number, group, scan)
		if not campaign.finale_picture.is_empty():
			scan.ask("finale_picture " + campaign.finale_picture)
			if not _finale_present(chain, campaign.finale_picture, skin):
				scan.lack(group, "finale_picture " + campaign.finale_picture, "", true)
		var cues := Catalog.voice_cues()
		for voice_group: StringName in campaign.log_voices + campaign.supply_voices:
			if voice_group == &"":
				continue
			scan.ask("voice group " + String(voice_group))
			var clips := cues.clips(String(voice_group))
			if clips.is_empty():
				scan.lack(group, "voice group " + String(voice_group), "", true)
				continue
			for clip in clips:
				if not NameRegistry.original().has_name(&"voice", String(clip)) and not chain.any(func(each: Pack) -> bool: return each.has("audio/voice/%s.ogg" % clip)):
					scan.lack(group, "voice " + String(clip), "voice group " + String(voice_group), true)


## Is the picture a campaign's `finale_picture` names there? As `Campaign.finale_texture` finds it, but by existence and with no skin asked: a file, a name of the registry
## (its file in the chain, or a skin's picture when one is handed in) or a name of a pack's own `pictures/ui_picture/`.
static func _finale_present(chain: Array[Pack], picture: String, skin: GameSkin) -> bool:
	if picture.begins_with("res://"):
		return Packs.exists_at(picture)
	var number := NameRegistry.original().index_of(&"ui_picture", picture)
	if number >= 0:
		return _picture_present(chain, Assets.ui_picture_rel(number), skin)
	return chain.any(func(each: Pack) -> bool: return each.has("pictures/ui_picture/%s.png" % picture))


static func _sector(chain: Array[Pack], number: int, group: String, scan: Scan) -> void:
	var label := "sector %d" % number
	scan.ask(label)
	if not Catalog.has_sector(number):
		scan.lack(group, label)
		return
	var data_pack := Packs.sector_owner(number)
	if data_pack != null:                                             # a sector in the data form: JSON and a script
		scan.ask(SectorJson.foe_rel(number))
		if not data_pack.has(SectorJson.foe_rel(number)):
			scan.lack(group, SectorJson.foe_rel(number), label)
	else:                                                             # a complete pack's sector: the screens and the script it refers to
		_dependencies(Catalog.sector_path(number), label, scan)
