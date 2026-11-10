@tool
class_name FoeCodeEdit
extends CodeEdit
## The text editor of one foe script: a CodeEdit that knows the instructions. Hovering a word
## shows a tooltip, typing operands shows the instruction's signature, and typing a word
## offers completions. The texts come from FoeHelp; this class only connects them to the
## CodeEdit machinery.
##
## Teaches: three different ways a CodeEdit shows help, because each works differently:
##   TOOLTIP. `symbol_tooltip_on_hover` + `symbol_hovered` only emit a signal (the Script
##     editor answers it by building its own popup); CodeEdit shows nothing itself, and
##     `set_symbol_lookup_word_as_valid` belongs to Ctrl+click lookups. What does show
##     text is Control's ordinary tooltip, and a Control can compute it on demand:
##     override the virtual `_get_tooltip(at_position)`. The viewport calls it after the
##     mouse has rested for `gui/timers/tooltip_delay_sec`, with the mouse position, so
##     there is no timing to get wrong (a `tooltip_text` set from `symbol_hovered` would
##     race with the viewport's own timer). Unlike the symbol word, the position tells us
##     the exact column, which `self+2` and `-3` need: a "word" for CodeEdit stops at `+`.
##   CODE HINT. `set_code_hint(text)` draws a small box next to the caret. The character
##     U+FFFF (FoeOps.HINT_MARK) placed before and after one part of the text underlines
##     that part, and the box is shifted so the marked part sits under the caret. CodeEdit
##     clears the hint itself on a click and on cursor keys, so we set it again on the
##     `caret_changed` signal. There is no getter, hence `hint` below.
##   COMPLETION. The virtual `_request_code_completion(force)` is called when the user
##     presses Ctrl+Space (force) or `request_code_completion()` is called. It submits
##     options with `add_code_completion_option` and then `update_code_completion_options`;
##     the CodeEdit filters, sorts and draws them, and inserts the chosen one. CodeEdit
##     asks for completion by itself only after a prefix character (`code_completion_prefixes`);
##     to complete while typing a word like the Script editor does, we call
##     `request_code_completion()` when the text changes.
## A CodeEdit that is made in code needs a subclass to override a virtual: that is why this
## class exists. `@tool`, like every script that runs in the editor.

## The caret hint as last given to `set_code_hint` ("" when none).
var hint := ""
## The names of the sector this script belongs to (the panel sets it before each check); completion and tooltips
## show them next to their numbers. Without it only the global and common names are known.
var symbols := FoeNames.new()


func _init() -> void:
	code_completion_enabled = true
	# Without this CodeEdit refuses to complete after blank space, so Ctrl+Space on an empty
	# line (all instruction names) would show nothing. A typed space does not open a menu
	# by itself: FoeHelp.completions offers nothing until a letter is typed (unless forced).
	code_completion_prefixes = PackedStringArray([" "])
	set_code_hint_draw_below(true)
	caret_changed.connect(update_hint)
	text_changed.connect(_on_text_changed)


# --- comments ----------------------------------------------------------------

## Ctrl+K: comment out the caret's line, or every line the selection touches, by putting
## `;` in front of it; if all those lines (blank ones aside) are comments already, take the
## `;` away again. One undo step. CodeEdit's `delimiter_comments` only teaches it what a
## comment looks like (for highlighting); the toggle itself is a command of Godot's Script
## editor, not of CodeEdit, so a CodeEdit of our own has to bring it along.
func toggle_comment() -> void:
	var first := get_caret_line()
	var last := first
	if has_selection():
		first = get_selection_from_line()
		last = get_selection_to_line()
		if last > first and get_selection_to_column() == 0:
			last -= 1                       # a selection ending at column 0 does not take that line
	var all_commented := true
	for i in range(first, last + 1):
		var stripped := get_line(i).strip_edges(true, false)
		if not stripped.is_empty() and not stripped.begins_with(";"):
			all_commented = false
	begin_complex_operation()
	for i in range(first, last + 1):
		var line := get_line(i)
		if all_commented:
			var at := line.find(";")
			if at >= 0:
				set_line(i, line.substr(0, at) + line.substr(at + 1))
		elif not line.strip_edges().is_empty():
			set_line(i, ";" + line)
	end_complex_operation()


# --- tooltip -----------------------------------------------------------------

## Called by the viewport when the mouse has rested over the editor.
func _get_tooltip(at_position: Vector2) -> String:
	var where := get_line_column_at_pos(Vector2i(at_position), false, false)
	return tooltip_at(where.y, where.x)


## The tooltip for a character cell; "" when there is none (blank space, past the end of a line).
func tooltip_at(line: int, column: int) -> String:
	if line < 0 or column < 0:
		return ""
	return FoeHelp.tooltip(text.split("\n"), line, column, symbols)


# --- code hint ---------------------------------------------------------------

## Shows the hint for the caret's place, or hides it.
func update_hint() -> void:
	hint = FoeHelp.code_hint(get_line(get_caret_line()), get_caret_column())
	set_code_hint(hint)


# --- completion --------------------------------------------------------------

func _request_code_completion(force: bool) -> void:
	var options := FoeHelp.completions(text.split("\n"), get_caret_line(), get_caret_column(), force, symbols)
	if options.is_empty():
		cancel_code_completion()
		return
	for option in options:
		var display: String = option.get("display", option["name"]) + "    " + option["summary"]
		add_code_completion_option(_kind_of(option["type"]), display, option["insert"], _color_of(option["type"]))
	update_code_completion_options(force)


## Typing in the editor opens the completion menu while the caret is at the end of a word.
## Only when this editor has the keyboard focus: loading a file, Reload or a change from
## another program also change the text, and must not pop a menu up.
func _on_text_changed() -> void:
	if has_focus():
		request_code_completion()


func _kind_of(type: int) -> int:
	match type:
		FoeHelp.Candidate.LABEL:
			return CodeEdit.KIND_CONSTANT
		FoeHelp.Candidate.SELF, FoeHelp.Candidate.MIRROR:
			return CodeEdit.KIND_VARIABLE
		FoeHelp.Candidate.NAME:
			return CodeEdit.KIND_ENUM
	return CodeEdit.KIND_FUNCTION


## Completion entries use the highlighter's colours, so a name looks in the menu like it
## looks in the text.
func _color_of(type: int) -> Color:
	var highlighter := syntax_highlighter as FoeSyntaxHighlighter
	if highlighter == null:
		return Color.WHITE
	match type:
		FoeHelp.Candidate.LABEL:
			return highlighter.label_color
		FoeHelp.Candidate.SELF, FoeHelp.Candidate.MIRROR:
			return highlighter.self_color
		FoeHelp.Candidate.NAME:
			return highlighter.name_color
	return highlighter.mnemonic_color
