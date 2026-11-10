class_name Opening
extends Control
## The game's first scene: the opening sequence (news cartoon, title, story) and then the sign-in screen.
##
## Teaches: a DIRECTOR. Each part of the opening is its own scene (`NewsCartoon`, `TitleScene`, `StoryPages`)
## built on the same small interface (`StorySegment`: `finished`, `advance()`, `skip()`). This script
## instantiates them one after the other and reads the keys in one place:
##
##   Enter            go on to the next part of what is playing (cartoon -> title -> Intro -> next page)
##   left click       the same as Enter, anywhere on the screen, in every part (the buttons of the title prompt excepted)
##   Space / Escape   skip the whole opening and go to the sign-in screen
##
## Like the original (`OpeningSequence` 0x42b16b) it loops ("attract mode"): when the last story page runs out its time with
## no key and no click, the whole opening starts over from the news cartoon, without limit. Only Space / Escape, the title's
## Start button, and Enter or a click on the last page lead to sign-in. Started alone it ends by changing to the sign-in scene
## too, so the whole path title -> opening -> sign-in can be tried from this scene.

const NEWS_CARTOON := preload("res://src/story/news_cartoon.tscn")
const TITLE_SCENE := preload("res://src/story/title_scene.tscn")
const STORY_PAGES := preload("res://src/story/story_pages.tscn")

## Set by tests that only want to look at the director: the sequence still runs, but nothing changes scene.
var go_to_sign_in: bool = true

var current: StorySegment
var _skipped: bool = false
## True while the window does not have the focus: the whole opening stands still (see `set_window_active`).
var window_paused: bool = false
## Instance id of the part that was playing when the left button went down (0: none); see `_input`.
var _press_part_id: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS       # the director must hear the focus coming back while the tree is paused
	Audio.stop_music()
	Audio.apply_profile(null)
	_run()


func _run() -> void:
	var again := true
	while again:
		again = await _play_parts()
		if again:
			_start_over()
	_leave()


## One pass: the cartoon, the title, the story. True when the pass ends the way that makes the original start over: the last
## story page timed out (`OpeningStoryPages` 0x42a9f1 returned 0 with `OpeningEnded` 0x449e98 still 0).
func _play_parts() -> bool:
	await _play(NEWS_CARTOON)
	if _skipped:
		return false
	var title := (await _play(TITLE_SCENE)) as TitleScene
	if _skipped or not title.wants_intro:
		return false
	var story := (await _play(STORY_PAGES)) as StoryPages
	return story.timed_out and not _skipped


## The end of a pass that goes round again: `OpeningMusicCue(6)` (0x42b0f9) stops the song and the loop of `OpeningSequence` begins
## again at its top, where the cartoon starts its own song (9502) and its speech from the first clip. Every part is a new scene,
## so nothing else is carried over.
func _start_over() -> void:
	Audio.stop_music()
	Audio.stop_voice()


## The window lost / regained the focus (Godot sends these two notifications to every node).
##
## The original's opening stands still while the window is not the active one: `MainWindowProc` (0x41312f) handles
## WM_ACTIVATE by `PauseSoundOnDeactivate` (0x413847) (active flag `WindowActive` 0x440d80 = 0, `pause_sound`: `KillWave` +
## the song paused), and every loop of `OpeningStoryPages` (0x42a9f1) / the cartoon / the title polls the input with
## `PeekInput` (0x410d50) -> `PollInputEvent` (0x410bc5), which does not return while the flag is 0. So the pictures freeze,
## no effect or clip starts, and `ResumeSoundOnActivate` (0x413861) lets the song go on from the same place.
## (The original's alarms run on the real clock, so a page can time out meanwhile; here the page's clock stops too.)
func _notification(what: int) -> void:
	if not WindowFocus.enabled:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_window_active(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_window_active(true)


## Freezes (false) or releases (true) the running part: its animations, tweens and timers stop with the scene tree, `Audio`
## (always running) kills the sound effect / clip and pauses the song by its own focus handling. Also callable by tests.
func set_window_active(active: bool) -> void:
	window_paused = not active
	get_tree().paused = window_paused


func _exit_tree() -> void:
	if window_paused:
		get_tree().paused = false


## Instantiates `scene`, waits until it is over and returns it (the caller may want to ask it something).
func _play(scene: PackedScene) -> StorySegment:
	current = scene.instantiate()
	current.process_mode = Node.PROCESS_MODE_PAUSABLE     # (this node is "always": only the part stands still)
	add_child(current)
	await current.finished
	var segment := current
	current = null
	segment.queue_free()
	return segment


func _leave() -> void:
	set_window_active(true)
	Audio.stop_music()
	Audio.stop_voice()
	if go_to_sign_in:
		SceneRouter.go_to(SceneRouter.SIGN_IN)


## Mouse clicks. `OpeningSequence` (0x42b16b) registers the hotspot 0xd over the whole 640 x 400 screen (`AddHotspot` 0x415d15) when
## it starts and removes it when it leaves (0x42b724); `PollInput` (0x410c7d) gives a left-button RELEASE inside a hotspot the
## bare id, i.e. 0xd = Enter, in the cartoon, the ship scene, the title reveal, the prompt and every story page alike. (The
## press gives 0x800d, which every loop discards.)
##
## Deliberate deviation from the original: in the original the release that ends a click on the Intro button arrives after the story
## has begun and acts as an Enter on story page 1 (so page 1 flashes by). Here a release whose press happened in an EARLIER part
## (the part that was playing at the press has since ended) is swallowed, so page 1 shows normally; any later click is an Enter.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_press_part_id = current.get_instance_id() if current != null else 0
		return
	var pressed_in := _press_part_id
	_press_part_id = 0
	if current == null or window_paused:
		return
	if pressed_in != 0 and pressed_in != current.get_instance_id():
		return                                                # the deliberate deviation above
	current.click(button.position)


func _unhandled_key_input(event: InputEvent) -> void:
	if current == null or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_ENTER, KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			current.advance()
		KEY_SPACE, KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_skipped = true
			current.skip()
