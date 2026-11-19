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
## to hand the player a choice at the end (`TextureButton`s and keys). The stage builder says which node plays which actor of the
## timeline (`CutsceneCast`); where and when is in the data, and where things STAND is in the pack's stage (`data/story/title_stage.tres`, a `CutsceneStage` that `StageBuilder` makes the nodes of). It is a state machine with three phases:
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

## The stage the scene plays on (`Catalog.story_stage`) and the timelines played on it: the ship scene (`title_ship`) and the reveal of the title (`title_reveal`).
const STAGE := &"title_stage"
const SHIP_TIMELINE := &"title_ship"
const REVEAL_TIMELINE := &"title_reveal"
const TIMELINES: Array[StringName] = [SHIP_TIMELINE, REVEAL_TIMELINE]
## The actors of the stage that belong to the ship scene and are gone when the title is revealed (the strip of waves and the sub, spray and splashes are not parts of the ship's node).
const SHIP_SCENE_ACTORS: Array[StringName] = [&"ship", &"waves_front", &"mini_sub", &"spray", &"splash_left", &"splash_right"]

const PROMPT_TIMEOUT := 25.0          # 1825 ticks
const MUSIC_DELAY_AFTER_PROMPT := 4.0

## True when the player asked for the story (Intro, Enter, a click outside the buttons, or nobody chose for 25 s).
var wants_intro: bool = false
var phase: Phase = Phase.SHIP

@onready var stage: Node2D = %Stage
@onready var animations: AnimationPlayer = %Animations
@onready var prompt: Control = %Prompt
@onready var start_button: TextureButton = %Start
@onready var intro_button: TextureButton = %Intro
@onready var prompt_timer: Timer = %PromptTimer

## The ship: the stage's group actor `ship`, which carries the hull, the radar and the hook.
var ship: Node2D
var _cast: CutsceneCast
var _reveal: CutsceneTimeline


func _ready() -> void:
	_cast = CutsceneCast.new(self)
	StageBuilder.build(STAGE, stage, _cast)
	ship = _cast.node_of(&"ship") as Node2D
	_build_prompt()
	_reveal = Catalog.story_timeline(REVEAL_TIMELINE)
	Cutscene.install_timeline(animations, &"ship", Catalog.story_timeline(SHIP_TIMELINE), _cast)
	Cutscene.install_timeline(animations, &"reveal", _reveal, _cast)
	animations.animation_finished.connect(_on_animation_finished)
	prompt_timer.wait_time = PROMPT_TIMEOUT
	prompt_timer.one_shot = true
	prompt_timer.timeout.connect(_choose.bind(true))
	Audio.play_music(AudioService.SONG_TITLE)
	animations.play(&"ship")


# --- the prompt ---------------------------------------------------------------------------

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
	for actor in SHIP_SCENE_ACTORS:
		var node := _cast.node_of(actor) as CanvasItem
		if node == null:
			TroubleLog.session.tell("[story] the stage '%s' of the title has no actor '%s', which the ship scene hides when the title is revealed: nothing is hidden for it" % [STAGE, actor])
		else:
			node.visible = false
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
