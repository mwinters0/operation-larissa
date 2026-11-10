class_name SubModel
extends RefCounted
## The rules of the player's submarine: where it is, how fast, which sprite cell it shows, whether it is hurt. No nodes.
##
## Teaches: a game that runs on a FIXED LOGIC TICK (GameClock, 12.17 Hz); an integer tile scan for the walls (`wall_gap`);
## rules that read their inputs from a snapshot (`InputSnapshot`, `TileGrid`) instead of from `Input` and a `TileMapLayer`;
## integer game arithmetic (SubTuning.step_velocity); a signal that reports "I left the screen" without knowing what happens
## next; and a lookup-table state machine for the sprite cell (SubTuning.next_cell). The `Sub` node (src/gameplay) only draws
## what this object says.
##
## Coordinates: `position` is the CENTRE of the 96 x 54 picture in playfield pixels (0..607, 0..287). The original stores the
## picture's top-left corner in WINDOW pixels (SubX, SubY), see `place_original` and `original_position`.
##
## THE TICK. Everything that decides what the sub does happens in `logic_tick`, once per game tick (called by the `SimWorld`
## that owns the tick), with the original's whole-number arithmetic: the velocity is a Vector2i in 1/8 pixel per tick, the sub
## moves `velocity >> 3` whole pixels, and x is forced to an even number. (Run at 60 Hz in px/s, this would make weak water
## currents, below the decay of 6 units, drift less than in the original, because the original's "cut to whole pixels once per
## tick" is exactly what lets them move the sub at all.) What stays smooth is the DRAWING: the view shifts the picture between
## ticks from `previous_position` to `position`.
##
## Wall collision is the original's own integer tile scan (`wall_gap`) with ONE fixed box (the run's `wall_box`, 80 x 32 in the original) over the screen's `TileGrid`;
## the physics engine is not used for it, and neither is any `TileMapLayer`. The per-frame rectangles of SubTuning give
## `hurt_rect_window()` (what the creatures are tested against); the pieces are taken with the whole picture box instead
## (`PieceModel.touched_by`).
##
## LIFETIMES. Every member variable is in one of the `*_FIELDS` lists below (tests/engine/test_state_lifetimes.gd checks it): what
## `place_original` clears, what every tick works out again, the switches the owning `SimWorld` sets, and the ones that live as
## long as this object (`KEPT_FIELDS`, with the reason).

## The sub's centre left the playfield through `direction`. The world decides what that means: switch screen (then call
## `enter_from`) or clamp (`clamp_to_edge`).
signal crossed_edge(direction: SectorData.Direction)
## The displayed sprite cell (0-8, see SubTuning) changed.
signal cell_changed(cell: int)
## The sub was put somewhere (`place_original`): a view that hid a dissolved sub shows it again.
signal placed

## Which side of the wall box `wall_gap` looks at.
enum WallSide { LEFT, RIGHT, UP, DOWN }
const TILE_COLUMNS := TileGrid.COLUMNS
const TILE_ROWS := TileGrid.ROWS

# Edge rules of the original, converted from window pixels to the centre origin
# (DESIGN 3.3: SubX < -32 / >= 576, SubY < 3 / >= 291; re-entry at 572 / -32 / 290 / 3).
const LEFT_EDGE := 0.0
const RIGHT_EDGE := 608.0
const TOP_EDGE := -2.0
const BOTTOM_EDGE := 286.0
## Where the sub appears after crossing: just inside the opposite edge.
const ENTER_FROM_RIGHT_X := 604.0
const ENTER_FROM_LEFT_X := 0.0
const ENTER_FROM_BOTTOM_Y := 285.0
const ENTER_FROM_TOP_Y := -2.0
## Offset from the picture's top-left corner (playfield pixels) to its centre.
const PICTURE_CENTER := Vector2(48, 27)
## The playfield starts at (16, 32) in the original's window pixels.
const PLAYFIELD_ORIGIN := Vector2(16, 32)
## The hit bubbles are the sub pictures 9 to 12, each shown for two ticks: `bubble_ticks` beyond `BUBBLE_PICTURES * TICKS_PER_BUBBLE_PICTURE`
## would run out of pictures (`Tuning.check` warns).
const FIRST_BUBBLE_PICTURE := 9
const BUBBLE_PICTURES := 4
const TICKS_PER_BUBBLE_PICTURE := 2

## Cleared by `place_original`: where the sub is and how it moves (`DoAction` (0x417ffc) zeroes `SubVX` / `SubVY` and
## `InvulnerabilityCounter` (0x448684) on entry and sets `SubX` / `SubY` / `SubCell`, from `ExitSupplyStation` (0x4328b0) or the
## sector's respawn point).
const PLACE_FIELDS: Array[StringName] = [&"position", &"previous_position", &"velocity_units", &"cell", &"invulnerability"]
## Worked out again by every controlled tick before anything reads it (`ApplyWaterCurrent` -> `WaterCurrentX` / `WaterCurrentY`,
## 0x448678 / 0x44867c, which `DoAction` does not clear either).
const TICK_FIELDS: Array[StringName] = [&"current_units"]
## Switched by the `SimWorld` that owns the sub (`start_flight`, `stop_flight`, the station trips, the dissolve, the pending problem;
## its `load_sector` puts the beacon out).
const SWITCH_FIELDS: Array[StringName] = [&"active", &"controlled", &"message_light"]
## Member variables that no scope clears, and why.
const KEPT_FIELDS: Dictionary[StringName, String] = {
	&"tuning": "configuration: the run's numbers, handed over by the owner (`SimWorld.load_sector`)",
	&"tile_grid": "wiring: the owner hands over the grid of the screen it shows",
	&"propeller_phase": "free-running like `SubPropellerPhase` (0x44127c), which no routine of the original resets",
}

var tuning: SubTuning
## While false the sub neither moves nor animates and nobody draws it (the sector viewer's browsing mode).
var active: bool = true
## False while a script moves the sub (driving out of / into the supply station, the dissolve): the keys, the water currents and
## the walls are ignored, only the propeller keeps turning.
var controlled: bool = true
## True while the light on the sub blinks: a math problem is waiting (it opens by itself after `Tuning.pending_ticks` ticks (36), or at once when the
## player presses Enter). Set by `SimWorld._set_beacon`, which announces every change (`SimWorld.beacon_changed`).
var message_light: bool = false
## The walls (flag 0x40) and the water currents of the screen the sub is on. Whoever owns the playfield sets it (the world, on
## every screen change); an empty grid, open water everywhere, until then.
var tile_grid := TileGrid.new()

## Centre of the picture in playfield pixels. Always whole numbers while the rules move it.
var position: Vector2 = Vector2.ZERO
## Where `position` was at the start of the last tick (for the view's smoothing).
var previous_position: Vector2 = Vector2.ZERO
## Velocity in the original's units: 1/8 pixel per tick. The simulation's one truth.
var velocity_units: Vector2i = Vector2i.ZERO
## Sprite cell 0-8 (see SubTuning). Start of a sector: cell 6, facing right.
var cell: int = 6
## 0 or 1; flips each game tick so the propeller seems to turn.
var propeller_phase: int = 0
## The water current acting on the sub right now, in the original's units (1/8 px per tick per tick). Zero outside current
## tiles. Exposed for tests/HUD.
var current_units: Vector2i = Vector2i.ZERO
## Ticks of invulnerability left after a creature hit (0 = vulnerable).
var invulnerability: int = 0


## `sub_tuning` is the `sub` section of the run's `Tuning`; the owner hands over another when a run begins (`tuning`).
func _init(sub_tuning: SubTuning) -> void:
	tuning = sub_tuning


## Looks up the current under the sub (DESIGN 3.3: the tile just below the picture's centre). Read once per game tick, before
## the sub moves.
func read_current() -> Vector2i:
	return tile_grid.current_at_point(position + Vector2(tuning.current_probe))


# --- the tick -------------------------------------------------------------------

## Everything the sub does in one game tick, in the order of the original's DoAction: timers, sprite cell (from the keys, or
## from the drift when no key is held), velocity (keys, decay, current), movement, screen edges. `input` is what the player's
## hands did (`steer`); null means nothing is pressed. Public so tests can run it without a world.
func logic_tick(input: InputSnapshot = null) -> void:
	previous_position = position
	propeller_phase ^= 1
	if invulnerability > 0:
		invulnerability -= 1
	if not controlled:
		return

	var steer := input.steer if input != null else Vector2i.ZERO
	# With no key, the sprite follows the direction we are drifting in (the sign of the velocity BEFORE it decays this tick).
	_update_cell(
			steer.x if steer.x != 0 else signi(velocity_units.x),
			steer.y if steer.y != 0 else signi(velocity_units.y))

	current_units = read_current()
	velocity_units = tuning.step_velocity(velocity_units, steer, current_units)
	_move(SubTuning.displacement(velocity_units))
	_check_edges()


## A mod's sub ability (`RuleHooks.sub_ability`): `effect` is what the game validated and cut to the run's limits (`RuleHooks.validate_sub`), keys all optional: `vx` and `vy` set the velocity
## (1/8 pixel per tick; the next tick's walls and edges apply to it as to any velocity) and `invulnerability` the ticks of it that are left. An empty effect changes nothing.
func adjust(effect: Dictionary) -> void:
	if effect.has("vx"):
		velocity_units.x = effect["vx"]
	if effect.has("vy"):
		velocity_units.y = effect["vy"]
	if effect.has("invulnerability"):
		invulnerability = effect["invulnerability"]


## Moves the sub by whole pixels like `DoAction` does: BOTH axes are checked against the walls from the position at the start of
## the tick (`wall_gap`), a blocked axis is shortened to the free distance and loses its velocity, then SubX (forced even) and
## SubY are updated together. The physics engine is not involved: its safety margin made a sub that rests against a ceiling or
## floor collide with that tile as soon as it moved sideways (Dragon Reef sector 1, screen 1: the capsule on the right was out
## of reach).
func _move(step: Vector2i) -> void:
	var at := Vector2i(position.round() - PICTURE_CENTER + PLAYFIELD_ORIGIN)     # whole pixels, as in the original
	var dx := step.x
	var dy := step.y
	if dx < 0:
		var gap := wall_gap(WallSide.LEFT, at, _is_solid, tuning.wall_box)
		if gap < 1 and dx < gap:
			velocity_units.x = 0
			dx = gap
	elif dx > 0:
		var gap := wall_gap(WallSide.RIGHT, at, _is_solid, tuning.wall_box)
		if gap >= 0 and gap < dx:
			velocity_units.x = 0
			dx = gap
	if dy < 0:
		var gap := wall_gap(WallSide.UP, at, _is_solid, tuning.wall_box)
		if gap < 1 and dy < gap:
			velocity_units.y = 0
			dy = gap
	elif dy > 0:
		var gap := wall_gap(WallSide.DOWN, at, _is_solid, tuning.wall_box)
		if gap >= 0 and gap < dy:
			velocity_units.y = 0
			dy = gap
	position = Vector2((at.x + dx) & ~1, at.y + dy) - PLAYFIELD_ORIGIN + PICTURE_CENTER


## True when tile (`column`, `row`) of the playfield is solid (flag 0x40; invisible walls count).
func _is_solid(column: int, row: int) -> bool:
	return tile_grid.is_solid(column, row)


## The box the wall scan looks at, in the coordinates of the tile map: `box` (`SubTuning.wall_box`, relative to the picture's top-left
## corner) put where the sub is, `at` being SubX / SubY (window pixels, which lie `PLAYFIELD_ORIGIN` from the tile map). The original's
## box is x SubX-8 .. SubX+71, y SubY-22 .. SubY+9.
static func wall_scan_box(at: Vector2i, box: Rect2i) -> Rect2i:
	return Rect2i(at - Vector2i(PLAYFIELD_ORIGIN) + box.position, box.size)


## The wall scan of the original (`ScanSubWalls` (0x418ea7), Ghidra; DESIGN 3.3). `at` is SubX / SubY (window pixels of the
## picture's top-left corner); `box` is the run's wall box (`SubTuning.wall_box`; `wall_scan_box` puts it in the coordinates of the
## tile map).
## Only the (up to two) tile rows / columns BEYOND the box's own edge tile are looked at; tiles the box already overlaps are
## ignored. `is_solid` takes (column, row).
## Returns, for LEFT / UP, the farthest allowed (negative) move, or 1 when there is no wall within two tiles; for RIGHT / DOWN
## the farthest allowed (positive) move, or -1 when there is none.
static func wall_gap(side: WallSide, at: Vector2i, is_solid: Callable, box: Rect2i) -> int:
	var scan := wall_scan_box(at, box)
	var left := scan.position.x
	var right := scan.end.x - 1
	var top := scan.position.y
	var bottom := scan.end.y - 1
	# GDScript's int division and % truncate towards zero, like the original's C code.
	var first_column := maxi(left / 16, 0)
	var last_column := mini(right / 16, TILE_COLUMNS - 1)
	var first_row := maxi(top / 16, 0)
	var last_row := mini(bottom / 16, TILE_ROWS - 1)
	match side:
		WallSide.LEFT:
			var column := left / 16 - 1
			for n in 2:
				if column < 0:
					break
				if _column_has_solid(is_solid, column, first_row, last_row):
					return -(n * 16 + left % 16)
				column -= 1
			return 1
		WallSide.RIGHT:
			var column := right / 16 + 1
			for n in 2:
				if column >= TILE_COLUMNS:
					break
				if _column_has_solid(is_solid, column, first_row, last_row):
					return n * 16 + (15 - right % 16)
				column += 1
			return -1
		WallSide.UP:
			var row := top / 16 - 1
			for n in 2:
				if row < 0:
					break
				if _row_has_solid(is_solid, row, first_column, last_column):
					return -(n * 16 + top % 16)
				row -= 1
			return 1
		_:
			var row := bottom / 16 + 1
			for n in 2:
				if row >= TILE_ROWS:
					break
				if _row_has_solid(is_solid, row, first_column, last_column):
					return n * 16 + (15 - bottom % 16)
				row += 1
			return -1


static func _column_has_solid(is_solid: Callable, column: int, first_row: int, last_row: int) -> bool:
	for row in range(first_row, last_row + 1):
		if is_solid.call(column, row):
			return true
	return false


static func _row_has_solid(is_solid: Callable, row: int, first_column: int, last_column: int) -> bool:
	for column in range(first_column, last_column + 1):
		if is_solid.call(column, row):
			return true
	return false


func _update_cell(horizontal: int, vertical: int) -> void:
	var new_cell := tuning.next_cell(cell, horizontal, vertical)
	if new_cell != cell:
		cell = new_cell
		cell_changed.emit(cell)


# --- hits, invulnerability -----------------------------------------------------

## Starts the invulnerable period after a creature hit.
func start_invulnerability() -> void:
	invulnerability = tuning.invulnerability_ticks


func is_invulnerable() -> bool:
	return invulnerability > 0


## True while the sprite blinks: the LAST `blink_ticks` ticks of the invulnerable period (after the first 8 ticks of bubbles),
## see DrawSub in DESIGN 3.3.
func is_blinking() -> bool:
	return invulnerability > 0 and invulnerability <= tuning.blink_ticks


## The picture shows on every other tick while blinking (the propeller phase flips every tick, so it doubles as the blink clock).
func is_picture_visible() -> bool:
	return not is_blinking() or propeller_phase == 1


## Which bubble picture (9-12) is drawn now, or -1 outside the first `bubble_ticks` ticks of the invulnerability (`SubTuning`); the
## sub blinks for the last `blink_ticks`.
func bubble_picture() -> int:
	var elapsed := tuning.invulnerability_ticks - invulnerability
	if invulnerability > 0 and elapsed < tuning.bubble_ticks:
		return FIRST_BUBBLE_PICTURE + floori(elapsed / float(TICKS_PER_BUBBLE_PICTURE))
	return -1


# --- placing ---------------------------------------------------------------------

## The original's SubX / SubY: window pixels of the picture's top-left corner.
func original_position() -> Vector2i:
	return Vector2i(position - PICTURE_CENTER + PLAYFIELD_ORIGIN)


## The rectangle creatures are tested against, in WINDOW pixels (the same system as `FoeModel.hit_rect_window()`): the current
## cell's rectangle from `SubTuning.frame_rects` moved to the picture's top-left corner.
func hurt_rect_window() -> Rect2i:
	var rect := tuning.frame_rects[cell]
	return Rect2i(rect.position + original_position(), rect.size)


## Puts the sub where the original would, from its SubX / SubY (window pixels of the picture's top-left corner) and sprite cell. Clears
## every field of `PLACE_FIELDS`: the entry of `DoAction` (0x417ffc) zeroes `SubVX` / `SubVY` and `InvulnerabilityCounter` (0x448684).
func place_original(sub_x: int, sub_y: int, new_cell: int = 6) -> void:
	position = Vector2(sub_x, sub_y) - PLAYFIELD_ORIGIN + PICTURE_CENTER
	velocity_units = Vector2i.ZERO
	invulnerability = 0
	cell = new_cell
	snap()
	placed.emit()


## Forget the previous position: after a jump the picture must not glide across the screen.
func snap() -> void:
	previous_position = position


## After the playfield switched screens: put the sub just inside the edge opposite to `direction` (leaving to the right means
## entering from the left).
func enter_from(direction: SectorData.Direction) -> void:
	match direction:
		SectorData.Direction.LEFT:
			position.x = ENTER_FROM_RIGHT_X
		SectorData.Direction.RIGHT:
			position.x = ENTER_FROM_LEFT_X
		SectorData.Direction.UP:
			position.y = ENTER_FROM_BOTTOM_Y
		SectorData.Direction.DOWN:
			position.y = ENTER_FROM_TOP_Y
	snap()


## There is no screen behind that edge: stay at the limit. As in the original the velocity is left alone; it decays by itself
## when the key is released.
func clamp_to_edge(direction: SectorData.Direction) -> void:
	match direction:
		SectorData.Direction.LEFT:
			position.x = LEFT_EDGE
		SectorData.Direction.RIGHT:
			position.x = ENTER_FROM_RIGHT_X
		SectorData.Direction.UP:
			position.y = TOP_EDGE
		SectorData.Direction.DOWN:
			position.y = ENTER_FROM_BOTTOM_Y
	snap()


func _check_edges() -> void:
	# Horizontal first, then vertical, like the original (both can fire in a corner).
	if position.x < LEFT_EDGE:
		crossed_edge.emit(SectorData.Direction.LEFT)
	elif position.x >= RIGHT_EDGE:
		crossed_edge.emit(SectorData.Direction.RIGHT)
	if position.y < TOP_EDGE:
		crossed_edge.emit(SectorData.Direction.UP)
	elif position.y >= BOTTOM_EDGE:
		crossed_edge.emit(SectorData.Direction.DOWN)


## Velocity in pixels per second, for read-outs and tests (the simulation uses units).
func velocity_px_per_s() -> Vector2:
	return tuning.velocity_to_px_per_s(velocity_units)
