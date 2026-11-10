class_name GenericFinale
extends StorySegment
## The end of a game that has no closing scene of its own: a picture and a few lines of text, the way a student's campaign says
## "well done". `Game.show_closing` puts it up when `Campaign.closing_scene` is none of the original's two ("voyager", "expert"); what it
## shows is the campaign's own data (`Campaign.finale_text`, `finale_picture`), and when it is over the flow goes on to the Hall of Fame
## exactly as it does after the original's scenes.
##
## Teaches: the smallest `StorySegment` there is. The base class already is the whole contract (`finished`, `advance`, `skip`), so a scene
## that only has to show something and wait for a key adds almost nothing: it fills three nodes from data and lets `Game._closing_key` do
## the keys (Enter goes on, Space / Escape skip), which is why this file contains no input handling for the keyboard. A left click goes on
## too, like the story pages. The scene has no timer: like the original's closing pages it waits for the player.
##
## The text and the picture are resolved by the campaign (`Campaign.finale_message()`, `finale_texture()`), so the same scene shows a
## text of the original's string table or one typed into the campaign, a picture of the game's registry or one of the student's own files.
## A campaign with no text or no picture just shows the other; with neither, the campaign's name and the "continue" line.

## Where the picture goes: centred in the upper part of the window (the lines go under it).
const PICTURE_BOX := Rect2(20, 16, 600, 230)

@onready var picture: TextureRect = %Picture
@onready var title_label: Label = %Title
@onready var message_label: Label = %Message
@onready var continue_label: Label = %Continue

## The campaign being finished (set by `show_finale`).
var campaign: Campaign


func _ready() -> void:
	picture.position = PICTURE_BOX.position
	picture.size = PICTURE_BOX.size
	continue_label.text = Catalog.text(&"click_to_go_on")


## Fills the scene from `finished_campaign` (call it after the scene is in the tree).
func show_finale(finished_campaign: Campaign) -> void:
	campaign = finished_campaign
	var texture := campaign.finale_texture()
	picture.texture = texture
	picture.visible = texture != null
	title_label.text = campaign.display_title()
	message_label.text = campaign.finale_message()


## A left click goes on, like Enter.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and not button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		click(button.position)
