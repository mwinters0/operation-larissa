class_name MessageQueue
extends RefCounted
## The game's message line: hints, "Surface Ship Message", "Computer Message" and questions
## ("Do you want to exit?") wait here and are shown ONE AT A TIME, in the order they were posted.
##
## Teaches: a queue as the cure for "two things want the one dialog at once" (a hint and a ship
## message in the same frame), signals as the way a model talks to its view (`MessageBoxView` listens
## to `message_shown`), `await` on a signal for the answer, and the `GameClock` as the game's
## time (a message can close itself after N ticks; a message that `pauses_game` holds the clock
## while it is up, like the original's modal dialogs).
##
##     var message := queue.post("Exit", "Do you want to exit?", ["Yes", "No"])
##     var choice: int = await message.closed        # 0 = Yes, 1 = No
##
## The class is pure logic (no nodes: its clock is just something that ticks), so `tests/engine/test_message_queue.gd` drives it directly.

## `Message.escape_choice` value: Escape presses the last button.
const LAST_BUTTON := -3

## One message. `closed(choice)` fires when the player (or the timer) ends it; `choice` is the
## index of the pressed button, or -1 when the timer closed it.
class Message extends RefCounted:
	signal closed(choice: int)
	var title: String = ""
	var body: String = ""
	var buttons: PackedStringArray = PackedStringArray(["OK"])
	## Stop the game clock while the message is up (modal, like the original's dialogs).
	var pauses_game: bool = true
	## Close by itself after this many game ticks (0 = wait for a button). Only counts ticks that happen,
	## so it is meant for messages that do NOT pause the game.
	var auto_close_ticks: int = 0
	var ticks_left: int = 0
	var choice: int = -2          # -2 = still open
	## The button that has the focus (and that Enter presses) when the message opens. The original's Yes / No
	## dialogs (`RunModalDialog` 0x4174ec) start on the button given in the dialog record, often "No".
	var default_button: int = 0
	## What Escape answers: `LAST_BUTTON` ("No" / "Cancel" / "OK") or a fixed value. The original's Options
	## questions answer -1 for Escape, which means "leave the setting as it is".
	var escape_choice: int = MessageQueue.LAST_BUTTON

## The message on screen changed. `message` is null when the queue is empty.
signal message_shown(message: Message)
signal message_closed(message: Message, choice: int)
## The last message was closed and nothing is waiting.
signal emptied

var current: Message = null
var _waiting: Array[Message] = []
var _clock: Object


## `clock` is anything with a `tick(count)` signal and `hold()` / `release()` methods: in the game it is the `GameClock` autoload
## (`MessageQueue.new(GameClock)`), in a test a stand-in. The queue does not name the autoload itself, so it stays a plain object that
## the rules (`GameFlow`) may hold (`tests/engine/test_rules_are_plain_objects.gd`).
func _init(clock: Object) -> void:
	_clock = clock
	_clock.tick.connect(_on_tick)


## Adds a message. It is shown at once if nothing else is, otherwise after those before it.
func post(title: String, body: String, buttons: PackedStringArray = PackedStringArray(["OK"]),
		pauses_game: bool = true, auto_close_ticks: int = 0, default_button: int = 0,
		escape_choice: int = LAST_BUTTON) -> Message:
	var message := Message.new()
	message.default_button = default_button
	message.escape_choice = escape_choice
	message.title = title
	message.body = body
	message.buttons = buttons
	message.pauses_game = pauses_game
	message.auto_close_ticks = auto_close_ticks
	message.ticks_left = auto_close_ticks
	_waiting.append(message)
	if current == null:
		_show_next()
	return message


## A message from the surface ship (the original's dialog title).
func post_ship(text: String) -> Message:
	return post("Surface Ship Message", text)


## A message from the onboard computer.
func post_computer(text: String) -> Message:
	return post("Computer Message", text)


## Everything still waiting behind the current message.
func waiting_count() -> int:
	return _waiting.size()


func is_open() -> bool:
	return current != null


## Ends the current message with the pressed button's index and shows the next one.
func close_current(choice: int = 0) -> void:
	if current == null:
		return
	var message := current
	current = null
	message.choice = choice
	if message.pauses_game:
		_clock.release()
	message_closed.emit(message, choice)
	message.closed.emit(choice)
	if current == null:                      # (a handler of `closed` may have posted the next message already: leave it)
		_show_next()


## The scene that shows the queue is going away: every message is forgotten without an answer (no `closed`, so a step that waits for
## one never goes on), the clock hold of the one on screen is given back, and the queue stops listening to the clock.
func discard() -> void:
	if current != null and current.pauses_game:
		_clock.release()
	current = null
	_waiting.clear()
	if _clock.tick.is_connected(_on_tick):
		_clock.tick.disconnect(_on_tick)


func _show_next() -> void:
	if _waiting.is_empty():
		message_shown.emit(null)
		emptied.emit()
		return
	current = _waiting.pop_front()
	if current.pauses_game:
		_clock.hold()                       # a hold, not "pause and remember": see `GameClock.hold`
	message_shown.emit(current)


## One tick of game time passed: a self-closing message counts down.
func _on_tick(_count: int) -> void:
	if current == null or current.auto_close_ticks <= 0:
		return
	current.ticks_left -= 1                  # `count` is the running total, one call = one tick
	if current.ticks_left <= 0:
		close_current(-1)
