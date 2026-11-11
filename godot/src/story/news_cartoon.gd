class_name NewsCartoon
extends StorySegment
## The opening's first scene: a radar map of the Pacific, a control room with a worried crew, the falling space
## capsule, and the news bulletins typed out and read aloud ("RED ALERT... GALAXY SPACE CAPSULE HAS ALTERED ITS
## COURSE ..."). Original: the first loop of `OpeningSequence` (OPENING.C).
##
## Teaches: a cutscene whose choreography is DATA (`data/story/news_cartoon.tres`, a `CutsceneTimeline` of the pack; the legacy pack's is written by the importer from
## the original's tables) and whose view is this script: it builds the pictures, tells a `CutsceneCast` which node plays
## which actor ("crew_4" is the `Crew4` sprite), and has `Cutscene.animation()` turn the timeline into `Animation`s. There are
## TWO `AnimationPlayer`s, because one player plays one animation at a time:
##
##   * `Ambient` loops forever: the alarm lights and the pulsing radar ring (`news_ambient.tres`) and the flickering console
##     lights, which are random in the original and so are made here with a seeded generator (`_flicker_timeline`);
##   * `Script` plays once: the capsule's dots appear along its path, the bulletins are typed (a `reveal` track), the crew
##     act out their scripts (the man on the left only walks in after 30 s), the alarm lights come on one after the other,
##     and at the end an event cue tells the segment to finish.
##
## The speech is NOT in an animation: how long a clip lasts is not known when the animation is built, so a
## coroutine (`_speak`) waits for each group of clips with `await Audio.speak(...)`, exactly like the
## original's small speech state machine (`CartoonSpeech` (0x42984d)). Space / Escape skip everything, Enter goes on to the
## title; the director (`Opening`) handles the keys.
##
## Timing facts from the decompilation: the original redraws every 10 ticks of its 73 Hz timer ("call n" below is
## the n-th redraw, at t = 10 (n - 1) ticks); a bulletin is typed at 3 ticks per character and then read for
## 25 redraws (3.4 s); the capsule's trail gets a new dot every 11 redraws, the ring starts 6 redraws after the
## last one. The crew's pictures and timings are the original's five little scripts; the importer plays them out, redraw by
## redraw, into the timeline.

## The ambient animation's step: the original's redraw every 10 ticks (the flicker of the console lights changes at that rate).
const REDRAW_TICKS := 10.0
## The crew member who walks in from the left edge (his script starts at call 220, 30 s).
const WALKER := 4

## The speech: groups of the 11 clips (how many clips in each) with the pause before each group, in ticks of the original's 1/73 s (the
## original's `CartoonSpeech` (0x42984d): a pause precedes clips 1, 3, 6 and 7, the others follow their predecessor at once). The pauses
## are data (`news.group_pauses` of `data/rules/durations.json`, `Durations`): the port always waited 3.4 s, which is 248.2 ticks, so 248
## (the bulletin is read for 25 redraws of 10 ticks, 250, which may be where the pause comes from: not checked in the decompilation).
## How long a group SPEAKS is not here: it is the clips' recorded lengths (`VoiceIndex.durations`, `Audio.speak`).
const SPEECH_GROUP_CLIPS: Array[int] = [2, 3, 1, 1, 4]


## The wait before the first clip: 3 s (`news.speech_start_delay_ticks`).
static func speech_start_delay_ticks() -> int:
	return maxi(Durations.at("news.speech_start_delay_ticks"), 0)


## The groups of the speech as `[pause ticks, clip count]`, the pauses from the data.
static func speech_groups() -> Array[Array]:
	var pauses := Durations.list_at("news.group_pauses")
	var groups: Array[Array] = []
	for i in SPEECH_GROUP_CLIPS.size():
		groups.append([maxi(pauses[i], 0) if i < pauses.size() else 0, SPEECH_GROUP_CLIPS[i]])
	return groups


@onready var stage: Node2D = %Stage
@onready var teletype: Label = %Teletype
@onready var ambient: AnimationPlayer = %Ambient
@onready var script_player: AnimationPlayer = %Script

var _crew: Array[Sprite2D] = []
var _alarms: Array[Sprite2D] = []
var _status_lights: Array[Sprite2D] = []
var _panel_lights: Array[Sprite2D] = []
var _dots: Array[Sprite2D] = []
var _ring: Sprite2D
var _cast: CutsceneCast


func _ready() -> void:
	_cast = CutsceneCast.new(self)
	_cast.texts = _bulletin_text
	_build_stage()
	teletype.position = Catalog.story_layout().at(StoryLayout.TELETYPE)
	teletype.text = ""
	_cast.bind(&"teletype", teletype)
	# The bulletin is wrapped as a whole and only REVEALED character by character: with the default
	# (characters hidden before shaping) the label wraps the part typed so far, and a word that reaches the
	# edge jumps to the next line.
	teletype.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	var alarms := Catalog.story_timeline(&"news_ambient")
	Cutscene.install_timeline(ambient, &"ambient", alarms.merged_with(_flicker_timeline(alarms)), _cast)
	Cutscene.install_timeline(script_player, &"news", Catalog.story_timeline(&"news_cartoon"), _cast)
	ambient.play(&"ambient")
	script_player.play(&"news")
	Audio.play_music(AudioService.SONG_OPENING)
	_speak()


## The loop is over for good: stop the animations (the speech stops in `finish`).
func finish() -> void:
	if done:
		return
	ambient.stop()
	script_player.stop()
	super.finish()


## The timeline's only event: the last bulletin has been read.
func cue(event: StringName) -> void:
	if event == &"end":
		finish()


# --- the picture ---------------------------------------------------------------------------

## A picture node with a NAME (its place in the scene tree) that plays the actor `actor` of the timeline.
func _sprite(node_name: String, actor: String, picture: StringName, at: Vector2, flip: bool = false) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = Assets.ui_picture(picture)
	sprite.centered = false
	sprite.position = at
	sprite.flip_h = flip
	stage.add_child(sprite)
	_cast.bind(StringName(actor), sprite)
	return sprite


## Places every picture at the original's coordinates (`StoryLayout`).
func _build_stage() -> void:
	_sprite("Map", "map", &"radar_map", Catalog.story_layout().at(StoryLayout.MAP))
	for i in range(StoryLayout.CAPSULE_TRAIL_FIRST, StoryLayout.CAPSULE_TRAIL_LAST + 1):
		var dot := _sprite("Dot%02d" % _dots.size(), "dot_%02d" % _dots.size(), &"capsule_dot", Catalog.story_layout().at(i))
		dot.visible = false
		_dots.append(dot)
	_ring = _sprite("Ring", "ring", &"crash_ring_0", Catalog.story_layout().at(StoryLayout.CRASH_SITE))
	_ring.visible = false
	_sprite("ConsoleLeft", "console_left", &"control_console", Catalog.story_layout().at(StoryLayout.CONSOLE_LEFT))
	_sprite("ConsoleRight", "console_right", &"control_console", Catalog.story_layout().at(StoryLayout.CONSOLE_RIGHT), true)
	for index in StoryLayout.ALARM_LIGHTS:
		_alarms.append(_sprite("Alarm%d" % _alarms.size(), "alarm_%d" % _alarms.size(), &"alarm_light_0", Catalog.story_layout().at(index)))
	# The right half of each row of lights is drawn mirrored by the original.
	for i in StoryLayout.STATUS_LIGHTS.size():
		_status_lights.append(_sprite("Status%02d" % i, "status_%02d" % i, &"status_light_0", Catalog.story_layout().at(StoryLayout.STATUS_LIGHTS[i]), i >= 3))
	for i in StoryLayout.PANEL_LIGHTS.size():
		_panel_lights.append(_sprite("Panel%02d" % i, "panel_%02d" % i, &"panel_light_0", Catalog.story_layout().at(StoryLayout.PANEL_LIGHTS[i]), i >= 4))
	for index in StoryLayout.CREW:
		_crew.append(_sprite("Crew%d" % _crew.size(), "crew_%d" % _crew.size(), &"crew_walk_0", Catalog.story_layout().at(index)))
	_crew[WALKER].visible = false                        # he is not there yet


# --- what the timeline does not have -----------------------------------------------------------

## The little lights flicker at random, like the console of the original (a seeded generator keeps it the same every
## time), so there is no original timeline for them: this one is ours, baked into a loop as long as the alarm lights'
## (`news_ambient.tres`) and merged with it. Status lights: each redraw a light is on with probability 100 / 299 and shows
## one of three pictures; panel lights are always on and show one of three pictures.
func _flicker_timeline(alarms: CutsceneTimeline) -> CutsceneTimeline:
	var flicker := CutsceneTimeline.made_in_code(alarms.length,
			"Ours: the console's lights flicker at random in the original (CartoonStatusLights, CartoonPanelLights); a generator seeded with 73 bakes it into a loop.", true)
	var steps := roundi(alarms.length / REDRAW_TICKS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	for i in _status_lights.size():
		var visible_keys: Array = []
		var picture_keys: Array = []
		for step in steps:
			var r := rng.randi() % 299
			visible_keys.append([step * REDRAW_TICKS, r < 100])
			picture_keys.append([step * REDRAW_TICKS, StringName("status_light_%d" % (r % 3))])
		flicker.track(StringName("status_%02d" % i), CutsceneTrack.PROP_VISIBLE, visible_keys)
		flicker.track(StringName("status_%02d" % i), CutsceneTrack.PROP_PICTURE, picture_keys)
	for i in _panel_lights.size():
		var picture_keys: Array = []
		for step in steps:
			picture_keys.append([step * REDRAW_TICKS, StringName("panel_light_%d" % (rng.randi() % 299 % 3))])
		flicker.track(StringName("panel_%02d" % i), CutsceneTrack.PROP_PICTURE, picture_keys)
	return flicker


## Bulletin `index` (0-5) as the teletype prints it: the original's text with its odd characters cleaned.
static func bulletin(index: int) -> String:
	return tidy(Catalog.text(StringName("news_bulletin_%d" % index)))


## The original's text as the teletype shows it (the importer counts the typing time on this text).
static func tidy(text: String) -> String:
	return text.strip_edges().replace("\r", "\n")


func _bulletin_text(text_name: StringName) -> String:
	return tidy(Catalog.text(text_name)) if text_name != &"" else ""


# --- the speech ---------------------------------------------------------------------------------

## The 11 clips of the bulletins in their groups, with the original's pauses.
func _speak() -> void:
	var clips := Catalog.voice_cues().clips("opening_cartoon")
	if not await pause_ticks(speech_start_delay_ticks()):
		return
	var first := 0
	for group in speech_groups():
		if not await pause_ticks(group[0]):
			return
		var count: int = group[1]
		await Audio.speak(clips.slice(first, first + count))
		first += count
		if done:
			return
