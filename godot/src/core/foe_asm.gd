class_name FoeAsm
extends RefCounted
## An assembler and disassembler for the creature scripts (DESIGN 3.5): turns text
## like "Jump_To again" into the bytes FoeVM runs, and bytes back into text.
##
## Teaches: what an ASSEMBLER is (a program that translates readable instruction
## names into machine bytes, one line to one instruction); LABELS versus OFFSETS (a
## designer writes "again:" and "Jump_To again"; the assembler works out that the jump
## must go back 9 bytes, so inserting an instruction never breaks a jump); and TWO
## PASSES (pass 1 only measures: how many bytes each line takes, hence where each label
## sits. A jump may name a label further down, so only after pass 1 do all addresses
## exist. Pass 2 then writes the bytes). It is also a round trip: disassemble then
## assemble gives back the original bytes, which the tests check for every sector.
##
## THE TEXT FORMAT
##   ; a comment runs to the end of the line.  Blank lines are ignored.
##   name:                      a label, marks the position of the next instruction
##       Move_Foe_Relative_XY -2 3 1     an instruction: a name from FoeOps.MNEMONIC
##                                       (any upper/lower case) and its operands
## Operands are separated by spaces (no commas):
##   - Jump_To, Call_Subroutine and the first operand of Loop_CounterN_Back_To: a label.
##   - the Loop count: 0..65535.
##   - Move_Foe_Relative_XY dx dy: -128..127, then the picture step 0..255.
##   - Put_Foe_To_Sleep / Wake_Foe: a creature number 0..127, or `self`, `self+N`,
##     `self-N` for "this creature plus N" (N from -64 to 63), or the creature's name.
##   - a sound, a picture, a flag, a screen: a number 0..255, or the NAME of the sound / picture / flag / screen
##     (FoeNames: names are looked up in the scope of the sector). After a picture, `mirrored` flips it:
##     `Set_Frame eel_swim_1 mirrored` is the same as `Set_Frame 169` when eel_swim_1 is 41 (bit 7 is the mirror).
##   - everything else: 0..255.
## Which operands an instruction has, their kinds and valid ranges are not written here:
## they come from the table FoeOps.OPERANDS, which the editor's hints use as well.
##
## PADDING. `Padding N` is a PSEUDO-INSTRUCTION (FoeOps.PADDING): a directive that makes the
## assembler write N zero bytes (a bare `Padding` is 1), like `db 0` or `.fill` in a real
## assembler. It is the disassembler's way of writing filler that no creature reaches.
##
## THE GENERATED COMMENT. The disassembler marks code that can never execute (found by
## `reachable`) with one comment line before each run of it (`unexecuted_notes`); unreachable
## zero bytes are not code, they are written as `Padding N` (`padding_spans`).

## The generated comment, indented like instructions. Keep it equal to
## UNEXECUTED_UNUSED of tools/import/foe_text.py.
const UNEXECUTED_UNUSED := "    ; The following instructions are not executed -- nothing jumps to them"
## What the comment begins with (after the indentation): the editor's dead-code warning is
## not shown for a run under a comment line that starts like this.
const UNEXECUTED_COMMENT_PREFIX := "; The following instructions are not executed"

## The outcome of `assemble`. `bytes` is only filled when `errors` is empty.
class Result extends RefCounted:
	var bytes: PackedByteArray = PackedByteArray()
	## label name -> buffer offset (base + index into bytes)
	var labels: Dictionary = {}
	## The `base` that was given to `assemble`.
	var base: int = 0
	## buffer offset of every instruction -> its source line (1-based). Lets a check of the
	## bytes (`unreachable_offsets`) report in terms of the text.
	var instruction_lines: Dictionary = {}
	## buffer offset of the first byte of every `Padding` line -> {"line": its source line,
	## "count": how many bytes it writes}. A Padding line is also in `instruction_lines`.
	var paddings: Dictionary = {}
	## One message per problem, each starting with "line N:" (1-based).
	var errors: Array[String] = []

	func ok() -> bool:
		return errors.is_empty()


# =============================================================================
# Disassembler
# =============================================================================

## Text for the whole `script`. `base` is the buffer offset of script[0]. `entries`
## maps a label name to a buffer offset (the foes' entry points). Other jump targets
## get the name "loc_<offset>". When several names share an offset only the FIRST
## one `entries` lists is printed; jumps use it too (the creatures that share the
## place all point their entry fields at that one label). The Python importer
## (tools/import/foe_text.py) writes exactly the same text; a test compares them.
##
## `annotations` are the designers' additions for this sector, as FoeAnnotations
## stores them: {"labels": {offset: name}, "comments": {offset: note}}. A stored
## name replaces the generated label at its offset (jumps use it too) or adds a label
## where there is none; a note has up to four keys: "label_above" (lines before the
## label line: replaces the default blank line), "label_inline" (the comment on the
## label line), "above" (lines before the instruction line, or after the last line at
## the end of the script; REPLACES the generated "not executed" comment of
## `unexecuted_notes` at that offset, so an empty list removes it) and "inline" (the
## comment on the instruction line). See
## tools/import/foe_annotations.py for the full rules. Without annotations the text
## is the plain generated one.
##
## Unreachable zero bytes are written as `Padding N` lines (`padding_spans`). A stored
## label or comment at an offset inside such a span cuts the span there, so it keeps a
## line to sit on.
## `symbols` says which names the operands are written with (FoeNames: the sector and zone the script belongs to):
## an operand with a real (non-made-up) name is printed with it, every other one as the number, because a made-up
## name like `sfx_28` says less than 28 does. Without `symbols` every operand is a number. A picture with bit 7
## is printed as the picture and `mirrored` either way.
static func disassemble(script: PackedByteArray, base: int, entries: Dictionary, annotations: Dictionary = {}, symbols: FoeNames = null) -> String:
	var comments: Dictionary = annotations.get("comments", {})
	# --- pass 1: decode every instruction and collect the places that need a name ---
	var decoded := decode(script, base)
	var names := label_names(entries, annotations)    # buffer offset -> the one label printed there
	for target in jump_targets(decoded):
		if not names.has(target):
			names[target] = "loc_%d" % target

	# --- pass 2: print, putting each label before the instruction it marks ---
	var unexecuted := unexecuted_notes(script, base, entries)
	var cuts: Array = annotations.get("labels", {}).keys()
	cuts.append_array(comments.keys())
	var spans := _split_at(padding_spans(script, base, entries.values()), cuts)
	var lines: Array[String] = []
	var placed: Dictionary = {}
	var covered := base                                     # offsets below this belong to a Padding line already
	for item in decoded:
		var at: int = item["at"]
		if at < covered:
			continue
		var text := ""
		if spans.has(at):
			text = "%s %d" % [FoeOps.op_name(FoeOps.PADDING), spans[at]]
			covered = at + int(spans[at])
		else:
			text = "??%d" % item["byte"] if item["op"] < 0 else _format(item["op"], item["operands"], at, names, symbols)
		_emit_position(lines, names, placed, comments.get(at, {}), at, text, unexecuted.get(at, []))
	_emit_position(lines, names, placed, comments.get(base + script.size(), {}), base + script.size(), "", [])    # labels and comments at the very end
	# Names whose offset is not an instruction start cannot be placed. Say so, as comments.
	var stray: Array = names.keys().filter(func(offset): return not placed.has(offset))
	stray.sort()
	for offset in stray:
		lines.append("")
		lines.append("; %s (offset %d) is not at the start of an instruction" % [names[offset], offset])
	return "\n".join(lines) + "\n"


## Every instruction of `script` as {"at": buffer offset, "op": opcode, "operands":
## PackedByteArray}; a byte that cannot be decoded is {"at", "op": -1, "byte"} (printed
## as "??N", which `assemble` rejects).
static func decode(script: PackedByteArray, base: int) -> Array[Dictionary]:
	var decoded: Array[Dictionary] = []
	var index := 0
	while index < script.size():
		var opcode := script[index]
		var count := FoeOps.OPERAND_COUNT[opcode] if FoeOps.is_valid(opcode) else 0
		if not FoeOps.is_valid(opcode) or index + 1 + count > script.size():
			decoded.append({"at": base + index, "op": -1, "byte": opcode})
			index += 1
			continue
		decoded.append({"at": base + index, "op": opcode, "operands": script.slice(index + 1, index + 1 + count)})
		index += 1 + count
	return decoded


## The offsets of the instructions of `decoded` that can ever execute, as a set
## ({offset: true}): a REACHABILITY (control-flow) analysis, the same idea as a
## compiler's dead-code detection.
##
## Start at the `roots` (the creatures' start / hit / ink entry points) and follow every
## way a creature can go on from an instruction, exactly as FoeVM does:
##   - most instructions go on with the NEXT instruction (also Hide_Foe and
##     Wait_Next_Tick: the next tick resumes there);
##   - Jump_To goes to its target and nowhere else (no fall-through);
##   - Return ends the path: it goes back to where the creature was interrupted, or to
##     the instruction after the Call_Subroutine that called it (next point), and both
##     of those are reached by their own paths;
##   - Call_Subroutine goes to its target AND to the next instruction, because the
##     subroutine's Return comes back there;
##   - Loop_Counter0/1/2 go to their target (jump back) AND to the next instruction
##     (the loop is over);
##   - the conditional instructions (If_...) go to the next instruction AND to the one
##     after it (skipped when the condition is false).
## Everything not visited is dead. It works on instruction starts only: a jump into the
## middle of an instruction reaches nothing, as the VM would execute different bytes
## there than this linear decoding shows. tools/import/foe_text.py has the twin.
static func reachable(decoded: Array[Dictionary], roots: Array) -> Dictionary:
	var index_of: Dictionary = {}
	for i in decoded.size():
		index_of[decoded[i]["at"]] = i
	var todo: Array[int] = []
	for at in roots:
		if index_of.has(int(at)):
			todo.append(index_of[int(at)])
	var seen: Dictionary = {}
	while not todo.is_empty():
		var i: int = todo.pop_back()
		if i >= decoded.size() or seen.has(i):
			continue
		seen[i] = true
		var item := decoded[i]
		var opcode: int = item["op"]
		if opcode < 0 or opcode == FoeOps.Op.RET:
			continue                                        # a byte that faults / the end of a path
		if _has_target(opcode):                             # Jump_To, Call_Subroutine, Loop_Counter*
			var target: int = item["at"] + 1 + FoeOps.OPERAND_COUNT[opcode] + _i16(item["operands"], 0)
			if index_of.has(target):
				todo.append(index_of[target])
		if opcode == FoeOps.Op.JMP:
			continue                                        # never falls through
		todo.append(i + 1)
		if _is_conditional(opcode):
			todo.append(i + 2)                              # the skip
	var alive: Dictionary = {}
	for i in seen:
		alive[decoded[i]["at"]] = true
	return alive


## If_Sub_X_Greater .. If_Random_Greater and If_Flag: they skip the next instruction
## when the condition is false.
static func _is_conditional(opcode: int) -> bool:
	return (opcode >= FoeOps.Op.IF_SUBX_GT and opcode <= FoeOps.Op.IF_RAND_GT) or opcode == FoeOps.Op.IF_SEM


## The offsets of the instructions of `script` (first byte at buffer offset `base`) that
## can never execute, in order, given the creatures' entry offsets (every start / hit /
## ink offset). Works on any script bytes: the disassembler uses it, and so does the Foe
## Script editor on the bytes it just assembled from a hand-written text
## (`dead_code_warnings`). The analysis itself is `reachable`. Twin: foe_text.unreachable_offsets.
static func unreachable_offsets(script: PackedByteArray, base: int, entry_offsets: Array) -> Array[int]:
	var decoded := decode(script, base)
	var alive := reachable(decoded, entry_offsets)
	var dead: Array[int] = []
	for item in decoded:
		if not alive.has(item["at"]):
			dead.append(item["at"])
	return dead


## The runs of unreachable instructions, each as [offset of the first, offset just after
## the last].
##
## A run is consecutive dead instructions without a label between them. A label here is a
## place something jumps to (an entry offset or the target of a jump / call / loop; a name
## a designer merely gave to a place, or a heading in the middle of a block, is no reason
## to split), and the instructions after such a label are a new run. Twin: foe_text.dead_runs.
static func dead_runs(script: PackedByteArray, base: int, entry_offsets: Array) -> Array:
	var decoded := decode(script, base)
	var dead: Dictionary = {}
	for at in unreachable_offsets(script, base, entry_offsets):
		dead[at] = true
	var splits: Dictionary = {}
	for at in entry_offsets:
		splits[int(at)] = true
	for at in jump_targets(decoded):
		splits[at] = true
	var end := base + script.size()
	var runs: Array = []
	var current: Array = []
	for i in decoded.size():
		var at: int = decoded[i]["at"]
		var stop: int = decoded[i + 1]["at"] if i + 1 < decoded.size() else end
		if not dead.has(at):
			current = []                                    # a live instruction closes the run
		elif current.is_empty() or splits.has(at):
			current = [at, stop]                            # a new run (a label starts a new one even inside a run)
			runs.append(current)
		else:
			current[1] = stop
	return runs


## The padding inside one dead run (`dead_runs`, [first, stop]): an Array of [offset,
## offset just after] for each stretch of zero bytes that NOTHING FALLS INTO. Twin:
## foe_text._run_padding.
##
## A stretch of zero bytes (Wait_Next_Tick instructions) is padding when it starts the
## run, or follows a Return or a Jump_To: those never go on to the next instruction. A
## stretch after any other instruction (in an unused animation, a pause between two
## pictures) is entered by falling through from the code before it, so it is part of that
## code and stays Wait_Next_Tick. A run of only zero bytes is one stretch of padding.
static func _run_padding(decoded: Array[Dictionary], run: Array) -> Array:
	var inside: Array[Dictionary] = []
	for item in decoded:
		if item["at"] >= run[0] and item["at"] < run[1]:
			inside.append(item)
	var spans: Array = []
	var i := 0
	while i < inside.size():
		if inside[i]["op"] != 0:
			i += 1
			continue
		var j := i
		while j < inside.size() and inside[j]["op"] == 0:
			j += 1
		if i == 0 or inside[i - 1]["op"] == FoeOps.Op.JMP or inside[i - 1]["op"] == FoeOps.Op.RET:
			spans.append([inside[i]["at"], inside[j]["at"] if j < inside.size() else run[1]])
		i = j
	return spans


## Where the disassembler writes `Padding N`: offset of the first zero byte -> N, in order.
## `entry_offsets` are the creatures' entry points, as for `dead_runs`.
##
## Padding is the unreachable zero bytes that nothing falls into, found per dead run
## (`_run_padding`): a run of only zero bytes is ONE span (N = its length); in a run with
## code, the zero bytes that start it or follow a Return / Jump_To are spans (the filler
## the original tool left between its unused scripts), while a pause inside an unused
## animation stays Wait_Next_Tick. A reachable zero byte is never padding: a creature
## runs it as Wait_Next_Tick. Twin: foe_text.padding_spans.
static func padding_spans(script: PackedByteArray, base: int, entry_offsets: Array) -> Dictionary:
	var decoded := decode(script, base)
	var spans: Dictionary = {}
	for run in dead_runs(script, base, entry_offsets):
		for edge in _run_padding(decoded, run):
			var at: int = edge[0]
			while at < edge[1]:                             # (a span longer than PADDING_MAX needs more than one line)
				var size := mini(edge[1] - at, FoeOps.PADDING_MAX)
				spans[at] = size
				at += size
	return spans


## `spans` with every span cut in two at an offset of `cuts` that lies inside it, so that a
## stored label or comment at that offset still has a line of its own. Twin: foe_text._split_at.
static func _split_at(spans: Dictionary, cuts: Array) -> Dictionary:
	var result: Dictionary = {}
	for at in spans:
		var points: Array = [at]
		var inner: Array = []
		for cut in cuts:
			if int(cut) > at and int(cut) < at + spans[at]:
				inner.append(int(cut))
		inner.sort()
		points.append_array(inner)
		points.append(at + spans[at])
		for k in points.size() - 1:
			result[points[k]] = points[k + 1] - points[k]
	return result


## The generated comment before each run of unreachable code: offset of the run's first
## instruction that is not padding -> [comment line].
##
## The runs are those of `dead_runs`, with the `entries` offsets as the creatures' entry
## points. A run made only of zero bytes is just a `Padding N` line (`padding_spans`) and
## gets no comment; any other run is "nothing jumps to them" (scripts the original
## authoring tool left behind). The comment is part of the plain text, so the annotation
## store holds it only when a designer replaced or removed it.
## Twin: foe_text.unexecuted_notes.
static func unexecuted_notes(script: PackedByteArray, base: int, entries: Dictionary) -> Dictionary:
	var decoded := decode(script, base)
	var notes: Dictionary = {}
	for run in dead_runs(script, base, entries.values()):
		var padded: Dictionary = {}
		for edge in _run_padding(decoded, run):
			for at in range(edge[0], edge[1]):
				padded[at] = true
		for item in decoded:
			if item["at"] >= run[0] and item["at"] < run[1] and not padded.has(item["at"]):
				notes[item["at"]] = [UNEXECUTED_UNUSED]
				break
	return notes


## Warnings for a hand-written text, as "line N: ..." messages like the assembler's
## errors but meant to be shown apart from them: neither is a mistake the assembler must
## refuse (the original sectors keep their unused code, so that the text assembles to the
## original bytes), only something a script author probably did not intend. In line order:
##   - CODE NO CREATURE CAN REACH, one warning per run (see `dead_runs`), such as a
##     forgotten `Jump_To`: "never executed". `Padding` lines do not count as code: a run of
##     only Padding is fine, and in a run with code the warning is for the first line that
##     is not Padding. When everything in the run besides Padding is Wait_Next_Tick, the
##     message adds that `Padding N` is the way to write filler. A run whose first line of
##     code comes right after a `; The following instructions are not executed ...` comment
##     line (blank lines, label lines and Padding lines in between do not matter) is not warned about:
##     that comment, which the disassembler writes, says the author knows.
##   - A `Padding` THAT A CREATURE REACHES (found by `reachable`, not by looking at what
##     comes before it): its zero bytes would run as Wait_Next_Tick. No comment silences
##     this; the author chose Padding to say "never runs".
## `result` is `assemble(source, ...)` of `source`; `entry_labels` are the labels the
## creatures start (start / hit / ink) at (`sector_entry_labels`). No warnings when the
## text has errors, when there are no entry labels, or when one of them is not a label of
## the text (the sector reports that itself; with an entry missing, code that only it
## reaches would be flagged wrongly).
static func dead_code_warnings(source: String, result: Result, entry_labels: Array) -> Array[String]:
	var warnings: Array[String] = []
	if not result.ok():
		return warnings
	var entry_offsets: Array = []
	for label in entry_labels:
		if not result.labels.has(label):
			return warnings
		entry_offsets.append(result.labels[label])
	if entry_offsets.is_empty():
		return warnings
	var lines := source.split("\n")
	var decoded := decode(result.bytes, result.base)
	var alive := reachable(decoded, entry_offsets)
	var found: Array[Dictionary] = []                       # {"line", "text"}
	# bytes that a Padding line wrote: not code
	var padded: Dictionary = {}
	for at in result.paddings:
		var count: int = result.paddings[at]["count"]
		for k in count:
			padded[at + k] = true
		if alive.has(at):
			found.append({"line": result.paddings[at]["line"], "text": "Padding is reached and would run as Wait_Next_Tick (%d tick%s of doing nothing); end the code above it with Jump_To or Return, or write Wait_Next_Tick if a pause is meant" % [count, "" if count == 1 else "s"]})
	for run in dead_runs(result.bytes, result.base, entry_offsets):
		var first_line := 0
		var ticks := 0
		var only_waits := true
		for item in decoded:
			if item["at"] < run[0] or item["at"] >= run[1] or padded.has(item["at"]):
				continue
			if first_line == 0:
				first_line = result.instruction_lines.get(item["at"], 0)
			ticks += 1
			only_waits = only_waits and item["op"] == 0
		if first_line == 0 or _has_not_executed_comment(lines, first_line - 1):
			continue
		var text := "never executed (no creature start/hit/ink entry or jump reaches it)"
		if only_waits:
			text += "; if it is only filler, write Padding %d instead" % ticks
		found.append({"line": first_line, "text": text})
	found.sort_custom(func(a, b): return a["line"] < b["line"])
	for item in found:
		warnings.append("line %d: %s" % [item["line"], item["text"]])
	return warnings


## The labels the creatures of `sector` start at: every start, hit and ink label.
static func sector_entry_labels(sector: SectorData) -> Array:
	var labels: Array = []
	for foe in sector.foes:
		labels.append_array([foe.start_label, foe.hit_label, foe.ink_label])
	return labels


## Does the first line above `lines[index]` that is neither blank, nor a label line, nor a
## `Padding` line hold the "not executed" comment?
static func _has_not_executed_comment(lines: PackedStringArray, index: int) -> bool:
	var n := index - 1
	while n >= 0:
		var text := lines[n].strip_edges()
		var first_word := text.replace("\t", " ").split(" ", false)[0].to_lower() if not text.is_empty() else ""
		if text.is_empty() or (text.ends_with(":") and is_identifier(text.trim_suffix(":"))) or first_word == FoeOps.op_name(FoeOps.PADDING).to_lower():
			n -= 1
			continue
		return text.begins_with(UNEXECUTED_COMMENT_PREFIX)
	return false


## The buffer offset every jump / call / loop instruction of `decoded` goes to.
static func jump_targets(decoded: Array[Dictionary]) -> Array[int]:
	var targets: Array[int] = []
	for item in decoded:
		var opcode: int = item["op"]
		if opcode >= 0 and _has_target(opcode):
			targets.append(item["at"] + 1 + FoeOps.OPERAND_COUNT[opcode] + _i16(item["operands"], 0))
	return targets


## The generated label of every place that has one: the entry names, then
## "loc_<offset>" for the other jump targets. What the plain text prints; the
## annotation store keeps only the names that differ from these.
static func generated_names(script: PackedByteArray, base: int, entries: Dictionary) -> Dictionary:
	var names := label_names(entries)
	for target in jump_targets(decode(script, base)):
		if not names.has(target):
			names[target] = "loc_%d" % target
	return names


## One instruction in text form ("Jump_To loc_52"), jump targets named by `names`
## (offset -> label; an unnamed target is written "loc_<offset>").
static func format_instruction(opcode: int, operands: PackedByteArray, at: int, names: Dictionary, symbols: FoeNames = null) -> String:
	return _format(opcode, operands, at, names, symbols)


## The operand values of a decoded instruction, in the form `parse_operands` gives for its words: the label name of
## a jump target (`names`: offset -> label, an unnamed one "loc_<offset>"), a signed number for an I8, the stored
## byte (self+N encoded) for a creature, the plain value for everything else (a mirrored picture includes bit 7).
## Two spellings of one instruction have equal values.
static func operand_values(opcode: int, operands: PackedByteArray, at: int, names: Dictionary) -> Array:
	var values: Array = []
	var position := 0
	for part in FoeOps.operands(opcode):
		match part["kind"]:
			FoeOps.Kind.LABEL:
				var target := at + 1 + FoeOps.OPERAND_COUNT[opcode] + _i16(operands, position)
				values.append(str(names.get(target, "loc_%d" % target)))
			FoeOps.Kind.U16:
				values.append(operands[position] | (operands[position + 1] << 8))
			FoeOps.Kind.I8:
				var v := operands[position]
				values.append(v - 256 if v >= 128 else v)
			_:
				values.append(operands[position])
		position += FoeOps.kind_width(part["kind"])
	return values


## The values of the operand words of one instruction line (`words` after the instruction name), exactly as
## `assemble` reads them: {"values": Array (see `operand_values`), "errors": Array[String] (without a line number),
## "complete": the number of operands was right}. A label is returned as the word. Lets a tool compare a hand-written
## line with the original instruction whatever spelling it uses (a number, a name, `mirrored`).
static func parse_operands(opcode: int, words: Array, symbols: FoeNames = null) -> Dictionary:
	var problems: Array[Dictionary] = []
	var item := {"line": 0, "op": opcode, "values": [], "complete": false}
	_check_operands(problems, item, PackedStringArray(words), symbols if symbols != null else FoeNames.new())
	var errors: Array[String] = []
	for problem in problems:
		errors.append(problem["text"])
	return {"values": item["values"], "errors": errors, "complete": item["complete"]}


## offset -> the label printed there: the first name `entries` lists for an offset,
## replaced or extended by the names in `annotations["labels"]`. (Jump targets
## without a name get "loc_<offset>" later, in `disassemble`.)
static func label_names(entries: Dictionary, annotations: Dictionary = {}) -> Dictionary:
	var names: Dictionary = {}
	for label in entries:
		var offset := int(entries[label])
		if not names.has(offset):
			names[offset] = str(label)
	var renamed: Dictionary = annotations.get("labels", {})
	for offset in renamed:
		names[int(offset)] = str(renamed[offset])
	return names


## The label each creature's start / hit / ink fields must name, as [start, hit, ink]
## per creature: the one printed at that offset (see `label_names`). `offsets` has one
## [pc, script_hit, script_ink] per creature, like `entry_names` takes.
static func entry_labels(offsets: Array, annotations: Dictionary = {}) -> Array:
	var names := label_names(entry_names(offsets), annotations)
	var result: Array = []
	for item in offsets:
		result.append([names[item[0]], names[item[1]], names[item[2]]])
	return result


## Text for a sector's script, naming each creature's entry points
## foe<i>_start (pc), foe<i>_hit (script_hit) and foe<i>_ink (script_ink); see `entry_names`.
static func disassemble_sector(sector: SectorData) -> String:
	var offsets: Array = []
	for foe in sector.foes:
		offsets.append([foe.pc, foe.script_hit, foe.script_ink])
	return disassemble(sector.foe_bytecode, sector.foe_script_base, entry_names(offsets), {}, FoeNames.for_sector(sector))


## The label names for creatures' entry points: foe<i>_start, foe<i>_hit, foe<i>_ink,
## in creature order. `offsets` has one [pc, script_hit, script_ink] per creature.
## Returns label -> offset in that order, which `disassemble` takes as `entries`.
static func entry_names(offsets: Array) -> Dictionary:
	var entries: Dictionary = {}
	for i in offsets.size():
		entries["foe%d_start" % i] = offsets[i][0]
		entries["foe%d_hit" % i] = offsets[i][1]
		entries["foe%d_ink" % i] = offsets[i][2]
	return entries


## One instruction for a debug display: "<nearest label before pc>+<bytes after it>:
## <Mnemonic> <operands>", e.g. "foe3_start+7: Loop_Counter0_Back_To loc_1204 6".
## `labels` is name -> buffer offset (SectorData.foe_labels). Without any label at or
## before `pc` the plain offset is printed instead.
static func instruction_text(script: PackedByteArray, base: int, labels: Dictionary, pc: int, symbols: FoeNames = null) -> String:
	var names: Dictionary = {}                 # buffer offset -> label
	var nearest := -1
	for label in labels:
		var offset: int = labels[label]
		if not names.has(offset):
			names[offset] = label
		if offset <= pc and offset > nearest:
			nearest = offset
	var where := "%d" % pc if nearest < 0 else "%s+%d" % [names[nearest], pc - nearest]
	var index := pc - base
	if index < 0 or index >= script.size():
		return "%s: <outside the script>" % where
	var opcode := script[index]
	if not FoeOps.is_valid(opcode):
		return "%s: ??%d" % [where, opcode]
	var count: int = FoeOps.OPERAND_COUNT[opcode]
	if index + 1 + count > script.size():
		return "%s: %s <cut off>" % [where, FoeOps.MNEMONIC[opcode]]
	return "%s: %s" % [where, _format(opcode, script.slice(index + 1, index + 1 + count), pc, names, symbols)]


## Appends what belongs to the position `offset`: the label line (a blank line first
## by default, or the stored "label_above" lines) when there is a label here that is
## not placed yet, then the "above" lines (the stored ones, or `default_above`, the
## generated comment of `unexecuted_notes`, when the note has none), then `text` (an
## instruction; empty at the very end) with its "inline" comment.
static func _emit_position(lines: Array[String], names: Dictionary, placed: Dictionary, note: Dictionary, offset: int, text: String, default_above: Array) -> void:
	if names.has(offset) and not placed.has(offset):
		placed[offset] = true
		if note.has("label_above"):
			for line in note["label_above"]:
				lines.append(str(line))
		elif not lines.is_empty():
			lines.append("")
		lines.append("%s:%s" % [names[offset], inline_text(note.get("label_inline", ""))])
	for line in note.get("above", default_above):
		lines.append(str(line))
	if not text.is_empty():
		lines.append("    " + text + inline_text(note.get("inline", "")))


## What follows the code on a line for a stored end-of-line comment: two spaces, unless
## the stored text brings its own leading spaces.
static func inline_text(tail: String) -> String:
	if tail.is_empty():
		return ""
	return tail if tail[0] == " " or tail[0] == "\t" else "  " + tail


static func _format(opcode: int, operands: PackedByteArray, at: int, names: Dictionary, symbols: FoeNames = null) -> String:
	var text: String = FoeOps.MNEMONIC[opcode]
	var position := 0
	for part in FoeOps.operands(opcode):
		match part["kind"]:
			FoeOps.Kind.LABEL:
				var next := at + 1 + FoeOps.OPERAND_COUNT[opcode]
				var target := next + _i16(operands, position)
				text += " " + str(names.get(target, "loc_%d" % target))
			FoeOps.Kind.U16:
				text += " %d" % (operands[position] | (operands[position + 1] << 8))
			FoeOps.Kind.I8:
				var v := operands[position]
				text += " %d" % (v - 256 if v >= 128 else v)
			FoeOps.Kind.FOE:
				text += " " + _foe_text(operands[position], symbols)
			_:
				text += " " + _operand_text(part, operands[position], symbols)
		position += FoeOps.kind_width(part["kind"])
	return text


## A one-byte operand as text: its real name when `symbols` has one, else the number; an operand that can be mirrored
## (bit 7) is the picture without the bit, then `mirrored`.
static func _operand_text(part: Dictionary, value: int, symbols: FoeNames) -> String:
	var mirrored: bool = part.get("mirror", false) and value >= 128
	var plain := value & 0x7F if mirrored else value
	var shown := symbols.name_for(part["kind"], plain) if symbols != null else ""
	var text := shown if not shown.is_empty() else str(plain)
	return text + " " + FoeOps.MIRROR_WORD if mirrored else text


## 3 -> "3" (or its name); 0x81 -> "self+1"; 0xFF -> "self-1"; 0x80 -> "self".
static func _foe_text(operand: int, symbols: FoeNames = null) -> String:
	if operand & 0x80 == 0:
		var shown := symbols.name_for(FoeOps.Kind.FOE, operand) if symbols != null else ""
		return shown if not shown.is_empty() else str(operand)
	var offset := operand & 0x7F
	if offset >= 64:
		offset -= 128
	if offset == 0:
		return "self"
	return "self%+d" % offset


static func _i16(bytes: PackedByteArray, at: int) -> int:
	var v := bytes[at] | (bytes[at + 1] << 8)
	return v - 65536 if v >= 32768 else v


# =============================================================================
# Assembler
# =============================================================================

## Translates `source` into bytes. `base` is the buffer offset of the first byte
## (SectorData.foe_script_base); the returned label offsets are buffer offsets too.
## Every problem found is reported, not just the first. `symbols` (FoeNames) says which names the operands may use
## in the sector the script belongs to; without it only the global names and the `common` ones work.
static func assemble(source: String, base: int, symbols: FoeNames = null) -> Result:
	if symbols == null:
		symbols = FoeNames.new()
	var result := Result.new()
	result.base = base
	var problems: Array[Dictionary] = []       # {line, seq, text}
	var first_line_of: Dictionary = {}          # label -> line, for the duplicate message
	var items: Array[Dictionary] = []
	var size := 0
	var layout_reliable := true

	# --- pass 1: measure. Each instruction's size depends only on its name, so we
	# can give every label its address without knowing where the jumps go. ---
	var lines := source.split("\n")
	for n in lines.size():
		var line_no := n + 1
		var text := lines[n]
		var semicolon := text.find(";")
		if semicolon >= 0:
			text = text.substr(0, semicolon)
		text = text.replace("\t", " ").replace("\r", " ").strip_edges()
		if text.is_empty():
			continue

		if text.ends_with(":") and is_identifier(text.trim_suffix(":")):
			var label := text.trim_suffix(":")
			if first_line_of.has(label):
				_problem(problems, line_no, "duplicate label '%s' (first defined on line %d)" % [label, first_line_of[label]])
			else:
				first_line_of[label] = line_no
				result.labels[label] = base + size
			continue

		var words := text.split(" ", false)
		var opcode := FoeOps.op_from_mnemonic(words[0])
		if opcode < 0:
			layout_reliable = false           # we cannot know how many bytes this line is
			_problem(problems, line_no, _unknown_instruction(words[0]))
			continue
		if FoeOps.is_pseudo(opcode):          # Padding: a directive, `count` zero bytes and no opcode
			var count := _padding_count(problems, line_no, words)
			result.instruction_lines[base + size] = line_no
			if count < 0:
				layout_reliable = false       # the size of this line is unknown
				continue
			result.paddings[base + size] = {"line": line_no, "count": count}
			items.append({"line": line_no, "op": opcode, "at": base + size, "count": count})
			size += count
			continue
		var item := {"line": line_no, "op": opcode, "at": base + size, "values": [], "complete": false}
		result.instruction_lines[base + size] = line_no
		_check_operands(problems, item, words.slice(1), symbols)
		items.append(item)
		size += 1 + FoeOps.OPERAND_COUNT[opcode]

	# --- pass 2: now every label has an address, so write the bytes. ---
	var bytes := PackedByteArray()
	for item in items:
		if FoeOps.is_pseudo(item["op"]):
			bytes.resize(bytes.size() + item["count"])        # `count` zero bytes
			continue
		bytes.append(item["op"])
		if not item["complete"]:
			# Wrong operand count: reported already; keep the length right and move on.
			bytes.resize(bytes.size() + FoeOps.OPERAND_COUNT[item["op"]])
			continue
		var next: int = item["at"] + 1 + FoeOps.OPERAND_COUNT[item["op"]]
		var spec := FoeOps.operands(item["op"])
		for k in spec.size():
			var value: Variant = item["values"][k]
			match spec[k]["kind"]:
				FoeOps.Kind.LABEL:
					var label: String = value
					var offset := 0
					if label.is_empty():
						pass                   # not a label at all: already reported in pass 1
					elif not result.labels.has(label):
						_problem(problems, item["line"], "unknown label '%s'" % label)
					else:
						offset = result.labels[label] - next
						if layout_reliable and (offset < FoeOps.JUMP_MIN or offset > FoeOps.JUMP_MAX):
							_problem(problems, item["line"], "%s to '%s' is %d bytes away; a jump can only reach %d..%d bytes" % [FoeOps.MNEMONIC[item["op"]], label, offset, FoeOps.JUMP_MIN, FoeOps.JUMP_MAX])
							offset = 0
					bytes.append(offset & 0xFF)
					bytes.append((offset >> 8) & 0xFF)
				FoeOps.Kind.U16:
					bytes.append(value & 0xFF)
					bytes.append((value >> 8) & 0xFF)
				_:
					bytes.append(value & 0xFF)       # I8 and FOE are already encoded as 0..255

	problems.sort_custom(func(a, b): return a["line"] < b["line"] or (a["line"] == b["line"] and a["seq"] < b["seq"]))
	for problem in problems:
		result.errors.append("line %d: %s" % [problem["line"], problem["text"]])
	if result.errors.is_empty():
		result.bytes = bytes
	return result


## The count of a `Padding` line (`words` is the whole line split at spaces): 1 for a bare
## `Padding`, else the number in 1..FoeOps.PADDING_MAX. Reports a problem and returns -1 when
## the line is not valid.
static func _padding_count(problems: Array[Dictionary], line_no: int, words: PackedStringArray) -> int:
	var name := FoeOps.op_name(FoeOps.PADDING)
	if words.size() == 1:
		return 1
	if words.size() > 2:
		_problem(problems, line_no, "%s takes at most 1 operand (count), got %d" % [name, words.size() - 1])
		return -1
	var kind: int = FoeOps.operands(FoeOps.PADDING)[0]["kind"]
	var limits := FoeOps.kind_range(kind)
	var word := words[1]
	if word.is_valid_int() and word.to_int() >= limits.x and word.to_int() <= limits.y:
		return word.to_int()
	var got := str(word.to_int()) if word.is_valid_int() else "'%s'" % word
	_problem(problems, line_no, "%s count must be %s, got %s" % [name, FoeOps.range_text(kind), got])
	return -1


## Checks the operand words of one instruction and stores their values in item["values"]
## (a label name for a jump target, an integer otherwise). A word `mirrored` belongs to the operand before it:
## `Set_Frame eel_swim_1 mirrored` has one operand.
static func _check_operands(problems: Array[Dictionary], item: Dictionary, words: PackedStringArray, symbols: FoeNames) -> void:
	var opcode: int = item["op"]
	var name: String = FoeOps.MNEMONIC[opcode]
	var spec := FoeOps.operands(opcode)
	var groups: Array[Dictionary] = []                      # {"word", "mirrored"}
	for word in words:
		if word.to_lower() == FoeOps.MIRROR_WORD and not groups.is_empty() and not groups[-1]["mirrored"]:
			groups[-1]["mirrored"] = true
		else:
			groups.append({"word": word, "mirrored": false})
	if groups.size() != spec.size():
		var wanted: Array[String] = []
		for k in spec.size():
			wanted.append(_operand_word(spec, k))
		var plural := "operand" if spec.size() == 1 else "operands"
		var message := "%s takes no operands, got %d" % [name, groups.size()]
		if not spec.is_empty():
			message = "%s needs %d %s (%s), got %d" % [name, spec.size(), plural, " ".join(wanted), groups.size()]
		_problem(problems, item["line"], message)
		return
	item["complete"] = true
	for k in spec.size():
		var word: String = groups[k]["word"]
		var label := _operand_word(spec, k)
		var kind: int = spec[k]["kind"]
		var value := 0
		if groups[k]["mirrored"] and not spec[k].get("mirror", false):
			_problem(problems, item["line"], "%s %s takes no '%s' (it goes after the picture that is shown)" % [name, label, FoeOps.MIRROR_WORD])
		match kind:
			FoeOps.Kind.LABEL:
				if is_identifier(word):
					item["values"].append(word)
				else:
					_problem(problems, item["line"], "%s needs a label, got '%s'" % [name, word])
					item["values"].append("")
				continue
			FoeOps.Kind.FOE:
				value = FoeOps.parse_foe(word)
				if value < 0 and is_identifier(word):
					value = symbols.index_for(kind, word)
					if value < 0:
						_problem(problems, item["line"], "%s %s: %s" % [name, label, symbols.explain(kind, word)])
				elif value < 0:
					_problem(problems, item["line"], "%s %s must be %s, got '%s'" % [name, label, FoeOps.range_text(kind), word])
				value = maxi(value, 0)
			_:
				value = _number_or_name(problems, item, name, label, word, spec[k], symbols)
				if groups[k]["mirrored"] and spec[k].get("mirror", false):
					if value >= 128:
						_problem(problems, item["line"], "%s %s: '%s' goes after a picture 0..127, but %d already has bit 7 (the mirror) set" % [name, label, FoeOps.MIRROR_WORD, value])
					value |= 128
		item["values"].append(value)


## What the error messages call operand `k`: its name from the table, except that a
## lone plain byte (Play_Sound, Set_Frame, the If_ tests, the flags) is just "operand".
static func _operand_word(spec: Array, k: int) -> String:
	if spec.size() == 1 and [FoeOps.Kind.U8, FoeOps.Kind.SOUND, FoeOps.Kind.FRAME, FoeOps.Kind.FLAG, FoeOps.Kind.SCREEN].has(spec[0]["kind"]):
		return "operand"
	return spec[k]["name"]


## An operand that is a whole number in the range of its kind, or (for a kind that has names) a name of the sector;
## reports a problem and returns 0 otherwise. A word that looks like a name gets the registry's explanation (with
## "did you mean ..."); any other word the range message.
static func _number_or_name(problems: Array[Dictionary], item: Dictionary, name: String, label: String, word: String, operand: Dictionary, symbols: FoeNames) -> int:
	var kind: int = operand["kind"]
	if not word.is_valid_int() and is_identifier(word) and not FoeOps.name_kind(kind).is_empty():
		var found := symbols.index_for(kind, word)
		if found >= 0:
			return found
		_problem(problems, item["line"], "%s %s: %s" % [name, label, symbols.explain(kind, word)])
		return 0
	return _int_in_range(problems, item, name, label, word, kind)


## An integer word that must lie in the range of `kind`; reports a problem and returns 0 otherwise.
static func _int_in_range(problems: Array[Dictionary], item: Dictionary, name: String, label: String, word: String, kind: int) -> int:
	var limits := FoeOps.kind_range(kind)
	if word.is_valid_int() and word.to_int() >= limits.x and word.to_int() <= limits.y:
		return word.to_int()
	var got := str(word.to_int()) if word.is_valid_int() else "'%s'" % word
	_problem(problems, item["line"], "%s %s must be %s, got %s" % [name, label, FoeOps.range_text(kind), got])
	return 0


static func _unknown_instruction(word: String) -> String:
	var text := "unknown instruction '%s'" % word
	var short := FoeOps.Op.keys().find(word.to_upper())
	if short >= 0:
		text += " (did you mean %s?)" % FoeOps.MNEMONIC[short]
	elif word.ends_with(":"):
		text += " (a label goes on a line of its own)"
	return text


static func _problem(problems: Array[Dictionary], line: int, text: String) -> void:
	problems.append({"line": line, "seq": problems.size(), "text": text})


## [A-Za-z_][A-Za-z0-9_]*: the rule for label names.
static func is_identifier(word: String) -> bool:
	if word.is_empty():
		return false
	for i in word.length():
		var c := word.unicode_at(i)
		var letter := (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
		var digit := c >= 48 and c <= 57
		if not (letter or (digit and i > 0)):
			return false
	return true


# =============================================================================
# Operand layout, shared by both directions: FoeOps.OPERANDS
# =============================================================================

## Does this instruction have a jump target in its first two operand bytes?
static func _has_target(opcode: int) -> bool:
	var spec := FoeOps.operands(opcode)
	return not spec.is_empty() and spec[0]["kind"] == FoeOps.Kind.LABEL
