class_name PelletModel
extends RefCounted
## One ink pellet fired from the sub, as the rules see it. No nodes.
##
## Teaches: a tiny two-state machine (flying -> splashing) and a thing that exists only as long as the list that holds it says so
## (`SimWorld.pellets`; the number of pellets in flight is the length of that list, not a count of scene children).
##
## A pellet moves on the game tick like everything else (`SimWorld.tick` steps it, last of all, after the contacts): 3 steps per
## tick of up to 8 pixels each (24 px per tick, 292 px/s), the numbers come from SubTuning. After each step it checks the rock:
## the original looks at the tile under the pellet's centre, so we ask the screen's `TileGrid` (the wall bytes) the same question.
## A pellet that touches rock or a creature turns into a three-picture splash; one that leaves the playfield just disappears
## (`alive` becomes false and the world drops it).
##
## What a pellet touches is plain rectangle arithmetic, not physics (like the sub's contacts):
##  * Creatures: `SimWorld.check_contacts` tests the 16 x 16 box (`window_rect`) of every FLYING pellet against the creatures that
##    do NOT touch the sub that tick, as `update_animals` (0x41ed0c) does (the pellet test is the ELSE branch of its sub test). The
##    first pellet that overlaps starts the creature's ink script (any damage, also harmless and friendly ones) and calls
##    `hit_creature`. Hidden, off-screen and already interrupted creatures are skipped.
##  * The sub: never. No code of the original reads a pellet together with the sub (only `StartStunGun` reads SubX / SubY / SubCell,
##    for the spawn point), so the sub flies through its own pellets.

## The pellet starts its splash (on rock or on a creature): the original plays sound 0x19 then.
signal splashed

enum State { FLYING, SPLASHING }

## The pellet picture is 16 x 16; its centre is what is tested against the tiles.
const PICTURE_CENTER := Vector2(8, 8)
## The pellet is removed once its top-left corner leaves this area (the original's limits converted from window to playfield
## pixels).
const MIN_POSITION := Vector2(-15, -15)
const MAX_POSITION := Vector2(607, 287)
## Ink bundle pictures 1-3 are the splash; picture 0 is the flying pellet.
const FIRST_SPLASH_PICTURE := 1
const SPLASH_PICTURES := 3

## Number of the shot since the world was made (the events name a pellet by it).
var id: int = 0
var state: State = State.FLYING
## False once the pellet is gone (its splash is over, or it flew out of the playfield).
var alive: bool = true
## Pixels per step, from the direction table; `ink_steps_per_tick` steps per tick.
var step: Vector2i = Vector2i.ZERO
var splash_picture: int = 0     # 1-3 while splashing
## Top-left corner of the picture in playfield pixels, and where it was at the start of the last tick (for the view's smoothing).
var position: Vector2 = Vector2.ZERO
var previous_position: Vector2 = Vector2.ZERO
## Where the current splash picture is drawn relative to `position`.
var splash_offset: Vector2 = Vector2.ZERO

var _tuning: SubTuning
var _grid: TileGrid


## Prepares a pellet for the sub cell `cell`. `top_left` is the pellet picture's top-left corner in playfield pixels; `grid` is
## the screen it flies over.
func launch(top_left: Vector2, cell: int, tuning: SubTuning, grid: TileGrid) -> void:
	position = top_left
	previous_position = top_left
	_tuning = tuning
	_grid = grid
	step = tuning.pellet_step(cell)


## The pellet exists now (the world has put it in its list). Fired facing the viewer, a pellet has no motion and splashes at once.
func begin() -> void:
	if step == Vector2i.ZERO:
		_start_splash()


## One game tick, called by `SimWorld.tick` (the pellet does not listen to the clock itself). Public so tests can run it without
## a world.
func logic_tick() -> void:
	previous_position = position
	match state:
		State.FLYING:
			for i in _tuning.ink_steps_per_tick:
				position += Vector2(step)
				if _outside_playfield():
					alive = false
					return
				if _touches_rock():
					_start_splash()
					return
		State.SPLASHING:
			if splash_picture >= FIRST_SPLASH_PICTURE + SPLASH_PICTURES - 1:
				alive = false
			else:
				_show_splash(splash_picture + 1)


func is_flying() -> bool:
	return state == State.FLYING


func _outside_playfield() -> bool:
	return position.x < MIN_POSITION.x or position.x > MAX_POSITION.x \
			or position.y < MIN_POSITION.y or position.y > MAX_POSITION.y


## The original tests the tile under the picture's centre.
func _touches_rock() -> bool:
	return _grid.is_solid_at(position + PICTURE_CENTER)


## The 16 x 16 box that is tested against the creature rectangles, in WINDOW pixels, edges inclusive (`FoeModel.rects_touch`):
## `StunGunX` / `StunGunY` (0x44b04c / 0x44b054) to +15 in `update_animals`.
func window_rect() -> Rect2i:
	return Rect2i(Vector2i(position) + Vector2i(SubModel.PLAYFIELD_ORIGIN), Vector2i(15, 15))


## A creature was hit: the pellet starts its splash (and plays the splash sound, like on rock).
func hit_creature() -> void:
	if state == State.FLYING:
		_start_splash()


func _start_splash() -> void:
	state = State.SPLASHING
	splashed.emit()
	_show_splash(FIRST_SPLASH_PICTURE)


func _show_splash(picture: int) -> void:
	splash_picture = picture
	# Each splash picture is drawn at its own offset from the pellet's position.
	splash_offset = Vector2(_tuning.ink_splash_dx[picture], _tuning.ink_splash_dy[picture])
	previous_position = position
