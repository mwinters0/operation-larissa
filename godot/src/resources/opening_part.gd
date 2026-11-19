class_name OpeningPart
extends Resource
## One part of the opening, as DATA: what kind of part it is, the file of the pack chain it plays, and which answer of the part leads on to the next. An `OpeningList` lists them in order; `Opening` plays them.
##
## Teaches: a part as a name and a kind, not a node: the director builds the segment that plays it (`Opening._segment_of`), so a pack arranges the opening by writing names.

## The kinds of part.
const SCENE := &"scene"          ## a scene file (`StoryScene`, `data/story/<name>.tres`) played by a `TimelineSegment`
const STORY := &"story"          ## a story script (`StoryScript`, `data/story/<name>.tres`: pages of pictures, text and speech) played by `StoryPages`
const KINDS: Array[StringName] = [SCENE, STORY]

## One of `KINDS`.
@export var kind: StringName = SCENE
## The file the part plays, by name: a scene or a story script of the chain (`Catalog.story_scene`, `Catalog.story_script`).
@export var name: StringName = &""
## The answer of the part (one of `StageActor.CHOICES`, what a scene's `prompt` buttons say) that goes on to the next part; any other answer, or none, leaves the opening for the sign-in screen. Empty: the part always goes on.
@export var leads_on: StringName = &""
