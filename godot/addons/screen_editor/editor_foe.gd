@tool
class_name ScreenEditorFoe
extends ScreenEditorItem
## A creature that STARTS on this screen: the record `FoeData` of `sector_NN.tres`, shown with its start picture.
##
## Teaches: an editor node for a record of ANOTHER file (like `ScreenEditorPiece`), with more fields, a properties panel
## that is only the Inspector, and a button that leaves the scene for another tool.
##  * The creature list belongs to the SECTOR (the original keeps its 34-byte records in the sector's creature table,
##    not in a screen record), so saving a screen with a moved creature rewrites those lines of `sector_NN.tres` and nothing
##    else (`ScreenFile.foes_text`). The node keeps the creature's NUMBER (`foe_index`, its place in `SectorData.foes`):
##    the script finds creatures by number, so the number is what identifies the record, not the node's name or order.
##  * `position` is the record's `pos` in window pixels, the picture's top-left corner (what `Foe._playfield_position` draws
##    at, plus the playfield origin). The original keeps x / 2 and y / 2 in two bytes each, so the grid is (2, 2) and an odd
##    position can not be stored (`FoeData.problems()` says so; the node snaps to the grid, so dragging never gets there).
##  * The fields are the ORIGINAL record's: `start_frame` (the record's `frame`: a picture number of the zone's creature
##    pictures, shown by name in the drop-down), `flip`, `frame_min` / `frame_max` (the range the script keeps the picture
##    in), `damage`, `starts_dormant`, `starts_hidden`, the screen, and the three entry points `start_label`, `hit_label`, `ink_label`
##    (labels of the sector's `.foe` script). What the script does with them afterwards is not shown here, only where the
##    creature is at the first tick, and the first tick is usually the script moving it, so the picture is the START state.
##  * Some record names are taken by `AnimatedSprite2D`: `frame` is the picture the node is showing, and `hidden` is a member of
##    the class, which is why the record's `frame`, `hidden` and (to match it) `dormant` are called `start_frame`, `starts_hidden` and
##    `starts_dormant` here.
##  * Hidden and dormant creatures are drawn differently on purpose, because a creature that is not visible in the game is
##    exactly the one nobody finds in an editor: `starts_hidden` (not drawn until a script shows it) is faint with a dashed outline,
##    `starts_dormant` (asleep until a script wakes it) is tinted blue, and a creature that will start on another screen after saving
##    is dimmed with an arrow, as a piece is.
##  * "Go to ... label" opens the Foe Script screen at the label of the entry point (`ScreenEditorFoeJump`).
##
## Adding and removing creatures is adding and removing MARKERS: duplicate a marker (Ctrl+D) or use "Add creature" on the
## `ScreenEditor` and the sector gets a creature (`SectorData.add_foe`, a copy of the one you duplicated), delete a marker and the
## sector loses it (`SectorData.remove_foe`), unless the creature script names it: then the deletion is refused with the script
## line, and the marker comes back. The marker keeps the record it stands for (`record`), because after a removal in the middle the
## numbers move up and `foe_index` follows the record, not the other way round. `ScreenEditor.add_foe_marker(index)` makes a marker
## for a record of the sector; `ScreenEditor._collect_foes` is the only place that reads them back.

## Picture colours of the states.
const HIDDEN_ALPHA := 0.35
const DORMANT_TINT := Color(0.6, 0.75, 1.0)
const AWAY_ALPHA := 0.4
const OUTLINE_COLOR := Color(0.9, 0.5, 1.0, 0.8)
const LABEL_COLOR := Color(0.95, 0.8, 1.0)

## Position in the sector's creature list (the number scripts and `SectorData.foes` use). Read only; the `ScreenEditor` keeps it
## right when creatures are added or removed.
@export var foe_index: int = 0
## Asleep until a script wakes it (record byte 0x00).
@export var starts_dormant: bool = false:
	set(value):
		starts_dormant = value
		_look()
## Not drawn until a script shows it (byte 0x01).
@export var starts_hidden: bool = false:
	set(value):
		starts_hidden = value
		_look()
## The screen the creature starts on (byte 0x02). Change it to move the creature to another screen when you save.
@export_range(0, 11) var move_to_screen: int = 0:
	set(value):
		move_to_screen = value
		_look()
## The record's `frame` (byte 0x07): the picture it starts with, a number of the zone's creature pictures. The Inspector
## offers the pictures by name.
@export var start_frame: int = 0:
	set(value):
		start_frame = value
		show_picture()
		_edited()
## Starts mirrored (byte 0x08).
@export var flip: bool = false:
	set(value):
		flip = value
		show_picture()
		_edited()
## The lowest and highest picture the script keeps the creature's picture in (bytes 0x09, 0x0A).
@export var frame_min: int = 0:
	set(value):
		frame_min = value
		_edited()
@export var frame_max: int = 0:
	set(value):
		frame_max = value
		_edited()
## Oxygen lost on contact (byte 0x0F, one signed byte). Negative = friendly, like Zoom the dolphin.
@export_range(-128, 127) var damage: int = 0:
	set(value):
		damage = value
		_edited()
@export_group("Entry points")
## The labels of the sector's creature script where the creature starts, what runs when the sub touches it and what runs
## when an ink pellet hits it. Several creatures may share a label. The drop-down suggests the labels of the script.
@export var start_label: String = "":
	set(value):
		start_label = value
		_edited()
@export var hit_label: String = "":
	set(value):
		hit_label = value
		_edited()
@export var ink_label: String = "":
	set(value):
		ink_label = value
		_edited()
## Opens the Foe Script screen at the label above.
@export_tool_button("Go to start label", "Script") var go_start: Callable = _go_start
@export_tool_button("Go to hit label", "Script") var go_hit: Callable = _go_hit
@export_tool_button("Go to ink label", "Script") var go_ink: Callable = _go_ink
@export_group("")

## The zone of the sector (whose creature pictures these are); set when the node joins the `ScreenEditor`.
var zone: int = NameRegistry.NO_SCOPE
## Bytes 0x12..0x21 of the record, kept as they were (see `FoeData.runtime_state`); not editable.
var runtime_state: PackedByteArray = PackedByteArray()
## The creature of `SectorData.foes` this marker stands for; null for a marker nobody has added to the sector yet (a duplicate).
var record: FoeData = null


func _init() -> void:
	super()
	grid = Vector2i(2, 2)                 # the original stores creature positions as words / 2


func adopt(editor: ScreenEditor) -> void:
	zone = editor.zone()
	super(editor)
	notify_property_list_changed()


func _validate_property(property: Dictionary) -> void:
	super(property)
	var property_name: StringName = property.name
	if property_name == &"foe_index":
		property.usage |= PROPERTY_USAGE_READ_ONLY
	elif property_name == &"start_frame" or property_name == &"frame_min" or property_name == &"frame_max":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = FoeData.picture_choices(zone, int(get(property_name)))
	elif property_name == &"start_label" or property_name == &"hit_label" or property_name == &"ink_label":
		var editor := ScreenEditor.find_for(self)
		if editor != null:
			property.hint = PROPERTY_HINT_ENUM_SUGGESTION
			property.hint_string = ",".join(editor.script_labels())


# --- the picture ----------------------------------------------------------------------------------------------------

## The name of the picture `number` in this zone ("eel_swim_0"), or "" when it has none.
func picture_name(number: int) -> String:
	return NameRegistry.original().name_of(&"frame", number & 0x7F, zone)


## The start picture, mirrored if the record is. A picture number the zone has no picture for is drawn as nothing, like the
## game (`Foe.show_picture` ignores it), with a red outline.
func show_picture() -> void:
	if sprite_frames == null:
		return
	var count := sprite_frames.get_frame_count(&"all")
	flip_h = flip
	frame = clampi(start_frame, 0, maxi(count - 1, 0))
	self_modulate = Color.WHITE if start_frame >= 0 and start_frame < count else Color(1, 1, 1, 0.0)
	_look()


func _on_this_screen() -> bool:
	var editor := ScreenEditor.find_for(self)
	return editor == null or editor.screen == move_to_screen


## How hidden, dormant and "leaves this screen" look.
func _look() -> void:
	var color := DORMANT_TINT if starts_dormant else Color.WHITE
	color.a = HIDDEN_ALPHA if starts_hidden else 1.0
	if not _on_this_screen():
		color.a = minf(color.a, AWAY_ALPHA)
	modulate = color
	queue_redraw()
	_edited()


func _size() -> Vector2:
	if sprite_frames != null and start_frame >= 0 and start_frame < sprite_frames.get_frame_count(&"all"):
		return sprite_frames.get_frame_texture(&"all", start_frame).get_size()
	return Vector2(16, 16)


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, _size())
	var picture_missing := sprite_frames != null and start_frame >= sprite_frames.get_frame_count(&"all")
	if starts_hidden:
		_dashed_rect(box, OUTLINE_COLOR)
	else:
		draw_rect(box, Color(1, 0.2, 0.2, 0.8) if picture_missing else OUTLINE_COLOR, false)
	var text := "#%d %s" % [foe_index, picture_name(start_frame)]
	if starts_dormant:
		text += " (dormant)"
	if starts_hidden:
		text += " (hidden)"
	if not _on_this_screen():
		text += " -> screen %d" % move_to_screen
	draw_string(ThemeDB.fallback_font, Vector2(0, -3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, LABEL_COLOR)


func _dashed_rect(box: Rect2, color: Color) -> void:
	var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 1.0, 3.0)


# --- the record -------------------------------------------------------------------------------------------------------

## The record this node stands for. The three run-time entry points (`pc`, `script_hit`, `script_ink`) are not stored in
## the resource; the sector fills them in when it compiles the script.
func to_record() -> FoeData:
	var record := FoeData.new()
	record.dormant = starts_dormant
	record.hidden = starts_hidden
	record.screen = move_to_screen
	record.pos = pixel_position()
	record.frame = start_frame
	record.flip = flip
	record.frame_min = frame_min
	record.frame_max = frame_max
	record.damage = damage
	record.start_label = start_label
	record.hit_label = hit_label
	record.ink_label = ink_label
	record.runtime_state = runtime_state
	return record


## The marker for creature number `index` of the sector, named "Foe 3".
static func from_record(record: FoeData, index: int) -> ScreenEditorFoe:
	var node := ScreenEditorFoe.new()
	node.record = record
	node.foe_index = index
	node.starts_dormant = record.dormant
	node.starts_hidden = record.hidden
	node.move_to_screen = record.screen
	node.start_frame = record.frame
	node.flip = record.flip
	node.frame_min = record.frame_min
	node.frame_max = record.frame_max
	node.damage = record.damage
	node.start_label = record.start_label
	node.hit_label = record.hit_label
	node.ink_label = record.ink_label
	node.runtime_state = record.runtime_state
	node.position = Vector2(record.pos)
	node.name = marker_name(index)
	return node


## "Foe 3": the name of the marker of creature number `index`.
static func marker_name(index: int) -> String:
	return "Foe %d" % index


## What keeps the creature from being stored as the original's record: `FoeData.problems()` (a screen above 255, an odd
## position, a damage of 300 ...) and a label the sector's script does not have. `labels`: the script's labels, or empty
## when they are not known (then labels are not checked). Each message starts with the creature's number.
func problems(labels: PackedStringArray) -> Array[String]:
	var found: Array[String] = []
	for message in to_record().problems():
		found.append("creature %d: %s" % [foe_index, message])
	if move_to_screen < 0 or move_to_screen >= SectorData.SCREEN_COUNT:
		found.append("creature %d: screen %d does not exist (0 to %d)" % [foe_index, move_to_screen, SectorData.SCREEN_COUNT - 1])
	if not labels.is_empty():
		for pair: Array in [["start_label", start_label], ["hit_label", hit_label], ["ink_label", ink_label]]:
			if not labels.has(pair[1]):
				found.append("creature %d: %s '%s' is not a label of the sector's script" % [foe_index, pair[0], pair[1]])
	return found


func _get_configuration_warnings() -> PackedStringArray:
	var found := _common_warnings()
	var editor := ScreenEditor.find_for(self)
	for message in problems(editor.script_labels() if editor != null else PackedStringArray()):
		found.append(message)
	return found


# --- the script labels --------------------------------------------------------------------------------------------------

func _go_start() -> void:
	go_to_label(start_label)


func _go_hit() -> void:
	go_to_label(hit_label)


func _go_ink() -> void:
	go_to_label(ink_label)


## Opens the sector's creature script in the Foe Script screen with the caret on `label`. Says why when it can not.
##
## Deferred: the "Go to ... label" buttons call this from inside the Inspector button's `pressed` signal (Godot calls a tool
## button's Callable synchronously). Opening the script edits another object, so the Inspector clears its properties and frees
## that very button while its signal is still being emitted: the editor crashed. `call_deferred` runs the jump on the next idle
## frame, after the button has finished.
func go_to_label(label: String) -> void:
	var editor := ScreenEditor.find_for(self)
	if editor == null:
		return
	editor.show_script_label.call_deferred(label)
