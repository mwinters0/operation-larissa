class_name SectorReach
extends RefCounted
## Breadth-first search over everything the submarine can reach in one sector.
##
## Teaches: testing a whole game level automatically. The state is the sub's position on the ORIGINAL's integer grid
## (screen, SubX, SubY; SubX is always even), the moves are what one game tick can do, and the walls are the very
## function the game uses (`SubModel.wall_gap`, the port of `ScanSubWalls` (0x418ea7)), so "reachable" here means
## "a player can get there in the game".
##
## THE MOVE MODEL. Per tick the sub moves `(vx >> 3, vy >> 3)` pixels, at most `max_speed_*_units >> 3` (16 / 12 in the original's
## `SubTuning`), but WHICH displacement is possible
## depends on the velocity history. What does NOT depend on it is this: from rest, one can always get a net move of
## exactly one grid step with the sub at rest again afterwards (x: +-2, because SubX is forced even; y: +-1):
##   right  2: key, key, opposite key  -> dx 1, 3, 1 = SubX +0, +2, +0      left  2: key, opposite key -> dx -2, 0
##   down   1: key, opposite key       -> dy 1, 0                           up    1: key, opposite, opposite -> dy -2, 0, +1
## (the intermediate positions are never beyond the target, and a wall that shortens a move shortens it to exactly the
## free distance, so a step is possible exactly when `wall_gap` leaves room for it). The scan looks two tiles (>= 32 px)
## ahead, farther than any single move of the original (<= 16 px), so a wall can never be jumped over by a fast move: small steps do not
## lose any place that big steps reach in open water. What big steps CAN do is slip diagonally past a tile corner (both
## axes of one tick are scanned from the position at the START of the tick, and tiles the box already overlaps are ignored).
## Three modes therefore exist:
##  * ORTHOGONAL - steps (+-2, 0) and (0, +-1). A sound lower bound: everything it reaches is really reachable.
##  * DIAGONAL   - adds (+-2, +-1) in one tick (the corner slip, an approximation: exact diagonal steps need matching velocities).
##  * FAST       - adds the big moves at top speed and at half of it (the original's (+-16, +-12), (+-8, +-6), (+-16, 0), (0, +-12)
##                 etc., `max_step`). An upper bound.
## Currents are ignored (pure geometry), as are creatures.
##
## Screen changes are DESIGN 3.3 / `DoAction`: SubX < -32 -> left neighbour at 572; SubX >= 576 -> right neighbour at -32;
## then (with the possibly new screen) SubY < 3 -> up neighbour at 290; SubY >= 291 -> down neighbour at 3; no neighbour
## (0 in the original, -1 here) clamps to the edge (-32 / 572 / 3 / 290).

enum Mode { ORTHOGONAL, DIAGONAL, FAST }

const COLUMNS := 38
const ROWS := 18
const SCREENS := 12
## SubX range of the grid (even), SubY range. Beyond it `DoAction` switches screens or clamps.
const X_MIN := -32
const X_MAX := 574
const X_COUNT := 304
const Y_MIN := 3
const Y_MAX := 290
const Y_COUNT := 288
const PER_SCREEN := X_COUNT * Y_COUNT
const STATE_COUNT := SCREENS * PER_SCREEN
## Where the sub is when a sector starts and the player has control (`ExitSupplyStation` 0x4328b0: SubX 0 -> 96, SubY 202).
const LAUNCH := Vector3i(0, 96, 202)

const _STEPS_ORTHOGONAL: Array[int] = [2, 0, -2, 0, 0, 1, 0, -1]
const _STEPS_DIAGONAL: Array[int] = [2, 0, -2, 0, 0, 1, 0, -1, 2, 1, 2, -1, -2, 1, -2, -1]

var sector_index: int = -1
## The sub's wall box (`SubTuning.wall_box`) that the gap tables are made for; `build` needs it.
var wall_box := Rect2i()
## The longest move of one tick (`SubTuning.max_speed_*_units >> 3`, pixels): the big steps of `Mode.FAST`.
var max_step := Vector2i()
## Per screen: 684 bytes, 1 where the tile is solid (flag 0x40), row-major like the data.
var solid: Array[PackedByteArray] = []
## Per screen: current tile bytes' (0x80 flag) are kept as the raw tile byte for the report (0 = none).
var tiles: Array[PackedByteArray] = []
## Neighbour screen per side and screen, -1 for none: [left, right, up, down].
var neighbours: Array[PackedInt32Array] = []

# Gap tables. The horizontal gaps depend on y only through the rows the box covers, the vertical ones on x through the columns it
# covers, so each is computed once per "class" with `SubModel.wall_gap` itself.
var _row_class: PackedInt32Array = PackedInt32Array()       # per y index -> class of the covered row range
var _column_class: PackedInt32Array = PackedInt32Array()    # per x index -> class of the covered column range
var _row_class_count: int = 0
var _column_class_count: int = 0
var _gap_left: PackedInt32Array = PackedInt32Array()
var _gap_right: PackedInt32Array = PackedInt32Array()
var _gap_up: PackedInt32Array = PackedInt32Array()
var _gap_down: PackedInt32Array = PackedInt32Array()
var _built: bool = false
## Set to true before `explore` to also get `parents` (per state, the state it was first reached from; -1 for a seed).
var record_parents: bool = false
var parents: PackedInt32Array = PackedInt32Array()


## Copies the tile maps and neighbour tables out of the (shared, read-only) resource, so that a search can run on a thread. `sub` is
## the sub section of the rule values in use (its wall box and top speeds): the gap tables and the steps, and so a search, need it;
## the tile maps alone (`solid`) do not.
static func from_sector(sector: SectorData, sub: SubTuning = null) -> SectorReach:
	var reach := SectorReach.new()
	reach._take_sub(sub)
	reach.sector_index = sector.index
	for screen in sector.screens:
		reach.tiles.append(screen.tiles.duplicate())
	reach.neighbours = [
			sector.neighbors_left.duplicate(), sector.neighbors_right.duplicate(),
			sector.neighbors_up.duplicate(), sector.neighbors_down.duplicate()]
	reach._derive_solid()
	return reach


## For tests: tile bytes per screen (684 each) and four neighbour arrays, and the sub section of the rule values.
static func from_tiles(tile_screens: Array[PackedByteArray], side_neighbours: Array[PackedInt32Array], sub: SubTuning = null) -> SectorReach:
	var reach := SectorReach.new()
	reach._take_sub(sub)
	for t in tile_screens:
		reach.tiles.append(t)
	reach.neighbours = side_neighbours
	reach._derive_solid()
	return reach


func _derive_solid() -> void:
	solid.clear()
	for t in tiles:
		var s := PackedByteArray()
		s.resize(COLUMNS * ROWS)
		for i in t.size():
			s[i] = 1 if (t[i] & TileCodec.SOLID_BIT) != 0 else 0
		solid.append(s)


# --- indexing ---------------------------------------------------------------------------------------------------

static func state_index(screen: int, sub_x: int, sub_y: int) -> int:
	return screen * PER_SCREEN + (sub_y - Y_MIN) * X_COUNT + ((sub_x - X_MIN) >> 1)


static func state_screen(index: int) -> int:
	return index / PER_SCREEN


static func state_x(index: int) -> int:
	return ((index % PER_SCREEN) % X_COUNT) * 2 + X_MIN


static func state_y(index: int) -> int:
	return (index % PER_SCREEN) / X_COUNT + Y_MIN


# --- the gap tables -----------------------------------------------------------------------------------------------

## Fills the gap tables by calling `SubModel.wall_gap` (the real scan) once per distinct covered-rows / covered-columns class.
func build() -> void:
	if _built:
		return
	assert(wall_box.has_area(), "SectorReach.build: no wall box (give from_sector the sub section of the rule values in use)")
	_built = true
	# class of a y: the (first row, last row) the box covers, clamped like the scan does
	var row_ids := {}
	var row_rep: Array[int] = []
	_row_class.resize(Y_COUNT)
	for yi in Y_COUNT:
		var y := yi + Y_MIN
		var scan := SubModel.wall_scan_box(Vector2i(0, y), wall_box)
		var key := Vector2i(maxi(scan.position.y / 16, 0), mini((scan.end.y - 1) / 16, ROWS - 1))
		if not row_ids.has(key):
			row_ids[key] = row_rep.size()
			row_rep.append(y)
		_row_class[yi] = row_ids[key]
	var column_ids := {}
	var column_rep: Array[int] = []
	_column_class.resize(X_COUNT)
	for xi in X_COUNT:
		var x := xi * 2 + X_MIN
		var scan := SubModel.wall_scan_box(Vector2i(x, 0), wall_box)
		var key := Vector2i(maxi(scan.position.x / 16, 0), mini((scan.end.x - 1) / 16, COLUMNS - 1))
		if not column_ids.has(key):
			column_ids[key] = column_rep.size()
			column_rep.append(x)
		_column_class[xi] = column_ids[key]
	_row_class_count = row_rep.size()
	_column_class_count = column_rep.size()
	var screens := solid.size()
	_gap_left.resize(screens * _row_class_count * X_COUNT)
	_gap_right.resize(screens * _row_class_count * X_COUNT)
	_gap_up.resize(screens * _column_class_count * Y_COUNT)
	_gap_down.resize(screens * _column_class_count * Y_COUNT)
	for screen in screens:
		var cells := solid[screen]
		var is_solid := func(column: int, row: int) -> bool: return cells[row * COLUMNS + column] != 0
		for rc in _row_class_count:
			var base := (screen * _row_class_count + rc) * X_COUNT
			for xi in X_COUNT:
				var at := Vector2i(xi * 2 + X_MIN, row_rep[rc])
				_gap_left[base + xi] = SubModel.wall_gap(SubModel.WallSide.LEFT, at, is_solid, wall_box)
				_gap_right[base + xi] = SubModel.wall_gap(SubModel.WallSide.RIGHT, at, is_solid, wall_box)
		for cc in _column_class_count:
			var base := (screen * _column_class_count + cc) * Y_COUNT
			for yi in Y_COUNT:
				var at := Vector2i(column_rep[cc], yi + Y_MIN)
				_gap_up[base + yi] = SubModel.wall_gap(SubModel.WallSide.UP, at, is_solid, wall_box)
				_gap_down[base + yi] = SubModel.wall_gap(SubModel.WallSide.DOWN, at, is_solid, wall_box)


## The gap `SubModel.wall_gap` returns for `side` at (`screen`, `sub_x`, `sub_y`), from the tables.
func gap(side: SubModel.WallSide, screen: int, sub_x: int, sub_y: int) -> int:
	build()
	var xi := (sub_x - X_MIN) >> 1
	var yi := sub_y - Y_MIN
	match side:
		SubModel.WallSide.LEFT:
			return _gap_left[(screen * _row_class_count + _row_class[yi]) * X_COUNT + xi]
		SubModel.WallSide.RIGHT:
			return _gap_right[(screen * _row_class_count + _row_class[yi]) * X_COUNT + xi]
		SubModel.WallSide.UP:
			return _gap_up[(screen * _column_class_count + _column_class[xi]) * Y_COUNT + yi]
		_:
			return _gap_down[(screen * _column_class_count + _column_class[xi]) * Y_COUNT + yi]


# --- one move and the screen change after it -----------------------------------------------------------------------

## Where the sub is after one tick that tries to move it by (`dx`, `dy`) from the given state: the wall clamp of `DoAction`
## (each axis shortened to the scan's gap, both axes scanned from the start position), `SubX` forced even, then the screen change /
## edge clamp. Returns Vector3i(screen, x, y). Slow (for tests and for cross-checking `SubModel._move`); `explore` has the same logic inline.
func step(screen: int, sub_x: int, sub_y: int, dx: int, dy: int) -> Vector3i:
	var moved := move_only(screen, sub_x, sub_y, dx, dy)
	return after_move(screen, moved.x, moved.y)


## The position after the wall clamp and the evenness of SubX, before any screen change (what `SubModel._move` computes).
func move_only(screen: int, sub_x: int, sub_y: int, dx: int, dy: int) -> Vector2i:
	build()
	if dx < 0:
		var g := gap(SubModel.WallSide.LEFT, screen, sub_x, sub_y)
		if g < 1 and dx < g:
			dx = g
	elif dx > 0:
		var g := gap(SubModel.WallSide.RIGHT, screen, sub_x, sub_y)
		if g >= 0 and g < dx:
			dx = g
	if dy < 0:
		var g := gap(SubModel.WallSide.UP, screen, sub_x, sub_y)
		if g < 1 and dy < g:
			dy = g
	elif dy > 0:
		var g := gap(SubModel.WallSide.DOWN, screen, sub_x, sub_y)
		if g >= 0 and g < dy:
			dy = g
	return Vector2i((sub_x + dx) & ~1, sub_y + dy)


## The screen change / clamp rules of `DoAction` for a position that may be outside the grid.
func after_move(screen: int, new_x: int, new_y: int) -> Vector3i:
	if new_x < X_MIN:
		var n := neighbours[0][screen]
		if n >= 0:
			screen = n
			new_x = 572
		else:
			new_x = X_MIN
	elif new_x >= 576:
		var n := neighbours[1][screen]
		if n >= 0:
			screen = n
			new_x = X_MIN
		else:
			new_x = 572
	if new_y < Y_MIN:
		var n := neighbours[2][screen]
		if n >= 0:
			screen = n
			new_y = Y_MAX
		else:
			new_y = Y_MIN
	elif new_y > Y_MAX:
		var n := neighbours[3][screen]
		if n >= 0:
			screen = n
			new_y = Y_MIN
		else:
			new_y = Y_MAX
	return Vector3i(screen, new_x, new_y)


## What a search needs of the sub: its wall box and the longest move of one tick.
func _take_sub(sub: SubTuning) -> void:
	if sub == null:
		return
	wall_box = sub.wall_box
	max_step = Vector2i(sub.max_speed_x_units >> 3, sub.max_speed_y_units >> 3)


## The steps of `Mode.FAST`: the diagonal ones, then every move at top speed and at half of it (an axis may also stand still).
func _fast_steps() -> Array[int]:
	var steps: Array[int] = _STEPS_DIAGONAL.duplicate()
	for step in [max_step, max_step / 2]:
		for move: Vector2i in [Vector2i(step.x, 0), Vector2i(-step.x, 0), Vector2i(0, step.y), Vector2i(0, -step.y),
				Vector2i(step.x, step.y), Vector2i(step.x, -step.y), Vector2i(-step.x, step.y), Vector2i(-step.x, -step.y)]:
			steps.append_array([move.x, move.y])
	return steps


# --- the search ------------------------------------------------------------------------------------------------------

## Every state reachable from `seeds` (Vector3i(screen, SubX, SubY)). Returns one byte per state (`state_index`), 1 = reachable.
## `blocked` (optional, same layout): states the sub must not enter or leave (used to ask "what if this area were impassable?").
func explore(seeds: Array, mode: Mode = Mode.ORTHOGONAL, blocked: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	build()
	var steps: Array[int] = _STEPS_ORTHOGONAL
	if mode == Mode.DIAGONAL:
		steps = _STEPS_DIAGONAL
	elif mode == Mode.FAST:
		steps = _fast_steps()
	var step_count := steps.size() / 2
	var use_blocked := blocked.size() == STATE_COUNT
	var visited := PackedByteArray()
	visited.resize(STATE_COUNT)
	var queue := PackedInt32Array()
	queue.resize(STATE_COUNT)
	var head := 0
	var tail := 0
	if record_parents:
		parents.resize(STATE_COUNT)
	for seed_state: Vector3i in seeds:
		var s := state_index(seed_state.x, seed_state.y, seed_state.z)
		if visited[s] == 0 and not (use_blocked and blocked[s] != 0):
			visited[s] = 1
			if record_parents:
				parents[s] = -1
			queue[tail] = s
			tail += 1
	var screens := solid.size()
	var left_neighbour: PackedInt32Array = neighbours[0]
	var right_neighbour: PackedInt32Array = neighbours[1]
	var up_neighbour: PackedInt32Array = neighbours[2]
	var down_neighbour: PackedInt32Array = neighbours[3]
	var row_count := _row_class_count
	var column_count := _column_class_count
	while head < tail:
		var state := queue[head]
		head += 1
		var screen := state / PER_SCREEN
		var within := state - screen * PER_SCREEN
		var yi := within / X_COUNT
		var xi := within - yi * X_COUNT
		var sub_x := xi * 2 + X_MIN
		var sub_y := yi + Y_MIN
		var horizontal_base := (screen * row_count + _row_class[yi]) * X_COUNT + xi
		var vertical_base := (screen * column_count + _column_class[xi]) * Y_COUNT + yi
		var gap_left := _gap_left[horizontal_base]
		var gap_right := _gap_right[horizontal_base]
		var gap_up := _gap_up[vertical_base]
		var gap_down := _gap_down[vertical_base]
		for k in step_count:
			var dx := steps[k * 2]
			var dy := steps[k * 2 + 1]
			if dx < 0:
				if gap_left < 1 and dx < gap_left:
					dx = gap_left
			elif dx > 0:
				if gap_right >= 0 and gap_right < dx:
					dx = gap_right
			if dy < 0:
				if gap_up < 1 and dy < gap_up:
					dy = gap_up
			elif dy > 0:
				if gap_down >= 0 and gap_down < dy:
					dy = gap_down
			var new_screen := screen
			var new_x := (sub_x + dx) & ~1
			var new_y := sub_y + dy
			if new_x < X_MIN:
				var n := left_neighbour[new_screen]
				if n >= 0:
					new_screen = n
					new_x = 572
				else:
					new_x = X_MIN
			elif new_x >= 576:
				var n := right_neighbour[new_screen]
				if n >= 0:
					new_screen = n
					new_x = X_MIN
				else:
					new_x = 572
			if new_y < Y_MIN:
				var n := up_neighbour[new_screen]
				if n >= 0:
					new_screen = n
					new_y = Y_MAX
				else:
					new_y = Y_MIN
			elif new_y > Y_MAX:
				var n := down_neighbour[new_screen]
				if n >= 0:
					new_screen = n
					new_y = Y_MIN
				else:
					new_y = Y_MAX
			if new_screen >= screens:
				continue
			var target := new_screen * PER_SCREEN + (new_y - Y_MIN) * X_COUNT + ((new_x - X_MIN) >> 1)
			if visited[target] != 0 or (use_blocked and blocked[target] != 0):
				continue
			visited[target] = 1
			if record_parents:
				parents[target] = state
			queue[tail] = target
			tail += 1
	return visited


## The chain of states from a seed to `target_state` (inclusive), from the `parents` of the last `explore` with `record_parents`.
func path_to(target_state: int) -> PackedInt32Array:
	var path := PackedInt32Array()
	var at := target_state
	while at >= 0:
		path.append(at)
		at = parents[at]
	path.reverse()
	return path


# --- questions about a result ----------------------------------------------------------------------------------------

## The states of `visited` on `screen` where SubX is in [`x_from`, `x_to`] and SubY in [`y_from`, `y_to`] (inclusive); the first one is
## returned as Vector3i(screen, x, y), or Vector3i(-1, 0, 0) when there is none.
static func first_state_in(visited: PackedByteArray, screen: int, x_from: int, x_to: int, y_from: int, y_to: int) -> Vector3i:
	x_from = maxi(x_from + (x_from & 1), X_MIN)       # SubX is even
	x_to = mini(x_to, X_MAX)
	y_from = maxi(y_from, Y_MIN)
	y_to = mini(y_to, Y_MAX)
	for y in range(y_from, y_to + 1):
		var row := screen * PER_SCREEN + (y - Y_MIN) * X_COUNT
		for x in range(x_from, x_to + 1, 2):
			if visited[row + ((x - X_MIN) >> 1)] != 0:
				return Vector3i(screen, x, y)
	return Vector3i(-1, 0, 0)


## How many states of `visited` lie in the same box `first_state_in` searches (a measure of how easy a contact is to make).
static func count_states_in(visited: PackedByteArray, screen: int, x_from: int, x_to: int, y_from: int, y_to: int) -> int:
	x_from = maxi(x_from + (x_from & 1), X_MIN)
	x_to = mini(x_to, X_MAX)
	y_from = maxi(y_from, Y_MIN)
	y_to = mini(y_to, Y_MAX)
	var n := 0
	for y in range(y_from, y_to + 1):
		var row := screen * PER_SCREEN + (y - Y_MIN) * X_COUNT
		for x in range(x_from, x_to + 1, 2):
			n += visited[row + ((x - X_MIN) >> 1)]
	return n


## The original's pick-up test (`CheckProbeCollision` 0x42dbb2): the sub's WHOLE picture box (SubX..SubX+95, SubY..SubY+57) against the
## piece's 24 x 20 box at (`piece_x`, `piece_y`), both edges inclusive. The cell of the sub plays no part.
static func first_pickup_original(visited: PackedByteArray, screen: int, piece_x: int, piece_y: int) -> Vector3i:
	return first_state_in(visited, screen, piece_x - 95, piece_x + 23, piece_y - 57, piece_y + 19)


## The port's pick-up test. It used to be the per-cell `Hurtbox` Area2D against the piece's Area2D (a smaller rectangle, a finding of the
## first sweep); the port now takes pieces exactly like the original (`PieceModel.touched_by`), so `cell_rect` no longer matters.
## Returns the first reachable state, or Vector3i(-1, 0, 0).
static func first_pickup_port(visited: PackedByteArray, screen: int, piece_x: int, piece_y: int, _cell_rect: Rect2i) -> Vector3i:
	return first_pickup_original(visited, screen, piece_x, piece_y)


## Does the sub's rectangle (`cell_rect` = (left, top, width, height) from the top-left of the picture; edges inclusive like
## `FoeModel.rects_touch`) touch `target` (window pixels) in this reachable set? Returns the first state or Vector3i(-1, 0, 0).
static func first_touch(visited: PackedByteArray, screen: int, target: Rect2i, cell_rect: Rect2i) -> Vector3i:
	var x_from := target.position.x - cell_rect.position.x - cell_rect.size.x
	var x_to := target.end.x - cell_rect.position.x
	var y_from := target.position.y - cell_rect.position.y - cell_rect.size.y
	var y_to := target.end.y - cell_rect.position.y
	return first_state_in(visited, screen, x_from, x_to, y_from, y_to)


## True when any state of `visited` lies on `screen`.
static func any_on_screen(visited: PackedByteArray, screen: int) -> bool:
	var base := screen * PER_SCREEN
	for i in range(base, base + PER_SCREEN):
		if visited[i] != 0:
			return true
	return false


## How many states are marked.
static func count(visited: PackedByteArray) -> int:
	var n := 0
	for b in visited:
		n += b
	return n
