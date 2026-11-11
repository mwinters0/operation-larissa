class_name Collectible
extends Node2D
## A rock piece or the data canister lying on the sea floor, as it is drawn.
##
## Teaches (animation): an `AnimatedSprite2D` whose frame is set by the GAME CLOCK instead of by `play()`. The original draws
## every piece once per game frame from one counter that runs 0..15 and is shared by all pieces (`DrawProbePieces` 0x42dc3b,
## extracted/tables/piece_animation.json): the data canister flashes red / green on every tick, every other piece is a rock that sparkles
## on 3 of the 16 ticks. The `SpriteFrames` animations "canister" (2 frames) and "rock" (16 frames, one per tick) of the legacy pack are generated
## from that data; a pack may give them any number of frames. `frame` is simply `GameClock.tick_count % frame_count`, so every piece stays in step, even after a screen
## change. When the clock stops (a problem is up) the pieces freeze, like everything else.
##
## Whether the sub takes the piece (the rectangle arithmetic of `CheckProbeCollision`) is `PieceModel`'s rule; this node is a plain
## sprite that the `OriginalPresenter` creates for every piece in `SimWorld.pieces` and frees when the rules say it was collected.

## Size of the pictures of the pieces bundle (24 x 20).
const PICTURE_SIZE := Vector2(PieceModel.PICTURE_SIZE)
## The two animations of `pieces_frames.tres`.
const CANISTER_ANIMATION := &"canister"
const ROCK_ANIMATION := &"rock"

var model: PieceModel
## Number of the piece in its sector (kept for the tests and tools that look for a node by it).
var index: int = 0
var data: PieceData

@onready var sprite: AnimatedSprite2D = %Sprite


## Call before adding the node to the tree.
func setup(piece: PieceModel) -> void:
	model = piece
	data = piece.data
	index = piece.index
	# The data holds WINDOW pixels (the same numbers as the sub's SubX / SubY); the playfield
	# starts at (16, 32) of the window. The pieces of the real sectors range over x 16-592,
	# y 64-288, which only fits the playfield when you subtract that origin.
	position = Vector2(piece.position()) - Sub.PLAYFIELD_ORIGIN


func _ready() -> void:
	sprite.sprite_frames = Catalog.pieces_frames()
	sprite.animation = animation_for(data.is_canister)
	_show_tick(GameClock.tick_count)
	GameClock.tick.connect(_show_tick)


## The data canister flashes; every other piece is a rock that sparkles.
static func animation_for(is_canister: bool) -> StringName:
	return CANISTER_ANIMATION if is_canister else ROCK_ANIMATION


## The picture of the pieces bundle (0-4: rock, two sparkles, red and green canister) that a piece shows on
## game tick `tick`.
static func picture_for(is_canister: bool, tick: int) -> int:
	var frames := Catalog.pieces_frames()
	var animation := animation_for(is_canister)
	var texture := frames.get_frame_texture(animation, posmod(tick, frames.get_frame_count(animation)))
	for i in frames.get_frame_count(&"all"):
		if frames.get_frame_texture(&"all", i) == texture:
			return i
	return -1


func _show_tick(tick_count: int) -> void:
	sprite.frame = tick_count % sprite.sprite_frames.get_frame_count(sprite.animation)
