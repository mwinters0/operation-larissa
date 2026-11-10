@tool
class_name ScreenEditorPlaytestDialog
extends ConfirmationDialog
## The dialog of "Playtest screen": where the sub starts, how much air and ink it has, which pieces are collected, which flags are
## set and what each creature of the screen is doing. "Play" starts the game on the screen (`ScreenEditorPlaytest.run`).
##
## Teaches: a form built in code from a plain object. The dialog holds no state of its own: `fill` puts a `PlaytestSetup` into the
## controls and `read` makes one from them, so a test can drive it without the editor, and the setup (not the dialog) knows what
## the game can reach (`PlaytestSetup.problems`, shown under the form). A preset is a function on the setup, applied to the
## numbers; the controls are then free to change it.

## The line of the start options that stands for the playtest marker (`ScreenEditorPlaytestStart`), and for typed-in coordinates.
const START_MARKER := 4
const START_COORDINATES := 5
## The setups the dialog was last closed with, by sector * 100 + screen, as arguments: the next time starts from them.
static var _last: Dictionary = {}

## The editor of the screen to play.
var editor: ScreenEditor

var _sector: SectorData
var _preset: OptionButton
var _start: OptionButton
var _x: SpinBox
var _y: SpinBox
var _cell: SpinBox
var _tanks: SpinBox
var _oxygen: SpinBox
var _ink: SpinBox
var _piece_boxes: Array[CheckBox] = []
var _flag_boxes: Array[CheckBox] = []
## Creature number -> its OptionButton (the creatures that start on this screen).
var _foe_boxes: Dictionary = {}
var _others: LineEdit
var _paused: CheckBox
var _summary: Label
var _filling := false


## Saves the screen if needed and opens the dialog for it. A screen that can not be played is a toast and no dialog.
static func open(screen_editor: ScreenEditor) -> void:
	var why := ScreenEditorPlaytest.save_first(screen_editor)
	if not why.is_empty():
		EditorInterface.get_editor_toaster().push_toast("Playtest: " + why, EditorToaster.SEVERITY_WARNING)
		return
	var dialog := ScreenEditorPlaytestDialog.new()
	dialog.editor = screen_editor
	EditorInterface.get_base_control().add_child(dialog)
	dialog.build()
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.play)
	dialog.popup_centered()


## The controls, for the sector and screen of `editor`. Public so that a test can build the dialog on a scene of its own.
func build() -> void:
	title = "Playtest sector %d, screen %d" % [editor.sector, editor.screen]
	ok_button_text = "Play"
	_sector = Catalog.sector(editor.sector)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 460)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	add_child(scroll)

	_preset = OptionButton.new()
	_preset.add_item("Preset: custom values", -1)
	for i in PlaytestSetup.PRESETS.size():
		_preset.add_item(PlaytestSetup.PRESET_TITLES[PlaytestSetup.PRESETS[i]], i)
	_preset.item_selected.connect(_on_preset_selected)
	box.add_child(_preset)

	box.add_child(_heading("Where the sub starts"))
	_start = OptionButton.new()
	var default_start := PlaytestSetup.new()
	default_start.screen = editor.screen
	_start.add_item("Default for this screen (%s)" % default_start.resolved_start(), 0)
	_start.add_item("Launch from the start station (screen 0)", 1)
	_start.add_item("The respawn point (screen %d)" % editor.tuning.midpoint_screen, 2)
	_start.add_item("The middle of the playfield", 3)
	_start.add_item("At the playtest marker (drag it in the 2D view)", START_MARKER)
	_start.add_item("At these coordinates", START_COORDINATES)
	_start.set_item_disabled(1, editor.screen != 0)
	_start.set_item_disabled(2, editor.screen != editor.tuning.midpoint_screen)
	_start.item_selected.connect(_changed)
	box.add_child(_start)
	var place := HBoxContainer.new()
	_x = _spin(place, "SubX", 16, 528, 2)
	_y = _spin(place, "SubY", 32, 262, 1)
	_cell = _spin(place, "picture", 0, 8, 1)
	_cell.value = 6
	var marker_button := Button.new()
	marker_button.text = "Show the marker"
	marker_button.tooltip_text = "Puts the playtest marker on the screen and closes this dialog so that you can drag it. It is not saved with the screen."
	marker_button.pressed.connect(_show_marker)
	place.add_child(marker_button)
	box.add_child(place)

	box.add_child(_heading("The sub's air and ink"))
	var numbers := HBoxContainer.new()
	_tanks = _spin(numbers, "spare tanks", 0, editor.tuning.max_tanks, 1)
	_oxygen = _spin(numbers, "oxygen", 1, editor.tuning.max_oxygen, 1)
	_ink = _spin(numbers, "ink pellets", 0, editor.tuning.ink_max, 1)
	box.add_child(numbers)

	box.add_child(_heading("Pieces already collected (piece 0 is the data canister)"))
	var pieces := GridContainer.new()
	pieces.columns = 4
	for i in _sector.pieces.size():
		var check := CheckBox.new()
		check.text = "%d (screen %d)%s" % [i, _sector.pieces[i].screen, " here" if _sector.pieces[i].screen == editor.screen else ""]
		check.toggled.connect(_changed)
		pieces.add_child(check)
		_piece_boxes.append(check)
	box.add_child(pieces)

	box.add_child(_heading("Creature flags set (bit 15 is the finale)"))
	var flags := GridContainer.new()
	flags.columns = 8
	for bit in 16:
		var check := CheckBox.new()
		check.text = str(bit)
		check.toggled.connect(_changed)
		flags.add_child(check)
		_flag_boxes.append(check)
	box.add_child(flags)

	box.add_child(_heading("Creatures that start on this screen"))
	var foes := GridContainer.new()
	foes.columns = 2
	for i in _sector.foes.size():
		if _sector.foes[i].screen != editor.screen:
			continue
		var label := Label.new()
		label.text = "#%d  %s" % [i, "dormant" if _sector.foes[i].dormant else "awake"] + (", hidden" if _sector.foes[i].hidden else "")
		foes.add_child(label)
		var state := OptionButton.new()
		state.add_item("as in the file", 0)
		for j in PlaytestSetup.FOE_STATES.size():
			state.add_item(PlaytestSetup.FOE_STATES[j], j + 1)
		state.item_selected.connect(_changed)
		foes.add_child(state)
		_foe_boxes[i] = state
	if _foe_boxes.is_empty():
		var none := Label.new()
		none.text = "(none)"
		foes.add_child(none)
	box.add_child(foes)
	var others := HBoxContainer.new()
	var others_label := Label.new()
	others_label.text = "Creatures elsewhere"
	others.add_child(others_label)
	_others = LineEdit.new()
	_others.placeholder_text = "e.g. 4:dormant,7:woken"
	_others.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_others.text_changed.connect(_changed)
	others.add_child(_others)
	box.add_child(others)

	_paused = CheckBox.new()
	_paused.text = "Start with the clock stopped (P pauses, S steps)"
	_paused.toggled.connect(_changed)
	box.add_child(_paused)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size.x = 520
	box.add_child(_summary)

	var start := _remembered()
	start.sector = editor.sector
	start.screen = editor.screen
	if ScreenEditorPlaytestStart.find_in(editor) != null:
		start.start = PlaytestSetup.START_AT                    # (a marker somebody placed is wanted)
		start.sub_pos = ScreenEditorPlaytestStart.find_in(editor).pixel_position()
		start.cell = ScreenEditorPlaytestStart.find_in(editor).cell
	fill(start)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.7, 0.85, 1.0))
	return label


func _spin(row: HBoxContainer, label_text: String, minimum: int, maximum: int, step: int) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value_changed.connect(_changed)
	row.add_child(spin)
	return spin


## The setup of the last time this screen was played in this editor session, else a new one.
func _remembered() -> PlaytestSetup:
	var key := editor.sector * 100 + editor.screen
	if _last.has(key):
		return PlaytestSetup.from_arguments(String(_last[key]).split(" "))
	return PlaytestSetup.new()


# --- the controls <-> the setup ------------------------------------------------------

## Puts `setup` into the controls (its sector and screen are the editor's, whatever it says).
func fill(setup: PlaytestSetup) -> void:
	setup.sector = editor.sector
	setup.screen = editor.screen
	_filling = true
	match setup.start:
		PlaytestSetup.START_LAUNCH:
			_start.select(1)
		PlaytestSetup.START_RESPAWN:
			_start.select(2)
		PlaytestSetup.START_CENTRE:
			_start.select(3)
		PlaytestSetup.START_AT:
			var marker := ScreenEditorPlaytestStart.find_in(editor)
			_start.select(START_MARKER if marker != null and marker.pixel_position() == setup.sub_pos else START_COORDINATES)
		_:
			_start.select(0)
	var place := setup.start_place()
	_x.value = place["pos"].x
	_y.value = place["pos"].y
	_cell.value = place["cell"]
	_fill_numbers(setup)
	var elsewhere: Array[String] = []
	for number in _foe_boxes:
		var at := PlaytestSetup.FOE_STATES.find(setup.foe_states.get(number, ""))
		_foe_boxes[number].select(at + 1)
	var numbers: Array = setup.foe_states.keys()
	numbers.sort()
	for number in numbers:
		if not _foe_boxes.has(number):
			elsewhere.append("%d:%s" % [number, setup.foe_states[number]])
	_others.text = ",".join(elsewhere)
	_paused.button_pressed = setup.paused
	_filling = false
	_changed()


func _fill_numbers(setup: PlaytestSetup) -> void:
	_tanks.value = setup.tanks
	_oxygen.value = setup.oxygen
	_ink.value = setup.ink
	for i in _piece_boxes.size():
		_piece_boxes[i].button_pressed = (setup.pieces_mask >> i) & 1 == 1
	for bit in _flag_boxes.size():
		_flag_boxes[bit].button_pressed = (setup.flags >> bit) & 1 == 1


## The setup the controls say.
func read() -> PlaytestSetup:
	var setup := PlaytestSetup.new()
	setup.sector = editor.sector
	setup.screen = editor.screen
	match _start.get_selected_id():
		1:
			setup.start = PlaytestSetup.START_LAUNCH
		2:
			setup.start = PlaytestSetup.START_RESPAWN
		3:
			setup.start = PlaytestSetup.START_CENTRE
		START_MARKER:
			var marker := ScreenEditorPlaytestStart.find_in(editor)
			if marker != null:
				setup.start = PlaytestSetup.START_AT
				setup.sub_pos = marker.pixel_position()
				setup.cell = marker.cell
		START_COORDINATES:
			setup.start = PlaytestSetup.START_AT
			setup.sub_pos = Vector2i(int(_x.value), int(_y.value))
			setup.cell = int(_cell.value)
	setup.tanks = int(_tanks.value)
	setup.oxygen = int(_oxygen.value)
	setup.ink = int(_ink.value)
	for i in _piece_boxes.size():
		if _piece_boxes[i].button_pressed:
			setup.pieces_mask |= 1 << i
	for bit in _flag_boxes.size():
		if _flag_boxes[bit].button_pressed:
			setup.flags |= 1 << bit
	setup.read_foes(_others.text)
	for number in _foe_boxes:
		var chosen: int = _foe_boxes[number].get_selected_id()
		if chosen > 0:
			setup.foe_states[number] = PlaytestSetup.FOE_STATES[chosen - 1]
	setup.paused = _paused.button_pressed
	return setup


func _on_preset_selected(index: int) -> void:
	var id := _preset.get_item_id(index)
	if id < 0:
		return
	var setup := read()
	setup.apply_preset(PlaytestSetup.PRESETS[id])
	_filling = true
	_fill_numbers(setup)
	_filling = false
	_changed()


func _changed(_value: Variant = null) -> void:
	if _filling or _summary == null:
		return
	var setup := read()
	var problems := setup.problems()
	_summary.text = ("Not possible in the game, so the nearest value is used:\n- " + "\n- ".join(problems) + "\n") if not problems.is_empty() else ""
	_summary.text += setup.describe()


## "Show the marker": the playtest marker is put on the screen (where the sub would start, or where it is), selected, and the dialog closes.
func _show_marker() -> void:
	var setup := read()
	var place := setup.start_place()
	var marker := ScreenEditorPlaytestStart.ensure_in(editor, place["pos"], place["cell"])
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(marker)
	_last[editor.sector * 100 + editor.screen] = setup.to_arguments()
	queue_free()


## "Play": remember the setup and start the game.
func play() -> void:
	var setup := read()
	_last[editor.sector * 100 + editor.screen] = setup.to_arguments()
	var why := ScreenEditorPlaytest.run(editor, setup)
	if not why.is_empty():
		EditorInterface.get_editor_toaster().push_toast(why, EditorToaster.SEVERITY_WARNING)
	queue_free()
