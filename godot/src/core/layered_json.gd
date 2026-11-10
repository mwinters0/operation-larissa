class_name LayeredJson
extends RefCounted
## The mechanics of a rule file that a pack may lay over the project's own, key by key: finding the files down the pack chain, reading
## them, merging them, and walking a pack's file against the project's to say what is wrong in it. `Durations` (`rules/durations.json`)
## and `Tuning` (`rules/tuning.json`) are built on it; each keeps what is its own (which numbers it needs, what a sensible value is).
##
## Teaches: one mechanism for two files. The part that does not depend on what the numbers mean (layers, merge, the walk over keys) is
## written once, and the part that does (a leaf check) is handed in as a `Callable`, so a new rule file costs a few lines and cannot
## drift from the others in how a layer is read.

## What a walk needs to know about the file it checks.
class Check extends RefCounted:
	## What a key of the file is called in a message ("duration": "no such duration").
	var noun: String = "key"
	## The project's file, named in the message about an unknown key.
	var base_path: String = ""
	## What the entries of a list are, in the message about something that is not a list ("must be a list of whole numbers").
	var list_of: String = "numbers"
	## Called for every value that is neither a section nor a list, and for every entry of a list: `(value, path, errors, warnings)`.
	## A list entry that is itself a list is handed to it whole.
	var leaf: Callable
	## Dotted paths of lists the rules index into by a fixed count (a table with one entry per sprite cell): another length than the
	## project's is an error, not a warning.
	var exact_lengths: Array[String] = []
	## Dotted paths of lists of any length (a table whose size the file itself decides): no message about the length.
	var free_lengths: Array[String] = []

	func _init(file_noun: String, project_file: String, entries: String, leaf_check: Callable) -> void:
		noun = file_noun
		base_path = project_file
		list_of = entries
		leaf = leaf_check


## The files that make up a rule file: the project's `base_path` first, then `pack_path` of each pack of the chain (the bottom pack
## first, so that the chosen pack has the last word), then `extra`. A file of a pack is named by its path under the pack (a virtual one for a pack file:
## `Pack.path_of`); `read` asks the pack for it.
static func files(base_path: String, pack_path: String, extra: Array[String]) -> Array[String]:
	var found: Array[String] = [base_path]
	var chain := Packs.chain()
	for i in range(chain.size() - 1, -1, -1):
		if chain[i].has(pack_path):
			found.append(chain[i].path_of(pack_path))
	found.append_array(extra)
	return found


## `paths` read and laid over each other, later ones winning key by key. `owner` names the caller in an error message.
static func read_all(paths: Array[String], owner: String) -> Dictionary:
	var table := {}
	for path in paths:
		merge(table, read(path, owner))
	return table


## One file as a dictionary; a file that cannot be read is reported (`owner`) and gives an empty one. A file of a pack (`files` names it by its path under the pack) is read
## by the pack, a folder or a pack file alike; any other path (the project's own file, a tool's `extra`) is read from the file system (`Packs.bytes_at`).
static func read(path: String, owner: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(Packs.bytes_at(path).get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	push_error("%s: cannot read '%s'" % [owner, path])
	return {}


## `layer` laid over `into`: a section is merged key by key, anything else replaces.
static func merge(into: Dictionary, layer: Dictionary) -> void:
	for key: String in layer:
		if into.get(key) is Dictionary and layer[key] is Dictionary:
			merge(into[key], layer[key])
		else:
			into[key] = layer[key]


static func dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func is_number(value: Variant) -> bool:
	return value is float or value is int


## Is `value` a whole number? If not, says so in `errors`.
static func check_whole(value: Variant, path: String, errors: Array[String]) -> bool:
	if is_number(value) and value == floorf(value):
		return true
	errors.append("%s must be a whole number, not %s" % [path, str(value)])
	return false


## What is wrong in `layer` set against `base` (both parsed): an unknown key (a typo would be silently ignored otherwise), a section where
## the project has a value or the reverse, a list where the project has none; the entries of lists and the plain values go to
## `check.leaf`. Keys that start with an underscore are notes and are skipped. A list of another length than the project's is a warning,
## an error where `check.exact_lengths` names it, and nothing where `check.free_lengths` does.
## `prefix` is the dotted path of `base` ("" at the top).
static func walk(base: Dictionary, layer: Dictionary, check: Check, errors: Array[String], warnings: Array[String], prefix: String = "") -> void:
	for key: String in layer:
		var path := prefix + key
		if key.begins_with("_"):
			continue
		if not base.has(key):
			errors.append("%s: no such %s (the keys are those of %s)" % [path, check.noun, check.base_path.trim_prefix("res://")])
			continue
		var wanted: Variant = base[key]
		var value: Variant = layer[key]
		if wanted is Dictionary:
			if value is Dictionary:
				walk(wanted, value, check, errors, warnings, path + ".")
			else:
				errors.append("%s is a section {...}, not %s" % [path, str(value)])
		elif wanted is Array:
			if not value is Array:
				errors.append("%s must be a list of %s" % [path, check.list_of])
				continue
			if (value as Array).size() != (wanted as Array).size() and not check.free_lengths.has(path):
				var message := "%s has %d entries, the game's has %d" % [path, (value as Array).size(), (wanted as Array).size()]
				if check.exact_lengths.has(path):
					errors.append(message + ": the rules index it, it must have as many")
				else:
					warnings.append(message)
			for entry: Variant in value:
				check.leaf.call(entry, path, errors, warnings)
		else:
			check.leaf.call(value, path, errors, warnings)


# --- reading a section into typed values -------------------------------------------------------------------------------------------
# A key the merged file lacks is a bug in the data (the project's own file holds every key): it is reported and 0 (or an empty list)
# is returned, so a broken file names the key instead of leaving the rules with a mysterious value.

## The whole number `key` of `section`.
static func int_of(section: Dictionary, key: String, owner: String) -> int:
	var value: Variant = section.get(key)
	if is_number(value):
		return int(value)
	push_error("%s: no number '%s'" % [owner, key])
	return 0


## The float `key` of `section`.
static func float_of(section: Dictionary, key: String, owner: String) -> float:
	var value: Variant = section.get(key)
	if is_number(value):
		return float(value)
	push_error("%s: no number '%s'" % [owner, key])
	return 0.0


## The list of whole numbers `key` of `section`.
static func ints_of(section: Dictionary, key: String, owner: String) -> PackedInt32Array:
	var found := PackedInt32Array()
	var value: Variant = section.get(key)
	if value is Array:
		for entry: Variant in value:
			found.append(int(entry))
	else:
		push_error("%s: no list '%s'" % [owner, key])
	return found


## The list `key` of `section`, each entry a list of exactly `size` whole numbers (`[x, y, w, h]`).
static func int_rows_of(section: Dictionary, key: String, size: int, owner: String) -> Array[PackedInt32Array]:
	var rows: Array[PackedInt32Array] = []
	var value: Variant = section.get(key)
	if value is Array:
		for entry: Variant in value:
			var row := PackedInt32Array()
			if entry is Array and (entry as Array).size() == size:
				for number: Variant in entry:
					row.append(int(number))
			else:
				push_error("%s: an entry of '%s' is not a list of %d numbers" % [owner, key, size])
				row.resize(size)
			rows.append(row)
	else:
		push_error("%s: no list '%s'" % [owner, key])
	return rows


## The list `key` of `section` as ONE row of `size` whole numbers (a rectangle `[x, y, w, h]`, a point `[x, y]`).
static func row_of(section: Dictionary, key: String, size: int, owner: String) -> PackedInt32Array:
	var row := ints_of(section, key, owner)
	if row.size() != size:
		push_error("%s: '%s' is not a list of %d numbers" % [owner, key, size])
		row.resize(size)
	return row
