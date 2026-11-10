@tool
class_name PackExportFilter
extends EditorExportPlugin
## Decides which pack folders an export carries. The export presets' filters can say "exclude `packs/dev/*`" but not "exclude every pack": a pack of the project that the
## preset does not know (a copy of dev you are making, a friend's pack) would go in. So this plugin skips the files: an exported game carries no pack at all, whatever
## folders are in `res://packs/` on this machine. A pack reaches a game as a pack file (`<id>.larissa`) next to it or in `user://packs/` (`PackExport.complete` with `archive`; `Packs` reads a pack file where it lies),
## never inside it.
##
## Teaches: an export plugin sees every file that is about to go in and can say `skip()` for it. The same decision as a pure
## function (`carries`) so a test can try it without an export.

const PACKS_DIR := "res://packs/"


func _get_name() -> String:
	return "PackExportFilter"


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if not carries(path):
		skip()


## Does an export carry the file `path`?
static func carries(path: String) -> bool:
	return not path.begins_with(PACKS_DIR)
