class_name AnswerBox
extends Control
## The "Ans:" panel: where the player types an answer when there is no calculator.
##
## Teaches: a keyboard-driven widget that is not a `LineEdit`. The original shows the typed
## number in the same green picture digits as its calculator, so this node keeps a small text
## buffer and hands it to an `LcdDisplay`. The buffer follows the original's entry rules (`GetNumber` (0x41fb34), the
## calculator-less mode): up to nine digits and a "." (a decimal), or a fraction "whole numerator/denominator" with
## at most 2 characters in front (sign included), 2 numerator and 3 denominator digits. A space or `F` starts the
## fraction, `/` goes on to the denominator, `-` or `N` flips the sign. Backspace deletes (and always clicks), Enter
## submits. Once the denominator is being typed, an operator key or an Enter without a usable denominator opens the
## "Fraction Mode" help instead (`notice_requested`). The text is parsed by the caller (`NumberValue.parse`).

## Enter was pressed; `typed` is the text as typed (possibly empty or unparsable).
signal submitted(typed: String)
## What the box shows changed (`text`: what is typed, "" when nothing).
signal entry_changed(text: String)
## Backspace was pressed: the original plays its sound `calc_backspace` then, even when nothing is left to erase.
signal sfx_requested(sfx: StringName)
## The player is to be shown the "Fraction Mode" help (`ShowCalcNoticeDialog(-1)` (0x420d8f)).
signal notice_requested(notice: CalculatorModel.Notice)

const SFX_BACKSPACE := &"calc_backspace"

@export var layout: CalculatorLayout

var text: String = "":
	set(value):
		text = value
		if is_node_ready():
			display.text = text if not text.is_empty() else "0"
		entry_changed.emit(text)
## While false the box ignores the keyboard (a finished problem).
var keyboard_enabled: bool = true:
	set(value):
		keyboard_enabled = value
		set_process_unhandled_key_input(value)

@onready var picture: TextureRect = %Picture
@onready var display: LcdDisplay = %Display


func _ready() -> void:
	layout = Catalog.skinned(layout if layout != null else Catalog.pack_resource("data/ui/calculator_layout.tres")) as CalculatorLayout         # (the pack's; the skin in use may show another)
	position = Vector2(layout.answer_position)
	picture.texture = layout.answer_panel
	size = Vector2(layout.answer_size)                      # (from the layout's data, not from the texture that happens to be loaded)
	custom_minimum_size = size
	display.layout = layout
	display.frame_origin = layout.answer_position
	display.origin = layout.display_origin_answer
	display.show_markers = false
	display.text = "0"


## Empties the box for a new problem.
func reset() -> void:
	text = ""


## Types one character as if the key had been pressed (also used by tests). Returns whether it was accepted.
func type_character(character: String) -> bool:
	if character.length() != 1:
		return false
	var parts := _parts()
	var stage: int = parts.stage
	var digits: int = (parts.whole as String).length()
	var negative: bool = parts.negative
	match character:
		"f", "F", " ":                                           # F: starts the fraction (0x41ff9f)
			if stage != 0 or "." in text or digits + int(negative) > CalculatorModel.MAX_WHOLE_BEFORE_FRACTION:
				return false
			text += " "
			return true
		"/":
			match stage:
				0:                                               # "3/4": the digits so far are the numerator (0x4200c0)
					if "." in text or digits == 0 or digits > NumberValue.MAX_NUMERATOR_DIGITS:
						return false
				1:
					if (parts.numerator as String).is_empty():
						return false
				_:
					notice_requested.emit(CalculatorModel.Notice.FRACTION_HELP)    # a second bar: an operator
					return false
			text += "/"
			return true
		"-", "n", "N":
			if stage == 2 and character == "-":
				notice_requested.emit(CalculatorModel.Notice.FRACTION_HELP)
				return false
			if stage != 0 and character == "-":
				return false
			return _toggle_sign(parts)
		"+", "*", "=":
			if stage == 2:
				notice_requested.emit(CalculatorModel.Notice.FRACTION_HELP)
			return false
		".":
			if stage != 0 or "." in text:
				return false
			text += "."
			return true
	if character < "0" or character > "9":
		return false
	var room: bool
	match stage:
		0:
			room = digits + int(negative) < NumberValue.MAX_DIGITS
		1:
			room = (parts.numerator as String).length() < NumberValue.MAX_NUMERATOR_DIGITS
		_:
			room = (parts.denominator as String).length() < NumberValue.MAX_DENOMINATOR_DIGITS
	if not room:
		return false
	text += character
	return true


## Enter: a decimal, or a fraction with a usable denominator (not empty, first digit not 0, as `GetNumber` checks it),
## goes to the answer; an empty box does nothing; an unfinished fraction opens the "Fraction Mode" help.
func submit() -> void:
	var parts := _parts()
	if parts.stage == 0 and (parts.whole as String).is_empty():
		return                                                   # nothing typed yet: state 0 ignores Enter (0x4201d8)
	var finished: bool = parts.stage == 0 or not (parts.denominator as String).is_empty() and not (parts.denominator as String).begins_with("0")
	if finished:
		submitted.emit(text)
	else:
		notice_requested.emit(CalculatorModel.Notice.FRACTION_HELP)


## The typed text in its parts. `stage` is 0 while the whole number / decimal is typed, 1 after the F (numerator),
## 2 after the bar (denominator). "-12 3/456": negative, whole "12", numerator "3", denominator "456". Without an F
## ("3/4") the digits in front of the bar are the numerator and `whole` is empty.
func _parts() -> Dictionary:
	var negative := text.begins_with("-")
	var rest := text.substr(1) if negative else text
	var stage := 0
	var whole := rest
	var numerator := ""
	var denominator := ""
	var bar := rest.find("/")
	if bar >= 0:
		stage = 2
		denominator = rest.substr(bar + 1)
		whole = rest.substr(0, bar)
	var space := whole.find(" ")
	if space >= 0:
		numerator = whole.substr(space + 1)
		whole = whole.substr(0, space)
		stage = maxi(stage, 1)
	elif bar >= 0:
		numerator = whole
		whole = ""
	return {"negative": negative, "whole": whole.replace(".", ""), "numerator": numerator, "denominator": denominator, "stage": stage}


## The sign key. Taking the sign off always works; putting it on needs room: a digit in a decimal, and in a fraction
## the whole part (digits and sign together) at most two characters (0x4202e7 / 0x41feca).
func _toggle_sign(parts: Dictionary) -> bool:
	if parts.negative:
		text = text.substr(1)
		return true
	var digits := (parts.whole as String).length()
	if digits + 1 > (NumberValue.MAX_DIGITS if parts.stage == 0 else CalculatorModel.MAX_WHOLE_BEFORE_FRACTION):
		return false
	text = "-" + text
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or not visible:
		return
	match key_event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			submit()
			return
		KEY_BACKSPACE:
			get_viewport().set_input_as_handled()
			sfx_requested.emit(SFX_BACKSPACE)                    # always: even on an empty entry (0x42031a, 0x420546, 0x41fefd)
			text = text.left(-1)
			return
	var character := ""
	if key_event.unicode > 0:
		character = String.chr(key_event.unicode)
	elif key_event.keycode >= KEY_0 and key_event.keycode <= KEY_9:
		character = String.chr(key_event.keycode)
	elif key_event.keycode >= KEY_KP_0 and key_event.keycode <= KEY_KP_9:
		character = str(key_event.keycode - KEY_KP_0)
	elif key_event.keycode in [KEY_PERIOD, KEY_KP_PERIOD]:
		character = "."
	elif key_event.keycode in [KEY_SLASH, KEY_KP_DIVIDE]:
		character = "/"
	elif key_event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		character = "-"
	elif key_event.keycode == KEY_KP_ADD:
		character = "+"
	elif key_event.keycode == KEY_KP_MULTIPLY:
		character = "*"
	elif key_event.keycode == KEY_EQUAL:
		character = "="
	elif key_event.keycode == KEY_SPACE:
		character = " "
	if type_character(character):
		get_viewport().set_input_as_handled()
