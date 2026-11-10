class_name Deco
extends AnimatedSprite2D
## A static decoration (seaweed, rock, coral ...) placed on a screen.
##
## Teaches: instancing a small scene from code, and using one shared
## SpriteFrames "sprite sheet" as an indexed picture set: the deco's `slot`
## is simply the frame number of the animation "all", which never plays.

## Configures the sprite. Call before `add_child` (or after, it does not matter).
func setup(frames: SpriteFrames, placement: DecoPlacement) -> void:
	sprite_frames = frames
	animation = &"all"
	frame = placement.slot
	position = Vector2(placement.pos) - Sub.PLAYFIELD_ORIGIN       # stored in window pixels
	# Bit 7 of the original id byte means "draw mirrored" (verified by
	# comparing against the backgrounds: unflipped decos leave hard seams).
	flip_h = placement.flag
