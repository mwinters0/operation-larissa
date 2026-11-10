@tool
class_name ScreenFile
extends RefCounted
## Writes a screen back to its `.tres` file in the exact text the importer wrote, and reads the original record.
##
## Teaches: why the editor writes this file itself instead of calling `ResourceSaver.save`, and how to edit a text
## file surgically. The importer (tools/import/screen_record.py) wrote `screen_MM.tres`; this class produces the
## SAME text from a `ScreenData`, so that opening a screen and saving it without a change leaves `git diff` empty.
## `ResourceSaver` would not: in the editor it writes `format=4`, a random `uid=` in the header, random `id`s for
## the script references, leaves out every property that has its default value (`flag = false`), and stores the
## tile bytes as base64. Those are good choices for general resources and bad ones for a file whose diff students
## read. The test tests/engine/test_screen_editor_files.gd writes all 384 committed screens through `screen_text` and
## demands byte-identical text, so the two writers cannot drift apart unnoticed.
##
## `sector_text` does the same for the little the screen editor may change in `sector_NN.tres` (the pieces' screen and
## position, the respawn point): it replaces just those lines and leaves the other 6000 lines of the file alone.
## `foes_text` does it for the creatures the screen editor's markers (`ScreenEditorFoe`) moved or edited: the lines of the properties in
## `FOE_FIELDS` of the creatures that differ.
## `sector_patch` is the same idea for a `SectorData` that something else changed (the Inspector, a script): it also knows
## the creatures' properties and the neighbour tables, and REFUSES a change to any other property instead of dropping it.
##
## A different NUMBER of pieces or creatures is written too (the Sector Inspector adds and removes them, `SectorData.add_piece` ...):
## `SectorLists` writes the whole list again, and `foe_script_base` follows the count (the script follows the records).
##
## The same text-writing code is what `ScreenDataSaver` and `SectorDataSaver` call when Godot itself saves one of these
## resources (Ctrl+S, Save All): see those two classes for why.

const SCRIPTS := "res://src/resources/"
## Provenance and SHA-256 of every original screen record (committed; tools/import/screen_record.py).
const HASH_FIXTURE_PATH := "res://tests/fixtures/screens.json"
## The original record bytes, written by the importer from your copy of the game (git-ignored).
const ORIGINAL_BYTES_PATH := "res://tests/fixtures/original/screens.json"

## What a sector file may have patched into it, field by field (the importer's property names). Anything else that differs
## from the file on disk is refused by `sector_patch`. What is meant to be edited
## in place: creature properties, pieces, neighbours (and the respawn point, which the screen editor moves).
const SECTOR_FIELDS: Array[String] = ["start_pos", "start_frame", "neighbors_left", "neighbors_right", "neighbors_up", "neighbors_down",
		"music_name"]
## A piece: where it lies. `is_canister` is not editable: the first piece is the data canister and the game counts on that.
const PIECE_FIELDS: Array[String] = ["screen", "pos"]
## A creature: every property of the record (the three entry points are labels of the sector's `.foe` script).
const FOE_FIELDS: Array[String] = ["dormant", "hidden", "screen", "pos", "frame", "flip", "frame_min", "frame_max", "damage", "start_label", "hit_label", "ink_label"]

## the importer's raw file parsed once: sector index -> screen index -> record (PackedByteArray, 0x500 bytes)
static var _fixture: Dictionary = {}
## the committed hashes parsed once: sector index -> screen index -> SHA-256 (hex)
static var _hashes: Dictionary = {}

## The message of the last refusal (`refuse`), "" before any. Tests read it; the editor shows it as an error and a toast.
static var last_refusal: String = ""


## A saver says no: nothing is written, the reason is logged (and shown as a toast in the editor).
## `ResourceSaver.save` tries the NEXT saver when one returns an error, and the next one is Godot's own text saver, which
## would write the file in Godot's format. So a refusing saver reports the problem here and still returns OK to the engine:
## "OK" means "handled", the file on disk is untouched.
static func refuse(path: String, why: String) -> void:
	last_refusal = "%s was NOT written: %s" % [path, why]
	push_error(last_refusal)
	if Engine.is_editor_hint():
		EditorInterface.get_editor_toaster().push_toast(last_refusal, EditorToaster.SEVERITY_ERROR)


## Writes `text` to `path` unless the file already holds exactly that (then it is not touched: no new modification time, no
## re-import, an empty `git diff`). OK or the error of the file system.
static func write_if_changed(path: String, text: String) -> Error:
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text:
		return OK
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


## "res://packs/legacy/data/sectors/sector_03/screen_05.tres" (`dir` = "" for the game's own: where the sector is; or a folder of sector folders, a copy of it in a test).
static func screen_path(dir: String, sector: int, screen: int) -> String:
	return "%s/screen_%02d.tres" % [Catalog.sector_dir(sector, dir), screen]


static func sector_path(dir: String, sector: int) -> String:
	return Catalog.sector_path(sector, dir)


# --- the screen file ----------------------------------------------------------------------------------------------

## The text of `screen_MM.tres` for `screen`: a port of `build_screen` in tools/import/screen_record.py. Property order,
## ids (`Deco_1`, `Anim_14` ... one counter for the whole file) and number formats are the importer's.
static func screen_text(screen: ScreenData) -> String:
	var ids := {
		"screen_data": "1_screen_data", "deco_placement": "2_deco_placement",
		"anim_deco_data": "3_anim_deco_data", "math_trigger_data": "4_math_trigger_data",
	}
	var subs: Array[String] = []
	var counter := 0
	var lists: Dictionary = {}
	for pair: Array in [["bg_decos", screen.bg_decos], ["mid_decos", screen.mid_decos], ["fg_decos", screen.fg_decos]]:
		var refs: Array[String] = []
		for deco: DecoPlacement in pair[1]:
			counter += 1
			subs.append(_sub("Deco", counter, "deco_placement", ids, [
				["pos", _vec(deco.pos)], ["slot", str(deco.slot)], ["flag", _bool(deco.flag)]]))
			refs.append('SubResource("Deco_%d")' % counter)
		lists[pair[0]] = _array("deco_placement", ids, refs)
	var anim_refs: Array[String] = []
	for anim: AnimDecoData in screen.anim_decos:
		counter += 1
		subs.append(_sub("Anim", counter, "anim_deco_data", ids, [
			["pos", _vec(anim.pos)], ["frames", _packed_ints(anim.frames)], ["size", _vec(anim.size)],
			["start_cursor", str(anim.start_cursor)]]))
		anim_refs.append('SubResource("Anim_%d")' % counter)
	var trigger_refs: Array[String] = []
	for trigger: MathTriggerData in screen.triggers:
		counter += 1
		var props: Array = [["pos", _vec(trigger.pos)], ["slot", str(trigger.slot)], ["armed", _bool(trigger.armed)],
				["rearm_on_enter", _bool(trigger.rearm_on_enter)], ["test_nibble", str(trigger.test_nibble)]]
		if trigger.other_bits & MathTriggerData.OTHER_BITS_MASK != 0:      # never in the original; kept if set
			props.append(["other_bits", str(trigger.other_bits & MathTriggerData.OTHER_BITS_MASK)])
		subs.append(_sub("Trigger", counter, "math_trigger_data", ids, props))
		trigger_refs.append('SubResource("Trigger_%d")' % counter)

	var blocks: Array[String] = ['[gd_resource type="Resource" script_class="ScreenData" format=3]']
	var ext: Array[String] = []
	for key: String in ["screen_data", "deco_placement", "anim_deco_data", "math_trigger_data"]:
		ext.append('[ext_resource type="Script" path="%s%s.gd" id="%s"]' % [SCRIPTS, key, ids[key]])
	blocks.append("\n".join(ext))
	blocks.append_array(subs)
	var body: Array[String] = ["[resource]", 'script = ExtResource("%s")' % ids["screen_data"],
			"original_sector = %d" % screen.original_sector, "original_screen = %d" % screen.original_screen,
			"tiles = PackedByteArray(%s)" % ", ".join(Array(screen.tiles).map(func(b: int) -> String: return str(b))),
			"bg_decos = " + lists["bg_decos"], "mid_decos = " + lists["mid_decos"], "fg_decos = " + lists["fg_decos"],
			"anim_decos = " + _array("anim_deco_data", ids, anim_refs),
			"triggers = " + _array("math_trigger_data", ids, trigger_refs)]
	if not screen.stale_bytes.is_empty():
		body.append("stale_offset = %d" % screen.stale_offset)
		body.append("stale_bytes = PackedByteArray(%s)" % ", ".join(Array(screen.stale_bytes).map(func(b: int) -> String: return str(b))))
	blocks.append("\n".join(body))
	return "\n\n".join(blocks) + "\n"


static func _sub(prefix: String, number: int, script_key: String, ids: Dictionary, props: Array) -> String:
	var lines: Array[String] = ['[sub_resource type="Resource" id="%s_%d"]' % [prefix, number],
			'script = ExtResource("%s")' % ids[script_key]]
	for prop: Array in props:
		lines.append("%s = %s" % [prop[0], prop[1]])
	return "\n".join(lines)


static func _array(script_key: String, ids: Dictionary, refs: Array[String]) -> String:
	return 'Array[ExtResource("%s")]([%s])' % [ids[script_key], ", ".join(refs)]


static func _vec(v: Vector2i) -> String:
	return "Vector2i(%d, %d)" % [v.x, v.y]


static func _bool(value: bool) -> String:
	return "true" if value else "false"


static func _packed_ints(values: PackedInt32Array) -> String:
	return "PackedInt32Array(%s)" % ", ".join(Array(values).map(func(v: int) -> String: return str(v)))


# --- the sector file ----------------------------------------------------------------------------------------------

## `sector_NN.tres` text with the pieces' `screen` / `pos` and the respawn point replaced. Returns {"text": the new
## text, "error": ""} or {"text": "", "error": why}. A line that already holds the wanted value is not touched, so the
## text of an unchanged sector comes back byte for byte.
static func sector_text(text: String, pieces: Array[PieceData], start_pos: Vector2i, start_frame: int) -> Dictionary:
	var lines := text.split("\n")
	var piece_ids := _sub_ids(lines, "pieces")
	if piece_ids.size() != pieces.size():
		return {"text": "", "error": "the sector file lists %d pieces but the editor has %d" % [piece_ids.size(), pieces.size()]}
	for i in pieces.size():
		var header := '[sub_resource type="Resource" id="%s"]' % piece_ids[i]
		var at := lines.find(header)
		if at < 0:
			return {"text": "", "error": "piece %d: no block %s in the sector file" % [i, header]}
		var end := at + 1
		while end < lines.size() and not lines[end].begins_with("["):
			end += 1
		for pair: Array in [["screen", str(pieces[i].screen)], ["pos", _vec(pieces[i].pos)]]:
			if not _set_line(lines, at + 1, end, pair[0], pair[1]):
				return {"text": "", "error": "piece %d: no '%s = ' line in the sector file" % [i, pair[0]]}
	var resource_at := lines.find("[resource]")
	if resource_at < 0:
		return {"text": "", "error": "no [resource] block in the sector file"}
	for pair: Array in [["start_pos", _vec(start_pos)], ["start_frame", str(start_frame)]]:
		if not _set_line(lines, resource_at + 1, lines.size(), pair[0], pair[1]):
			return {"text": "", "error": "no '%s = ' line in the sector file" % pair[0]}
	return {"text": "\n".join(lines), "error": ""}


## `text` (a `sector_NN.tres`) with the creatures' properties (`FOE_FIELDS`) of `after` written over those of `before`: only the
## lines whose value differs are replaced, so equal lists come back byte for byte. The two lists are the creatures of the sector
## in file order (the screen editor passes the creatures as loaded and as the markers say they are now). {"text", "error"} like
## `sector_text`; a different number of creatures than the file lists is an error (adding and removing is not done here).
static func foes_text(text: String, before: Array[FoeData], after: Array[FoeData]) -> Dictionary:
	var lines := text.split("\n")
	var ids := _sub_ids(lines, "foes")
	if ids.size() != after.size() or before.size() != after.size():
		return {"text": "", "error": "the sector file lists %d creatures but the editor has %d" % [ids.size(), after.size()]}
	for i in after.size():
		var header := '[sub_resource type="Resource" id="%s"]' % ids[i]
		var at := lines.find(header)
		if at < 0:
			return {"text": "", "error": "creature %d: no block %s in the sector file" % [i, header]}
		var end := at + 1
		while end < lines.size() and not lines[end].begins_with("["):
			end += 1
		for name in FOE_FIELDS:
			if before[i].get(name) != after[i].get(name):
				if not _patch_line(lines, at + 1, end, name, after[i].get(name)):
					return {"text": "", "error": "creature %d: no '%s = ' line in the sector file, or a value it can not write" % [i, name]}
	return {"text": "\n".join(lines), "error": ""}


## `sector_NN.tres` text (`text`, the file as it is on disk, which loaded as `disk`) with every supported change of `wanted`
## written into it: the properties in `SECTOR_FIELDS`, `PIECE_FIELDS` and `FOE_FIELDS`. Only the lines whose value differs
## between `disk` and `wanted` are replaced, so an unchanged sector comes back byte for byte. Returns {"text", "error"} like
## `sector_text`. If anything else differs (a property that is not on those lists, or the NUMBER of pieces or creatures), the
## result is an error that names it and no text: a change is never dropped silently, and never written in Godot's format.
static func sector_patch(text: String, disk: SectorData, wanted: SectorData) -> Dictionary:
	var unsupported := sector_unsupported(disk, wanted)
	if not unsupported.is_empty():
		return {"text": "", "error": unsupported}
	var lines := text.split("\n")
	# a list with a different number of entries is written again as a whole (the entries have no partner to compare with)
	for group: String in ["pieces", "foes"]:
		if (disk.get(group) as Array).size() != (wanted.get(group) as Array).size():
			var rewritten := SectorLists.rewrite(lines, group, wanted.get(group))
			if not (rewritten.error as String).is_empty():
				return {"text": "", "error": rewritten.error}
			lines = rewritten.lines
	var resource_at := lines.find("[resource]")
	if resource_at < 0:
		return {"text": "", "error": "no [resource] block in the sector file"}
	for name in SECTOR_FIELDS + ["foe_script_base"]:
		if disk.get(name) != wanted.get(name):
			if not _patch_line(lines, resource_at + 1, lines.size(), name, wanted.get(name)):
				return {"text": "", "error": "no '%s = ' line in the sector file, or a value it can not write" % name}
	for group: Array in [["pieces", PIECE_FIELDS, disk.pieces, wanted.pieces], ["foes", FOE_FIELDS, disk.foes, wanted.foes]]:
		if (group[2] as Array).size() != (group[3] as Array).size():
			continue
		var ids := _sub_ids(lines, group[0])
		var before: Array = group[2]
		var after: Array = group[3]
		if ids.size() != after.size():
			return {"text": "", "error": "the sector file lists %d %s but there are %d here" % [ids.size(), group[0], after.size()]}
		for i in after.size():
			var header := '[sub_resource type="Resource" id="%s"]' % ids[i]
			var at := lines.find(header)
			if at < 0:
				return {"text": "", "error": "%s[%d]: no block %s in the sector file" % [group[0], i, header]}
			var end := at + 1
			while end < lines.size() and not lines[end].begins_with("["):
				end += 1
			for name: String in group[1]:
				if before[i].get(name) != after[i].get(name):
					if not _patch_line(lines, at + 1, end, name, after[i].get(name)):
						return {"text": "", "error": "%s[%d].%s: no such line in the sector file, or a value it can not write" % [group[0], i, name]}
	return {"text": "\n".join(lines), "error": ""}


## "" when `wanted` differs from `disk` only in what `sector_patch` can write; else the first thing that does not fit, naming
## the property ("music_name", "pieces[2].is_canister", "screens: ...").
static func sector_unsupported(disk: SectorData, wanted: SectorData) -> String:
	for property in wanted.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name: String = property.name
		if name in SECTOR_FIELDS:
			continue
		if name == "foe_script_base":                              # follows the number of creatures: the script follows the records
			var moved: int = wanted.foe_script_base - disk.foe_script_base
			if moved != FoeData.RECORD_SIZE * (wanted.foes.size() - disk.foes.size()):
				return "foe_script_base is %d (it was %d), but it must follow the number of creatures, %d bytes for each, because the script starts right after the records: add and remove creatures with the Sector Inspector's buttons (SectorData.add_foe / remove_foe), not in the raw list" % [wanted.foe_script_base, disk.foe_script_base, FoeData.RECORD_SIZE]
			continue
		if name == "pieces" or name == "foes":
			var fields: Array[String] = PIECE_FIELDS if name == "pieces" else FOE_FIELDS
			var before: Array = disk.get(name)
			var after: Array = wanted.get(name)
			if before.size() != after.size():
				continue                                           # a different number: `SectorLists` writes the whole list
			for i in after.size():
				var message := _unsupported_in(before[i], after[i], fields, "%s[%d]" % [name, i])
				if not message.is_empty():
					return message
		elif _differs(disk.get(name), wanted.get(name)):
			return "%s was changed, and the sector saver can only write %s, the creatures' properties, the pieces' screen and position and the number of pieces and creatures (change this one in the importer, tools/import/step_sectors.py, or in the file)" % [name, ", ".join(SECTOR_FIELDS)]
	return ""


## The first stored property of `after` (a PieceData or FoeData) that is not in `allowed` and differs from `before`.
static func _unsupported_in(before: Object, after: Object, allowed: Array[String], where: String) -> String:
	for property in after.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name: String = property.name
		if not (name in allowed) and _differs(before.get(name), after.get(name)):
			return "%s.%s was changed, and the sector saver cannot write that property (it can write %s)" % [where, name, ", ".join(allowed)]
	return ""


## Do two property values differ? Resources count as the same when they are the same FILE (the screens of a sector, its script);
## their contents are saved in their own files.
static func _differs(a: Variant, b: Variant) -> bool:
	if a is Resource or b is Resource:
		return not (a is Resource and b is Resource and (a as Resource).resource_path == (b as Resource).resource_path)
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return true
		for i in (a as Array).size():
			if _differs(a[i], b[i]):
				return true
		return false
	return a != b


## Sets `name = <value as the importer writes it>` between lines `from` and `to`. False if there is no such line or the
## value is of a kind the importer's format is not known for.
static func _patch_line(lines: PackedStringArray, from: int, to: int, name: String, value: Variant) -> bool:
	var literal := _literal(value)
	return not literal.is_empty() and _set_line(lines, from, to, name, literal)


## `value` as text in the importer's format (tools/import/tres.py), or "" for a type that is not written here.
static func _literal(value: Variant) -> String:
	match typeof(value):
		TYPE_INT:
			return str(value)
		TYPE_BOOL:
			return _bool(value)
		TYPE_VECTOR2I:
			return _vec(value)
		TYPE_STRING:
			return _quote(value)
		TYPE_PACKED_INT32_ARRAY:
			return _packed_ints(value)
	return ""


## A GDScript string literal, escaped like `tres.s` in the importer (backslash, quote, newline, tab, control characters).
static func _quote(text: String) -> String:
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code == 92:
			out += "\\\\"
		elif code == 34:
			out += '\\"'
		elif code == 10:
			out += "\\n"
		elif code == 9:
			out += "\\t"
		elif code < 32 or code == 127:
			out += "\\u%04x" % code
		else:
			out += text[i]
	return '"' + out + '"'


## The ids of the sub resources listed by the line `array_name = Array[ExtResource("...")]([SubResource("Piece_1"), ...])`
## of the [resource] block, in order. `array_name` is "pieces" or "foes".
static func _sub_ids(lines: PackedStringArray, array_name: String) -> Array[String]:
	var found: Array[String] = []
	for line in lines:
		if line.begins_with(array_name + " = "):
			var rest := line
			while true:
				var from := rest.find('SubResource("')
				if from < 0:
					break
				var to := rest.find('"', from + 13)
				found.append(rest.substr(from + 13, to - from - 13))
				rest = rest.substr(to + 1)
			break
	return found


## Replaces the value of the line `name = ...` between lines `from` and `to` (exclusive). False if there is none.
static func _set_line(lines: PackedStringArray, from: int, to: int, name: String, value: String) -> bool:
	for i in range(from, to):
		if lines[i].begins_with(name + " = "):
			var wanted := "%s = %s" % [name, value]
			if lines[i] != wanted:
				lines[i] = wanted
			return true
	return false


# --- the original ---------------------------------------------------------------------------------------------------

## The original 0x500-byte record of screen `screen` of sector `sector`, or an empty array when the importer has not written
## the original bytes (`has_original_bytes()`; a project without tests/, or a copy of the repository where nobody ran
## tools/import/import_all.py on their copy of the game). The bytes are the importer's, from the game's files; the editor only
## reads them. `original_sha256` is what the committed fixture says they hash to.
static func original_record(sector: int, screen: int) -> PackedByteArray:
	if _fixture.is_empty():
		var file := FileAccess.open(ORIGINAL_BYTES_PATH, FileAccess.READ)
		if file == null:
			return PackedByteArray()
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not (parsed is Dictionary):
			return PackedByteArray()
		for entry: Dictionary in parsed["sectors"]:
			var records: Array = []
			for row: Dictionary in entry["screens"]:
				var raw := String(row["record_hex"]).hex_decode()
				raw.resize(ScreenData.RECORD_SIZE)                  # the fixture leaves out the trailing zeros
				records.append(raw)
			_fixture[int(entry["index"])] = records
	if not _fixture.has(sector):
		return PackedByteArray()
	return _fixture[sector][screen]


## True when the importer's file of the original record bytes is there.
static func has_original_bytes() -> bool:
	return FileAccess.file_exists(ORIGINAL_BYTES_PATH)


## The SHA-256 (lower-case hex) the committed fixture holds for the original record of screen `screen` of sector `sector`, or ""
## when the fixture is not there (a project without tests/) or has no such screen. Needs no original bytes.
static func original_sha256(sector: int, screen: int) -> String:
	if _hashes.is_empty() and FileAccess.file_exists(HASH_FIXTURE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HASH_FIXTURE_PATH))
		if parsed is Dictionary:
			for entry: Dictionary in parsed["sectors"]:
				var rows := {}
				for row: Dictionary in entry["screens"]:
					rows[int(row["screen"])] = String(row["sha256"])
				_hashes[int(entry["index"])] = rows
	return _hashes.get(sector, {}).get(screen, "")
