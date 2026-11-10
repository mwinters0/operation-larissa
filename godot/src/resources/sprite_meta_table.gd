@tool
class_name SpriteMetaTable
extends Resource
## Pixel size and collision boxes for a list of sprites.
##
## Teaches: separating *data about* images (hit boxes) from the images.
## All values are in pixels (the original stores half pixels; already doubled).
##
## The original keeps each set of sprites in three resources of 512 bytes (widths, heights, hit rectangles); only the
## first `count()` entries are used, the rest is zero. `encode_widths()`, `encode_heights()` and `encode_hit_rects()` give
## them back; tests/legacy/test_sprite_meta_fidelity.gd checks their hashes against tests/fixtures/sprite_meta.json
## (docs/port/FIDELITY.md).

## Size of each of the original's three resources, in bytes.
const RESOURCE_SIZE := 512
## Bytes of a sprite's entry in the hit rectangle table: x1 y1 x2 y2 of the box, then the same of the flipped box.
const RECT_ENTRY := 8
## Sprites that fit in the hit rectangle table.
const MAX_SPRITES := RESOURCE_SIZE / RECT_ENTRY

## Size of each sprite, in pixels.
@export var sizes: Array[Vector2i] = []
## Hit box relative to the sprite's top-left, for the unflipped sprite.
@export var hit_rects: Array[Rect2i] = []
## Same, for the horizontally flipped sprite.
@export var hit_rects_flipped: Array[Rect2i] = []

func count() -> int:
	return sizes.size()

## Hit box of sprite `slot`, taking the flip into account.
func hit_rect(slot: int, flipped: bool = false) -> Rect2i:
	return hit_rects_flipped[slot] if flipped else hit_rects[slot]


# --- the original's table bytes ----------------------------------------------------------------------------------

## Everything that stops the tables from being stored as the original's, in plain words; empty when they fit.
## The `encode_*` functions return nothing while this is not empty.
func problems() -> Array[String]:
	var found: Array[String] = []
	var n := sizes.size()
	if hit_rects.size() != n or hit_rects_flipped.size() != n:
		found.append("%d sizes, %d hit rectangles and %d flipped hit rectangles: there must be one of each per sprite" % [n, hit_rects.size(), hit_rects_flipped.size()])
		return found
	if n > MAX_SPRITES:
		found.append("%d sprites, but the hit rectangle table has room for %d" % [n, MAX_SPRITES])
		return found
	for i in n:
		found.append_array(_half_problems(sizes[i].x, "sprite %d width" % i))
		found.append_array(_half_problems(sizes[i].y, "sprite %d height" % i))
		for pair: Array in [["hit rectangle", hit_rects[i]], ["flipped hit rectangle", hit_rects_flipped[i]]]:
			var r: Rect2i = pair[1]
			var what: String = "sprite %d %s" % [i, pair[0]]
			found.append_array(_half_problems(r.position.x, what + " left"))
			found.append_array(_half_problems(r.position.y, what + " top"))
			found.append_array(_half_problems(r.end.x, what + " right (left + width)"))
			found.append_array(_half_problems(r.end.y, what + " bottom (top + height)"))
	return found


## The widths table: RESOURCE_SIZE bytes (width / 2 per sprite, then zeros), or an empty array while `problems()` finds problems.
func encode_widths() -> PackedByteArray:
	return _encode_sizes(true)


## The heights table, the same.
func encode_heights() -> PackedByteArray:
	return _encode_sizes(false)


## The hit rectangle table: RESOURCE_SIZE bytes, 8 per sprite (x1 y1 x2 y2 of the box, then of the flipped box, all / 2),
## then zeros, or an empty array while `problems()` finds problems.
func encode_hit_rects() -> PackedByteArray:
	if not problems().is_empty():
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(RESOURCE_SIZE)
	for i in sizes.size():
		for pair: Array in [[0, hit_rects[i]], [4, hit_rects_flipped[i]]]:
			var at: int = RECT_ENTRY * i + pair[0]
			var r: Rect2i = pair[1]
			out[at] = r.position.x / 2
			out[at + 1] = r.position.y / 2
			out[at + 2] = r.end.x / 2
			out[at + 3] = r.end.y / 2
	return out


func _encode_sizes(widths: bool) -> PackedByteArray:
	if not problems().is_empty():
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(RESOURCE_SIZE)
	for i in sizes.size():
		out[i] = (sizes[i].x if widths else sizes[i].y) / 2
	return out


## Messages for a pixel value that the original keeps halved in one byte.
static func _half_problems(value: int, what: String) -> Array[String]:
	var found: Array[String] = []
	if value < 0 or value > 2 * 255:
		found.append("%s %d does not fit: the original keeps it / 2 in one byte, so 0 to 510" % [what, value])
	elif value % 2 != 0:
		found.append("%s %d is not on the grid: the original keeps it / 2, so it must be even" % [what, value])
	return found


## The name of the entry that byte `offset` of table `kind` ("widths", "heights" or "hit_rects") belongs to, e.g.
## "sprite 3 flipped hit rectangle top". With `used` (the number of sprites of the set) an entry after them is marked.
static func field_at(kind: String, offset: int, used: int = -1) -> String:
	var sprite := offset if kind != "hit_rects" else offset / RECT_ENTRY
	var label: String
	match kind:
		"widths":
			label = "width"
		"heights":
			label = "height"
		_:
			var part := offset % RECT_ENTRY
			label = "%shit rectangle %s" % ["flipped " if part >= 4 else "", ["left", "top", "right", "bottom"][part % 4]]
	var tail := " (after the stored sprites)" if used >= 0 and sprite >= used else ""
	return "sprite %d %s%s" % [sprite, label, tail]


## "" when the two tables are the same, else "first difference at byte 0x0b (sprite 1 flipped hit rectangle top): expected
## 0x06, got 0x08". Names the entry of the `expected` table `kind`.
static func first_difference(kind: String, expected: PackedByteArray, actual: PackedByteArray, used: int = -1) -> String:
	if actual.size() != expected.size():
		return "the %s table has %d bytes, expected %d" % [kind, actual.size(), expected.size()]
	for i in expected.size():
		if expected[i] != actual[i]:
			return "first difference in the %s table at byte 0x%03x (%s): expected 0x%02x, got 0x%02x" % [kind, i, field_at(kind, i, used), expected[i], actual[i]]
	return ""
