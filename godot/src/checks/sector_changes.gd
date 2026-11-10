@tool
class_name SectorChanges
extends RefCounted
## The "what changed" report: what a sector differs in from the original, in words.
##
## Teaches: building a readable report out of the encoders the fidelity tests already trust. Every kind of original data has an
## encoder (`SectorData.encode()`, `FoeData.encode()`, `ScreenData.encode()`, `FoeAsm.assemble`, `SpriteMetaTable.encode_*`, ...)
## and a committed SHA-256 of the original's record. The report encodes what is in the project NOW and
##   * with the original bytes (the importer's git-ignored `tests/fixtures/original/*.json`, `OriginalBytes`): names every field that
##     differs, decoded ("piece 4 moved from (120, 64) to (124, 64)", "screen 5: 3 tiles changed, (12, 7) wall 5 -> empty",
##     "creature 2: x 360 -> 364", the creature script as a diff of lines);
##   * without them: compares the hash only, and says WHICH records differ and that the importer on your copy of the game would
##     show the rest.
## A difference that a test lists in its `DELIBERATE_*_CHANGES` constant is reported as DELIBERATE with the reason, not as a
## surprise (`Deliberate`). Plain objects only: no scene, no editor, so the same report runs from the command line
## (`res://src/checks/check_sector.tscn`), from the editor (the Sector Checks plugin) and from a test.
##
## Use:  var report := SectorChanges.report(Catalog.sector(3));  print(report.text())

enum State {
	## Encodes to the original's bytes.
	SAME,
	## Differs from the original and is not on a deliberate list.
	CHANGED,
	## Differs, and a `DELIBERATE_*_CHANGES` constant lists it (the reason is in the details).
	DELIBERATE,
	## The sector (or table) has no original to compare with: a sector the designers made.
	NO_ORIGINAL,
}

const STATE_TEXT: Array[String] = ["same as the original", "differs from the original", "differs from the original on purpose", "has no original"]
## How many detail lines one place lists before it says "... and N more".
const MAX_LINES := 10
const SIDE_NAMES: Array[String] = ["left", "right", "up", "down"]
const HASH_ONLY := "only the hash is compared; %s to see what changed"


## The `DELIBERATE_*_CHANGES` lists of the fidelity tests, which are where the project records a change made on purpose. Read from
## the test files (they are not shipped, so an exported game finds none); a test can fill its own.
class Deliberate extends RefCounted:
	var header: Dictionary = {}        ## sector -> reason (TestSectorHeaderFidelity.DELIBERATE_SECTOR_CHANGES)
	var foe: Dictionary = {}           ## "sector:creature" -> reason (TestFoeRecordFidelity.DELIBERATE_FOE_CHANGES)
	var foe_script: Dictionary = {}   ## sector -> reason (TestFoeAsmLegacy.DELIBERATE_SCRIPT_CHANGES)
	var screen: Dictionary = {}        ## "sector:screen" -> reason (TestScreenFidelity.DELIBERATE_SCREEN_CHANGES)
	var sprite: Dictionary = {}        ## set name -> reason (TestSpriteMetaFidelity.DELIBERATE_SET_CHANGES)
	var trigger: String = ""           ## reason, or "" (TestTriggerTableFidelity.DELIBERATE_TABLE_CHANGE)
	var zones: String = ""             ## reason, or "" (TestZoneFidelity.DELIBERATE_LEVEL_CHANGE)
	var problem: Dictionary = {}       ## type -> reason (TestProblemTableFidelity.DELIBERATE_TYPE_CHANGES)

	static func from_tests() -> Deliberate:
		var out := Deliberate.new()
		out.header = _constant("res://tests/legacy/test_sector_header_fidelity.gd", "DELIBERATE_SECTOR_CHANGES", {})
		out.foe = _constant("res://tests/legacy/test_foe_record_fidelity.gd", "DELIBERATE_FOE_CHANGES", {})
		out.foe_script = _constant("res://tests/legacy/test_foe_asm_legacy.gd", "DELIBERATE_SCRIPT_CHANGES", {})
		out.screen = _constant("res://tests/legacy/test_screen_fidelity.gd", "DELIBERATE_SCREEN_CHANGES", {})
		out.sprite = _constant("res://tests/legacy/test_sprite_meta_fidelity.gd", "DELIBERATE_SET_CHANGES", {})
		out.trigger = _constant("res://tests/legacy/test_trigger_table_fidelity.gd", "DELIBERATE_TABLE_CHANGE", "")
		out.zones = _constant("res://tests/legacy/test_zone_fidelity.gd", "DELIBERATE_LEVEL_CHANGE", "")
		out.problem = _constant("res://tests/legacy/test_problem_table_fidelity.gd", "DELIBERATE_TYPE_CHANGES", {})
		return out

	## The constant `name` of the script at `path`, or `fallback` when the script is not there (an exported game) or has no such constant.
	static func _constant(path: String, name: String, fallback: Variant) -> Variant:
		if not ResourceLoader.exists(path):
			return fallback
		var script_resource := load(path) as GDScript
		if script_resource == null:
			return fallback
		return script_resource.get_script_constant_map().get(name, fallback)


## What a report needs besides the sector: where the original bytes are, which differences are deliberate, and (for tests and
## for tools that hold unsaved work) tables to use instead of the project's own.
class Options extends RefCounted:
	var source: OriginalBytes
	var deliberate: Deliberate
	## "trigger_table" -> TriggerTable, "zones" -> ZoneTable, "sprite:<set>" -> SpriteMetaTable, "problem:<type>" -> ProblemType.
	var overrides: Dictionary = {}

	func _init() -> void:
		source = OriginalBytes.new()
		deliberate = Deliberate.from_tests()


## One kind of data (or one piece of it) compared with the original.
class Item extends RefCounted:
	## "header", "creatures", "script", "screen", "sprite meta", "trigger table", "default levels", "problem table".
	var kind := ""
	## What exactly: "" for the sector's own header, "screen 5", "set zone2", "type 12 (Window Crack)".
	var subject := ""
	var state: State = State.SAME
	var details: Array[String] = []
	## True when only hashes were compared: it says that it differs, not what.
	var hash_only := false

	func label() -> String:
		return kind if subject.is_empty() or subject == kind else "%s (%s)" % [kind, subject]

	func changed() -> bool:
		return state == State.CHANGED

	## "creature 2: x 360 -> 364" lines under a first line "screen 5: differs from the original".
	func text(indent: String = "  ") -> String:
		var lines: Array[String] = ["%s%s: %s" % [indent, subject if not subject.is_empty() else kind, STATE_TEXT[state]]]
		for detail in details:
			lines.append("%s    %s" % [indent, detail])
		return "\n".join(lines)


## The whole report for one sector (or for the shared tables).
class Report extends RefCounted:
	var title := ""
	var sector := -1
	var items: Array[Item] = []
	## Remarks about the report itself (the original bytes are missing, the sector has no original).
	var notes: Array[String] = []

	func add(item: Item) -> void:
		items.append(item)

	## Nothing differs (items that are the same, deliberate or without an original do not count against it).
	func is_same() -> bool:
		return count(State.CHANGED) == 0

	func count(state: State) -> int:
		var n := 0
		for item in items:
			if item.state == state:
				n += 1
		return n

	func uses_hash_only() -> bool:
		for item in items:
			if item.hash_only:
				return true
		return false

	func kinds() -> Array[String]:
		var out: Array[String] = []
		for item in items:
			if not out.has(item.kind):
				out.append(item.kind)
		return out

	## The report as plain text: one paragraph per kind; what is the same takes one line.
	func text() -> String:
		var lines: Array[String] = [title]
		for kind in kinds():
			var group: Array[Item] = []
			for item in items:
				if item.kind == kind:
					group.append(item)
			var differing: Array[Item] = []
			var same_subjects: Array[String] = []
			for item in group:
				if item.state == State.SAME or item.state == State.NO_ORIGINAL:
					same_subjects.append(item.subject)
				else:
					differing.append(item)
			if differing.is_empty():
				lines.append("  %s: %s" % [kind, STATE_TEXT[group[0].state] if group.size() == 1 else "all %d %s" % [group.size(), STATE_TEXT[group[0].state]]])
				for item in group:
					for detail in item.details:
						lines.append("      %s" % detail)
				continue
			if group.size() == 1:
				lines.append(group[0].text())
				continue
			lines.append("  %s: %d of %d differ" % [kind, differing.size(), group.size()])
			for item in differing:
				lines.append(item.text("    "))
			if not same_subjects.is_empty():
				lines.append("    same as the original: %s" % ", ".join(same_subjects))
		for note in notes:
			lines.append("  note: " + note)
		return "\n".join(lines)


# =====================================================================================================================
# One sector
# =====================================================================================================================

## What sector `sector` (what is in memory now: the editor's unsaved work is compared as it is) differs in from the original:
## header, creature records, creature script, the 12 screens, and the sprite sizes / hit rectangles of its zone. The tables the
## whole game shares (trigger table, default levels, problems) are `shared_report`.
static func report(sector: SectorData, options: Options = null) -> Report:
	if options == null:
		options = Options.new()
	var result := Report.new()
	result.sector = sector.index
	result.title = "What changed in sector %d against the original" % sector.index
	if not options.source.has_sector(sector.index):
		for kind in ["header", "creatures", "script", "screen"]:
			var item := Item.new()
			item.kind = kind
			item.state = State.NO_ORIGINAL
			result.add(item)
		result.notes.append("sector %d is not one of the original's %d, so there is nothing to compare it with; use the playability checks instead" % [sector.index, Catalog.ORIGINAL_SECTOR_COUNT])
		return result
	result.add(_header_item(sector, options))
	var script_item := _script_item(sector, options)
	result.add(_creatures_item(sector, options, script_item.state != State.SAME))
	result.add(script_item)
	for m in SectorData.SCREEN_COUNT:
		result.add(_screen_item(sector, m, options))
	for set_name in sprite_sets_of(sector):
		result.add(_sprite_item(set_name, options))
	_add_notes(result, options)
	return result


## The sprite sets whose tables the creatures of `sector` use: the common ones, the ink burst and the zone's own (`SpriteMeta`).
static func sprite_sets_of(sector: SectorData) -> Array[String]:
	return ["common", "ink", "zone%d" % sector.zone]


static func _add_notes(result: Report, options: Options) -> void:
	for problem in options.source.problems:
		result.notes.append(problem)
	if result.uses_hash_only():
		result.notes.append(HASH_ONLY % OriginalBytes.NEED_THE_IMPORTER + " (the original bytes are written to res://tests/fixtures/original/ by the importer)")


# =====================================================================================================================
# The tables the whole game shares
# =====================================================================================================================

## The trigger table, the default educational levels and the stored problems against the original. Not part of one sector.
static func shared_report(options: Options = null) -> Report:
	if options == null:
		options = Options.new()
	var result := Report.new()
	result.title = "What changed in the shared tables against the original"
	result.add(_trigger_item(options))
	result.add(_zones_item(options))
	for type_id in options.source.problem_types():
		result.add(_problem_item(type_id, options))
	_add_notes(result, options)
	return result


# =====================================================================================================================
# Building blocks
# =====================================================================================================================

static func _item(kind: String, subject: String) -> Item:
	var item := Item.new()
	item.kind = kind
	item.subject = subject
	return item


## Sets the state of `item`: SAME when nothing differs, DELIBERATE (with the reason as a detail) when `reason` is not empty.
static func _finish(item: Item, differs: bool, reason: String) -> Item:
	if not differs:
		item.state = State.SAME
	elif not reason.is_empty():
		item.state = State.DELIBERATE
		item.details.push_front("deliberate: %s" % reason)
	else:
		item.state = State.CHANGED
	return item


static func _capped(lines: Array[String], limit: int = MAX_LINES) -> Array[String]:
	if lines.size() <= limit:
		return lines
	var out: Array[String] = lines.slice(0, limit)
	out.append("... and %d more" % (lines.size() - limit))
	return out


static func _hash_only_detail(what: String = "it") -> String:
	return "%s differs (%s)" % [what, HASH_ONLY % OriginalBytes.NEED_THE_IMPORTER]


static func _u16(bytes: PackedByteArray, at: int) -> int:
	return bytes.decode_u16(at)


# =====================================================================================================================
# The sector header
# =====================================================================================================================

static func _header_item(sector: SectorData, options: Options) -> Item:
	var item := _item("header", "")
	var problems := sector.header_problems()
	var reason: String = options.deliberate.header.get(sector.index, "")
	if not problems.is_empty():
		item.details.append("does not fit the original's header, so it cannot be compared: %s" % problems[0])
		return _finish(item, true, reason)
	var bytes := sector.encode()
	var original := options.source.header(sector.index)
	if not original.is_empty():
		var lines := header_differences(original, bytes)
		item.details.append_array(_capped(lines, 40))
		return _finish(item, not lines.is_empty(), reason)
	var same := FixtureHash.sha256_hex(bytes) == options.source.header_hash(sector.index)
	if not same:
		item.hash_only = true
		item.details.append(_hash_only_detail("the header"))
	return _finish(item, not same, reason)


## The differences between two headers (the original's `expected` and the current `actual`), decoded: one line each.
static func header_differences(expected: PackedByteArray, actual: PackedByteArray) -> Array[String]:
	var lines: Array[String] = []
	if expected.size() != SectorData.HEADER_SIZE or actual.size() != SectorData.HEADER_SIZE:
		lines.append("the header has %d bytes, expected %d" % [actual.size(), expected.size()])
		return lines
	var start_was := Vector2i(_u16(expected, 0) * 2, _u16(expected, 2) * 2)
	var start_now := Vector2i(_u16(actual, 0) * 2, _u16(actual, 2) * 2)
	if start_was != start_now:
		lines.append("start position (%d, %d) -> (%d, %d)" % [start_was.x, start_was.y, start_now.x, start_now.y])
	if _u16(expected, 0x3E) != _u16(actual, 0x3E):
		lines.append("start frame %d -> %d" % [_u16(expected, 0x3E), _u16(actual, 0x3E)])
	var was_count := _u16(expected, 4)
	var now_count := _u16(actual, 4)
	if was_count != now_count:
		lines.append("piece count %d -> %d" % [was_count, now_count])
	for slot in SectorData.MAX_PIECES:
		var was := [expected[0x06 + slot], _u16(expected, 0x11 + 2 * slot) * 2, _u16(expected, 0x27 + 2 * slot) * 2]
		var now := [actual[0x06 + slot], _u16(actual, 0x11 + 2 * slot) * 2, _u16(actual, 0x27 + 2 * slot) * 2]
		if was == now:
			continue
		var used_was := slot < was_count
		var used_now := slot < now_count
		var name := "piece %d" % slot if (used_was or used_now) else "piece slot %d (not used by the game)" % slot
		if used_was != used_now:
			lines.append("%s %s: screen %d at (%d, %d)" % [name, "added" if used_now else "removed", (now if used_now else was)[0], (now if used_now else was)[1], (now if used_now else was)[2]])
			continue
		if was[0] != now[0]:
			lines.append("%s moved to another screen: %d -> %d" % [name, was[0], now[0]])
		if was[1] != now[1] or was[2] != now[2]:
			lines.append("%s moved from (%d, %d) to (%d, %d)%s" % [name, was[1], was[2], now[1], now[2], "" if was[0] == now[0] else " (on its screen)"])
	for side in 4:
		for screen in SectorData.SCREEN_COUNT:
			var at := 0x42 + 12 * side + screen
			if expected[at] != actual[at]:
				lines.append("%s neighbour of screen %d: %s -> %s" % [SIDE_NAMES[side], screen, _neighbour_text(expected[at] - 1), _neighbour_text(actual[at] - 1)])
	for at in [0x3D, 0x40, 0x41]:
		if expected[at] != actual[at]:
			lines.append("unused header byte 0x%02x (the game never reads it): %d -> %d" % [at, expected[at], actual[at]])
	return lines


static func _neighbour_text(screen: int) -> String:
	return "screen %d" % screen if screen >= 0 else "none"


# =====================================================================================================================
# Creature records
# =====================================================================================================================

static func _creatures_item(sector: SectorData, options: Options, script_changed: bool) -> Item:
	var item := _item("creatures", "")
	var hashes := options.source.foe_hashes(sector.index)
	var originals := options.source.foe_records(sector.index)
	var script_problem := script_problem_of(sector)
	if not script_problem.is_empty():
		item.details.append("cannot be written as the original's records, so they cannot be compared: the creature script has a problem (%s)" % script_problem)
		return _finish(item, true, "")
	var records := sector.encode_foe_records()
	if records.is_empty() and not sector.foes.is_empty():
		var problems := sector.foe_problems()
		item.details.append("cannot be written as the original's records, so they cannot be compared: %s" % (problems[0] if not problems.is_empty() else "?"))
		return _finish(item, true, "")
	var differing := 0
	var deliberate_only := true
	var reasons: Array[String] = []
	var lines: Array[String] = []
	if records.size() != hashes.size():
		lines.append("creature count %d -> %d" % [hashes.size(), records.size()])
		differing += 1
		deliberate_only = false
	var entry_note := false
	for k in maxi(records.size(), hashes.size()):
		var reason := _foe_reason(sector.index, k, options)
		var what := ""
		if k >= hashes.size():
			what = "creature %d added" % k
		elif k >= records.size():
			what = "creature %d removed" % k
		elif not originals.is_empty():
			var fields := foe_differences(originals[k], records[k])
			if fields.is_empty():
				continue
			what = "creature %d: %s" % [k, "; ".join(fields)]
			if script_changed and (fields.filter(func(f: String) -> bool: return f.begins_with("start pc") or f.begins_with("hit script") or f.begins_with("ink script")).size() > 0):
				entry_note = true
		elif FixtureHash.sha256_hex(records[k]) != hashes[k]:
			what = "creature %d differs" % k
			item.hash_only = true
		else:
			continue
		differing += 1
		if reason.is_empty():
			deliberate_only = false
		else:
			reasons.append("creature %d: %s" % [k, reason])
		lines.append(what + ("  (deliberate: %s)" % reason if not reason.is_empty() else ""))
	item.details.append_array(_capped(lines, 30))
	if entry_note:
		item.details.append("(an entry point moves when the script above it changes: see the script)")
	if item.hash_only and differing > 0:
		item.details.append(HASH_ONLY % OriginalBytes.NEED_THE_IMPORTER)
	var summary := ""
	if differing > 0 and deliberate_only:
		summary = "; ".join(reasons)
	return _finish(item, differing > 0, summary)


## "" when the creature script assembles and every creature's entry labels exist (so the records can be encoded without the sector
## complaining), else the first problem. `SectorData.foe_problems()` finds the same, but reports it with `push_error`.
static func script_problem_of(sector: SectorData) -> String:
	var result := FoeAsm.assemble(sector.foe_script.source if sector.foe_script != null else "", sector.foe_script_base, FoeNames.for_sector(sector))
	if not result.ok():
		return result.errors[0]
	for k in sector.foes.size():
		if sector.foes[k] == null:
			return "creature %d is empty" % k
		for label: String in [sector.foes[k].start_label, sector.foes[k].hit_label, sector.foes[k].ink_label]:
			if not result.labels.has(label):
				return "creature %d names the label '%s', which the script does not have" % [k, label]
	return ""


static func _foe_reason(sector: int, creature: int, options: Options) -> String:
	var key := "%d:%d" % [sector, creature]
	if options.deliberate.foe.has(key):
		return str(options.deliberate.foe[key])
	return str(options.deliberate.foe_script.get(sector, ""))


## The differences between two creature records, decoded: "x 360 -> 364", "damage 1 -> 2" ...
static func foe_differences(expected: PackedByteArray, actual: PackedByteArray) -> Array[String]:
	var out: Array[String] = []
	if expected.size() != FoeData.RECORD_SIZE or actual.size() != FoeData.RECORD_SIZE:
		out.append("the record has %d bytes, expected %d" % [actual.size(), expected.size()])
		return out
	var fields := [
		["dormant", 0, 1], ["hidden", 1, 1], ["screen", 2, 1], ["x", 3, 2], ["y", 5, 2], ["frame", 7, 1], ["flip", 8, 1],
		["frame min", 9, 1], ["frame max", 10, 1], ["hit script", 0x0B, 2], ["ink script", 0x0D, 2], ["damage", 0x0F, -1], ["start pc", 0x10, 2]]
	for field: Array in fields:
		var at: int = field[1]
		var was: int
		var now: int
		match field[2]:
			1:
				was = expected[at]
				now = actual[at]
			2:
				was = _u16(expected, at)
				now = _u16(actual, at)
				if field[0] == "x" or field[0] == "y":
					was *= 2
					now *= 2
			_:
				was = expected.decode_s8(at)
				now = actual.decode_s8(at)
		if was != now:
			var label: String = field[0]
			out.append("%s %d -> %d" % [label, was, now])
	if expected.slice(FoeData.RUNTIME_STATE_AT) != actual.slice(FoeData.RUNTIME_STATE_AT):
		out.append("run-time state bytes differ (they are all zero in the original)")
	return out


# =====================================================================================================================
# The creature script
# =====================================================================================================================

static func _script_item(sector: SectorData, options: Options) -> Item:
	var item := _item("script", "")
	var reason: String = str(options.deliberate.foe_script.get(sector.index, ""))
	var fixture := options.source.script_hash(sector.index)
	var source_text := sector.foe_script.source if sector.foe_script != null else ""
	var names := FoeNames.for_sector(sector)
	var result := FoeAsm.assemble(source_text, sector.foe_script_base, names)
	if not result.ok():
		item.details.append("does not assemble, so it cannot be compared with the original:")
		for error in result.errors.slice(0, 3):
			item.details.append("  " + error)
		return _finish(item, true, reason)
	var same := not fixture.is_empty() and FixtureHash.sha256_hex(result.bytes) == str(fixture["sha256"]) and sector.foe_script_base == int(fixture["offset"])
	var original := options.source.script(sector.index)
	var old_text := ""
	if not original.is_empty():
		var store := FoeAnnotations.load_store().store
		old_text = FoeAsm.disassemble(original["script"], original["base"], original["entries"], FoeAnnotations.for_sector(store, sector.index), names)
	if same:
		if not old_text.is_empty() and old_text != source_text:
			var comment_changes := LineDiff.diff(old_text, source_text).size()
			item.details.append("the instructions are the original's; only names or comments differ (%d place%s in the text)" % [comment_changes, "" if comment_changes == 1 else "s"])
		return _finish(item, false, "")
	if fixture.is_empty():
		return _finish(item, true, reason)
	if result.bytes.size() != int(fixture["size"]) or sector.foe_script_base != int(fixture["offset"]):
		item.details.append("assembles to %d bytes at buffer offset %d; the original has %d at %d" % [result.bytes.size(), sector.foe_script_base, int(fixture["size"]), int(fixture["offset"])])
	if old_text.is_empty():
		item.hash_only = true
		item.details.append(_hash_only_detail("the script"))
		return _finish(item, true, reason)
	item.details.append_array(_script_hunks(old_text, source_text, sector))
	return _finish(item, true, reason)


## The comment-free, whitespace-normalised instruction lines of a script text, with each one's line number in the text.
static func _code_lines(text: String) -> Dictionary:
	var lines: Array[String] = []
	var numbers: Array[int] = []
	var n := 0
	for raw in text.replace("\r\n", "\n").split("\n"):
		n += 1
		var code: String = raw
		var semicolon := code.find(";")
		if semicolon >= 0:
			code = code.substr(0, semicolon)
		code = " ".join(code.replace("\t", " ").strip_edges().split(" ", false))
		if code.is_empty():
			continue
		lines.append(code)
		numbers.append(n)
	return {"lines": lines, "numbers": numbers}


## The places where the script text differs from the original's disassembly, as sentences with the source line numbers.
## Comments and blank lines do not count. `sector` names the creature that enters at the nearest label before a place.
static func _script_hunks(old_text: String, new_text: String, sector: SectorData) -> Array[String]:
	var old_code := _code_lines(old_text)
	var new_code := _code_lines(new_text)
	var new_lines: Array[String] = new_code["lines"]
	var new_numbers: Array[int] = new_code["numbers"]
	var hunks := LineDiff.diff_lines(old_code["lines"], new_lines)
	var out: Array[String] = []
	if hunks.is_empty():
		out.append("only names or comments differ, no instruction does")
		return out
	for hunk in hunks.slice(0, 12):
		var first_index := mini(hunk.new_start - 1, new_lines.size() - 1)
		var first_line: int = new_numbers[first_index] if first_index >= 0 else 1
		var last_line: int = new_numbers[mini(hunk.new_start - 1 + hunk.new_lines.size() - 1, new_lines.size() - 1)] if not hunk.new_lines.is_empty() else first_line
		var where := "line %d" % first_line if hunk.new_lines.size() <= 1 else "lines %d-%d" % [first_line, last_line]
		if hunk.new_lines.is_empty():
			where = "before line %d" % first_line
		var owner := _owner_text(new_lines, hunk.new_start - 1, sector)
		if hunk.kind() == "changed" and hunk.old_lines.size() == hunk.new_lines.size():
			var pairs: Array[String] = []
			for i in mini(hunk.new_lines.size(), 4):
				pairs.append("`%s` (was `%s`)" % [hunk.new_lines[i], hunk.old_lines[i]])
			out.append("%s%s: %s%s" % [where, owner, "; ".join(pairs), " ..." if hunk.new_lines.size() > 4 else ""])
		else:
			var now := "; ".join(hunk.new_lines.slice(0, 3)) if not hunk.new_lines.is_empty() else "nothing"
			var was := "; ".join(hunk.old_lines.slice(0, 3)) if not hunk.old_lines.is_empty() else "nothing"
			out.append("%s%s %s: now `%s`%s, was `%s`%s" % [where, owner, hunk.kind(), now, " ..." if hunk.new_lines.size() > 3 else "", was, " ..." if hunk.old_lines.size() > 3 else ""])
	if hunks.size() > 12:
		out.append("... and %d more places" % (hunks.size() - 12))
	return out


## " (in `eel_loop`, creature 3's start)": the nearest label at or before code line `index`, and the creatures that enter there.
static func _owner_text(code: Array[String], index: int, sector: SectorData) -> String:
	for i in range(mini(index, code.size() - 1), -1, -1):
		if not code[i].ends_with(":") or code[i].contains(" "):
			continue
		var label := code[i].trim_suffix(":")
		var users: Array[String] = []
		for k in sector.foes.size():
			for pair: Array in [["start", sector.foes[k].start_label], ["hit", sector.foes[k].hit_label], ["ink", sector.foes[k].ink_label]]:
				if pair[1] == label:
					users.append("creature %d's %s" % [k, pair[0]])
		return " (in `%s`%s)" % [label, ", " + ", ".join(users.slice(0, 3)) if not users.is_empty() else ""]
	return ""


# =====================================================================================================================
# Screens
# =====================================================================================================================

static func _screen_item(sector: SectorData, m: int, options: Options) -> Item:
	var item := _item("screen", "screen %d" % m)
	var reason: String = str(options.deliberate.screen.get("%d:%d" % [sector.index, m], ""))
	if m >= sector.screens.size() or sector.screens[m] == null:
		item.details.append("missing")
		return _finish(item, true, reason)
	var screen := sector.screens[m]
	var problems := screen.validate()
	if not problems.is_empty():
		item.details.append("does not fit the original's record, so it cannot be compared: %s" % problems[0])
		return _finish(item, true, reason)
	var bytes := screen.encode()
	var original := options.source.screen(sector.index, m)
	if not original.is_empty():
		var lines := screen_differences(original, bytes)
		item.details.append_array(lines)
		return _finish(item, not lines.is_empty(), reason)
	var same := FixtureHash.sha256_hex(bytes) == options.source.screen_hash(sector.index, m)
	if not same:
		item.hash_only = true
		item.details.append(_hash_only_detail("the screen"))
	return _finish(item, not same, reason)


## What changed between two screen records: tiles (where), and each deco / anim deco / trigger list.
static func screen_differences(expected: PackedByteArray, actual: PackedByteArray) -> Array[String]:
	var out: Array[String] = []
	if expected.size() != ScreenData.RECORD_SIZE or actual.size() != ScreenData.RECORD_SIZE:
		out.append("the record has %d bytes, expected %d" % [actual.size(), expected.size()])
		return out
	var tiles: Array[String] = []
	var changed_tiles := 0
	var low := Vector2i(ScreenData.TILE_COLUMNS, ScreenData.TILE_ROWS)
	var high := Vector2i(-1, -1)
	for i in ScreenData.TILE_BYTES:
		if expected[i] == actual[i]:
			continue
		changed_tiles += 1
		var cell := Vector2i(i % ScreenData.TILE_COLUMNS, i / ScreenData.TILE_COLUMNS)
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
		tiles.append("(%d, %d) %s -> %s" % [cell.x, cell.y, _tile_name(expected[i]), _tile_name(actual[i])])
	if changed_tiles > 0:
		out.append("%d tile%s changed (columns %d-%d, rows %d-%d): %s" % [changed_tiles, "" if changed_tiles == 1 else "s", low.x, high.x, low.y, high.y, "; ".join(_capped(tiles, 6))])
	var was := _parse_record(expected)
	var now := _parse_record(actual)
	for list in ScreenData.LAYOUT.size():
		var layout: Dictionary = ScreenData.LAYOUT[list]
		out.append_array(_list_differences(layout, was["lists"][list], now["lists"][list]))
	var from := maxi(was["used"], now["used"])
	if expected.slice(from) != actual.slice(from):
		out.append("the leftover bytes after the lists changed (the game never reads them)")
	return out


static func _tile_name(byte: int) -> String:
	if byte == 0:
		return "empty"
	if byte & TileCodec.SOLID_BIT != 0:
		return "wall %d" % (byte & 0x3F)
	if byte & TileCodec.CURRENT_BIT != 0:
		return "current 0x%02x" % byte
	return "0x%02x" % byte


## {"lists": [Array of PackedByteArray per `ScreenData.LAYOUT` entry], "used": bytes the lists take}. Stops at the end of the
## record if a count is wrong.
static func _parse_record(record: PackedByteArray) -> Dictionary:
	var lists: Array = []
	var p := ScreenData.TILE_BYTES
	for layout: Dictionary in ScreenData.LAYOUT:
		var entries: Array[PackedByteArray] = []
		var count: int = record[p] if p < record.size() else 0
		p += 1
		var size: int = layout["size"]
		for e in count:
			if p + size > record.size():
				break
			entries.append(record.slice(p, p + size))
			p += size
		lists.append(entries)
	return {"lists": lists, "used": p}


static func _list_differences(layout: Dictionary, was: Array, now: Array) -> Array[String]:
	var out: Array[String] = []
	var name: String = layout["name"]
	if was == now:
		return out
	if was.size() == now.size():
		for e in was.size():
			if was[e] != now[e]:
				out.append("%s entry %d: %s" % [name, e, _entry_differences(layout, was[e], now[e])])
		return _capped(out)
	var was_left: Array = was.duplicate()
	var added: Array[String] = []
	for entry: PackedByteArray in now:
		var found := was_left.find(entry)
		if found >= 0:
			was_left.remove_at(found)
		else:
			added.append(_entry_text(layout, entry))
	var removed: Array[String] = []
	for entry: PackedByteArray in was_left:
		removed.append(_entry_text(layout, entry))
	out.append("%s: %d -> %d entries%s%s" % [name, was.size(), now.size(),
			"; added %s" % ", ".join(_capped(added, 4)) if not added.is_empty() else "", "; removed %s" % ", ".join(_capped(removed, 4)) if not removed.is_empty() else ""])
	return out


## The field values of an entry, in pixels where the record halves or quarters them: "x 64, y 32, slot and mirror flag 5".
static func _entry_text(layout: Dictionary, entry: PackedByteArray) -> String:
	var fields: Array = layout["fields"]
	var parts: Array[String] = []
	for f in mini(fields.size(), entry.size()):
		parts.append("%s %d" % [fields[f], _field_value(fields[f], entry[f])])
	if not str(layout["rest"]).is_empty() and entry.size() > fields.size():
		parts.append("frame list %s" % str(Array(entry.slice(fields.size()))))
	return "(%s)" % ", ".join(parts)


static func _entry_differences(layout: Dictionary, was: PackedByteArray, now: PackedByteArray) -> String:
	var fields: Array = layout["fields"]
	var parts: Array[String] = []
	for i in mini(was.size(), now.size()):
		if was[i] == now[i]:
			continue
		if i < fields.size():
			parts.append("%s %d -> %d" % [fields[i], _field_value(fields[i], was[i]), _field_value(fields[i], now[i])])
		elif not parts.any(func(p: String) -> bool: return p.begins_with("frame list")):
			parts.append("frame list %s -> %s" % [str(Array(was.slice(fields.size()))), str(Array(now.slice(fields.size())))])
	return ", ".join(parts)


## A record byte as the pixel value the editor shows: x and width are stored divided by 4, y and height by 2.
static func _field_value(field: String, byte: int) -> int:
	match field:
		"x", "width":
			return byte * 4
		"y", "height":
			return byte * 2
	return byte


# =====================================================================================================================
# Sprite sizes and hit rectangles
# =====================================================================================================================

static func _sprite_item(set_name: String, options: Options) -> Item:
	var item := _item("sprite meta", "set %s" % set_name)
	var reason: String = str(options.deliberate.sprite.get(set_name, ""))
	var table: SpriteMetaTable = options.overrides.get("sprite:" + set_name)
	if table == null:
		table = Packs.resource("data/sprite_meta/sprite_meta_%s.tres" % set_name) as SpriteMetaTable
	if table == null:
		item.details.append("the table is missing")
		return _finish(item, true, reason)
	var problems := table.problems()
	if not problems.is_empty():
		item.details.append("does not fit the original's tables, so it cannot be compared: %s" % problems[0])
		return _finish(item, true, reason)
	var differs := false
	for kind in ["widths", "heights", "hit_rects"]:
		var bytes: PackedByteArray = table.call("encode_" + kind)
		var original := options.source.sprite_table(set_name, kind)
		if not original.is_empty():
			var changes: Array[String] = []
			for i in original.size():
				if original[i] != bytes[i]:
					changes.append("%s: %d -> %d" % [SpriteMetaTable.field_at(kind, i, table.count()), original[i] * 2, bytes[i] * 2])
			if not changes.is_empty():
				differs = true
				item.details.append_array(_capped(changes))
		elif FixtureHash.sha256_hex(bytes) != options.source.sprite_hash(set_name, kind):
			differs = true
			item.hash_only = true
			item.details.append(_hash_only_detail("the %s table" % kind))
	return _finish(item, differs, reason)


# =====================================================================================================================
# The trigger table, the default levels, the problem tables
# =====================================================================================================================

static func _trigger_item(options: Options) -> Item:
	var item := _item("trigger table", "")
	var table: TriggerTable = options.overrides.get("trigger_table")
	if table == null:
		table = Catalog.trigger_table()
	var problems := table.problems()
	if not problems.is_empty():
		item.details.append("does not fit the original's table, so it cannot be compared: %s" % problems[0])
		return _finish(item, true, options.deliberate.trigger)
	var bytes := table.encode()
	var original := options.source.trigger_table()
	if original.is_empty():
		var same := FixtureHash.sha256_hex(bytes) == options.source.trigger_hash()
		if not same:
			item.hash_only = true
			item.details.append(_hash_only_detail("the table"))
		return _finish(item, not same, options.deliberate.trigger)
	var changes: Array[String] = []
	for i in original.size():
		if original[i] != bytes[i]:
			changes.append("%s: problem type %d -> %d" % [TriggerTable.field_at(i), original[i], bytes[i]])
	item.details.append_array(_capped(changes))
	return _finish(item, not changes.is_empty(), options.deliberate.trigger)


static func _zones_item(options: Options) -> Item:
	var item := _item("default levels", "")
	var table: ZoneTable = options.overrides.get("zones")
	if table == null:
		table = Catalog.zones()
	var problems := table.default_edu_problems()
	if not problems.is_empty():
		item.details.append("does not fit the original's table, so it cannot be compared: %s" % problems[0])
		return _finish(item, true, options.deliberate.zones)
	var bytes := table.encode_default_edu_levels()
	var original := options.source.zones()
	if original.is_empty():
		var same := FixtureHash.sha256_hex(bytes) == options.source.zones_hash()
		if not same:
			item.hash_only = true
			item.details.append(_hash_only_detail("the table"))
		return _finish(item, not same, options.deliberate.zones)
	var changes: Array[String] = []
	for i in original.size():
		if original[i] != bytes[i]:
			changes.append("%s: educational level %d -> %d" % [ZoneTable.field_at(i), original[i], bytes[i]])
	item.details.append_array(changes)
	return _finish(item, not changes.is_empty(), options.deliberate.zones)


static func _problem_item(type_id: int, options: Options) -> Item:
	var item := _item("problem table", "type %d" % type_id)
	var reason: String = str(options.deliberate.problem.get(type_id, ""))
	var type: ProblemType = options.overrides.get("problem:%d" % type_id)
	if type == null:
		# not `Catalog.problem_type`: that asks the skin in use, and a skin is a placeholder in the editor; the original's file is the same object
		type = Packs.resource("data/problems/problem_type_%02d.tres" % type_id) as ProblemType
	if type == null:
		item.details.append("the problem type is missing")
		return _finish(item, true, reason)
	if not type.title.is_empty():
		item.subject = "type %d (%s)" % [type_id, type.title]
	var problems := type.problems()
	if not problems.is_empty():
		item.details.append("does not fit the original's tables, so it cannot be compared: %s" % problems[0])
		return _finish(item, true, reason)
	var differs := false
	for level in 4:
		var fixture := options.source.problem_hash(type_id, level)
		if fixture.is_empty():
			continue
		var bytes := type.encode_table(level)
		var original := options.source.problem_table(type_id, level)
		if not original.is_empty():
			var difference := ProblemType.first_difference(original, bytes, type.field_kinds)
			if not difference.is_empty():
				differs = true
				item.details.append("level %d: %s (%d records now)" % [level, difference, type.record_count(level)])
		elif FixtureHash.sha256_hex(bytes) != str(fixture["sha256"]) or bytes.size() != int(fixture["size"]):
			differs = true
			item.hash_only = true
			item.details.append(_hash_only_detail("the level %d table" % level))
	return _finish(item, differs, reason)
