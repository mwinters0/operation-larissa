class_name PieceModel
extends RefCounted
## A rock piece or the data canister lying on the sea floor, as the rules see it: a place and a number. No nodes.
##
## Teaches: when NOT to use physics. The original takes a piece with plain integer arithmetic on two rectangles
## (`CheckProbeCollision` 0x42dbb2, see `touched_by`): the WHOLE 96 x 58 picture box of the sub, edges included, against the
## piece's 24 x 20 box, whatever the sprite cell. An `Area2D` would use the (smaller) per-cell hurt rectangle and does not see
## rectangles that merely touch. `SimWorld` asks every piece of the screen once per game tick, before the sub moves, as `DoAction`
## does; what picking up MEANS (a bit in the run, a sound, maybe a math problem) is decided there too. Whether a piece is still
## lying around is not stored here: the world keeps the pieces of the screen that are not collected (`SimWorld.pieces`).

## Size of the pictures of the pieces bundle (24 x 20).
const PICTURE_SIZE := Vector2i(24, 20)
## Size of the sub's picture (bundle 15, 96 x 58): the box that takes the pieces.
const SUB_PICTURE_SIZE := Vector2i(96, 58)

## Number of the piece in its sector's list (0 = the data canister); the bit it sets in the run's piece mask.
var index: int = 0
var data: PieceData


func _init(piece: PieceData = null, piece_index: int = 0) -> void:
	data = piece
	index = piece_index


## Window pixels, the same numbers as the sub's SubX / SubY.
func position() -> Vector2i:
	return data.pos


func is_canister() -> bool:
	return data.is_canister


## `CheckProbeCollision` (0x42dbb2): the sub's picture box (`sub_pos` = SubX / SubY, 96 x 58) touches the piece's 24 x 20 box at
## `piece_pos` (window pixels). Both edges count: SubX <= px + 23, px <= SubX + 95, SubY <= py + 19, py <= SubY + 57. The sprite
## cell plays no part.
static func touched_by(sub_pos: Vector2i, piece_pos: Vector2i) -> bool:
	return sub_pos.x <= piece_pos.x + PICTURE_SIZE.x - 1 and piece_pos.x <= sub_pos.x + SUB_PICTURE_SIZE.x - 1 \
			and sub_pos.y <= piece_pos.y + PICTURE_SIZE.y - 1 and piece_pos.y <= sub_pos.y + SUB_PICTURE_SIZE.y - 1


## Does the sub at `sub_pos` take this piece?
func is_touched_by(sub_pos: Vector2i) -> bool:
	return touched_by(sub_pos, data.pos)
