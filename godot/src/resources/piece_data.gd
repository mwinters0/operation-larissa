@tool
class_name PieceData
extends Resource
## A collectible: capsule piece or data canister.

## Which of the sector's 12 screens it lies on.
@export var screen: int = 0
## Position of the picture's top-left corner in WINDOW pixels (the playfield starts at (16, 32)).
@export var pos: Vector2i = Vector2i.ZERO
## The first piece of every sector is the data canister.
@export var is_canister: bool = false
