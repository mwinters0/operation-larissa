@tool
class_name FoeLineInfo
extends RefCounted
## Reads one line of foe assembly the way the editor's helpers need it: "which word is at
## column N, which instruction is this, which of its operands is that word?" and "where are
## the labels?". Plain functions on Strings, so a test can check them without any editor.
##
## Teaches: separating ANALYSIS from PRESENTATION. This class only answers questions about
## text; FoeHelp turns the answers into tooltip, hint and completion texts; FoeCodeEdit
## shows them. Each layer can be tested alone. It also shows that an editor feature is
## mostly string handling: a line is a few words separated by spaces, and the caret is a
## number (the column) that falls on one of them or between two.
##
## The line format is the assembler's (FoeAsm): `; comment`, a label `name:` alone on a
## line, or an instruction name followed by operands separated by spaces.

## What the column is on.
enum Part {
	NOTHING,            ## blank space (or a blank line)
	COMMENT,            ## after a `;`
	LABEL_DEFINITION,   ## the `name:` of a label line
	MNEMONIC,           ## the instruction name, which FoeOps knows
	UNKNOWN_WORD,       ## a first word that is neither a label line nor an instruction
	OPERAND,            ## a word after the instruction name
}


## One word of a line, `start` and `end` being columns: line.substr(start, end - start).
class Token extends RefCounted:
	var text := ""
	var start := 0
	var end := 0


## The answer of `locate`.
class Spot extends RefCounted:
	var part := Part.NOTHING
	## The word at the column; null when the column is on blank space or in a comment.
	var token: Token = null
	## The opcode when the line's first word is an instruction name, else -1.
	var opcode := -1
	## Which operand (0 is the first) the word, or the blank space, belongs to; -1 when the
	## column is not after the instruction name. Can be beyond the instruction's last operand.
	var operand := -1
	## True for a line that is just `name:`.
	var label_line := false
	## True when the word before this operand is a picture that has no `mirrored` after it yet, so `mirrored`
	## may be typed here (it is not an operand of its own: it belongs to the picture).
	var mirror_may_follow := false
	## True when the word at the column is the `mirrored` of the operand before it.
	var on_mirror_word := false
	## The text of the word in front of the column ("" when the column is not in a word).
	## It is what the user has typed so far, which completion matches against.
	var typed := ""

	## Is the column where an instruction name goes (the first word of the line)?
	func at_instruction() -> bool:
		return operand < 0 and not label_line and part != Part.COMMENT

	## The operand description (a FoeOps.OPERANDS entry) the column is on; empty when none.
	func operand_info() -> Dictionary:
		var list := FoeOps.operands(opcode)
		return list[operand] if operand >= 0 and operand < list.size() else {}


## The words of the code part of a line (everything before the `;`), split at spaces,
## tabs and carriage returns like FoeAsm does.
static func tokens(line: String) -> Array[Token]:
	var result: Array[Token] = []
	var semicolon := line.find(";")
	var code := line if semicolon < 0 else line.substr(0, semicolon)
	var position := 0
	while position < code.length():
		if _is_space(code.unicode_at(position)):
			position += 1
			continue
		var token := Token.new()
		token.start = position
		while position < code.length() and not _is_space(code.unicode_at(position)):
			position += 1
		token.end = position
		token.text = code.substr(token.start, token.end - token.start)
		result.append(token)
	return result


## What is at `column` of `line`. With `caret` false the column is a character the mouse
## is over, so a word covers start <= column < end. With `caret` true it is a caret position
## between characters, which also touches the word it stands right behind: start <= column <= end.
static func locate(line: String, column: int, caret := false) -> Spot:
	var spot := Spot.new()
	var semicolon := line.find(";")
	if semicolon >= 0 and (column > semicolon if caret else column >= semicolon):
		spot.part = Part.COMMENT
		return spot
	var words := tokens(line)
	if words.is_empty():
		return spot
	var first := words[0]
	spot.label_line = words.size() == 1 and first.text.ends_with(":") \
			and FoeAsm.is_identifier(first.text.trim_suffix(":"))
	if not spot.label_line:
		spot.opcode = FoeOps.op_from_mnemonic(first.text)
	var found := -1
	for i in words.size():
		var inside := words[i].start <= column and (column <= words[i].end if caret else column < words[i].end)
		if inside:
			found = i
			break
	if found >= 0:
		spot.token = words[found]
		spot.typed = words[found].text.substr(0, clampi(column - words[found].start, 0, words[found].text.length()))
	if found == 0:
		if spot.label_line:
			spot.part = Part.LABEL_DEFINITION
		else:
			spot.part = Part.MNEMONIC if spot.opcode >= 0 else Part.UNKNOWN_WORD
		return spot
	if found < 0 and column < first.start:
		return spot                                  # blank space before the first word
	if spot.label_line:
		return spot                                  # nothing may follow a label
	# After the instruction name: the operand is the number of operands whose words end before the column. A
	# `mirrored` is part of the operand before it (the assembler groups the words the same way).
	var groups := operand_groups(words)
	var index := 0
	if found >= 0:
		index = groups[found]["operand"]
		spot.on_mirror_word = groups[found]["mirror_word"]
	else:
		for i in range(1, words.size()):
			if words[i].end < column:
				index = groups[i]["operand"] + 1
	spot.operand = index
	var before := FoeOps.operands(spot.opcode)
	if index > 0 and index <= before.size() and before[index - 1].get("mirror", false):
		var previous_mirrored := false
		for i in range(1, words.size()):
			if groups[i]["operand"] == index - 1 and groups[i]["mirror_word"]:
				previous_mirrored = true
		spot.mirror_may_follow = not previous_mirrored and not spot.on_mirror_word
	spot.part = Part.OPERAND if found >= 0 else Part.NOTHING
	return spot


## Which operand each word of `words` (the line's tokens) is, as the assembler groups them: element i is
## {"operand": the operand's index (-1 for the instruction name), "mirror_word": the word is a `mirrored` that
## belongs to the operand before it}. A `mirrored` with no operand before it, or a second one, is an operand of its own.
static func operand_groups(words: Array[Token]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var operands := 0
	var last_mirrored := false
	for i in words.size():
		if i == 0:
			result.append({"operand": -1, "mirror_word": false})
		elif words[i].text.to_lower() == FoeOps.MIRROR_WORD and operands > 0 and not last_mirrored:
			last_mirrored = true
			result.append({"operand": operands - 1, "mirror_word": true})
		else:
			operands += 1
			last_mirrored = false
			result.append({"operand": operands - 1, "mirror_word": false})
	return result


## The lines on which each label is defined: label -> Array[int] of 0-based line numbers
## (more than one when the label is defined twice, which the assembler rejects).
static func label_definitions(lines: PackedStringArray) -> Dictionary:
	var result := {}
	for n in lines.size():
		var words := tokens(lines[n])
		if words.size() == 1 and words[0].text.ends_with(":") and FoeAsm.is_identifier(words[0].text.trim_suffix(":")):
			var name := words[0].text.trim_suffix(":")
			if not result.has(name):
				result[name] = []
			result[name].append(n)
	return result


## The lines that use each label as an operand (Jump_To, Call_Subroutine, Loop_Counter...):
## label -> Array[int] of 0-based line numbers, one entry per use.
static func label_uses(lines: PackedStringArray) -> Dictionary:
	var result := {}
	for n in lines.size():
		var words := tokens(lines[n])
		if words.size() < 2:
			continue
		var list := FoeOps.operands(FoeOps.op_from_mnemonic(words[0].text))
		for k in mini(list.size(), words.size() - 1):
			if list[k]["kind"] == FoeOps.Kind.LABEL and FoeAsm.is_identifier(words[k + 1].text):
				var name := words[k + 1].text
				if not result.has(name):
					result[name] = []
				result[name].append(n)
	return result


## The label the caret (a column between characters) is on: the name of a `name:` line, or
## a label operand of an instruction. "" when the caret touches neither.
static func label_at(line: String, column: int) -> String:
	var spot := locate(line, column, true)
	if spot.token == null:
		return ""
	if spot.part == Part.LABEL_DEFINITION:
		return spot.token.text.trim_suffix(":")
	if spot.part == Part.OPERAND and spot.operand_info().get("kind", -1) == FoeOps.Kind.LABEL \
			and FoeAsm.is_identifier(spot.token.text):
		return spot.token.text
	return ""


## `lines` with every definition (`old:`) and every use (a label operand `old`) of the label
## `old` renamed to `new`. Whole words only, so `old2` and `xold` stay; comments are never
## touched, because the words come from `tokens`, which stops at the `;`.
static func rename_label(lines: PackedStringArray, old: String, new: String) -> PackedStringArray:
	var result := lines.duplicate()
	for n in lines.size():
		var words := tokens(lines[n])
		if words.is_empty():
			continue
		var found: Array[Token] = []
		var definition := words.size() == 1 and words[0].text == old + ":"
		if definition:
			found.append(words[0])
		else:
			var list := FoeOps.operands(FoeOps.op_from_mnemonic(words[0].text))
			for k in mini(list.size(), words.size() - 1):
				if list[k]["kind"] == FoeOps.Kind.LABEL and words[k + 1].text == old:
					found.append(words[k + 1])
		var line := lines[n]
		for i in range(found.size() - 1, -1, -1):          # from the right, so earlier columns stay valid
			line = line.substr(0, found[i].start) + new + (":" if definition else "") + line.substr(found[i].end)
		result[n] = line
	return result


static func _is_space(code: int) -> bool:
	return code == 32 or code == 9 or code == 13
