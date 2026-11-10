class_name OriginalPresenter
extends SectorPresenter
## The presenter with the original's look: one screen of one sector drawn from the generated data (the background picture, the walls,
## the decorations, the pieces, the sub, the creatures, the ink, the bubbles). It shows the `SimWorld` it is bound to and decides
## nothing: every child below is built from what `sim` says and kept in step by the events of the rules (the contract is in
## `SectorPresenter`).
##
## Teaches:
##  * a scene as the VIEW of an object that has no nodes
##  * scenes instanced from code (`Deco`, `AnimDeco`, `Foe`, `InkPellet`, `Collectible`) and freed with `remove_child`
##  * `TileMapLayer.set_cell` with a shared `TileSet`; two layers, one tileset
##  * draw order = node order in the tree (no `z_index` needed)
##
## The playfield is 608 x 288 pixels (38 x 18 tiles of 16 x 16). Everything inside uses the original coordinates, so numbers from
## DESIGN can be used unchanged. `SectorWorld` places this node and cuts off anything that sticks out of the window.
##
## Draw order, back to front (see the scene), as the original's routines draw it. `DrawScreen` (0x433f1c) bakes the still picture:
## background, back decos, solid tiles, the station, mid decos. Every frame of `DoAction` (0x417ffc) then draws pieces
## (`DrawProbePieces` (0x42dc3b)), sub (`DrawSub` (0x418a81)), creatures (`update_animals` (0x41ed0c)), ink, the front decos, the ANIMATED
## decos (`DrawAnimatedDecos` (0x41e943)) and last the random bubbles. So in play: Background, BackDecos, Walls, Currents (hidden
## unless debugging), Station, MidDecos, Collectibles, Triggers (the debug markers), Sub, Foes, Pellets, FrontDecos, AnimDecos,
## Bubbles: the sub and the pieces are drawn over the station, the mid decos over the station's picture, a swaying seaweed (an
## animated deco) and a creature over the sub, and a bubble over everything.
##
## The supply trips draw otherwise. `ExitSupplyStation` (0x4328b0) and `EnterSupplyStation` (0x432b96) draw the sub, THEN the station's
## body and door, then the pieces, creatures, front and animated decos; `LaunchBalloon` (0x432eae) draws the balloon, the station, then
## the same. They draw no bubbles. So while a trip runs (`_arrange`): MidDecos, Sub, Station (the balloon first inside it), Collectibles,
## Foes ...: the station hides the sub and covers the mid decos, the pieces lie over both. After a launch the order is the play order
## again; after the dock it stays the trip's (the balloon follows and the sector is over). The bubbles are held and cleared for as long.
## Deliberate deviation from the original (G44): after a launch, `ExitSupplyStation` (0x4328b0) leaves the station drawn over the mid
## decos in its picture until a dirty rectangle (the sub, a creature) restores them from the still; here the mid decos are over the
## station again as soon as the launch ends.
##
## HOW IT FOLLOWS THE RULES.
##  * By EVENT, where the rules send one: a creature's picture, mirror and visibility (`creature_*`), a pellet leaving or arriving
##    (`pellet_fired`, `pellet_gone`), a collected piece, a fired trigger, a new sector or screen.
##  * By the TICK, for what has no event because it changes all the time: after each `ticked` the sub, the creatures' places and the
##    pellets are read from the rules. (The creature's place is where "glide or hop" is decided, see `Foe`.)
##  * By the FRAME, `show_between_ticks(fraction)`: every moving picture is shifted between its previous and its current place
##    (`TickSmoothing`): the sub, the creatures, the pellets, and the balloon of a supply trip.
##  * By the CLOCK, for the animations that no rule depends on: the sparkle of the pieces (`Collectible`), the swaying decos
##    (`AnimDeco`) and the ambient bubbles (`Bubbles`, with its own random numbers) listen to `GameClock.tick`.
##
## The `Sub` node is hidden until the rules switch the sub on (`sim.sub.active`), so the browsing-only users of this scene (the sector
## viewer, the playfield tests) are unaffected.
##
## WHAT TAKES TIME IS NOT HERE. The sub dissolving after a lost tank, the door and the drive of the supply stations and the
## balloon last as long as the RULES say (`SimWorld.dissolve_started(ticks)`, `sequence_started(sequence)`): this node is told how
## many ticks it has, draws the state after each of them, and nothing waits for it. The sub's position and `controlled` are the
## rules' too: the drive moves the model in the tick, and the picture only follows it.

## The layers whose order depends on the routine that draws them, back to front: in play (the station is part of the still picture)
## and while a supply trip runs (the station is drawn after the sub and the mid decos, before the pieces).
const PLAY_ORDER: Array[StringName] = [&"Station", &"MidDecos", &"Collectibles", &"Sub"]
const TRIP_ORDER: Array[StringName] = [&"MidDecos", &"Sub", &"Station", &"Collectibles"]

## Source id of the "currents" arrow atlas inside neptune_tileset.tres.
const CURRENTS_SOURCE_ID := 5
## Source id of the hatched "invisible wall" tile in neptune_tileset.tres. It exists only for the screen editor, which
## shows the tile byte 0x40 (a wall without art) with it. The game never uses it: `_build_tiles` draws picture 0 of the
## zone atlas, which is transparent but has the same collision square.
const INVISIBLE_WALL_SOURCE_ID := 6

const DECO_SCENE := preload("res://src/gameplay/deco.tscn")
const ANIM_DECO_SCENE := preload("res://src/gameplay/anim_deco.tscn")
const FOE_SCENE := preload("res://src/gameplay/foe.tscn")
const PELLET_SCENE := preload("res://src/gameplay/ink_pellet.tscn")
const COLLECTIBLE_SCENE := preload("res://src/gameplay/collectible.tscn")
const TRIGGER_SCENE := preload("res://src/gameplay/math_trigger.tscn")

## The creature nodes of the sector (also those on other screens), in the order of `sim.foes`.
var foes: Array[Foe] = []

## The debug overlays asked for (`show_debug`); nodes built later look here.
var _show_triggers := false
var _show_currents := false
var _show_collisions := false
## The nodes of the pellets in flight, by `PelletModel.id`.
var _pellet_nodes := {}

# `%Name` finds a node by its unique name inside this scene.
@onready var background: Sprite2D = %Background
@onready var back_decos: Node2D = %BackDecos
@onready var walls: TileMapLayer = %Walls
@onready var currents: TileMapLayer = %Currents
@onready var mid_decos: Node2D = %MidDecos
@onready var anim_decos: Node2D = %AnimDecos
@onready var collectibles: Node2D = %Collectibles
@onready var triggers_layer: Node2D = %Triggers
@onready var foes_layer: Node2D = %Foes
@onready var sub: Sub = %Sub
@onready var station: SupplyStation = %Station
@onready var pellets: Node2D = %Pellets
@onready var front_decos: Node2D = %FrontDecos
@onready var bubbles: Bubbles = %Bubbles


func _ready() -> void:
	# The tile set of the pack in use, with the skin's pictures in it (the same set for both layers).
	var tiles := Catalog.tileset()
	walls.tile_set = tiles
	currents.tile_set = tiles


## Connects the events of `sim_world` and builds everything from what it holds already: a presenter may be bound in the middle of a
## sector (F3 R, a skin change, a tool), with pellets in flight, a supply trip or a dissolve running, and shows what one bound from the
## start shows (`tests/engine/test_presenter_binds_late.gd`).
func bind(sim_world: SimWorld) -> void:
	super.bind(sim_world)
	sub.bind(sim.sub)
	_listen(sim.sector_loaded, _on_sector_loaded)
	_listen(sim.screen_loaded, _on_screen_loaded)
	_listen(sim.creature_picture_changed, func(foe: FoeModel, picture: int) -> void: foes[foe.vm.index].show_picture(picture))
	_listen(sim.creature_mirror_changed, func(foe: FoeModel, mirrored: bool) -> void: foes[foe.vm.index].show_mirror(mirrored))
	_listen(sim.creature_visibility_changed, func(foe: FoeModel, shown: bool) -> void: foes[foe.vm.index].show_visible(shown))
	_listen(sim.piece_collected, _on_piece_collected)
	_listen(sim.pieces_reset, _build_collectibles)
	_listen(sim.trigger_fired, _on_trigger_fired)
	_listen(sim.pellet_fired, _on_pellet_fired)
	_listen(sim.pellet_gone, _on_pellet_gone)
	_listen(sim.ticked, _on_ticked)
	_listen(sim.sequence_started, _on_sequence_started)
	_listen(sim.sequence_finished, _on_sequence_finished)
	_listen(sim.dissolve_started, _show_dissolve.unbind(1))
	_listen(sim.dissolve_advanced, _show_dissolve.unbind(1))
	_listen(sim.dissolve_finished, _show_dissolve)
	if sim.sector != null:
		_on_sector_loaded(sim.sector_index)
		_on_screen_loaded(sim.sector_index, sim.screen_index)
	_arrange()
	_show_dissolve()


## Shows the whole state of the rules now: the sub, every creature (picture, mirror, place) and every pellet.
func refresh() -> void:
	_arrange()
	sub.refresh()
	for foe in foes:
		foe.sync()
	for pellet: InkPellet in pellets.get_children():
		pellet.refresh()


## Every moving picture glides from its previous to its current place, `fraction` of the way into the tick.
func show_between_ticks(fraction: float) -> void:
	sub.show_between_ticks(fraction)
	station.show_between_ticks(sim.sequence, fraction)
	for foe in foes:
		foe.show_between_ticks(fraction)
	for pellet: InkPellet in pellets.get_children():
		pellet.show_between_ticks(fraction)


## The overlays: trigger markers, the arrows of the currents, and the rectangles of the rules (the walls of the tile layer, the sub's
## wall box and hurt rectangle, the creatures' hit rectangles).
func show_debug(triggers: bool, show_currents: bool, collisions: bool) -> void:
	_show_triggers = triggers
	_show_currents = show_currents
	_show_collisions = collisions
	currents.visible = show_currents
	walls.collision_visibility_mode = _collision_mode(collisions)
	sub.debug_draw = collisions
	for foe in foes:
		foe.debug_draw = collisions
	for trigger: MathTrigger in triggers_layer.get_children():
		trigger.debug_draw = triggers


# --- what takes time (told by the rules) ------------------------------------------------

## A trip at the station begins (the launch, the dock or the balloon): show its first tick.
func _on_sequence_started(sequence: StationSequence) -> void:
	_arrange()
	station.show_sequence(sequence)


## The last tick of a trip has run: its final picture, and the order of the layers of play again (after a launch).
func _on_sequence_finished(sequence: StationSequence) -> void:
	_arrange()
	station.show_sequence(sequence)


## Is the station drawn the way the trip routines draw it? From the start of a trip to its end, and after a dock or a balloon until the
## sector is loaded again (the sector is over; nothing draws the play order in between).
func _in_trip() -> bool:
	return sim.sequence != null and (not sim.sequence.is_done() or sim.sequence.kind != StationSequence.Kind.LAUNCH)


## Puts the layers of `PLAY_ORDER` or `TRIP_ORDER` in order (the other nodes keep their places) and holds the bubbles for a trip.
func _arrange() -> void:
	var trip := _in_trip()
	var order := TRIP_ORDER if trip else PLAY_ORDER
	for i in range(1, order.size()):
		var before := get_node("%" + String(order[i - 1]))
		var after := get_node("%" + String(order[i]))
		if before.get_index() > after.get_index():
			move_child(after, before.get_index())           # (right behind `before`: moving to its index, as it shifts down by one)
	bubbles.hold(trip)


## The dissolve as the rules hold it now, for each of its events, a load and a bind: a dissolve that runs has drawn its 16 passes and the
## closing copy spread evenly over the ticks the rules gave it (`sim.dissolve_ticks`, told in `dissolve_started`); one that has run out
## leaves nothing of the sub (`sim.is_dissolved()`); a load in the middle of one (`load_sector` -> `abandon_damage`, no event) leaves
## none.
func _show_dissolve() -> void:
	if sim.is_dissolving():
		sub.show_dissolve(floori(float(sim.dissolve_elapsed * (DissolvePattern.PASSES + 1)) / sim.dissolve_ticks))
	else:
		sub.show_dissolve(Sub.NO_DISSOLVE, sim.is_dissolved())


# --- the events of the rules, answered ---------------------------------------------

## The rules ran a tick: the sub, the creatures' places and the pellets are read.
func _on_ticked() -> void:
	sub.refresh()
	if sim.sequence != null and not sim.sequence.is_done():
		station.show_sequence(sim.sequence)
	for foe in foes:
		foe.follow()
	for pellet: InkPellet in pellets.get_children():
		pellet.refresh()


func _on_piece_collected(piece: PieceModel, _at: Vector2i) -> void:
	for node: Collectible in collectibles.get_children():
		if node.model == piece:
			collectibles.remove_child(node)       # (gone from the tree at once: the pieces that are left are the children)
			node.queue_free()


func _on_trigger_fired(trigger: TriggerModel) -> void:
	for node: MathTrigger in triggers_layer.get_children():
		if node.model == trigger:
			node.queue_redraw()


func _on_pellet_fired(pellet: PelletModel) -> void:
	_add_pellet(pellet)


func _on_pellet_gone(pellet: PelletModel) -> void:
	var node: InkPellet = _pellet_nodes.get(pellet.id)
	_pellet_nodes.erase(pellet.id)
	if node != null:
		pellets.remove_child(node)
		node.queue_free()


# --- builders -------------------------------------------------------------

## The creatures exist: one node for each, bound to its model. A load ends a dissolve that runs without an event of its own
## (`SimWorld.abandon_damage`): the sub's dissolve is read again too.
func _on_sector_loaded(_index: int) -> void:
	_arrange()
	_show_dissolve()
	_clear(foes_layer)
	foes.clear()
	var frames := Catalog.foes_frames(sim.sector.zone)
	for model in sim.foes:
		var foe: Foe = FOE_SCENE.instantiate()
		foe.setup(model, frames, sim.sector.zone)
		foe.debug_draw = _show_collisions
		foes_layer.add_child(foe)
		foes.append(foe)


## Draws the screen the sim has just laid out: the picture of the walls and currents, the decorations, the pieces and trigger
## markers, the station.
func _on_screen_loaded(sector_number: int, screen_number: int) -> void:
	var screen := sim.sector.screens[screen_number]
	var zone := Catalog.zone(sim.sector.zone)
	var deco_frames := Catalog.decos_frames(sim.sector.zone)

	background.texture = _load_background(screen_number)
	_build_tiles(screen, zone)
	_build_decos(back_decos, screen.bg_decos, deco_frames)
	_build_decos(mid_decos, screen.mid_decos, deco_frames)
	_build_decos(front_decos, screen.fg_decos, deco_frames)
	_build_anim_decos(screen.anim_decos, deco_frames)
	_build_pellets()                      # (after `load_screen` there are none; `reload_creatures` keeps those in flight)
	bubbles.enter_screen(sector_number, screen_number)     # the ambient bubbles start over on every screen
	_build_collectibles()
	_build_triggers()
	_show_station()
	for foe in foes:
		foe.sync()
	sub.refresh()


## The stations stand on the first and the last screen of every sector, the finales included (`DrawScreen` 0x433f1c). The door and
## the balloon are those of the trip the sim holds (one that runs, or the last one's final picture), whenever this is drawn.
func _show_station() -> void:
	station.visible = sim.screen_index == 0 or sim.screen_index == SimWorld.DOCK_SCREEN
	if station.visible:
		station.set_side(SupplyStation.Side.LEFT if sim.screen_index == 0 else SupplyStation.Side.RIGHT)
		if sim.sequence != null:
			station.show_sequence(sim.sequence)


## One node for each pellet the sim holds now (in flight or splashing). A "loaded" event says nothing about the pellets: `load_screen`
## has let them go (each with `pellet_gone`), `reload_creatures` keeps them, and a presenter bound late finds them in flight.
func _build_pellets() -> void:
	_clear(pellets)
	_pellet_nodes.clear()
	for pellet in sim.pellets:
		_add_pellet(pellet)


## The node of one pellet: the one builder, for a pellet just fired and for those `_build_pellets` finds.
func _add_pellet(pellet: PelletModel) -> void:
	var node: InkPellet = PELLET_SCENE.instantiate()
	node.setup(pellet, Catalog.foes_frames(sim.sector.zone))
	_pellet_nodes[pellet.id] = node
	pellets.add_child(node)


## Pieces of this screen that are not collected yet.
func _build_collectibles() -> void:
	_clear(collectibles)
	for piece in sim.pieces:
		var node: Collectible = COLLECTIBLE_SCENE.instantiate()
		node.setup(piece)
		collectibles.add_child(node)


## One marker node per math trigger of this screen (the rule itself is `TriggerModel.fires`).
func _build_triggers() -> void:
	_clear(triggers_layer)
	for trigger in sim.triggers_on_screen(sim.screen_index):
		var node: MathTrigger = TRIGGER_SCENE.instantiate()
		node.setup(trigger)
		node.debug_draw = _show_triggers
		triggers_layer.add_child(node)


## The picture behind everything (the skin's, else the original's: `Assets.background`). The two finale sectors have unused,
## completely empty screens (30: 5-11, 31: 11) that never got a background: show plain black.
func _load_background(index: int) -> Texture2D:
	return Assets.background(sim.sector_index, index)


## The picture of the walls and the currents is the two tile layers; the rules use `sim.tile_grid`, built from the same bytes.
func _build_tiles(screen: ScreenData, zone: ZoneData) -> void:
	walls.clear()
	currents.clear()
	for i in screen.tiles.size():
		var tile := TileCodec.decode(screen.tiles[i])
		var cell := Vector2i(i % ScreenData.TILE_COLUMNS, floori(i / float(ScreenData.TILE_COLUMNS)))
		match tile.kind:
			TileCodec.Kind.SOLID:
				# Picture 0 is transparent in the atlas but still has a collision
				# shape: the invisible walls along the top of surface sectors.
				walls.set_cell(cell, zone.tile_source_id, tile.atlas_coords)
			TileCodec.Kind.CURRENT:
				currents.set_cell(cell, CURRENTS_SOURCE_ID, tile.atlas_coords)


func _build_decos(container: Node2D, placements: Array[DecoPlacement], frames: SpriteFrames) -> void:
	_clear(container)
	for placement in placements:
		var deco: Deco = DECO_SCENE.instantiate()
		deco.setup(frames, placement)
		container.add_child(deco)


func _build_anim_decos(records: Array[AnimDecoData], frames: SpriteFrames) -> void:
	_clear(anim_decos)
	for record in records:
		var deco: AnimDeco = ANIM_DECO_SCENE.instantiate()
		deco.setup(frames, record)
		anim_decos.add_child(deco)


## Removes and frees all children at once. `queue_free` alone would leave them in
## the tree until the end of the frame; removing first makes counts correct immediately.
func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


static func _collision_mode(enabled: bool) -> TileMapLayer.DebugVisibilityMode:
	return TileMapLayer.DEBUG_VISIBILITY_MODE_FORCE_SHOW if enabled else TileMapLayer.DEBUG_VISIBILITY_MODE_DEFAULT
