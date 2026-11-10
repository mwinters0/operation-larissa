@tool
class_name FoeScript
extends Resource
## One sector's creature script: just the text, loaded from a `.foe` file.
##
## Teaches: a custom Resource type for a plain-text file. The text lives in
## `data/sectors/sector_NN/sector_NN.foe` (readable, diffable, editable in Godot's script editor),
## `FoeScriptLoader` and `FoeScriptSaver` teach the engine how to read and write that
## file, and `SectorData.foe_script` refers to it like to any other Resource. The
## language is explained in docs/create/FOE_SCRIPTING.md. `@tool` makes the script run in the
## editor too, which loading a `.foe` there needs.

## The script text, exactly as it is in the file (UTF-8, no changes at all). Assigning
## it emits `changed`; `SectorData` compiles again on next use because its compiled script is keyed by this text. It is exported so that a copy of a script that
## is not a file (one a sector in the data form made from its `.foe` text) keeps its text: `duplicate_deep` copies the stored properties of a resource that has no file.
@export_multiline var source: String = "":
	set(value):
		if value == source:
			return
		source = value
		emit_changed()


## Reads the file again (for the editor, after the file was changed on disk). Does
## nothing for a FoeScript that was not loaded from a file.
func reload() -> void:
	if not resource_path.is_empty():
		source = FileAccess.get_file_as_string(resource_path)
