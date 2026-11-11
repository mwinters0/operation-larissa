class_name PackExport
extends RefCounted
## Makes a pack out of what is in the project: a CAMPAIGN in the data form (a folder, or one pack file, `<id>.larissa`) or a COMPLETE pack (`dev`, `legacy`, a copy of dev) in the data form. A pack is checked by `PackCheck`
## first, and a pack with errors is not left behind.
##
## A CAMPAIGN pack holds what the campaign needs and is laid over a complete pack (`base` in its manifest: the pack at the bottom of the chain in use unless `Options.base` says another). It holds: `campaigns/<id>.json`, its sectors `sectors/sector_NN/` (JSON and
## `.foe`), and the pictures, clips, texts, speech groups, problem
## types and durations that are the designer's own. Those come from the PACK SOURCE FOLDER `res://data/campaigns/<id>/`, laid out as a pack
## (`pictures/ui_picture/finale.png`, `audio/voice/line_a.ogg`, `texts.json`, `rules/durations.json` ...) and copied as they are; a campaign that
## already comes from an untrusted pack of the chain (an installed one, or a student's scratch pack) is exported from that pack's files instead. A picture the
## campaign names by a `res://` path (`finale_picture`, `banner`) is copied into the pack as `pictures/ui_picture/<name>.png` and named by that name.
## The sectors are exported from the game's own reader (`Catalog.sector`), whether they are `.tres` files or a pack's JSON.
##
## A COMPLETE pack (`complete`) is written the way a pack that leaves the project is held: every `.tres` of `data/` as the JSON that `ResourceJson` describes it with, the
## sectors and campaigns in the data-pack layout, the pictures, sounds and MIDI files as they are, and no `base` in the manifest.
##
## Teaches: writing what is in the project as the data a pack holds, checking it with the same rules a stranger's pack gets, and leaving nothing behind when the check fails.

## Where a campaign's own files are, next to `res://data/campaigns/<id>.tres`: a folder named after the campaign, laid out as a pack.
const SOURCE_DIR := "res://data/campaigns"
## Files of a source folder that are not the designer's content: the editor's import bookkeeping.
const SOURCE_SKIP: Array[String] = ["import", "uid"]
## How many of the exported files `Result.text` lists.
const MAX_LISTED := 40

## Where `<id>/` source folders are looked for (a test points it at a scratch folder).
static var source_dir: String = SOURCE_DIR


class Options extends RefCounted:
	## The pack's id (a lowercase word); empty: the campaign's or source pack's.
	var pack_id: StringName = &""
	## The name shown in the list; empty: the campaign's title or the source pack's title.
	var title := ""
	var version := "1.0"
	## The pack the exported pack is laid over (its manifest's `base`); empty: the complete pack at the bottom of the chain in use.
	var base: StringName = &""
	var author := ""
	var description := ""
	## A campaign or complete pack as one pack file (`<id>.larissa`, `Pack.FILE_EXTENSION`: a zip of the folder) instead of a folder.
	var archive := false
	## The playability checks' reachability search on the sectors (a few seconds each).
	var reach := true


class Result extends RefCounted:
	## What `PackCheck` said about the pack (null only when the export could not even start).
	var report: PackReport
	## Why the export could not be made at all (a campaign that does not exist ...); empty otherwise.
	var error := ""
	## The folder or pack file that was made ("" when nothing was left behind).
	var path := ""
	## What is in it: relative paths.
	var files: Array[String] = []

	func ok() -> bool:
		return error.is_empty() and report != null and report.passes() and not path.is_empty()

	## What to tell the person: the error, or the report, and where the pack is.
	func text() -> String:
		var lines := PackedStringArray()
		if not error.is_empty():
			lines.append("error: " + error)
		if report != null:
			lines.append(report.text())
		if ok():
			for rel in files.slice(0, MAX_LISTED):
				lines.append("  " + rel)
			if files.size() > MAX_LISTED:
				lines.append("  ... and %d more" % (files.size() - MAX_LISTED))
			lines.append("exported %d files to %s" % [files.size(), path])
		elif error.is_empty():
			lines.append("nothing was exported: the pack has errors")
		return "\n".join(lines)


# --- the tail every data-form export shares -----------------------------------------------------------------------------------

## True (and `result.error` set) when `pack_id` is not a pack id.
static func _bad_id(pack_id: StringName, result: Result) -> bool:
	if RegEx.create_from_string(Pack.ID_PATTERN).search(String(pack_id)) == null:
		result.error = "'%s' is not a pack id (a lowercase word of at most 32 letters, digits and _)" % pack_id
		return true
	return false


## Makes the pack `<out_dir>/<pack id>/` with `write` (called with the folder, returns "" or what went wrong), checks it with `PackCheck` and leaves it behind as a folder
## or, with `options.archive`, as the pack file `<out_dir>/<pack id>.larissa`. A pack with errors is not left behind; an earlier export of the same pack is replaced.
static func _export_data_pack(result: Result, out_dir: String, pack_id: StringName, options: Options, write: Callable) -> Result:
	var stage := "%s/%s" % [out_dir.trim_suffix("/"), pack_id]
	if DirAccess.dir_exists_absolute(stage):
		if not FileAccess.file_exists(stage + "/" + Pack.MANIFEST):
			result.error = "%s exists and is not a pack: choose another folder" % stage
			return result
		PackFiles.remove_tree(stage)                       # (an earlier export of the same pack)
	var failure: String = write.call(stage)
	if not failure.is_empty():
		result.error = failure
		PackFiles.remove_tree(stage)
		return result
	var check_options := PackCheck.Options.new()
	check_options.reach = options.reach
	result.report = PackCheck.run(Pack.open(stage), check_options)
	if not result.report.passes():
		PackFiles.remove_tree(stage)
		return result
	for rel in PackFiles.files_under(stage):
		result.files.append(rel)
	if options.archive:
		var file_path := "%s.%s" % [stage, Pack.FILE_EXTENSION]
		var error := PackFiles.zip_folder(stage, file_path, String(pack_id))
		PackFiles.remove_tree(stage)
		if error != OK:
			result.error = "cannot write %s: %s" % [file_path, error_string(error)]
			return result
		result.path = file_path
	else:
		result.path = stage
	return result


# --- a campaign in the data form --------------------------------------------------------------------------------------------

## Exports the campaign `campaign_id` into `out_dir` (a folder path, `user://` or on disk) as `<out_dir>/<pack id>/` or, with `options.archive`,
## the pack file `<out_dir>/<pack id>.larissa`.
static func campaign(campaign_id: StringName, out_dir: String, options: Options = null) -> Result:
	var result := Result.new()
	if options == null:
		options = Options.new()
	var pack_id := options.pack_id if options.pack_id != &"" else campaign_id
	if _bad_id(pack_id, result):
		return result
	var source := Catalog.campaign(campaign_id)
	if source == null:
		result.error = "there is no campaign '%s' (the campaigns are: %s)" % [campaign_id, ", ".join(PackedStringArray(Catalog.campaigns().map(func(c: Campaign) -> String: return String(c.id))))]
		return result
	return _export_data_pack(result, out_dir, pack_id, options, func(stage: String) -> String: return _write_campaign(source, stage, pack_id, options))


## A pack FOLDER you wrote by hand (the example packs of `examples/packs/`, a skin) as the pack file `<out_dir>/<pack id>.larissa`: the folder is checked by `PackCheck` (with the chain its `base` makes,
## so the pack it is laid over must be found) and zipped as it is by the same `PackFiles.zip_folder` the exports use; a folder with errors leaves no file. Nothing is converted: the folder already holds the data form.
static func archive_folder(source: String, out_dir: String, options: Options = null) -> Result:
	var result := Result.new()
	if options == null:
		options = Options.new()
	var pack := Pack.open(source)
	if not pack.is_valid():
		result.error = "%s is not a pack: %s" % [source, "; ".join(pack.errors)]
		return result
	var check_options := PackCheck.Options.new()
	check_options.reach = options.reach
	result.report = PackCheck.run(pack, check_options)
	if not result.report.passes():
		return result
	var file_path := "%s/%s.%s" % [out_dir.trim_suffix("/"), pack.id, Pack.FILE_EXTENSION]
	var error := PackFiles.zip_folder(source, file_path, String(pack.id))
	if error != OK:
		result.error = "cannot write %s: %s" % [file_path, error_string(error)]
		return result
	result.files = PackFiles.files_under(source)
	result.path = file_path
	return result


## The id of the pack a campaign is laid over:`options.base`, else the complete pack at the bottom of the chain in use ("" when there is no chain).
static func _base_of(options: Options) -> String:
	if options.base != &"":
		return String(options.base)
	var made := Packs.chain()
	return String(made.back().id) if not made.is_empty() else ""


## Writes the pack's files into `stage`. Returns "" or what went wrong.
static func _write_campaign(source: Campaign, stage: String, pack_id: StringName, options: Options) -> String:
	DirAccess.make_dir_recursive_absolute(stage)
	var manifest := Pack.new()
	manifest.id = pack_id
	manifest.title = options.title if not options.title.is_empty() else source.display_title()
	manifest.version = options.version
	manifest.author = options.author
	manifest.description = options.description
	var base := _base_of(options)
	if base.is_empty():
		return "no pack is in use to lay the campaign over: choose one with --pack=<id>, or name the base with --base=<id>"
	if base == String(Packs.DEV) and not Packs.has_dev():
		return "the base is the dev pack, which is not here. " + Packs.Fallback.ADVICE_NEEDS_DEV
	manifest.base = StringName(base)                                                       # (a pack laid over another holds only what it changes)
	ResourceJson.save_json(manifest.manifest(), stage + "/" + Pack.MANIFEST)
	var holder := Packs.pack(source.pack_id) if source.pack_id != &"" else null
	# the campaign itself: the author's file as it is when it came from a pack, else the fields of the resource
	var campaign_rel := "campaigns/%s.json" % source.id
	if holder != null and holder.has(campaign_rel):
		var error := _copy_from(holder, campaign_rel, stage)
		if error != OK:
			return "cannot copy %s: %s" % [campaign_rel, error_string(error)]
	else:
		var data := ResourceJson.new().data_of(source)
		var failure := _pictures_by_name(source, data, stage)
		if not failure.is_empty():
			return failure
		ResourceJson.save_json(data, "%s/%s" % [stage, campaign_rel])
	# its sectors
	for number in source.sectors + source.finales:
		var sector := Catalog.sector(number)
		if sector == null:
			return "sector %d does not exist" % number
		var sector_holder := Packs.sector_owner(number)
		if sector_holder != null:                          # (from a pack: its files as they are)
			for rel: String in [SectorJson.json_rel(number), SectorJson.foe_rel(number)]:
				var error := _copy_from(sector_holder, rel, stage)
				if error != OK:
					return "cannot copy %s: %s" % [rel, error_string(error)]
		else:
			var error := SectorJson.save(sector, stage)
			if error != OK:
				return "cannot write sector %d: %s" % [number, error_string(error)]
	# the designer's own pictures, clips, texts ...
	if holder != null:
		for rel in holder.all_files():
			if rel == Pack.MANIFEST or rel.begins_with("campaigns/") or rel.begins_with("sectors/"):
				continue
			var error := _copy_from(holder, rel, stage)
			if error != OK:
				return "cannot copy %s: %s" % [rel, error_string(error)]
	else:
		var folder := "%s/%s" % [source_dir, source.id]
		if DirAccess.dir_exists_absolute(folder):
			var error := PackFiles.copy_tree(folder, stage, func(rel: String) -> bool: return SOURCE_SKIP.has(rel.get_extension()) or rel == Pack.MANIFEST)
			if error != OK:
				return "cannot copy %s: %s" % [folder, error_string(error)]
	return ""


## Writes the file `rel` of `from` (a folder or a pack file: the bytes are asked of the pack, `Pack.read_bytes`) into `stage` at the same place. `OK` or the error.
static func _copy_from(from: Pack, rel: String, stage: String) -> Error:
	if not from.has(rel):
		return ERR_FILE_NOT_FOUND
	return PackFiles.write_bytes("%s/%s" % [stage, rel], from.read_bytes(rel))


## A picture of the campaign that is a `res://` file (`finale_picture`, `banner`) goes into the pack as `pictures/ui_picture/<name>.png`, and the
## JSON names it. "" or what went wrong.
static func _pictures_by_name(source: Campaign, data: Dictionary, stage: String) -> String:
	if source.finale_picture.begins_with("res://"):
		var picture_name := _picture_into(source.finale_picture, "%s_finale" % source.id, stage)
		if picture_name.is_empty():
			return "finale_picture %s is not a PNG file" % source.finale_picture
		data["finale_picture"] = picture_name
	if source.banner != null:
		var from := source.banner.resource_path
		var banner_name := _picture_into(from, "%s_banner" % source.id, stage) if from.begins_with("res://") else ""
		if banner_name.is_empty():
			return "the banner is not a PNG file of the project (%s)" % (from if not from.is_empty() else "a picture made in memory")
		data["banner"] = "pictures/ui_picture/%s.png" % banner_name
	return ""


## Copies the PNG `from` into the pack under `pictures/ui_picture/<stem>.png` (the file's own name if it is a name, else `fallback`); returns the name, or "".
static func _picture_into(from: String, fallback: String, stage: String) -> String:
	if from.get_extension() != "png":
		return ""
	var bytes := FileAccess.get_file_as_bytes(from)
	var image := Image.new()
	if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
		return ""
	var stem := from.get_file().get_basename()
	var picture_name := stem if NameRegistry.is_valid_name(stem) else fallback
	return picture_name if PackFiles.write_bytes("%s/pictures/ui_picture/%s.png" % [stage, picture_name], bytes) == OK else ""


# --- a complete pack in the data form ---------------------------------------------------------------------------------------

## Exports the complete pack `source_id` (`dev`, `legacy`, a copy of dev made by `PackCopy`: a pack of `res://packs/` or one installed) into `out_dir` as `<out_dir>/<pack id>/` or, with
## `options.archive`, the pack file `<out_dir>/<pack id>.larissa`, in the DATA FORM: nothing of it is a `.tres`, a scene or a script, so a game reads it with no `ResourceLoader`, from anywhere.
## `pack.json` names no base; `data/**.tres` is `data/**.json` at the same place (`ResourceJson`, `EngineJson`); sectors and campaigns are in the data-pack layout
## (`SectorJson`, `campaigns/<id>.json`); everything else the pack holds (`assets/`, `midi/`, `rules/`, `texts.json` ...) is copied as it is, but for the editor's
## import bookkeeping (`SOURCE_SKIP`). `options.pack_id` gives the copy another id, `title`, `author` and `description` another manifest (else the source's).
static func complete(source_id: StringName, out_dir: String, options: Options = null) -> Result:
	var result := Result.new()
	if options == null:
		options = Options.new()
	var pack_id := options.pack_id if options.pack_id != &"" else source_id
	if _bad_id(pack_id, result):
		return result
	if options.base != &"":
		result.error = "a complete pack is laid over nothing: leave --base out"
		return result
	var source := _complete_source(source_id)
	if source == null:
		result.error = "there is no pack '%s' (the packs are: %s)%s" % [source_id, ", ".join(PackedStringArray(Packs.available().map(func(each: Pack) -> String: return String(each.id)))),
				" " + Packs.Fallback.ADVICE_NEEDS_DEV if source_id == Packs.DEV else ""]
		return result
	if not source.is_valid():
		result.error = "the pack '%s' cannot be exported: %s" % [source_id, source.errors[0]]
		return result
	if source.base != &"":
		result.error = "the pack '%s' is laid over '%s', so it is not complete: export it with its base, or export a campaign" % [source_id, source.base]
		return result
	return _export_data_pack(result, out_dir, pack_id, options, func(stage: String) -> String: return _write_complete(source, stage, pack_id, options))


## The pack to export: `dev`, else the pack of that id among the packs found; null when there is none.
static func _complete_source(source_id: StringName) -> Pack:
	if source_id == Packs.DEV:
		return Packs.dev()
	for each in Packs.available():
		if each.id == source_id:
			return PackCheck.open(String(source_id))
	return null


## Writes the data form of `source` into `stage`. Returns "" or what went wrong.
static func _write_complete(source: Pack, stage: String, pack_id: StringName, options: Options) -> String:
	DirAccess.make_dir_recursive_absolute(stage)
	var manifest := Pack.new()
	manifest.id = pack_id
	manifest.title = options.title if not options.title.is_empty() else source.title
	manifest.version = options.version
	manifest.author = options.author if not options.author.is_empty() else source.author
	manifest.description = options.description if not options.description.is_empty() else source.description
	manifest.mod = source.mod
	var written := ResourceJson.save_json(manifest.manifest(), stage + "/" + Pack.MANIFEST)
	if written != OK:
		return "cannot write %s: %s" % [Pack.MANIFEST, error_string(written)]
	for rel in source.all_files():
		var failure := _write_complete_file(source, stage, rel)
		if not failure.is_empty():
			return failure
	for folder in source.folders_in("data/sectors"):                          # (a sector is its `.tres` with its screens and its script)
		var number := folder.trim_prefix("sector_").to_int()
		var sector := source.resource("data/sectors/%s/%s.tres" % [folder, folder]) as SectorData
		if sector == null:
			return "cannot read the sector %s" % folder
		var error := SectorJson.save(sector, stage)
		if error != OK:
			return "cannot write sector %d: %s" % [number, error_string(error)]
	return ""


## One file of the source: its data form, or itself. "" or what went wrong.
static func _write_complete_file(source: Pack, stage: String, rel: String) -> String:
	var extension := rel.get_extension()
	if rel == Pack.MANIFEST or SOURCE_SKIP.has(extension) or rel.begins_with("data/sectors/"):
		return ""                                                            # (the manifest is written; the sectors are written by their folders)
	if extension == "tres":
		var campaign_file := rel.begins_with("data/campaigns/")
		var resource := source.resource(rel)
		if resource == null:
			return "cannot read %s" % rel
		var writer := ResourceJson.new(source)
		var data := writer.data_of(resource)
		if not writer.problems.is_empty():
			return "%s cannot be written as data: %s" % [rel, "; ".join(writer.problems)]
		var target := "campaigns/%s.json" % rel.get_file().get_basename() if campaign_file else Pack.data_rel(rel)
		var error := ResourceJson.save_json(data, "%s/%s" % [stage, target])
		return "" if error == OK else "cannot write %s: %s" % [target, error_string(error)]
	if Pack.RESOURCE_EXTENSIONS.has(extension):
		return "%s is %s, which cannot be written as data: a pack that leaves the project holds none" % [rel, "a script" if extension in ["gd", "gdc"] else "code or a scene"]
	var error := _copy_from(source, rel, stage)
	return "" if error == OK else "cannot copy %s: %s" % [rel, error_string(error)]
