class_name PictureTable
extends RefCounted
## The picture table of ONE pack: `pictures.json`, from a skin key to a file of the pack or to another key.
##
##     {"format": 1,
##      "pictures": {
##        "ui_picture/title_sky": "art/sky.png",                       a file of THIS pack (relative to its root, a PNG)
##        "frame/sub_00": {"file": "art/sub_00@4x.png", "scale": 4},   a file drawn at 1/scale of its size (`ScaledTexture`: 4x art in a 640 x 400 game)
##        "ui_picture/coral_dawn": {"alias": "ui_picture/title_sky"}   another key: one file serves both names
##      }}
##
## A key is `<kind>/<name>`, the kind one of `KINDS`. What a file is called, and in which folder it lies, means nothing to the engine: the table is the only way a
## pack names a picture. `read` parses the file through the pack (`Pack.read_text`: a folder or a `.larissa` alike) and keeps what is sound; `problems` says, one sentence each, what is not (a malformed
## key or value, an unknown field, a file name that is no path inside the pack), and `check` adds what needs the pack's files (a file the pack does not hold, an alias that leads back to itself).
## The lookup that follows the rows through the whole chain (aliases are resolved from the top again) is `Pictures`.
##
## Teaches: a parser that keeps the good rows and names the bad ones, so one typo costs one picture and not the pack; and a JSON file validated by hand with a sentence for each mistake.

const FILE := "pictures.json"
const FORMAT := 1
const ALIAS_KEY := "alias"
const FILE_KEY := "file"
const SCALE_KEY := "scale"
## The largest `scale` of a row (`ScaledTexture`'s own range is 1 to this).
const MAX_SCALE := 16
const PICTURE_EXTENSION := "png"

## The kinds of picture there are (the part of a key before the `/`). `GameSkin.KEY_KINDS` is this list (the kind of a key a skin's tools and a mod's draw list name).
const KINDS: Array[String] = ["ui_picture", "background", "problem_art", "frame", "deco", "tile"]

## The part of a key after its kind: letters, digits, `_`, `-` and `.`, not starting with a dot.
static var _name_pattern := RegEx.create_from_string("^[A-Za-z0-9_\\-][A-Za-z0-9_.\\-]*$")

## The pack the table is of (for the sentences).
var pack_id: StringName = &""
## Does the pack hold a `pictures.json` at all? A pack that does not is read by the path lookups the table replaces (`Pictures`).
var present := false
## key -> the file of the pack (`art/sky.png`).
var files: Dictionary = {}
## key -> how many times larger than its drawn size the file is (only a row that says `scale`; 1 otherwise).
var scales: Dictionary = {}
## key -> the key it is an alias of.
var aliases: Dictionary = {}
## What is wrong with the file itself, one sentence each (without the pack's name).
var problems: Array[String] = []


## The table of `pack`: empty and not `present` when the pack has no `pictures.json`.
static func read(pack: Pack) -> PictureTable:
	var table := PictureTable.new()
	table.pack_id = pack.id
	if not pack.has(FILE):
		return table
	table.present = true
	var parser := JSON.new()
	if parser.parse(pack.read_text(FILE)) != OK:
		table.problems.append("%s line %d: %s" % [FILE, parser.get_error_line(), parser.get_error_message()])
		return table
	table._take(parser.data)
	return table


## Is `key` a picture key (`frame/sub_00`): a kind of `KINDS`, a slash, a name?
static func is_key(key: Variant) -> bool:
	if not key is String or not (key as String).contains("/"):
		return false
	var at: int = (key as String).find("/")
	return KINDS.has((key as String).substr(0, at)) and _name_pattern.search((key as String).substr(at + 1)) != null


## Why `key` is no picture key, as a clause ("the kind 'x' is not one of ...") or "" when it is one.
static func key_problem(key: Variant) -> String:
	if not key is String:
		return "a key is text"
	var text: String = key
	if not text.contains("/"):
		return "a key is <kind>/<name>"
	if not KINDS.has(text.get_slice("/", 0)):
		return "the kind '%s' is not one of %s" % [text.get_slice("/", 0), ", ".join(KINDS)]
	if not is_key(text):
		return "the name '%s' is not letters, digits, _, - and . (and no slash)" % text.substr(text.find("/") + 1)
	return ""


func has(key: String) -> bool:
	return files.has(key) or aliases.has(key)


## Every key the table has a row for.
func keys() -> Array[String]:
	var found: Array[String] = []
	for key: String in files:
		found.append(key)
	for key: String in aliases:
		found.append(key)
	return found


## How many times larger than the size it is drawn at the file of `key` is (1 for a plain row).
func scale_of(key: String) -> int:
	return int(scales.get(key, 1))


## The table as the JSON object it was read from (a tool writes a table with it).
func to_data() -> Dictionary:
	var rows := {}
	var sorted := keys()
	sorted.sort()
	for key in sorted:
		if aliases.has(key):
			rows[key] = {ALIAS_KEY: aliases[key]}
		elif scale_of(key) > 1:
			rows[key] = {FILE_KEY: files[key], SCALE_KEY: scale_of(key)}
		else:
			rows[key] = files[key]
	return {"format": FORMAT, "pictures": rows}


## What is wrong with the pack's table as one sentence each, the file's own `problems` first: a row whose file the pack does not hold (or that is no PNG picture), an alias that leads back to itself through this
## pack's rows alone. An alias to a key this pack does not hold may be held by a pack under it, so it is not asked here (`Pictures` says it when the chain is in use).
func check(pack: Pack) -> Array[String]:
	var found := problems.duplicate()
	var keys_sorted := keys()
	keys_sorted.sort()
	for key in keys_sorted:
		if files.has(key):
			var rel: String = files[key]
			if not pack.has(rel):
				found.append("%s: '%s' names the file %s, which the pack does not hold" % [FILE, key, rel])
		else:
			var loop := _own_loop(key)
			if not loop.is_empty():
				found.append("%s: the aliases %s go round in a circle" % [FILE, loop])
	return found


## "a -> b -> a" when the aliases from `key` lead back to a key already passed through this pack's rows alone, else "".
func _own_loop(key: String) -> String:
	var seen: Array[String] = [key]
	var at: String = key
	while aliases.has(at):
		at = aliases[at]
		if seen.has(at):
			return " -> ".join(PackedStringArray(seen + [at]))
		seen.append(at)
	return ""


func _take(data: Variant) -> void:
	if not data is Dictionary:
		problems.append("%s should be a JSON object with \"format\" and \"pictures\"" % FILE)
		return
	var top: Dictionary = data
	for field: String in top:
		if field != "format" and field != "pictures":
			problems.append("%s has no field '%s' (\"format\" and \"pictures\" are the fields)" % [FILE, field])
	if not (top.get("format") is float or top.get("format") is int):
		problems.append("%s: \"format\" should be the number %d" % [FILE, FORMAT])
	elif int(top["format"]) != FORMAT:
		problems.append("%s: format %d: this game reads format %d" % [FILE, int(top["format"]), FORMAT])
		return
	if not top.get("pictures") is Dictionary:
		problems.append("%s: \"pictures\" should be an object of key to file" % FILE)
		return
	var rows: Dictionary = top["pictures"]
	for key: Variant in rows:
		var bad := key_problem(key)
		if not bad.is_empty():
			problems.append("%s: '%s' is no picture key (%s)" % [FILE, key, bad])
			continue
		var value: Variant = rows[key]
		if value is String:
			var why := _file_problem(value)
			if why.is_empty():
				files[key] = value
			else:
				problems.append("%s: '%s': %s" % [FILE, key, why])
		elif value is Dictionary and (value as Dictionary).has(FILE_KEY):
			_take_scaled(key, value)
		elif value is Dictionary and (value as Dictionary).size() == 1 and (value as Dictionary).has(ALIAS_KEY):
			var target: Variant = (value as Dictionary)[ALIAS_KEY]
			var target_problem := key_problem(target)
			if target_problem.is_empty():
				aliases[key] = target
			else:
				problems.append("%s: '%s' is an alias of '%s', which is no picture key (%s)" % [FILE, key, target, target_problem])
		else:
			problems.append("%s: '%s' should be a file of the pack (text), {\"%s\": \"<file>\", \"%s\": <number>} or {\"%s\": \"<key>\"}" % [FILE, key, FILE_KEY, SCALE_KEY, ALIAS_KEY])


## A row `{"file": ..., "scale": N}`.
func _take_scaled(key: String, row: Dictionary) -> void:
	var typo := false
	for field: String in row:
		if field != FILE_KEY and field != SCALE_KEY:
			problems.append("%s: '%s' has no field '%s' (\"%s\" and \"%s\" are the fields)" % [FILE, key, field, FILE_KEY, SCALE_KEY])
			typo = true
	if typo:
		return
	var rel: Variant = row[FILE_KEY]
	var why := _file_problem(rel) if rel is String else "the file should be text"
	if not why.is_empty():
		problems.append("%s: '%s': %s" % [FILE, key, why])
		return
	var scale: Variant = row.get(SCALE_KEY, 1)
	if not (scale is float or scale is int) or int(scale) != scale or int(scale) < 1 or int(scale) > MAX_SCALE:
		problems.append("%s: '%s': \"%s\" should be a whole number from 1 to %d" % [FILE, key, SCALE_KEY, MAX_SCALE])
		return
	files[key] = rel
	if int(scale) > 1:
		scales[key] = int(scale)


## Why `rel` cannot be the file of a row ("" when it can): a path that leaves the pack, or one that is no PNG.
static func _file_problem(rel: String) -> String:
	if not Pack.is_safe(rel):
		return "'%s' is not a path inside the pack" % rel
	if rel.get_extension().to_lower() != PICTURE_EXTENSION:
		return "'%s' is not a .%s file" % [rel, PICTURE_EXTENSION]
	return ""
