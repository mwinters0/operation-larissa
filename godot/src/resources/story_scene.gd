class_name StoryScene
extends Resource
## A scene of the opening as DATA: which stage it stands on, which timelines it plays (the ones that loop and the ones that play once, in order), which song starts with it and what is said. The pack holds
## it as `data/story/<scene>.tres` (`.json` in the data form; `Catalog.story_scene`); a `TimelineSegment` plays it. Every name in it is a file of the pack chain: `stage` a `CutsceneStage`
## (`Catalog.story_stage`), `loops` and `timelines` `CutsceneTimeline`s (`Catalog.story_timeline`), `song` a song of the music catalog or of the pack, the groups of `speech` groups of `voice_cues`.
##
## What happens at a moment of a timeline is an EVENT cue whose name is a VERB of the engine and its words (`StoryVerbs.VERBS`): `end` finishes the scene, `speak <group>` speaks a voice group, `prompt` asks the player (the stage's buttons). A
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
## The timelines that play once, one after the other (the cartoon itself). The scene is over when a cue says `end`.
@export var timelines: Array[StringName] = []
## The song that starts with the scene (a `music` name); empty: no song starts.
@export var song: StringName = &""
## The timeline of `timelines` at whose start the song stops (the title's song ends when the title is revealed); empty: the song plays on.
@export var song_stops_at: StringName = &""
## The song the `prompt` verb starts after `prompt.music_delay_ticks` (the story's own song, once the buttons are up); empty: none.
@export var prompt_song: StringName = &""
## What is said, in order: each step a pause and a voice group. Empty: the scene is silent.
@export var speech: Array[SpeechStep] = []
## Where the numbers come from: the original's function, and which are our own.
@export_multiline var provenance: String = ""


## Every timeline of the scene, the loops first.
func all_timelines() -> Array[StringName]:
	var found: Array[StringName] = []
	found.append_array(loops)
	found.append_array(timelines)
	return found


## What is wrong with the scene when played on the chain in use, one sentence each that goes on after "the scene 'x'" and says what the player gets instead; empty when it is fine. The stage itself is not judged
## here (the builder and `PackCheck` tell of the stage and of the actors a timeline names that it lacks); only what the scene needs of it, a button for its `prompt`.
func unresolved() -> PackedStringArray:
	var found := PackedStringArray()
	for timeline_name in loops:
		var timeline := Catalog.story_timeline(timeline_name)
		if timeline == null:
			found.append("names the timeline '%s', which no pack of the chain holds: it is not played" % timeline_name)
		elif not timeline.loop:
			found.append("lists the timeline '%s' as looping, but it does not loop: it plays once and stops" % timeline_name)
	for timeline_name in timelines:
		var timeline := Catalog.story_timeline(timeline_name)
		if timeline == null:
			found.append("names the timeline '%s', which no pack of the chain holds: it is not played" % timeline_name)
		elif timeline.loop:
			found.append("lists the timeline '%s' to play once, but it loops: the timelines after it are never played" % timeline_name)
	for timeline_name in all_timelines():
		var timeline := Catalog.story_timeline(timeline_name)
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
	var stage_file := Catalog.story_stage(stage)
	if stage_file != null and _has_cue(&"prompt") and not stage_file.actors.any(func(actor: StageActor) -> bool: return actor.kind == StageActor.BUTTON):
		found.append("has the cue 'prompt', but its stage '%s' has no button: the prompt shows none, and only Enter, a click and the time-out answer it" % stage)
	for step in speech:
		if step.group == &"" or Catalog.voice_cues().clips(String(step.group)).is_empty():
			found.append("speaks the voice group '%s', which no pack of the chain holds in voice_cues: that step is left out" % step.group)
		if step.pause_ticks < 0:
			found.append("has a speech step with a pause of %d ticks: it is taken as 0" % step.pause_ticks)
	return found


## Does a timeline of the scene have the event cue `cue_name`?
func _has_cue(cue_name: StringName) -> bool:
	for timeline_name in all_timelines():
		var timeline := Catalog.story_timeline(timeline_name)
		if timeline != null and timeline.cues.any(func(entry: CutsceneCue) -> bool: return entry.kind == CutsceneCue.EVENT and entry.cue_name == cue_name):
			return true
	return false
