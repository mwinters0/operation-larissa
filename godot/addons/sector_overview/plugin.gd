@tool
extends EditorPlugin
## Puts the sector overview (`SectorOverview`, src/debug/sector_overview.tscn) in the editor's main screen bar, next to 2D, 3D, Script
## and Foe Script.
##
## Teaches: the same panel as a tool scene and as an editor screen, and one editor plugin using another one's code. The overview does not
## know where it runs: it only EMITS what the user asked for, and this plugin answers in the editor's way:
##   - a screen to open  -> `ScreenEditorPlugin.open_screen_in_editor`, the code the Screen Editor addon itself opens a screen with;
##   - a creature's script -> `ScreenEditorFoeJump.open_in_editor`: the Foe Script screen (which takes any `FoeScript` the editor is asked to
##     edit) with the caret on the creature's start label.
## So this addon needs the Screen Editor addon (the Foe Script one for the jump), which sit in the same project.
## Everything else (the layout, the reachability search, the creature traces) is plain code of the game that the panel calls. The panel's
## own scripts are `@tool` (a NODE whose script lacks it is only a placeholder in the editor, see `ScreenData`); plain `RefCounted`
## classes such as `SectorReach` and `FoeVM` need nothing: `Class.new()` makes a working object in the editor too, and the data classes
## (`SectorData` ...) are `@tool` already.
##
## It is a main screen plugin like the Foe Script editor (`_has_main_screen`, `_get_plugin_name`, `_get_plugin_icon`, `_make_visible`).
## The map follows the sector it shows: a change of the sector or of its creature script (a save of the Screen Editor, the Sector Inspector,
## the Foe Script screen) builds it again (`SectorOverview._watch`).

const SCREEN_NAME := "Sector Overview"
const SCENE := "res://src/debug/sector_overview.tscn"

var _overview: SectorOverview


func _enter_tree() -> void:
	_overview = (load(SCENE) as PackedScene).instantiate() as SectorOverview
	_overview.screen_open_requested.connect(open_screen)
	_overview.foe_script_requested.connect(_show_foe_script)
	_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(_overview)
	_make_visible(false)


func _exit_tree() -> void:
	if _overview != null:
		_overview.queue_free()
		_overview = null


# --- the main screen ----------------------------------------------------------------------------

func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return SCREEN_NAME


func _get_plugin_icon() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	for icon_name in ["Grid", "GridMinimap", "TileMap", "Node"]:
		if theme.has_icon(icon_name, "EditorIcons"):
			return theme.get_icon(icon_name, "EditorIcons")
	return null


func _make_visible(visible: bool) -> void:
	if _overview != null:
		_overview.visible = visible


# --- what the overview asks for -----------------------------------------------------------------

## Opens screen `screen` of sector `sector` as the Screen Editor addon does (its "Edit screen..."): the scene folder, the template and the
## naming stay in that plugin (`ScreenEditorPlugin.open_screen_in_editor`), so this addon repeats none of them.
func open_screen(sector: int, screen: int) -> void:
	ScreenEditorPlugin.open_screen_in_editor(sector, screen)


## The creature's start label in the Foe Script screen: the script opens with the caret on the label (`ScreenEditorFoeJump`, which the
## Screen Editor's "Go to ... label" uses too). `labels` are the creature's start, contact and ink labels; the first is where it begins.
func _show_foe_script(sector: int, foe_index: int, labels: PackedStringArray) -> void:
	var error := jump_to_label(Catalog.sector(sector).foe_script, labels[0] if labels.size() > 0 else "")
	if not error.is_empty():
		push_warning("Sector overview: creature %d of sector %d: %s." % [foe_index, sector, error])


## Opens `script` in the Foe Script screen with the caret on `label`; "" when it worked, else the reason (the script is open anyway when
## it is only the label that could not be found). `panel` is for tests: a Foe Script panel of their own instead of the editor's.
static func jump_to_label(script: FoeScript, label: String, panel: FoeEditorPanel = null) -> String:
	if panel != null:
		return ScreenEditorFoeJump.show_label(panel, script, label)
	return ScreenEditorFoeJump.open_in_editor(script, label)
