class_name OpeningList
extends Resource
## The opening as DATA: its parts in the order they are played, and whether it starts over. The pack holds it as `data/story/opening.tres` (`.json` in the data form; `Catalog.opening`); `Opening` plays it. A pack may hold an
## opening of its own (any number of scenes and story pages, in any order) or an empty one (the game goes straight to the sign-in screen).
##
## Every name in it is a file of the pack chain. `problem` and `unresolved` are the ONE judgement of the list against the chain: `Opening` tells each line once when it plays and skips the part that does not resolve, `PackCheck` reports the same
## lines.
##
## The legacy pack's list is written by the importer (`tools/import/step_story.py`), the dev pack's by `tools/dev_pack/dev_story.py`; `provenance` says which.
##
## Teaches: the order of a sequence and the rules of its ending (which answer goes on, whether it loops) as data next to the parts, so a director that reads them has no list of its own, and one function judges them for the game and for the check.

## The parts, in order.
@export var parts: Array[OpeningPart] = []
## Does the opening start over when the last part that played ran out its time with no key and no click (`StorySegment.timed_out`)? The original's "attract mode" (`OpeningSequence` 0x42b16b): without a limit, until a key or a choice leaves.
@export var starts_over: bool = false
## Where the numbers come from: the original's function, and which are our own.
@export_multiline var provenance: String = ""


## What is wrong with `part` that makes the opening leave it out, as a sentence that goes on after "the opening's part 2"; empty when the chain holds what the part plays.
func problem(part: OpeningPart) -> String:
	if not OpeningPart.KINDS.has(part.kind):
		return "is of the kind '%s', which is none of %s: that part is skipped" % [part.kind, ", ".join(OpeningPart.KINDS)]
	if part.kind == OpeningPart.SCENE and Catalog.story_scene(part.name) == null:
		return "names the scene '%s', which no pack of the chain holds (data/story/%s.tres): that part is skipped" % [part.name, part.name]
	if part.kind == OpeningPart.STORY and Catalog.story_script(part.name) == null:
		return "names the story '%s', which no pack of the chain holds (data/story/%s.tres): that part is skipped" % [part.name, part.name]
	return ""


## Every line of trouble the list has when played on the chain in use, each as it goes on after "the opening's" (the part's number counts from 1, as a pack author counts): the parts that are skipped, and the answers that can never come.
func unresolved() -> PackedStringArray:
	var found := PackedStringArray()
	for i in parts.size():
		var part := parts[i]
		var skipped := problem(part)
		var label := "part %d (%s '%s')" % [i + 1, part.kind, part.name]
		if not skipped.is_empty():
			found.append("%s %s" % [label, skipped])
		if part.leads_on == &"":
			continue
		if not StageActor.CHOICES.has(part.leads_on):
			found.append("%s goes on with the answer '%s', which none of %s is: the opening ends after it" % [label, part.leads_on, ", ".join(StageActor.CHOICES)])
		elif part.kind != OpeningPart.SCENE or (skipped.is_empty() and not _asks(part)):
			found.append("%s goes on with the answer '%s', but nothing in it asks (a scene needs the cue 'prompt'): the opening ends after it" % [label, part.leads_on])
	return found


## Does the scene of `part` have a prompt that the player answers?
func _asks(part: OpeningPart) -> bool:
	var scene := Catalog.story_scene(part.name)
	return scene != null and scene.has_cue(&"prompt")
