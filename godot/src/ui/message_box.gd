class_name MessageBoxView
extends Control
## The dialog that shows the `MessageQueue`'s current message: a title, a text, buttons.
##
## Teaches: containers and anchors. The panel is centred by a `CenterContainer`; its size comes from
## its text and buttons, not from numbers. All colours and fonts are the project Theme's
## (`ConsolePanel`, `ConsoleTitle`). A dimmed `ColorRect` behind it swallows mouse clicks so the
## game below cannot be touched while a message is up.
##
## Keyboard: Enter / Space press the focused button (the first one at the start), Left / Right move
## between buttons, Escape picks the LAST button ("No" / "Cancel"; "OK" for a single button) unless the
## message says otherwise (`Message.escape_choice`), Y / N answer a Yes / No question. The button with the focus
## when it opens is `Message.default_button`.
##
## The screen's `ModalHost` shows the queue through this view (`ModalHost.attach`): it calls `show_message` and gives the focus back
## to the screen when the box hides.

## The queue whose current message is shown (set by `ModalHost.attach`): the buttons close its messages.
var queue: MessageQueue

@onready var dim: ColorRect = %Dim
@onready var title_label: Label = %Title
@onready var body_label: RichTextLabel = %Body
@onready var button_row: HBoxContainer = %Buttons


func _ready() -> void:
	hide()


## Shows `message`, or hides the box when it is null.
func show_message(message: MessageQueue.Message) -> void:
	if message == null:
		hide()
		return
	title_label.text = message.title
	body_label.text = message.body
	for child in button_row.get_children():
		button_row.remove_child(child)
		child.queue_free()
	for i in message.buttons.size():
		var button := Button.new()
		button.text = message.buttons[i]
		button.custom_minimum_size = Vector2(72, 24)
		button.pressed.connect(queue.close_current.bind(i))
		button_row.add_child(button)
	show()
	(button_row.get_child(clampi(message.default_button, 0, button_row.get_child_count() - 1)) as Button).grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	var keycode: int = (event as InputEventKey).keycode
	if keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		var escape := queue.current.escape_choice if queue.current != null else MessageQueue.LAST_BUTTON
		queue.close_current(button_row.get_child_count() - 1 if escape == MessageQueue.LAST_BUTTON else escape)
	elif (keycode == KEY_Y or keycode == KEY_N) and button_row.get_child_count() == 2 \
			and (button_row.get_child(0) as Button).text == "Yes":
		# a Yes / No question also answers to its initials, like the original's dialogs (RunModalDialog: 'Y', 'N')
		get_viewport().set_input_as_handled()
		queue.close_current(0 if keycode == KEY_Y else 1)
