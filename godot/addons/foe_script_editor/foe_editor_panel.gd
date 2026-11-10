@tool
class_name FoeEditorPanel
extends HSplitContainer
## The "Foe Script" screen: a small text editor for `.foe` creature scripts.
##
## Teaches: building editor UI in code from the stock Controls (HSplitContainer, ItemList,
## CodeEdit, Label, Button, Timer) and wiring them with signals; `CodeEdit` with line
## numbers, a custom `SyntaxHighlighter` and (in `FoeCodeEdit`) tooltips, hints and completion
## that know the instructions; and keeping an EDIT BUFFER apart from the
## RESOURCE it came from. Left: the list of opened files. Right: the file's path with an
## "unsaved" marker, the CodeEdit, and under it the problems the assembler (`FoeAsm`) found.
##
## One `Document` per opened file, each with its OWN CodeEdit (only the current one is
## visible), so switching files keeps the undo history, caret and scroll position of each.
## A document is unsaved ("dirty") while its text differs from what is on disk. Saving
## copies the text into `FoeScript.source` and writes it with `ResourceSaver.save`, whose
## `FoeScriptSaver` stores the text byte for byte. The plugin (plugin.gd) owns the panel and
## decides when the editor asks us to save; nothing here needs the plugin, which is why the
## tests can create a panel by itself. `@tool`, like every script that runs in the editor.
##
## RUN IN SANDBOX (the button, or Ctrl+R) plays `src/debug/foe_sandbox.tscn` on this file's sector, opened on the screen of
## the creature whose script contains the caret's line, with that creature selected and its `.foe` line shown. The panel
## only decides WHAT to run (`run_in_sandbox`, tested without the editor) and announces it with the signal `sandbox_requested`;
## plugin.gd starts the game. The text is saved first, because the game is a new process that reads the files from disk; a
## text that does not assemble is not run. While the sandbox is paused, the lines its creatures are on are marked in the gutter
## (`show_running_lines`, fed by foe_debugger_plugin.gd over the debugger channel).
##
## Two commands go beyond text editing, both for the names and comments the designers add
## to the generated script text (docs/create/FOE_SCRIPTING.md, "Names and comments"):
##   RENAME LABEL (F2, or the context menu) renames a label's definition and every use in
##     the buffer. If creatures name it as their start / hit / ink label, the sector's `.tres`
##     is changed too, and the `.foe` is saved with it, so the two files never disagree.
##   STORE NAMES & COMMENTS (the button) harvests the saved text into the annotation store
##     (`FoeAnnotations`), so a later import or reset brings the names and comments back.
##     Saving a file never does this by itself.

## One opened file.
class Document extends RefCounted:
	var resource: FoeScript
	var edit: CodeEdit
	## The text as it is on disk (as of the last load or save).
	var disk_text := ""
	## True when the file changed on disk while the buffer had unsaved edits.
	var conflict := false
	## The assembler's messages for the current text ("line N: ...").
	var errors: Array[String] = []
	var error_lines: Array[int] = []
	## Lines tinted yellow: the first line of each run of code that never executes.
	var warning_lines: Array[int] = []
	## Code no creature can reach ("line N: never executed ..."): shown after the errors in
	## another colour; not a mistake the assembler refuses, and never blocks saving.
	var warnings: Array[String] = []
	var size := 0
	## The text's source map (instruction -> line), made by `check`.
	var source_map: FoeSourceMap = null
	## The gutter that shows the creatures of a running sandbox (see `show_running_lines`).
	var running_gutter := -1
	## The lines (0-based) that carry a mark in it.
	var running_lines: Array[int] = []
	## Messages of the commands (rename, store): shown under the problems until the next command.
	var notes: Array[String] = []

	func path() -> String:
		return resource.resource_path

	func is_dirty() -> bool:
		return edit.text != disk_text

## How long after the last keystroke the text is assembled again.
const CHECK_DELAY := 0.5
const ERROR_LINE_COLOR := Color(1.0, 0.3, 0.3, 0.18)
const WARNING_LINE_COLOR := Color(0.95, 0.8, 0.3, 0.16)
const NO_COLOR := Color(0, 0, 0, 0)
## Id of the "Rename label" entry in the editor's context menu (far above the engine's own ids).
const RENAME_MENU_ID := 1000
const NOTE_COLOR := Color(0.6, 0.8, 1.0)
const WARNING_COLOR := Color(0.95, 0.8, 0.3)
const STORE_FILE := "foe_annotations.json"
## The scene "Run in sandbox" plays, and the largest label of "no creature" in the creature drop-down.
const SANDBOX_SCENE := "res://src/debug/foe_sandbox.tscn"
const RUNNING_COLOR := Color(0.4, 0.9, 0.5)
const HINT := "Double-click a .foe file in the FileSystem dock to edit it here."

var _documents: Array[Document] = []
var _current: Document = null

var _file_list: ItemList
var _path_label: Label
var _state_label: Label
var _save_button: Button
var _reload_button: Button
var _close_button: Button
var _editors: MarginContainer
var _hint: Label
var _problem_title: Label
var _problem_list: ItemList
var _close_dialog: ConfirmationDialog
var _store_button: Button
var _rename_dialog: ConfirmationDialog
var _rename_edit: LineEdit
var _rename_message: Label
var _rename_doc: Document = null
var _rename_old := ""
var _check_timer: Timer
var _run_button: Button
var _foe_choice: OptionButton
var _pause_check: CheckBox

## The panel wants the game to run the sandbox with these command-line words (`FoeSandbox.parse_args`).
signal sandbox_requested(arguments: String)


func _init() -> void:
	name = "FoeEditorPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()


func _notification(what: int) -> void:
	# Back from another program (maybe a text editor that saved the file): look at the disk.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_visible_in_tree():
		check_disk_changes()


# =============================================================================
# Public API (used by plugin.gd and the tests)
# =============================================================================

## Shows `script` in the editor, opening a tab for it when it is not open yet.
## Returns the document, or null for a FoeScript that has no file to save to.
func open_script(script: FoeScript) -> Document:
	if script == null or script.resource_path.is_empty():
		return null
	var doc := find_document(script.resource_path)
	if doc == null:
		doc = _add_document(script)
	_select(doc)
	return doc


func find_document(path: String) -> Document:
	for doc in _documents:
		if doc.path() == path:
			return doc
	return null


func current_document() -> Document:
	return _current


func document_count() -> int:
	return _documents.size()


## The paths of the files with unsaved changes.
func unsaved_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for doc in _documents:
		if doc.is_dirty():
			paths.append(doc.path())
	return paths


func has_unsaved() -> bool:
	return not unsaved_paths().is_empty()


## Writes the document to its file. Returns OK or the error ResourceSaver reported.
func save_document(doc: Document) -> Error:
	doc.resource.source = doc.edit.text
	var error := ResourceSaver.save(doc.resource, doc.path())
	if error != OK:
		push_error("Foe Script: could not save %s (error %d)" % [doc.path(), error])
		return error
	doc.disk_text = doc.edit.text
	doc.conflict = false
	if Engine.is_editor_hint():
		# Tell the editor about the new file content, so it does not scan for it later.
		EditorInterface.get_resource_filesystem().update_file(doc.path())
	_refresh_state(doc)
	return OK


## Saves every document with unsaved changes. Returns the first error, or OK.
func save_all() -> Error:
	var result := OK
	for doc in _documents:
		if doc.is_dirty():
			var error := save_document(doc)
			if result == OK:
				result = error
	return result


## Copies the buffers into their FoeScript resources, without writing any file, so the
## editor's copy of a script (what the Inspector sees) is never behind what you typed.
func apply_to_scripts() -> void:
	for doc in _documents:
		doc.resource.source = doc.edit.text


## Closes the document. With unsaved changes they are thrown away, so ask first
## (the Close button does).
func close_document(doc: Document) -> void:
	var index := _documents.find(doc)
	if index < 0:
		return
	_documents.remove_at(index)
	_file_list.remove_item(index)
	doc.edit.queue_free()
	doc.resource.reload()                  # forget edits that were applied but never saved
	if _current == doc:
		_current = null
		if _documents.is_empty():
			_show_nothing()
		else:
			_select(_documents[mini(index, _documents.size() - 1)])


## Compares every open file with the disk. A file changed behind our back is read again
## when the buffer has no unsaved edits; otherwise the buffer is kept and marked.
func check_disk_changes() -> void:
	for doc in _documents:
		if not FileAccess.file_exists(doc.path()):
			continue
		var text := _lf(FileAccess.get_file_as_string(doc.path()))
		if text == doc.disk_text:
			continue
		if doc.is_dirty():
			doc.conflict = true
		else:
			_set_text(doc, text)
			doc.resource.reload()
		_refresh_state(doc)


## Throws the unsaved edits away and reads the file again.
func reload_document(doc: Document) -> void:
	_set_text(doc, FileAccess.get_file_as_string(doc.path()))
	doc.resource.reload()
	doc.conflict = false
	_refresh_state(doc)


## Assembles the document's text and shows the problems. Done by a timer after typing
## stops, and directly after a load or a save.
func check(doc: Document) -> void:
	var result := FoeAsm.assemble(doc.edit.text, 0, _symbols_of(doc))
	doc.errors = result.errors
	doc.size = result.bytes.size()
	doc.warnings = FoeAsm.dead_code_warnings(doc.edit.text, result, _entry_labels_of(doc))
	doc.source_map = FoeSourceMap.from_result(doc.edit.text, result)
	for line in doc.error_lines + doc.warning_lines:
		if line < doc.edit.get_line_count():
			doc.edit.set_line_background_color(line, NO_COLOR)
	doc.error_lines.clear()
	doc.warning_lines.clear()
	for message in doc.warnings:
		var line := _line_of(message) - 1
		if line >= 0 and line < doc.edit.get_line_count():
			doc.edit.set_line_background_color(line, WARNING_LINE_COLOR)
			doc.warning_lines.append(line)
	for message in doc.errors:
		var line := _line_of(message) - 1
		if line >= 0 and line < doc.edit.get_line_count():
			doc.edit.set_line_background_color(line, ERROR_LINE_COLOR)
			doc.error_lines.append(line)
	if doc == _current:
		_show_problems(doc)
		_update_creature_choice()


## The names the document's operands may use (FoeNames: the sector beside `doc` says which sector and zone).
## Without such a sector only the global and common names work. The completion and the tooltips of the editor
## use the same names.
func _symbols_of(doc: Document) -> FoeNames:
	var sector := _sector_of(doc)
	var symbols := FoeNames.for_sector(sector)
	if doc.edit is FoeCodeEdit:
		(doc.edit as FoeCodeEdit).symbols = symbols
	return symbols


## The sector beside `doc` (the `.tres` with the same name); null when there is none.
func _sector_of(doc: Document) -> SectorData:
	var tres_path := doc.path().get_basename() + ".tres"
	return ResourceLoader.load(tres_path) as SectorData if FileAccess.file_exists(tres_path) else null


## The labels the creatures of the sector beside `doc` (its `.tres`) start at; [] when there is
## no such sector, which means no dead-code warnings (the entry points are not known).
func _entry_labels_of(doc: Document) -> Array:
	var tres_path := doc.path().get_basename() + ".tres"
	if not FileAccess.file_exists(tres_path):
		return []
	var sector := ResourceLoader.load(tres_path) as SectorData
	return [] if sector == null else FoeAsm.sector_entry_labels(sector)


## Moves the caret of the current document to the line of problem number `index`: the errors
## first, then the warnings (the notes after them have no line).
func go_to_problem(index: int) -> void:
	if _current == null or index < 0 or index >= _current.errors.size() + _current.warnings.size():
		return
	var message := _current.errors[index] if index < _current.errors.size() else _current.warnings[index - _current.errors.size()]
	var line := _line_of(message) - 1
	if line < 0:
		return
	_current.edit.set_caret_line(line)
	_current.edit.set_caret_column(0)
	_current.edit.center_viewport_to_caret()
	_current.edit.grab_focus()


# =============================================================================
# Run in sandbox, and the lines of a running sandbox
# =============================================================================

## The creatures that run the caret's line of the current document (numbers in the sector), the ones that enter at the label the
## caret is under first. [] when the text does not assemble or no creature runs it.
func creatures_at_caret() -> Array[int]:
	if _current == null or _current.source_map == null:
		return []
	var sector := _sector_of(_current)
	return [] if sector == null else _current.source_map.creatures_at_line(sector.foes, _current.edit.get_caret_line() + 1)


## Plays the sandbox on the current document's sector with creature `foe` (-1: the first of `creatures_at_caret`; a creature
## number to choose another), opened on the screen it lives on. `paused` starts the sandbox with the clock stopped, to step
## through the lines. Saves the text first, and refuses (returns why, and shows it under the problems) when it cannot run:
## no sector beside the file, a sector the sandbox does not know, a text that does not assemble, a file that cannot be saved.
## Returns "" when it asked for the run (`sandbox_requested`).
func run_in_sandbox(foe: int = -1, paused: bool = false) -> String:
	var problem := _sandbox_problem()
	if problem.is_empty():
		var doc := _current
		check(doc)                                  # the text as it is now, not as it was 0.5 s ago
		if not doc.errors.is_empty():
			problem = "Not run: the text has %d problem%s (see below); the game would stop every creature of the sector." % [
					doc.errors.size(), "" if doc.errors.size() == 1 else "s"]
		elif doc.is_dirty() and save_document(doc) != OK:
			problem = "Not run: %s could not be saved." % doc.path().get_file()
	if not problem.is_empty():
		_note(problem)
		return problem
	var doc := _current
	var sector := _sector_of(doc)
	var creatures := creatures_at_caret()
	if foe < 0 and not creatures.is_empty():
		foe = creatures[0]
	var arguments := "--sector=%d" % sector.index
	var message := "Sandbox: sector %d" % sector.index
	if foe >= 0 and foe < sector.foes.size():
		arguments += " --foe=%d" % foe
		message += ", creature #%d on screen %d" % [foe, sector.foes[foe].screen]
	else:
		foe = -1
		message += ", screen 0 (no creature runs line %d)" % (doc.edit.get_caret_line() + 1)
	if paused:
		arguments += " --pause"
		message += ", paused: S steps a tick"
	_note(message)
	sandbox_requested.emit(arguments)
	return ""


## Why the sandbox cannot be run for the current document, before its text is looked at ("" when it can).
func _sandbox_problem() -> String:
	if _current == null:
		return "Not run: open a sector's .foe file first."
	var sector := _sector_of(_current)
	if sector == null:
		return "Not run: there is no sector beside this file (%s)." % (_current.path().get_basename() + ".tres").get_file()
	if not Catalog.has_sector(sector.index):
		return "Not run: the sandbox plays the sectors of the game (%s), and there is no sector %d there." % [", ".join(Catalog.own_sector_dirs()), sector.index]
	return ""


## Marks the lines the creatures of a running sandbox are on, in the document of the sector the report names. `report` is
## `FoeSandbox.line_report()`: {"sector", "selected", "lines": {creature number: line}}. The gutter shows the creature numbers
## (`#3 #7`), the selected one as `*3`; the selected creature's line is scrolled into view when it is off screen. An
## empty "lines" (the sandbox runs again) or `clear_running_lines` removes the marks.
func show_running_lines(report: Dictionary) -> void:
	clear_running_lines()
	var lines: Dictionary = report.get("lines", {})
	if lines.is_empty():
		return
	var doc: Document = null
	for candidate in _documents:
		if FoeAnnotations.sector_of_path(candidate.path()) == int(report.get("sector", -1)):
			doc = candidate
	if doc == null:
		return
	if doc.running_gutter < 0:
		doc.edit.add_gutter()
		doc.running_gutter = doc.edit.get_gutter_count() - 1
		doc.edit.set_gutter_name(doc.running_gutter, "creatures")
		doc.edit.set_gutter_type(doc.running_gutter, TextEdit.GUTTER_TYPE_STRING)
		doc.edit.set_gutter_draw(doc.running_gutter, true)
		doc.edit.set_gutter_width(doc.running_gutter, 90)
	var selected := int(report.get("selected", -1))
	var by_line := {}
	for foe in lines:
		by_line[int(lines[foe])] = by_line.get(int(lines[foe]), []) + [int(foe)]
	for line in by_line:
		if line < 1 or line > doc.edit.get_line_count():
			continue
		var words: Array[String] = []
		for foe in by_line[line]:
			words.append(("*%d" if foe == selected else "#%d") % foe)
		doc.edit.set_line_gutter_text(line - 1, doc.running_gutter, " ".join(words))
		doc.edit.set_line_gutter_item_color(line - 1, doc.running_gutter, RUNNING_COLOR)
		doc.running_lines.append(line - 1)
	if doc == _current and lines.has(selected) and int(lines[selected]) >= 1:
		var follow := int(lines[selected]) - 1
		if follow < doc.edit.get_first_visible_line() or follow > doc.edit.get_last_full_visible_line():
			doc.edit.set_line_as_center_visible(follow)


## Takes the creature marks away from every document.
func clear_running_lines() -> void:
	for doc in _documents:
		for line in doc.running_lines:
			if line < doc.edit.get_line_count():
				doc.edit.set_line_gutter_text(line, doc.running_gutter, "")
		doc.running_lines.clear()


# =============================================================================
# Names and comments: rename a label, store the names in the annotation store
# =============================================================================

## Why `new` cannot be the name of the label `old` in this document ("" when it can).
func rename_problem(doc: Document, old: String, new: String) -> String:
	var lines := doc.edit.text.split("\n")
	var defined := FoeLineInfo.label_definitions(lines)
	if not defined.has(old):
		return "'%s' is not a label defined in this file." % old
	if not FoeAsm.is_identifier(new):
		return "A label name is letters, digits and _, and does not start with a digit."
	if new == old:
		return "That is the name it has."
	if defined.has(new):
		return "'%s' is already a label of this file." % new
	if doc.conflict:
		return "The file changed on disk: Save or Reload it first."
	return ""


## Renames the label `old` to `new`: the definition and every use in the buffer (whole words
## only, never inside a comment), as one step that Undo (Ctrl+Z) takes back in one go. When
## creatures of the sector name `old` as their start / hit / ink label, the sector's `.tres`
## follows (its text and the loaded SectorData) and the `.foe` is saved as well: the two
## files are written together, so neither ever names a label the other does not have.
## Otherwise the buffer is only changed (unsaved). Returns "" or why nothing was done.
func rename_label(doc: Document, old: String, new: String) -> String:
	new = new.strip_edges()
	var problem := rename_problem(doc, old, new)
	if not problem.is_empty():
		return problem
	var lines := doc.edit.text.split("\n")
	var renamed := FoeLineInfo.rename_label(lines, old, new)
	var line := doc.edit.get_caret_line()
	var column := doc.edit.get_caret_column()
	var places := 0
	doc.edit.begin_complex_operation()
	for n in lines.size():
		if renamed[n] != lines[n]:
			doc.edit.set_line(n, renamed[n])
			places += 1
	doc.edit.end_complex_operation()
	doc.edit.set_caret_line(line)
	doc.edit.set_caret_column(mini(column, doc.edit.get_line(line).length()))
	_on_text_changed(doc)
	doc.notes = ["Renamed '%s' to '%s' in %d line%s." % [old, new, places, "" if places == 1 else "s"]]
	var tres_path := doc.path().get_basename() + ".tres"
	if FileAccess.file_exists(tres_path):
		var tres_text := FileAccess.get_file_as_string(tres_path)
		var changed := FoeAnnotations.rename_entry_label(tres_text, old, new)
		if changed != tres_text:
			var labels := FoeAnnotations.read_entry_labels(changed)
			_use_labels_in_loaded_sector(tres_path, labels)       # before the text is saved: it recompiles
			var error := save_document(doc)
			if error == OK:
				error = _write_text(tres_path, changed)
			if error == OK:
				doc.notes.append("'%s' is an entry label of creatures of %s: renamed there too, and the .foe saved with it." % [old, tres_path.get_file()])
			else:
				doc.notes.append("Could not save the renamed entry label (error %d): check %s and the .foe." % [error, tres_path.get_file()])
	_show_problems(doc)
	return ""


## Harvests the document into the annotation store (res://data/sectors/foe_annotations.json, beside
## the sector's folder; the project's, also for the sectors of the legacy pack): the label names and comments of the text, kept by original byte offset so a
## later import or reset puts them back. Refuses (a note in the problems area) when the
## file is not an original sector, has unsaved changes, or its instructions differ from the
## original. Also rewrites the file in the standard layout if it was not, and makes the
## sector's `.tres` entry labels follow renamed labels. Returns true when stored.
func store_annotations(doc: Document) -> bool:
	var refusal := store_problem(doc)
	if refusal.is_empty():
		var index := FoeAnnotations.sector_of_path(doc.path())
		var original := FoeAnnotations.original(index)
		var result := FoeAnnotations.harvest(doc.edit.text, original["script"], original["base"], original["entries"], _symbols_of(doc))
		refusal = "" if result.ok else result.problem
		if result.ok:
			# the store sits in the folder of the sector folders: data/sectors/sector_NN/sector_NN.foe -> data/sectors/. A pack's sectors are not the project's own
			# data, and the store is the project's (committed): it is `res://data/sectors/foe_annotations.json` for them.
			var sectors_folder := doc.path().get_base_dir().get_base_dir()
			var store_path := FoeAnnotations.STORE_PATH if sectors_folder != Catalog.SECTORS_DIR and Catalog.own_sector_dirs().has(sectors_folder) else sectors_folder.path_join(STORE_FILE)
			var parsed := FoeAnnotations.load_store(store_path)
			if not parsed.ok():
				refusal = "%s: %s" % [STORE_FILE, parsed.error]
			else:
				var annotations := result.annotations()
				if FoeAnnotations.is_empty(annotations):
					parsed.store.erase(index)
				else:
					parsed.store[index] = annotations
				var error := FoeAnnotations.save_store(parsed.store, store_path)
				if error != OK:
					refusal = "could not write %s (error %d)" % [store_path, error]
				else:
					_finish_store(doc, result, original, store_path)
					return true
	doc.notes = ["Names and comments were not stored: %s" % refusal]
	_show_problems(doc)
	return false


## Why this document cannot be harvested right now ("" when it can).
func store_problem(doc: Document) -> String:
	var index := FoeAnnotations.sector_of_path(doc.path())
	if not FoeAnnotations.has_original(index):
		return "this file is not one of the original sectors; its text is its own source, nothing regenerates it, so there is nothing to store."
	var unusable := FoeAnnotations.original_problem()
	if not unusable.is_empty():
		return "the original script is not available to compare with: " + unusable + "."
	if doc.is_dirty():
		return "the file has unsaved changes. Save it first (Ctrl+S), then store."
	if doc.conflict:
		return "the file changed on disk. Save or Reload it first."
	return ""


func _finish_store(doc: Document, result: FoeAnnotations.Harvest, original: Dictionary, store_path: String) -> void:
	var notes: Array[String] = ["Stored %d label name%s and %d commented place%s in %s." % [
			result.labels.size(), "" if result.labels.size() == 1 else "s",
			result.comments.size(), "" if result.comments.size() == 1 else "s", store_path.get_file()]]
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(store_path)
	if result.text != doc.edit.text:
		# Not in the standard layout (the stored file must equal what the disassembler writes): lay it out.
		_replace_text(doc, result.text)
		save_document(doc)
		notes.append("The file was laid out in the standard layout (spacing, final newline) and saved again.")
	var tres_path := doc.path().get_basename() + ".tres"
	if FileAccess.file_exists(tres_path):
		var old := FileAccess.get_file_as_string(tres_path)
		var labels: Array = FoeAsm.entry_labels(original["offsets"], result.annotations())
		var changed := FoeAnnotations.set_entry_labels(old, labels)
		if not changed.is_empty() and changed != old:
			_use_labels_in_loaded_sector(tres_path, labels)
			var error := _write_text(tres_path, changed)
			notes.append("The creatures' entry labels in %s now follow the renamed labels." % tres_path.get_file() if error == OK
					else "Could not write %s (error %d)." % [tres_path.get_file(), error])
	doc.notes = notes
	_show_problems(doc)


## Replaces the whole buffer as one undoable step (setting `text` would forget the undo history).
func _replace_text(doc: Document, text: String) -> void:
	var line := doc.edit.get_caret_line()
	var column := doc.edit.get_caret_column()
	doc.edit.begin_complex_operation()
	doc.edit.select_all()
	doc.edit.insert_text_at_caret(text)
	doc.edit.end_complex_operation()
	doc.edit.deselect()
	line = mini(line, doc.edit.get_line_count() - 1)
	doc.edit.set_caret_line(line)
	doc.edit.set_caret_column(mini(column, doc.edit.get_line(line).length()))
	_on_text_changed(doc)


## Writes a text file (a sector `.tres`) and tells the editor. Returns OK or the error.
func _write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	return OK


## The SectorData of `tres_path`, if the editor has it loaded, gets the new labels in
## memory too (the Inspector and the game's Catalog share that object).
func _use_labels_in_loaded_sector(tres_path: String, labels: Array) -> void:
	if not ResourceLoader.has_cached(tres_path):
		return
	var sector := ResourceLoader.load(tres_path) as SectorData
	if sector == null or sector.foes.size() != labels.size():
		return
	for i in labels.size():                                     # (SectorData compiles again on next use: its cache is keyed by the labels)
		sector.foes[i].start_label = labels[i][0]
		sector.foes[i].hit_label = labels[i][1]
		sector.foes[i].ink_label = labels[i][2]


## Opens the rename dialog for the label under the caret of `doc`.
func begin_rename(doc: Document) -> void:
	var label := FoeLineInfo.label_at(doc.edit.get_line(doc.edit.get_caret_line()), doc.edit.get_caret_column())
	if label.is_empty():
		doc.notes = ["Rename label: put the caret on a label name (a `name:` line or the label after Jump_To, Call_Subroutine, Loop_Counter...) and press F2."]
		_show_problems(doc)
		return
	_rename_doc = doc
	_rename_old = label
	_rename_dialog.title = "Rename label '%s'" % label
	_rename_edit.text = label
	_rename_dialog.get_ok_button().disabled = true
	_rename_message.text = "Every use of the label in this file is renamed too."
	_rename_dialog.popup_centered()
	_rename_edit.select_all()
	_rename_edit.grab_focus()


# =============================================================================
# Building the UI
# =============================================================================

func _build_ui() -> void:
	_file_list = ItemList.new()
	_file_list.custom_minimum_size.x = 160
	_file_list.item_selected.connect(func(index: int): _select(_documents[index]))
	add_child(_file_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)

	var header := HBoxContainer.new()
	right.add_child(header)
	_path_label = Label.new()
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_path_label)
	_state_label = Label.new()
	_state_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	header.add_child(_state_label)
	_foe_choice = OptionButton.new()
	_foe_choice.tooltip_text = "The creatures whose script runs the caret's line. The sandbox opens on the one chosen here."
	_foe_choice.custom_minimum_size.x = 170
	_foe_choice.fit_to_longest_item = false
	_foe_choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_foe_choice)
	_pause_check = CheckBox.new()
	_pause_check.text = "Paused"
	_pause_check.tooltip_text = "Start the sandbox with the clock stopped: S steps one tick, and the line each creature is on is marked here."
	header.add_child(_pause_check)
	_run_button = Button.new()
	_run_button.text = "Run in sandbox"
	_run_button.tooltip_text = "Save, then play the sandbox on this sector and the creature at the caret (Ctrl+R). Tab selects another creature there; P pauses, S steps."
	_run_button.pressed.connect(_on_run_pressed)
	header.add_child(_run_button)
	_reload_button = Button.new()
	_reload_button.text = "Reload"
	_reload_button.tooltip_text = "Throw away your edits and read the file from disk again."
	_reload_button.pressed.connect(func(): reload_document(_current))
	header.add_child(_reload_button)
	_store_button = Button.new()
	_store_button.text = "Store names & comments"
	_store_button.pressed.connect(func(): store_annotations(_current))
	header.add_child(_store_button)
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.tooltip_text = "Write the file (Ctrl+S) and check it for problems."
	_save_button.pressed.connect(func(): save_document(_current))
	header.add_child(_save_button)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(_on_close_pressed)
	header.add_child(_close_button)

	var stack := VSplitContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(stack)

	_editors = MarginContainer.new()
	_editors.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editors.custom_minimum_size.y = 200
	stack.add_child(_editors)
	_hint = Label.new()
	_hint.text = HINT
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_editors.add_child(_hint)

	var problems := VBoxContainer.new()
	problems.custom_minimum_size.y = 130                    # the title and at least three rows of the list
	stack.add_child(problems)
	_problem_title = Label.new()
	problems.add_child(_problem_title)
	_problem_list = ItemList.new()
	_problem_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_problem_list.item_clicked.connect(func(index: int, _at: Vector2, _button: int): go_to_problem(index))
	_problem_list.item_activated.connect(go_to_problem)
	problems.add_child(_problem_list)

	_close_dialog = ConfirmationDialog.new()
	_close_dialog.ok_button_text = "Discard changes"
	_close_dialog.confirmed.connect(func(): close_document(_current))
	add_child(_close_dialog)

	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.ok_button_text = "Rename"
	var rename_box := VBoxContainer.new()
	_rename_edit = LineEdit.new()
	_rename_edit.custom_minimum_size.x = 320
	_rename_edit.text_changed.connect(_on_rename_text_changed)
	rename_box.add_child(_rename_edit)
	_rename_message = Label.new()
	rename_box.add_child(_rename_message)
	_rename_dialog.add_child(rename_box)
	_rename_dialog.register_text_enter(_rename_edit)
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	add_child(_rename_dialog)

	_check_timer = Timer.new()
	_check_timer.one_shot = true
	_check_timer.wait_time = CHECK_DELAY
	_check_timer.timeout.connect(func(): if _current != null: check(_current))
	add_child(_check_timer)

	_show_nothing()


## A new document with its own CodeEdit, filled from the file.
func _add_document(script: FoeScript) -> Document:
	var doc := Document.new()
	doc.resource = script
	doc.edit = _make_code_edit(doc)
	_editors.add_child(doc.edit)
	doc.edit.hide()
	_symbols_of(doc)
	_set_text(doc, FileAccess.get_file_as_string(doc.path()) if FileAccess.file_exists(doc.path()) else script.source)
	_documents.append(doc)
	_file_list.add_item("")
	_refresh_state(doc)
	return doc


func _make_code_edit(doc: Document) -> CodeEdit:
	var edit := FoeCodeEdit.new()           # tooltips, signature hints and completion come with it
	edit.gutters_draw_line_numbers = true
	edit.indent_use_spaces = true
	edit.indent_size = 4
	edit.auto_brace_completion_enabled = false
	edit.delimiter_comments = PackedStringArray([";"])      # what a comment is (Ctrl+K: FoeCodeEdit.toggle_comment)
	edit.highlight_current_line = true
	edit.draw_tabs = true
	edit.scroll_smooth = true
	edit.caret_blink = true
	var highlighter := FoeSyntaxHighlighter.new()
	highlighter.use_editor_colors()
	edit.syntax_highlighter = highlighter
	var menu := edit.get_menu()
	menu.add_separator()
	menu.add_item("Rename label...  (F2)", RENAME_MENU_ID)
	menu.id_pressed.connect(func(id: int): if id == RENAME_MENU_ID: begin_rename(doc))
	menu.about_to_popup.connect(func():
		var index := menu.get_item_index(RENAME_MENU_ID)
		menu.set_item_disabled(index, FoeLineInfo.label_at(edit.get_line(edit.get_caret_line()), edit.get_caret_column()).is_empty()))
	edit.text_changed.connect(_on_text_changed.bind(doc))
	edit.caret_changed.connect(func(): if doc == _current: _update_creature_choice())
	edit.gui_input.connect(_on_edit_input.bind(doc))
	return edit


## CodeEdit keeps only "\n" line breaks, so a file with Windows line endings (CRLF) would look
## changed the moment it opens. The panel therefore compares and saves LF text: opening and
## saving a CRLF file converts it to LF (the project's files are all LF).
func _lf(text: String) -> String:
	return text.replace("\r\n", "\n")


func _set_text(doc: Document, text: String) -> void:
	text = _lf(text)
	doc.edit.text = text
	doc.disk_text = text
	doc.conflict = false
	check(doc)


# =============================================================================
# Selection, state, problems
# =============================================================================

func _select(doc: Document) -> void:
	_current = doc
	_hint.hide()
	for other in _documents:
		other.edit.visible = other == doc
	_file_list.select(_documents.find(doc))
	_refresh_state(doc)
	_show_problems(doc)
	_update_creature_choice()
	if doc.edit.is_inside_tree():
		doc.edit.grab_focus()


func _show_nothing() -> void:
	_hint.show()
	_path_label.text = ""
	_state_label.text = ""
	_save_button.disabled = true
	_close_button.disabled = true
	_store_button.disabled = true
	_store_button.tooltip_text = ""
	_reload_button.hide()
	_run_button.disabled = true
	_foe_choice.clear()
	_problem_title.text = ""
	_problem_list.clear()


## The tab title, the header (path, unsaved marker) and the buttons of one document.
func _refresh_state(doc: Document) -> void:
	var index := _documents.find(doc)
	if index >= 0:
		_file_list.set_item_text(index, doc.path().get_file() + (" *" if doc.is_dirty() else ""))
		_file_list.set_item_tooltip(index, doc.path())
	if doc != _current:
		return
	_path_label.text = doc.path()
	var parts: Array[String] = []
	if doc.is_dirty():
		parts.append("● Unsaved changes")
	if doc.conflict:
		parts.append("Changed on disk: Save overwrites it, Reload discards your edits")
	_state_label.text = "   ".join(parts)
	_save_button.disabled = false
	_close_button.disabled = false
	_run_button.disabled = false
	var original := FoeAnnotations.has_original(FoeAnnotations.sector_of_path(doc.path()))
	_store_button.disabled = not original
	_store_button.tooltip_text = "Keep this file's label names and comments in the annotation store, so a later import or reset brings them back. Save first." if original \
			else "Only the original sectors have a store: the text of a sector you made is its own source, and nothing regenerates it."
	_reload_button.visible = doc.conflict


func _show_problems(doc: Document) -> void:
	_problem_list.clear()
	var warnings := "%d warning%s" % [doc.warnings.size(), "" if doc.warnings.size() == 1 else "s"]
	if doc.errors.is_empty() and doc.warnings.is_empty():
		_problem_title.text = "No problems. Assembles to %d bytes." % doc.size
	elif doc.errors.is_empty():
		_problem_title.text = "No errors, %s (click one to go to its line). Assembles to %d bytes." % [warnings, doc.size]
	else:
		_problem_title.text = "%d problem%s%s (click one to go to its line)" % [doc.errors.size(), "" if doc.errors.size() == 1 else "s",
				"" if doc.warnings.is_empty() else ", " + warnings]
		for message in doc.errors:
			_problem_list.add_item(message)
	for message in doc.warnings:
		var warning_index := _problem_list.add_item(message)
		_problem_list.set_item_custom_fg_color(warning_index, WARNING_COLOR)
	for note in doc.notes:
		var index := _problem_list.add_item(note)
		_problem_list.set_item_custom_fg_color(index, NOTE_COLOR)


## Fills the drop-down beside "Run in sandbox" with the creatures that run the caret's line (the item's id is the creature number).
## Keeps the choice when the creature is still in the list.
func _update_creature_choice() -> void:
	var kept := _foe_choice.get_selected_id() if _foe_choice.selected >= 0 else -1
	_foe_choice.clear()
	var sector := _sector_of(_current) if _current != null else null
	for foe in creatures_at_caret():
		var data := sector.foes[foe]
		_foe_choice.add_item("#%d  %s  (screen %d)" % [foe, data.start_label, data.screen], foe)
	if _foe_choice.item_count == 0:
		_foe_choice.add_item("no creature runs this line", -1)
		_foe_choice.disabled = true
	else:
		_foe_choice.disabled = false
		var at := _foe_choice.get_item_index(kept)
		_foe_choice.select(maxi(at, 0))


## Shows a message under the problems (the way the commands do), until the next command.
func _note(message: String) -> void:
	if _current != null:
		_current.notes = [message]
		_show_problems(_current)


## The N of "line N: ..."; 0 when the message does not start that way.
func _line_of(message: String) -> int:
	return message.get_slice(":", 0).trim_prefix("line ").to_int()


# =============================================================================
# Signals
# =============================================================================

func _on_text_changed(doc: Document) -> void:
	_refresh_state(doc)
	if is_inside_tree():
		_check_timer.start()


## Ctrl+S (Cmd+S on a Mac) saves, wherever the caret is in the editor; Ctrl+K comments
## lines in or out; F2 renames a label; Ctrl+R runs the sandbox.
func _on_edit_input(event: InputEvent, doc: Document) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_K \
			and key.is_command_or_control_pressed() and not key.shift_pressed and not key.alt_pressed:
		(doc.edit as FoeCodeEdit).toggle_comment()
		doc.edit.accept_event()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F2 \
			and not key.is_command_or_control_pressed() and not key.shift_pressed and not key.alt_pressed:
		begin_rename(doc)
		doc.edit.accept_event()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R \
			and key.is_command_or_control_pressed() and not key.shift_pressed and not key.alt_pressed:
		_on_run_pressed()
		doc.edit.accept_event()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_S \
			and key.is_command_or_control_pressed() and not key.shift_pressed and not key.alt_pressed:
		save_document(doc)
		doc.edit.accept_event()


## Live check of the name typed in the rename dialog.
func _on_rename_text_changed(text: String) -> void:
	var problem := rename_problem(_rename_doc, _rename_old, text.strip_edges())
	_rename_dialog.get_ok_button().disabled = not problem.is_empty()
	_rename_message.text = problem if not problem.is_empty() else "Every use of the label in this file is renamed too."


func _on_rename_confirmed() -> void:
	var problem := rename_label(_rename_doc, _rename_old, _rename_edit.text)
	if not problem.is_empty():
		_rename_doc.notes = [problem]
		_show_problems(_rename_doc)
	if _rename_doc.edit.is_inside_tree():
		_rename_doc.edit.grab_focus()


func _on_run_pressed() -> void:
	run_in_sandbox(_foe_choice.get_selected_id() if _foe_choice.selected >= 0 else -1, _pause_check.button_pressed)


func _on_close_pressed() -> void:
	if _current == null:
		return
	if _current.is_dirty():
		_close_dialog.dialog_text = "%s has unsaved changes. Close it and lose them?" % _current.path().get_file()
		_close_dialog.popup_centered()
	else:
		close_document(_current)
