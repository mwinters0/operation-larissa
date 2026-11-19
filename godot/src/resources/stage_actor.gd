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
const BUTTON := &"button"        ## a `TextureButton` showing `picture` (pressed: `pressed_picture`) that answers a prompt with its `choice`; hidden until the scene's `prompt` begins
const FRAMES := &"frames"        ## an `AnimatedSprite2D` showing a picture of a SET the scene's view holds (the sub's drawings, a zone's creatures): `frames` names the set, a timeline's `frame` and `pose` tracks pick the picture
const CHAIN := &"chain"          ## a clipped box that carries a stack of pictures (the crane's cable) which a timeline's `extent` track lowers and raises and whose first piece, the hook, shows one of `pictures` as its `frame` track says
const FILL := &"fill"            ## a rectangle of one `color` and `size`
const KINDS: Array[StringName] = [PICTURE, TEXT, GROUP, BUTTON, FRAMES, CHAIN, FILL]

## What a button answers (`choice`): the opening's director compares it with the part's `leads_on` (`OpeningPart`), so two answers are known.
const START := &"start"          ## leave the opening: the game
const INTRO := &"intro"          ## go on to the story pages
const CHOICES: Array[StringName] = [START, INTRO]

## The name a timeline gives this actor in its tracks (`radar`, `crew_3`); it is also the actor's node in the scene, written in capitals
## (`Radar`, `Crew3`: `node_name`). Unique in a stage.
@export var name: StringName = &""
## One of `KINDS`.
@export var kind: StringName = PICTURE
## The picture the actor starts with: a NAME of the registry (`ui_picture` kind), as a timeline's `picture` track writes it. Empty for a group
## and a text box. A `frames` actor: the picture of its set it starts on, named as a timeline's `frame` track names it (empty: the first). A `chain`'s hook gets its picture from `pictures`, not from here.
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
## A text box, a `fill`: its size in window pixels. A `group` or a `chain` with a size shows only that rectangle of what it carries (the playfield, the crane's arm); with none it clips nothing.
@export var size: Vector2 = Vector2.ZERO
## A button: the picture it shows while it is pressed (a NAME like `picture`); empty: it looks the same pressed.
@export var pressed_picture: StringName = &""
## A button: what pressing it answers, one of `CHOICES`.
@export var choice: StringName = &""
## A button: the key that presses it from the keyboard, as the engine names keys (`I`, `S`); empty: none. Its size is its picture's.
@export var hotkey: String = ""
## A `frames` actor: the name of the picture set it shows. The scene's view hands the sets in when it builds the stage (`CutsceneCast.frame_sets`), so the stage names which one.
@export var frames: StringName = &""
## A `chain`: the pictures its first piece (the hook) takes, by the `frame` a timeline sets (open, closing, closed). The pieces are the actors that have the chain as their parent, listed from the hook up and placed where
## they stand when the chain's `extent` is 0; a timeline's `extent` track moves them all down by that many pixels.
@export var pictures: Array[StringName] = []
## A `fill`: the colour of the rectangle.
@export var color: Color = Color.WHITE


## The name of the actor's node: the words of `name` joined, each in capitals (`mini_sub` -> `MiniSub`, `dot_07` -> `Dot07`).
func node_name() -> String:
	var parts := String(name).split("_", false)
	var joined := ""
	for part in parts:
		joined += part.substr(0, 1).to_upper() + part.substr(1)
	return joined

