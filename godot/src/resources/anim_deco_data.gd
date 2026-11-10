@tool
class_name AnimDecoData
extends Resource
## An animated decoration: a list of deco slots shown one after another.
##
## Teaches: decoded fields as the single owner of a binary record. The original keeps a 22-byte record
## (DESIGN 4.1); the earlier version of this resource carried those bytes in a second field (`raw`) next to
## the decoded ones. Now only the decoded fields exist and `encode()` writes the 22 bytes from them; the
## fidelity test (tests/legacy/test_screen_fidelity.gd) proves that this gives back every one of the 355 original
## records byte for byte.
##
## Two things in the record are constant in all 355 original records and are therefore not fields: a frame
## entry never has bit 7 set, and the bytes after the list's 0 terminator are all 1. The importer stops with an
## error if a game copy ever differs, so that nothing is lost silently.

## Size of one entry in the original screen record.
const RECORD_SIZE := 22
## Header bytes before the frame list: x/4, y/2, w/4, h/2, start cursor.
const HEADER_SIZE := 5
## Most frames the 17 list bytes can hold and still end with the 0 terminator.
const MAX_FRAMES := 16
## What follows the terminator up to the end of the 22 bytes.
const FILLER := 1

## Top-left position in window pixels (the playfield starts at (16, 32)).
@export var pos: Vector2i = Vector2i.ZERO
## Deco slots (same 0-based numbering as DecoPlacement.slot), one per game tick,
## looping back to the start at the end of the list.
## The original file stores slot + 1 here (0 ends the list); `encode` adds the 1 again.
@export var frames: PackedInt32Array = PackedInt32Array()
## Size in pixels of the largest frame (header bytes [2] * 4 and [3] * 2).
@export var size: Vector2i = Vector2i.ZERO
## Start position in the frame list (header byte [4]). Identical decos next to
## each other use different values so they do not all animate in lock-step.
## It can be larger than the list; use `start_cursor % frames.size()`.
@export var start_cursor: int = 0


## The 22 bytes of the original record: x/4, y/2, w/4, h/2, start cursor, frames + 1, a 0, then 1s.
## Only meaningful when `problems()` is empty.
func encode() -> PackedByteArray:
	var out := PackedByteArray([pos.x / 4, pos.y / 2, size.x / 4, size.y / 2, start_cursor])
	for slot in frames:
		out.append(slot + 1)
	out.append(0)
	while out.size() < RECORD_SIZE:
		out.append(FILLER)
	return out


## What keeps this record from being stored in the original format; empty when it fits.
func problems() -> Array[String]:
	var found: Array[String] = []
	found.append_array(ScreenData.position_problems(pos, "x", "y"))
	found.append_array(ScreenData.position_problems(size, "width", "height"))
	if start_cursor < 0 or start_cursor > 255:
		found.append("start_cursor %d does not fit in one byte (0 to 255)" % start_cursor)
	if frames.size() > MAX_FRAMES:
		found.append("%d frames do not fit: the record has room for %d, then the 0 that ends the list" % [frames.size(), MAX_FRAMES])
	for i in frames.size():
		if frames[i] < 0 or frames[i] > 126:
			found.append("frame %d: slot %d does not fit (the list stores slot + 1 in 7 bits, so 0 to 126)" % [i, frames[i]])
	return found
