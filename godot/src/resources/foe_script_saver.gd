@tool
class_name FoeScriptSaver
extends ResourceFormatSaver
## Teaches `ResourceSaver.save(foe_script, "res://...foe")` to write the plain text.
##
## Teaches: `ResourceFormatSaver`, the other half of `FoeScriptLoader` (`@tool` for the
## same reason). Saving then loading gives back the same text, byte for byte.


func _get_recognized_extensions(resource: Resource) -> PackedStringArray:
	return PackedStringArray([FoeScriptLoader.EXTENSION]) if resource is FoeScript else PackedStringArray()


func _recognize(resource: Resource) -> bool:
	return resource is FoeScript


func _save(resource: Resource, path: String, _flags: int) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	# store_string writes the UTF-8 bytes as they are: no BOM, no added newline.
	file.store_string((resource as FoeScript).source)
	return file.get_error()
