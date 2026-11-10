class_name InkPellet
extends Node2D
## One ink pellet fired from the sub, as it is drawn: the flying picture or one of the three splash pictures.
##
## Teaches: spawning a scene from code (`PackedScene.instantiate`) as the answer to an event (`SimWorld.pellet_fired`) and freeing
## it on the next (`pellet_gone`); a node that only shows a model (a plain `Node2D`: no physics body, the sub flies through it). Where the pellet is, whether it flies or splashes, and what it
## touches are the fields and rules of its `PelletModel` (src/rules/pellet_model.gd), which `SimWorld` steps once per game tick.

## Ink bundle pictures 1-3 are the splash; picture 0 is the flying pellet.
const FIRST_SPLASH_PICTURE := PelletModel.FIRST_SPLASH_PICTURE
const SPLASH_PICTURES := PelletModel.SPLASH_PICTURES
## The ink pictures start at this slot of a zone's foe SpriteFrames.
const INK_SLOT_BASE := 28

var model: PelletModel

var _frames: SpriteFrames

@onready var sprite: AnimatedSprite2D = %Sprite


## Shows `pellet_model` with the ink pictures of `frames`. Call before adding the node to the tree.
func setup(pellet_model: PelletModel, frames: SpriteFrames) -> void:
	model = pellet_model
	_frames = frames
	position = model.position


func _ready() -> void:
	sprite.sprite_frames = _frames
	sprite.animation = &"all"
	sprite.pause()
	refresh()


## Called once per drawn frame (`SectorPresenter.show_between_ticks`): the picture is `fraction` (0..1) of the way from the pellet's
## previous place to its current one.
func show_between_ticks(fraction: float) -> void:
	sprite.position = model.splash_offset + TickSmoothing.offset(model.previous_position, position, fraction)


## Copies the model to the nodes: the place and the picture (the flying one, or the current splash picture).
func refresh() -> void:
	position = model.position
	sprite.frame = INK_SLOT_BASE + model.splash_picture
