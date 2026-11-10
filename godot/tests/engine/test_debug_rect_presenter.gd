class_name TestDebugRectPresenter
extends GdUnitTestSuite
## Teaches: testing a presenter against the rules it shows. The debug rectangles are a pure function of the `SimWorld`
## (`DebugRectPresenter.boxes()`), so this test builds a sim with no scene, binds the presenter, and checks that every rectangle it
## would draw is a rectangle the rules test: the walls of the tile grid, the sub's hurt rectangle and wall box, the creatures'
## hit rectangles, the pellets, the pieces, the triggers, the dock, the supply trips. That the picture really is drawn is checked by
## letting a frame go by.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const ORIGIN := Vector2(16, 32)


## A debug presenter that notes that `_draw` ran.
class Probe:
	extends DebugRectPresenter
	var draws: int = 0

	func _draw() -> void:
		draws += 1
		super._draw()


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func _bound_to(sim: SimWorld) -> DebugRectPresenter:
	var presenter := auto_free(DebugRectPresenter.new()) as DebugRectPresenter
	add_child(presenter)
	presenter.bind(sim)
	return presenter


func _of_kind(presenter: DebugRectPresenter, kind: StringName) -> Array[DebugRectPresenter.Box]:
	var found: Array[DebugRectPresenter.Box] = []
	for box in presenter.boxes():
		if box.kind == kind:
			found.append(box)
	return found


func _in_playfield(window_rect: Rect2i) -> Rect2:
	return Rect2(Vector2(window_rect.position) - ORIGIN, window_rect.size)


# --- what the rules hold is what is drawn -----------------------------------------------------------

func test_a_presenter_with_no_sector_draws_nothing_and_needs_no_scene() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _bound_to(sim)
	assert_array(presenter.boxes()).is_empty()
	sim.load_sector(Ground.MAIN, 0)
	assert_array(presenter.boxes()).is_not_empty()                      # (it heard `screen_loaded`)


func test_the_walls_and_the_currents_are_the_tile_grid() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _bound_to(sim)
	for the_screen in [[Ground.MAIN, 0], [Ground.MAIN, 2], [Ground.MAIN, Ground.CURRENT_SCREEN], [Ground.LEDGE, 1]]:
		sim.load_sector(the_screen[0], the_screen[1])
		var solid := 0
		var currents := 0
		for row in TileGrid.ROWS:
			for column in TileGrid.COLUMNS:
				if sim.tile_grid.is_solid(column, row):
					solid += 1
				elif sim.tile_grid.current_at(column, row) != Vector2i.ZERO:
					currents += 1
		var area := 0.0
		for wall in _of_kind(presenter, &"wall"):
			area += wall.rect.get_area()
			var middle := wall.rect.get_center()
			assert_bool(sim.tile_grid.is_solid_at(middle)).is_true()                # every block lies on wall tiles
		assert_float(area).is_equal(solid * 256.0)
		assert_int(_of_kind(presenter, &"current").size()).is_equal(currents)
		assert_bool(solid > 0).is_true()


func test_the_sub_is_its_hurt_rectangle_and_its_wall_box() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _bound_to(sim)
	sim.load_sector(Ground.MAIN, 0)
	assert_array(_of_kind(presenter, &"sub_hurt")).is_empty()           # (not flying yet)
	sim.foes_active = false
	sim.start_flight(100, 100)
	for t in 5:
		sim.tick(InputSnapshot.steering(1, 0))
	presenter.show_between_ticks(1.0)
	var hurt := _of_kind(presenter, &"sub_hurt")
	var walls := _of_kind(presenter, &"sub_walls")
	assert_int(hurt.size()).is_equal(1)
	assert_int(walls.size()).is_equal(1)
	assert_that(hurt[0].rect).is_equal(_in_playfield(sim.sub.hurt_rect_window()))
	var wall_box := sim.sub.tuning.wall_box
	assert_that(walls[0].rect).is_equal(_in_playfield(Rect2i(wall_box.position + sim.sub.original_position(), wall_box.size)))
	# between two ticks it glides, as the original's sub does (`TickSmoothing`)
	var moved := sim.sub.position - sim.sub.previous_position
	assert_float(moved.length()).is_greater(0.0)
	presenter.show_between_ticks(0.0)
	assert_that(_of_kind(presenter, &"sub_hurt")[0].rect.position).is_equal(hurt[0].rect.position - moved)


func test_the_creatures_are_their_hit_rectangles_when_they_can_be_touched() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _bound_to(sim)
	sim.load_sector(Ground.MAIN, 4)
	var touchable := sim.foes.filter(func(f: FoeModel) -> bool: return f.is_touchable())
	var boxes := _of_kind(presenter, &"creature")
	assert_int(boxes.size()).is_equal(touchable.size())
	assert_bool(touchable.size() > 0).is_true()
	for i in touchable.size():
		assert_that(boxes[i].rect).is_equal(_in_playfield(touchable[i].hit_rect_window()))
		assert_str(boxes[i].label).is_equal(str(touchable[i].vm.index))
	touchable[0].vm.hidden = true                                       # a hidden creature cannot be touched: no rectangle
	assert_int(_of_kind(presenter, &"creature").size()).is_equal(touchable.size() - 1)


func test_pellets_pieces_and_triggers_are_what_the_rules_hold() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _bound_to(sim)
	sim.load_sector(Ground.MAIN, 5)
	sim.foes_active = false
	sim.start_flight(100, 100)
	sim.tick(InputSnapshot.firing())
	sim.tick()
	assert_int(sim.pellets.size()).is_equal(1)
	var pellets := _of_kind(presenter, &"pellet")
	presenter.show_between_ticks(1.0)
	assert_that(_of_kind(presenter, &"pellet")[0].rect).is_equal(_in_playfield(sim.pellets[0].window_rect()))
	assert_int(pellets.size()).is_equal(1)
	sim.load_screen(9)                                                  # screen 9 of the ground sector has pieces
	assert_int(_of_kind(presenter, &"piece").size()).is_equal(sim.pieces.size())
	assert_bool(sim.pieces.size() > 0).is_true()
	assert_that(_of_kind(presenter, &"piece")[0].rect.position).is_equal(Vector2(sim.pieces[0].position()) - ORIGIN)
	sim.load_screen(5)
	var triggers := _of_kind(presenter, &"trigger")
	assert_int(triggers.size()).is_equal(sim.triggers_on_screen(5).size())
	assert_bool(triggers.size() > 0).is_true()
	assert_str(triggers[0].label).is_equal(str(sim.triggers_on_screen(5)[0].data.slot))
	sim.triggers_on_screen(5)[0].armed = false
	assert_that(_of_kind(presenter, &"trigger")[0].color).is_not_equal(triggers[0].color)    # a used trigger is grey


func test_the_dock_is_drawn_on_the_last_screen_only() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _bound_to(sim)
	sim.load_sector(Ground.MAIN, 3)
	assert_array(_of_kind(presenter, &"dock")).is_empty()
	sim.load_screen(SimWorld.DOCK_SCREEN)
	var dock := _of_kind(presenter, &"dock")
	assert_int(dock.size()).is_equal(1)
	assert_float(dock[0].rect.position.x).is_equal(SimWorld.DOCK_MIN_X - ORIGIN.x)
	assert_float(dock[0].rect.position.y).is_equal(SimWorld.DOCK_MIN_Y - ORIGIN.y)


func test_the_supply_trips_and_the_dissolve_are_told_by_the_rules() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _bound_to(sim)
	sim.load_sector(Ground.MAIN, 0)
	sim.foes_active = false
	sim.start_launch()
	var door := _of_kind(presenter, &"door")
	assert_int(door.size()).is_equal(1)
	var length := sim.sequence.ticks                                    # (the trip's length is the pack's: its durations table)
	assert_str(door[0].label).is_equal("door 3  0 of %d" % length)
	for t in 7:
		sim.tick()
	assert_str(_of_kind(presenter, &"door")[0].label).is_equal("door -1  7 of %d" % length)
	while not sim.sequence.is_done():
		sim.tick()
	assert_array(_of_kind(presenter, &"door")).is_empty()               # the trip is over: nothing to show
	sim.start_balloon()
	sim.tick()
	assert_str(_of_kind(presenter, &"balloon")[0].label).is_equal("balloon  1 of %d" % sim.sequence.ticks)
	# the dissolve fades the sub out over the ticks the rules count
	sim.sequence = null
	sim.damage_settled_by_owner = true
	sim.begin_dissolve()
	sim.advance_dissolve(10)
	var alpha_half := _of_kind(presenter, &"sub_hurt")[0].color.a
	assert_float(alpha_half).is_equal_approx(1.0 - 10.0 / SimWorld.dissolve_length(), 0.0001)


# --- it is a presenter like another -----------------------------------------------------------------

func test_the_picture_is_drawn_when_a_frame_goes_by() -> void:
	var probe := auto_free(Probe.new()) as Probe
	add_child(probe)
	var sim := SimWorld.new(GameState)
	probe.bind(sim)
	sim.load_sector(Ground.MAIN, 2)
	sim.start_flight(100, 100)
	await await_idle_frame()
	var before := probe.draws
	assert_int(before).is_greater(0)
	sim.tick(InputSnapshot.firing())                                    # `ticked` asks for a new picture
	await await_idle_frame()
	assert_int(probe.draws).is_greater(before)


func test_after_unbind_it_no_longer_answers_the_sim() -> void:
	var probe := auto_free(Probe.new()) as Probe
	add_child(probe)
	var sim := SimWorld.new(GameState)
	probe.bind(sim)
	sim.load_sector(Ground.MAIN, 0)
	await await_idle_frame()
	probe.unbind()
	await await_idle_frame()                                            # (the picture is cleared)
	var before := probe.draws
	sim.tick()
	sim.load_screen(1)
	await await_idle_frame()
	assert_int(probe.draws).is_equal(before)
	assert_array(probe.boxes()).is_empty()


func test_as_an_overlay_it_sits_over_another_presenter_on_the_same_sim() -> void:
	# how a skin author uses it: the original look, with the rectangles the rules test drawn over it, both bound to one sim
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var overlay := DebugRectPresenter.new()
	overlay.backdrop = false
	world.presenter.add_child(overlay)
	overlay.bind(world.sim)
	world.load_sector(Ground.MAIN, 0)
	world.start_flight(100, 100)
	assert_int(_of_kind(overlay, &"sub_hurt").size()).is_equal(1)
	assert_int(world.original.foes.size()).is_equal(world.sim.foes.size())      # the original presenter shows it too
	world.tick()
	overlay.unbind()
	overlay.queue_free()


func test_the_world_can_start_with_it_and_swap_back_and_forth() -> void:
	PresenterChoice.forced = PresenterChoice.DEBUG_RECTS
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	PresenterChoice.forced = &""
	assert_object(world.presenter).is_instanceof(DebugRectPresenter)
	assert_object(world.original).is_null()
	assert_int(world.presenter.get_child_count()).is_equal(0)           # no nodes below it: it only draws
	world.load_sector(Ground.MAIN, 0)
	world.toggle_presenter()
	assert_object(world.original).is_not_null()
	assert_int(world.original.foes.size()).is_equal(world.sim.foes.size())       # the original look builds what the rules already hold
	world.toggle_presenter()
	assert_object(world.presenter).is_instanceof(DebugRectPresenter)
	assert_array((world.presenter as DebugRectPresenter).boxes()).is_not_empty()


func test_the_choice_makes_each_kind_and_knows_the_other_one() -> void:
	var original := auto_free(PresenterChoice.make_presenter(PresenterChoice.ORIGINAL)) as SectorPresenter
	var debug := auto_free(PresenterChoice.make_presenter(PresenterChoice.DEBUG_RECTS)) as SectorPresenter
	assert_object(original).is_instanceof(OriginalPresenter)
	assert_object(debug).is_instanceof(DebugRectPresenter)
	assert_str(PresenterChoice.kind_of(original)).is_equal("original")
	assert_str(PresenterChoice.kind_of(debug)).is_equal("debug_rects")
	assert_str(PresenterChoice.other_than(debug)).is_equal("original")
	assert_str(PresenterChoice.other_than(original)).is_equal("debug_rects")
	assert_str(PresenterChoice.requested()).is_equal("original")          # (no command line argument in a test run)
