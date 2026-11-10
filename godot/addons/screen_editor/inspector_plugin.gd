@tool
class_name ScreenInspectorPlugin
extends EditorInspectorPlugin
## Puts an "Open in Screen Editor" button at the top of the Inspector whenever a screen file is shown there.
##
## Teaches: `EditorInspectorPlugin`. The editor asks every inspector plugin `_can_handle(object)` for the object the Inspector is
## about to show; the ones that say yes get `_parse_begin` (before the properties) and may add their own controls. This is the
## quiet way to offer the screen editor: seeing a `ScreenData` in the Inspector, for instance by clicking a sector's `Screens`
## list, never switches scenes by itself.

var plugin: ScreenEditorPlugin


func _can_handle(object: Object) -> bool:
	return object is ScreenData and ScreenEditorPlugin.screen_of(object).x >= 0


func _parse_begin(object: Object) -> void:
	var where := ScreenEditorPlugin.screen_of(object)
	var button := Button.new()
	button.text = "Open sector %d, screen %d in the Screen Editor" % [where.x, where.y]
	button.tooltip_text = "Opens the screen as a scene with a tile map, decorations and triggers you can move around."
	# Deferred: opening a scene clears the Inspector, which frees this button while its `pressed` signal is still being emitted.
	button.pressed.connect(plugin.open_screen.bind(where.x, where.y), CONNECT_DEFERRED)
	add_custom_control(button)
