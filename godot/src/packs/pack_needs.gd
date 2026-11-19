class_name PackNeeds
extends RefCounted
## What a chain of packs must hold for the game to be playable, and what it lacks. One definition, cheap enough to run at every start (only existence checks and the
## headers of the resources, no `SectorChecks`, no reachability search, no texture decoded), used by the start-up check and by `PackCheck`.
##
## THE CLOSURE has four layers, each derived from what the code asks for:
##   * WHOLE FILES of a complete pack that `Catalog` (the cutscenes' choreography among it), `Assets`, `SpriteMeta` and the theme load through `Packs.path`: `FILES` (declared here, one list), the
##     sets of each zone (`PER_ZONE`, `PER_TILE_ZONE`) and the problem types (`Catalog.PROBLEM_TYPE_COUNT`; a type is a trusted pack's `.tres` or its `.json` in the data form).
##     `tests/engine/test_pack_needs.gd` keeps the list equal to what the dev pack holds under `data/`.
##   * PICTURES that code asks for by name: every `ui_picture` and `problem_art` name of the registry, as the KEY `Assets` asks for (`ui_picture/title_sky`): a row of some pack's `pictures.json` answers it; and the pictures of the game a mod of the chain names
##     (`ModSpec.needed_pictures`: the keys its manifest declares for its draw lists, the pictures of its theme; a mod `ModHost` refused draws nothing and counts for none): they count among `picture_keys`, so a set of packs of a higher picture scale must hold them (`PictureScale`); a key no pack
##     holds is no gap (`PackCheck` warns of it, a draw list that names it draws nothing).
##   * THINGS THE DATA NAMES: the sounds a required resource refers to (`ResourceLoader.get_dependencies`), the keys of the pictures it holds (a `PictureRef` of a `.tres`, `{"$picture": key}` of the data form, a problem type's `art_keys`: each needs a row
##     in some pack of the chain), the songs of the music catalog, the clips of the voice index. The files live inside the pack that holds the resource, so no other pack can fill them in; a key is answered by the whole chain.
##   * WHAT THE CONTENT BRINGS: each campaign `Catalog` finds in the chain: its sectors (and what a `.tres` sector refers to, a JSON sector's script), its finale picture, the
##     speech groups of its log and supply messages. The tiles, creature pictures and sounds a sector uses are slots of its zone's sets and of the sound catalog, already
##     required above; a sector's own background is not (a screen without one is plain black on purpose in the original), nor is a MIDI file (the rendered song plays).
##
## A PICTURE is answered by the packs' tables alone (a skin maps none): a row for its key in a pack that draws in this run (`PictureTable.has`; whether the row resolves is `PackCheck`'s and `Pictures`' business). A resource's own pictures are loaded with the resource.
##
## WHAT A HIGHER PICTURE SCALE MUST HOLD (`picture_keys`) is wider than what the game needs to start: besides the needs above it counts the pictures the game DRAWS when it has them and leaves out when it has not, so that a set of 4x art is chosen only when the run would show
## what it shows at scale 1: every `background` row the packs of picture scale 1 would draw (a screen with a background in them but none in the set would be black), and for a mod's wildcard `<kind>/*` every row of that kind they would draw (the mod's script names them by
## the keys of its state, so the manifest cannot list them). These are no gaps (a chain with none of them starts); they count only for the scale.
##
## THE CHAIN is an argument, so a chain that has no `dev` under it can be asked about (`chain_of`); a chain that is not the one in use is lent to `Packs` for the question.
##
## Teaches: a closure computed from the code's own constants and lookups instead of a second description that could drift, existence checks instead of loads (a path is
## cheap, a texture is not), and a result that is data (`Gap`) so that one caller shows a count and another a sentence.

## How many walks of the closure were made (`_scan`). A second walk of the same chain gives the same answer and costs only time (a walk reads the data of every sector of the chain), so no test could tell it from the effects; `test_picture_scale.gd` reads this counter
## to pin that a chain is walked once per change of the chain, and nothing else reads it.
static var walks := 0

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
	"data/story/opening.tres": "OpeningList",
	"data/story/closing_crew.tres": "ClosingCrewScripts",
	"data/ui/hud_layout.tres": "HudLayout",
	"data/ui/calculator_layout.tres": "CalculatorLayout",
	"data/problems/screen_layout.tres": "ProblemScreenLayout",
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
	## For a picture a pack has to hold: its key. The gap stands unless a pack that draws in the run has a row for it (`inspect` decides, once the run's scale is known).
	var unless_row_for := ""

	func text() -> String:
		return path if needed_by.is_empty() else "%s (%s)" % [path, needed_by]


## Everything one walk of the closure found.
class Scan extends RefCounted:
	## path -> true: every file or thing the closure asked for, present or not.
	var needed: Dictionary = {}
	## key -> true: the picture keys among them, and those the scale must hold besides (what `PictureScale` asks the packs of each scale to hold).
	var pictures: Dictionary = {}
	var gaps: Array[Gap] = []
	## What `PictureScale` made of `pictures`: the scale the run draws at; set by `inspect`.
	var decision: PictureScale.Decision

	func ask(path: String) -> void:
		needed[path] = true

	## The closure needs the picture `key` (and asks for it as a thing too).
	func ask_picture(key: String) -> void:
		needed[key] = true
		pictures[key] = true

	## A picture the scale must hold that the game does not need to start (`want_picture`'s callers say why).
	func want_picture(key: String) -> void:
		pictures[key] = true

	## The picture `key` is needed: a gap (named `path`, the key when empty, in `group`) unless a pack that draws in the run has a row for it.
	func need_picture(key: String, needed_by: String, group := GROUP_PICTURES, path := "", soft := false) -> void:
		if path.is_empty():
			needed[key] = true                                     # (a picture that is a thing of its own; a finale's is asked under its own name)
		pictures[key] = true
		lack(group, key if path.is_empty() else path, needed_by, soft)
		gaps[gaps.size() - 1].unless_row_for = key

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
	return named_by_opening().get(rel, named_by_closings().get(rel, ""))


## The files the opening names (a test reads it too), with the class each holds: each scene a `StoryScene` and each story a `StoryScript`, and what a scene names: its stage a `CutsceneStage`, each looping or one-shot timeline a `CutsceneTimeline`, as the chain in use
## gives the opening and the scenes (`Catalog.opening`, `Catalog.story_scene`). The opening names the scenes and stories, so no second list here says which they are; `FILES` holds the opening only.
static func named_by_opening() -> Dictionary:
	var named := {}
	var opening := Catalog.opening()
	if opening == null:
		return named
	for part in opening.parts:
		if part.kind == OpeningPart.STORY:
			named[Catalog.STORY_REL % part.name] = "StoryScript"
		elif part.kind == OpeningPart.SCENE:
			_name_scene(part.name, named)
	return named


## The files the closings name, as `named_by_opening` does the opening's: the scene each campaign of the chain gives as its `closing_scene` (a `StoryScene`), its stage and its timelines (a flight file is a `SubFlight`). `FILES` holds none of them.
static func named_by_closings() -> Dictionary:
	var named := {}
	for campaign in Catalog.campaigns():
		if campaign.closing_scene != &"":
			_name_scene(campaign.closing_scene, named)
	return named


## The scene `scene_name`, its stage and its timelines as files of `named`, each with its class (the ones the chain does not hold are named all the same: that they are missing is the scene's and `PackCheck`'s to say).
static func _name_scene(scene_name: StringName, named: Dictionary) -> void:
	named[Catalog.STORY_REL % scene_name] = "StoryScene"
	var scene := Catalog.story_scene(scene_name)
	if scene == null:
		return
	named[Catalog.STORY_REL % scene.stage] = "CutsceneStage"
	for timeline_name in scene.all_timelines():
		named[Catalog.STORY_REL % timeline_name] = "SubFlight" if Catalog.story_flight(timeline_name) != null else "CutsceneTimeline"


## The chain `first` and its bases make, with nothing under it: no `dev` is appended when a link is broken (the chain then stops at the broken link; `Packs.resolve`
## says why). Empty for a pack with errors.
static func chain_of(first: Pack) -> Array[Pack]:
	return Packs.resolve(first, [], false).packs


## Everything `chain` cannot answer, in the order of the groups.
static func gaps(chain: Array[Pack]) -> Array[Gap]:
	return inspect(chain).gaps


## One walk of the closure over `chain`, with its picture needs judged: the gaps (a picture is a gap unless a pack of the scale the run draws at has a row for it), and the decision of `PictureScale` made from the keys the walk found. The scale is decided from this
## walk alone (`PictureScale.decide`), so nothing here reads the run's. `Packs` asks it for the chain it starts with and keeps the decision.
static func inspect(chain: Array[Pack]) -> Scan:
	var scan := _scan(chain)
	var keys: Array[String] = []
	keys.assign(scan.pictures.keys())
	keys.sort()
	if not PictureScale.has_higher(chain):
		keys = []                                                      # (nothing to measure: the keys are not looked at)
	scan.decision = PictureScale.decide(chain, keys)
	scan.gaps = scan.gaps.filter(func(gap: Gap) -> bool: return gap.unless_row_for.is_empty() or not scan.decision.packs.any(func(each: Pack) -> bool: return each.picture_table().has(gap.unless_row_for)))
	return scan


## The paths (or names) of `gaps`, each once, sorted.
static func missing(chain: Array[Pack]) -> Array[String]:
	var found: Dictionary = {}
	for gap in gaps(chain):
		found[gap.path] = true
	var sorted: Array[String] = []
	sorted.assign(found.keys())
	sorted.sort()
	return sorted


## Every file or thing the closure asks `chain` for, each once, sorted: the set a complete chain answers.
static func required(chain: Array[Pack]) -> Array[String]:
	var sorted: Array[String] = []
	sorted.assign(_scan(chain).needed.keys())
	sorted.sort()
	return sorted


## Every picture key the closure asks `chain` for, each once, sorted (the code's names, the keys the data holds, a campaign's finale picture): the set `PictureScale` asks the packs of one scale to hold between them.
static func picture_keys(chain: Array[Pack]) -> Array[String]:
	var sorted: Array[String] = []
	sorted.assign(_scan(chain).pictures.keys())
	sorted.sort()
	return sorted


## Does `chain` answer everything?
static func is_complete(chain: Array[Pack]) -> bool:
	return gaps(chain).is_empty()


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

static func _scan(chain: Array[Pack]) -> Scan:
	walks += 1
	var scan := Scan.new()
	_files(chain, scan)
	_problem_types(chain, scan)
	if chain.is_empty():
		return scan
	var live := _is_live(chain)
	if live:
		_content(chain, scan)
	else:
		Packs.lend(chain, func() -> void: _content(chain, scan))
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
static func _content(chain: Array[Pack], scan: Scan) -> void:
	_pictures(chain, scan)
	_mod_pictures(chain, scan)
	_scale_one_pictures(chain, scan)
	_references(chain, scan)
	_problem_art(chain, scan)
	_audio(chain, scan)
	_campaigns(chain, scan)


static func _pictures(chain: Array[Pack], scan: Scan) -> void:
	var registry := NameRegistry.original()
	for kind: StringName in [&"ui_picture", &"problem_art"]:
		for picture_name: String in registry.entries(kind):
			scan.need_picture("%s/%s" % [kind, picture_name], "")


## The pictures of the game the mods of the chain name (`ModSpec.needed_pictures`), asked as keys for the scale decision. A key no pack holds is not a gap: the game goes on without it (the draw list that names it draws nothing, a theme's style is flat) and `PackCheck` warns of the mod that names it.
## A mod `ModHost` refused draws nothing, so what it names is not drawn and counts for nothing.
static func _mod_pictures(chain: Array[Pack], scan: Scan) -> void:
	for each in chain:
		if each.mod != null and not ModHost.is_refused(each.id):
			for key in each.mod.needed_pictures():
				scan.ask_picture(key)


## The pictures the scale must hold besides the needs: what the packs of picture scale 1 of `chain` would draw of the kinds the game draws when it has the picture and leaves out when it has not: every `background` (`Assets.background`: a screen with none is plain black), and every row of
## a kind a mod's wildcard `<kind>/*` names. The rows are those scale 1 would draw (`Pictures.unanswered`), so a set of 4x art that lacks one of them is not chosen (the screen would be black, the mod's picture missing, and nothing would say it). A key the packs of scale 1 would not draw
## is not counted: the game does not show it at scale 1 either, and a chain with no packs at scale 1 has no such pictures to keep.
static func _scale_one_pictures(chain: Array[Pack], scan: Scan) -> void:
	var kinds: Array[String] = ["background"]
	for each in chain:
		if each.mod != null and not ModHost.is_refused(each.id):
			for kind in each.mod.picture_kinds():
				if not kinds.has(kind):
					kinds.append(kind)
	var one := PictureScale.packs_at(chain, 1)
	for each in one:
		var table := each.picture_table()
		for key in table.keys():
			if kinds.any(func(kind: String) -> bool: return key.begins_with(kind + "/")) and Pictures.unanswered(key, one).is_empty():
				scan.want_picture(key)


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
				_tres_pictures(chain, holder, rel, scan)
			else:
				_data_references(chain, holder, rel, scan)


## The picture keys a trusted `.tres` holds (`PictureRef.keys_in_tres`), in itself and in the `PictureRef` files it names as textures (`PictureRef.texture_files_in_tres`), each of which a row of some pack of the chain must answer. The text is read, nothing is loaded.
static func _tres_pictures(chain: Array[Pack], holder: Pack, rel: String, scan: Scan) -> void:
	var text := holder.read_text(rel)
	var keys := PictureRef.keys_in_tres(text)
	for path in PictureRef.texture_files_in_tres(text):
		if Packs.has_file_at(path):
			keys.append_array(PictureRef.keys_in_tres(Packs.bytes_at(path).get_string_from_utf8()))
	for key in keys:
		scan.need_picture(key, rel)


## The files (and folders) the data form of `rel` (`holder`'s `.json`) names, each of which some pack of `chain` from the holder down must provide.
static func _data_references(chain: Array[Pack], holder: Pack, rel: String, scan: Scan) -> void:
	var data: Variant = holder.read_json(Pack.data_rel(rel))
	var below := chain.slice(maxi(chain.find(holder), 0))
	for named in ResourceJson.named_files(data):
		scan.ask(named)
		if not below.any(func(each: Pack) -> bool: return each.provides(named) or each.has_folder(named)):          # (a `$path` may name a folder)
			scan.lack(GROUP_REFERENCES, named, rel)
	for key in ResourceJson.named_pictures(data):                  # (a picture by key: the whole chain looks it up, `Pictures`)
		scan.need_picture(key, rel)


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


## The pictures of a problem type's panel (the types the chain adds too): the keys of `art_keys`, each of which a row of some pack of the chain must answer. A type is read; one that is a gap above is left alone.
static func _problem_art(chain: Array[Pack], scan: Scan) -> void:
	for type_id in Catalog.problem_type_ids():
		var stem := PROBLEM_TYPE_STEM % type_id
		if not chain.any(func(each: Pack) -> bool: return each.provides(stem + ".tres")):
			continue
		var problem := Catalog.problem_type_unskinned(type_id)
		if problem == null:
			continue
		for key in problem.art_keys:
			scan.need_picture(key, stem + ".tres")


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
static func _campaigns(chain: Array[Pack], scan: Scan) -> void:
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
			scan.need_picture(campaign.finale_picture, "", group, "finale_picture " + campaign.finale_picture, true)
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
