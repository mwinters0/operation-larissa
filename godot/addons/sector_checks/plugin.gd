@tool
extends EditorPlugin
## Adds Project > Tools > "Check sector..." to the editor: a window that runs the what-changed report and the playability checks of a
## sector and shows them.
##
## Teaches: the smallest useful `EditorPlugin`. It does not edit anything and has no screen of its own: it adds one menu item
## (`add_tool_menu_item`, which puts it under Project > Tools) and, when the item is chosen, shows a window (`SectorCheckDialog`). The
## reports themselves are plain objects in `res://src/checks/` (`SectorChanges`, `SectorChecks`, `SectorReport`), the same code the
## command line tool runs (`res://src/checks/check_sector.tscn`) and the tests exercise: a plugin is the thin part that puts them in the
## editor.
##
## The sector that is selected first is the one being looked at: a `sector_NN.tres` or one of its screens or the creature script
## shown in the Inspector, else the one the window showed last.

const MENU_ITEM := "Check sector..."

var _dialog: SectorCheckDialog


func _enter_tree() -> void:
	_dialog = SectorCheckDialog.new()
	EditorInterface.get_base_control().add_child(_dialog)
	add_tool_menu_item(MENU_ITEM, _show_dialog)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null


func _show_dialog() -> void:
	_dialog.open(_sector_being_looked_at())


## The number of the sector whose file is shown in the Inspector (the sector, one of its screens, its script), or -1.
func _sector_being_looked_at() -> int:
	var object := EditorInterface.get_inspector().get_edited_object()
	if object is Resource and not (object as Resource).resource_path.is_empty():
		return SectorCheckDialog.sector_of_path((object as Resource).resource_path)
	return -1
