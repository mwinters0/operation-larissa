class_name TestPresenter
extends GdUnitTestSuite
## Teaches: testing the edge between the rules and the picture. A presenter needs only a `SimWorld`: this test binds the
## original presenter to a bare sim with no `SectorWorld` around it, checks that what it shows is what the rules say (by the events,
## by the tick, and between two ticks by the tick fraction), and that a different presenter - here a blank one - can take its place
## without the rules noticing.

const PRESENTER_SCENE := "res://src/gameplay/original_presenter.tscn"
const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SectorWorld.skip_animations = false
	GameState.reset()


## An original presenter in the tree, bound to `sim`.
func _presenter_for(sim: SimWorld) -> OriginalPresenter:
	var presenter := auto_free((load(PRESENTER_SCENE) as PackedScene).instantiate()) as OriginalPresenter
	add_child(presenter)
	presenter.bind(sim)
	return presenter


func _steer(x: int, y: int) -> InputSnapshot:
	return InputSnapshot.steering(x, y)


# --- the smoothing is a function of the fraction ----------------------------------------------

func test_the_tick_fraction_is_an_argument_of_the_smoothing() -> void:
	var previous := Vector2(10, 20)
	var current := Vector2(30, 20)
	assert_that(TickSmoothing.offset(previous, current, 0.0)).is_equal(Vector2(-20, 0))       # a tick has just happened: still at the old place
	assert_that(TickSmoothing.offset(previous, current, 0.5)).is_equal(Vector2(-10, 0))
	assert_that(TickSmoothing.offset(previous, current, 1.0)).is_equal(Vector2.ZERO)          # the next tick is due: at the new place


# --- a presenter bound to a bare sim ----------------------------------------------------------

func test_a_presenter_follows_a_sim_that_has_no_scene_around_it() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _presenter_for(sim)                   # (bound before any sector exists)
	sim.load_sector(DevCreatures.ARENA, 0)
	assert_int(presenter.foes.size()).is_equal(sim.foes.size())
	assert_int(presenter.collectibles.get_child_count()).is_equal(sim.pieces.size())
	for i in sim.foes.size():
		assert_bool(presenter.foes[i].visible).is_equal(sim.foes[i].is_shown())
	sim.start_flight()
	presenter.refresh()
	assert_bool(presenter.sub.visible).is_true()
	for t in 30:
		sim.tick(_steer(1, 0) if t < 20 else InputSnapshot.firing())       # swim right, then shoot
		assert_that(presenter.sub.position).is_equal(sim.sub.position)     # (the sim said `ticked`; nobody called refresh)
		assert_int(presenter.pellets.get_child_count()).is_equal(sim.pellets.size())
		for i in sim.foes.size():
			assert_that(presenter.foes[i].position).is_equal(Vector2(sim.foes[i].vm.x, sim.foes[i].vm.y) - SubModel.PLAYFIELD_ORIGIN)
	assert_int(sim.pellets.size()).is_greater(0)


func test_a_presenter_bound_late_builds_what_the_rules_already_hold() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, DevCreatures.WAKER_SCREEN)                  # (a screen with a creature and a trigger)
	var presenter := _presenter_for(sim)
	assert_int(presenter.foes.size()).is_equal(sim.foes.size())
	assert_int(presenter.collectibles.get_child_count()).is_equal(sim.pieces.size())
	assert_int(presenter.triggers_layer.get_child_count()).is_equal(sim.triggers_on_screen(DevCreatures.WAKER_SCREEN).size())
	assert_int(sim.triggers_on_screen(DevCreatures.WAKER_SCREEN).size()).is_greater(0)
	for i in sim.foes.size():
		assert_bool(presenter.foes[i].visible).is_equal(sim.foes[i].is_shown())
		assert_int(presenter.foes[i].sprite.frame).is_equal(sim.foes[i].vm.frame)


func test_a_creature_changing_is_an_event_and_the_node_follows_it() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _presenter_for(sim)
	sim.load_sector(DevCreatures.ARENA, DevCreatures.MIRROR_SCREEN)        # the mirror is drawn mirrored and shown
	var model := sim.foes[DevCreatures.MIRROR]
	var node := presenter.foes[DevCreatures.MIRROR]
	assert_bool(node.visible).is_true()
	assert_bool(node.sprite.flip_h).is_true()
	model.vm.hidden = true
	model.vm.flip = false
	model.vm.frame = NameRegistry.original().index_of(&"frame", "ink_burst_2", 0)
	model.announce_changes()                               # the model says what changed; no `sync`, no tick
	assert_bool(node.visible).is_false()
	assert_bool(node.sprite.flip_h).is_false()
	assert_int(node.sprite.frame).is_equal(model.vm.frame)


# --- the tick and the fraction -----------------------------------------------------------------

func test_ticked_is_the_last_thing_of_a_tick() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight()
	sim.trace_ticks = true
	var steps_seen: Array[int] = []
	sim.ticked.connect(func() -> void: steps_seen.append(sim.tick_trace.size()))
	for t in 4:
		sim.tick()
	assert_array(steps_seen).is_equal([SimWorld.TICK_ORDER.size(), SimWorld.TICK_ORDER.size(), SimWorld.TICK_ORDER.size(), SimWorld.TICK_ORDER.size()])


func test_the_picture_sits_between_the_previous_and_the_current_place_by_the_fraction() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _presenter_for(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foes_active = false
	sim.start_flight(100, 100)
	for t in 3:
		sim.tick(_steer(1, 0))
	var moved := sim.sub.position - sim.sub.previous_position
	assert_float(moved.length()).is_greater(0.0)
	presenter.show_between_ticks(0.0)
	assert_that(presenter.sub.visual.position).is_equal(-moved)                    # just after the tick: where it was before it
	presenter.show_between_ticks(0.5)
	assert_that(presenter.sub.visual.position).is_equal(-moved * 0.5)
	presenter.show_between_ticks(1.0)
	assert_that(presenter.sub.visual.position).is_equal(Vector2.ZERO)             # the next tick is due: at the place the rules say
	# A pellet is drawn the same way.
	sim.tick(InputSnapshot.firing())
	sim.tick()
	var pellet := sim.pellets[0]
	var node: InkPellet = presenter.pellets.get_child(0)
	presenter.show_between_ticks(0.25)
	assert_that(node.sprite.position).is_equal(pellet.splash_offset + (pellet.previous_position - pellet.position) * 0.75)


## The lock opens (`GameFlow.complete_sector` -> `SimWorld.reload_creatures`): the creatures start over, announced as a load of the same
## sector and screen, but the pellets in flight fly on. The presenter builds its pellets from what the sim holds, not from the event.
func test_the_pellets_in_flight_are_still_drawn_after_the_creatures_are_reloaded() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _presenter_for(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foes_active = false
	sim.start_flight(100, 100)
	sim.tick(InputSnapshot.firing())
	sim.tick()
	assert_int(sim.pellets.size()).is_greater(0)
	sim.reload_creatures()
	assert_int(presenter.pellets.get_child_count()).is_equal(sim.pellets.size())
	for t in 3:
		sim.tick()
		assert_int(presenter.pellets.get_child_count()).is_equal(sim.pellets.size())
		for i in sim.pellets.size():
			assert_that((presenter.pellets.get_child(i) as InkPellet).position).is_equal(sim.pellets[i].position)


## A presenter bound while the sub dissolves (F3 R, a skin change) draws the dissolve where it is, as the one bound before it does.
func test_a_presenter_bound_during_a_dissolve_draws_it_where_it_is() -> void:
	var sim := SimWorld.new(GameState)
	var first := _presenter_for(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(200, 150, 6)
	sim.begin_dissolve()
	sim.advance_dissolve(SimWorld.dissolve_length() / 2)
	var late := _presenter_for(sim)
	assert_object(late.sub.dissolve_material()).is_not_null()
	assert_float(late.sub.dissolve_material().get_shader_parameter("passes_done")).is_equal(first.sub.dissolve_material().get_shader_parameter("passes_done"))
	assert_float(late.sub.dissolve_material().get_shader_parameter("passes_done")).is_greater(0.0)
	sim.advance_dissolve(SimWorld.dissolve_length())                       # it runs out: nothing of the sub is drawn by either
	var after := _presenter_for(sim)
	for presenter: OriginalPresenter in [first, late, after]:
		assert_object(presenter.sub.dissolve_material()).is_null()
		assert_bool(presenter.sub.visual.visible).is_false()


## A sector loaded during a dissolve (a respawn key, a tool) ends it with no event (`SimWorld.abandon_damage`): the presenter reads on
## the load that none runs, and the sub is drawn whole again.
func test_a_sector_loaded_during_a_dissolve_leaves_no_dissolve_drawn() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _presenter_for(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(200, 150, 6)
	sim.begin_dissolve()
	sim.advance_dissolve(SimWorld.dissolve_length() / 2)
	assert_object(presenter.sub.dissolve_material()).is_not_null()
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(200, 150, 6)
	assert_object(presenter.sub.dissolve_material()).is_null()
	for picture: AnimatedSprite2D in [presenter.sub.sprite, presenter.sub.bubbles, presenter.sub.light]:
		assert_object(picture.material).is_null()
	assert_bool(presenter.sub.visual.visible).is_true()


## A presenter bound during a supply trip shows the door and the balloon where the trip has them, at once (not from the next tick on).
func test_a_presenter_bound_during_a_trip_shows_the_door_and_the_balloon() -> void:
	var sim := SimWorld.new(GameState)
	var first := _presenter_for(sim)
	sim.load_sector(DevCreatures.ARENA, SimWorld.DOCK_SCREEN)
	sim.foes_active = false
	sim.start_flight(400, 200, 6)
	sim.start_dock()
	sim.tick()                                                              # the door shows picture 4
	var late := _presenter_for(sim)
	assert_bool(late.station.door.visible).is_true()
	assert_object(late.station.door.texture).is_same(first.station.door.texture)
	assert_object(late.station.door.texture).is_same(Catalog.station_frames().get_frame_texture(&"all", sim.sequence.door_picture()))
	while not sim.sequence.is_done():
		sim.tick()
	sim.start_balloon()
	for t in 5:
		sim.tick()
	late = _presenter_for(sim)
	assert_bool(late.station.balloon.visible).is_true()
	assert_that(late.station.balloon.position).is_equal(first.station.balloon.position)


# --- debug overlays ----------------------------------------------------------------------------

func test_the_collision_overlay_reaches_nodes_built_later_too() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _presenter_for(sim)
	presenter.show_debug(true, false, true)
	sim.load_sector(DevCreatures.ARENA, 0)                                  # (the creatures and the trigger markers do not exist yet when it was asked for)
	sim.start_flight()
	presenter.show_debug(true, false, true)
	assert_bool(presenter.sub.debug_draw).is_true()
	for foe in presenter.foes:
		assert_bool(foe.debug_draw).is_true()
	presenter.show_debug(false, false, false)
	assert_bool(presenter.sub.debug_draw).is_false()
	for foe in presenter.foes:
		assert_bool(foe.debug_draw).is_false()


# --- another presenter in its place ------------------------------------------------------------

## The state of a flight in numbers: where the sub and the creatures are after each tick, and what the player's game holds.
func _fly(world: SectorWorld, ticks: int) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	world.load_sector(DevCreatures.ARENA, 0)
	world.sim.foe_context.rng.seed = 4242
	world.start_flight()
	var steer := Vector2i.ZERO
	var trace: Array[String] = []
	for t in ticks:
		if t % 7 == 0:
			steer = Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		var input := InputSnapshot.steering(steer.x, steer.y)
		input.fire_presses = 1 if rng.randf() < 0.3 else 0
		world.tick(input)
		var line := "%s %d ink=%d ox=%d" % [world.sim.sub.original_position(), world.sim.screen_index, GameState.ink, GameState.oxygen()]
		for foe in world.sim.foes:
			line += " %d,%d,%d" % [foe.vm.x, foe.vm.y, foe.vm.frame]
		trace.append(line)
	return trace


func test_a_blank_presenter_in_its_place_changes_nothing_the_rules_do() -> void:
	var original_world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var original_trace := _fly(original_world, 250)
	GameState.reset()
	var blank_world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	blank_world.replace_presenter(SectorPresenter.new())
	assert_object(blank_world.original).is_null()
	assert_int(blank_world.presenter.get_child_count()).is_equal(0)       # it shows nothing at all
	var blank_trace := _fly(blank_world, 250)
	assert_array(blank_trace).is_equal(original_trace)


## Steps the world's rules by hand until `done` is true; returns how many ticks that took (at most `limit`).
func _ticks_until(world: SectorWorld, done: Array, limit: int = 200) -> int:
	var ticks := 0
	while not done[0] and ticks < limit:
		world.tick()
		ticks += 1
	return ticks


## The length of every step that holds up play, with a given presenter: launch, dock, balloon in game ticks, dissolve in ticks of 1/73 s.
func _timings(world: SectorWorld) -> Array[int]:
	var timings: Array[int] = []
	world.load_sector(DevCreatures.ARENA, 0)
	world.sim.foes_active = false
	var launched := [false]
	(func() -> void:
		await world.launch()
		launched[0] = true).call()
	timings.append(_ticks_until(world, launched))
	assert_bool(world.sim.sub.controlled).is_true()
	world.load_sector(DevCreatures.ARENA, SimWorld.DOCK_SCREEN)
	world.start_flight(400, 200, 6)
	var docked := [false]
	(func() -> void:
		await world.dock()
		docked[0] = true).call()
	timings.append(_ticks_until(world, docked))
	assert_bool(world.sim.sub.active).is_false()
	var sent := [false]
	(func() -> void:
		await world.send_balloon()
		sent[0] = true).call()
	timings.append(_ticks_until(world, sent))
	world.load_sector(DevCreatures.ARENA, 0)
	world.start_flight(200, 150, 6)
	GameState.oxygen_model.oxygen = 1
	world.sub_touches(world.sim.foes[DevCreatures.POST])
	var dissolved := 0
	while GameClock.holds > 0 and dissolved < 100:
		world.sim.advance_dissolve(1)
		dissolved += 1
	timings.append(dissolved)
	return timings


func test_a_blank_presenter_holds_up_launch_dock_balloon_and_dissolve_for_exactly_as_long() -> void:
	# the lengths are the rules', so a presenter that draws nothing cannot make a step shorter (or longer) than the original one.
	SectorWorld.skip_animations = false
	var original_world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var original_timings := _timings(original_world)
	GameState.reset()
	var blank_world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	blank_world.replace_presenter(SectorPresenter.new())
	assert_object(blank_world.original).is_null()
	var blank_timings := _timings(blank_world)
	assert_array(original_timings).is_equal([StationSequence.launch().ticks, StationSequence.dock().ticks, StationSequence.balloon().ticks, SimWorld.dissolve_length()])
	assert_array(blank_timings).is_equal(original_timings)


func test_a_blank_presenter_gives_the_same_trace_through_a_launch_and_a_dive() -> void:
	SectorWorld.skip_animations = false
	var traces: Array = []
	for blank in [false, true]:
		GameState.reset()
		var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
		if blank:
			world.replace_presenter(SectorPresenter.new())
		world.load_sector(DevCreatures.ARENA, 0)
		world.sim.foe_context.rng.seed = 99
		var launched := [false]
		(func() -> void:
			await world.begin_sector(DevCreatures.ARENA)
			launched[0] = true).call()
		var trace: Array[String] = []
		var t := 0
		while t < 60:
			world.tick(InputSnapshot.steering(1, 0) if launched[0] else null)
			trace.append("%s %s %s" % [world.sim.sub.original_position(), world.sim.sub.controlled, launched[0]])
			t += 1
		traces.append(trace)
	assert_array(traces[1]).is_equal(traces[0])
	assert_bool((traces[0] as Array).any(func(line: String) -> bool: return line.ends_with("true"))).is_true()


func test_the_replacement_is_bound_to_the_rules_and_shows_what_they_hold() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(DevCreatures.ARENA, DevCreatures.MIRROR_SCREEN)
	world.replace_presenter((load(PRESENTER_SCENE) as PackedScene).instantiate() as SectorPresenter)
	assert_int(world.original.foes.size()).is_equal(world.sim.foes.size())
	assert_bool(world.original.foes[DevCreatures.MIRROR].visible).is_true()
