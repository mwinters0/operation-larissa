class_name PracticeSetupDialog
extends Control
## "Math Practice Customized Settings": the kind of set, the educational level and the calculator.
##
## Teaches: three groups of radio buttons (`CheckBox` + `ButtonGroup`, as in `CustomizationDialog`) built from
## the original's strings 11155-11167, and a dialog that answers with a signal instead of changing anything
## itself. With "10 Mental Math Problems" the calculator choice is greyed out (the lock has no calculator).

signal accepted(kind: PracticeSet.Kind, level: int, calculator: bool)
signal cancelled

@onready var title_label: Label = %Title
@onready var kind_box: VBoxContainer = %Kinds
@onready var level_box: VBoxContainer = %Levels
@onready var calculator_on: CheckBox = %CalculatorOn
@onready var calculator_off: CheckBox = %CalculatorOff
@onready var done_button: Button = %Done
@onready var cancel_button: Button = %Cancel

var _kind_buttons: Array[CheckBox] = []
var _level_buttons: Array[CheckBox] = []


func _ready() -> void:
	title_label.text = Catalog.text(&"practice_settings_title")
	%KindHeading.text = Catalog.text(&"practice_kind_heading")
	%LevelHeading.text = Catalog.text(&"practice_level_heading")
	%CalculatorHeading.text = Catalog.text(&"calculator_heading")
	calculator_on.text = Catalog.text(&"calculator_on")
	calculator_off.text = Catalog.text(&"calculator_off")
	done_button.text = Catalog.text(&"settings_done_button")
	cancel_button.text = Catalog.text(&"settings_cancel_button")
	_kind_buttons = _radio_group(kind_box, [&"practice_kind_0", &"practice_kind_1", &"practice_kind_2"])
	_level_buttons = _radio_group(level_box, [&"level_choice_0", &"level_choice_1", &"level_choice_2", &"level_choice_3"])
	var calculator_group := ButtonGroup.new()
	calculator_on.button_group = calculator_group
	calculator_off.button_group = calculator_group
	for button in _kind_buttons:
		button.toggled.connect(func(_pressed: bool) -> void: _update_calculator_choice())
	done_button.pressed.connect(func() -> void: accepted.emit(chosen_kind(), chosen_level(), calculator_on.button_pressed))
	cancel_button.pressed.connect(func() -> void: cancelled.emit())
	_kind_buttons[0].grab_focus()


## One radio button per string (a `text` name), all in one group; the first one is chosen.
func _radio_group(box: VBoxContainer, texts: Array[StringName]) -> Array[CheckBox]:
	var group := ButtonGroup.new()
	var buttons: Array[CheckBox] = []
	for text_name in texts:
		var button := CheckBox.new()
		button.text = Catalog.text(text_name).replace("\n", " ")
		button.button_group = group
		box.add_child(button)
		buttons.append(button)
	buttons[0].button_pressed = true
	return buttons


## Shows the current choices.
func set_values(kind: PracticeSet.Kind, level: int, calculator: bool) -> void:
	if _kind_buttons.is_empty():
		await ready
	_kind_buttons[kind].button_pressed = true
	_level_buttons[clampi(level, 0, 3)].button_pressed = true
	calculator_on.button_pressed = calculator
	calculator_off.button_pressed = not calculator
	_update_calculator_choice()


func chosen_kind() -> PracticeSet.Kind:
	for i in _kind_buttons.size():
		if _kind_buttons[i].button_pressed:
			return i as PracticeSet.Kind
	return PracticeSet.Kind.FIVE


func chosen_level() -> int:
	for i in _level_buttons.size():
		if _level_buttons[i].button_pressed:
			return i
	return 0


func _update_calculator_choice() -> void:
	var mental := chosen_kind() == PracticeSet.Kind.MENTAL
	calculator_on.disabled = mental
	calculator_off.disabled = mental


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancelled.emit()
