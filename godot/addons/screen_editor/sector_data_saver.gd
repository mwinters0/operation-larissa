@tool
class_name SectorDataSaver
extends ResourceFormatSaver
## Makes Godot's own `ResourceSaver` write a `SectorData` into `sector_NN.tres` by changing only the lines that changed.
##
## Teaches: the same front-of-the-queue `ResourceFormatSaver` as `ScreenDataSaver` (read that header first), for a file that
## is too big and too hand-shaped to rewrite from scratch: `sector_NN.tres` is about 400 lines of importer text, and the
## 12 screens, the script and the creatures are separate things. So this saver PATCHES the file on disk instead of writing a
## new one: it loads the file as it is (`disk`), compares the `SectorData` it was asked to save (`wanted`) with it, and
## replaces just the lines of the properties that changed (`ScreenFile.sector_patch`):
##   - the respawn point (`start_pos`, `start_frame`) and the four neighbour tables,
##   - every creature property (the Inspector is where a designer renames `start_label`, `hit_label`, `ink_label`, see
##     docs/create/FOE_SCRIPTING.md, or moves a creature),
##   - a piece's `screen` and `pos` (the screen editor moves these),
##   - the music name, and the NUMBER of pieces and creatures (the Sector Inspector adds and removes them: `SectorLists` writes the
##     whole list again and `foe_script_base` follows the count, see `ScreenFile.sector_patch`).
## Any OTHER difference (the zone, a changed `index` ...) is REFUSED with
## a message that names the property: the file stays as it is. A change is never dropped without a word and never written in
## Godot's format. The saver reports OK to the engine in both cases, see `ScreenFile.refuse` for why (the next saver in line
## is Godot's own, which would write the file in its format).
##
## An unchanged sector is not written at all. Only the editor saves these files, so the plugin registers the saver.


func _recognize(resource: Resource) -> bool:
	return resource is SectorData


func _recognize_path(_resource: Resource, path: String) -> bool:
	return path.get_extension().to_lower() == "tres"


func _get_recognized_extensions(resource: Resource) -> PackedStringArray:
	return PackedStringArray(["tres"]) if resource is SectorData else PackedStringArray()


func _save(resource: Resource, path: String, _flags: int) -> Error:
	if not FileAccess.file_exists(path):
		ScreenFile.refuse(path, "a sector file can only be changed, not created here (copy an existing sector file, or run the importer)")
		return OK
	# A fresh copy of the file as it is on disk (not the cached object: that one may be the very resource being saved).
	var disk := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	if disk == null:
		ScreenFile.refuse(path, "the file on disk could not be loaded as a SectorData")
		return OK
	var patched := ScreenFile.sector_patch(FileAccess.get_file_as_string(path), disk, resource as SectorData)
	if not (patched.error as String).is_empty():
		ScreenFile.refuse(path, patched.error)
		return OK
	ScreenFile.last_refusal = ""
	return ScreenFile.write_if_changed(path, patched.text)
