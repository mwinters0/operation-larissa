@tool
class_name SectorInspectorPlugin
extends EditorInspectorPlugin
## Puts the sector panel (`SectorPanel`) at the top of the Inspector whenever a `SectorData` is shown there, and hides the
## raw rows the panel replaces.
##
## Teaches: `EditorInspectorPlugin`, the second half. `ScreenInspectorPlugin` only adds a button in `_parse_begin`; this one also
## decides, property by property, what the Inspector shows: `_parse_property` is called for every property the Inspector is
## about to list, and returning `true` means "I handled it": the default row is not made. The neighbour tables, the start,
## the music and the list of pieces are hidden that way, because the panel edits them with names and limits and with undo; the
## creature list (`foes`) stays, its rows are where a creature's picture, damage and labels are changed.

## What the panel edits (the raw rows would be a second, unchecked way to the same data), and what follows from it: `stale_pieces`
## is the original's left-over, `foe_script_base` follows the number of creatures.
const HIDDEN := ["start_pos", "start_frame", "neighbors_left", "neighbors_right", "neighbors_up", "neighbors_down",
		"music_name", "pieces", "stale_pieces", "foe_script_base"]

var plugin: SectorEditorPlugin


## The two decisions the editor asks for, as static functions so that a test can ask them without an editor
## (an `EditorInspectorPlugin` can not be made outside the editor).
static func handles(object: Object) -> bool:
	return object is SectorData


static func hides(property: String) -> bool:
	return property in HIDDEN


func _can_handle(object: Object) -> bool:
	return handles(object)


func _parse_begin(object: Object) -> void:
	var panel := SectorPanel.new()
	panel.setup(object as SectorData, plugin.get_undo_redo())
	add_custom_control(panel)


func _parse_property(_object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	return hides(name)
