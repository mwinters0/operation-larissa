@tool
class_name ScreenEditorFoeJump
extends RefCounted
## "Jump to the script labels": from a creature on the screen to the line of its entry point in the Foe Script screen.
##
## Teaches: one editor plugin using another one without changing it. The Foe Script screen (`addons/foe_script_editor/`) is a
## main screen whose `_handles` accepts a `FoeScript`; `EditorInterface.edit_resource(script)` therefore opens it, exactly like
## double-clicking the `.foe` file. Its panel (`FoeEditorPanel`) is an ordinary `Control` child of the editor's main screen, so
## we find it there and use what it already offers (`open_script`, the document's `CodeEdit`). All the knowledge about where a
## label is lives in `FoeLineInfo.label_definitions`, the same function the panel's own commands use.

## The 0-based line on which `label` is defined in `source` (the text of a `.foe` file), or -1 when it is not defined.
static func line_of_label(source: String, label: String) -> int:
	var found: Array = FoeLineInfo.label_definitions(source.split("\n")).get(label, [])
	return -1 if found.is_empty() else found[0]


## Every label defined in `source`, in the order of the file.
static func labels_of(source: String) -> PackedStringArray:
	var found := PackedStringArray()
	if source.is_empty():
		return found
	var definitions := FoeLineInfo.label_definitions(source.split("\n"))
	var keys: Array = definitions.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return definitions[a][0] < definitions[b][0])
	for label: String in keys:
		found.append(label)
	return found


## The Foe Script panel of the running editor, or null (no editor, or the plugin is off).
static func find_panel() -> FoeEditorPanel:
	if not Engine.is_editor_hint():
		return null
	for child in EditorInterface.get_editor_main_screen().get_children():
		if child is FoeEditorPanel:
			return child
	return null


## Opens `script` in `panel` and puts the caret on the line of `label`. Returns "" when it worked, else what went wrong
## (the label is not in the script, the script has no file ...). Needs no editor, so a test can hand it a panel of its own.
static func show_label(panel: FoeEditorPanel, script: FoeScript, label: String) -> String:
	if script == null or script.resource_path.is_empty():
		return "this sector has no creature script file"
	if label.is_empty():
		return "this entry point has no label"
	var doc := panel.open_script(script)
	if doc == null:
		return "%s could not be opened" % script.resource_path
	var line := line_of_label(doc.edit.text, label)
	if line < 0:
		return "'%s' is not a label of %s" % [label, script.resource_path.get_file()]
	doc.edit.set_caret_line(line)
	doc.edit.set_caret_column(0)
	doc.edit.center_viewport_to_caret()
	if doc.edit.is_inside_tree():
		doc.edit.grab_focus()
	return ""


## In the editor: switches to the Foe Script screen with `script` open and the caret on `label`. "" or the reason it can not.
static func open_in_editor(script: FoeScript, label: String) -> String:
	if script == null or script.resource_path.is_empty():
		return "this sector has no creature script file"
	if not Engine.is_editor_hint():
		return "the Foe Script screen only exists in the Godot editor"
	var cached := ResourceLoader.load(script.resource_path) as FoeScript         # the editor's own copy, not a private one
	EditorInterface.edit_resource(cached)
	var panel := find_panel()
	if panel == null:
		return "the Foe Script plugin is not enabled (Project > Project Settings > Plugins)"
	return show_label(panel, cached, label)
