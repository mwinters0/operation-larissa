class_name ExpertClosing
extends StorySegment
## The end of the Expert game: a crane lowers a hook from the top of the screen, grabs the sub with the Alien
## Artifact and hoists it up; the next shot shows the sub swinging in beside the research ship while the crew
## cheers, and the picture then waits for a key or a click. Original: `ExpertClosingSequence` (0x41c650, CLOSING.C,
## called from `DoAction` in sector 31 on screen 10 once the finale creature has set the semaphore bit 15), with the
## closing song 9501.
##
## Teaches: one `AnimationPlayer` with THREE animations played one after the other (`hoist`, `deck`, `wait`), chained
## with `animation_finished`; each of them built from a `CutsceneTimeline` of the pack (`data/story/expert_hoist.tres`,
## `expert_deck.tres`, `expert_wait.tres`); in the legacy pack they are the original's loops, one picture update every 18 ticks, played out step by step
## into keys, the six sailors' programs (`ClosingCrewActor` runs them; the importer ran their twin) included. A looping
## animation is the "wait for a key" state. This script only says which node plays which actor.
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

# The three stages are the pack's data (`Catalog.story_timeline`: `expert_hoist`, `expert_deck`, `expert_wait`; the legacy pack's are written by
# `tools/import/step_story.py` from CLOSING.C: the turn, the idle, the hook's 16 steps down and the 17 steps up, the deck shot's 6 + 140 steps,
# the box's blinking).
const PLAYFIELD_ORIGIN := ExpertClosingCable.PLAYFIELD_ORIGIN
## `ExpertClosingDrawArtifact` (0x41cd84) draws item 0 / 1 of `ZoneFoeBundle`, toggled on every call. In sector 31 that is
## the Expert finale's zone foe bundle (zone 6: logical resource 461 = bundle 112), pictures 2002 / 2003 (84 x 72, a spiked
## mine with blinking lights): the Alien Artifact. They are slots 35 and 36 of `foes_zone6` (zone foes start at slot 35).
const ARTIFACT_ZONE := 6
const ARTIFACT_PICTURES: Array[StringName] = [&"alien_artifact_0", &"alien_artifact_1"]      # zone 6's slots 35 and 36

# --- the deck shot ---
const SHIP_PICTURE := &"deck_ship"
const SHIP_AT := Vector2(232, 32)
const SEA_PICTURE := &"deck_sea"
const SEA_AT := Vector2(0, 300)
const CLOUD_PICTURE := &"deck_cloud"
const CLOUD_AT := Vector2(80, 108)
const CREW_COUNT := 6
## `ExpertClosingDrawPod` (0x41cdba): item 3, 4, 5, 4 of the bundle (pictures 2015-2017, 56 x 28) at (568, 104), the last one
## mirrored, one phase per step (`deck_pod_0` .. `deck_pod_2`, items 3-5 of the bundle).
const POD_PICTURES: Array[StringName] = [&"deck_pod_0", &"deck_pod_1", &"deck_pod_2", &"deck_pod_1"]
const POD_AT := Vector2(568, 104)

enum Stage { HOIST, DECK, WAIT }

var stage: Stage = Stage.HOIST
var _crew: Array[Sprite2D] = []

@onready var playfield: Control = %Playfield
@onready var sub: AnimatedSprite2D = %Sub
@onready var artifact: AnimatedSprite2D = %Artifact
@onready var cable: ExpertClosingCable = %Cable
@onready var deck: Control = %Deck
@onready var crew_layer: Node2D = %Crew
@onready var deck_artifact: AnimatedSprite2D = %DeckArtifact
@onready var deck_sub: AnimatedSprite2D = %DeckSub
@onready var deck_cable: ExpertClosingCable = %DeckCable
@onready var pod: Sprite2D = %Pod
@onready var ship: Sprite2D = %Ship
@onready var sea: Sprite2D = %Sea
@onready var cloud: Sprite2D = %Cloud
@onready var animations: AnimationPlayer = %Animations


func _ready() -> void:
	for animated: AnimatedSprite2D in [sub, deck_sub]:
		animated.sprite_frames = Catalog.sub_frames()
		animated.animation = &"all"
		animated.pause()
	for animated: AnimatedSprite2D in [artifact, deck_artifact]:
		animated.sprite_frames = Catalog.foes_frames(ARTIFACT_ZONE)
		animated.animation = &"all"
		animated.frame = _artifact_slot(0)
		animated.pause()
	ship.texture = Assets.ui_picture(SHIP_PICTURE)
	ship.position = SHIP_AT - PLAYFIELD_ORIGIN
	sea.texture = Assets.ui_picture(SEA_PICTURE)
	sea.position = SEA_AT - PLAYFIELD_ORIGIN
	cloud.texture = Assets.ui_picture(CLOUD_PICTURE)
	cloud.position = CLOUD_AT - PLAYFIELD_ORIGIN
	pod.texture = Assets.ui_picture(POD_PICTURES[0])
	pod.position = POD_AT - PLAYFIELD_ORIGIN
	_build_crew()
	deck.visible = false
	var cast := _make_cast()
	for stage_name: StringName in [&"hoist", &"deck", &"wait"]:
		Cutscene.install_timeline(animations, stage_name, Catalog.story_timeline(StringName("expert_" + stage_name)), cast)
	animations.animation_finished.connect(_on_animation_finished)
	Audio.play_music(AudioService.SONG_CLOSING)
	animations.play(&"hoist")


## Which node plays which actor of the timelines. The crane's chain calls its properties `bottom` and `hook_frame`.
func _make_cast() -> CutsceneCast:
	var cast := CutsceneCast.new(self)
	cast.sub_tuning = GameState.tuning.sub
	cast.frame_zone = ARTIFACT_ZONE
	var chain := {CutsceneTrack.PROP_EXTENT: "bottom", CutsceneTrack.PROP_FRAME: "hook_frame"}
	cast.bind(&"cable", cable, chain)
	cast.bind(&"sub", sub)
	cast.bind(&"artifact", artifact)
	cast.bind(&"deck_cable", deck_cable, chain)
	cast.bind(&"deck_sub", deck_sub)
	cast.bind(&"deck_artifact", deck_artifact)
	cast.bind(&"pod", pod)
	for i in _crew.size():
		cast.bind(StringName("crew_%d" % i), _crew[i])
	return cast


## The six sailors: sprites that the `deck` animation moves, re-textures and shows or hides.
func _build_crew() -> void:
	for i in CREW_COUNT:
		var sailor := Sprite2D.new()
		sailor.name = "Crew%d" % i
		sailor.centered = false
		sailor.visible = false
		crew_layer.add_child(sailor)
		_crew.append(sailor)


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


## The slot of the artifact's picture `toggle` (0 or 1) in the creature set of `ARTIFACT_ZONE`.
static func _artifact_slot(toggle: int) -> int:
	return NameRegistry.original().index_of(&"frame", ARTIFACT_PICTURES[toggle], ARTIFACT_ZONE)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"hoist":
		_show_deck()
	elif animation_name == &"deck":
		stage = Stage.WAIT
		animations.play(&"wait")


## Cut to the ship: hide the sector, show the deck, play the deck animation.
func _show_deck() -> void:
	stage = Stage.DECK
	playfield.visible = false
	deck.visible = true
	animations.play(&"deck")
