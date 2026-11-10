class_name StoryPages
extends StorySegment
## The opening story: nine pages of pictures, text and speech ("Nine months ago, an elite team of astronauts and
## scientists began a top-secret research project in deep space ..."). Original: `OpeningStoryPages` (0x42a9f1) (OPENING.C)
## and the page player `PlayStoryPageSpeech` (0x42a817).
##
## Teaches: a data-driven slideshow. `data/story/story_script.tres` (a `StoryScript`, written by the importer) says what each
## page shows (the heading, the frame picture, the extra pictures) and how long it holds up the story, one function
## (`_show_page`) swaps the pictures, an `AnimationPlayer` fades each page in (a small timeline made here: the fade is
## ours), and an `AnimatedSprite2D` plays the blinking radar ring of page 5 (contrast: the sprite sheet animation of a
## fixed set of frames is `AnimatedSprite2D`'s job, the choreography of many nodes is `AnimationPlayer`'s).
## The words are pictures: the original draws its text in a font we do not have, but the page texts are also
## stored as finished bitmaps (2056-2064), so the real wording and look are kept.
##
## Pacing, as in the original: a page lasts as long as its speech and at least 5 seconds; Enter or a left click goes on
## to the next page (and cuts the speech off), Space / Escape end the story. The last page waits up to 45 seconds
## for a key or a click; when it runs out with none, `timed_out` tells the director to start the opening over.

const SCRIPT := preload("res://data/story/story_script.tres")
## The fade-in of a page (ours; the original draws a page at once), in seconds.
const FADE_SECONDS := 0.2

signal _page_over

var page_index: int = -1
## True when the last page ran out its time with no key and no click (not Enter, a click or Space / Escape): the
## original's opening then starts over (see `Opening`). `OpeningStoryPages` (0x42a9f1) returns 0 for it and for Enter
## alike; only Enter sets `OpeningEnded` (0x449e98).
var timed_out: bool = false
## Bumped whenever a page ends, so that the clock of an earlier page cannot end a later one.
var _generation: int = 0

@onready var page: Control = %Page
@onready var heading: TextureRect = %Heading
@onready var frame: TextureRect = %Frame
@onready var extras: Control = %Extras
@onready var caption: TextureRect = %Caption
@onready var ring: AnimatedSprite2D = %Ring
@onready var click_label: Label = %ClickLabel
@onready var animations: AnimationPlayer = %Animations


func _ready() -> void:
	%Background.texture = Assets.ui_picture(SCRIPT.background)
	heading.position = SCRIPT.heading_position
	frame.position = SCRIPT.frame_position
	caption.position = SCRIPT.caption_position
	ring.sprite_frames = _ring_frames()
	ring.position = SCRIPT.ring_position + Vector2(26, 21)       # (an AnimatedSprite2D is centred)
	click_label.text = Catalog.text(&"click_to_go_on")
	var cast := CutsceneCast.new(self)
	cast.bind(&"page", page)
	cast.bind(&"caption", caption)
	Cutscene.install_timeline(animations, &"show", _fade_in_timeline(), cast)
	_run()


## The radar ring's four pictures (`story_ring_0` .. `story_ring_3`) as a `SpriteFrames` for an `AnimatedSprite2D`.
func _ring_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 1.0 / CutsceneTimeline.seconds(SCRIPT.ring_picture_ticks))
	for picture in SCRIPT.ring_pictures:
		frames.add_frame(&"default", Assets.ui_picture(picture))
	return frames


## Every page fades in, and the caption follows 15 ticks later (as in the original). The fade is ours, so this timeline is
## made here and not by the importer.
func _fade_in_timeline() -> CutsceneTimeline:
	var fade := FADE_SECONDS * CutsceneTimeline.TICKS_PER_SECOND
	var timeline := CutsceneTimeline.made_in_code(0.5 * CutsceneTimeline.TICKS_PER_SECOND,
			"Ours: the fade-in of a page (0.2 s); the original draws a page at once. The caption's delay is the original's (15 ticks).")
	timeline.track(&"page", CutsceneTrack.PROP_FADE, [[0.0, 0.0], [fade, 1.0]], true)
	timeline.track(&"caption", CutsceneTrack.PROP_VISIBLE, [[0.0, false], [fade + SCRIPT.caption_delay_ticks, true]])
	return timeline


# --- the show -------------------------------------------------------------------------------------

## Plays the pages in order until the story is over or skipped.
func _run() -> void:
	for i in SCRIPT.pages.size():
		if done:
			return
		await _play_page(i)
	finish()


func _play_page(index: int) -> void:
	_show_page(index)
	var generation := _generation
	_page_clock(index, generation)
	await _page_over


## Swaps the pictures for page `index` (0-8) and fades it in.
func _show_page(index: int) -> void:
	page_index = index
	var data := SCRIPT.pages[index]
	heading.texture = Assets.ui_picture(data.heading)
	frame.texture = Assets.ui_picture(data.frame)
	caption.texture = Assets.ui_picture(data.caption)
	for child in extras.get_children():
		child.queue_free()
	for i in data.extra_pictures.size():
		var picture := TextureRect.new()
		picture.texture = Assets.ui_picture(data.extra_pictures[i])
		picture.position = data.extra_positions[i]
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		extras.add_child(picture)
	ring.visible = data.ring
	if data.ring:
		ring.play()
	else:
		ring.stop()
	click_label.visible = data.last
	animations.play(&"show")


## Speaks the page, then waits out the minimum time, then ends the page. `generation` makes the clock of a page
## that was already ended by Enter harmless.
func _page_clock(index: int, generation: int) -> void:
	var spoken := await Audio.speak(Catalog.voice_cues().story_page(index))          # (the ticks it took: the clips' recorded lengths)
	if done or generation != _generation:
		return
	var remaining := roundi(SCRIPT.hold_ticks(index)) - spoken
	if remaining > 0:
		await pause_ticks(remaining)                                                  # (stands still while the window is inactive)
	if not done and generation == _generation:
		timed_out = SCRIPT.pages[index].last
		_end_page()


func _end_page() -> void:
	_generation += 1
	_page_over.emit()


## Clicks. A left-button release anywhere is Enter on every page, because `OpeningSequence` (0x42b16b) keeps the whole-screen hotspot
## 0xd registered while the story runs (`Opening._input` forwards it to `StorySegment.click` -> `advance`). `OpeningStoryPages`
## (0x42a9f1) itself registers no hotspot and only acts on 0xd (Enter) and 0x20 / 0x1b (Space / Escape); "Click to go on."
## (string 11003) on the last page is therefore true, as on every other page.
##
## Nothing is handled here: the root `Control` takes no mouse events of its own.


## Enter: the next page (the speech of this one is cut off).
##
## Cutting the speech off ends `Audio.speak` inside `stop_voice` (it emits `voice_finished` at once), so the clock of this page wakes up
## in the middle of this call and, when the speech had counted its full hold already, ends the page ITSELF and the next page begins
## before `stop_voice` returns. Ending the page again here would end that new page too (one Enter, two pages). The original has no
## such race: `PlayStoryPageSpeech` (0x42a817) is one loop that sees the key. So the page is ended here only if the clock did not.
func advance() -> void:
	if done:
		return
	var generation := _generation
	Audio.stop_voice()
	if generation == _generation:
		_end_page()
