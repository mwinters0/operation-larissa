class_name CalcNoticeDialog
extends Control
## The modal notice of the calculator: "Calculator Error" (divide by zero, too large, an operator inside a fraction) or the
## "Fraction Mode" help.
##
## Teaches: a modal dialog without a dialog node. A dimmed `ColorRect` takes the mouse, `_input` (which runs BEFORE the
## widgets underneath see a key) takes every key while the dialog is open, and only Enter, Space and Escape close it,
## like the original's `RunModalDialog` (0x4174ec) with its single OK button, so a digit typed meanwhile never
## reaches the calculator or the answer box. The words are the original's (`ShowCalcNoticeDialog` (0x420d8f)): title 11042
## "Calculator Error" + message 10174-10176, or title 11044 "Fraction Mode" + text 11043.

## The player closed the dialog.
signal closed

## First text id of the three "Calculator Error" messages (bundle 0xf5 items 0-2).
const TITLE_ERROR := &"calculator_error_title"
const TEXT_FRACTION_HELP := &"fraction_help_text"
const TITLE_FRACTION_HELP := &"fraction_help_title"

@onready var dim: ColorRect = %Dim
@onready var title_label: Label = %Title
@onready var body_label: Label = %Body
@onready var ok_button: Button = %Ok


func _ready() -> void:
	hide()
	ok_button.pressed.connect(close)


## Title and body of the dialog for `notice` (a `CalculatorModel.Notice`), as plain text.
static func texts_for(notice: CalculatorModel.Notice) -> PackedStringArray:
	if notice == CalculatorModel.Notice.FRACTION_HELP:
		return PackedStringArray([Catalog.text(TITLE_FRACTION_HELP), printable(Catalog.text(TEXT_FRACTION_HELP))])
	var body := Catalog.text(StringName("calc_notice_%d" % notice))
	return PackedStringArray([Catalog.text(TITLE_ERROR), printable(body)])


## The original's text with its key pictures written out ("press [/]"), and its line breaks.
static func printable(raw: String) -> String:
	return HintSystem.printable(raw.replace("\u0091", "/")).replace("\r", "\n")


func show_notice(notice: CalculatorModel.Notice) -> void:
	var texts := texts_for(notice)
	title_label.text = texts[0]
	body_label.text = texts[1]
	show()
	ok_button.grab_focus()


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not visible or key_event == null:
		return
	get_viewport().set_input_as_handled()
	if key_event.pressed and not key_event.echo and key_event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_SPACE]:
		close()
