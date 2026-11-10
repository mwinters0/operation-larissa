@tool
class_name DecoPlacement
extends Resource
## One decoration placed on a screen (seaweed, rock, coral ...).
##
## Teaches: the smallest useful custom Resource. Each placement is a tiny
## record that the Inspector can show and edit. Also: a Resource that can write itself back
## into the original's 3-byte record (`encode`) and say what does not fit (`problems`).
##
## The original data stores x/4 and y/2 in single bytes; the importer has
## already multiplied them back, so `pos` is in WINDOW pixels like the original's (the
## playfield starts at window (16, 32); `Deco` subtracts that).

## Size of one entry in the original screen record.
const RECORD_SIZE := 3

## Top-left position of the picture in window pixels (x 16-623, y 32-319 is the playfield).
@export var pos: Vector2i = Vector2i.ZERO
## Index into the zone's deco SpriteFrames ("decos_zone{z}.tres").
## 0-69 are the common decos, 70+ are the zone's own decos.
@export var slot: int = 0
## Bit 7 of the original id byte: draw the deco mirrored left-to-right (decided by comparing against the backgrounds).
@export var flag: bool = false


## The 3 bytes of the original record: x / 4, y / 2, slot | 0x80 for the mirrored flag.
## Only meaningful when `problems()` is empty.
func encode() -> PackedByteArray:
	return PackedByteArray([pos.x / 4, pos.y / 2, slot | (0x80 if flag else 0)])


## What keeps this placement from being stored in the original format; empty when it fits.
func problems() -> Array[String]:
	var found: Array[String] = []
	found.append_array(ScreenData.position_problems(pos, "x", "y"))
	if slot < 0 or slot > 127:
		found.append("slot %d does not fit: the id byte keeps the slot in 7 bits (0 to 127), bit 7 is the mirror flag" % slot)
	return found
