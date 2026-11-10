@tool
class_name FoeSyntaxHighlighter
extends SyntaxHighlighter
## Colours the foe assembly (docs/create/FOE_SCRIPTING.md section 2) in the Foe Script editor.
##
## Teaches: `SyntaxHighlighter`. A CodeEdit asks its highlighter, line by line, "which
## colour starts at which column?"; the answer is a Dictionary `{column: {"color": Color}}`
## and each colour lasts until the next column listed. The highlighter only looks at one
## line at a time, which is enough here: the language has no multi-line constructs (a
## comment ends with its line). `highlight_text` does the work on a plain String, so a test
## can check it without any editor around.
##
## What is coloured: the instruction name (any upper/lower case, must be in FoeOps.MNEMONIC;
## the `Padding` pseudo-instruction is coloured like an instruction, since it is written like one),
## a label definition `name:`, a number, `self` / `self+N` / `self-N`, a label used as an
## operand, a NAME used as an operand of a sound / picture / creature / flag / screen (and the `mirrored`
## after a picture), and the comment after `;`. A first word that is neither a label nor an
## instruction is drawn in the error colour, the same mistake FoeAsm would report.
## `@tool`, like every script that runs inside the editor.

var text_color := Color(0.80, 0.81, 0.82)
var mnemonic_color := Color(1.00, 0.44, 0.52)      # Jump_To, Wait_Next_Tick, ...
var label_color := Color(0.34, 0.70, 1.00)         # again:   and   Jump_To again
var number_color := Color(0.63, 1.00, 0.88)
var self_color := Color(1.00, 0.70, 0.45)          # self, self+2
var name_color := Color(0.65, 0.85, 0.50)          # begin, eel_swim_1 (and mirrored)
var comment_color := Color(0.80, 0.81, 0.82, 0.5)
var error_color := Color(1.00, 0.30, 0.30)


## Takes the colours of the editor theme, so the Foe Script screen looks like the Script
## screen (and follows the user's theme). Does nothing outside the editor.
func use_editor_colors() -> void:
	if not Engine.is_editor_hint():
		return
	var settings := EditorInterface.get_editor_settings()
	text_color = _setting(settings, "text_color", text_color)
	mnemonic_color = _setting(settings, "keyword_color", mnemonic_color)
	label_color = _setting(settings, "function_color", label_color)
	number_color = _setting(settings, "number_color", number_color)
	self_color = _setting(settings, "base_type_color", self_color)
	name_color = _setting(settings, "string_color", name_color)
	comment_color = _setting(settings, "comment_color", comment_color)


func _setting(settings: EditorSettings, name: String, fallback: Color) -> Color:
	var key := "text_editor/theme/highlighting/" + name
	return settings.get_setting(key) if settings.has_setting(key) else fallback


func _get_line_syntax_highlighting(line: int) -> Dictionary:
	return highlight_text(get_text_edit().get_line(line))


## The colours for one line of text, in the form `_get_line_syntax_highlighting` returns.
func highlight_text(text: String) -> Dictionary:
	var colors := {0: {"color": text_color}}
	var comment := text.find(";")
	var code := text if comment < 0 else text.substr(0, comment)
	var position := 0
	var first_word := true
	var opcode := -1
	var operands := 0                                    # how many operands the words so far make
	var last_mirrored := false
	while position < code.length():
		if _is_space(code[position]):
			position += 1
			continue
		var start := position
		while position < code.length() and not _is_space(code[position]):
			position += 1
		var word := code.substr(start, position - start)
		var kind := -1
		if first_word:
			opcode = FoeOps.op_from_mnemonic(word)
		elif word.to_lower() == FoeOps.MIRROR_WORD and operands > 0 and not last_mirrored:
			last_mirrored = true
			kind = -2                                    # the mirror word of the operand before
		else:
			operands += 1
			last_mirrored = false
			var list := FoeOps.operands(opcode)
			kind = list[operands - 1]["kind"] if operands <= list.size() else -1
		colors[start] = {"color": _word_color(word, first_word, kind)}
		colors[position] = {"color": text_color}         # the gap after the word
		first_word = false
	if comment >= 0:
		colors[comment] = {"color": comment_color}      # replaces the gap colour if they meet
	return colors


## `kind` is the FoeOps.Kind of the operand the word is (-1 when unknown, -2 for a `mirrored`).
func _word_color(word: String, first_word: bool, kind := -1) -> Color:
	if first_word:
		if word.ends_with(":") and _is_identifier(word.trim_suffix(":")):
			return label_color
		return mnemonic_color if FoeOps.op_from_mnemonic(word) >= 0 else error_color
	if kind == -2:
		return name_color
	if word.is_valid_int():
		return number_color
	if (kind == FoeOps.Kind.FOE and FoeOps.parse_foe(word) >= 0) or (kind == -1 and word.begins_with("self")):
		return self_color
	if _is_identifier(word):
		return label_color if kind == FoeOps.Kind.LABEL or kind == -1 else name_color
	return text_color


func _is_space(character: String) -> bool:
	return character == " " or character == "\t" or character == "\r"


## A letter or `_`, then letters, digits and `_`: the same rule the assembler applies to labels.
func _is_identifier(word: String) -> bool:
	if word.is_empty():
		return false
	for i in word.length():
		var code := word.unicode_at(i)
		var letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95
		var digit := code >= 48 and code <= 57
		if not (letter or (digit and i > 0)):
			return false
	return true
