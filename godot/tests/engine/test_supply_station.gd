class_name TestSupplyStation
extends GdUnitTestSuite
## Teaches: a presentation step that holds up play is a number of ticks in the RULES, so it is tested by counting ticks, not by
## waiting for an animation. `StationSequence` is the trip (launch, dock, balloon); `SimWorld.tick` advances it; the scene tests below
## step the world by hand (`world.tick()`) and count. The numbers are the pack's (`station.*` of its `rules/durations.json`: dev's launch takes
## 28 ticks of 6/73 s, its dock 26; the balloon keeps the base file's rise). The original's own numbers: tests/legacy/test_supply_station_legacy.gd.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	SectorWorld.skip_animations = false


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()
	SectorWorld.skip_animations = false


# --- the trips are numbers ---------------------------------------------------------------------

func test_the_trips_read_the_packs_numbers() -> void:
	# (the numbers are data, `rules/durations.json`; `test_durations.gd` changes them and watches the rules follow)
	var launch := StationSequence.launch()
	var dock := StationSequence.dock()
	assert_array([launch.pixels_per_tick, dock.pixels_per_tick]).is_equal([4, 5])
	assert_int(launch.to_x - launch.from_x).is_equal(96)
	assert_int(dock.to_x - dock.from_x).is_equal(100)
	assert_array([launch.opening_ticks, launch.closing_ticks, dock.opening_ticks, dock.closing_ticks]).is_equal([2, 2, 4, 2])


func test_a_launch_is_28_ticks_and_a_dock_26() -> void:
	assert_int(StationSequence.launch().drive_ticks()).is_equal(24)
	assert_int(StationSequence.launch().ticks).is_equal(28)
	assert_int(StationSequence.dock().drive_ticks()).is_equal(20)
	assert_int(StationSequence.dock().ticks).is_equal(26)
	var balloon := StationSequence.balloon()                                # from the surface ship's window to above the playfield, at its speed
	assert_int(balloon.ticks).is_equal(ceili(float(balloon.balloon_from_y - balloon.balloon_to_y) / balloon.pixels_per_tick))


func test_the_door_opens_for_two_ticks_stays_open_and_closes_for_two() -> void:
	var launch := StationSequence.launch()
	var pictures: Array[int] = []
	for at in launch.ticks + 1:
		pictures.append(launch.door_picture(at))
	assert_array(pictures.slice(0, 4)).is_equal([3, 4, StationSequence.DOOR_OPEN, StationSequence.DOOR_OPEN])
	assert_array(pictures.slice(25, 29)).is_equal([StationSequence.DOOR_OPEN, 4, 3, StationSequence.DOOR_CLOSED])
	assert_int(launch.door_sound_tick()).is_equal(27)                      # 2 + 24 + 1: with the closing picture 3
	assert_int(StationSequence.dock().door_sound_tick()).is_equal(25)       # 4 + 20 + 1


func test_the_sub_waits_for_the_door_then_drives_a_fixed_number_of_pixels_a_tick() -> void:
	var launch := StationSequence.launch()
	assert_array([launch.sub_x(0), launch.sub_x(2), launch.sub_x(3), launch.sub_x(26), launch.sub_x(28)]).is_equal([0, 0, 4, 96, 96])
	var dock := StationSequence.dock()
	assert_array([dock.sub_x(4), dock.sub_x(5), dock.sub_x(24), dock.sub_x(26)]).is_equal([352, 357, 452, 452])


func test_the_balloon_rises_by_its_speed_a_tick_until_it_is_above_the_playfield() -> void:
	var balloon := StationSequence.balloon()
	assert_array([balloon.balloon_y(0), balloon.balloon_y(1)]).is_equal([balloon.balloon_from_y, balloon.balloon_from_y - balloon.pixels_per_tick])
	assert_int(balloon.balloon_y(balloon.ticks)).is_less_equal(balloon.balloon_to_y)
	assert_int(balloon.balloon_y(balloon.ticks - 1)).is_greater(balloon.balloon_to_y)


# --- the rules run them, with no scene -------------------------------------------------------

func test_the_rules_alone_launch_the_sub_in_28_ticks() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(0, 0)
	sim.foes_active = false                                                  # (the creatures' own sounds are not what is counted here)
	var seen: Array[String] = []
	sim.sequence_started.connect(func(trip: StationSequence) -> void: seen.append("started %d" % trip.ticks))
	sim.sequence_finished.connect(func(_trip: StationSequence) -> void: seen.append("finished"))
	sim.sound_requested.connect(func(sfx: StringName) -> void: seen.append("sound %s" % sfx))
	sim.start_launch()
	assert_bool(sim.sub.controlled).is_false()                               # nobody steers during the launch
	assert_int(sim.sub.original_position().x).is_equal(0)
	for t in 27:
		sim.tick()
		assert_bool(sim.sub.controlled).is_false()
	assert_array(seen).is_equal(["started 28", "sound station_door"])      # the door sound came with tick 27
	sim.tick()                                                              # the 28th
	assert_array(seen).is_equal(["started 28", "sound station_door", "finished"])
	assert_bool(sim.sub.controlled).is_true()
	assert_that(sim.sub.original_position()).is_equal(Vector2i(96, 202))


func test_the_sub_moves_only_in_ticks_and_only_its_speed_each() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(0, 0)
	sim.foes_active = false
	sim.start_launch()
	var xs: Array[int] = []
	for t in 28:
		sim.tick()
		xs.append(sim.sub.original_position().x)
		if t > 0 and xs[t] != xs[t - 1]:
			assert_int(xs[t] - xs[t - 1]).is_equal(4)
			assert_that(sim.sub.previous_position + Vector2(4, 0)).is_equal(sim.sub.position)      # (a view glides the 4 px)
	assert_array(xs.slice(0, 5)).is_equal([0, 0, 4, 8, 12])
	assert_int(xs[27]).is_equal(96)


func test_the_rules_alone_dock_the_sub_in_26_ticks_and_hide_it() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(0, 11)
	sim.start_flight(400, 200, 6)
	sim.start_dock()
	assert_that(sim.sub.original_position()).is_equal(Vector2i(352, 202))
	for t in 25:
		sim.tick()
	assert_bool(sim.sub.active).is_true()
	sim.tick()
	assert_bool(sim.sub.active).is_false()                                   # inside the station
	assert_int(sim.sub.original_position().x).is_equal(452)


func test_the_rules_alone_send_the_balloon_in_its_ticks() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(0, 11)
	var done := [0]
	sim.sequence_finished.connect(func(_trip: StationSequence) -> void: done[0] += 1)
	sim.start_balloon()
	for t in StationSequence.balloon().ticks - 1:
		sim.tick()
	assert_int(done[0]).is_equal(0)
	sim.tick()
	assert_int(done[0]).is_equal(1)
	sim.tick()
	assert_int(done[0]).is_equal(1)                                          # (a finished trip does not finish again)


# --- the scene shows them ------------------------------------------------------------------------

func test_the_stations_stand_on_the_first_and_last_screen_only() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	assert_bool(world.original.station.visible).is_true()
	assert_int(world.original.station.side).is_equal(SupplyStation.Side.LEFT)
	world.load_screen(5)
	assert_bool(world.original.station.visible).is_false()
	world.load_screen(11)
	assert_bool(world.original.station.visible).is_true()
	assert_int(world.original.station.side).is_equal(SupplyStation.Side.RIGHT)
	world.load_sector(DevPack.TOUR_FINALE, 0)                           # the finale sectors have stations too
	assert_bool(world.original.station.visible).is_true()
	assert_int(world.original.station.side).is_equal(SupplyStation.Side.LEFT)


func test_the_launch_drives_the_sub_out_and_closes_the_door() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	world.sim.foes_active = false
	var done := [false]
	(func() -> void:                                                      # a coroutine runs until its first await, then we go on
		await world.launch()
		done[0] = true).call()
	assert_bool(world.sim.sub.controlled).is_false()                          # nobody steers during the launch
	assert_int(world.sim.sub.original_position().x).is_equal(0)
	assert_object(world.original.station.door.texture).is_same(Catalog.station_frames().get_frame_texture(&"all", 3))
	for t in 2:
		world.tick()
	assert_bool(world.original.station.door.visible).is_false()                # the door is open
	for t in 25:
		world.tick()
	assert_bool(done[0]).is_false()
	world.tick()
	assert_bool(done[0]).is_true()
	assert_int(world.sim.sub.original_position().x).is_equal(96)
	assert_int(world.sim.sub.original_position().y).is_equal(202)
	assert_bool(world.sim.sub.controlled).is_true()
	assert_bool(world.original.station.door.visible).is_true()                     # the door is closed again
	assert_object(world.original.station.door.texture).is_same(Catalog.station_frames().get_frame_texture(&"all", 2))


func test_docking_drives_the_sub_into_the_right_station() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 11)
	world.start_flight(400, 200, 6)
	var done := [false]
	(func() -> void:
		await world.dock()
		done[0] = true).call()
	for t in 25:
		world.tick()
	assert_bool(done[0]).is_false()
	world.tick()
	assert_bool(done[0]).is_true()
	assert_bool(world.sim.sub.active).is_false()                              # inside the station
	assert_int(world.sim.sub.original_position().x).is_greater_equal(StationSequence.dock().to_x)


func test_a_dock_after_a_launch_is_as_long_as_one_without() -> void:
	# (The animation this replaced played the door of the dock for one tick when the same station had just launched a sub.)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	(func() -> void: await world.launch()).call()
	for t in 28:
		world.tick()
	world.load_sector(0, 11)
	world.start_flight(400, 200, 6)
	var done := [false]
	(func() -> void:
		await world.dock()
		done[0] = true).call()
	for t in 25:
		world.tick()
	assert_bool(done[0]).is_false()
	world.tick()
	assert_bool(done[0]).is_true()


func test_the_balloon_shows_while_it_rises_and_is_gone_after_its_ticks() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 11)
	var done := [false]
	(func() -> void:
		await world.send_balloon()
		done[0] = true).call()
	var balloon := world.original.station.balloon
	assert_bool(balloon.visible).is_true()
	var trip := StationSequence.balloon()
	assert_float(balloon.position.y).is_equal(trip.balloon_from_y - 32.0)       # window y in the playfield
	world.tick()
	assert_float(balloon.position.y).is_equal(trip.balloon_from_y - trip.pixels_per_tick - 32.0)
	for t in trip.ticks - 2:
		world.tick()
	assert_bool(done[0]).is_false()
	world.tick()
	assert_bool(done[0]).is_true()
	assert_bool(balloon.visible).is_false()


# --- the order they are drawn in -------------------------------------------------------------------

func test_the_balloon_rises_from_behind_the_station() -> void:
	# `LaunchBalloon` (0x432eae) draws the balloon before the body pictures and the door. Draw order is node order (no z_index
	# anywhere). The order of the station against the other layers is in `test_draw_order.gd`.
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 11)
	var station := world.original.station
	for in_front in [station.body_a, station.body_b, station.body_c, station.door]:
		assert_int(station.balloon.get_index()).is_less(in_front.get_index())
	assert_int(station.z_index).is_equal(0)                                # (order is the only thing that decides)
	assert_int(station.balloon.z_index).is_equal(0)
	# the balloon does pass the station's body (otherwise the order would not show)
	var balloon_rect := Rect2(station.balloon.position, station.balloon.texture.get_size())
	var body_rect := Rect2(station.body_b.position, station.body_b.texture.get_size())
	assert_bool(balloon_rect.intersects(body_rect)).is_true()
