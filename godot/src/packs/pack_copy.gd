class_name PackCopy
extends RefCounted
## Starts a pack of your own by copying one: `pack_tool --new=<id> --from=dev` (and the editor's Project > Tools > "New pack...") copies the pack `<from>` (the folder
## `res://packs/<from>`, else any pack found: an installed folder, a pack file) to the folder `res://packs/<id>`, so you have a complete game, every file of it a placeholder you can replace one by one.
##
## A plain copy would not work. The files of a pack name each other by path (`res://packs/dev/assets/...` inside every `.tres`, `.tscn` and `.import`), and the
## engine knows each imported file and resource by a UID (`uid://...`, in the `.import` file, in the first line of a `.tres`/`.tscn`, in a `.foe.uid` file next to
## the file). Two files with the same UID are a clash: the engine keeps one and complains about the other. So the copy
##   1. rewrites every `res://packs/<from>/` to `res://packs/<id>/` in the text files (`.tres`, `.tscn`, `.import`, `.json`),
##   2. gives every file that HAS a UID a new one, and changes every mention of the old UID in the copy (the UID of a script of the game, which the copy
##      only refers to, stays: only the UIDs of the copied files change),
##   3. points each `.import` at the cache name of its new path (`.godot/imported/<file>-<md5 of the source path>.ctex`, so the copy does not share the original's
##      cached pictures), which the next import fills in,
##   4. writes a new `pack.json`: the new id and title, no `base` (the copy is as complete as its source).
## It refuses an id that is taken or reserved (`dev`). The engine imports the copy the next time the editor has the focus or `godot --headless --path godot --import` runs.
##
## Teaches: why a copy is not always a copy (identity by path and by UID), and a rewrite that must change exactly what it means to: it looks UIDs up in a table
## of the copy's own files, not with a pattern that would also catch the UIDs of the game's scripts.

## Files whose text is rewritten; every other file is copied byte for byte.
const TEXT_EXTENSIONS: Array[String] = ["tres", "tscn", "import", "json", "uid"]

## The folder packs are copied in (a test could point it elsewhere, but the paths inside the files only mean something under `res://packs/`).
static var packs_dir := Packs.PROJECT_PACKS_DIR

static var _uid_pattern: RegEx


class Result extends RefCounted:
	var ok := false
	var id: StringName = &""
	## The new folder.
	var path := ""
	## How many files the copy holds, and how many got a new UID.
	var files := 0
	var new_uids := 0
	## What happened, in a sentence.
	var message := ""


## Copies the pack `from` to the folder `res://packs/<new_id>`. `title` is the new pack's title ("" makes one from the id).
static func make(new_id: StringName, from: StringName = Packs.DEV, title := "") -> Result:
	var result := Result.new()
	var refusal := _refusal(new_id, from)
	if not refusal.is_empty():
		result.message = refusal
		return result
	var source := _source_pack(from)
	var target := "%s/%s" % [packs_dir, new_id]
	var failure := _copy(source, target, from, new_id, title, result)
	if not failure.is_empty():
		PackFiles.remove_tree(target)
		result.ok = false
		result.message = failure
		return result
	result.ok = true
	result.id = new_id
	result.path = target
	result.message = "made the pack '%s' in %s from '%s' (%d files, %d with a new UID). Open the project in the editor, or run `godot --headless --path godot --import`, to import it; then `--pack=%s` plays it." % [
			new_id, target, from, result.files, result.new_uids, new_id]
	return result


## Why `new_id` cannot be made from `from`, or "".
static func _refusal(new_id: StringName, from: StringName) -> String:
	if RegEx.create_from_string(Pack.ID_PATTERN).search(String(new_id)) == null:
		return "'%s' is not a pack id (a lowercase word, letters, digits and _, at most 32 characters)" % new_id
	if new_id == Packs.DEV:
		return "'dev' is reserved for the dev pack: give your copy an id of its own"
	if DirAccess.dir_exists_absolute("%s/%s" % [packs_dir, new_id]):
		return "there is already a pack '%s' in %s" % [new_id, packs_dir]
	for each in Packs.available():
		if each.id == new_id:
			return "there is already a pack '%s' (%s)" % [new_id, each.root]
	if from == Packs.DEV and not Packs.has_dev():
		return "there is no dev pack to copy: %s" % Packs.Fallback.ADVICE_NEEDS_DEV
	if _source_pack(from) == null:
		return "there is no pack '%s' to copy" % from
	return ""


## The pack to copy: the folder `from` of `packs_dir`, else the pack of that id that was found (`dev()`, `Packs.available()`: an installed folder or a pack file, which `Pack` reads alike). Null when there is none.
static func _source_pack(from: StringName) -> Pack:
	var folder := Pack.open("%s/%s" % [packs_dir, from])
	if folder.has(Pack.MANIFEST):
		return folder
	if from == Packs.DEV:
		return Packs.dev()
	for each in Packs.available():
		if each.id == from:
			return each
	return null


## Does the copy; "" or what went wrong.
static func _copy(source: Pack, target: String, from: StringName, new_id: StringName, title: String, result: Result) -> String:
	var files := source.all_files()
	var table := _new_uids(source, files)
	result.files = files.size()
	result.new_uids = table.size()
	var old_prefix := "res://packs/%s/" % from
	var new_prefix := "res://packs/%s/" % new_id
	for rel in files:
		var to_file := "%s/%s" % [target, rel]
		var error: Error
		if TEXT_EXTENSIONS.has(rel.get_extension()):
			error = PackFiles.write_text(to_file, _rewritten(rel, source.read_text(rel), old_prefix, new_prefix, table))
		else:
			error = PackFiles.write_bytes(to_file, source.read_bytes(rel))
		if error != OK:
			return "cannot write %s: %s" % [to_file, error_string(error)]
	return _write_manifest(source, target, from, new_id, title)


## old UID text -> new UID text, for every file of the pack that has a UID of its own.
static func _new_uids(source: Pack, files: Array[String]) -> Dictionary:
	var table := {}
	var taken := {}
	for rel in files:
		var old := own_uid(rel, source.read_text(rel)) if _has_uid_place(rel) else ""
		if old.is_empty() or table.has(old):
			continue
		var fresh := ""
		while fresh.is_empty() or taken.has(fresh):
			var id := ResourceUID.create_id()
			if ResourceUID.has_id(id):
				continue
			fresh = ResourceUID.id_to_text(id)
		taken[fresh] = true
		table[old] = fresh
	return table


static func _has_uid_place(rel: String) -> bool:
	return ["import", "tres", "tscn", "uid"].has(rel.get_extension())


## The UID that the file `rel` has of its own, given its text: the `uid=` of an `.import` file, the one in the first line of a `.tres`/`.tscn`, the whole
## content of a `.uid` file. "" when it has none.
static func own_uid(rel: String, text: String) -> String:
	match rel.get_extension():
		"import":
			var found := RegEx.create_from_string("(?m)^uid=\"(uid://[a-z0-9]+)\"").search(text)
			return found.get_string(1) if found != null else ""
		"tres", "tscn":
			var first := text.get_slice("\n", 0)
			var found := RegEx.create_from_string("^\\[gd_(?:resource|scene)\\b[^\\]]*? uid=\"(uid://[a-z0-9]+)\"").search(first)
			return found.get_string(1) if found != null else ""
		"uid":
			var stripped := text.strip_edges()
			return stripped if stripped.begins_with("uid://") else ""
	return ""


## The text of the file `rel` with the pack's paths and its own UIDs changed.
static func _rewritten(rel: String, text: String, old_prefix: String, new_prefix: String, table: Dictionary) -> String:
	var old_source := ""
	if rel.get_extension() == "import":
		old_source = _source_file(text)
	text = text.replace(old_prefix, new_prefix)
	if rel.get_extension() == "import" and not old_source.is_empty():
		text = text.replace(old_source.md5_text(), old_source.replace(old_prefix, new_prefix).md5_text())
	if _uid_pattern == null:
		_uid_pattern = RegEx.create_from_string("uid://[a-z0-9]+")
	var matches := _uid_pattern.search_all(text)
	for i in range(matches.size() - 1, -1, -1):
		var found := matches[i]
		var fresh: String = table.get(found.get_string(), "")
		if not fresh.is_empty():
			text = text.substr(0, found.get_start()) + fresh + text.substr(found.get_end())
	return text


## The `source_file="..."` of an `.import` file (before any rewriting), or "".
static func _source_file(text: String) -> String:
	var found := RegEx.create_from_string("(?m)^source_file=\"([^\"]*)\"").search(text)
	return found.get_string(1) if found != null else ""


## Writes the new manifest: the source's, with the new id and title and no `base`.
static func _write_manifest(source: Pack, target: String, from: StringName, new_id: StringName, title: String) -> String:
	var parsed: Variant = source.read_json(Pack.MANIFEST)
	var manifest: Dictionary = parsed if parsed is Dictionary else {}
	manifest.erase("base")
	manifest["id"] = String(new_id)
	manifest["title"] = title if not title.strip_edges().is_empty() else String(new_id).replace("_", " ").capitalize()
	manifest["version"] = "1"
	manifest["description"] = "Made from the '%s' pack with `pack_tool --new`. Replace its files one by one." % from
	manifest["author"] = ""
	var error := PackFiles.write_text("%s/%s" % [target, Pack.MANIFEST], JSON.stringify(manifest, "  ") + "\n")
	return "" if error == OK else "cannot write the manifest: %s" % error_string(error)
