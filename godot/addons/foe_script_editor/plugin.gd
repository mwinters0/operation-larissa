@tool
extends EditorPlugin
## Gives the `.foe` creature scripts their own editor: a "Foe Script" screen in the main
## screen bar, next to 2D, 3D, Script and AssetLib.
##
## Teaches: `EditorPlugin`. A plugin is a `@tool` script that runs INSIDE the editor
## (never in the exported game) and can change how the editor behaves. This one is a MAIN
## SCREEN plugin:
##   - `_has_main_screen` / `_get_plugin_name` / `_get_plugin_icon` add the tab, and
##     `_make_visible` is called when the user switches to it or away from it;
##   - `_handles` says which objects it can edit (a FoeScript) and `_edit` receives one:
##     that is what happens when you double-click a `.foe` in the FileSystem dock, or
##     click a sector's `Foe Script` property in the Inspector (the editor then also
##     switches to this screen by itself);
##   - `_save_external_data`, `_build` and `_get_unsaved_status` tie the panel into the
##     editor's own saving: Save All, running the game, and closing the editor (which asks
##     first when a script has unsaved changes);
##   - the `filesystem_changed` signal tells us a file changed on disk.
## Two more parts belong to debugging a script. The panel's "Run in sandbox" asks for a run (`sandbox_requested`) and this
## plugin starts it: `EditorInterface.play_custom_scene` takes no arguments, so the words for the sandbox (`--sector= --foe=`)
## travel in an environment variable that the game process inherits (`FoeSandbox.ARGS_ENV`). And an `EditorDebuggerPlugin`
## (`FoeDebuggerPlugin`, added with `add_debugger_plugin`) receives the lines the paused sandbox says its creatures are on.
## The text editor itself is `FoeEditorPanel` (which also has the Rename label command, F2, and
## the "Store names & comments" button for the annotation store, see `FoeAnnotations`), the
## colours are `FoeSyntaxHighlighter`. Neither command runs by itself on a save.
## Why not the built-in script editor? `EditorInterface.edit_script` only takes a `Script`;
## a `.foe` is a plain Resource, and the engine offers no way to put one into the script
## editor. The running game does not need this plugin: it is a new process that loads the
## files from disk, which is why the panel saves to disk before the game starts.

const SCREEN_NAME := "Foe Script"

var _panel: FoeEditorPanel
var _debugger: FoeDebuggerPlugin
var _modified := {}                 # path -> modification time last seen


func _enter_tree() -> void:
	_panel = FoeEditorPanel.new()
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_panel.sandbox_requested.connect(_on_sandbox_requested)
	_debugger = FoeDebuggerPlugin.new()
	_debugger.relay.lines_reported.connect(_panel.show_running_lines)
	_debugger.relay.run_ended.connect(_panel.clear_running_lines)
	add_debugger_plugin(_debugger)
	_make_visible(false)
	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.filesystem_changed.connect(_on_filesystem_changed)
	_on_filesystem_changed()


func _exit_tree() -> void:
	if _debugger != null:
		remove_debugger_plugin(_debugger)
		_debugger = null
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem.filesystem_changed.disconnect(_on_filesystem_changed)
	if _panel != null:
		_panel.queue_free()
		_panel = null


# --- the main screen ---------------------------------------------------------

func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return SCREEN_NAME


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Script", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible


# --- editing a FoeScript -----------------------------------------------------

func _handles(object: Object) -> bool:
	return object is FoeScript


## The editor has already switched to our screen when it calls this (it does so for any
## main screen plugin whose `_handles` accepts the object; it calls `_edit(null)` on the
## screen it leaves), so there is no need for `EditorInterface.set_main_screen_editor`.
func _edit(object: Object) -> void:
	if object is FoeScript:
		_panel.open_script(object)


# --- saving ------------------------------------------------------------------

## Asked by the editor when it saves "everything" (Save All, closing with "Save").
func _save_external_data() -> void:
	_panel.save_all()


## Asked before the game runs. The game is a separate process that reads the files from
## disk, so unsaved foe text would be missing from it: save it first. Returning false
## would cancel the run.
func _build() -> bool:
	return _panel.save_all() == OK


## Asked when the editor is about to close; a non-empty answer opens a confirmation dialog.
## (`for_scene` is empty when the whole editor closes; a closing scene tab is not our business.)
func _get_unsaved_status(for_scene: String) -> String:
	if not for_scene.is_empty() or not _panel.has_unsaved():
		return ""
	return "Foe scripts with unsaved changes:\n" + "\n".join(_panel.unsaved_paths())


## Asked when the editor wants every editor to settle its state (before it saves a scene).
func _apply_changes() -> void:
	_panel.apply_to_scripts()


# --- running the sandbox --------------------------------------------------------

## The panel saved the text and chose the sector and the creature; start the game on them. The environment variable is set only
## for the moment the game process is created (it inherits it), then taken away so that a later hand-started sandbox does not
## repeat this run. (`play_custom_scene` also calls `_build`, which saves again; nothing is left unsaved.)
func _on_sandbox_requested(arguments: String) -> void:
	_panel.clear_running_lines()
	OS.set_environment(FoeSandbox.ARGS_ENV, arguments)
	EditorInterface.play_custom_scene(FoeEditorPanel.SANDBOX_SCENE)
	get_tree().create_timer(2.0).timeout.connect(func(): OS.unset_environment(FoeSandbox.ARGS_ENV))


# --- files changed on disk ---------------------------------------------------

## Opened files are compared by the panel (it keeps the unsaved edits safe). A FoeScript
## the editor holds without having it open in the panel, such as the one a sector shows in
## the Inspector, is simply read again, so it never shows stale text.
func _on_filesystem_changed() -> void:
	_panel.check_disk_changes()
	for path in _foe_files():
		var time := FileAccess.get_modified_time(path)
		if _modified.get(path, time) != time and _panel.find_document(path) == null \
				and ResourceLoader.has_cached(path):
			var cached := ResourceLoader.load(path) as FoeScript
			if cached != null:
				cached.reload()
		_modified[path] = time


## Every `.foe` under the game's sector folders (the legacy pack's and the project's own, `Catalog.own_sector_dirs`): one per sector folder, `sector_NN/sector_NN.foe`.
func _foe_files() -> PackedStringArray:
	var found := PackedStringArray()
	for directory in Catalog.own_sector_dirs():
		for folder in DirAccess.get_directories_at(directory):
			for file_name in DirAccess.get_files_at(directory + "/" + folder):
				if file_name.get_extension() == FoeScriptLoader.EXTENSION:
					found.append(directory + "/" + folder + "/" + file_name)
	return found
