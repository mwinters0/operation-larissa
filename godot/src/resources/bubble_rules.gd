class_name BubbleRules
extends Resource
## The rules of the ambient bubbles, as decoded from the original's BUBBLES.C (DESIGN 9, "Ambient bubbles").
## The values come from `docs/data/bubbles.json` through the importer (`data/bubble_rules.tres`); nothing here
## is typed in by hand, so a change in the data changes the game and the tests.
##
## The original has exactly TWO bubbles, a thin "column" and a wider "cluster", each with its own speed and
## picture order. A bubble that is not active has a 1 in `spawn_chance` chance per tick to start.
## Positions are window pixels (the playfield's top-left corner is (16, 32)).

## Each tick an idle bubble starts when `randi_range(0, spawn_chance - 1) == 0`.
@export var spawn_chance: int = 50
## A new bubble starts with its picture's top edge at this y (the playfield's bottom edge)...
@export var spawn_y: int = 320
## ...and ends when its picture is completely above this y (the playfield's top edge).
@export var top_y: int = 32
## Left edge: `x_base + random(0 .. x_span - picture_width - 1)`, rounded down to an even number.
@export var x_base: int = 28
@export var x_span: int = 584

## Per bubble (slot): the first picture of the fx bundle, pixels risen per tick, and the pictures that follow the
## first one, repeating forever (a column: 1, 2, 3, 0, ...; a cluster: 5, 6, 7, 6, 5, 4, ...).
@export var slot_first_picture: PackedInt32Array = PackedInt32Array()
@export var slot_rise_per_tick: PackedInt32Array = PackedInt32Array()
@export var slot_loop: Array[PackedInt32Array] = []
## The size of each of the eight bubble pictures (pixels), written by the importer from the picture files. The spawn range
## (`width` below) and the test "completely above the playfield" use these, so no random draw or despawn depends on which
## bubble pictures are on disk (a skin with bigger bubbles keeps the original's numbers).
@export var picture_sizes: Array[Vector2i] = []

## Screens without bubbles: Vector2i(sector, screen). The first four screens of sector 0.
@export var no_bubble_screens: Array[Vector2i] = []
## The finale sector has none on these screens.
@export var finale_sector: int = 30
@export var finale_screens: PackedInt32Array = PackedInt32Array()


## The width of a bubble's first picture rounded down to an even number: the original rounds the width before the
## spawn range `x_span - width` is drawn from.
func spawn_width(slot: int) -> int:
	return picture_sizes[slot_first_picture[slot]].x & ~1


## The height of picture number `picture`: a bubble is gone once `height + y < top_y`.
func picture_height(picture: int) -> int:
	return picture_sizes[picture].y


## How many bubbles can exist at once (one per slot).
func slot_count() -> int:
	return slot_first_picture.size()


## False on the screens where the original never draws or moves the bubbles.
func allowed_on(sector_index: int, screen_index: int) -> bool:
	if no_bubble_screens.has(Vector2i(sector_index, screen_index)):
		return false
	return not (sector_index == finale_sector and finale_screens.has(screen_index))


## The picture `age` ticks after the bubble started (age 0 = the first picture).
func picture_at(slot: int, age: int) -> int:
	if age == 0:
		return slot_first_picture[slot]
	var loop := slot_loop[slot]
	return loop[(age - 1) % loop.size()]


## The leftmost x of a bubble whose first picture is `picture_width` wide, for a random number `r` in
## 0 .. `x_span - width - 1`: `x_base + r`, rounded down to even (the original did the same with `& 1`).
func x_for(r: int) -> int:
	var x := x_base + r
	return x - (x & 1)
