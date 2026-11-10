@tool
class_name OriginalBytes
extends RefCounted
## The original game's bytes and hashes, as the fidelity tests read them: what `SectorChanges` compares a sector with.
##
## Teaches: the two halves of the fidelity idea (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"). `tests/fixtures/*.json` is
## committed and holds a SHA-256 of every whole original record (a sector header, a screen, a creature record, a script, a table):
## the anchor that does not come from anybody's copy of the game. `tests/fixtures/original/*.json` is written by the importer from
## YOUR copy, git-ignored, and holds the bytes themselves. With only the hashes one can say THAT a record differs; with the bytes
## one can say WHICH field. So every `...()` function that returns bytes returns an empty array when the importer has not written
## them, and also when they are not the bytes the committed hash is of (a different release or a patched copy would otherwise be
## compared with itself): `problems` says which, and `has_bytes()` / the `..._hash` functions tell the report what it can still
## say. Nothing here is cached beyond one instance, so make a new one for every report (the importer may have run since).

const FIXTURE_DIR := "res://tests/fixtures/"
const NEED_THE_IMPORTER := "run tools/import/import_all.py on your copy of the game"

## Where the importer's files are: `FixtureHash.ORIGINAL_DIR`, or another folder (a test points it at one that does not exist to
## see how the report degrades).
var original_dir: String = FixtureHash.ORIGINAL_DIR
## Why some original bytes could not be used (a file that is not what its hash says), one sentence each.
var problems: Array[String] = []

var _json: Dictionary = {}                 # file stem -> parsed contents, or null


func _init(p_original_dir: String = FixtureHash.ORIGINAL_DIR) -> void:
	original_dir = p_original_dir


## The parsed JSON of `res://tests/fixtures/<stem>.json` (the committed hashes) or, with `original`, of the importer's file of the
## same name; an empty dictionary when the file is not there.
func _file(stem: String, original: bool) -> Dictionary:
	var key := ("original/" if original else "") + stem
	if not _json.has(key):
		var path := (original_dir if original else FIXTURE_DIR).path_join(stem + ".json")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_json[key] = parsed if parsed is Dictionary else {}
	return _json[key]


## Is the importer's file for `stem` ("screens", "sector_headers", ...) there?
func has_bytes(stem: String) -> bool:
	return not _file(stem, true).is_empty()


## The first entry of `list` (an Array of dictionaries) whose `key` is `value`, or an empty dictionary.
static func _entry(list: Array, key: String, value: Variant) -> Dictionary:
	for item: Dictionary in list:
		if item.get(key) == value or str(item.get(key)) == str(value):
			return item
	return {}


## `bytes` when its SHA-256 is `expected`; otherwise an empty array, with the reason added to `problems`.
func _verified(bytes: PackedByteArray, expected: String, what: String, stem: String) -> PackedByteArray:
	if bytes.is_empty() or expected.is_empty():
		return PackedByteArray()
	if FixtureHash.sha256_hex(bytes) != expected:
		var text := "%s in %s.json does not match the SHA-256 committed in the fixture (your copy of the game is a different version or patched); %s" % [what, stem, NEED_THE_IMPORTER]
		if not problems.has(text):
			problems.append(text)
		return PackedByteArray()
	return bytes


# --- sector headers --------------------------------------------------------------------------------------------------

func has_sector(index: int) -> bool:
	return not _entry(_file("sector_headers", false).get("sectors", []), "index", index).is_empty()


func header_hash(index: int) -> String:
	return _entry(_file("sector_headers", false).get("sectors", []), "index", index).get("header_sha256", "")


func header(index: int) -> PackedByteArray:
	var entry := _entry(_file("sector_headers", true).get("sectors", []), "index", index)
	if entry.is_empty():
		return PackedByteArray()
	return _verified(String(entry["header_hex"]).hex_decode(), header_hash(index), "the header of sector %d" % index, "sector_headers")


# --- creature records ------------------------------------------------------------------------------------------------

## The hash of every creature record of the sector (empty array for a sector without an original).
func foe_hashes(index: int) -> Array[String]:
	var out: Array[String] = []
	for foe: Dictionary in _entry(_file("foe_records", false).get("sectors", []), "index", index).get("foes", []):
		out.append(foe["sha256"])
	return out


## The original records of the sector (Array of PackedByteArray), or an empty array.
func foe_records(index: int) -> Array:
	var entry := _entry(_file("foe_records", true).get("sectors", []), "index", index)
	var hashes := foe_hashes(index)
	var records: Array = []
	if entry.is_empty() or entry["records_hex"].size() != hashes.size():
		return records
	for k in hashes.size():
		var bytes := _verified(String(entry["records_hex"][k]).hex_decode(), hashes[k], "creature %d of sector %d" % [k, index], "foe_records")
		if bytes.is_empty():
			return []
		records.append(bytes)
	return records


# --- creature scripts ------------------------------------------------------------------------------------------------

## The committed provenance of the script: {"offset" (the base), "size", "sha256"}; empty without an original.
func script_hash(index: int) -> Dictionary:
	return _entry(_file("foe_scripts", false).get("sectors", []), "index", index)


## The original script as `FoeAnnotations.original` gives it: {"index", "base", "script" (bytes), "offsets" (one [pc, hit, ink] per
## creature), "entries" (label -> offset)}, or an empty dictionary.
func script(index: int) -> Dictionary:
	var entry := _entry(_file("foe_scripts", true).get("sectors", []), "index", index)
	var hashes := script_hash(index)
	if entry.is_empty() or hashes.is_empty():
		return {}
	var bytes := _verified(String(entry["script_hex"]).hex_decode(), hashes["sha256"], "the script of sector %d" % index, "foe_scripts")
	if bytes.is_empty():
		return {}
	var offsets: Array = []
	for foe: Dictionary in entry["foes"]:
		offsets.append([int(foe["pc"]), int(foe["script_hit"]), int(foe["script_ink"])])
	return {"index": index, "base": int(entry["base"]), "script": bytes, "offsets": offsets, "entries": FoeAsm.entry_names(offsets)}


# --- screens ---------------------------------------------------------------------------------------------------------

func screen_hash(index: int, screen: int) -> String:
	var sector := _entry(_file("screens", false).get("sectors", []), "index", index)
	return _entry(sector.get("screens", []), "screen", screen).get("sha256", "")


## The original record (ScreenData.RECORD_SIZE bytes) of a screen, or an empty array.
func screen(index: int, screen_number: int) -> PackedByteArray:
	var sector := _entry(_file("screens", true).get("sectors", []), "index", index)
	var entry := _entry(sector.get("screens", []), "screen", screen_number)
	if entry.is_empty():
		return PackedByteArray()
	var record := String(entry["record_hex"]).hex_decode()      # the hex is cut after the last non-zero byte, the rest is zero
	record.resize(ScreenData.RECORD_SIZE)
	return _verified(record, screen_hash(index, screen_number), "screen %d of sector %d" % [screen_number, index], "screens")


# --- sprite sizes and hit rectangles ---------------------------------------------------------------------------------

## The names of the sets the fixture lists ("common", "ink", "zone0" ...).
func sprite_sets() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in _file("sprite_meta", false).get("sets", []):
		out.append(entry["name"])
	return out


func sprite_hash(set_name: String, kind: String) -> String:
	return _entry(_file("sprite_meta", false).get("sets", []), "name", set_name).get("tables", {}).get(kind, {}).get("sha256", "")


## One of the set's three 512-byte tables ("widths", "heights", "hit_rects"), or an empty array.
func sprite_table(set_name: String, kind: String) -> PackedByteArray:
	var entry := _entry(_file("sprite_meta", true).get("sets", []), "name", set_name)
	if entry.is_empty() or not entry.has(kind + "_hex"):
		return PackedByteArray()
	return _verified(String(entry[kind + "_hex"]).hex_decode(), sprite_hash(set_name, kind), "the %s table of sprite set %s" % [kind, set_name], "sprite_meta")


# --- the single tables -----------------------------------------------------------------------------------------------

func trigger_hash() -> String:
	return _file("trigger_table", false).get("sha256", "")


func trigger_table() -> PackedByteArray:
	var entry := _file("trigger_table", true)
	return _verified(String(entry.get("hex", "")).hex_decode(), trigger_hash(), "the trigger table", "trigger_table")


func zones_hash() -> String:
	return _file("zones", false).get("sha256", "")


func zones() -> PackedByteArray:
	var entry := _file("zones", true)
	return _verified(String(entry.get("hex", "")).hex_decode(), zones_hash(), "the default levels", "zones")


# --- problem tables --------------------------------------------------------------------------------------------------

## {"sha256", "size"} of the stored table of a problem type at an educational level; empty when the original has none.
func problem_hash(type_id: int, level: int) -> Dictionary:
	for entry: Dictionary in _file("problem_tables", false).get("tables", []):
		if int(entry["type"]) == type_id and int(entry["level"]) == level:
			return entry
	return {}


func problem_table(type_id: int, level: int) -> PackedByteArray:
	for entry: Dictionary in _file("problem_tables", true).get("tables", []):
		if int(entry["type"]) == type_id and int(entry["level"]) == level:
			return _verified(String(entry["hex"]).hex_decode(), problem_hash(type_id, level).get("sha256", ""), "the problem table of type %d level %d" % [type_id, level], "problem_tables")
	return PackedByteArray()


## The numbers of the original's problem types that have a stored table.
func problem_types() -> Array[int]:
	var out: Array[int] = []
	for entry: Dictionary in _file("problem_tables", false).get("tables", []):
		if not out.has(int(entry["type"])):
			out.append(int(entry["type"]))
	return out


# --- the original's limits, from the committed fixtures --------------------------------------------------------------

## The most creatures any original sector has.
func max_creatures() -> int:
	var most := 0
	for entry: Dictionary in _file("foe_records", false).get("sectors", []):
		most = maxi(most, entry["foes"].size())
	return most


## The longest original creature script, in bytes.
func max_script_size() -> int:
	var most := 0
	for entry: Dictionary in _file("foe_scripts", false).get("sectors", []):
		most = maxi(most, int(entry["size"]))
	return most
