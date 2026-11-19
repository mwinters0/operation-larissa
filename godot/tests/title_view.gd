class_name TitleView
extends RefCounted
## What a test asks of the title scene (the `TimelineSegment` that plays the scene file `title`): which of its three phases it is in, its ship, whether its prompt is up. A TEST helper: `test_opening` and `test_opening_legacy` read the
## same phases, so the dev pack's title and the original's are held to one reading of "SHIP, REVEAL, PROMPT".
##
## Teaches: the phases of the title are not a state of the segment (it knows only which timeline of its scene plays and whether a `prompt` has begun); a test names them from those two facts.

const SHIP := &"ship"          ## the timeline `title_ship` plays
const REVEAL := &"reveal"      ## `title_reveal` plays, no prompt yet
const PROMPT := &"prompt"      ## the buttons are up


static func phase(title: TimelineSegment) -> StringName:
	if title.prompting:
		return PROMPT
	return SHIP if title.script_player.current_animation == "title_ship" else REVEAL


## The ship: the stage's group actor `ship`, which carries the hull, the radar and the hook.
static func ship(title: TimelineSegment) -> Node2D:
	return title.cast.node_of(&"ship") as Node2D


static func prompt_visible(title: TimelineSegment) -> bool:
	return not title.buttons.is_empty() and title.buttons.values().all(func(button: TextureButton) -> bool: return button.visible)
