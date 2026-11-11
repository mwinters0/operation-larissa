class_name TitleScene
extends StorySegment
## The opening's second scene: the surface ship launches the mini-submarine, then "The Learning Company Presents
## OPERATION NEPTUNE" appears, and the player chooses Start or Intro. Original: the second half of
## `OpeningSequence` (OPENING.C) and its Start / Intro prompt.
##
## Teaches: a long, timed animation that is DATA (`data/story/title_ship.tres` and `title_reveal.tres`, `CutsceneTimeline`s
## of the pack; the legacy pack's are written by the importer) played by one `AnimationPlayer` this script builds: stepped movement (`position` keys that JUMP,
## because the original redraws every 12 ticks and moves 8 px per redraw), picture swaps (discrete `texture` keys), a CLIPPED
## picture (the `region_rect` of the sinking sub shrinks until nothing is left), sounds and events (method tracks) -- plus how
## to hand the player a choice at the end (`TextureButton`s and keys). The script only says which node plays which actor of the
## timeline (`CutsceneCast`); where and when is in the data. It is a state machine with three phases:
##
##   SHIP     26.8 s: the ship sails across the sky, stops, drops the mini-sub into the sea with a splash
##   REVEAL   "presents", "OPERATION", "NEPTUNE" and the copyright appear, one after the other (no fading)
##   PROMPT   [Start] [Intro]; Intro (Enter, I, a click on its button or anywhere outside the buttons) goes on to the story
##            pages, Start (S, Space, Escape, a click on its button) ends the opening. If nobody presses anything for 25 s the
##            story begins by itself.
##
## All the numbers of the ship scene come from the original's own per-redraw routines, decoded into one table
## (extracted/tables/opening.json, written into the timeline by the importer): where the hull, the radar, the hook, the sub and the
## spray are in each of the 163 frames. The sub is NOT fixed to the ship: the hook lets go, it falls 6 px per frame into the water,
## splashes, and the original draws it with a clip rectangle ending at the waterline (screen row 312), so it sinks
## out of sight while the ship sails on without it.

enum Phase { SHIP, REVEAL, PROMPT }

# The ship scene (`title_ship`) and the reveal of the title (`title_reveal`) are the pack's data (`Catalog.story_timeline`).

const SUB_SIZE := Vector2(72, 44)
const SPLASH_FIRST_PICTURE := &"spray_0"    # five 76 x 50 pictures (`spray_0` .. `spray_4`)

const PROMPT_TIMEOUT := 25.0          # 1825 ticks
const MUSIC_DELAY_AFTER_PROMPT := 4.0

## True when the player asked for the story (Intro, Enter, a click outside the buttons, or nobody chose for 25 s).
var wants_intro: bool = false
var phase: Phase = Phase.SHIP

@onready var stage: Node2D = %Stage
@onready var ship: Node2D = %Ship
@onready var animations: AnimationPlayer = %Animations
@onready var prompt: Control = %Prompt
@onready var start_button: TextureButton = %Start
@onready var intro_button: TextureButton = %Intro
@onready var prompt_timer: Timer = %PromptTimer

var _ship_sub: Sprite2D
var _ship_radar: Sprite2D
var _ship_hook: Sprite2D
var _ship_spray: Sprite2D
var _waves_front: Sprite2D
var _splashes: Array[Sprite2D] = []
var _titles: Dictionary = {}          # name -> Sprite2D, shown one after the other during REVEAL
var _cast: CutsceneCast
var _reveal: CutsceneTimeline


func _ready() -> void:
	_cast = CutsceneCast.new(self)
	_build_stage()
	_build_prompt()
	_reveal = Catalog.story_timeline(&"title_reveal")
	Cutscene.install_timeline(animations, &"ship", Catalog.story_timeline(&"title_ship"), _cast)
	Cutscene.install_timeline(animations, &"reveal", _reveal, _cast)
	animations.animation_finished.connect(_on_animation_finished)
	prompt_timer.wait_time = PROMPT_TIMEOUT
	prompt_timer.one_shot = true
	prompt_timer.timeout.connect(_choose.bind(true))
	Audio.play_music(AudioService.SONG_TITLE)
	animations.play(&"ship")


# --- the picture ---------------------------------------------------------------------------

## A picture node with a NAME (its place in the scene tree) that plays the actor `actor` of the timeline (if it has one).
func _sprite(parent: Node, node_name: String, picture: StringName, at: Vector2, flip: bool = false, actor: StringName = &"") -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = Assets.ui_picture(picture)
	sprite.centered = false
	sprite.position = at
	sprite.flip_h = flip
	parent.add_child(sprite)
	if actor != &"":
		_cast.bind(actor, sprite)
	return sprite


## Sky, sea and clouds; then the ship with its parts (placed RELATIVE to the hull, so that the ship is one node that moves
## as a whole), the mini-sub (which does NOT move with the ship once it is dropped, so its place is its own, in window
## pixels), the waves in front of it, the splash and the title pictures. Each picture that the timeline moves or changes
## is told to the cast as an actor.
func _build_stage() -> void:
	_sprite(stage, "Sky", &"title_sky", Catalog.story_layout().at(StoryLayout.SKY))
	_sprite(stage, "Sea", &"title_sea", Catalog.story_layout().at(StoryLayout.SEA))
	_sprite(stage, "CloudLeft", &"title_cloud_0", Catalog.story_layout().at(StoryLayout.CLOUD_LEFT))
	_sprite(stage, "CloudRight", &"title_cloud_1", Catalog.story_layout().at(StoryLayout.CLOUD_RIGHT))
	var origin := Catalog.story_layout().at(StoryLayout.SHIP)
	stage.move_child(ship, -1)                         # the Ship node comes from the scene file: draw it after the sky, sea and clouds
	ship.position = origin
	_cast.bind(&"ship", ship)
	_sprite(ship, "Hull", &"ship_idle", Vector2.ZERO)
	_ship_radar = _sprite(ship, "Radar", &"ship_radar_0", Catalog.story_layout().at(StoryLayout.SHIP_RADAR) - origin, false, &"radar")
	_ship_hook = _sprite(ship, "Hook", &"ship_hook_0", Catalog.story_layout().at(StoryLayout.SHIP_HOOK) - origin, true, &"hook")
	# The sub is drawn clipped: its `region_rect` shows only the rows above the waterline. It is drawn right after the ship's parts.
	_ship_sub = _sprite(stage, "MiniSub", &"ship_mini_sub", Catalog.story_layout().at(StoryLayout.SHIP_SUB), false, &"mini_sub")
	_ship_sub.region_enabled = true
	_ship_sub.region_rect = Rect2(Vector2.ZERO, SUB_SIZE)
	_waves_front = _sprite(stage, "WavesFront", &"title_waves_front", Catalog.story_layout().at(StoryLayout.WAVES_FRONT))
	# The bow spray is drawn after the waves (in front of them); it moves with the hull at a fixed offset.
	_ship_spray = _sprite(stage, "Spray", &"spray_1", Catalog.story_layout().at(StoryLayout.SHIP_BOW_SPRAY), false, &"spray")
	var splash_at := Catalog.story_layout().at(StoryLayout.SPLASH)
	_splashes.append(_sprite(stage, "SplashLeft", SPLASH_FIRST_PICTURE, splash_at, false, &"splash_left"))
	_splashes.append(_sprite(stage, "SplashRight", SPLASH_FIRST_PICTURE, splash_at + Vector2(76, 0), true, &"splash_right"))
	for splash in _splashes:
		splash.visible = false
	# The title pictures just appear, one after the other (a single blit each in the original: no wipe).
	_titles = {
		"Presents": _sprite(stage, "Presents", &"title_presents", Catalog.story_layout().at(StoryLayout.PRESENTS), false, &"presents"),
		"Operation": _sprite(stage, "Operation", &"title_operation", Catalog.story_layout().at(StoryLayout.OPERATION), false, &"operation"),
		"Neptune": _sprite(stage, "Neptune", &"title_neptune", Catalog.story_layout().at(StoryLayout.NEPTUNE), false, &"neptune"),
		"Copyright": _sprite(stage, "Copyright", &"title_copyright", Catalog.story_layout().at(StoryLayout.COPYRIGHT), false, &"copyright"),
	}
	for sprite: Sprite2D in _titles.values():
		sprite.visible = false


## The two buttons of the prompt: the pictures of Start and Intro, up and down.
func _build_prompt() -> void:
	start_button.texture_normal = Assets.ui_picture(&"start_button_up")
	start_button.texture_pressed = Assets.ui_picture(&"start_button_down")
	intro_button.texture_normal = Assets.ui_picture(&"intro_button_up")
	intro_button.texture_pressed = Assets.ui_picture(&"intro_button_down")
	# The original's buttons act on the PRESS (`TitleScreenPromptLoop` answers 0x8975 / 0x8977, the left button DOWN codes).
	start_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	intro_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	start_button.pressed.connect(_choose.bind(false))
	intro_button.pressed.connect(_choose.bind(true))
	prompt.visible = false


# --- phases 1 and 2: the ship and the title ---------------------------------------------------
# Both are played from data: `title_ship.tres` (frame r of the original's table is shown at r x 12 ticks; every track is
# DISCRETE, the value jumps at each key, because the original redraws every 12 ticks and moves whole 8 px steps; the splash
# sound plays in the frame in which the sub touches the water, the pictures start two frames later) and `title_reveal.tres`
# (each title picture just appears, a sound before each, as in the original -- a single blit, no wipe: "Presents" for 292
# ticks; then it is erased as "OPERATION" appears; 292 ticks later "NEPTUNE" and the copyright come, together with the Start /
# Intro buttons).

# --- the phases ---------------------------------------------------------------------------

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"ship" and phase == Phase.SHIP:
		_leave_ship_scene()
		animations.play(&"reveal")


## The ship is gone (it sailed off, or Enter was pressed): clear sky, silent title. The wave strip goes with the ship: the original
## draws it only with the ship's parts (`TitleWaveStrip` 0x42a1d7), and the reveal paints sky, sea and clouds afresh (`TitleDrawBackdrop`
## 0x429d09), which has no strip.
func _leave_ship_scene() -> void:
	phase = Phase.REVEAL
	ship.visible = false
	_waves_front.visible = false
	_ship_sub.visible = false                             # (the sub is not a part of the ship node: it has a place of its own)
	_ship_spray.visible = false
	for splash in _splashes:
		splash.visible = false
	Audio.stop_music()                                    # the original stops the song when the title appears


## The prompt: the buttons, the 25 s countdown, and (after 4 s) the story's own music.
func _show_prompt() -> void:
	if phase == Phase.PROMPT or done:
		return
	phase = Phase.PROMPT
	prompt.visible = true
	prompt_timer.start()
	if await pause(MUSIC_DELAY_AFTER_PROMPT):
		Audio.play_music(AudioService.SONG_OPENING)


## The player's choice (or the timeout): remembered in `wants_intro`, then the segment ends.
func _choose(intro: bool) -> void:
	if done:
		return
	wants_intro = intro
	prompt_timer.stop()
	finish()


## The reveal timeline's one event: the third title picture is up, the prompt begins.
func cue(event: StringName) -> void:
	if event == &"prompt":
		_show_prompt()


# --- keys: the director forwards Enter, clicks and Space / Escape -------------------------------------------

## Enter, by phase (`OpeningSequence` 0x42b16b, `TitleRevealText` 0x42a211, `WaitEnterSpaceEscOrTicks` 0x428fbe, `TitleScreenPromptLoop`
## 0x42a49a):
##   SHIP    the ship scene ends; the reveal starts from "Presents"
##   REVEAL  ends only the hold that is running: "Presents" -> "OPERATION", "OPERATION" -> "NEPTUNE" + the prompt (the original
##           waits up to 292 ticks for Enter / Space / Escape twice; an Enter ends the wait and is taken, it never skips a picture)
##   PROMPT  Intro
func advance() -> void:
	match phase:
		Phase.PROMPT:
			_choose(true)
		Phase.SHIP:
			animations.stop()                             # first: stopping puts animated properties back to where they were
			_leave_ship_scene()
			animations.play(&"reveal")
		Phase.REVEAL:
			_end_hold()


## Cuts the running hold of the reveal short: the next title picture appears at once (with its sound), and after the last hold the
## prompt. The moments are the timeline's marks (`presents`, `operation`, `neptune`). `AnimationPlayer.seek` calls no method
## tracks, so what the cues of that moment would have done (the sound, the prompt) is done here.
func _end_hold() -> void:
	if done:
		return
	var marks := _reveal.marks
	var position := animations.current_animation_position
	var target: StringName = &"operation" if position < CutsceneTimeline.seconds(marks[&"operation"]) else &"neptune"
	animations.seek(CutsceneTimeline.seconds(marks[target]) + 0.001, true)       # (a hair past the key, so that playing on does not fire it again)
	for cue_entry in _reveal.cues:
		if is_equal_approx(cue_entry.tick, marks[target]):
			if cue_entry.kind == CutsceneCue.SOUND:
				play_sfx(cue_entry.cue_name)
			else:
				cue(cue_entry.cue_name)


## A left-button release: Enter (the whole-screen hotspot 0xd), except over a button of the prompt: that is the buttons' own hotspot
## (0x975 / 0x977), whose release nobody answers (the buttons act on the PRESS, code 0x8975 / 0x8977).
func click(at: Vector2) -> void:
	if phase == Phase.PROMPT and (start_button.get_global_rect().has_point(at) or intro_button.get_global_rect().has_point(at)):
		return
	advance()


## Space / Escape: leave without the story, whatever is on screen.
func skip() -> void:
	_choose(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if phase != Phase.PROMPT or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_I:
			get_viewport().set_input_as_handled()
			_choose(true)
		KEY_S:
			get_viewport().set_input_as_handled()
			_choose(false)
