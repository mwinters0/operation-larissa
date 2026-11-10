class_name CustomizationDialog
extends Control
## Options > Problem Customization: the educational level (1-4) and the calculator switch.
##
## Teaches: radio buttons from `CheckBox` + `ButtonGroup` (buttons in one group are mutually exclusive, which
## is all "radio" means in Godot), and a dialog that returns its result in a signal instead of
## changing the game itself. The words are the original's strings (11021-11031, 11153-11154, 11161-11167).

## The player pressed Done: `level` is 0-3, `calculator` the new calculator setting.
signal accepted(level: int, calculator: bool)
signal cancelled

@onready var title_label: Label = %Title
@onready var level_heading: Label = %LevelHeading
@onready var level_box: VBoxContainer = %Levels
@onready var calculator_heading: Label = %CalculatorHeading
@onready var calculator_on: CheckBox = %CalculatorOn
@onready var calculator_off: CheckBox = %CalculatorOff
@onready var done_button: Button = %Done
@onready var cancel_button: Button = %Cancel

var _level_buttons: Array[CheckBox] = []


func _ready() -> void:
	title_label.text = Catalog.text(&"customization_title")
	level_heading.text = Catalog.text(&"educational_level_heading")
	calculator_heading.text = Catalog.text(&"calculator_heading")
	calculator_on.text = Catalog.text(&"calculator_on")
	calculator_off.text = Catalog.text(&"calculator_off")
	done_button.text = Catalog.text(&"settings_done_button")
	cancel_button.text = Catalog.text(&"settings_cancel_button")
	var level_group := ButtonGroup.new()
	for i in 4:
		var button := CheckBox.new()
		button.text = Catalog.text(StringName("level_choice_%d" % i))
		button.button_group = level_group
		level_box.add_child(button)
		_level_buttons.append(button)
	var calculator_group := ButtonGroup.new()
	calculator_on.button_group = calculator_group
	calculator_off.button_group = calculator_group
	done_button.pressed.connect(func() -> void: accepted.emit(chosen_level(), calculator_on.button_pressed))
	cancel_button.pressed.connect(func() -> void: cancelled.emit())
	_level_buttons[0].grab_focus()


## Shows the player's current choices.
func set_values(level: int, calculator: bool) -> void:
	if _level_buttons.is_empty():
		await ready
	_level_buttons[clampi(level, 0, 3)].button_pressed = true
	calculator_on.button_pressed = calculator
	calculator_off.button_pressed = not calculator


func chosen_level() -> int:
	for i in _level_buttons.size():
		if _level_buttons[i].button_pressed:
			return i
	return 0


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancelled.emit()
