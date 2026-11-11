class_name Calculator
extends CalculatorPanel
## The on-screen calculator, drawn from the original's own picture.
##
## Teaches: building a UI on top of ART. The 292 x 130 picture already shows every key face, so the
## buttons are transparent `Button`s (theme variation "CalcKey": only hover, press and keyboard
## focus show) placed on the key rectangles the original registered as mouse hotspots
## (`CalculatorLayout`). Every key, mouse or keyboard, calls the same `press`, and the widget
## reports upward with ONE signal. The numbers are drawn by an `LcdDisplay` child.
##
## Keyboard (DESIGN 2.8): digits and `. + - * / =`, the letters F N S R C (Space = F), Enter submits.
##
## Every key, mouse or keyboard, goes through `input_key`: the click and the model's answer come at once, then the key
## stays lit for 12 ticks and the calculator takes no input meanwhile (`GetNumber` (0x41fb34) /
## `BlinkButton` (0x41b411): `set_alarm(0, 12)`, highlight, `wait_alarm`). A key that arrives meanwhile waits in a queue
## and is taken afterwards, like the original's input queue. `press` is the same key without the flash (tests).
## One exception, as in the original: while the display holds a RESULT, a command key (operator, =, Enter, N, S, R, C) goes
## through `BlinkButton`, which lights the key first and acts only when the 12 ticks are over; entry keys (digits, ".", F)
## act at once.
##
## Layout: this Control sits at the picture's window position (336, 266), so the buttons'
## rectangles are shifted by that.

## The player pressed Enter / the Enter button; `value` is the number on the display.
## Not emitted while a fraction is unfinished or the model refused the key (`notice_requested` then).
signal submitted(value: NumberValue)

## A key was pressed: the original plays its sound `calc_backspace` (`HighlightCalcKey` (0x41b4f1)) for each of the 22 keys.
signal sfx_requested(sfx: StringName)
## What the display shows changed (`text` is the display's text).
signal entry_changed(text: String)

## The model refused a key or reset itself and the player is to be told (`ShowCalcNoticeDialog` (0x420d8f)):
## a `CalculatorModel.Notice`.
signal notice_requested(notice: CalculatorModel.Notice)

## "calc_backspace" in the sound table, but the original uses it as THE calculator key click.
const SFX_KEY := &"calc_backspace"
## How long a pressed key stays lit and the calculator takes no input: `set_alarm(0, 12)` = 12 ticks of 1/73 s. The number is the
## rules' (`CalculatorModel.key_flash_ticks()`); this widget is told it and only turns it into seconds for its `Timer`.
const TICKS_PER_SECOND := TickMeter.TICKS_PER_SECOND
## The theme's looks of a key (`ThemeBuilder`): the invisible rectangle over the key's art, and the key lit for `key_flash_ticks`.
const KEY := &"CalcKey"
const KEY_LIT := &"CalcKeyLit"

var model := CalculatorModel.new()
## While false the calculator ignores the keyboard (a finished problem).
var keyboard_enabled: bool = true:
	set(value):
		keyboard_enabled = value
		set_process_unhandled_key_input(value)

@onready var keys: Control = %Keys

var _buttons: Dictionary = {}     # key name -> Button
var _flash_timer: Timer
var _flashing_key: String = ""    # the lit key while the flash lasts, else ""
var _waiting_keys: Array[String] = []     # keys that came in during a flash
var _deferred_key: String = ""            # a command key that acts when the flash ends


func _ready() -> void:
	_load_layout()
	_flash_timer = Timer.new()
	_flash_timer.one_shot = true
	_flash_timer.wait_time = TickMeter.seconds(CalculatorModel.key_flash_ticks())
	_flash_timer.timeout.connect(end_flash)
	add_child(_flash_timer)
	for key_name in _scene_layout.key_names:                 # (one button per key; where each goes is `_dress`'s)
		var button := Button.new()
		button.theme_type_variation = KEY
		button.focus_mode = Control.FOCUS_NONE               # the keyboard goes to the widget, not to a focused button
		button.tooltip_text = key_name
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS     # `pressed` on the mouse DOWN: the original clicks on the press
		button.pressed.connect(input_key.bind(key_name))     # bind: same handler, a different key each time
		keys.add_child(button)
		_buttons[key_name] = button
	_dress()
	SkinChoice.events.changed.connect(_on_skin_changed)
	_refresh()


## The skin in use is another: the calculator is dressed again.
func _on_skin_changed(_skin: GameSkin) -> void:
	_dress()


## Puts the calculator on as the skin in use shows it: the layout and its picture, the rectangle the layout gives it and the one of each key, and the display's layout. The one builder of the calculator's looks (`_ready` and a skin put on in the middle of a
## problem both call it): the picture is stretched to the layout's size, so a skin's picture of another size moves nothing. The keys' looks and the display's field are the theme's (`key` and `display`): they are looked up, not set here.
func _dress() -> void:
	layout = Catalog.skinned(_scene_layout) as CalculatorLayout
	_dress_panel(layout.picture_position, layout.picture, layout.picture_size, layout.display_origin_calculator)
	for i in layout.key_names.size():
		var button := _buttons.get(layout.key_names[i]) as Button
		if button != null:
			var rect := layout.key_rects[i]
			button.position = Vector2(rect.position - layout.picture_position)
			button.size = Vector2(rect.size)


## A key from the mouse or the keyboard: `press` it and light it for `FLASH_TICKS`. While a key is lit the new one waits.
func input_key(key: String) -> void:
	if not _flashing_key.is_empty():
		_waiting_keys.append(key)
		return
	if model.result_shown() and not CalculatorModel.is_entry_key(key) and key in _buttons:
		sfx_requested.emit(SFX_KEY)           # the click and the highlight at once, the key's work after the 12 ticks
		_deferred_key = key
	else:
		press(key)
	_start_flash(key)


## Feeds one key to the model (also used by tests) and updates the display. Enter does the pending operation first
## (the model's `Enter` is `=` and more); it submits only when the model ignored nothing and had nothing to complain about.
func press(key: String) -> void:
	if key in _buttons:                       # all 22 keys click, valid in the current state or not
		sfx_requested.emit(SFX_KEY)
	_apply(key)


## The key's work without its click: the model, the display, the notice or the submission.
func _apply(key: String) -> void:
	var notice := model.press(key)
	_refresh()
	if notice != CalculatorModel.Notice.NONE:
		notice_requested.emit(notice)
	elif key == "Enter" and model.submit_ready:
		var value := model.value()
		if value != null:
			submitted.emit(value)


## Clears the calculator for a new problem.
func reset() -> void:
	model = CalculatorModel.new()
	_waiting_keys.clear()
	_deferred_key = ""
	end_flash()
	_refresh()


## Whether a key is lit and input is being held back.
func is_flashing() -> bool:
	return not _flashing_key.is_empty()


func _start_flash(key: String) -> void:
	var button := _buttons.get(key) as Button
	if button == null:
		return
	_flashing_key = key
	_light(button)
	_flash_timer.start()


## The lit key wears the theme's `CalcKeyLit` look (`ThemeBuilder`: the `key` style's "pressed" look, also under the mouse). Nothing is copied: the button looks the variation up, so a skin put on during the 12 ticks shows in it.
func _light(button: Button) -> void:
	button.theme_type_variation = KEY_LIT


## The 12 ticks are over (or a test does not want to wait): the key goes dark and the next waiting key is taken.
func end_flash() -> void:
	_flash_timer.stop()
	var button := _buttons.get(_flashing_key) as Button
	if button != null:
		button.theme_type_variation = KEY
	_flashing_key = ""
	if not _deferred_key.is_empty():
		var key := _deferred_key
		_deferred_key = ""
		_apply(key)
	if not _waiting_keys.is_empty() and _flashing_key.is_empty():
		input_key(_waiting_keys.pop_front())


## Does the button of `key` wear the lit look (for tests)?
func looks_lit(key: String) -> bool:
	var button := _buttons.get(key) as Button
	return button != null and button.theme_type_variation == KEY_LIT


## The invisible button of `key` (for tests and for flashing it on a key press).
func button_for(key: String) -> Button:
	return _buttons.get(key)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or not visible:
		return
	var key := key_for_event(key_event)
	if key.is_empty():
		return
	get_viewport().set_input_as_handled()
	input_key(key)


## Which calculator key an event stands for ("" = none). The original reads typed CHARACTERS: `MainWindowProc`
## (0x41312f) turns WM_CHAR into `PostKeyEvent` (0x410b78)(character) and only the cursor / paging keys come from
## WM_KEYDOWN, so what counts is the character the key produced, with Shift applied ('+' is Shift+= on a US layout, a
## plain key elsewhere, and 8 with Shift is '*' there). So `unicode` decides whenever the event carries one; the
## `keycode` is only the fallback for events without a character (tests, remote control), plus the number pad.
## The characters taken are those of `GetNumber` (0x41fb34) / `BlinkButton` (0x41b411): 0-9 . + - * / =, Enter,
## Backspace, space (= F) and the letters of `CalcHotkeys` (0x441444) F S N R C in either case; also, as in
## `TranslateCalcKey` (0x41b843), the codes 2-6 (Ctrl+B, C, D, E, F; the mouse hotspot ids of the F S N R C keys,
## which a typed control character happens to equal) stand for F S N R C.
static func key_for_event(event: InputEventKey) -> String:
	match event.keycode:                                  # keys with a name but no (or a control) character
		KEY_ENTER, KEY_KP_ENTER:
			return "Enter"
		KEY_SPACE:
			return "F"                        # the jump table of `GetNumber` sends 0x20 to the F handler
		KEY_BACKSPACE:
			return "C"
	if event.ctrl_pressed and not event.alt_pressed and event.keycode >= KEY_B and event.keycode <= KEY_F:
		return "FSNRC"[event.keycode - KEY_B]
	if event.unicode > 0:
		var character := String.chr(event.unicode)
		if character in "0123456789.+-*/=":
			return character
		if character.to_upper() in "FNSRC":
			return character.to_upper()
		return ""                                         # a typed character the calculator does not know ('?' for Shift+/)
	match event.keycode:
		KEY_PERIOD, KEY_KP_PERIOD:
			return "."
		KEY_KP_ADD:
			return "+"
		KEY_MINUS, KEY_KP_SUBTRACT:
			return "-"
		KEY_KP_MULTIPLY:
			return "*"
		KEY_SLASH, KEY_KP_DIVIDE:
			return "/"
		KEY_EQUAL:
			return "="
	if event.keycode >= KEY_0 and event.keycode <= KEY_9:
		return String.chr(event.keycode)
	if event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
		return str(event.keycode - KEY_KP_0)
	if event.keycode in [KEY_F, KEY_N, KEY_S, KEY_R, KEY_C]:
		return OS.get_keycode_string(event.keycode)
	return ""


func _refresh() -> void:
	display.text = model.display_text()
	entry_changed.emit(display.text)
	display.fraction_flag = model.in_fraction_mode()
	display.operator = model.pending_operator()
	display.memory_flag = model.has_memory()
