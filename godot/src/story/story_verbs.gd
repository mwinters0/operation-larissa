class_name StoryVerbs
extends RefCounted
## The verbs a cue of a scene's timeline may call, and the one judgement of a cue against them. A cue of kind EVENT is a verb and the words after it (`speak news_speech_0`); `TimelineSegment` carries it out by calling `_verb_<verb>`,
## `StoryScene.unresolved` and `PackCheck` use `problem` to tell a pack's cue that the engine cannot carry out. A verb is one more entry of `VERBS` and one more method of the segment: what a verb does (input, waits, speech) is the
## engine's, a pack only arranges the verbs. What Enter does is not a verb: it goes on to the next timeline of the scene, or, in a timeline that has marks, to the next mark (the timeline's own holds), and once a `prompt` has begun it answers it
## (`TimelineSegment.advance`); in a scene that drops keys until `listen`, Enter and every other key end the scene once `listen` has run, and while the pages of `messages` show Enter belongs to the message box.
##
## Teaches: a small fixed vocabulary as data (a table of verb -> number of words) that both the player of a scene and the check of a pack read, so what the check accepts is what the game does. It is a script of its own, and not
## constants of the segment, because the scene resource (which `Catalog` returns) judges its cues against it and must not depend on the node that plays them.

## The verbs, each with how many words follow it.
const VERBS := {
	&"end": 0,          ## the scene is over
	&"speak": 1,        ## speak the voice group of the word that follows, and wait for it
	&"listen": 0,       ## from here any key or click ends a scene that drops them until it (`StoryScene.deaf_until_listen`)
	&"prompt": 0,       ## ask the player: the stage's buttons appear, Enter, a click elsewhere or the time-out choose Intro, the button's key its own answer; the scene's `prompt_song` starts after a delay
	&"messages": 0,     ## show the scene's `messages` in the message box, one page at a time (`StoryScene.messages`); the scene is over after the last page is closed
}


## The words of an event cue: the verb, then what follows it (`speak news_speech_0` is `["speak", "news_speech_0"]`).
static func parse(cue_name: StringName) -> PackedStringArray:
	return String(cue_name).split(" ", false)


## What is wrong with the event cue `cue_name`, or "" when the engine can carry it out: a verb it has not, a number of words other than the verb takes, a voice group that holds no clips.
static func problem(cue_name: StringName) -> String:
	var words := parse(cue_name)
	if words.is_empty() or not VERBS.has(StringName(words[0])):
		return "'%s' is not a verb of the engine (%s)" % [words[0] if not words.is_empty() else "", ", ".join(VERBS.keys())]
	var verb := StringName(words[0])
	var wanted: int = VERBS[verb]
	if words.size() - 1 != wanted:
		return "'%s' takes %d word%s after it, not %d" % [verb, wanted, "" if wanted == 1 else "s", words.size() - 1]
	if verb == &"speak" and Catalog.voice_cues().clips(words[1]).is_empty():
		return "the voice group '%s' holds no clips in voice_cues" % words[1]
	return ""


## The sentence for an event cue that does nothing (`problem` says why), as it goes on after "the scene 'x'".
static func line(cue_name: StringName, why: String) -> String:
	return "has the cue '%s': %s; the cue does nothing" % [cue_name, why]
