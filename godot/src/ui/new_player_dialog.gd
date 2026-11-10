class_name NewPlayerDialog
extends Control
## "Enter New Player Name", then "Choose a Game Level" (Voyager, Expert, or any other campaign there is).
##
## Teaches: `LineEdit` with `max_length` (eight characters, the original's limit) and a filter on `text_changed`
## that applies the original's key rules, a dialog that has two steps shown one after the other by toggling panels,
## and keyboard-first design: Enter confirms, Escape cancels the whole dialog, the first button of each step has focus. The words
## are the original's (11183-11184, 11189-11190, 11258-11259).
##
## Original `EnterNewPlayerNameDialog` (0x4305ae): the box takes at most 8 characters; the first one is made upper
## case; a blank is accepted only after the first character; Backspace erases the last character; Enter with an empty
## name does nothing; Escape cancels. `PlayerProfile.typed_name` holds those rules; this dialog only applies them.

## `campaign_id` is the id of the campaign chosen (`Campaign.id`: "voyager", "expert", or a campaign of its own).
signal confirmed(player_name: String, campaign_id: StringName)
signal cancelled

@onready var name_panel: PanelContainer = %NamePanel
@onready var name_title: Label = %NameTitle
@onready var name_text: Label = %NameText
@onready var name_edit: LineEdit = %NameEdit
@onready var game_panel: PanelContainer = %GamePanel
@onready var game_title: Label = %GameTitle
@onready var game_text: Label = %GameText
@onready var voyager_button: Button = %Voyager
@onready var expert_button: Button = %Expert

var _chosen_name: String = ""


func _ready() -> void:
	name_title.text = Catalog.text(&"new_player_title")
	name_text.text = Catalog.text(&"new_player_text").replace("\r", "\n").replace("\u0017\u0018", "Enter").strip_edges()
	game_title.text = Catalog.text(&"game_level_title")
	game_text.text = Catalog.text(&"game_level_text").replace("\r", "\n").strip_edges()
	_offer_campaigns()
	name_edit.max_length = PlayerProfile.NAME_MAX
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.text_submitted.connect(_on_name_submitted)
	_show_name_step()


## One button per campaign (`Catalog.campaigns()`: the original's two first, then the others by id), each with the campaign's own caption.
## The scene has the original's two buttons, which the first two campaigns use; every further campaign gets a copy of the second, added
## below it in the same column (a `VBoxContainer` stacks them, and Up / Down move the focus between them).
func _offer_campaigns() -> void:
	var offered := Catalog.campaigns()
	var buttons: Array[Button] = [voyager_button, expert_button]
	for i in offered.size():
		if i >= buttons.size():
			var copy := expert_button.duplicate() as Button
			copy.unique_name_in_owner = false
			copy.name = "Campaign%d" % i
			expert_button.get_parent().add_child(copy)
			buttons.append(copy)
		buttons[i].text = offered[i].new_game_label()
		buttons[i].pressed.connect(_choose.bind(offered[i].id))
	for i in range(offered.size(), buttons.size()):
		buttons[i].hide()


func _show_name_step() -> void:
	name_panel.show()
	game_panel.hide()
	name_edit.grab_focus()


## Typing and pasting go through the original's key rules; the caret keeps its place.
func _on_name_changed(text: String) -> void:
	var allowed := PlayerProfile.typed_name(text)
	if allowed == text:
		return
	var caret := name_edit.caret_column
	name_edit.text = allowed
	name_edit.caret_column = mini(caret, allowed.length())


func _on_name_submitted(text: String) -> void:
	_chosen_name = PlayerProfile.typed_name(text)
	if _chosen_name.is_empty():
		return
	name_panel.hide()
	game_panel.show()
	voyager_button.grab_focus()


func _choose(campaign_id: StringName) -> void:
	confirmed.emit(_chosen_name, campaign_id)


## Escape leaves the dialog from either step: in "Choose a Game Level" `ChooseGameLevelDialog` (0x43013f) answers -1 for
## Esc and `AddNewPlayer` (0x430851) then returns -1 too, so the whole New is cancelled (no step back to the name).
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancelled.emit()
