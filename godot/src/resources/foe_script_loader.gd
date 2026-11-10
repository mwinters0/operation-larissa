@tool
class_name FoeScriptLoader
extends ResourceFormatLoader
## Teaches `load("res://packs/legacy/data/sectors/sector_00/sector_00.foe")` to return a FoeScript.
##
## Teaches: `ResourceFormatLoader`. A script with a `class_name` that extends it is
## registered by the engine on its own (no autoload, no plugin), so a new file format
## is a few small overrides. The editor and the exported game both find it.
## `@tool` is required: without it the editor only keeps an empty stand-in of the
## script, the loader answers nothing and every sector fails to open in the editor.

const EXTENSION := "foe"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray([EXTENSION])


func _handles_type(type: StringName) -> bool:
	return type == &"Resource"


## Empty on purpose: no built-in class stands for a creature script, the script class
## named below (FoeScript) does. Loading works as usual, `load()` returns a FoeScript, and
## the editor shows it in the "Foe Script" screen (see addons/foe_script_editor).
func _get_resource_type(_path: String) -> String:
	return ""


func _get_resource_script_class(path: String) -> String:
	return "FoeScript" if path.get_extension() == EXTENSION else ""


func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	# get_file_as_string reads the bytes as UTF-8 without touching the line endings
	# or adding a final newline: the text is the file, and the file is the text.
	var text := FileAccess.get_file_as_string(path)
	if FileAccess.get_open_error() != OK:
		return FileAccess.get_open_error()
	var script := FoeScript.new()
	script.source = text
	return script
