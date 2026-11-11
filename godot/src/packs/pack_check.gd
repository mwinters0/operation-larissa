class_name PackCheck
extends RefCounted
## Is this pack sound? One function, `run(pack)`, that answers with a `PackReport`. The export tool calls it before it lets a pack
## out, the in-game pack screen calls it for the Check button, and `pack_tool.tscn --check=` calls it from a terminal: the same rules, the same words.
##
## ERRORS stop the pack (it cannot be exported or used): a manifest that is wrong, a layout the game refuses (`Pack.problems`), a base that is not
## there, a JSON file that says something the game cannot read, a campaign that
## is not playable (`Campaign.problems`, a sector it lists that nobody has), a sector that fails the playability checks (`SectorChecks`),
## a speech group that names a clip nobody has, a `rules/durations.json` or `rules/tuning.json` with a key the game does not know or a value that makes no sense, a
## picture that is not a PNG, a file the game needs that neither the pack nor the packs under it hold (`PackNeeds`), a file of a sector check that the pack lacks.
## WARNINGS only say: a clip without a measurable length or whose stated
## length is far from the file's (G2a, `ClipLengths`), a stated duration that is merely odd, a sector in no campaign, a song or voice
## group that resolves to nothing (the game goes on without it), files the game never reads.
##
## THE CONTENT IS LOOKED AT AS THE GAME WILL SEE IT. The pack is made the chosen pack for the duration of the check if it is not already (`_with_chain`),
## with the chain its `base` links make, so `Catalog.sector`, `Campaign.problems`, the name lookups and the playability checks are the real ones, not a second
## reader that could disagree; the chain in use is put back afterwards. The names a pack uses resolve in the pack or in the packs it is laid over.
##
## Teaches: validation as the same code path as use (check by loading, not by a parallel description), and a result that is data.

## The songs a campaign names when it names none (`Campaign.DEFAULT_SONG`) and the closing scenes the game has of its own.
const OWN_CLOSINGS: Array[StringName] = [&"voyager", &"expert"]
## How many names of what is missing one finding shows.
const NEEDS_SHOWN := 5


class Options extends RefCounted:
	## Run the playability checks on the pack's sectors at all.
	var sectors := true
	## The reachability search of the playability checks (a few seconds per sector). Off for a quick look.
	var reach := true
	## Does the chain hold every file the game needs (`PackNeeds`)? Cheap, so on even for a quick look.
	var needs := true


## The pack at `where`: a folder with a `pack.json`, or the id of a pack that was found (`dev` among them). Never null; check `errors`. For the command line and the
## dialog that is given a path.
static func open(where: String) -> Pack:
	if not where.contains("/") and not where.contains("\\"):
		for each in Packs.available():
			if String(each.id) == where:
				return each
		if where == String(Packs.DEV) and Packs.has_dev():
			return Packs.dev()
	return Pack.open(where)


## The report on `pack` (the chosen pack or another). The chain in use is as it was afterwards.
static func run(pack: Pack, options: Options = null) -> PackReport:
	if options == null:
		options = Options.new()
	var report := PackReport.new()
	report.describe(pack)
	for message in pack.errors:
		report.error("manifest", message)
	if not pack.is_valid():
		return report
	for message in pack.problems():
		if not pack.errors.has(message):
			report.error("layout", message)
	_chain(pack, report)
	if pack.sector_ids().is_empty() and pack.campaign_ids().is_empty() and pack.mod == null and report.passes():
		if not pack.has("texts.json") and pack.folders_in("pictures").is_empty() and pack.folders_in("audio").is_empty() and not pack.has(Durations.PACK_PATH) and not pack.has(Tuning.PACK_PATH):
			report.warn("layout", "the pack holds nothing the game reads (no campaign, sector, text, picture, clip, durations, rule values or mod)")
	_with_chain(pack, func(live: Pack) -> void:
		_content(live, report, options)
		if options.needs:
			_needs(live, report))
	return report


# --- the pack in the chain it will be used in ----------------------------------------------------------------------------------

## The chain the pack would be used in is made of it and the packs its `base` names, and so on. Errors: a base that is not there, a base with errors,
## links that go round in a circle.
static func _chain(pack: Pack, report: PackReport) -> void:
	var made := Packs.resolve(pack)
	if made.fallback == null:
		return
	match made.fallback.why:
		Packs.Fallback.Why.MISSING_BASE when made.fallback.needs_dev():
			report.error("base", "the pack is laid over the dev pack, which is not here. " + Packs.Fallback.ADVICE_NEEDS_DEV)
		Packs.Fallback.Why.MISSING_BASE:
			report.error("base", "the pack is laid over '%s', which is not installed (packs are found in %s and %s)" % [made.fallback.detail, Packs.PROJECT_PACKS_DIR, Packs.USER_PACKS_DIR])
		Packs.Fallback.Why.CYCLE:
			report.error("base", "the pack '%s' is laid over itself through its bases" % made.fallback.pack_id)
		_:
			report.error("base", made.fallback.text())


## Makes `pack` the chosen pack (with the chain under it) while `body` (called with the pack as the chain holds it) runs, unless it is the chosen pack already; the
## chain in use is put back afterwards.
static func _with_chain(pack: Pack, body: Callable) -> void:
	var current := Packs.chosen()                              # (null when the game refused its choice and holds no pack)
	if current != null and current.root == pack.root:
		body.call(current)
		return
	var saved := Packs.snapshot()
	Packs.use(pack)
	body.call(Packs.chosen())
	Packs.restore(saved)


# --- the content ------------------------------------------------------------------------------------------------------------------

static func _content(live: Pack, report: PackReport, options: Options) -> void:
	_mod(live, report)
	_data_files(live, report)
	_texts(live, report)
	_voice_cues(live, report)
	_pictures(live, report)
	_audio(live, report)
	_durations(live, report)
	_tuning(live, report)
	_campaigns(live, report)
	_sectors(live, report, options)


## Does the chain the pack is used in hold everything the game needs? One error per group of what is missing, with a few names. A pack whose chain cannot be made is
## left alone (`_chain` said so). The campaigns are not looked at again: `_campaigns` judges the pack's own.
static func _needs(live: Pack, report: PackReport) -> void:
	if Packs.resolve(live, [], false).fallback != null:
		return
	var found: Array[PackNeeds.Gap] = []
	for gap in PackNeeds.gaps(Packs.chain()):
		if not gap.group.begins_with(PackNeeds.CAMPAIGN_PREFIX):
			found.append(gap)
	var groups := PackNeeds.by_group(found)
	for group: String in groups:
		report.error("needs", "%s the game needs, that neither this pack nor the packs under it hold (%s)" % [group, PackNeeds.summary(groups[group], NEEDS_SHOWN)])


## Reads a JSON file of the pack; a file that is not JSON is an error that says where. Null for a missing file or an error.
static func _json(live: Pack, rel: String, report: PackReport, area: String) -> Variant:
	if not live.has(rel):
		return null
	var parser := JSON.new()
	if parser.parse(live.read_text(rel)) != OK:
		report.error(area, "%s line %d: %s" % [rel, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data


## The resources a pack holds in the data form (`data/**/*.json`, the data form of `data/**/*.tres`): each parses, says the class its place calls for (`PackNeeds.class_of`;
## elsewhere any class of the game's) and has no field the class lacks and no value of the wrong kind. The plain data file `problem_art_index.json` is only parsed.
static func _data_files(live: Pack, report: PackReport) -> void:
	for rel in live.all_files():
		if not rel.begins_with("data/") or rel.get_extension() != "json":
			continue
		var raw: Variant = _json(live, rel, report, "data")
		if raw == null:
			continue
		if rel == Assets.PROBLEM_ART_INDEX_REL:
			continue
		if not raw is Dictionary:
			report.error("data", "%s must be a JSON object" % rel)
			continue
		var expected := PackNeeds.class_of(Pack.data_rel_to_authoring(rel))
		var said := String(raw.get(ResourceJson.CLASS_KEY, ""))
		var script: Script = ResourceJson.script_named(expected) if not expected.is_empty() else null
		if not expected.is_empty() and said != expected and not (said.is_empty() and script != null):
			report.error("data", "%s is a %s, but says it is %s" % [rel, expected, "no class" if said.is_empty() else said])
			continue
		if expected.is_empty() and not (EngineJson.handles(said) or ResourceJson.script_named(said) != null):
			report.error("data", "%s says its class is '%s', which the game does not know" % [rel, said])
			continue
		var reader := ResourceJson.new(live)
		var made := reader.read(rel, script)
		for problem in reader.problems:
			report.error("data", "%s: %s" % [rel, problem])
		if made == null and reader.problems.is_empty():
			report.error("data", "%s cannot be read" % rel)


## A mod pack's script (a data skin has none): the manifest entry (`Pack.mod`, read by `ModSpec`, whose errors are the manifest's) names a `.sgd` file the pack holds, within the size limit, with a
## `mod_init(api)`, and defines the function of everything the manifest lists (`ModSpec.functions`: `skin_layer` or `skin_frame`, `problem_frame`, the rule hooks). What the pack must hold for it (acceptable shaders and pictures of a skin or of problem screens, the pictures a skin maps, each problem type it draws or judges as data) is `ModParts.problems`. A `.sgd` file the manifest does not name is never run.
## (Whether it compiles is known only to the Sandbox, when the mod is loaded: `ModHost.failure`.)
static func _mod(live: Pack, report: PackReport) -> void:
	var scripts: Array[String] = []
	for rel in live.all_files():
		if rel.get_extension() == ModSpec.SCRIPT_EXTENSION:
			scripts.append(rel)
	if live.mod != null:
		if live.mod.has_entry():
			_entry_script(live, report)
		for message in ModParts.problems(live):
			report.error("mod", message)
		var sizes: Dictionary = SkinTemplates.sizes() if not live.mod.pictures.is_empty() else {}
		for key in live.mod.pictures:
			if not _game_names_picture(key):
				report.warn("mod", "the skin's picture %s names no picture of the game: it is never asked for" % key)
			else:
				_picture_size(live, key, sizes, report)
		for key in live.mod.theme_pictures():
			if ModSpec.is_picture_key(key) and not live.mod.pictures.has(key) and not _game_names_picture(key):
				report.warn("mod", "the theme's picture %s is neither one the skin maps nor one of the game's: the style is drawn flat" % key)
		scripts.erase(live.mod.entry)
	for rel in live.all_files():
		if rel.get_extension() == Pack.FONT_EXTENSION and (live.mod == null or not live.mod.font_files().has(rel)):
			report.warn("mod", "%s is never used: %s" % [rel, "a skin names its font in \"skin\": {\"hud_font\": {\"file\": ...}} or {\"theme\": {\"font\": {\"file\": ...}}}" if live.mod != null and live.mod.is_skin else "a font is read by a skin mod only"])
	for rel in scripts:
		report.warn("mod", "%s is never run: %s" % [rel, "a mod pack's manifest names one entry script (\"mod\": {\"entry\": ...})" if live.mod != null else "the manifest has no \"mod\" entry"])


## A warning when the skin's PNG for `key` is not the size of the picture it replaces (the game draws it stretched to the place of the original's). `sizes` are the ones the art templates have (`SkinTemplates.sizes`, from the layouts of the pack in use), so the two cannot disagree; a picture no layout holds is not judged.
static func _picture_size(live: Pack, key: String, sizes: Dictionary, report: PackReport) -> void:
	var texture := live.texture(live.mod.pictures[key])
	var wanted: Vector2i = sizes.get(key, Vector2i.ZERO)
	if texture != null and wanted != Vector2i.ZERO and Vector2i(texture.get_size()) != wanted:
		report.warn("mod", "the skin's picture %s is %dx%d, and the picture it replaces is %dx%d: it is drawn stretched to that place" % [key, texture.get_width(), texture.get_height(), wanted.x, wanted.y])


## Does the game's own registry name the picture a skin key (`<kind>/<name>`) says? A skin that replaces a picture the game never asks for changes nothing.
static func _game_names_picture(key: String) -> bool:
	return NameRegistry.original().index_of(StringName(key.get_slice("/", 0)), key.get_slice("/", 1)) >= 0


## The entry script of the mod `live`: in the pack, within the size limit, with `mod_init(api)` and the functions the manifest lists.
static func _entry_script(live: Pack, report: PackReport) -> void:
	var entry := live.mod.entry
	if not live.has(entry):
		report.error("mod", "the entry script %s is not in the pack" % entry)
		return
	var bytes := live.read_bytes(entry)
	var source := bytes.get_string_from_utf8()
	if bytes.size() > ModSpec.MAX_SOURCE_BYTES:
		report.error("mod", "%s is larger than %d bytes" % [entry, ModSpec.MAX_SOURCE_BYTES])
	elif source.strip_edges().is_empty():
		report.error("mod", "%s is empty or not UTF-8 text" % entry)
	elif RegEx.create_from_string("(?m)^func\\s+mod_init\\s*\\(").search(source) == null:
		report.error("mod", "%s defines no mod_init(api): it is where a mod starts" % entry)
	else:
		var needed := live.mod.functions()
		for function in needed:
			var found := RegEx.create_from_string("(?m)^func\\s+%s\\s*\\(([^)]*)\\)" % function).search(source)
			if found == null:
				report.error("mod", "%s defines no %s: the manifest lists what is asked of it" % [entry, ModSpec.signature(function, needed[function])])
			elif found.get_string(1).split(",", false).size() != needed[function].size():
				report.error("mod", "%s defines %s with %d argument(s): the game calls it as %s (the \"requires_api\" of the manifest says which)" % [entry, function, found.get_string(1).split(",", false).size(), ModSpec.signature(function, needed[function])])


static func _texts(live: Pack, report: PackReport) -> void:
	var words: Variant = _json(live, "texts.json", report, "texts")
	if words == null:
		return
	if not words is Dictionary:
		report.error("texts", "texts.json must be an object {\"text_name\": \"the words\"}")
		return
	for key: String in words:
		if not words[key] is String:
			report.error("texts", "texts.json: '%s' is not a string" % key)
		elif not NameRegistry.is_valid_name(key):
			report.warn("texts", "texts.json: '%s' %s, so nothing can name it" % [key, NameRegistry.name_problem(key)])


static func _voice_cues(live: Pack, report: PackReport) -> void:
	var cues: Variant = _json(live, "voice_cues.json", report, "voice cues")
	if cues == null:
		return
	if not (cues is Dictionary and cues.get("groups") is Dictionary):
		report.error("voice cues", "voice_cues.json must be {\"groups\": {\"group name\": [\"voice name\", ...]}}")
		return
	for group: String in cues["groups"]:
		if not cues["groups"][group] is Array:
			report.error("voice cues", "group '%s' must be a list of voice names" % group)
			continue
		for clip_name: Variant in cues["groups"][group]:
			if not clip_name is String:
				report.error("voice cues", "group '%s' holds something that is not a name" % group)
			elif not NameRegistry.original().has_name(&"voice", clip_name) and not live.has("audio/voice/%s.ogg" % clip_name):
				report.error("voice cues", "group '%s' names the voice '%s', which is neither one of the game's nor a file of the pack (audio/voice/%s.ogg)" % [group, clip_name, clip_name])


static func _pictures(live: Pack, report: PackReport) -> void:
	for kind in live.folders_in("pictures"):
		if not GameSkin.KEY_KINDS.has(kind):
			report.warn("pictures", "pictures/%s: the game looks for pictures in %s only" % [kind, ", ".join(GameSkin.KEY_KINDS)])
			continue
		for file in live.files_in("pictures/" + kind):
			var rel := "pictures/%s/%s" % [kind, file]
			if file.get_extension() != "png":
				report.warn("pictures", "%s: only .png pictures are read" % rel)
			elif live.texture(rel) == null:
				report.error("pictures", "%s is not a PNG picture the engine can decode" % rel)
			elif not NameRegistry.is_valid_name(file.get_basename()):
				report.warn("pictures", "%s: '%s' %s, so no picture key names it" % [rel, file.get_basename(), NameRegistry.name_problem(file.get_basename())])


static func _audio(live: Pack, report: PackReport) -> void:
	for kind in live.folders_in("audio"):
		if not Packs.CLIP_KINDS.has(StringName(kind)):
			report.warn("audio", "audio/%s: the game looks for clips in %s only" % [kind, ", ".join(Packs.CLIP_KINDS)])
			continue
		for file in live.files_in("audio/" + kind):
			if file.get_extension() != "ogg":
				report.warn("audio", "audio/%s/%s: only .ogg (Vorbis) clips are read" % [kind, file])
			elif not NameRegistry.is_valid_name(file.get_basename()):
				report.warn("audio", "audio/%s/%s: '%s' %s, so nothing can name the clip" % [kind, file, file.get_basename(), NameRegistry.name_problem(file.get_basename())])
	for message in live.clip_warnings():
		report.warn("audio", message)


static func _durations(live: Pack, report: PackReport) -> void:
	var layer: Variant = _json(live, Durations.PACK_PATH, report, "durations")
	if layer == null:
		return
	var errors: Array[String] = []
	var warnings: Array[String] = []
	Durations.check(layer, errors, warnings)
	for message in errors:
		report.error("durations", message)
	for message in warnings:
		report.warn("durations", message)


static func _tuning(live: Pack, report: PackReport) -> void:
	var layer: Variant = _json(live, Tuning.PACK_PATH, report, "tuning")
	if layer == null:
		return
	var errors: Array[String] = []
	var warnings: Array[String] = []
	Tuning.check(layer, errors, warnings)
	for message in errors:
		report.error("tuning", message)
	for message in warnings:
		report.warn("tuning", message)


static func _campaigns(live: Pack, report: PackReport) -> void:
	for campaign_id in live.campaign_ids():
		var area := "campaign %s" % campaign_id
		var rel := "campaigns/%s.json" % campaign_id
		var reader := ResourceJson.new(live)
		var campaign := reader.read(rel, Campaign) as Campaign
		for problem in reader.problems:
			report.error(area, "%s: %s" % [rel, problem])
		if campaign == null:
			continue
		if campaign.id != &"" and campaign.id != campaign_id:
			report.error(area, "%s says the campaign is '%s'; the file's name is its id" % [rel, campaign.id])
			continue
		var live_campaign := Catalog.campaign(campaign_id)           # (as the game reads it: it knows its pack, its picture resolves)
		if live_campaign == null:
			report.error(area, "the game does not find the campaign (see above)")
			continue
		for problem in live_campaign.problems():
			report.error(area, problem)
		_campaign_content(live_campaign, live, report, area)


static func _campaign_content(campaign: Campaign, live: Pack, report: PackReport, area: String) -> void:
	for mod in campaign.mods:
		var holder := Packs.pack(mod)
		if holder == null or holder.mod == null or not holder.mod.has_rules:
			report.warn(area, "mod '%s' is no mod pack with rule hooks in the chain: a run of this campaign plays without it" % mod)
	for sector in campaign.sectors + campaign.finales:
		if not Catalog.has_sector(sector):
			report.error(area, "sector %d is not in this pack, nor in the packs it is laid over" % sector)
		var owner_campaign := Catalog.campaign_of_sector(sector)
		if owner_campaign != null and owner_campaign != campaign:
			report.error(area, "sector %d is also in the campaign '%s'" % [sector, owner_campaign.id])
	if not _files_lacking().is_empty():                  # (the speech groups and songs are read from files the chain lacks: `_needs` says which)
		return
	var cues := Catalog.voice_cues()
	for group: StringName in campaign.log_voices + campaign.supply_voices:
		if group != &"" and cues.clips(String(group)).is_empty():
			report.warn(area, "voice group '%s' has no clips: that line is not spoken" % group)
	if campaign.fallback_song != Campaign.DEFAULT_SONG and MusicCatalog.id_of(campaign.fallback_song) < 0 and Packs.clip(&"music", campaign.fallback_song) == null:
		report.warn(area, "fallback_song '%s' is neither one of the game's songs nor audio/music/%s.ogg of the pack: sectors without a song are silent" % [campaign.fallback_song, campaign.fallback_song])
	if campaign.closing_scene != &"" and not OWN_CLOSINGS.has(campaign.closing_scene):
		report.warn(area, "closing_scene '%s' is none of %s: the generic finale plays" % [campaign.closing_scene, ", ".join(PackedStringArray(OWN_CLOSINGS.map(func(s: StringName) -> String: return String(s))))])
	if campaign.finales.is_empty():
		report.warn(area, "no finale: the game never ends")


static func _sectors(live: Pack, report: PackReport, options: Options) -> void:
	var lacking := _files_lacking()
	var in_a_campaign := {}
	for campaign_id in live.campaign_ids():
		var each := Catalog.campaign(campaign_id)
		if each != null and each.pack_id == live.id:
			for sector in each.sectors + each.finales:
				in_a_campaign[sector] = true
	for number in live.sector_ids():
		var area := "sector %d" % number
		var reader := ResourceJson.new(live)
		reader.skip = PackedStringArray([SectorJson.SCRIPT_FIELD])
		var raw: Variant = live.read_json(SectorJson.json_rel(number))
		var parsed := reader.read(SectorJson.json_rel(number), SectorData) as SectorData
		for problem in reader.problems:
			report.error(area, "%s: %s" % [SectorJson.json_rel(number), problem])
		if parsed == null:
			continue
		if raw is Dictionary:
			if raw.has("index") and int(raw["index"]) != number:
				report.error(area, "the file is in the folder of sector %d but says it is sector %d" % [number, int(raw["index"])])
			var script_rel := "%s/%s" % [SectorJson.folder_rel(number), String(raw.get(SectorJson.SCRIPT_FIELD, "sector_%02d.foe" % number))]
			if not live.has(script_rel):
				report.error(area, "no creature script %s" % script_rel)
				continue
		if not in_a_campaign.has(number):
			report.warn(area, "no campaign of this pack lists it")
		if not lacking.is_empty():                       # (the catalogs and tables below are read from files the chain lacks)
			if options.sectors and not options.needs:    # (with `needs` on, `_needs` says what is missing)
				report.error(area, "cannot be checked: the chain lacks files the sector checks read (%s)" % PackNeeds.summary(lacking, NEEDS_SHOWN))
			continue
		if not parsed.music_name.is_empty() and MusicCatalog.song_of_stem(parsed.music_name) == &"":
			report.warn(area, "music_name '%s' is none of the game's songs nor audio/music/%s.ogg of the pack: the campaign's fallback song plays" % [parsed.music_name, parsed.music_name])
		if not options.sectors:
			continue
		var sector := Catalog.sector(number)
		if sector == null:
			report.error(area, "the game could not read the sector")
			continue
		var check_options := SectorChecks.Options.new()
		check_options.reach = options.reach
		for finding in SectorChecks.check(sector, check_options):
			if finding.fails():
				report.add(PackReport.Severity.ERROR if finding.severity == CheckFinding.Severity.ERROR else PackReport.Severity.WARNING, area, _finding_text(finding))


## The files the game always needs that the chain in use lacks (the trigger table, the zones ...): the sector checks read them, so they are not run without.
static func _files_lacking() -> Array[PackNeeds.Gap]:
	var found: Array[PackNeeds.Gap] = []
	for gap in PackNeeds.gaps(Packs.chain()):
		if gap.group == PackNeeds.GROUP_FILES:
			found.append(gap)
	return found


## "screen 3 piece 2: no position the sub can reach touches it [reach.piece]": a playability finding without the sector (the area says it).
static func _finding_text(finding: CheckFinding) -> String:
	var where := ""
	if finding.screen >= 0:
		where = "screen %d " % finding.screen
	if not finding.object.is_empty():
		where += finding.object + " "
	return "%s%s%s  [%s]" % [where, ": " if not where.is_empty() else "", finding.message, finding.check]
