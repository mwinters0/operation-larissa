class_name StageActor
extends Resource
## One thing on a cutscene's stage, as DATA: its name (the one a `CutsceneTrack` names), what kind of thing it is, the picture it starts with,
## where it stands in window pixels, whether it is mirrored, whom it rides with, and whether it is there when the scene starts. The
## `CutsceneStage` that lists the actors is what `StageBuilder` makes nodes of.
##
## Teaches: a scene's furniture as plain fields instead of nodes in a `.tscn`: a pack author arranges a scene by editing numbers and names,
## and the same list builds the same nodes in every view. A position is in WINDOW pixels (the 640 x 400 screen) whatever the parent, so a
## picture is put where it shows; the builder subtracts the parent's position to give the node its place inside the parent.

## The kinds of actor.
const PICTURE := &"picture"      ## a `Sprite2D` showing `picture`
const TEXT := &"text"            ## a `Label` of `size` that the timeline's `text` and `reveal` tracks fill (the teletype)
const GROUP := &"group"          ## a `Node2D` that holds other actors and moves them as one (the ship that carries its radar and hook)
const KINDS: Array[StringName] = [PICTURE, TEXT, GROUP]

## The name a timeline gives this actor in its tracks (`radar`, `crew_3`); it is also the actor's node in the scene, written in capitals
## (`Radar`, `Crew3`: `node_name`). Unique in a stage.
@export var name: StringName = &""
## One of `KINDS`.
@export var kind: StringName = PICTURE
## The picture the actor starts with: a NAME of the registry (`ui_picture` kind), as a timeline's `picture` track writes it. Empty for a group
## and a text box.
@export var picture: StringName = &""
## Where the actor's top-left corner is, in window pixels.
@export var position: Vector2 = Vector2.ZERO
## Drawn mirrored (flipped left to right).
@export var mirror: bool = false
## The actor this one rides with: it moves when the parent does and is hidden with it. Empty: it stands on the stage itself. A parent is listed BEFORE its children.
@export var parent: StringName = &""
## Is the actor there when the scene starts?
@export var visible: bool = true
## A picture: the part of it that is drawn, in the picture's pixels (the mini-sub that sinks behind the waves starts whole and a timeline's `clip` track shrinks it). An empty rectangle draws the whole picture.
@export var clip: Rect2 = Rect2()
## A text box: its size in window pixels.
@export var size: Vector2 = Vector2.ZERO


## The name of the actor's node: the words of `name` joined, each in capitals (`mini_sub` -> `MiniSub`, `dot_07` -> `Dot07`).
func node_name() -> String:
	var parts := String(name).split("_", false)
	var joined := ""
	for part in parts:
		joined += part.substr(0, 1).to_upper() + part.substr(1)
	return joined
