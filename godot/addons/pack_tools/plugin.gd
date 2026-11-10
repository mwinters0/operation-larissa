@tool
extends EditorPlugin
## Adds Project > Tools > "Export pack...", "Check pack..." and "New pack from dev..." to the editor: one window (`PackToolDialog`) that exports a campaign or a complete pack in the data form,
## checks any pack, or starts a pack of your own by copying one (`PackCopy`), and shows what the tool printed. It also registers the export plugin (`PackExportFilter`)
## that keeps every pack folder out of an exported game.
##
## Teaches: an editor plugin that is only a front for a command line tool. The window does not export anything itself: it starts this same Godot on
## `res://src/packs/pack_tool.tscn` in a process of its own (`PackToolDialog.arguments`) and shows what that prints. So the editor, a terminal and the
## tests all run the same code (`PackExport`, `PackCheck`), and an export never depends on what the editor happens to have loaded (the editor runs scripts
## without `@tool` as placeholders, which a tool made of plain objects would trip over).

const EXPORT_ITEM := "Export pack..."
const CHECK_ITEM := "Check pack..."
const NEW_ITEM := "New pack from dev..."

var _dialog: PackToolDialog
var _export_filter: PackExportFilter


func _enter_tree() -> void:
	_dialog = PackToolDialog.new()
	EditorInterface.get_base_control().add_child(_dialog)
	add_tool_menu_item(EXPORT_ITEM, func() -> void: _dialog.open(PackToolDialog.Job.EXPORT_CAMPAIGN))
	add_tool_menu_item(CHECK_ITEM, func() -> void: _dialog.open(PackToolDialog.Job.CHECK))
	add_tool_menu_item(NEW_ITEM, func() -> void: _dialog.open(PackToolDialog.Job.NEW_PACK))
	_export_filter = PackExportFilter.new()
	add_export_plugin(_export_filter)


func _exit_tree() -> void:
	remove_tool_menu_item(EXPORT_ITEM)
	remove_tool_menu_item(CHECK_ITEM)
	remove_tool_menu_item(NEW_ITEM)
	if _export_filter != null:
		remove_export_plugin(_export_filter)
		_export_filter = null
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null
