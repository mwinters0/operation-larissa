class_name ExpertClosing
extends StorySegment
## The end of the Expert game: a crane lowers a hook from the top of the screen, grabs the sub with the Alien
## Artifact and hoists it up; the next shot shows the sub swinging in beside the research ship while the crew
## cheers, and the picture then waits for a key or a click. Original: `ExpertClosingSequence` (0x41c650, CLOSING.C,
## called from `DoAction` in sector 31 on screen 10 once the finale creature has set the semaphore bit 15), with the
## closing song 9501.
##
## Teaches: a closing whose every picture, position and draw order is data. `StageBuilder` makes the nodes of the stage file `expert_closing_stage` (the playfield with the sub, the artifact and the crane's cable, the deck
## with the ship, the sea, the sailors and the control box); one `AnimationPlayer` plays THREE animations one after the other (`hoist`, `deck`, `wait`), chained with `animation_finished`, each built from a
## `CutsceneTimeline` of the pack (`expert_hoist`, `expert_deck`, `expert_wait`; in the legacy pack they are the original's loops, one picture update every 18 ticks, played out step by step into keys, the six sailors'
## programs (`ClosingCrewActor` runs them; the importer ran their twin) included). A looping animation is the "wait for a key" state. This script says only which picture sets the stage may show, when to cut from the
## sector's shot to the deck, and what ends it.
##
## The original, step by step (a step is 18 ticks = 0.2466 s; every step draws the sub and the Alien Artifact):
##   1. `HOIST`: the sub turns to face right (`ExpertClosingTurnTable`), idles 20 steps, the hook comes down 16 steps of
##      12 px (open for 10 steps, closing for 5, closed from the 16th step on), then the cable pulls the sub, the
##      artifact and the hook up 12 px per step for 17 steps.
##   2. `DECK`: the shot of the research ship; the sub rises into it for 6 steps (the artifact and the cable with it),
##      and for 140 more steps the six sailors walk and wave while the control box at the right edge blinks.
##   3. `WAIT`: only the box blinks, until a key is pressed or the mouse is clicked.
## Every key pressed before the last stage is read and thrown away (`PeekInput` / `WaitForInput` in each step), and
## the click area (`AddHotspot` 0xd) exists only in the last stage.

## The stage the closing is played on (`Catalog.story_stage`) and the timeline each of its three animations (`hoist`, `deck`, `wait`, played one after the other) plays on it. The legacy pack's are written by `tools/import/step_story.py` from CLOSING.C
## (the turn, the idle, the hook's 16 steps down and the 17 steps up, the deck shot's 6 + 140 steps, the box's blinking, the places of the pictures), the dev pack's by `tools/dev_pack/dev_story.py`.
const STAGE := &"expert_closing_stage"
const TIMELINES: Dictionary[StringName, StringName] = {&"hoist": &"expert_hoist", &"deck": &"expert_deck", &"wait": &"expert_wait"}
## The two groups of the stage that this script shows and hides (`_show_deck`): the sector's shot and the ship's.
const PLAYFIELD := &"playfield"
const DECK := &"deck"
## The picture sets the closing hands to the stage (`StageActor.frames`): the sub's drawings and the Alien Artifact's, which are the creature pictures of zone 6. `ExpertClosingDrawArtifact` (0x41cd84) draws item 0 / 1
## of `ZoneFoeBundle`, toggled on every call; in sector 31 that is the Expert finale's zone foe bundle (zone 6: logical resource 461 = bundle 112), pictures 2002 / 2003 (84 x 72, a spiked mine with blinking lights).
const SET_SUB := &"sub"
const SET_ARTIFACT := &"artifact"
const FRAME_SETS: Array[StringName] = [SET_SUB, SET_ARTIFACT]
const ARTIFACT_ZONE := 6

enum Stage { HOIST, DECK, WAIT }

var stage: Stage = Stage.HOIST
## Which node plays which actor (the stage's actors, bound by `StageBuilder`).
var cast: CutsceneCast

@onready var stage_root: Node2D = %Stage
@onready var animations: AnimationPlayer = %Animations


func _ready() -> void:
	cast = make_cast(self)
	StageBuilder.build(STAGE, stage_root, cast)
	for animation_name in TIMELINES:
		var timeline := Catalog.story_timeline(TIMELINES[animation_name])
		if timeline != null:
			Cutscene.install_timeline(animations, animation_name, timeline, cast)
	animations.animation_finished.connect(_on_animation_finished)
	Audio.play_music(AudioService.SONG_CLOSING)
	animations.play(&"hoist")


## The cast of the closing played under `root`, with the sets its stage may show (`FRAME_SETS`, each with its pictures): the one place the sets are handed in.
static func make_cast(root: Node) -> CutsceneCast:
	var cast := CutsceneCast.new(root)
	cast.sub_tuning = GameState.tuning.sub
	cast.frame_zone = ARTIFACT_ZONE
	cast.frame_sets = {SET_SUB: Catalog.sub_frames(), SET_ARTIFACT: Catalog.foes_frames(ARTIFACT_ZONE)}
	return cast


# --- the keys ------------------------------------------------------------------------------------

## Enter and Space / Escape (the director forwards them): the original reads and drops every key until the last stage.
func advance() -> void:
	_key_pressed()


func skip() -> void:
	_key_pressed()


## Any other key and the mouse: the last stage has a click area over the whole screen and waits for any input.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if (key != null and key.pressed and not key.echo) or (click != null and click.pressed):
		_key_pressed()


func _key_pressed() -> void:
	if stage == Stage.WAIT:
		finish()


## The song ends with the sequence (`StopBackgroundMusic` 0x41cba2), not in the Hall of Fame.
func finish() -> void:
	if done:
		return
	animations.stop()
	Audio.stop_music()
	super.finish()


func _show(actor: StringName, shown: bool) -> void:
	var node := cast.node_of(actor) as CanvasItem
	if node != null:
		node.visible = shown


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"hoist":
		_show_deck()
	elif animation_name == &"deck":
		stage = Stage.WAIT
		animations.play(&"wait")


## Cut to the ship: hide the sector, show the deck, play the deck animation.
func _show_deck() -> void:
	stage = Stage.DECK
	_show(PLAYFIELD, false)
	_show(DECK, true)
	animations.play(&"deck")
