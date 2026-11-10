class_name PackWarning
extends Control
## The screen the game opens on when its chain of packs is not whole (`Packs.fallback_reason()` is not null): no pack was found, the one asked for is not there, a pack has
## errors or a missing base, or the chain lacks things the game needs. What it is depends on `Packs.dev_fallback` when the chain was chosen.
##
##   * DEBUG (`dev_fallback` on, `Packs.is_refused()` false): the dev pack is under the chain and answers what the chain lacks. The screen says what happened
##     (`Fallback.text()`), how many things are missing and that the dev pack's placeholders stand in for them, and where to read (`Fallback.advice()`). One key or
##     click goes on into the game.
##   * RELEASE (`dev_fallback` off, `is_refused()` true): the game does not play this chain. The screen states the problem, the missing count when there is one and
##     where to read, and blocks play. P (or the Pack screen button) opens the pack screen to choose another pack, and the choice is checked again; any other key,
##     any click that is not on a button, or the Quit button quits.
##
## `--pack=dev` chooses dev on purpose, and so does a pack laid over `dev`: those chains are whole, `Main.first_scene` skips this screen, and this scene only speaks.
##
## Teaches: a screen is a scene plus a small script that SHOWS state somebody else owns (`Packs`), with few ways out. `_unhandled_input` lets any button or dialog that
## wants the key have it first (the buttons take no focus, so a key never presses one); a modifier key on its own does not count as "a key"; a dialog opened over the
## screen is a child that closes itself and tells the screen what happened by a signal.

## The words under the reason; kept in one place so a test can ask for them.
const NOT_FOR_PLAY := "The dev pack is placeholder content for developers: coloured shapes with their names written on them, and a voice that says what each sound is. It is not meant for play."
## With a chain that lacks things: %s is the line that says how many.
const STANDS_IN := "%s The dev pack's placeholders stand in for them: coloured shapes with their names written on them, and a voice that says what each sound is. They are not meant for play."
const PROMPT := "Press any key or click to go on with the dev pack."
const PROMPT_REFUSED := "Press P for the pack screen. Any other key or click quits."
const TITLE := "The dev pack is in use"
const TITLE_REFUSED := "This game cannot be played"

## Keys that are only a modifier: they do not leave the screen.
const MODIFIER_KEYS: Array[Key] = [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]
const PACK_DIALOG := preload("res://src/ui/pack_dialog.tscn")

## Emitted when the player goes on (the router has been asked for the opening).
signal continued
## Emitted when the player quits (the game exits, unless `SceneRouter.dry_run`).
signal quit_requested

@onready var title_label: Label = %Title
@onready var reason_label: Label = %Reason
@onready var missing_label: Label = %Missing
@onready var not_for_play_label: Label = %NotForPlay
@onready var where_label: Label = %WhereToRead
@onready var prompt_label: Label = %Prompt
@onready var pack_screen_button: Button = %PackScreen
@onready var quit_button: Button = %Quit

var _left := false
var _dialog: PackDialog


func _ready() -> void:
	pack_screen_button.pressed.connect(open_pack_screen)
	quit_button.pressed.connect(quit)
	show_state()


## Writes what `Packs` says now into the labels (also after a choice on the pack screen that did not make the chain whole).
func show_state() -> void:
	var reason := Packs.fallback_reason()
	var refused := Packs.is_refused()
	title_label.text = TITLE_REFUSED if refused else TITLE
	reason_label.text = reason.text() if reason != null else ""
	missing_label.text = reason.missing_text() if reason != null else ""
	missing_label.visible = not missing_label.text.is_empty() and refused
	where_label.text = reason.advice() if reason != null else ""
	if refused:
		not_for_play_label.text = ""
	elif reason != null and reason.missing > 0:
		not_for_play_label.text = STANDS_IN % reason.missing_text()
	else:
		not_for_play_label.text = NOT_FOR_PLAY
	not_for_play_label.visible = not refused
	prompt_label.text = PROMPT_REFUSED if refused else PROMPT
	pack_screen_button.visible = refused
	quit_button.visible = refused


func _unhandled_input(event: InputEvent) -> void:
	if _dialog != null:
		return                                                     # (the pack screen has the keys and the mouse)
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and not MODIFIER_KEYS.has(key.keycode):
			get_viewport().set_input_as_handled()
			if Packs.is_refused():
				if key.keycode == KEY_P:
					open_pack_screen()
				else:
					quit()
			else:
				go_on()
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			get_viewport().set_input_as_handled()
			if Packs.is_refused():
				quit()
			else:
				go_on()


## Leaves for the opening sequence, once. A refused chain is never played: it does nothing.
func go_on() -> void:
	if _left or Packs.is_refused():
		return
	_left = true
	continued.emit()
	SceneRouter.go_to(SceneRouter.OPENING)


## Quits the game, once.
func quit() -> void:
	if _left:
		return
	_left = true
	quit_requested.emit()
	if not SceneRouter.dry_run:
		get_tree().quit()


## Opens the pack screen over this one, with the button that chooses a pack. A pack chosen there is checked again (`Packs.choose`): a whole chain goes on to the opening, anything
## else is shown here again.
func open_pack_screen() -> void:
	if _left or _dialog != null:
		return
	_dialog = PACK_DIALOG.instantiate()
	_dialog.choosing = true
	_dialog.closed.connect(_close_pack_screen)
	_dialog.used.connect(_on_used)
	add_child(_dialog)


func _close_pack_screen() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null
	show_state()


func _on_used(_id: StringName) -> void:
	_close_pack_screen()
	if Packs.fallback_reason() == null:
		go_on()
