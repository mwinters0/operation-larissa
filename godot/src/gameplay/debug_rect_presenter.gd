class_name DebugRectPresenter
extends SectorPresenter
## The "debug rectangles" presenter: the same sector as the original one, drawn from the rules with nothing but rectangles, lines
## and text. No pictures, no tiles, no scenes, no child nodes: one `_draw()`.
##
## Teaches: how little a presenter needs. It is given a `SimWorld` (`bind`), asks it what is where, and draws that; the rules do not
## know it exists, so the game plays exactly as with the original look (`tests/engine/test_plays_identically.gd` proves it). It is also what
## you want when you author a skin: these are the rectangles the rules really test, so a picture that does not cover
## its rectangle is the picture's fault, not the rules'.
##
## WHAT IS DRAWN (playfield pixels; the rules' window pixels minus `SubModel.PLAYFIELD_ORIGIN`):
##   grey blocks       the walls of `sim.tile_grid` (one block per run of wall tiles in a row), and the water currents as little arrows
##   red outline       the sub's hurt rectangle, `sim.sub.hurt_rect_window()`; creatures touch the sub when theirs overlap it
##   cyan outline      the sub's wall box (`SubTuning.wall_box`), the one the walls are tested against
##   orange outlines   the hit rectangles of the creatures that can be touched (`FoeModel.hit_rect_window()`), numbered
##   green outlines    ink pellets (`PelletModel.window_rect()`), blue while they splash
##   yellow outlines   the pieces still lying around (`PieceModel`), the data canister in white
##   crosses           the math triggers of this screen (`TriggerModel.data.pos`), with their slot; grey once they have fired
##   purple outline    the dock: where the corner of the sub's picture must be to dock (`SimWorld.DOCK_*`), on the last screen
##   text              the trip at the supply station (door picture, balloon) and the dissolve, "n of N ticks"
## The sub and the pellets glide between ticks (`TickSmoothing`, the fraction `show_between_ticks` is given); the rest is drawn where
## the last tick left it.
##
## USE IT: `SectorWorld.replace_presenter(DebugRectPresenter.new())`, or start the game with `-- --presenter=debug_rects`, or press R
## in the F3 debug keys (`PresenterChoice`). As an OVERLAY over another presenter (a skin being authored): `SectorWorld.set_overlay(true)`
## (key O in the sector viewer, F3 then O in the game, `-- --overlay` on the command line), or by hand: `DebugRectPresenter.overlay(parent, sim)`
## adds one as a child of the playfield with `backdrop = false`, so it only draws outlines, bound to the same `SimWorld`; the side-by-side tool
## (`src/debug/skin_compare.tscn`) lays one over each half.
##
## It reads the rules directly (`sim`), like `OriginalPresenter`: it is part of the game and the tools, not a skin. What a skin's OWN overlay needs
## is in the skin API: `view.sub().hurt_rect` and `wall_rect`, `creature.hit_rect`, `view.is_solid` / `current_at` for the tiles.
##
## It shows no keys of the sector viewer (`show_debug`): everything is always on, that is the point of it.

## How opaque the filled boxes (the walls) are when this is an overlay (`backdrop` off), so the skin's picture shows through them.
const OVERLAY_FILL_ALPHA := 0.4

## Fill the playfield with a dark background. Off: only the outlines are drawn (an overlay).
var backdrop: bool = true

## What is drawn, tagged by kind so a test can ask for "the creatures". `filled` boxes are solid, the others outlines.
class Box:
	extends RefCounted
	var kind: StringName
	var rect: Rect2
	var color: Color
	var filled: bool
	var label: String

	func _init(box_kind: StringName, box_rect: Rect2, box_color: Color, box_filled: bool = false, box_label: String = "") -> void:
		kind = box_kind
		rect = box_rect
		color = box_color
		filled = box_filled
		label = box_label

## How far into the tick we are (`show_between_ticks`).
var _fraction: float = 1.0
## The boxes that only change with the screen: walls, currents, the dock. Built when a screen is laid out.
var _still: Array[Box] = []


## A debug-rectangles overlay over whatever `parent` shows: no backdrop, added as the last child (drawn above the others) and bound to `sim_world`.
## `parent` must be in the tree. The owner passes the tick fraction to it like to any presenter (`show_between_ticks`).
static func overlay(parent: Node, sim_world: SimWorld) -> DebugRectPresenter:
	var rects := DebugRectPresenter.new()
	rects.name = "RectOverlay"
	rects.backdrop = false
	parent.add_child(rects)
	rects.bind(sim_world)
	return rects


func bind(sim_world: SimWorld) -> void:
	super.bind(sim_world)
	_listen(sim.screen_loaded, func(_sector: int, _screen: int) -> void: refresh())
	_listen(sim.ticked, queue_redraw)
	_listen(sim.pieces_reset, queue_redraw)
	_listen(sim.dissolve_advanced, queue_redraw.unbind(1))                    # (these two tell us a number / a trip we do not need)
	_listen(sim.sequence_started, queue_redraw.unbind(1))
	refresh()


## Stops answering the sim, and draws nothing from now on.
func unbind() -> void:
	super.unbind()
	_still.clear()
	queue_redraw()


## Lays the still boxes out again from the rules' grid (walls and currents) and draws.
func refresh() -> void:
	_still.clear()
	if sim != null and sim.sector != null:
		_collect_still()
	queue_redraw()


func show_between_ticks(fraction: float) -> void:
	_fraction = fraction
	queue_redraw()


# --- what there is to draw -------------------------------------------------------------------

## Every box now: the still ones and then the sub, creatures, pellets, pieces, triggers and the supply trip, in that order.
func boxes() -> Array[Box]:
	var found: Array[Box] = _still.duplicate()
	if sim == null or sim.sector == null:
		return found
	var sub := sim.sub
	if sub.active:
		var glide := TickSmoothing.offset(sub.previous_position, sub.position, _fraction)
		var alpha := 1.0 if not sim.is_dissolving() else 1.0 - float(sim.dissolve_elapsed) / sim.dissolve_ticks
		found.append(Box.new(&"sub_hurt", _rect(sub.hurt_rect_window(), glide), Color(1, 0.25, 0.25, alpha), false, "cell %d" % sub.cell))
		found.append(Box.new(&"sub_walls", _rect(Rect2i(sub.tuning.wall_box.position + sub.original_position(), sub.tuning.wall_box.size), glide),
				Color(0.2, 1, 1, alpha)))
	for foe in sim.foes:
		if foe.is_touchable():
			found.append(Box.new(&"creature", _rect(foe.hit_rect_window()), Color(1, 0.6, 0.1), false, str(foe.vm.index)))
	for pellet in sim.pellets:
		var glide := TickSmoothing.offset(pellet.previous_position, pellet.position, _fraction)
		found.append(Box.new(&"pellet", _rect(pellet.window_rect(), glide), Color(0.3, 1, 0.3) if pellet.is_flying() else Color(0.4, 0.5, 1)))
	for piece in sim.pieces:
		found.append(Box.new(&"piece", _rect(Rect2i(piece.position(), PieceModel.PICTURE_SIZE)), Color.WHITE if piece.is_canister() else Color(1, 1, 0.2),
				false, str(piece.index)))
	for trigger in sim.triggers_on_screen(sim.screen_index):
		found.append(Box.new(&"trigger", _rect(Rect2i(trigger.data.pos - Vector2i(4, 4), Vector2i(8, 8))),
				Color(1, 0.8, 0.2) if trigger.armed else Color(0.5, 0.5, 0.5), false, str(trigger.data.slot)))
	if sim.sequence != null and not sim.sequence.is_done():
		found.append_array(_trip_boxes(sim.sequence))
	return found


func _collect_still() -> void:
	var grid := sim.tile_grid
	for row in TileGrid.ROWS:
		var run_start := -1
		for column in TileGrid.COLUMNS + 1:                                    # (one past the end closes the last run)
			var solid := column < TileGrid.COLUMNS and grid.is_solid(column, row)
			if solid and run_start < 0:
				run_start = column
			elif not solid and run_start >= 0:
				_still.append(Box.new(&"wall", Rect2(Vector2(run_start, row) * TileGrid.TILE_SIZE,
						Vector2(column - run_start, 1) * TileGrid.TILE_SIZE), Color(0.35, 0.35, 0.4), true))
				run_start = -1
			if column < TileGrid.COLUMNS and not solid and grid.current_at(column, row) != Vector2i.ZERO:
				var middle := (Vector2(column, row) + Vector2(0.5, 0.5)) * TileGrid.TILE_SIZE
				var along := Vector2(grid.current_at(column, row)).normalized() * 6.0
				# (an arrow is kept as the Rect2 from its tail to its head, `_draw` draws the line between the two corners)
				_still.append(Box.new(&"current", Rect2(middle - along, along * 2.0), Color(0.3, 0.6, 1, 0.8)))
	if sim.screen_index == SimWorld.DOCK_SCREEN:
		_still.append(Box.new(&"dock", _rect(Rect2i(SimWorld.DOCK_MIN_X, SimWorld.DOCK_MIN_Y, 624 - SimWorld.DOCK_MIN_X,
				SimWorld.DOCK_MAX_Y - SimWorld.DOCK_MIN_Y)), Color(0.8, 0.4, 1), false, "dock"))


## The supply trip in progress: a box for the door (its picture number as the label) and, for the balloon, for the balloon.
func _trip_boxes(trip: StationSequence) -> Array[Box]:
	var found: Array[Box] = []
	if trip.is_drive():
		var door_x := 84 if trip.kind == StationSequence.Kind.LAUNCH else 448
		found.append(Box.new(&"door", _rect(Rect2i(door_x, StationSequence.DRIVE_Y, 16, 58)), Color(0.8, 0.4, 1), false,
				"door %d  %d of %d" % [trip.door_picture(), trip.elapsed, trip.ticks]))
	else:
		found.append(Box.new(&"balloon", _rect(Rect2i(trip.balloon_x, trip.balloon_y(), 48, 64)), Color(0.8, 0.4, 1), false,
				"balloon  %d of %d" % [trip.elapsed, trip.ticks]))
	return found


## A rectangle of the rules (window pixels) in playfield pixels, shifted by `glide`.
func _rect(window_rect: Rect2i, glide: Vector2 = Vector2.ZERO) -> Rect2:
	return Rect2(Vector2(window_rect.position) - SubModel.PLAYFIELD_ORIGIN + glide, window_rect.size)


# --- drawing ---------------------------------------------------------------------------------

func _draw() -> void:
	if backdrop:
		draw_rect(Rect2(Vector2.ZERO, Vector2(TileGrid.PLAYFIELD_SIZE)), Color(0.04, 0.06, 0.12))
	var font := ThemeDB.fallback_font
	for box in boxes():
		if box.kind == &"current":
			draw_line(box.rect.position, box.rect.end, box.color, 1.0)
			draw_circle(box.rect.end, 1.5, box.color)
			continue
		if box.filled:
			# (as an overlay the walls are see-through: the picture under them is what is being checked)
			draw_rect(box.rect, box.color if backdrop else Color(box.color, OVERLAY_FILL_ALPHA))
		else:
			draw_rect(box.rect, box.color, false)
		if not box.label.is_empty():
			draw_string(font, box.rect.position + Vector2(2, -2), box.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, box.color)
	if sim != null and sim.is_dissolving():
		draw_string(font, Vector2(8, 12), "dissolve %d of %d" % [sim.dissolve_elapsed, sim.dissolve_ticks], HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
