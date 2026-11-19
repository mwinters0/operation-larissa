class_name SpeechStep
extends Resource
## One line of a scene's speech: wait `pause_ticks`, then speak the voice group `group` and wait until it has been spoken. A `StoryScene` lists them in the order they are said.
##
## Teaches: a pause and the group it comes before in ONE record, so the two cannot drift apart (a list of pauses in one file and a list of groups in another, matched by position, can). How long a group
## SPEAKS is not here: it is the recorded lengths of its clips (`Audio.speak`), which is why the speech is a sequence of steps and not cues at moments of a timeline.

## The wait before the group, in ticks of the original's 73 Hz timer (0: the group follows at once).
@export var pause_ticks: int = 0
## The voice group (`VoiceCues.clips`: the `voice_cues` group of that name in the chain) that is spoken.
@export var group: StringName = &""
