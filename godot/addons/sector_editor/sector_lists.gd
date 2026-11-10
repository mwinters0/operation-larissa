@tool
class_name SectorLists
extends RefCounted
## Rewrites the `pieces` or the `foes` list of a `sector_NN.tres` when the NUMBER of entries changed, in the importer's text.
##
## Teaches: why a list that grows or shrinks is written differently from one whose entries only changed. `ScreenFile.sector_patch`
## changes single lines (`pos = Vector2i(..)`) and so needs the same entries before and after. A piece or a creature that is
## added or removed has no such partner: which entry of the file is the one that is gone? A `SectorData` in memory does not
## say (its entries are objects, and the one the Inspector shows is not the one in the file). So this class does not ask: it
## writes EVERY entry of the list again from the data, in the order of the list, and drops or adds the `[sub_resource]` blocks
## at the end. The text of one entry is exactly what the importer writes (tools/import/step_sectors.py `build_sector`), so an
## entry that did not change comes out as it was, and adding a piece and removing it again leaves the file as it was.
## tests/test_sector_lists.gd writes all 32 sectors' lists and demands the file back unchanged.
##
## The blocks are identified by their ids (`Piece_1`, `Foe_8`): the importer counts one number up through the whole file. The
## entries that are still there keep their ids in order, an added entry takes the next number nobody has used, and the ids of
## the entries that are gone are dropped from the end. The ids mean nothing to the game (Godot reads them to connect the
## `pieces = ...` line with the blocks), they only have to be unique.

## The two lists: the array property, the id prefix, the script of its entries and the properties of an entry in the file's order.
const GROUPS := {
	"pieces": {"prefix": "Piece", "script": "piece_data.gd", "fields": ["screen", "pos", "is_canister"]},
	"foes": {"prefix": "Foe", "script": "foe_data.gd", "fields": ["dormant", "hidden", "screen", "pos", "frame", "flip",
			"frame_min", "frame_max", "damage", "start_label", "hit_label", "ink_label"]},
}


## `lines` (the sector file's text, split at the newlines) with the list `group` ("pieces" or "foes") written from `items` (the
## PieceData or FoeData in the list). Returns {"lines": PackedStringArray, "error": ""} or {"lines": [], "error": why}.
static func rewrite(lines: PackedStringArray, group: String, items: Array) -> Dictionary:
	var spec: Dictionary = GROUPS[group]
	var ids := ScreenFile._sub_ids(lines, group)
	var script_id := _script_id(lines, spec["script"])
	if script_id.is_empty():
		return _fail("no [ext_resource] for %s in the sector file" % spec["script"])
	var list_at := _list_line(lines, group)
	if list_at < 0:
		return _fail("no '%s = ' line in the sector file" % group)
	# where the old blocks are: from the first one to the end of the last one
	var start := _insertion_point(lines, group)
	var end := start
	if not ids.is_empty():
		start = lines.find(_header(ids[0], spec))
		var last := lines.find(_header(ids[ids.size() - 1], spec))
		if start < 0 or last < start:
			return _fail("%s: the blocks of the list are not in the order of the list" % group)
		end = last + 1
		while end < lines.size() and not lines[end].begins_with("["):
			end += 1
		for at in range(start, end):
			if lines[at].begins_with("[") and not ids.has(_id_of(lines[at])):
				return _fail("%s: another block lies between the blocks of the list (%s)" % [group, lines[at]])
	# the new ids: the old ones in order, then the next numbers nobody uses
	var next := _highest_number(lines) + 1
	var new_ids: Array[String] = []
	for i in items.size():
		if i < ids.size():
			new_ids.append(ids[i])
		else:
			new_ids.append("%s_%d" % [spec["prefix"], next])
			next += 1
	var block: Array[String] = []
	var refs: Array[String] = []
	for i in items.size():
		block.append_array(block_lines(items[i], new_ids[i], script_id, spec))
		block.append("")
		refs.append('SubResource("%s")' % new_ids[i])
	var out := PackedStringArray()
	out.append_array(lines.slice(0, start))
	out.append_array(PackedStringArray(block))
	out.append_array(lines.slice(end))
	list_at = _list_line(out, group)
	out[list_at] = '%s = Array[ExtResource("%s")]([%s])' % [group, script_id, ", ".join(refs)]
	return {"lines": out, "error": ""}


## The lines of one entry's block (without the blank line after it): the importer's text for a PieceData or a FoeData.
static func block_lines(item: Object, id: String, script_id: String, spec: Dictionary) -> Array[String]:
	var out: Array[String] = ['[sub_resource type="Resource" id="%s"]' % id, 'script = ExtResource("%s")' % script_id]
	for field: String in spec["fields"]:
		out.append("%s = %s" % [field, ScreenFile._literal(item.get(field))])
	if item is FoeData and not (item as FoeData).runtime_state.is_empty():      # only where a byte is not zero, like the importer
		var bytes: PackedByteArray = (item as FoeData).runtime_state
		out.append("runtime_state = PackedByteArray(%s)" % ", ".join(Array(bytes).map(func(b: int) -> String: return str(b))))
	return out


static func _fail(why: String) -> Dictionary:
	return {"lines": PackedStringArray(), "error": why}


static func _header(id: String, _spec: Dictionary) -> String:
	return '[sub_resource type="Resource" id="%s"]' % id


## `Piece_3` of `[sub_resource type="Resource" id="Piece_3"]`.
static func _id_of(header_line: String) -> String:
	var from := header_line.find('id="')
	if from < 0:
		return ""
	return header_line.substr(from + 4, header_line.find('"', from + 4) - from - 4)


## The id of the `[ext_resource]` that loads the script `file`.
static func _script_id(lines: PackedStringArray, file: String) -> String:
	for line in lines:
		if line.begins_with("[ext_resource") and line.contains("/" + file + '"'):
			var from := line.find(' id="')
			return line.substr(from + 5, line.find('"', from + 5) - from - 5)
	return ""


## The line `group = Array[...]` of the [resource] block, or -1.
static func _list_line(lines: PackedStringArray, group: String) -> int:
	var resource_at := lines.find("[resource]")
	for at in range(maxi(resource_at, 0), lines.size()):
		if lines[at].begins_with(group + " = "):
			return at
	return -1


## Where the blocks of a list that has none yet go: the pieces before the first creature block, the creatures before [resource].
static func _insertion_point(lines: PackedStringArray, group: String) -> int:
	for at in lines.size():
		if group == "pieces" and lines[at].begins_with("[sub_resource") and _id_of(lines[at]).begins_with(GROUPS["foes"]["prefix"] + "_"):
			return at
		if lines[at] == "[resource]":
			return at
	return -1


## The largest number at the end of a sub resource's id in the file (`Foe_28` gives 28), 0 if there are none.
static func _highest_number(lines: PackedStringArray) -> int:
	var highest := 0
	for line in lines:
		if line.begins_with("[sub_resource"):
			var id := _id_of(line)
			highest = maxi(highest, id.get_slice("_", id.get_slice_count("_") - 1).to_int())
	return highest
