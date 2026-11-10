@tool
class_name SectorOverviewCanvas
extends Control
## Draws the sector map of `SectorOverviewModel`: the 12 screens small, each with its walls, and on top whatever the overlays ask for.
## Clicking is answered with signals; deciding what a click MEANS (open the screen editor, zoom in, show a text) is the host's job.
##
## Teaches: a custom `Control` that draws everything itself in `_draw` (`draw_texture_rect_region`, `draw_polyline`, `draw_string`)
## instead of owning a node per thing: a map of twelve screens with hundreds of tiles each is a picture, not a scene. The same
## data is drawn at any zoom by multiplying one number, and the same `object_at` of the model is used for drawing's order and
## for picking, so what you click is what was drawn on top. `_gui_input` (clicks and the wheel), `_get_tooltip` (hover text),
## `custom_minimum_size` (so that a `ScrollContainer` knows how far to scroll) and `queue_redraw` (draw again, only when something changed).
##
## The checks overlay (`SectorOverviewChecks`, the findings of `SectorChecks`) rings every object a finding is about (red: error, amber:
## warning, blue-grey: a remark, grey and dashed: allowed because the original is like this), frames the screen of a finding that is
## about the screen as a whole and puts a count on the corner of every screen that has findings. The "changed" overlay frames the
## screens that differ from the original in amber. Both only draw what the host gives them in `checks`.
##
## Where the layout is not a clean map (`SectorLayout`): links that do not join neighbouring cells are drawn as red arrows from the
## side they leave through to the side they arrive at, a screen led to itself by a small red loop, one-way links as amber arrows,
## and screens nothing leads to stand apart in a row below the map with a dashed frame.
##
## @tool: it also runs inside the editor (the `sector_overview` addon). There the pictures come straight from the files (the
## original look), because the skin machinery is for the running game.

signal screen_selected(screen: int)
signal screen_open_requested(screen: int)
## An object of the model was clicked; an empty dictionary when a click found none.
signal object_picked(object: Dictionary)
signal zoom_changed(zoom: float)

## What can be shown on top of the screens. The walls are always drawn.
enum Overlay { PIECES, CREATURES, TRIGGERS, CURRENTS, PLACES, REACHABILITY, PATHS, CHECKS, CHANGES }

const MIN_ZOOM := 0.1
const MAX_ZOOM := 1.0
## Pixels between two neighbouring screens (room for the links) and above each screen (its title).
const GAP := 26.0
const TITLE_HEIGHT := 16.0
const MARGIN := 12.0

const COLOR_BACKGROUND := Color(0.07, 0.08, 0.1)
const COLOR_WATER := Color(0.1, 0.2, 0.35)
const COLOR_WALL := Color(0.45, 0.4, 0.3)
const COLOR_CURRENT := Color(0.3, 0.8, 1.0)
const COLOR_FRAME := Color(0.5, 0.55, 0.6)
const COLOR_SELECTED := Color(1.0, 0.9, 0.3)
const COLOR_CONFLICT := Color(1.0, 0.25, 0.25)
const COLOR_ONE_WAY := Color(1.0, 0.7, 0.2)
const COLOR_LINK := Color(0.45, 0.5, 0.55)
const COLOR_PIECE := Color(1.0, 0.8, 0.2)
const COLOR_CANISTER := Color(0.3, 1.0, 1.0)
const COLOR_TRIGGER := Color(1.0, 0.3, 0.9)
const COLOR_START := Color(0.4, 1.0, 0.4)
const COLOR_DOCK := Color(0.4, 0.7, 1.0)
const COLOR_FINALE := Color(1.0, 0.6, 0.2)
const COLOR_UNREACHED := Color(1.0, 0.1, 0.1, 0.22)
const COLOR_ERROR := Color(1.0, 0.25, 0.25)
const COLOR_WARNING := Color(1.0, 0.7, 0.2)
const COLOR_REMARK := Color(0.55, 0.7, 0.95)
const COLOR_ALLOWED := Color(0.62, 0.65, 0.68)
const COLOR_CHANGED := Color(0.95, 0.6, 0.15)

var model: SectorOverviewModel:
	set(value):
		model = value
		_mask_textures.clear()
		selected_screen = -1
		selected_object = {}
		checks = null
		selected_finding = null
		_update_size()
		queue_redraw()
## Pixels of the picture per playfield pixel.
var zoom: float = 0.25:
	set(value):
		zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
		_update_size()
		queue_redraw()
var selected_screen: int = -1:
	set(value):
		selected_screen = value
		queue_redraw()
var selected_object: Dictionary = {}:
	set(value):
		selected_object = value
		queue_redraw()
## What the checks and the comparison with the original found, or null (then the overlays draw nothing).
var checks: SectorOverviewChecks:
	set(value):
		checks = value
		queue_redraw()
## The finding picked in the list beside the map: its mark is drawn with a thick yellow ring.
var selected_finding: CheckFinding:
	set(value):
		selected_finding = value
		queue_redraw()

var _shown: Dictionary = {
	Overlay.PIECES: true, Overlay.CREATURES: true, Overlay.TRIGGERS: true, Overlay.CURRENTS: false,
	Overlay.PLACES: true, Overlay.REACHABILITY: false, Overlay.PATHS: false, Overlay.CHECKS: false, Overlay.CHANGES: false}
var _mask_textures: Dictionary = {}      # screen -> ImageTexture of the reachability mask


# --- what is shown ------------------------------------------------------------------------------------------------------

func show_overlay(overlay: Overlay, on: bool) -> void:
	_shown[overlay] = on
	if overlay == Overlay.REACHABILITY:
		_mask_textures.clear()
	queue_redraw()


func is_overlay_shown(overlay: Overlay) -> bool:
	return _shown.get(overlay, false)


## The reachability mode or the settings of the traces changed in the model: forget what was made from the old ones.
func settings_changed() -> void:
	_mask_textures.clear()
	queue_redraw()


# --- where things are ----------------------------------------------------------------------------------------------------

func cell_size() -> Vector2:
	return Vector2(TileGrid.PLAYFIELD_SIZE) * zoom


## The top-left corner of `screen`'s picture in this control's pixels.
func origin_of(screen: int) -> Vector2:
	var cell: Vector2i = model.layout.cell_of[screen] - model.layout.bounds.position
	var pitch := cell_size() + Vector2(GAP, GAP + TITLE_HEIGHT)
	return Vector2(MARGIN, MARGIN + TITLE_HEIGHT) + Vector2(cell) * pitch


func screen_rect(screen: int) -> Rect2:
	return Rect2(origin_of(screen), cell_size())


## The screen whose picture is at `point` (this control's pixels), or -1.
func screen_at(point: Vector2) -> int:
	if model == null:
		return -1
	for screen in SectorData.SCREEN_COUNT:
		if screen_rect(screen).has_point(point):
			return screen
	return -1


## The playfield pixel of `point` on `screen`.
func playfield_point(screen: int, point: Vector2) -> Vector2:
	return (point - origin_of(screen)) / zoom


## The size the whole map needs.
func map_size(at_zoom: float) -> Vector2:
	if model == null:
		return Vector2.ZERO
	var pitch := Vector2(TileGrid.PLAYFIELD_SIZE) * at_zoom + Vector2(GAP, GAP + TITLE_HEIGHT)
	return Vector2(MARGIN, MARGIN) * 2.0 + Vector2(model.layout.bounds.size) * pitch - Vector2(GAP, 0)


## The zoom at which the whole map fits into `available` pixels (never more than 1, never less than the smallest zoom).
func fit_zoom(available: Vector2) -> float:
	if model == null or available.x <= 0.0 or available.y <= 0.0:
		return zoom
	var best := MAX_ZOOM
	for step in 40:
		var size := map_size(best)
		if size.x <= available.x and size.y <= available.y:
			return best
		best = maxf(best * 0.92, MIN_ZOOM)
		if best <= MIN_ZOOM:
			break
	return MIN_ZOOM


func _update_size() -> void:
	custom_minimum_size = map_size(zoom)


# --- drawing -------------------------------------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if model == null:
		return
	for screen in SectorData.SCREEN_COUNT:
		_draw_screen(screen)
	_draw_links()
	if selected_screen >= 0:
		draw_rect(screen_rect(selected_screen).grow(3), COLOR_SELECTED, false, 2.0)


func _draw_screen(screen: int) -> void:
	var rect := screen_rect(screen)
	var data := model.sector.screens[screen]
	var detached := model.layout.group_of[screen] > 0
	draw_rect(rect, COLOR_WATER)
	var background := _background(screen)
	if background != null:
		draw_texture_rect(background, rect, false)
	_draw_tiles(screen, data, rect)
	if is_overlay_shown(Overlay.CURRENTS):
		_draw_currents(data, rect)
	if is_overlay_shown(Overlay.REACHABILITY):
		_draw_reach(screen, rect)
	if is_overlay_shown(Overlay.PATHS):
		_draw_paths(screen, rect)
	_draw_objects(screen, rect)
	if is_overlay_shown(Overlay.CHECKS) and checks != null:
		_draw_check_marks(screen, rect)
	draw_rect(rect, COLOR_FRAME, false, 1.0)
	if detached:
		_draw_dashed_frame(rect.grow(2), COLOR_ONE_WAY)
	var font := get_theme_default_font()
	var title := "screen %d" % screen
	var title_color := Color.WHITE
	if detached:
		title += "  (not linked to the start)"
	if is_overlay_shown(Overlay.CHANGES) and checks != null and checks.is_changed(screen):
		draw_rect(rect.grow(2), COLOR_CHANGED, false, 3.0)
		title += "  (differs from the original)"
		title_color = COLOR_CHANGED
	draw_string(font, rect.position + Vector2(2, -4), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 12, title_color)


func _draw_tiles(_screen: int, data: ScreenData, rect: Rect2) -> void:
	var atlas_source := _tile_source()
	var tile := 16.0 * zoom
	for i in data.tiles.size():
		var byte := data.tiles[i]
		if byte & TileCodec.SOLID_BIT == 0:
			continue
		var cell := Vector2(i % ScreenData.TILE_COLUMNS, i / ScreenData.TILE_COLUMNS)
		var target := Rect2(rect.position + cell * tile, Vector2(tile, tile))
		var picture := byte & 0x3F
		if atlas_source != null and picture > 0:
			var coords := Vector2i(picture % TileCodec.ATLAS_COLUMNS, picture / TileCodec.ATLAS_COLUMNS)
			if atlas_source.has_tile(coords):
				draw_texture_rect_region(atlas_source.texture, target, atlas_source.get_tile_texture_region(coords))
				continue
		# picture 0 is the invisible wall along the surface (still a wall): a faint hatch; no art at all: a flat wall colour
		draw_rect(target, COLOR_WALL if picture > 0 else Color(1, 1, 1, 0.12))


func _draw_currents(data: ScreenData, rect: Rect2) -> void:
	var tile := 16.0 * zoom
	for i in data.tiles.size():
		var byte := data.tiles[i]
		if byte & TileCodec.SOLID_BIT != 0 or byte & TileCodec.CURRENT_BIT == 0:
			continue
		var cell := Vector2(i % ScreenData.TILE_COLUMNS, i / ScreenData.TILE_COLUMNS)
		var target := Rect2(rect.position + cell * tile, Vector2(tile, tile))
		var strength := float((byte & 0x38) >> 3) / 7.0
		draw_rect(target, Color(COLOR_CURRENT, 0.12 + 0.25 * strength))
		var direction := Vector2(TileCodec.CURRENT_DIRECTIONS[byte & 0x07])
		var centre := target.get_center()
		var tip := centre + direction.normalized() * tile * (0.3 + 0.25 * strength)
		draw_line(centre - (tip - centre), tip, Color(COLOR_CURRENT, 0.9), maxf(1.0, tile * 0.12))


func _draw_reach(screen: int, rect: Rect2) -> void:
	var reach := model.reach()
	if not reach.screen_reached[screen]:
		draw_rect(rect, COLOR_UNREACHED)
		draw_string(get_theme_default_font(), rect.position + Vector2(4, 24), "never entered", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_CONFLICT)
		return
	if not _mask_textures.has(screen):
		_mask_textures[screen] = ImageTexture.create_from_image(reach.mask(screen))
	# one image column per 2 playfield pixels, one row per pixel, starting at y = -2 (see `SectorOverviewModel.Reach.mask`)
	draw_texture_rect(_mask_textures[screen], Rect2(rect.position + Vector2(0, -2) * zoom, Vector2(TileGrid.PLAYFIELD_SIZE) * zoom), false)


# --- the checks -------------------------------------------------------------------------------------------------------------

static func finding_color(finding: CheckFinding) -> Color:
	if not finding.allowed.is_empty():
		return COLOR_ALLOWED
	match finding.severity:
		CheckFinding.Severity.ERROR:
			return COLOR_ERROR
		CheckFinding.Severity.WARNING:
			return COLOR_WARNING
	return COLOR_REMARK


## The rectangle (this control's pixels) that a mark rings: its object, at least big enough to see.
func mark_box(mark: SectorOverviewChecks.Mark, rect: Rect2) -> Rect2:
	var box := Rect2(rect.position + mark.rect.position * zoom, mark.rect.size * zoom)
	if mark.placed == SectorOverviewChecks.Placed.OBJECT and (box.size.x < 12.0 or box.size.y < 12.0):
		box = Rect2(box.get_center() - Vector2(7, 7), Vector2(14, 14))
	return box


func _draw_check_marks(screen: int, rect: Rect2) -> void:
	var marks := checks.marks_on(screen)
	if marks.is_empty():
		return
	# the best-hidden last: errors are drawn on top of warnings on top of the allowed
	for k in range(marks.size() - 1, -1, -1):
		var mark := marks[k]
		var color := finding_color(mark.finding)
		var box := mark_box(mark, rect)
		match mark.placed:
			SectorOverviewChecks.Placed.OBJECT:
				_draw_ring(box.grow(3), color, mark.muted())
			SectorOverviewChecks.Placed.SIDE:
				draw_rect(box, Color(color, 0.22))
				draw_rect(box, color, false, 1.0)
			_:
				_draw_ring(rect.grow(-3), color, mark.muted())
		if mark.finding == selected_finding:
			draw_rect(box.grow(6), COLOR_SELECTED, false, 3.0)
	var color := COLOR_ALLOWED                                     # the badge has the colour of the worst finding that is not allowed
	for mark in marks:
		if mark.finding.allowed.is_empty():
			color = finding_color(mark.finding)
			break
	var centre := rect.position + Vector2(rect.size.x - 11.0, 11.0)
	draw_circle(centre, 9.0, color)
	var font := get_theme_default_font()
	var label := str(checks.count_on(screen, true))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, centre + Vector2(-width / 2.0, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)


func _draw_ring(box: Rect2, color: Color, muted: bool) -> void:
	if muted:
		_draw_dashed_frame(box, color)
	else:
		draw_rect(box, color, false, 2.0)


## The mark of an object or a side strip under `point` (this control's pixels) on `screen`, or null.
func mark_at(screen: int, point: Vector2) -> SectorOverviewChecks.Mark:
	if checks == null or not is_overlay_shown(Overlay.CHECKS):
		return null
	var rect := screen_rect(screen)
	for mark in checks.marks_on(screen):
		if mark.placed != SectorOverviewChecks.Placed.SCREEN and mark_box(mark, rect).grow(3).has_point(point):
			return mark
	return null


func _draw_paths(screen: int, rect: Rect2) -> void:
	for path in model.paths(screen):
		var color := Color.from_hsv(fposmod(path.foe_index * 0.137, 1.0), 0.75, 1.0)
		for line in path.segments:
			if line.size() == 1:
				draw_circle(_to_control(rect, line[0]), maxf(2.0, 3.0 * zoom * 3), color)
			else:
				var points := PackedVector2Array()
				for point in line:
					points.append(_to_control(rect, point))
				draw_polyline(points, color, maxf(1.0, 2.0 * zoom * 2), true)
		if path.segments.is_empty():
			continue
		draw_circle(_to_control(rect, path.segments[0][0]), maxf(2.5, 4.0 * zoom * 2), Color.WHITE)


## A point in window pixels (the data's) on the picture of the screen at `rect`.
func _to_control(rect: Rect2, window_point: Vector2) -> Vector2:
	return rect.position + (window_point - SectorOverviewModel.ORIGIN) * zoom


func _draw_objects(screen: int, rect: Rect2) -> void:
	var font := get_theme_default_font()
	var playfield := Rect2(Vector2.ZERO, Vector2(TileGrid.PLAYFIELD_SIZE))
	for object: Dictionary in model.objects(screen):
		if not _is_shown(object["kind"]):
			continue
		var box := Rect2(rect.position + (object["rect"] as Rect2).position * zoom, (object["rect"] as Rect2).size * zoom)
		match object["kind"]:
			SectorOverviewModel.Kind.LAUNCH:
				draw_rect(box, Color(COLOR_START, 0.8), false, 1.0)
				if zoom >= 0.3:
					draw_string(font, box.position + Vector2(2, -2), "launch", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_START)
			SectorOverviewModel.Kind.START:
				draw_rect(box, Color(COLOR_START, 0.18))
				_draw_dashed_frame(box, COLOR_START)
				if zoom >= 0.3:
					draw_string(font, box.position + Vector2(2, box.size.y + 10), "start", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_START)
			SectorOverviewModel.Kind.DOCK:
				var clipped := (object["rect"] as Rect2).intersection(playfield)
				var dock := Rect2(rect.position + clipped.position * zoom, clipped.size * zoom)
				draw_rect(dock, Color(COLOR_DOCK, 0.18))
				draw_rect(dock, COLOR_DOCK, false, 1.0)
				draw_string(font, dock.position + Vector2(2, 11), "end station", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_DOCK)
			SectorOverviewModel.Kind.FINALE:
				draw_rect(box, COLOR_FINALE, false, 2.0)
				draw_string(font, box.position + Vector2(4, box.size.y - 6), "finale", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_FINALE)
			SectorOverviewModel.Kind.TRIGGER:
				var centre := box.get_center()
				var half := maxf(3.0, 5.0 * zoom * 2)
				draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -half), centre + Vector2(half, 0), centre + Vector2(0, half), centre + Vector2(-half, 0)]), Color(COLOR_TRIGGER, 0.85))
				if zoom >= 0.4:
					draw_string(font, centre + Vector2(half + 2, 4), str(model.sector.screens[screen].triggers[object["index"]].slot), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TRIGGER)
			SectorOverviewModel.Kind.PIECE, SectorOverviewModel.Kind.CANISTER:
				_draw_piece(object, box)
			SectorOverviewModel.Kind.CREATURE:
				_draw_creature(object, box)
		if object == selected_object:
			draw_rect(box.grow(2), Color.WHITE, false, 1.5)


func _draw_piece(object: Dictionary, box: Rect2) -> void:
	var canister: bool = object["kind"] == SectorOverviewModel.Kind.CANISTER
	var color := COLOR_CANISTER if canister else COLOR_PIECE
	var centre := box.get_center()
	var half := maxf(4.0, box.size.x * 0.5)
	if model_reach_known() and not _piece_reachable(object["index"]):
		draw_circle(centre, half + 3, Color(COLOR_CONFLICT, 0.55))
	draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -half), centre + Vector2(half, 0), centre + Vector2(0, half), centre + Vector2(-half, 0)]), color)
	draw_polyline(PackedVector2Array([centre + Vector2(0, -half), centre + Vector2(half, 0), centre + Vector2(0, half), centre + Vector2(-half, 0), centre + Vector2(0, -half)]), Color.BLACK, 1.0)
	if canister:
		draw_string(get_theme_default_font(), centre + Vector2(-3, 4), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)


func _draw_creature(object: Dictionary, box: Rect2) -> void:
	var foe := model.sector.foes[object["index"]]
	var frames := _foe_frames()
	var faded := foe.dormant or foe.hidden
	var alpha := 0.5 if faded else 1.0
	var picture := foe.frame & 0x7F
	if frames != null and picture < frames.get_frame_count(&"all"):
		var texture := frames.get_frame_texture(&"all", picture)
		var target := box
		if foe.flip:
			target = Rect2(box.position + Vector2(box.size.x, 0), Vector2(-box.size.x, box.size.y))
		draw_texture_rect(texture, target, false, Color(1, 1, 1, alpha))
	var outline := box
	if box.size.x < 8.0 or box.size.y < 8.0:                                                       # tiny at this zoom: a marker that can be hit
		outline = Rect2(box.get_center() - Vector2(4, 4), Vector2(8, 8))
	draw_rect(outline, Color(1, 0.4, 0.4, alpha), false, 1.0)
	if zoom >= 0.3:
		draw_string(get_theme_default_font(), outline.position + Vector2(1, -2), str(object["index"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.7, 0.7, alpha))


func _is_shown(kind: int) -> bool:
	match kind:
		SectorOverviewModel.Kind.PIECE, SectorOverviewModel.Kind.CANISTER:
			return is_overlay_shown(Overlay.PIECES)
		SectorOverviewModel.Kind.CREATURE:
			return is_overlay_shown(Overlay.CREATURES)
		SectorOverviewModel.Kind.TRIGGER:
			return is_overlay_shown(Overlay.TRIGGERS)
	return is_overlay_shown(Overlay.PLACES)


func model_reach_known() -> bool:
	return is_overlay_shown(Overlay.REACHABILITY)


func _piece_reachable(piece_index: int) -> bool:
	return model.reach().piece_reachable[piece_index]


func _draw_dashed_frame(rect: Rect2, color: Color) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		draw_dashed_line(corners[k], corners[(k + 1) % 4], color, 1.0, 4.0)


# --- the links ---------------------------------------------------------------------------------------------------------------

## The middle of a side of a screen's picture, a few pixels outside it.
func _side_point(screen: int, side: int, outside: float = 0.0) -> Vector2:
	var rect := screen_rect(screen)
	var step := Vector2(SectorLayout.STEPS[side])
	return rect.get_center() + step * (rect.size / 2.0 + Vector2(outside, outside))


func _draw_links() -> void:
	var font := get_theme_default_font()
	for link in model.layout.links:
		var screen: int = link["screen"]
		var side: int = link["side"]
		var target: int = link["target"]
		match link["kind"]:
			SectorLayout.Kind.OK:
				continue
			SectorLayout.Kind.ONE_WAY:
				var from := _side_point(screen, side, 1.0)
				_draw_arrow(from, from + Vector2(SectorLayout.STEPS[side]) * (GAP - 4.0), COLOR_ONE_WAY)
			SectorLayout.Kind.SELF:
				var at := _side_point(screen, side, 9.0)
				draw_arc(at, 8.0, 0.0, TAU, 20, COLOR_CONFLICT, 2.0)
				draw_string(font, at + Vector2(-3, 4), str(screen), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_CONFLICT)
			SectorLayout.Kind.MISPLACED:
				var from := _side_point(screen, side, 1.0)
				var to := _side_point(target, SectorLayout.OPPOSITE[side], 1.0)
				_draw_arrow(from, to, COLOR_CONFLICT, 2.0)
				draw_string(font, from + Vector2(4, -4), "%s -> %d" % [SectorLayout.SIDE_NAMES[side], target], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_CONFLICT)
			_:
				var at := _side_point(screen, side, 9.0)
				draw_string(font, at, "?%d" % target, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_CONFLICT)
	# a plain line across the gap for the links that lead back (a clean map shows its connections)
	for link in model.layout.links:
		if link["kind"] == SectorLayout.Kind.OK and link["side"] in [1, 3]:
			var from := _side_point(link["screen"], link["side"], 1.0)
			draw_line(from, from + Vector2(SectorLayout.STEPS[link["side"]]) * (GAP - 2.0 if link["side"] == 1 else GAP + TITLE_HEIGHT - 2.0), COLOR_LINK, 2.0)


func _draw_arrow(from: Vector2, to: Vector2, color: Color, width: float = 1.5) -> void:
	draw_line(from, to, color, width)
	var back := (from - to).normalized() * 7.0
	draw_line(to, to + back.rotated(0.4), color, width)
	draw_line(to, to + back.rotated(-0.4), color, width)


# --- pictures (the skin's in the game, the files' own in the editor) -----------------------------------------------------------

func _tile_source() -> TileSetAtlasSource:
	var tileset: TileSet
	if Engine.is_editor_hint():
		tileset = Packs.resource("data/neptune_tileset.tres") as TileSet
	else:
		tileset = Catalog.tileset()
	if tileset == null:
		return null
	return tileset.get_source(Catalog.zone(model.sector.zone).tile_source_id) as TileSetAtlasSource


func _foe_frames() -> SpriteFrames:
	var rel := "data/sprite_frames/foes_zone%d.tres" % model.sector.zone
	return (Packs.resource(rel) if Engine.is_editor_hint() else Catalog.foes_frames(model.sector.zone)) as SpriteFrames


func _background(screen: int) -> Texture2D:
	var path := Assets.background_path(model.sector.index, screen)
	if not Packs.exists_at(path):
		return null
	return Packs.file_at(path) as Texture2D if Engine.is_editor_hint() else Assets.background(model.sector.index, screen)


# --- the mouse -------------------------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or model == null:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.ctrl_pressed:
		zoom *= 1.15
		zoom_changed.emit(zoom)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.ctrl_pressed:
		zoom /= 1.15
		zoom_changed.emit(zoom)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		click(button.position, button.double_click)
		accept_event()


## A click at `point` (this control's pixels): an object is picked; elsewhere on a screen, that screen is selected, and a double click
## asks to open it. Public so that tests can click.
func click(point: Vector2, double: bool = false) -> void:
	var screen := screen_at(point)
	if screen < 0:
		selected_object = {}
		object_picked.emit({})
		return
	var object := _object_under(screen, point)
	selected_screen = screen
	selected_object = object
	if not object.is_empty():
		object_picked.emit(object)
		return
	object_picked.emit({})
	screen_selected.emit(screen)
	if double:
		screen_open_requested.emit(screen)


func _object_under(screen: int, point: Vector2) -> Dictionary:
	var at := playfield_point(screen, point)
	var slack := 5.0 / zoom
	var list := model.objects(screen)
	for i in range(list.size() - 1, -1, -1):
		var object: Dictionary = list[i]
		# the big places (the launch point, the dock, the finale frame) are picked only near their edge, so that they do not hide the screen
		if _is_shown(object["kind"]) and (object["rect"] as Rect2).grow(slack).has_point(at):
			if object["kind"] in [SectorOverviewModel.Kind.FINALE, SectorOverviewModel.Kind.DOCK, SectorOverviewModel.Kind.LAUNCH, SectorOverviewModel.Kind.START] \
					and (object["rect"] as Rect2).grow(-slack).has_point(at):
				continue
			return object
	return {}


func _get_tooltip(at_position: Vector2) -> String:
	if model == null:
		return ""
	var screen := screen_at(at_position)
	if screen < 0:
		return ""
	var object := _object_under(screen, at_position)
	var text := str(object["title"]) if not object.is_empty() else "screen %d (double click opens it)" % screen
	var mark := mark_at(screen, at_position)
	if mark != null:
		text += "\n" + SectorOverviewChecks.describe(mark.finding)
	return text
