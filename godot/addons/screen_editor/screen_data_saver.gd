@tool
class_name ScreenDataSaver
extends ResourceFormatSaver
## Makes Godot's own `ResourceSaver` write a `ScreenData` into `screen_MM.tres` in the importer's text, byte for byte.
##
## Teaches: `ResourceFormatSaver` at the FRONT of the queue, and why. Godot's editor re-saves every resource that is "edited"
## whenever you press Ctrl+S or Save All (`EditorNode::_save_external_resources`, editor_node.cpp), and loading a `.tres` that has
## sub resources leaves those flagged "edited" (`Object::set` marks the object, the loader only clears the flag of the MAIN
## resource), so after you opened any screen in the editor, the next Ctrl+S rewrote all twelve screens of the sector in
## Godot's own text format: `format=4`, a `uid=` in the header, `flag = false` left out, ... (docs/create/SCREEN_EDITOR.md, "Ctrl+S and Save All are safe").
## A `ResourceFormatSaver` is how a resource type chooses how it is written, as `FoeScriptSaver` does for `.foe`. But
## `class_name ... extends ResourceFormatSaver` alone is NOT enough for a `.tres`: the engine appends a saver found by its
## class name AFTER its own text saver (`ResourceSaver::add_custom_resource_format_saver`, core/io/resource_saver.cpp), the
## text saver recognizes every `.tres`, and the first saver that does is used. This one is therefore registered by hand
## with `ResourceSaver.add_resource_format_saver(saver, true)`: the `true` puts it first. `ScreenEditorPlugin` does that.
##
## What it writes is `ScreenFile.screen_text`, the same text the screen editor writes, so saving a screen that did not
## change leaves the file exactly as it is (and does not even touch it). A screen that cannot be stored as an original
## record (`ScreenData.validate` finds a problem) is REFUSED: the problem is logged and shown in the editor, the file stays as
## it was. The saver still reports OK to the engine, because `ResourceSaver.save` hands a failed save to the next saver
## and that is Godot's text saver, which would write the file in Godot's format. See `ScreenFile.refuse`.
##
## Only the editor saves these files (the game only reads them), so the saver does not need to exist outside the plugin.


func _recognize(resource: Resource) -> bool:
	return resource is ScreenData


func _recognize_path(_resource: Resource, path: String) -> bool:
	return path.get_extension().to_lower() == "tres"           # a binary `.res` stays Godot's business


func _get_recognized_extensions(resource: Resource) -> PackedStringArray:
	return PackedStringArray(["tres"]) if resource is ScreenData else PackedStringArray()


func _save(resource: Resource, path: String, _flags: int) -> Error:
	var screen := resource as ScreenData
	var problems := screen.validate()
	if not problems.is_empty():
		ScreenFile.refuse(path, "this screen cannot be stored as an original screen record: " + problems[0] + (" (and %d more)" % (problems.size() - 1) if problems.size() > 1 else ""))
		return OK
	ScreenFile.last_refusal = ""
	return ScreenFile.write_if_changed(path, ScreenFile.screen_text(screen))
