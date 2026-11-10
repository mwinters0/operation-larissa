@tool
class_name VoiceCues
extends Resource
## Which speech clips the original plays when (docs/data/audio_map.json, read from the decompiled game).
##
## The 371 clips are NE1SOUND 4000-4370; the game never plays one by itself, it plays RUNS of clips: the lines of a
## canister log, of a mission-control message, of the opening story. Each run is one entry of `groups`, stored as the
## original's numbers (generated data) and handed out as `voice` NAMES (names/original.json), which is what `Audio` plays.
##
## `@tool` because the pack check (`PackNeeds`) asks `clips` of it, and the editor's plugins start that check; a resource script that is not a tool script is only a placeholder in the editor
## and its methods can not be called.
##
## Teaches: data instead of code. The "which clip follows which" knowledge lives in a generated Resource, and the
## accessors below only turn a sector number into a group name and the numbers into names.

@export var groups: Dictionary = {}


## A group by name ("supply_3", "log_0", "jingle" ...); empty if there is no such group.
func clips(group: String) -> Array[StringName]:
	var registry := NameRegistry.original()
	var names: Array[StringName] = []
	for entry: Variant in groups.get(group, PackedInt32Array()):
		names.append(StringName(entry) if entry is String or entry is StringName else StringName(registry.name_of(&"voice", entry)))
	return names


## The "incoming transmission" sound that comes before every mission-control message (1.4 s).
func jingle() -> StringName:
	return clips("jingle")[0]


## (What mission control says after a sector and the spoken log entries are the campaign's: `Campaign.supply_voice_name`, `log_voice_name`;
## hand the name to `clips`.)

## The Voyager closing sequence speaks three pages (0-2).
func closing_page(page: int) -> Array[StringName]:
	return clips("closing_page_%d" % clampi(page, 0, 2))


## The opening story is nine pages (0-8) of one to three clips each (the opening shows them).
func story_page(page: int) -> Array[StringName]:
	return clips("story_page_%d" % clampi(page, 0, 8))


## Sign-in: "This is a highly classified mission. Please enter your name ..." when the screen first appears.
func sign_in_first_visit() -> Array[StringName]:
	return clips("sign_in_first_visit")


## Sign-in, after Start: the clearance clip, then the begin-mission clip (new player) or the resume-mission clip.
func sign_in_start(resuming: bool) -> Array[StringName]:
	return clips("sign_in_resume" if resuming else "sign_in_begin")
