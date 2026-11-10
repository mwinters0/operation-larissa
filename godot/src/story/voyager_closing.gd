class_name VoyagerClosing
extends StorySegment
## The end of the Voyager game: the sub rises with the Substance X sample, turns, changes into a helicopter
## and flies off; then the surface ship congratulates the player on three pages. Original:
## `VoyagerClosingSequence` (CLOSING.C, called from `DoAction` in sector 30, screen 2, once the finale
## creature has set the semaphore bit 15) and `VoyagerClosingPages` (0x41c5f2).
##
## Teaches: a cutscene laid over the running game. The sector keeps showing underneath (this scene has a
## transparent background and is added to a `CanvasLayer` by `Game`); a clipped `Control` keeps the helicopter
## inside the playfield. The choreography is DATA again, but data with a twist: the finale starts wherever the sub is, so
## the flight cannot be one fixed file. `data/story/voyager_closing_script.tres` (a `VoyagerClosingScript`) holds the
## original's loop counts and `timeline()` runs them for the place the sub is in, giving a `CutsceneTimeline` that the
## usual `Cutscene.animation()` plays. The three message pages are an ordinary `await` loop on the `MessageQueue`.
## Coordinates are the original's WINDOW pixels (SubX, SubY = the top-left of the picture); `Playfield` is at (16, 32), and
## the cast subtracts that for the nodes inside it.
##
## What the original does, in 6-tick steps (0.082 s): the sub rises 4 px per step for 18 steps; its sprite
## turns step by step until it shows cell 2; sound 0x2c and the helicopter appears in three pictures (12 ticks each);
## sound 0x2d, 15 steps of 8 px up with spinning rotor; then 8 px to the left per step until the helicopter has left the
## playfield. (The music is stopped for the sequence in the Voyager game.)

const SCRIPT := preload("res://data/story/voyager_closing_script.tres")
const PAGES := 3

var messages := MessageQueue.new(GameClock)
## Shows `messages` in the message box (a signal does not keep its RefCounted target alive: the scene holds it).
var modals: ModalHost
var _pages_started: bool = false

@onready var playfield: Control = %Playfield
@onready var sub: AnimatedSprite2D = %Sub
@onready var heli_body: Sprite2D = %HeliBody
@onready var heli_rotor: Sprite2D = %HeliRotor
@onready var animations: AnimationPlayer = %Animations
@onready var message_view: MessageBoxView = %MessageBox


## Begins the sequence with the sub at window position `sub_x`, `sub_y` showing cell `cell`.
func start(sub_x: int, sub_y: int, cell: int) -> void:
	sub.sprite_frames = Catalog.sub_frames()
	sub.animation = &"all"
	sub.pause()
	modals = ModalHost.new(self, [])                                      # (nothing under the box to put to sleep or to focus)
	modals.attach(messages, message_view)
	var cast := CutsceneCast.new(self)
	cast.sub_tuning = GameState.tuning.sub
	cast.bind(&"sub", sub)
	cast.bind(&"helicopter", heli_body)
	cast.bind(&"rotor", heli_rotor)
	Cutscene.install_timeline(animations, &"closing", SCRIPT.timeline(sub_x, sub_y, cell), cast)
	animations.play(&"closing")


## The timeline's one event: the flight is over, the surface ship's pages follow.
func cue(event: StringName) -> void:
	if event == &"pages":
		show_pages()


# --- the three pages ---------------------------------------------------------------------------

## The surface ship's message, one page at a time, read aloud while it is on screen. Enter closes a page
## (and cuts the speech off, like the original's `PlayVoyagerClosingSpeech` (0x41c508)).
func show_pages() -> void:
	if _pages_started or done:
		return
	_pages_started = true
	Audio.stop_music()
	var cues := Catalog.voice_cues()
	for page in PAGES:
		var speech: Array[StringName] = []
		if page == 0:
			speech.append(cues.jingle())                  # the "incoming transmission" sound
		speech.append_array(cues.closing_page(page))
		var message := messages.post_ship(page_text(page))
		Audio.play_voice_sequence(speech)
		await message.closed
		Audio.stop_voice()
		if done:
			return
	finish()


## Page `page` (0-2) as the message box shows it: the original's text without its own heading line and the
## key pictures turned into words.
static func page_text(page: int) -> String:
	var raw := Catalog.text(StringName("closing_page_%d" % page))
	var heading := "Surface Ship Message:\n"
	if raw.begins_with(heading):
		raw = raw.substr(heading.length())
	return HintSystem.printable(raw).strip_edges()


## Enter during the flight: straight to the pages.
func advance() -> void:
	if not _pages_started:
		animations.stop()
		show_pages()


func skip() -> void:
	animations.stop()
	messages.close_current()
	finish()
