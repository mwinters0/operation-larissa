@tool
class_name SectorEditorPlugin
extends EditorPlugin
## The Sector Inspector: one inspector plugin, and the "New sector..." menu item.
##
## Teaches: the smallest useful editor plugin. Not a main screen, not a dock: the sector's data is a Resource, the Inspector is
## where Godot shows a Resource, so the quiet, ordinary place for friendly controls is an `EditorInspectorPlugin`
## (`SectorInspectorPlugin`). Select `sector_NN.tres` in the FileSystem dock (or click a sector anywhere a resource is listed) and the
## panel appears above the properties. The panel's changes are undoable through this plugin's `get_undo_redo()` and are written by
## `SectorDataSaver` when the resource is saved (Ctrl+S); that saver is registered by the Screen Editor plugin, which must be enabled
## too. (Why a separate plugin: the screen editor is about ONE screen; the sector is the level above.)
##
## The menu item is the way to a NEW sector: Project > Tools > "New sector..." opens `NewSectorDialog`, which asks for a start
## (the empty template or a copy of a sector) and a number, and `SectorFactory` writes the files. The editor is told to look at the files
## (`scan`) and the new sector's file is selected in the FileSystem dock and shown in the Inspector, where this plugin's panel appears.

const MENU_ITEM := "New sector..."

var _inspector_plugin: SectorInspectorPlugin
var _dialog: NewSectorDialog


func _enter_tree() -> void:
	_inspector_plugin = SectorInspectorPlugin.new()
	_inspector_plugin.plugin = self
	add_inspector_plugin(_inspector_plugin)
	_dialog = NewSectorDialog.new()
	_dialog.sector_made.connect(_show_new_sector)
	EditorInterface.get_base_control().add_child(_dialog)
	add_tool_menu_item(MENU_ITEM, _open_dialog)


func _exit_tree() -> void:
	remove_inspector_plugin(_inspector_plugin)
	remove_tool_menu_item(MENU_ITEM)
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null


func _open_dialog() -> void:
	_dialog.open(_sector_being_looked_at())


## The sector whose file is shown in the Inspector (the sector, one of its screens, its script), or -1: the window offers a copy of it first.
func _sector_being_looked_at() -> int:
	var object := EditorInterface.get_inspector().get_edited_object()
	if object is Resource and not (object as Resource).resource_path.is_empty():
		return Catalog.sector_of_path((object as Resource).resource_path)
	return -1


## The new files are on disk: let the editor see them, then select the sector file and show it in the Inspector.
func _show_new_sector(made: SectorFactory.Made) -> void:
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.get_editor_toaster().push_toast("Made sector %d: %s" % [made.index, made.path])
	var sector := ResourceLoader.load(made.path, "", ResourceLoader.CACHE_MODE_REUSE)
	if sector != null:
		EditorInterface.select_file(made.path)
		EditorInterface.edit_resource(sector)
