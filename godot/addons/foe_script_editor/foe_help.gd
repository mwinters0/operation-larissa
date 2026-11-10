@tool
class_name FoeHelp
extends RefCounted
## The texts the Foe Script editor shows to help the person typing: the tooltip over a
## word, the signature hint while typing operands, and the list of completions. All of
## them are built from FoeOps (the instruction table) and FoeLineInfo (which word is where),
## as plain functions on Strings and numbers, so tests can check every text directly.
## FoeCodeEdit is the CodeEdit that asks for them and shows them.
##
## Teaches: one table, many views. Nothing here knows what any instruction does; it
## reads FoeOps.OPERANDS and FoeOps.SUMMARY (and FoeOps.PSEUDO for the `Padding`
## pseudo-instruction), so a new instruction or a corrected range shows up in the
## assembler, the tooltips, the hints and the completions at once.
## The same table answers "is this value valid?" (the assembler) and "what is this
## value?" (the tooltip).

## What a completion option stands for.
enum Candidate { MNEMONIC, LABEL, SELF, NAME, MIRROR }

## The kinds of operand that may be written with a name from the registry (FoeNames).
const NAMED_KINDS := [FoeOps.Kind.SOUND, FoeOps.Kind.FRAME, FoeOps.Kind.FLAG, FoeOps.Kind.SCREEN]

## Where the manual is.
const MANUAL := "docs/create/FOE_SCRIPTING.md"


# =============================================================================
# Tooltip
# =============================================================================

## The tooltip for the word under the mouse at `line` (0-based), `column` of `lines`; ""
## when there is nothing to say (blank space, a comment).
static func tooltip(lines: PackedStringArray, line: int, column: int, symbols: FoeNames = null) -> String:
	if line < 0 or line >= lines.size():
		return ""
	var spot := FoeLineInfo.locate(lines[line], column)
	match spot.part:
		FoeLineInfo.Part.MNEMONIC:
			return mnemonic_tooltip(spot.opcode)
		FoeLineInfo.Part.UNKNOWN_WORD:
			return "'%s' is not an instruction. The names are listed in %s." % [spot.token.text, MANUAL]
		FoeLineInfo.Part.LABEL_DEFINITION:
			return label_tooltip(lines, spot.token.text.trim_suffix(":"), line, true)
		FoeLineInfo.Part.OPERAND:
			return operand_tooltip(lines, line, spot, symbols)
	return ""


## Over an instruction name: the signature, what it does, and each operand.
static func mnemonic_tooltip(opcode: int) -> String:
	if not FoeOps.is_valid(opcode) and not FoeOps.is_pseudo(opcode):
		return ""
	var parts: Array[String] = [FoeOps.signature(opcode), FoeOps.summary(opcode)]
	var list := FoeOps.operands(opcode)
	if list.is_empty():
		parts.append("No operands.")
	else:
		parts.append("")
		for operand in list:
			var optional := ", optional" if operand.get("optional", false) else ""
			parts.append("%s (%s, %s%s): %s" % [operand["name"], FoeOps.kind_name(operand["kind"]), FoeOps.range_text(operand["kind"]), optional, operand["meaning"]])
	return "\n".join(parts)


## Over an operand word: which operand it is, what it means, and whether its value is valid.
static func operand_tooltip(lines: PackedStringArray, line: int, spot: FoeLineInfo.Spot, symbols: FoeNames = null) -> String:
	if symbols == null:
		symbols = FoeNames.new()
	var word := spot.token.text
	if spot.opcode < 0:
		return ""                       # the instruction name is wrong; the highlighter says so
	var list := FoeOps.operands(spot.opcode)
	if spot.operand >= list.size():
		return "%s takes %s, so this word is one too many." % [FoeOps.op_name(spot.opcode), _count_text(list.size())]
	var operand: Dictionary = list[spot.operand]
	var kind: int = operand["kind"]
	var text := "%s: operand %d of %s\n%s\n%s (%s)" % [operand["name"], spot.operand + 1, FoeOps.signature(spot.opcode), operand["meaning"], FoeOps.kind_name(kind), FoeOps.range_text(kind)]
	match kind:
		FoeOps.Kind.LABEL:
			if FoeAsm.is_identifier(word):
				return text + "\n\n" + label_tooltip(lines, word, line, false)
			return text + "\n\n'%s' is not a label name: use letters, digits and _, not starting with a digit." % word
		FoeOps.Kind.FOE:
			return text + "\n\n" + foe_text(word, symbols)
	if spot.on_mirror_word:
		return "%s: flips the picture left-right. It is stored as bit 7 of the picture byte, which is the same as adding 128 to the picture number (%s)." % [FoeOps.MIRROR_WORD, operand["name"]]
	if NAMED_KINDS.has(kind):
		return text + "\n\n" + named_value_text(operand, word, symbols)
	return text + "\n\n" + value_text(operand, word)


## What a creature word means: `self`, `self+2`, `self-1`, or a number.
static func foe_text(word: String, symbols: FoeNames = null) -> String:
	var encoded := FoeOps.parse_foe(word)
	if encoded < 0 and symbols != null and FoeAsm.is_identifier(word):
		var number := symbols.index_for(FoeOps.Kind.FOE, word)
		if number >= 0:
			return "%s: creature number %d, its position in the sector's foe list (the first foe is 0)." % [name_with_number(word, number), number]
		return symbols.explain(FoeOps.Kind.FOE, word) + "."
	if encoded < 0:
		return "'%s' is not valid: use a creature number 0..%d, or self, self+N, self-N with N from %d to %d." % [word, FoeOps.FOE_MAX, FoeOps.SELF_MIN, FoeOps.SELF_MAX]
	if encoded < 0x80:
		var real := symbols.name_for(FoeOps.Kind.FOE, encoded) if symbols != null else ""
		var named := "" if real.is_empty() else " Its name: %s." % name_with_number(real, encoded)
		return "Creature number %d: its position in the sector's foe list (the first foe is 0).%s" % [encoded, named]
	var offset := encoded & 0x7F
	if offset >= 64:
		offset -= 128
	if offset == 0:
		return "self: the creature that runs this instruction."
	return "self%+d: the creature %d place%s %s the one that runs this instruction in the foe list.\nA relative name stays right when foes are inserted nearby." % [
			offset, absi(offset), "" if absi(offset) == 1 else "s", "after" if offset > 0 else "before"]


## A name with the original number beside it, for tooltips and the completion list: "lock_tick (38)". A mirrored
## picture shows both parts of its byte: "eel_swim_1 (41 + 128)". The script text itself never has the number.
static func name_with_number(name: String, number: int, mirrored := false) -> String:
	return "%s (%d%s)" % [name, number, " + 128" if mirrored else ""]


## What an operand that may be a name (a sound, a picture, a flag, a screen) says: the number's name, or the name's
## number, or why the word is neither.
static func named_value_text(operand: Dictionary, word: String, symbols: FoeNames) -> String:
	var kind: int = operand["kind"]
	var kind_text := FoeOps.kind_name(kind)
	var mirror: bool = operand.get("mirror", false)
	if word.is_valid_int():
		var text := value_text(operand, word)
		var value := word.to_int()
		var limits := FoeOps.kind_range(kind)
		if value >= limits.x and value <= limits.y:
			var mirrored := mirror and value >= 128
			var real := symbols.name_for(kind, value - 128 if mirrored else value)
			if not real.is_empty():
				text += "\nIts name: %s." % name_with_number(real, value - 128 if mirrored else value, mirrored)
		return text
	if not FoeAsm.is_identifier(word):
		return "'%s' is not a whole number or a name. Valid: %s, or a name of a %s." % [word, FoeOps.range_text(kind), kind_text]
	var number := symbols.index_for(kind, word)
	if number < 0:
		return symbols.explain(kind, word) + "."
	if symbols.name_for(kind, number) == word:
		return "%s: the %s with this name." % [name_with_number(word, number), kind_text]
	return "%s: the made-up name of %s number %d (nobody named it yet)." % [word, kind_text, number]


## What a number operand's value means, or that it is not valid for its kind.
static func value_text(operand: Dictionary, word: String) -> String:
	var kind: int = operand["kind"]
	if not word.is_valid_int():
		return "'%s' is not a whole number. Valid: %s." % [word, FoeOps.range_text(kind)]
	var value := word.to_int()
	var limits := FoeOps.kind_range(kind)
	if value < limits.x or value > limits.y:
		return "Out of range: %d is not %s." % [value, FoeOps.range_text(kind)]
	var text := "%d is valid." % value
	if kind == FoeOps.Kind.COUNT:
		text = "%d is valid: %d zero byte%s." % [value, value, "" if value == 1 else "s"]
	elif operand.get("mirror", false):
		text = "Picture bits %d, %s." % [value & 0x7F, "mirrored (bit 7 is set)" if value >= 128 else "not mirrored (write mirrored after it to flip it)"]
	elif operand.has("pixels"):
		text = "%d is valid: %d pixels." % [value, value * operand["pixels"]]
	return text


## A label, where it is defined and how often it is used. `is_definition` is true for the
## `name:` line itself.
static func label_tooltip(lines: PackedStringArray, name: String, line: int, is_definition: bool) -> String:
	var defined: Array = FoeLineInfo.label_definitions(lines).get(name, [])
	var uses: Array = FoeLineInfo.label_uses(lines).get(name, [])
	var text := "Label '%s'" % name
	if is_definition:
		text += ": defined here (line %d)" % (line + 1)
		if defined.size() > 1:
			text += " and again on line %d, which the assembler rejects" % (defined[1] + 1 if defined[0] == line else defined[0] + 1)
		text += ".\n" + _uses_text(uses)
		return text
	if defined.is_empty():
		return text + " is not defined in this file: nothing is called '%s:'." % name
	text += ": defined on line %d (%s)." % [defined[0] + 1, "above" if defined[0] < line else ("below" if defined[0] > line else "this line")]
	if defined.size() > 1:
		text += " It is defined %d times, which the assembler rejects." % defined.size()
	return text + "\n" + _uses_text(uses)


static func _uses_text(uses: Array) -> String:
	match uses.size():
		0:
			return "Nothing jumps to it (a creature's entry point may still name it)."
		1:
			return "Used once, on line %d." % (uses[0] + 1)
	return "Used %d times." % uses.size()


static func _count_text(count: int) -> String:
	return "no operands" if count == 0 else "%d operand%s" % [count, "" if count == 1 else "s"]


# =============================================================================
# Signature hint while typing
# =============================================================================

## The text for CodeEdit.set_code_hint when the caret stands at `column` of `line`: the
## instruction's signature with the operand being typed between two FoeOps.HINT_MARKs (the
## CodeEdit underlines what is between them), and under it that operand's meaning. "" when
## the caret is not at an operand: in the instruction name, in a comment, on a label line,
## after the last operand, or in an instruction without operands.
static func code_hint(line: String, column: int) -> String:
	var spot := FoeLineInfo.locate(line, column, true)
	if spot.opcode < 0 or spot.operand < 0:
		return ""
	var operand := spot.operand_info()
	if operand.is_empty():
		return ""
	return "%s\n%s (%s): %s" % [FoeOps.signature(spot.opcode, spot.operand), operand["name"], FoeOps.range_text(operand["kind"]), operand["meaning"]]


# =============================================================================
# Completion
# =============================================================================

## The completion options for the caret at `column` of line number `line`: an Array of
## Dictionaries {"type": Candidate, "name": what it is called, "insert": the text to put in,
## "summary": one line about it}. In the instruction position, instruction names; where the
## operand is a label, the labels of the file; where it is a creature, `self`.
## They are the ones whose name begins with what is typed in front of the caret, upper or
## lower case. With nothing typed yet, only `force` (the user pressed Ctrl+Space) lists
## all of them, so that typing a space never opens a menu by itself. A single option that
## is exactly what is typed is not offered: there is nothing left to complete.
static func completions(lines: PackedStringArray, line: int, column: int, force := false, symbols: FoeNames = null) -> Array[Dictionary]:
	if symbols == null:
		symbols = FoeNames.new()
	var result: Array[Dictionary] = []
	if line < 0 or line >= lines.size():
		return result
	var spot := FoeLineInfo.locate(lines[line], column, true)
	if spot.part == FoeLineInfo.Part.COMMENT or spot.label_line:
		return result
	var typed := spot.typed
	if typed.is_empty() and not force:
		return result
	if spot.at_instruction():
		for opcode in FoeOps.listed():                      # the opcodes, then the pseudo-instructions (Padding)
			var name := FoeOps.op_name(opcode)
			if name.to_lower().begins_with(typed.to_lower()):
				result.append({"type": Candidate.MNEMONIC, "name": name,
						"insert": name + (" " if not FoeOps.operands(opcode).is_empty() else ""),
						"summary": FoeOps.summary(opcode)})
	else:
		var operand := spot.operand_info()
		if spot.mirror_may_follow and FoeOps.MIRROR_WORD.begins_with(typed.to_lower()):
			result.append({"type": Candidate.MIRROR, "name": FoeOps.MIRROR_WORD, "insert": FoeOps.MIRROR_WORD,
					"display": "%s (+ 128)" % FoeOps.MIRROR_WORD, "summary": "flip the picture left-right"})
		if operand.is_empty():
			return result
		match operand["kind"]:
			FoeOps.Kind.LABEL:
				var defined := FoeLineInfo.label_definitions(lines)
				for name in defined:
					if name.to_lower().begins_with(typed.to_lower()):
						result.append({"type": Candidate.LABEL, "name": name, "insert": name,
								"summary": "label on line %d" % (defined[name][0] + 1)})
			FoeOps.Kind.FOE:
				if "self".begins_with(typed.to_lower()):
					result.append({"type": Candidate.SELF, "name": "self", "insert": "self",
							"summary": "this creature (also self+N, self-N)"})
				result.append_array(_name_candidates(symbols, FoeOps.Kind.FOE, typed))
			FoeOps.Kind.SOUND, FoeOps.Kind.FRAME, FoeOps.Kind.FLAG, FoeOps.Kind.SCREEN:
				result.append_array(_name_candidates(symbols, operand["kind"], typed))
	if result.size() == 1 and result[0]["name"] == typed:
		result.clear()
	return result


## The real names of `kind` usable here whose spelling begins with `typed`, each with its original number for the
## list ("lock_tick (38)"); what is inserted is the name alone.
static func _name_candidates(symbols: FoeNames, kind: int, typed: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var entries := symbols.entries(kind)
	for name: String in entries:
		if name.begins_with(typed.to_lower()):
			found.append({"type": Candidate.NAME, "name": name, "insert": name,
					"display": name_with_number(name, entries[name]),
					"summary": "%s %d" % [FoeOps.kind_name(kind), entries[name]]})
	return found
