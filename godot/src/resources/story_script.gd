class_name StoryScript
extends Resource
## The opening story (`StoryPages`): its nine pages and how long each one stays. Decoded from `OpeningStoryPages`
## (0x42a9f1, OPENING.C) and turned into this Resource by the importer (`tools/import/step_story.py`).
##
## Teaches: a slideshow as data, and a duration as data. A page lasts as long as its speech but at least
## `minimum_page_ticks`; the view is told "this page holds at least N ticks" by this resource instead of knowing the
## number itself, so a replaced voice clip, or a skin, cannot change how long the page holds up the story.

@export var pages: Array[StoryPage] = []
## The picture behind every page.
@export var background: StringName = &""
## Where the heading, the frame and the caption go (window pixels).
@export var heading_position: Vector2 = Vector2.ZERO
@export var frame_position: Vector2 = Vector2.ZERO
@export var caption_position: Vector2 = Vector2.ZERO
## The blinking radar ring of page 5: its pictures, where it is, and how long each picture stays.
@export var ring_pictures: Array[StringName] = []
@export var ring_position: Vector2 = Vector2.ZERO
@export var ring_picture_ticks: float = 0.0
## A page lasts at least this long (365 ticks, 5 s), the last one waits up to 3285 ticks (45 s) for a key.
@export var minimum_page_ticks: float = 0.0
@export var last_page_ticks: float = 0.0
## The caption appears this many ticks after the page (the original draws the words a moment later).
@export var caption_delay_ticks: float = 0.0
## Where the numbers come from.
@export_multiline var provenance: String = ""


## How long page `index` holds up the story at least, in ticks.
func hold_ticks(index: int) -> float:
	return last_page_ticks if pages[index].last else minimum_page_ticks
