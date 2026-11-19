class_name TimelineSegment
extends StorySegment
## A part of the opening that PLAYS A SCENE FILE (`StoryScene`, `data/story/<scene>.tres` of the pack chain): the news cartoon is the scene `news_cartoon`. The segment builds the scene's stage
## (`StageBuilder`), plays its timelines, starts its song and says its speech; nothing of what is drawn, when or by whom is in this script. Original: the first loop of `OpeningSequence` (OPENING.C)
## and its small speech state machine `CartoonSpeech` (0x42984d) for the news cartoon.
##
## Teaches: a scene whose whole content is data, played by one script. Each timeline is an `Animation` made by `Cutscene.animation` on an `AnimationPlayer`: a player plays one animation at a time, so every
## LOOPING timeline has a player of its own (the alarm lights, the pulsing ring and the flickering console lights of the news cartoon are one such loop) and the ONE-SHOT timelines share one that plays them in order.
## What happens at a moment of a timeline is an event cue that is a VERB with its words (`StoryVerbs.VERBS`): `cue` parses it and calls `_verb_<name>`, so a verb is one more entry of `VERBS` and one more method, and a cue
## that names a verb the engine lacks is told once and does nothing (`StoryVerbs.problem`, the same judgement `PackCheck` uses). The speech is NOT in an animation, because how long a clip lasts is not known
## when the animation is built: a coroutine (`_speak`) walks the scene's `speech` steps, waits each pause and `await`s the verb `speak` (the voice group of that name, `Audio.speak`). Enter goes on (the segment ends), Space / Escape
## skip everything; the director (`Opening`) handles the keys.

## The scene's name (`Catalog.story_scene`).
var scene_name: StringName = &""
## The scene, null when no pack of the chain holds it (the segment then ends at once).
var scene: StoryScene
## Which node plays which actor of the scene's stage; the timelines' tracks are bound through it.
var cast: CutsceneCast
## The node the stage's actors are made under.
var stage: Node2D
## The players of the looping timelines (one each, in the scene's order) and the player of the one-shot timelines.
var loop_players: Array[AnimationPlayer] = []
var script_player: AnimationPlayer

var _loop_names: Array[StringName] = []    # the timeline each of `loop_players` plays
var _chain: Array[StringName] = []         # the one-shot timelines that are there to play, in order
var _chain_index: int = 0


## A segment that plays the scene `name_of_scene`: the scene is built when the segment enters the tree.
static func of(name_of_scene: StringName) -> TimelineSegment:
	var segment := TimelineSegment.new()
	segment.scene_name = name_of_scene
	segment.name = String(name_of_scene).to_pascal_case()
	segment.size = Vector2(640, 400)
	return segment


## The text of a timeline's `text` track as the teletype prints it: the original's text with its odd characters cleaned (the importer counts the typing time on this text).
static func tidy(text: String) -> String:
	return text.strip_edges().replace("\r", "\n")


func _ready() -> void:
	scene = Catalog.story_scene(scene_name)
	if scene == null:
		TroubleLog.session.tell("[story] no pack of the chain holds the scene '%s' (data/story/%s.tres): that part of the opening is skipped" % [scene_name, scene_name])
		finish.call_deferred()                    # (not at once: the director awaits `finished` only after it has added the segment)
		return
	_build()
	_play()
	if scene.song != &"":
		Audio.play_music(scene.song)
	_speak()


## The nodes of the scene, all of them: the black backdrop, the stage with the actors, a player for each loop and one for the one-shot timelines, with every animation installed. The one place they are made.
func _build() -> void:
	for line in scene.unresolved():
		TroubleLog.session.tell("[story] pack '%s': the scene '%s' %s" % [_pack_id(), scene_name, line])
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color.BLACK
	backdrop.size = size
	add_child(backdrop)
	stage = Node2D.new()
	stage.name = "Stage"
	add_child(stage)
	cast = CutsceneCast.new(self)
	cast.texts = _text
	StageBuilder.build(scene.stage, stage, cast)
	for timeline_name in scene.loops:
		var timeline := Catalog.story_timeline(timeline_name)
		if timeline != null:
			var player := _new_player(String(timeline_name))
			Cutscene.install_timeline(player, timeline_name, timeline, cast)
			loop_players.append(player)
			_loop_names.append(timeline_name)
	script_player = _new_player("Script")
	for timeline_name in scene.timelines:
		var timeline := Catalog.story_timeline(timeline_name)
		if timeline != null:
			Cutscene.install_timeline(script_player, timeline_name, timeline, cast)
			_chain.append(timeline_name)
	script_player.animation_finished.connect(_on_animation_finished)


func _new_player(player_name: String) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = player_name
	add_child(player)
	return player


func _play() -> void:
	for i in loop_players.size():
		loop_players[i].play(_loop_names[i])
	if not _chain.is_empty():
		script_player.play(_chain[0])


func _on_animation_finished(_finished: StringName) -> void:
	_chain_index += 1
	if _chain_index < _chain.size() and not done:
		script_player.play(_chain[_chain_index])


## The loop is over for good: stop the animations (the speech stops in `finish`).
func finish() -> void:
	if done:
		return
	for player in loop_players:
		player.stop()
	if script_player != null:
		script_player.stop()
	super.finish()


func _text(text_name: StringName) -> String:
	return tidy(Catalog.text(text_name)) if text_name != &"" else ""


func _pack_id() -> String:
	var holder := Packs.holder(Catalog.STORY_REL % scene_name)
	return String(holder.id) if holder != null else "?"


# --- the verbs ------------------------------------------------------------------------------------------------

## An event cue of a timeline: a verb and its words. A verb the engine lacks, or a cue with the wrong number of words, is told once and does nothing.
func cue(event: StringName) -> void:
	var problem := StoryVerbs.problem(event)
	if not problem.is_empty():
		TroubleLog.session.tell("[story] pack '%s': the scene '%s' %s" % [_pack_id(), scene_name, StoryVerbs.line(event, problem)])
		return
	var words := StoryVerbs.parse(event)
	call("_verb_%s" % words[0], words.slice(1))


## `end`: the scene is over.
func _verb_end(_words: PackedStringArray) -> void:
	finish()


## `speak <group>`: the clips of the voice group, one after the other, until the last has been heard (`Audio.speak`: as long as the recording, or a silent wait when Voice is off). A coroutine: `cue` does not wait for it, `_speak` does.
func _verb_speak(words: PackedStringArray) -> void:
	var clips := Catalog.voice_cues().clips(words[0])
	if not done:
		await Audio.speak(clips)


# --- the speech -----------------------------------------------------------------------------------------------

## The scene's speech: each step waits its pause, then speaks its group. A step whose group holds no clips is left out whole, pause and all (`StoryScene.unresolved` told it).
func _speak() -> void:
	for step in scene.speech:
		if Catalog.voice_cues().clips(String(step.group)).is_empty():
			continue
		if not await pause_ticks(maxi(step.pause_ticks, 0)):
			return
		await _verb_speak(PackedStringArray([step.group]))
		if done:
			return
