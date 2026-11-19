class_name StoryScene
extends Resource
## A scene of the opening as DATA: which stage it stands on, which timelines it plays (the ones that loop and the ones that play once, in order), which song starts with it and what is said. The pack holds
## it as `data/story/<scene>.tres` (`.json` in the data form; `Catalog.story_scene`); a `TimelineSegment` plays it. Every name in it is a file of the pack chain: `stage` a `CutsceneStage`
## (`Catalog.story_stage`), `loops` and `timelines` `CutsceneTimeline`s (`Catalog.story_timeline`) or, among the one-shot ones, flight files (`SubFlight`, `Catalog.story_flight`: `timeline_named` is the one resolver of a name to a timeline), `song` a song of the music catalog or
## of the pack, the groups of `speech` groups of `voice_cues`, the pages of `messages` texts and groups of the same.
##
## What happens at a moment of a timeline is an EVENT cue whose name is a VERB of the engine and its words (`StoryVerbs.VERBS`): `end` finishes the scene, `listen` makes a scene that drops keys hear them, `speak <group>` speaks a voice group, `prompt` asks the player (the stage's buttons), `messages` shows the scene's `messages` in the message box. A
## pack arranges the verbs; what they do (input, waits, speech) is the engine's. `unresolved` is the one judgement of a scene against its chain: the game tells each line once when it plays the scene,
## `PackCheck` reports the same lines.
##
## The legacy pack's scene is written by the importer (`tools/import/step_story.py`), the dev pack's by `tools/dev_pack/dev_story.py`; `provenance` says which.
##
## Teaches: a scene as a list of NAMES, not code that pairs a stage with its timelines: the pairing is data a pack can change, and one function judges it for the game and for the check.

## The stage the scene is built on (`StageBuilder.build`).
@export var stage: StringName = &""
## The timelines that play from the start of the scene and start over when they end (the alarm lights and the ring). Each plays on a player of its own.
@export var loops: Array[StringName] = []
## The timelines that play once, one after the other (the cartoon itself). The scene is over when a cue says `end`. The LAST one may loop (it plays until something ends the scene: the closing's last shot waits for a key).
@export var timelines: Array[StringName] = []
## Does the scene have a black backdrop under its stage? A scene that is laid over the running sector (a closing) has none.
@export var backdrop: bool = true
## Does the scene drop every key and click (Enter, Space, Escape, any other key, the mouse) until its verb `listen`? From `listen` on, any of them ends the scene. A scene that does not is ended by `end` and by Enter, as the opening's are.
@export var deaf_until_listen: bool = false
## The song that starts with the scene (a `music` name); empty: no song starts.
@export var song: StringName = &""
## The timeline of `timelines` at whose start the song stops (the title's song ends when the title is revealed); empty: the song plays on.
@export var song_stops_at: StringName = &""
## The song the `prompt` verb starts after `prompt.music_delay_ticks` (the story's own song, once the buttons are up); empty: none.
@export var prompt_song: StringName = &""
## What is said, in order: each step a pause and a voice group. Empty: the scene is silent.
@export var speech: Array[SpeechStep] = []
## The pages of the surface ship's message the verb `messages` shows, in order, in the message box (each a text and the voice groups read with it). Empty: the scene has no message box.
@export var messages: Array[SceneMessage] = []
## Where the numbers come from: the original's function, and which are our own.
@export_multiline var provenance: String = ""


## Every timeline of the scene, the loops first.
func all_timelines() -> Array[StringName]:
	var found: Array[StringName] = []
	found.append_array(loops)
	found.append_array(timelines)
	return found


## The timeline a scene's `timeline_name` is, for a scene played at `place` (null: nowhere, `ScenePlace.nowhere`): the timeline file of the chain, or the timeline a flight file of the chain makes for the sub's place and cell (`SubFlight.timeline`). The one resolver: the
## segment that plays a scene, `unresolved`, `has_cue` and the check of a pack all ask it. Null for a name no pack of the chain holds as either, and for a flight that is not sound (`SubFlight.problems`).
static func timeline_named(timeline_name: StringName, place: ScenePlace = null) -> CutsceneTimeline:
	var timeline := Catalog.story_timeline(timeline_name)
	if timeline != null:
		return timeline
	var flight := Catalog.story_flight(timeline_name)
	if flight == null or not flight.problems().is_empty():
		return null
	var where := place if place != null else ScenePlace.nowhere()
	return flight.timeline(where.sub_at.x, where.sub_at.y, where.sub_cell)


## What is wrong with the scene when played on the chain in use, one sentence each that goes on after "the scene 'x'" and says what the player gets instead; empty when it is fine. The stage itself is not judged
## here (the builder and `PackCheck` tell of the stage and of the actors a timeline names that it lacks); only what the scene needs of it, a button for its `prompt`. `place` is where the scene is played (null: nowhere): a flight's cues do not depend on it.
func unresolved(place: ScenePlace = null) -> PackedStringArray:
	var found := PackedStringArray()
	var made := made_at(place)
	for timeline_name in loops:
		var timeline := made[timeline_name]
		if timeline == null:
			found.append_array(_not_made(timeline_name))
		elif not timeline.loop:
			found.append("lists the timeline '%s' as looping, but it does not loop: it plays once and stops" % timeline_name)
	for i in timelines.size():
		var timeline := made[timelines[i]]
		if timeline == null:
			found.append_array(_not_made(timelines[i]))
		elif timeline.loop and i < timelines.size() - 1:
			found.append("lists the timeline '%s' to play once, but it loops and is not the last: the timelines after it are never played" % timelines[i])
	for timeline_name in made:
		var timeline := made[timeline_name]
		if timeline == null:
			continue
		for cue_entry in timeline.cues:
			var problem := StoryVerbs.problem(cue_entry.cue_name) if cue_entry.kind == CutsceneCue.EVENT else ""
			if not problem.is_empty():
				found.append(StoryVerbs.line(cue_entry.cue_name, problem))
	if song != &"" and not MusicCatalog.has_song(song):
		found.append("names the song '%s', which is neither one of the game's nor audio/music/%s.ogg of a pack: it has no music" % [song, song])
	if prompt_song != &"" and not MusicCatalog.has_song(prompt_song):
		found.append("names the prompt's song '%s', which is neither one of the game's nor audio/music/%s.ogg of a pack: the prompt has no music" % [prompt_song, prompt_song])
	if song_stops_at != &"" and not timelines.has(song_stops_at):
		found.append("stops the song at the timeline '%s', which it does not play once: the song plays on" % song_stops_at)
	if deaf_until_listen and not _has_cue_in(made, &"listen"):
		found.append("drops every key and click until the cue 'listen', which no timeline of it has: no key or click ends it, only the cue 'end'")
	elif _has_cue_in(made, &"listen") and not deaf_until_listen:
		found.append("has the cue 'listen', but does not drop keys until it (deaf_until_listen is off): the cue does nothing")
	var stage_file := Catalog.story_stage(stage)
	if stage_file != null and _has_cue_in(made, &"prompt") and not stage_file.actors.any(func(actor: StageActor) -> bool: return actor.kind == StageActor.BUTTON):
		found.append("has the cue 'prompt', but its stage '%s' has no button: the prompt shows none, and only Enter, a click and the time-out answer it" % stage)
	for step in speech:
		if step.group == &"" or Catalog.voice_cues().clips(String(step.group)).is_empty():
			found.append("speaks the voice group '%s', which no pack of the chain holds in voice_cues: that step is left out" % step.group)
		if step.pause_ticks < 0:
			found.append("has a speech step with a pause of %d ticks: it is taken as 0" % step.pause_ticks)
	found.append_array(_message_lines(made))
	return found


## Does a timeline of the scene have the event cue `cue_name`? (`place`: where the scene is played, null: nowhere.)
func has_cue(cue_name: StringName, place: ScenePlace = null) -> bool:
	return _has_cue_in(made_at(place), cue_name)


## The scene's timelines as made for `place` (null: nowhere), by name (null for one that is not made, `timeline_named`): what the segment plays, `unresolved` judges and the check of a pack looks at, each made once by the one who asks (a flight file is run each time it is made).
func made_at(place: ScenePlace) -> Dictionary[StringName, CutsceneTimeline]:
	var made: Dictionary[StringName, CutsceneTimeline] = {}
	for timeline_name in all_timelines():
		made[timeline_name] = timeline_named(timeline_name, place)
	return made


static func _has_cue_in(made: Dictionary[StringName, CutsceneTimeline], cue_name: StringName) -> bool:
	for timeline: CutsceneTimeline in made.values():
		if timeline != null and timeline.cues.any(func(entry: CutsceneCue) -> bool: return entry.kind == CutsceneCue.EVENT and entry.cue_name == cue_name):
			return true
	return false


## The pages the scene shows: the ones whose text a pack holds, in order (`SceneMessage.has_text`; `unresolved` tells of the others).
func shown_messages() -> Array[SceneMessage]:
	var found: Array[SceneMessage] = []
	for message in messages:
		if message != null and message.has_text():
			found.append(message)
	return found


## Why the timeline `timeline_name` is not played: no pack holds it, or it is a flight file that is not sound.
func _not_made(timeline_name: StringName) -> PackedStringArray:
	var flight := Catalog.story_flight(timeline_name)
	if flight == null:
		return PackedStringArray(["names the timeline '%s', which no pack of the chain holds: it is not played" % timeline_name])
	var found := PackedStringArray()
	for problem in flight.problems():
		found.append("names the flight '%s', which %s" % [timeline_name, problem])
	return found


## What is wrong with the pages of the scene (a text no pack holds, a voice group with no clips) and with the verb that shows them (messages without the cue, the cue without messages).
func _message_lines(made: Dictionary[StringName, CutsceneTimeline]) -> PackedStringArray:
	var found := PackedStringArray()
	for message in messages:
		if message == null or not message.has_text():
			found.append("has a message whose text '%s' no pack of the chain holds: that message is left out" % (message.text if message != null else &""))
			continue
		for group in message.speech:
			if Catalog.voice_cues().clips(String(group)).is_empty():
				found.append("speaks the voice group '%s' with the message '%s', which no pack of the chain holds in voice_cues: that group is not spoken" % [group, message.text])
	if not messages.is_empty() and not _has_cue_in(made, &"messages"):
		found.append("has messages, but no timeline of it has the cue 'messages': they are never shown")
	elif messages.is_empty() and _has_cue_in(made, &"messages"):
		found.append("has the cue 'messages', but no messages: the cue shows nothing")
	return found
