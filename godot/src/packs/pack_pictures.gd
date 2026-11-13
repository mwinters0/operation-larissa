class_name PackPictures
extends RefCounted
## Writes a pack's picture table (`pictures.json`, `PictureTable`) from a folder of picture files laid out as `<kind>/<name>.png` (`ui_picture/title_sky.png`, `frame/sub_00.png`: what the art templates, `SkinTemplates`, make, and the layout a person draws in),
## so that a pack made of such a folder needs no hand-written table. `pack_tool --pictures-table=<folder>` is this.
##
## A file under a folder named after a kind of picture (`PictureTable.KINDS`) becomes the row `<kind>/<name>` to that file; any other file is left alone and reported. A table the folder holds already is kept: its rows (aliases, files drawn at a scale, a file of any
## name) stay as they are, and a file whose key has no row gets one. Nothing is ever changed in a row, and the table is written only when it changed. The written table is checked the usual way (`PackCheck`, `pack_tool --check`).
##
## Teaches: deriving a table from a folder once, at authoring time, so that the game never guesses a key from a file name: the guess is written down where a person can read and change it.


class Result extends RefCounted:
	## The rows the table gained: key -> file.
	var added: Dictionary = {}
	## Files the folder holds that make no row (not a PNG under a kind folder), relative to the folder.
	var skipped: Array[String] = []
	## What was wrong with the table the folder held already (`PictureTable.problems`).
	var problems: Array[String] = []
	## "" or why nothing was written.
	var error := ""

	func ok() -> bool:
		return error.is_empty()

	func text() -> String:
		if not error.is_empty():
			return "error: " + error
		var lines: Array[String] = ["%s: %d row(s) added%s" % [PictureTable.FILE, added.size(), ("" if added.is_empty() else " (" + ", ".join(PackedStringArray(added.keys())) + ")")]]
		for rel in skipped:
			lines.append("%s is under no kind of picture (%s) or is no PNG: no row" % [rel, ", ".join(PictureTable.KINDS)])
		for problem in problems:
			lines.append("the table it held: " + problem)
		return "\n".join(lines)


## Writes `<folder>/pictures.json` from the `<kind>/<name>.png` files under `folder`, adding a row for each one no row names.
static func write(folder: String) -> Result:
	var result := Result.new()
	if not DirAccess.dir_exists_absolute(folder):
		result.error = "there is no folder %s" % folder
		return result
	var table := PictureTable.read(Pack.open(folder)) if FileAccess.file_exists(folder.path_join(PictureTable.FILE)) else PictureTable.new()
	result.problems = table.problems.duplicate()
	var data := table.to_data()
	var rows: Dictionary = data["pictures"]
	for rel in PackFiles.files_under(folder):
		if rel == PictureTable.FILE or rel == Pack.MANIFEST:
			continue
		var key := key_of(rel)
		if key.is_empty():
			result.skipped.append(rel)
		elif not _named(rows, rel):
			if not rows.has(key):
				rows[key] = rel
				result.added[key] = rel
	if not result.added.is_empty() or not FileAccess.file_exists(folder.path_join(PictureTable.FILE)):
		var written := ResourceJson.save_json({"format": PictureTable.FORMAT, "pictures": rows}, folder.path_join(PictureTable.FILE))
		if written != OK:
			result.error = "cannot write %s: %s" % [PictureTable.FILE, error_string(written)]
	return result


## The key of the file `rel` (`ui_picture/title_sky.png`): its kind folder and its name, or "" for a file that is no PNG directly under a folder named after a kind.
static func key_of(rel: String) -> String:
	var parts := rel.split("/")
	if parts.size() != 2 or parts[1].get_extension() != PictureTable.PICTURE_EXTENSION:
		return ""
	var key := "%s/%s" % [parts[0], parts[1].get_basename()]
	return key if PictureTable.is_key(key) else ""


## Does a row of `rows` (key -> file, scaled file or alias) already name the file `rel`?
static func _named(rows: Dictionary, rel: String) -> bool:
	for key: String in rows:
		var value: Variant = rows[key]
		if value is String and value == rel:
			return true
		if value is Dictionary and value.get(PictureTable.FILE_KEY, "") == rel:
			return true
	return false
