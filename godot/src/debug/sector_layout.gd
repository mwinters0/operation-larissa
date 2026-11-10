class_name SectorLayout
extends RefCounted
## Puts the 12 screens of a sector on a grid, the way the neighbour tables say they are joined, and says plainly where the
## tables do not fit on a grid.
##
## Teaches: laying out a graph that is only SUPPOSED to be a map. The sector header keeps four tables (left, right, up, down:
## for each screen the screen you reach through that side, DESIGN 4.1). Nothing forces them to agree: a screen may lead to
## a neighbour that does not lead back (a one-way link), two screens may claim the same cell, a level may wrap around, and
## a screen may lead to itself. The game does not mind (`SectorReach.after_move` just follows the table), but a picture
## on a grid does. So the layout is a breadth-first search from the start screen that PLACES what it can and then CHECKS
## every link against the result, instead of hiding what does not fit. Nothing is dropped: a screen that no link
## reaches is put in a group of its own below the main map (`detached`), and a link that is not between two neighbouring
## cells is listed (`conflicts`) so that a view can draw it as an explicit arrow.
##
## Plain data in, plain data out (no nodes, no `SectorData` needed), so it is tested headlessly over all 32 original sectors
## (`tests/engine/test_sector_overview.gd`) and reused by `SectorOverview`.
##
## THE SEARCH. Starting at the start screen (cell (0, 0)) the screens are taken in the order they are found; for the screen
## taken, each side in the order left, right, up, down places (1) the screen that side LEADS to, one cell over, and (2) every
## screen whose table leads INTO this one through the opposite side, one cell back (a one-way link still tells where a
## screen probably is). A cell that is taken is not used twice. A screen that nothing connects to the rest starts a group of
## its own, put below the main map (the next one to the right of that).
##
## THE CHECK. Every entry of the four tables is then a link with a verdict (`Kind`):
##   OK        the target is one cell over in the direction of the side, and leads back through the opposite side
##   ONE_WAY   it is placed right, but its opposite side does not lead back (the game allows it; sector 7 has two)
##   MISPLACED the target sits somewhere else: the table wraps around, or two links want different cells
##   SELF      a screen leads to itself
##   INVALID   a number that is no screen of the sector

enum Kind { OK, ONE_WAY, MISPLACED, SELF, INVALID }

## The sides, in the order of the tables (`SectorData.Direction`): left, right, up, down. The cell step of leaving through a side.
const STEPS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const SIDE_NAMES: Array[String] = ["left", "right", "up", "down"]
## The side one arrives through when leaving through side k.
const OPPOSITE: Array[int] = [1, 0, 3, 2]

## The four neighbour tables, [left, right, up, down], each one destination (or -1) per screen.
var neighbours: Array[PackedInt32Array] = []
var screen_count: int = 0
## Screen -> its cell (Vector2i, column and row; the start screen is (0, 0), rows grow downward). Holds every screen.
var cell_of: Dictionary = {}
## Cell -> screen. The inverse of `cell_of`.
var screen_at: Dictionary = {}
## Screen -> group number: 0 for the map that grows out of the start screen, 1, 2 ... for the groups nothing leads to.
var group_of: PackedInt32Array = PackedInt32Array()
## Every link of the tables that leads somewhere: dictionaries {screen, side, target, kind, text} (`Kind`), in table order
## (screen by screen, left, right, up, down).
var links: Array[Dictionary] = []
## The cells' bounding box, (position, size) in cells.
var bounds: Rect2i = Rect2i()


## The layout of the sector `sector` from its start screen (0, where the sub leaves the supply station).
static func from_sector(sector: SectorData, start: int = 0) -> SectorLayout:
	return compute([sector.neighbors_left, sector.neighbors_right, sector.neighbors_up, sector.neighbors_down], start)


## The layout for four neighbour tables ([left, right, up, down], entries -1 for none), starting at screen `start`.
static func compute(tables: Array, start: int = 0) -> SectorLayout:
	var layout := SectorLayout.new()
	for table: PackedInt32Array in tables:
		layout.neighbours.append(table)
	layout.screen_count = layout.neighbours[0].size()
	layout.group_of.resize(layout.screen_count)
	var group := 0
	var next_origin := Vector2i.ZERO
	var root := clampi(start, 0, maxi(layout.screen_count - 1, 0))
	while root >= 0:
		var found := layout._grow(root)
		var box := found.get_bounds()
		# the main map keeps its cells (the start screen at (0, 0)); a group is moved so that its top-left corner is at `next_origin`
		var shift := next_origin - box.position if group > 0 else Vector2i.ZERO
		for screen: int in found.screens:
			var cell: Vector2i = found.cells[screen] + shift
			layout.cell_of[screen] = cell
			layout.screen_at[cell] = screen
			layout.group_of[screen] = group
		var used := Rect2i(box.position + shift, box.size)
		layout.bounds = used if group == 0 else layout.bounds.merge(used)
		# the first group below the main map goes one empty row under it; the next ones go to the right of the one before
		next_origin = Vector2i(layout.bounds.position.x, layout.bounds.end.y + 1) if group == 0 else Vector2i(used.end.x + 1, next_origin.y)
		group += 1
		root = -1
		for screen in layout.screen_count:
			if not layout.cell_of.has(screen):
				root = screen
				break
	layout._check_links()
	return layout


# --- the search --------------------------------------------------------------------------------------------------

## One group: the screens reached from `root` and the cells they were given (the root at (0, 0)). Two-way links are followed
## first, all of them; only when none is left does ONE one-way link (or a link into a placed screen) place one more screen, and
## the two-way links of that screen are followed again. So a one-way link, which says less about where a screen is, never
## beats a two-way one for a cell.
func _grow(root: int) -> _Group:
	var group := _Group.new()
	group.add(root, Vector2i.ZERO)
	var queue: Array[int] = [root]
	var head := 0
	while true:
		while head < queue.size():
			_follow_two_way_links(group, queue[head], queue)
			head += 1
		var added := false
		for screen in group.screens:
			if _follow_one_way_link(group, screen, queue):
				added = true
				break
		if not added:
			return group
	return group


## Places the screens that `screen` leads to AND that lead back, one cell over.
func _follow_two_way_links(group: _Group, screen: int, queue: Array[int]) -> void:
	var here: Vector2i = group.cells[screen]
	for side in 4:
		var target := neighbours[side][screen]
		if _is_screen(target) and neighbours[OPPOSITE[side]][target] == screen and not group.cells.has(target) and not _placed(target):
			if group.try_place(target, here + STEPS[side]):
				queue.append(target)


## Places ONE more screen next to `screen`: one it leads to, or one that leads to it (through the opposite side), that has no
## cell yet. True if there was one.
func _follow_one_way_link(group: _Group, screen: int, queue: Array[int]) -> bool:
	var here: Vector2i = group.cells[screen]
	for side in 4:
		var target := neighbours[side][screen]
		if _is_screen(target) and not group.cells.has(target) and not _placed(target) and group.try_place(target, here + STEPS[side]):
			queue.append(target)
			return true
		for other in screen_count:
			if neighbours[OPPOSITE[side]][other] == screen and not group.cells.has(other) and not _placed(other) \
					and group.try_place(other, here - STEPS[OPPOSITE[side]]):
				queue.append(other)
				return true
	return false


## The cells a group has handed out, without the clumsiness of nested dictionaries.
class _Group extends RefCounted:
	var cells: Dictionary = {}        ## screen -> cell
	var taken: Dictionary = {}        ## cell -> screen
	var screens: Array[int] = []

	func add(screen: int, cell: Vector2i) -> void:
		cells[screen] = cell
		taken[cell] = screen
		screens.append(screen)

	func try_place(screen: int, cell: Vector2i) -> bool:
		if taken.has(cell):
			return false
		add(screen, cell)
		return true

	func get_bounds() -> Rect2i:
		var low := Vector2i(1 << 30, 1 << 30)
		var high := Vector2i(-(1 << 30), -(1 << 30))
		for cell: Vector2i in cells.values():
			low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
			high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
		return Rect2i(low, high - low + Vector2i.ONE)


func _is_screen(number: int) -> bool:
	return number >= 0 and number < screen_count


## Placed by an earlier group of this layout (a screen in the group that is growing now is checked by the group itself).
func _placed(screen: int) -> bool:
	return cell_of.has(screen)


# --- the check ---------------------------------------------------------------------------------------------------

func _check_links() -> void:
	links.clear()
	for screen in screen_count:
		for side in 4:
			var target := neighbours[side][screen]
			if target < 0:
				continue
			links.append(_verdict(screen, side, target))


func _verdict(screen: int, side: int, target: int) -> Dictionary:
	var link := {"screen": screen, "side": side, "target": target, "kind": Kind.OK, "text": ""}
	var name := SIDE_NAMES[side]
	if target >= screen_count:
		link["kind"] = Kind.INVALID
		link["text"] = "screen %d, %s: %d is not a screen of the sector" % [screen, name, target]
	elif target == screen:
		link["kind"] = Kind.SELF
		link["text"] = "screen %d leads to itself through its %s side" % [screen, name]
	elif cell_of[target] != cell_of[screen] + STEPS[side]:
		link["kind"] = Kind.MISPLACED
		var wanted: Vector2i = cell_of[screen] + STEPS[side]
		var holder := ""
		if screen_at.has(wanted) and screen_at[wanted] != target:
			holder = ", where screen %d sits" % screen_at[wanted]
		link["text"] = "screen %d, %s -> screen %d, but screen %d is at %s, not at the neighbouring cell %s%s" % [
				screen, name, target, target, cell_of[target], wanted, holder]
	elif neighbours[OPPOSITE[side]][target] != screen:
		link["kind"] = Kind.ONE_WAY
		var back := neighbours[OPPOSITE[side]][target]
		link["text"] = "screen %d, %s -> %d, but %d, %s -> %d" % [screen, name, target, target, SIDE_NAMES[OPPOSITE[side]], back]
	return link


# --- questions about the result ----------------------------------------------------------------------------------

## The links that do not fit on the grid (MISPLACED, SELF, INVALID): what a view draws as explicit arrows.
func conflicts() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for link in links:
		if link["kind"] in [Kind.MISPLACED, Kind.SELF, Kind.INVALID]:
			found.append(link)
	return found


## The links between neighbouring cells that do not lead back.
func one_way_links() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for link in links:
		if link["kind"] == Kind.ONE_WAY:
			found.append(link)
	return found


## The screens that nothing connects to the start screen's map, in order.
func detached() -> Array[int]:
	var found: Array[int] = []
	for screen in screen_count:
		if group_of[screen] > 0:
			found.append(screen)
	return found


## Is the link through `side` of `screen` drawn between neighbouring cells (OK or ONE_WAY)?
func is_adjacent(screen: int, side: int) -> bool:
	var target := neighbours[side][screen]
	return _is_screen(target) and target != screen and cell_of[target] == cell_of[screen] + STEPS[side]


## One line per finding, empty when the tables form a clean map. For reports and the overview's status line.
func report() -> PackedStringArray:
	var lines := PackedStringArray()
	for screen in detached():
		lines.append("screen %d is not connected to the start screen by any link (placed apart, group %d)" % [screen, group_of[screen]])
	for link in conflicts():
		lines.append(link["text"])
	for link in one_way_links():
		lines.append("one-way link: " + link["text"])
	return lines
