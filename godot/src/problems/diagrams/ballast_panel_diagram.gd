class_name BallastPanelDiagram
extends DiagramBase
## Types 28 and 29, Ballast Control Panel: ten weight buttons and a "Done" button on the panel picture.
## The player picks weights whose sum is the target and presses Done.
##
## Teaches: a DRAWN widget. Instead of Button nodes, the panel draws its own buttons from the original's
## pictures and handles mouse and keys itself (`_gui_input`, `_unhandled_key_input`): a state (`selected`,
## `cursor`), a pure `_build()` that turns the state into items, and a signal when the player is done.
##
## Keys [V, `GetBallastAnswer` (0x4196e8)]: '8' / '2' and the up / down arrows move the red cursor up / down the column
## (past the end of a column it goes to Done, and from Done back to the column's far end), '4' / '6' and the
## left / right arrows switch to the other column, Enter toggles the weight under the cursor (or presses Done).
## Deliberate deviation: Space does the same as Enter (the original ignores it); every other digit is ignored. The mouse acts when the left button is RELEASED (`PollInput` (0x410c7d)
## turns the left-button-up event into the hotspot id): it moves the cursor to the weight, toggles it, or presses Done.

## The player pressed Done. `mask` has bit i set for weight i; the pressed OK picture stays for `hold_ticks` ticks (the panel's
## data) before the answer is judged. The panel only SHOWS the hold: whoever owns the problem (`ProblemFlow`) counts the ticks.
signal done_pressed(mask: int, hold_ticks: int)
## (A switched weight button plays its sound `click` through `DiagramBase.sfx_requested`.)

const SFX_CLICK := &"click"

## Bit i is set if weight i is switched on.
var selected: int = 0
## The weight under the red cursor, 0-9, or 10 for the Done button.
var cursor: int = 0
## Asked again after the keys were switched off (the second try): the panel is ready, not pressed, and the cursor is on weight 0,
## as `GetBallastAnswer` (0x4196e8) keeps it in a local that starts at 0 on every entry; the chosen weights (`selected`) stay.
var keyboard_enabled: bool = true:
	set(value):
		var was_enabled := keyboard_enabled
		keyboard_enabled = value
		set_process_unhandled_key_input(value)
		if value and not was_enabled:
			cursor = 0
			_done_pressed = false
			_rebuild()
		elif value and _done_pressed:
			_done_pressed = false
			_rebuild()
## Done was pressed and the pressed OK picture is held (for `total.hold_ticks`, counted by the flow).
var _done_pressed: bool = false


func _init() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _build() -> void:
	add_spec_items(spec["items"])
	var weights: Dictionary = spec["weights"]
	var labels := AnswerChecker.denomination_labels(type, level)
	for i in slot_count():
		var at := slot_position(i)
		add_picture(weights["selected_pic"] if selected & (1 << i) else weights["slot_pic"], at)
		add_text(labels[i], at + Vector2(0, weights["label_offset"][1]), slot_size().x, false, weights["label_color"])
	var total: Dictionary = spec["total"]
	if _done_pressed:                                  # Done was pressed: the pressed OK picture instead of the button and cursor
		add_picture(total["done_pic"], vector(total["pos"]))
	else:
		add_picture(total["idle_pic"], vector(total["pos"]))
	if _done_pressed:
		pass                                           # (no cursor on the pressed picture)
	elif cursor < slot_count():                          # the red frame goes on top of the button it marks
		add_picture(weights["cursor_pic"], slot_position(cursor))
	else:
		add_picture(total["focus_pic"], vector(total["pos"]))
	# the yellow marker shows whether this panel fills (28) or drains (29) the tanks
	add_picture(spec["button"]["pic"], vector(spec["button"]["pos"]))


func slot_count() -> int:
	return spec["weights"]["pos"].size()


func slot_position(i: int) -> Vector2:
	return vector(spec["weights"]["pos"][i])


## The size of a weight button and of the Done button. They are in the type's data (the importer wrote the original
## pictures' sizes there), so the clickable rectangles never depend on the textures that are loaded.
func slot_size() -> Vector2:
	return vector(spec["weights"]["slot_size"])


func done_size() -> Vector2:
	return vector(spec["total"]["size"])


## The weights' values, for the sum.
func values() -> PackedInt32Array:
	return AnswerChecker.denominations(type, level)


## Sum of the weights that are switched on.
func sum() -> int:
	var total := 0
	for i in slot_count():
		if selected & (1 << i):
			total += values()[i]
	return total


func toggle(index: int) -> void:
	if _done_pressed:
		return
	sfx_requested.emit(SFX_CLICK)
	selected ^= 1 << index
	cursor = index
	_rebuild()


func _rebuild() -> void:
	items.clear()
	_build()
	queue_redraw()


## Which button is at window position `at`: 0-9 a weight, 10 Done, -1 nothing.
func button_at(at: Vector2) -> int:
	for i in slot_count():
		if Rect2(slot_position(i), slot_size()).has_point(at):
			return i
	if Rect2(vector(spec["total"]["pos"]), done_size()).has_point(at):
		return slot_count()
	return -1


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.pressed or click.button_index != MOUSE_BUTTON_LEFT:        # (acts on release)
		return
	_press(button_at(click.position))


func _press(index: int) -> void:
	if index < 0 or _done_pressed:
		return
	if index == slot_count():
		_press_done()
	else:
		toggle(index)


## `GetBallastAnswer` (0x4196e8): Done clicks (0x22) like every button, shows the pressed OK picture, waits 73 ticks (1 s)
## and only then hands the selection to the answer check. The 73 are data (`total.hold_ticks`); the wait is the flow's.
func _press_done() -> void:
	sfx_requested.emit(SFX_CLICK)
	_done_pressed = true
	_rebuild()
	done_pressed.emit(selected, hold_ticks())


## How long the pressed OK picture is held, in ticks (data).
func hold_ticks() -> int:
	return int(spec["total"]["hold_ticks"])


## True while the pressed OK picture is held (nothing can be changed then).
func is_done_pressed() -> bool:
	return _done_pressed


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key: int = key_event.keycode
	if key >= KEY_KP_0 and key <= KEY_KP_9:           # a keypad digit is the same character as the digit
		key = key - KEY_KP_0 + KEY_0
	@warning_ignore("integer_division")
	var half := slot_count() / 2                      # two columns of five weights, Done below them
	var done := slot_count()
	match key:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled()
			_press(cursor)
		KEY_UP, KEY_8:
			get_viewport().set_input_as_handled()
			cursor = done if cursor % half == 0 and cursor < done else (half - 1 if cursor == done else cursor - 1)
			_rebuild()
		KEY_DOWN, KEY_2:
			get_viewport().set_input_as_handled()
			cursor = done if cursor % half == half - 1 and cursor < done else (0 if cursor == done else cursor + 1)
			_rebuild()
		KEY_LEFT, KEY_RIGHT, KEY_4, KEY_6:
			get_viewport().set_input_as_handled()
			if cursor < half:
				cursor += half
			elif cursor < done:
				cursor -= half
			_rebuild()
