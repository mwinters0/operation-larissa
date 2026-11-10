@tool
class_name ScreenEditorPlugin
extends EditorPlugin
## Opens the screen editor: a menu item, a button in the Inspector, and a double-click on a screen file.
##
## Teaches: `EditorPlugin`, the quiet way. This is NOT a main-screen plugin like the Foe Script editor: the TileMap panel only
## works on a `TileMapLayer` in a scene open in the 2D editor, so the screen is edited as a scene (`ScreenEditor`) and the plugin's
## job is to open that scene and to save the screen when the scene is saved:
##   - `add_tool_menu_item` adds Project > Tools > "Edit screen..." (a small dialog asks for the sector and the screen) and "Playtest screen...".
##   - `ScreenInspectorPlugin` adds an "Open in Screen Editor" button above the properties of a `ScreenData`.
##   - `_handles` / `_edit`: the editor asks every plugin `_handles(object)` for the object it is about to show, and calls
##     `_edit(object)` on the ones that say yes. Double-clicking `screen_MM.tres` in the FileSystem dock shows the resource
##     in the Inspector, and `_edit` then opens the scene. We open it only when the object is the very file selected in the
##     FileSystem dock (`EditorInterface.get_current_path()`), so looking at a screen another way, for example through the `Screens` list of
##     a sector, does not jump to another scene.
##   - `_save_external_data` is called by the editor whenever it saves a scene (Ctrl+S) or everything, so Ctrl+S in the
##     screen scene saves the screen file too. `_get_unsaved_status` lists unsaved screens when the editor closes, `_build`
##     saves them before a game is run (the game is another process that reads the files).
##   - `ScreenDataSaver` and `SectorDataSaver` are registered at the FRONT of `ResourceSaver`'s list, so that when Godot itself
##     saves a `screen_MM.tres` or `sector_NN.tres` (Ctrl+S saves every resource the editor believes was edited, and it believes
##     that of every screen it has loaded) the files keep the importer's text instead of Godot's. See `_register_savers`.
## The scene files live in `res://screen_editor_work/` (not in git): one tiny holder per screen, see `ScreenEditor`.

const MENU_ITEM := "Edit screen..."
const PLAYTEST_ITEM := "Playtest screen..."
const WORK_DIR := "res://screen_editor_work"
const TEMPLATE := "res://addons/screen_editor/screen_editor.tscn"
## `res://packs/legacy/data/sectors/sector_03/screen_05.tres` (the legacy pack's) or `res://data/sectors/sector_40/screen_05.tres` (a designer's)
const SCREEN_PATTERN := "^res://(?:packs/[a-z][a-z0-9_]*/)?data/sectors/sector_(\\d{2,})/screen_(\\d\\d)\\.tres$"

var _inspector_plugin: ScreenInspectorPlugin
var _dialog: ConfirmationDialog
var _sector_box: SpinBox
var _screen_box: SpinBox
var _last_edit_time := -1000
var _savers: Array[ResourceFormatSaver] = []
var _register_queued := false


func _enter_tree() -> void:
	add_tool_menu_item(MENU_ITEM, _show_dialog)
	add_tool_menu_item(PLAYTEST_ITEM, _playtest_current)
	_inspector_plugin = ScreenInspectorPlugin.new()
	_inspector_plugin.plugin = self
	add_inspector_plugin(_inspector_plugin)
	_make_dialog()
	_register_savers()
	EditorInterface.get_resource_filesystem().script_classes_updated.connect(_on_script_classes_updated)


func _exit_tree() -> void:
	EditorInterface.get_resource_filesystem().script_classes_updated.disconnect(_on_script_classes_updated)
	_unregister_savers()
	remove_tool_menu_item(MENU_ITEM)
	remove_tool_menu_item(PLAYTEST_ITEM)
	remove_inspector_plugin(_inspector_plugin)
	_dialog.queue_free()


# --- the savers ---------------------------------------------------------------------------------------------------------------

## Puts the two savers first in line. `add_resource_format_saver(saver, true)`: the `true` is "at the front". Without it the
## engine would ask its own text saver first, and that one accepts every `.tres` (see `ScreenDataSaver`).
func _register_savers() -> void:
	_savers = [ScreenDataSaver.new(), SectorDataSaver.new()]
	for saver in _savers:
		ResourceSaver.add_resource_format_saver(saver, true)


func _unregister_savers() -> void:
	for saver in _savers:
		ResourceSaver.remove_resource_format_saver(saver)
	_savers.clear()


## The editor updates its list of `class_name` scripts whenever one is added or changed, and right after the signal it
## throws away EVERY saver that has a script (`ResourceSaver.remove_custom_savers`, called in
## `EditorFileSystem::_update_script_classes`, editor_file_system.cpp) and registers the `class_name` ones again, at the
## back. Ours would silently be gone. The signal comes BEFORE that clean-up, so take ours out ourselves while they are still
## there (`_unregister_savers`: from then on `_savers` is empty and says that none is registered, so leaving the editor before the
## next registration has nothing to remove, and `ResourceSaver.remove_resource_format_saver` is never asked for a saver it does not
## hold), and register again once the clean-up is over (`call_deferred` runs when the editor has finished what it is doing).
func _on_script_classes_updated() -> void:
	_unregister_savers()
	if not _register_queued:
		_register_queued = true
		_register_savers_when_idle.call_deferred()


## The deferred registration. Not when the plugin left the tree in the meantime (it was disabled, or the editor is closing): the
## savers are the plugin's, they live as long as it does.
func _register_savers_when_idle() -> void:
	_register_queued = false
	if is_inside_tree():
		_register_savers()


## (sector, screen) of a `ScreenData` that was loaded from `sector_NN/screen_MM.tres` of the game's sector folders, else (-1, -1).
static func screen_of(object: Object) -> Vector2i:
	var resource := object as Resource
	if resource == null:
		return Vector2i(-1, -1)
	var pattern := RegEx.create_from_string(SCREEN_PATTERN)
	var found := pattern.search(resource.resource_path)
	if found == null:
		return Vector2i(-1, -1)
	return Vector2i(found.get_string(1).to_int(), found.get_string(2).to_int())


# --- opening ---------------------------------------------------------------------------------------------------------------

func _handles(object: Object) -> bool:
	return object is ScreenData and screen_of(object).x >= 0


func _edit(object: Object) -> void:
	if object == null:
		return
	var where := screen_of(object)
	var now := Time.get_ticks_msec()
	if where.x < 0 or (object as Resource).resource_path != EditorInterface.get_current_path() or now - _last_edit_time < 1000:
		return
	_last_edit_time = now
	open_screen.call_deferred(where.x, where.y)         # not while the editor is still busy showing the resource


## Opens (making it first if needed) the scene that holds screen `screen` of sector `sector`.
func open_screen(sector: int, screen: int) -> void:
	open_screen_in_editor(sector, screen)


## The same without a plugin instance, for other editor tools (the sector overview's "Open screen" calls it): the scene folder and the
## template stay in this one place.
static func open_screen_in_editor(sector: int, screen: int) -> void:
	var path := "%s/sector_%02d_screen_%02d.tscn" % [WORK_DIR, sector, screen]
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
		var root := (load(TEMPLATE) as PackedScene).instantiate() as ScreenEditor
		root.sector = sector
		root.screen = screen
		root.name = "Screen_%02d_%02d" % [sector, screen]
		var packed := PackedScene.new()
		packed.pack(root)
		var error := ResourceSaver.save(packed, path)
		root.free()
		if error != OK:
			push_error("Screen editor: can not write %s (error %d)" % [path, error])
			return
		EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	EditorInterface.set_main_screen_editor("2D")


func _make_dialog() -> void:
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Edit screen"
	_dialog.ok_button_text = "Open"
	var row := HBoxContainer.new()
	_sector_box = _spin_box(row, "Sector", sector_limit())
	_screen_box = _spin_box(row, "Screen", 11)
	_dialog.add_child(row)
	_dialog.confirmed.connect(func() -> void: open_screen(int(_sector_box.value), int(_screen_box.value)))
	EditorInterface.get_base_control().add_child(_dialog)


## The highest sector number the dialog offers: the last sector there is (the original's 0-31 and every sector made since, `Catalog.sector_ids`).
static func sector_limit() -> int:
	return maxi(Catalog.last_sector(), 0)


func _spin_box(row: HBoxContainer, label_text: String, maximum: int) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var box := SpinBox.new()
	box.max_value = maximum
	row.add_child(box)
	return box


func _show_dialog() -> void:
	_sector_box.max_value = sector_limit()               # (a sector made since the editor started is offered too)
	var current := EditorInterface.get_edited_scene_root() as ScreenEditor        # start from the screen being edited
	if current != null:
		_sector_box.value = current.sector
		_screen_box.value = current.screen
	_dialog.popup_centered()


## Project > Tools > "Playtest screen...": the same as the button of the `ScreenEditor` root, for the screen in the open scene.
func _playtest_current() -> void:
	var current := EditorInterface.get_edited_scene_root() as ScreenEditor
	if current == null:
		EditorInterface.get_editor_toaster().push_toast("Playtest: open a screen first (Project > Tools > Edit screen...).", EditorToaster.SEVERITY_WARNING)
		return
	current.playtest()


# --- saving ------------------------------------------------------------------------------------------------------------------

func _open_editors() -> Array[ScreenEditor]:
	var found: Array[ScreenEditor] = []
	for root in EditorInterface.get_open_scene_roots():
		if root is ScreenEditor:
			found.append(root)
	return found


## The editor calls this whenever it saves (Ctrl+S saves the current scene, then every plugin's external data).
func _save_external_data() -> void:
	for editor in _open_editors():
		if editor.is_dirty():
			editor.save_screen()


## The game is another process and reads the files, so unsaved screens are written first. A screen with problems
## stays as it is on disk (the toast says so); that does not stop the game from starting.
func _build() -> bool:
	_save_external_data()
	return true


func _get_unsaved_status(for_scene: String) -> String:
	var lines: Array[String] = []
	for editor in _open_editors():
		if (for_scene.is_empty() or editor.scene_file_path == for_scene) and editor.is_dirty():
			lines.append("Sector %d, screen %d" % [editor.sector, editor.screen])
	if lines.is_empty():
		return ""
	return "Screens with changes not yet written to their .tres files:\n" + "\n".join(lines)
