@tool
class_name FoeAnnotations
extends RefCounted
## The designers' label names and comments for the creature scripts: the annotation
## store file, and "harvest", which reads them back out of a hand-edited .foe text.
##
## Teaches: why a GENERATED file that people also edit needs a second home for their
## edits. `data/sectors/sector_NN/sector_NN.foe` is produced from the original bytes by the
## importer, and an import or a reset writes it again; a label renamed or a comment
## written in the file would be lost. So the additions are stored apart, in
## `data/sectors/foe_annotations.json`, keyed by sector and ORIGINAL byte offset (the
## bytes never change, so an offset is a stable name for "this instruction"), and the
## disassembler (`FoeAsm.disassemble`) puts them back. Harvest is the other direction:
## from the text to the store. Computing an offset needs no assembler: it is the sum of
## the sizes (1 + operand count) of the instruction lines before it.
## Only ORIGINAL sectors (those in the committed hash fixture of the original scripts) have a store entry.
## A sector the designers made (index 32 and up) has no original: its .foe file is its
## only source, nothing regenerates it, so there is nothing to harvest.
##
## The file format and the rules for where a comment attaches are documented in
## tools/import/foe_annotations.py, which does exactly the same in Python (the importer
## and reset tools use it); tests/engine/test_foe_annotations.gd and tools/import/test_foe_annotations.py
## check that both agree, down to the bytes of the file. One sector in memory is
## {"labels": {offset: name}, "comments": {offset: {"label_above", "label_inline",
## "above", "inline"}}} with int offsets. Manual: docs/create/FOE_SCRIPTING.md ("Names and comments").
## Not shipped with the game (the file is excluded from exports); `@tool` because the
## Foe Script screen uses it.

const STORE_PATH := "res://data/sectors/foe_annotations.json"
## Provenance and SHA-256 of the script of every original sector (committed; tools/import/foe_script.py).
const HASH_FIXTURE := "res://tests/fixtures/foe_scripts.json"
## The original bytes of every original sector, written by the importer from your copy of the game (git-ignored).
const ORIGINAL_BYTES := FixtureHash.ORIGINAL_DIR + "foe_scripts.json"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"

const NOTE_KEYS := ["label_above", "label_inline", "above", "inline"]
const LIST_KEYS := ["label_above", "above"]

## The "comment" line of the file. Must equal FILE_COMMENT of foe_annotations.py.
const FILE_COMMENT := "The designers' label names and comments for the creature scripts, keyed by sector and ORIGINAL byte offset. Written by tools/import/harvest_foe_annotations.py and by the Foe Script screen; read by the importer and by tools/import/reset_foe_scripts.py. Not shipped with the game. See docs/create/FOE_SCRIPTING.md."

static var _originals: Dictionary = {}
static var _hashes: Dictionary = {}
static var _problem := ""


## The outcome of `parse`: the store, or what is wrong with the file.
class Parsed extends RefCounted:
	var store: Dictionary = {}
	var error := ""

	func ok() -> bool:
		return error.is_empty()


## The outcome of `harvest`.
class Harvest extends RefCounted:
	var ok := false
	## Why it was refused ("line N: ..."), when not ok.
	var problem := ""
	var labels: Dictionary = {}            # offset -> name
	var comments: Dictionary = {}          # offset -> note
	## offset -> the label the text has there
	var names: Dictionary = {}
	## The text in the standard layout, with these annotations.
	var text := ""

	func annotations() -> Dictionary:
		return {"labels": labels, "comments": comments}


# =============================================================================
# The original sectors
# =============================================================================

## The sector number of a path like ".../sector_07/sector_07.foe" (or .tres); -1 for any other name.
static func sector_of_path(path: String) -> int:
	var stem := path.get_file().get_basename()
	if not stem.begins_with("sector_") or not stem.trim_prefix("sector_").is_valid_int():
		return -1
	return stem.trim_prefix("sector_").to_int()


## The original script of `index`: {"index", "base", "script" (bytes), "offsets" (one
## [pc, script_hit, script_ink] per creature), "entries" (label -> offset)}. Empty when
## the sector has no original (a sector the designers made), or when the importer has not written
## the original bytes from your copy of the game (`has_original_bytes()`; an exported game has
## neither, the tests folder is not shipped). The script is checked against the committed
## SHA-256 (`HASH_FIXTURE`) when it is read: a different release or a patched copy gives no original at all
## (`original_problem()` says so) instead of being compared with itself.
static func original(index: int) -> Dictionary:
	_load_originals()
	return _originals.get(index, {})


## True when the importer's file of the original scripts is there (the property tests over the originals skip without it).
static func has_original_bytes() -> bool:
	return FileAccess.file_exists(ORIGINAL_BYTES)


## "" when the original bytes can be used, else why not: missing (run the importer) or not the committed ones.
static func original_problem() -> String:
	if not has_original_bytes():
		return "%s is missing; %s" % [ORIGINAL_BYTES, NEED_THE_IMPORTER]
	_load_originals()
	return _problem


## Provenance and hashes of the original scripts: sector index -> {"offset", "size", "sha256"}. Empty without the committed fixture.
static func original_hashes() -> Dictionary:
	if _hashes.is_empty() and FileAccess.file_exists(HASH_FIXTURE):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HASH_FIXTURE))
		if parsed is Dictionary:
			for entry: Dictionary in parsed["sectors"]:
				_hashes[int(entry["index"])] = entry
	return _hashes


static func _load_originals() -> void:
	if not _originals.is_empty() or not _problem.is_empty() or not has_original_bytes():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_BYTES))
	if not parsed is Dictionary:
		_problem = "%s is not a JSON object" % ORIGINAL_BYTES
		return
	var hashes := original_hashes()
	for entry: Dictionary in parsed["sectors"]:
		var index := int(entry["index"])
		var script := String(entry["script_hex"]).hex_decode()
		if not hashes.has(index) or FixtureHash.sha256_hex(script) != hashes[index]["sha256"]:
			_originals.clear()
			_problem = "sector %d: the script in %s does not match the SHA-256 committed in %s (your copy of the game is a different version or patched); %s" % [index, ORIGINAL_BYTES.get_file(), HASH_FIXTURE.get_file(), NEED_THE_IMPORTER]
			return
		var offsets: Array = []
		for foe in entry["foes"]:
			offsets.append([int(foe["pc"]), int(foe["script_hit"]), int(foe["script_ink"])])
		_originals[index] = {
			"index": index, "base": int(entry["base"]), "script": script,
			"offsets": offsets, "entries": FoeAsm.entry_names(offsets)}
	_problem = ""


## True when sector `index` is one of the original sectors (the committed hash fixture lists it). Needs no original bytes.
static func has_original(index: int) -> bool:
	return original_hashes().has(index)


## The numbers of all original sectors, ascending. Needs no original bytes.
static func original_sectors() -> Array:
	var result: Array = original_hashes().keys()
	result.sort()
	return result


# =============================================================================
# The file
# =============================================================================

static func empty_sector() -> Dictionary:
	return {"labels": {}, "comments": {}}


static func is_empty(sector: Dictionary) -> bool:
	return sector.get("labels", {}).is_empty() and sector.get("comments", {}).is_empty()


## One sector's annotations (empty ones when it has none) out of a whole store.
static func for_sector(store: Dictionary, index: int) -> Dictionary:
	return store.get(index, empty_sector())


## The store of the file at `path` ({} for a file that does not exist); `Parsed.error`
## says what is wrong with a file that cannot be read.
static func load_store(path: String = STORE_PATH) -> Parsed:
	if not FileAccess.file_exists(path):
		return Parsed.new()
	return parse(FileAccess.get_file_as_string(path))


## Reads the text of a store file. See foe_annotations.py for the layout.
static func parse(text: String) -> Parsed:
	var result := Parsed.new()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		result.error = "the annotation file is not a JSON object (%s)" % json.get_error_message()
		return result
	var data: Dictionary = json.data
	var sectors: Dictionary = data.get("sectors", {})
	for key in sectors:
		var index := int(key)
		var labels: Dictionary = {}
		var used: Dictionary = {}
		var source: Dictionary = sectors[key].get("labels", {})
		for offset in source:
			var name: Variant = source[offset]
			if not name is String or not FoeAsm.is_identifier(name):
				result.error = "sector %d, label at %s: '%s' is not an identifier" % [index, offset, name]
				return result
			if used.has(name):
				result.error = "sector %d: the label name '%s' is used twice" % [index, name]
				return result
			used[name] = true
			labels[int(offset)] = name
		var comments: Dictionary = {}
		var notes: Dictionary = sectors[key].get("comments", {})
		for offset in notes:
			var note := _checked_note(notes[offset])
			if note.is_empty():
				result.error = "sector %d, offset %s: a comment note is an object with some of %s" % [index, offset, ", ".join(NOTE_KEYS)]
				return result
			comments[int(offset)] = note
		if not labels.is_empty() or not comments.is_empty():
			result.store[index] = {"labels": _sorted(labels), "comments": _sorted(comments)}
	return result


## The note with only valid keys, in the order of NOTE_KEYS; {} when it is not valid.
static func _checked_note(raw: Variant) -> Dictionary:
	var note: Dictionary = {}
	if not raw is Dictionary:
		return note
	for key in raw:
		if not NOTE_KEYS.has(key):
			return {}
	for key in NOTE_KEYS:
		if not raw.has(key):
			continue
		var value: Variant = raw[key]
		if LIST_KEYS.has(key):
			if not value is Array:
				return {}
			for line in value:
				if not line is String:
					return {}
			note[key] = value.duplicate()
		else:
			if not value is String or value.is_empty():
				return {}
			note[key] = value
	return note


static func _sorted(by_offset: Dictionary) -> Dictionary:
	var keys := by_offset.keys()
	keys.sort()
	var result: Dictionary = {}
	for key in keys:
		result[key] = by_offset[key]
	return result


## The file text for `store`: fixed layout (numbers sorted, one line per label and per
## commented position), byte for byte what foe_annotations.dumps writes.
static func stringify(store: Dictionary) -> String:
	var out: Array[String] = ["{", ' "comment": %s,' % _quote(FILE_COMMENT)]
	var sectors: Array = []
	for index in store:
		if not is_empty(store[index]):
			sectors.append(index)
	sectors.sort()
	if sectors.is_empty():
		out.append(' "sectors": {}')
	else:
		out.append(' "sectors": {')
		for si in sectors.size():
			var sector: Dictionary = store[sectors[si]]
			var parts: Array[String] = []
			if not sector.get("labels", {}).is_empty():
				var items: Array[String] = []
				for offset in _sorted(sector["labels"]):
					items.append('    "%d": %s' % [offset, _quote(sector["labels"][offset])])
				parts.append('   "labels": {\n' + ",\n".join(items) + "\n   }")
			if not sector.get("comments", {}).is_empty():
				var items: Array[String] = []
				for offset in _sorted(sector["comments"]):
					var note: Dictionary = sector["comments"][offset]
					var fields: Array[String] = []
					for key in NOTE_KEYS:
						if not note.has(key):
							continue
						var shown := ""
						if LIST_KEYS.has(key):
							var quoted: Array[String] = []
							for line in note[key]:
								quoted.append(_quote(line))
							shown = "[" + ", ".join(quoted) + "]"
						else:
							shown = _quote(note[key])
						fields.append('"%s": %s' % [key, shown])
					items.append('    "%d": {%s}' % [offset, ", ".join(fields)])
				parts.append('   "comments": {\n' + ",\n".join(items) + "\n   }")
			out.append('  "%d": {' % sectors[si])
			out.append(",\n".join(parts))
			out.append("  }" + ("," if si < sectors.size() - 1 else ""))
		out.append(" }")
	out.append("}")
	return "\n".join(out) + "\n"


## A JSON string literal; like Python's json.dumps(ensure_ascii=False): only quote,
## backslash and control characters are escaped.
static func _quote(text: String) -> String:
	var out := '"'
	for i in text.length():
		var c := text.unicode_at(i)
		match c:
			34: out += '\\"'
			92: out += "\\\\"
			8: out += "\\b"
			12: out += "\\f"
			10: out += "\\n"
			13: out += "\\r"
			9: out += "\\t"
			_:
				if c < 32:
					out += "\\u%04x" % c
				else:
					out += char(c)
	return out + '"'


static func save_store(store: Dictionary, path: String = STORE_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(stringify(store))
	file.close()
	return OK


# =============================================================================
# The .tres entry labels
# =============================================================================

const LABEL_FIELDS := ["start_label", "hit_label", "ink_label"]


## `tres_text` (a sector_NN.tres) with every start_label / hit_label / ink_label line
## whose value is `old` changed to `new`; the rest of the file stays as it is.
static func rename_entry_label(tres_text: String, old: String, new: String) -> String:
	var lines := tres_text.split("\n")
	for n in lines.size():
		for field in LABEL_FIELDS:
			if lines[n] == '%s = "%s"' % [field, old]:
				lines[n] = '%s = "%s"' % [field, new]
	return "\n".join(lines)


## `tres_text` with the label fields of creature k set to `labels[k]` ([start, hit, ink]);
## "" when the number of creatures in the file is not `labels.size()`.
static func set_entry_labels(tres_text: String, labels: Array) -> String:
	var lines := tres_text.split("\n")
	var seen := [0, 0, 0]
	for n in lines.size():
		for f in 3:
			if lines[n].begins_with(LABEL_FIELDS[f] + ' = "') and lines[n].ends_with('"'):
				if seen[f] >= labels.size():
					return ""
				lines[n] = '%s = "%s"' % [LABEL_FIELDS[f], labels[seen[f]][f]]
				seen[f] += 1
	if seen != [labels.size(), labels.size(), labels.size()]:
		return ""
	return "\n".join(lines)


## The labels the creatures of a sector_NN.tres name, as [start, hit, ink] per creature.
static func read_entry_labels(tres_text: String) -> Array:
	var seen: Array = [[], [], []]
	for line in tres_text.split("\n"):
		for f in 3:
			if line.begins_with(LABEL_FIELDS[f] + ' = "') and line.ends_with('"'):
				seen[f].append(line.trim_prefix(LABEL_FIELDS[f] + ' = "').trim_suffix('"'))
	var labels: Array = []
	for k in seen[0].size():
		labels.append([seen[0][k], seen[1][k] if k < seen[1].size() else "", seen[2][k] if k < seen[2].size() else ""])
	return labels


# =============================================================================
# Harvest
# =============================================================================

## Reads the label names and comments out of `text`, which must be the ORIGINAL
## `script` (first byte at buffer offset `base`) written as text; `entries` is label ->
## offset of the creatures' entry points (FoeAsm.entry_names). Refuses (ok false, with
## the reason) when the text's instructions are not the original's, when two labels
## are at one place, or when a creature's entry point has no label. The result's `text`
## is the text in the standard layout: the stored file is in sync only when it equals that.
## A `Padding N` line counts as N bytes for the offsets (a bare `Padding` as 1), a label or
## comment on it belongs to its first byte, and the instructions-match check treats it as
## N zero bytes. The operands are compared as VALUES, not as spelling (`Set_Frame 163`, `Set_Frame 35 mirrored` and
## `Set_Frame eel_swim_1 mirrored` are one instruction); `symbols` (FoeNames of the sector) says which names exist,
## and the text of the result prints the names the registry has. Rules: tools/import/foe_annotations.py.
static func harvest(text: String, script: PackedByteArray, base: int, entries: Dictionary, symbols: FoeNames = null) -> Harvest:
	var decoded := FoeAsm.decode(script, base)
	var end := base + script.size()
	var positions: Dictionary = {end: true}
	for item in decoded:
		positions[item["at"]] = true
	for name in entries:
		if not positions.has(int(entries[name])):
			return _refuse("entry point %s (offset %d) is not at the start of an instruction" % [name, entries[name]])

	var lines := text.replace("\r\n", "\n").split("\n")
	var count := lines.size()
	if count > 0 and lines[count - 1] == "":
		count -= 1                                          # the newline that ends the last line
	var elements: Array[Dictionary] = []
	var gap: Array = []
	var offset := base
	for n in count:
		var raw := lines[n].strip_edges(false, true)
		var semicolon := raw.find(";")
		var code := raw if semicolon < 0 else raw.substr(0, semicolon)
		if code.strip_edges().is_empty():
			gap.append(raw if semicolon >= 0 else "")
			continue
		var tail := raw.substr(code.strip_edges(false, true).length())
		var words := Array(code.replace("\t", " ").replace("\r", " ").strip_edges().split(" ", false))
		if words.size() == 1 and words[0].ends_with(":") and FoeAsm.is_identifier(words[0].trim_suffix(":")):
			elements.append({"label": true, "line": n + 1, "offset": offset, "gap": gap, "tail": tail, "words": [words[0].trim_suffix(":")]})
		else:
			var opcode := FoeOps.op_from_mnemonic(words[0])
			if opcode < 0:
				return _refuse("line %d: unknown instruction '%s'" % [n + 1, words[0]])
			elements.append({"label": false, "line": n + 1, "offset": offset, "gap": gap, "tail": tail, "words": words})
			if FoeOps.is_pseudo(opcode):                    # Padding: `count` zero bytes
				var pad := _padding_count(words.slice(1))
				if pad < 0:
					return _refuse("line %d: Padding takes one count, 1..%d (or none for 1), got '%s'" % [n + 1, FoeOps.PADDING_MAX, " ".join(words.slice(1))])
				offset += pad
			else:
				offset += 1 + FoeOps.OPERAND_COUNT[opcode]
		gap = []
	var trailing := gap

	# the labels of the text
	var names: Dictionary = {}
	var first_line_of: Dictionary = {}
	for e in elements:
		if not e["label"]:
			continue
		var name: String = e["words"][0]
		if first_line_of.has(name):
			return _refuse("line %d: duplicate label '%s' (first defined on line %d)" % [e["line"], name, first_line_of[name]])
		if names.has(e["offset"]):
			return _refuse("line %d: '%s' and '%s' label the same place; keep one of them" % [e["line"], names[e["offset"]], name])
		first_line_of[name] = e["line"]
		names[e["offset"]] = name

	# the instructions must be the original's, one by one (a Padding line stands for that many zero bytes)
	var instructions: Array[Dictionary] = []
	for e in elements:
		if not e["label"]:
			instructions.append(e)
	var i := 0                                              # the next original instruction
	for e in instructions:
		if i >= decoded.size():
			return _refuse("line %d: the original has no instruction here" % e["line"])
		var item := decoded[i]
		if item["op"] < 0:
			return _refuse("the original has an undecodable byte at offset %d" % item["at"])
		var have: Array = e["words"]
		if FoeOps.is_pseudo(FoeOps.op_from_mnemonic(str(have[0]))):
			var pad := _padding_count(have.slice(1))
			for k in pad:
				if i + k >= decoded.size() or decoded[i + k]["op"] != 0 or decoded[i + k]["at"] != e["offset"] + k:
					var shown := "the end of the script"
					if i + k < decoded.size():
						var other := decoded[i + k]
						shown = "??%d" % other["byte"] if other["op"] < 0 else FoeAsm.format_instruction(other["op"], other["operands"], other["at"], names, symbols)
					return _refuse("line %d: the original has '%s' here, the text has '%s'" % [e["line"], shown, " ".join(have)])
			i += pad
			continue
		var expected := FoeAsm.format_instruction(item["op"], item["operands"], item["at"], names, symbols)
		var found := " ".join(have)
		var same: bool = e["offset"] == item["at"] and str(have[0]).to_lower() == FoeOps.op_name(item["op"]).to_lower()
		if same:
			var parsed := FoeAsm.parse_operands(item["op"], have.slice(1), symbols)
			same = parsed["errors"].is_empty() and parsed["values"] == FoeAsm.operand_values(item["op"], item["operands"], item["at"], names)
		if not same:
			return _refuse("line %d: the original has '%s' here, the text has '%s'" % [e["line"], expected, found])
		i += 1
	if i < decoded.size():
		var rest := decoded[i]
		if rest["op"] < 0:
			return _refuse("the original has an undecodable byte at offset %d" % rest["at"])
		return _refuse("the text ends early: the original continues with '%s'" % FoeAsm.format_instruction(rest["op"], rest["operands"], rest["at"], names, symbols))
	for name in entries:
		if not names.has(int(entries[name])):
			return _refuse("%s (offset %d) is an entry point of a creature and needs a label" % [name, entries[name]])

	# what differs from the generated text
	var generated := FoeAsm.generated_names(script, base, entries)
	var unexecuted := FoeAsm.unexecuted_notes(script, base, entries)    # the generated "above" lines
	var result := Harvest.new()
	result.ok = true
	result.names = names
	var label_offsets := names.keys()
	label_offsets.sort()
	for at in label_offsets:
		if generated.get(at, "") != names[at]:
			result.labels[at] = names[at]
	var notes: Dictionary = {}
	var have_previous := false
	for e in elements:
		var note: Dictionary = notes.get(e["offset"], {})
		var tail: String = e["tail"]
		if tail.begins_with("  ;"):
			tail = tail.substr(2)
		if e["label"]:
			if e["gap"] != ([""] if have_previous else []):
				note["label_above"] = e["gap"]
			if not tail.is_empty():
				note["label_inline"] = tail
		else:
			if e["gap"] != unexecuted.get(e["offset"], []):       # stored when it differs, even if it is empty
				note["above"] = e["gap"]
			if not tail.is_empty():
				note["inline"] = tail
		notes[e["offset"]] = note
		have_previous = true
	if not trailing.is_empty():
		var note: Dictionary = notes.get(end, {})
		note["above"] = trailing
		notes[end] = note
	var note_offsets := notes.keys()
	note_offsets.sort()
	for at in note_offsets:
		if notes[at].is_empty():
			continue
		var ordered: Dictionary = {}
		for key in NOTE_KEYS:
			if notes[at].has(key):
				ordered[key] = notes[at][key]
		result.comments[at] = ordered
	result.text = FoeAsm.disassemble(script, base, entries, result.annotations(), symbols)
	return result


## The N of a `Padding N` line, `operands` being the words after the name (1 for a bare
## `Padding`); -1 when they are not one whole number 1..FoeOps.PADDING_MAX.
static func _padding_count(operands: Array) -> int:
	if operands.is_empty():
		return 1
	var word := str(operands[0])
	var limits := FoeOps.kind_range(FoeOps.Kind.COUNT)
	if operands.size() == 1 and word.is_valid_int() and not word.begins_with("+") and word.to_int() >= limits.x and word.to_int() <= limits.y:
		return word.to_int()
	return -1


static func _refuse(problem: String) -> Harvest:
	var result := Harvest.new()
	result.problem = problem
	return result
