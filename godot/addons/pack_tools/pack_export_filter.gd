@tool
class_name PackExportFilter
extends EditorExportPlugin
## Decides which pack folders and which skins an export carries. The export presets' filters can say "exclude `packs/dev/*`" but not "exclude every pack": a pack of the project that the
## preset does not know (a copy of dev you are making, a friend's pack) would go in. So this plugin skips the files: an exported game carries no pack at all, whatever
## folders are in `res://packs/` on this machine. A pack reaches a game as a pack file (`<id>.larissa`) next to it or in `user://packs/` (`PackExport.complete` with `archive`; `Packs` reads a pack file where it lies),
## never inside it. Of the project's skins (`res://skins/`) a game carries the original one, which the game cannot run without (`SkinChoice.original`, the skin every run starts with); the others are skins for developing and demonstration
## (`creatures`: 3D models and an animation tree, which no pack can bring) and stay in the project. A skin for players is a skin pack (`docs/create/CONTENT.md`, "Skins and packs").
##
## Teaches: an export plugin sees every file that is about to go in and can say `skip()` for it. The same decision as a pure
## function (`carries`) so a test can try it without an export.

const PACKS_DIR := "res://packs/"
const SKINS_DIR := "res://skins/"
## The one project skin a game carries (`SkinChoice.ORIGINAL`).
const SHIPPED_SKIN := "res://skins/original/"


func _get_name() -> String:
	return "PackExportFilter"


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if not carries(path):
		skip()


## Does an export carry the file `path`? Not a pack's, not a project skin's but the original's.
static func carries(path: String) -> bool:
	if path.begins_with(SKINS_DIR):
		return path.begins_with(SHIPPED_SKIN)
	return not path.begins_with(PACKS_DIR)
