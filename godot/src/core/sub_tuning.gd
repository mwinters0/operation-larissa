class_name SubTuning
extends RefCounted
## Physics constants of the submarine, and the tables that say which picture it shows. The numbers are the `"sub"` section of
## `data/rules/tuning.json` (`Tuning` builds this object from it, once per run); the methods below are the rules that use them.
##
## Teaches: deriving modern units from legacy source units, and keeping the
## derivation in one commented place.
##
## The original runs at 73/6 = 12.1667 ticks per second. Velocity is stored in
## 1/8 pixel per tick, acceleration in 1/8 pixel per tick per tick. So:
##   px/s   = units / 8 * tick_hz         (1 unit = 1.5208 px/s)
##   px/s^2 = units / 8 * tick_hz^2       (1 unit = 18.505 px/s^2)
##
## The sub's physics runs on that same tick (see `step_velocity`), with the
## original's whole-number arithmetic, because the exact integers matter: a weak
## water current (below the decay of 6 units) only works out the way the original
## did when velocity is cut to whole pixels once per tick. The px/s conversions
## below are for humans (HUD read-outs, tests), not for the simulation.

const OWNER := "SubTuning"

## Game logic rate of the original, in ticks per second.
var tick_hz: float = 0.0
## Source units (1/8 px per tick).
var max_speed_x_units: int = 0
var max_speed_y_units: int = 0
var accel_units: int = 0
var decay_units: int = 0
## Collision rectangle of each of the 9 sub frames (left, top, width, height in px,
## measured from the top-left corner of the 96 x 54 sub picture). The creatures
## are tested against this one; pieces use the whole 96 x 58 picture, walls `wall_box` below.
var frame_rects: Array[Rect2i] = []
## The box the original tests against the *tile map*. Unlike `frame_rects` it is the
## same for every frame (DESIGN 3.3: x from SubX-8 to SubX+71, y from SubY-22 to
## SubY+9 in playfield pixels), here relative to the picture's top-left corner.
var wall_box := Rect2i()
## Size of the sub picture (all eight sub pictures are 96 x 54).
var sprite_size := Vector2i()
## The current is read from the tile under this point, relative to the picture's centre.
var current_probe := Vector2i()

# --- sprite cells ------------------------------------------------------------
# The original shows the sub with one of 9 "cells". 0-3 face left (the picture is
# mirrored), 4 is the front view, 5-8 face right. Each tick a lookup table maps
# the current cell to the next one, depending on what the player presses.
#   cell:   0 left+nose down   1 left+nose up   2 left level   3 left level
#           4 front            5, 6 right level   7 right+nose up   8 right+nose down
## Picture (0-7 of sub_frames) for `cell * 2 + propeller_phase`; the phase flips every tick.
var cell_pictures := PackedInt32Array()
## Next cell when steering left / right (or drifting left / right with vx < 0 / > 0).
var cell_after_left := PackedInt32Array()
var cell_after_right := PackedInt32Array()
## Next cell when steering down / up (or drifting down / up).
var cell_after_down := PackedInt32Array()
var cell_after_up := PackedInt32Array()
## Next cell when there is no vertical movement.
var cell_after_level := PackedInt32Array()
## After a creature hit: invulnerable for this many ticks, a stream of air bubbles (sub pictures 9-12) for the first `bubble_ticks`, then
## blinking for the last `blink_ticks`.
var invulnerability_ticks: int = 0
var blink_ticks: int = 0
var bubble_ticks: int = 0

# --- ink pellets (StartStunGun / UpdateStunGun, extracted/tables/ink_tables.json) -------
## Where a pellet appears, relative to the sub picture's top-left corner, per sprite cell.
var ink_spawn_dx := PackedInt32Array()
var ink_spawn_dy := PackedInt32Array()
## Direction code per sprite cell; it indexes the two step tables below.
## Code 3 means "no motion": a pellet fired while facing the viewer splashes at once.
var ink_direction := PackedInt32Array()
var ink_step_dx := PackedInt32Array()
var ink_step_dy := PackedInt32Array()
## A pellet moves this many steps per game tick (3 steps of 8 px = 24 px per tick).
var ink_steps_per_tick: int = 0
## Offsets of the three splash pictures (ink bundle pictures 1-3, then 4 and 4).
var ink_splash_dx := PackedInt32Array()
var ink_splash_dy := PackedInt32Array()

# --- what DrawSub puts on the sub (extracted/tables/bubbles.json, DESIGN 3.3) -------------
## The hit bubbles (sub pictures 9-12): left edge relative to the sub picture's left edge, per sprite cell.
var hit_bubble_x_by_cell := PackedInt32Array()
## The blinking message light (sub picture 8) is drawn only in these cells (the sub is seen from the side).
var light_cells := PackedInt32Array()
## Where the light's top-left corner is, relative to the sub picture's top-left corner, per cell.
var light_dx_by_cell := PackedInt32Array()
var light_dy_by_cell := PackedInt32Array()


## The sub's numbers from the `"sub"` section of the merged `tuning.json` (`Tuning`); a key the section lacks is reported and left at 0.
static func from_dict(section: Dictionary) -> SubTuning:
	var t := SubTuning.new()
	t.tick_hz = LayeredJson.float_of(section, "tick_hz", OWNER)
	t.max_speed_x_units = LayeredJson.int_of(section, "max_speed_x_units", OWNER)
	t.max_speed_y_units = LayeredJson.int_of(section, "max_speed_y_units", OWNER)
	t.accel_units = LayeredJson.int_of(section, "accel_units", OWNER)
	t.decay_units = LayeredJson.int_of(section, "decay_units", OWNER)
	for row in LayeredJson.int_rows_of(section, "frame_rects", 4, OWNER):
		t.frame_rects.append(Rect2i(row[0], row[1], row[2], row[3]))
	var wall := LayeredJson.row_of(section, "wall_box", 4, OWNER)
	t.wall_box = Rect2i(wall[0], wall[1], wall[2], wall[3])
	var size := LayeredJson.row_of(section, "sprite_size", 2, OWNER)
	t.sprite_size = Vector2i(size[0], size[1])
	var probe := LayeredJson.row_of(section, "current_probe", 2, OWNER)
	t.current_probe = Vector2i(probe[0], probe[1])
	t.cell_pictures = LayeredJson.ints_of(section, "cell_pictures", OWNER)
	t.cell_after_left = LayeredJson.ints_of(section, "cell_after_left", OWNER)
	t.cell_after_right = LayeredJson.ints_of(section, "cell_after_right", OWNER)
	t.cell_after_down = LayeredJson.ints_of(section, "cell_after_down", OWNER)
	t.cell_after_up = LayeredJson.ints_of(section, "cell_after_up", OWNER)
	t.cell_after_level = LayeredJson.ints_of(section, "cell_after_level", OWNER)
	t.invulnerability_ticks = LayeredJson.int_of(section, "invulnerability_ticks", OWNER)
	t.blink_ticks = LayeredJson.int_of(section, "blink_ticks", OWNER)
	t.bubble_ticks = LayeredJson.int_of(section, "bubble_ticks", OWNER)
	t.ink_spawn_dx = LayeredJson.ints_of(section, "ink_spawn_dx", OWNER)
	t.ink_spawn_dy = LayeredJson.ints_of(section, "ink_spawn_dy", OWNER)
	t.ink_direction = LayeredJson.ints_of(section, "ink_direction", OWNER)
	t.ink_step_dx = LayeredJson.ints_of(section, "ink_step_dx", OWNER)
	t.ink_step_dy = LayeredJson.ints_of(section, "ink_step_dy", OWNER)
	t.ink_steps_per_tick = LayeredJson.int_of(section, "ink_steps_per_tick", OWNER)
	t.ink_splash_dx = LayeredJson.ints_of(section, "ink_splash_dx", OWNER)
	t.ink_splash_dy = LayeredJson.ints_of(section, "ink_splash_dy", OWNER)
	t.hit_bubble_x_by_cell = LayeredJson.ints_of(section, "hit_bubble_x_by_cell", OWNER)
	t.light_cells = LayeredJson.ints_of(section, "light_cells", OWNER)
	t.light_dx_by_cell = LayeredJson.ints_of(section, "light_dx_by_cell", OWNER)
	t.light_dy_by_cell = LayeredJson.ints_of(section, "light_dy_by_cell", OWNER)
	return t


## Conversion factor: source velocity units -> pixels per second.
func units_to_px_per_s() -> float:
	return tick_hz / 8.0

## Conversion factor: source acceleration units -> pixels per second squared.
func units_to_px_per_s2() -> float:
	return tick_hz * tick_hz / 8.0

func max_speed_x() -> float:
	return max_speed_x_units * units_to_px_per_s()

func max_speed_y() -> float:
	return max_speed_y_units * units_to_px_per_s()

func accel() -> float:
	return accel_units * units_to_px_per_s2()

func decay() -> float:
	return decay_units * units_to_px_per_s2()


# --- the velocity rule, in the original's integer units ------------------------

## One game tick of the sub's velocity (DESIGN 3.3), all in whole numbers:
##  1. a held key accelerates by `accel_units` up to the speed limit of that axis;
##     with no key the velocity decays towards 0 by `decay_units` and never overshoots;
##  2. the water `current` (units) is added, then the limits apply again.
## `steer` is -1, 0 or +1 per axis. A pure function: nothing but its arguments is read.
func step_velocity(v: Vector2i, steer: Vector2i, current: Vector2i) -> Vector2i:
	var next := Vector2i(
			_step_axis(v.x, steer.x, max_speed_x_units),
			_step_axis(v.y, steer.y, max_speed_y_units))
	next += current
	return Vector2i(
			clampi(next.x, -max_speed_x_units, max_speed_x_units),
			clampi(next.y, -max_speed_y_units, max_speed_y_units))


func _step_axis(v: int, key: int, limit: int) -> int:
	if key != 0:
		return clampi(v + key * accel_units, -limit, limit)
	if v < 0:
		return mini(v + decay_units, 0)
	return maxi(v - decay_units, 0)


## Whole pixels moved in one tick for a velocity in units. `>> 3` is an arithmetic
## shift, i.e. a division by 8 that rounds DOWN: -1..-8 units move the sub one pixel
## to the left, while +1..+7 units move it not at all. That asymmetry is the original's.
static func displacement(v: Vector2i) -> Vector2i:
	return Vector2i(v.x >> 3, v.y >> 3)


## Velocity units -> pixels per second (for read-outs and tests).
func velocity_to_px_per_s(v: Vector2i) -> Vector2:
	return Vector2(v) * units_to_px_per_s()


## Top-left of a pellet fired from `cell`, relative to the sub picture's top-left corner.
func pellet_spawn_offset(cell: int) -> Vector2i:
	return Vector2i(ink_spawn_dx[cell], ink_spawn_dy[cell])


## One of the `ink_steps_per_tick` steps a pellet fired from `cell` takes each tick.
func pellet_step(cell: int) -> Vector2i:
	var code := ink_direction[cell]
	return Vector2i(ink_step_dx[code], ink_step_dy[code])


## Index of the picture to show: `phase` is 0 or 1 and flips on every game tick,
## which makes the propeller turn.
func picture_for(cell: int, phase: int) -> int:
	return cell_pictures[cell * 2 + (phase & 1)]

## Pictures of cells 0-3 are mirrored so that the sub faces left.
static func is_flipped(cell: int) -> bool:
	return cell < 4

## One step of the cell state machine (a pure function: easy to unit test).
## `horizontal` / `vertical` are -1, 0 or +1: the key held, or, when no key is
## held, the sign of the velocity (the sprite keeps tilting while the sub coasts).
func next_cell(cell: int, horizontal: int, vertical: int) -> int:
	if horizontal < 0:
		cell = cell_after_left[cell]
	elif horizontal > 0:
		cell = cell_after_right[cell]
	if vertical > 0:
		cell = cell_after_down[cell]
	elif vertical < 0:
		cell = cell_after_up[cell]
	else:
		cell = cell_after_level[cell]
	return cell

## The wall box in sub-centred coordinates (the Sub node's origin is the picture's centre).
func wall_box_centered() -> Rect2:
	return _centered(wall_box)

## Collision rectangle of `cell` in sub-centred coordinates.
func frame_rect_centered(cell: int) -> Rect2:
	return _centered(frame_rects[cell])

func _centered(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position) - Vector2(sprite_size) / 2.0, Vector2(rect.size))
