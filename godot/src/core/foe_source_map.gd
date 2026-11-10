class_name FoeSourceMap
extends RefCounted
## Which line of a `.foe` text an instruction came from, and the other way round: the debugger's map between the
## bytes a creature runs and the text a designer wrote.
##
## Teaches: a SOURCE MAP. A compiler throws the text away, keeping only bytes; a debugger that wants to say "the eel is on
## line 42" needs the way back. The assembler already writes it down while it works (`FoeAsm.Result.instruction_lines`: buffer
## offset of every instruction -> its line), so a source map is that table plus what a person asks of it: the line a creature's
## program counter is on, the text of that line, the label it sits under, and which creatures can ever execute a given line
## (the other direction, for "run this script in the sandbox from the line I am looking at").
##
## A plain object (no editor, no scene): `SectorData.foe_source_map` keeps one for the sector's compiled script, the Foe
## Script editor builds one from its buffer (`from_source`), and the sandbox asks it about every creature's `pc`.
## Lines are numbered from 1, as in the assembler's messages and the editor's gutter; 0 means "none".

## The text, line by line (no line endings).
var source_lines: PackedStringArray = PackedStringArray()
## buffer offset of every instruction (a Padding line too) -> its line (1-based): `FoeAsm.Result.instruction_lines`.
var instruction_lines: Dictionary = {}
## label name -> buffer offset, as assembled.
var labels: Dictionary = {}
## The bytes the text assembled to (empty when it has errors) and the buffer offset of the first one.
var bytes: PackedByteArray = PackedByteArray()
var base: int = 0

var _line_offsets: Dictionary = {}                  # line -> buffer offset of the instruction on it
var _label_above: PackedStringArray = PackedStringArray()      # [line] -> the label defined on that line or the nearest one above
var _decoded: Array[Dictionary] = []                # the instructions of `bytes`, decoded on first use
var _reach: Dictionary = {}                         # entry offset -> {line: true} (the lines a creature starting there can run)


## The map of an assembled `source`. `result` is what `FoeAsm.assemble(source, base, ...)` returned for it.
static func from_result(source: String, result: FoeAsm.Result) -> FoeSourceMap:
	var map := FoeSourceMap.new()
	map.source_lines = source.replace("\r", "").split("\n")
	map.instruction_lines = result.instruction_lines
	map.labels = result.labels
	map.bytes = result.bytes
	map.base = result.base
	map._index()
	return map


## Assembles `source` and maps it (the Foe Script editor does this with its buffer).
static func from_source(source: String, base: int = 0, symbols: FoeNames = null) -> FoeSourceMap:
	return from_result(source, FoeAsm.assemble(source, base, symbols))


## The line (1-based) of the instruction that starts at buffer offset `pc`; 0 when none does (the offset is outside the
## script, inside an instruction, or the text has errors that left the line unknown). A creature's `pc` is always the
## start of the instruction it runs next, so for a live creature this is "the line it is about to execute".
func line_of(pc: int) -> int:
	return instruction_lines.get(pc, 0)


## The buffer offset of the instruction on `line`; -1 when the line is not an instruction (a label, a comment, a blank).
func offset_of(line: int) -> int:
	return _line_offsets.get(line, -1)


## The text of `line` exactly as written (indentation and comment included); "" outside the text.
func line_text(line: int) -> String:
	return source_lines[line - 1] if line >= 1 and line <= source_lines.size() else ""


## The label `line` belongs to: the one defined on it, or the nearest one above ("" before the first label).
func label_above(line: int) -> String:
	return _label_above[line] if line >= 1 and line < _label_above.size() else ""


## One line for a debug display: `line 42 under 'again': Loop_Counter0_Back_To again 6  ; comment`. Without a line for `pc`
## (see `line_of`) it says so.
func describe(pc: int) -> String:
	var line := line_of(pc)
	if line == 0:
		return "no source line for offset %d" % pc
	var under := label_above(line)
	return "line %d%s: %s" % [line, "" if under.is_empty() else " under '%s'" % under, line_text(line).strip_edges()]


## The creatures of `foes` (FoeData, by index in the array) whose script runs `line`, for "run this in the sandbox from
## here". A creature that ENTERS at the label the line belongs to (its start, hit or ink label) comes first, in creature
## order; then the others that can reach the line by jumping, calling or falling through (`FoeAsm.reachable`, the same
## analysis that finds dead code). A line that is not an instruction (a comment, a blank, a label) stands for the
## first instruction after it (and the label that one is under). Empty when the text does not assemble or no creature runs it.
func creatures_at_line(foes: Array[FoeData], line: int) -> Array[int]:
	var target := _instruction_line_from(line)
	var owners: Array[int] = []
	var reachers: Array[int] = []
	if target == 0 or bytes.is_empty():
		return owners
	var under := label_above(target)
	for i in foes.size():
		var entries := _entry_offsets(foes[i])
		if entries.is_empty():
			continue
		if not under.is_empty() and under in [foes[i].start_label, foes[i].hit_label, foes[i].ink_label]:
			owners.append(i)
		elif _reaches(entries, target):
			reachers.append(i)
	return owners + reachers


# --- internals ----------------------------------------------------------------

func _index() -> void:
	for offset in instruction_lines:
		_line_offsets[instruction_lines[offset]] = offset
	_label_above.resize(source_lines.size() + 1)
	var current := ""
	for n in source_lines.size():
		var text := source_lines[n]
		var semicolon := text.find(";")
		if semicolon >= 0:
			text = text.substr(0, semicolon)
		text = text.replace("\t", " ").strip_edges()
		if text.ends_with(":") and FoeAsm.is_identifier(text.trim_suffix(":")):
			current = text.trim_suffix(":")
		_label_above[n + 1] = current


## `line` itself when it holds an instruction, else the next line that does; 0 when there is none.
func _instruction_line_from(line: int) -> int:
	for n in range(maxi(line, 1), source_lines.size() + 1):
		if _line_offsets.has(n):
			return n
	return 0


## The three entry offsets (start, hit, ink) of a creature that its labels name; [] if one of them is unknown.
func _entry_offsets(foe: FoeData) -> Array[int]:
	var found: Array[int] = []
	for label in [foe.start_label, foe.hit_label, foe.ink_label]:
		if not labels.has(label):
			return []
		found.append(labels[label])
	return found


func _reaches(entries: Array[int], line: int) -> bool:
	var key := ",".join(PackedStringArray(entries.map(func(offset: int) -> String: return str(offset))))
	if not _reach.has(key):
		var lines: Dictionary = {}
		if _decoded.is_empty():
			_decoded = FoeAsm.decode(bytes, base)
		var alive := FoeAsm.reachable(_decoded, entries)
		for offset in alive:
			if instruction_lines.has(offset):
				lines[instruction_lines[offset]] = true
		_reach[key] = lines
	return _reach[key].has(line)
