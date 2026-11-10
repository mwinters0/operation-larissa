class_name TestInputSnapshot
extends GdUnitTestSuite
## Teaches: keeping `Input` out of the rules. The keys are read in ONE place (`InputReader`, and the key events of
## `SectorWorld._unhandled_input`), once per game tick, into an `InputSnapshot`; `SubModel.logic_tick` and `SimWorld.tick` only
## look at that. Key presses that happen between two ticks (60 frames a second, 12 ticks a second) are counted and handed over,
## neither lost nor counted twice.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	for action in [&"sub_left", &"sub_right", &"sub_up", &"sub_down"]:
		Input.action_release(action)
	GameClock.paused = false
	GameState.reset()


func _action_event(action: StringName, pressed: bool = true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


# --- the snapshot and the reader --------------------------------------------------------------------------------

func test_left_beats_right_and_down_beats_up_as_in_the_original() -> void:
	assert_that(InputSnapshot.steer_from_keys(false, false, false, false)).is_equal(Vector2i.ZERO)
	assert_that(InputSnapshot.steer_from_keys(true, false, false, false)).is_equal(Vector2i(-1, 0))
	assert_that(InputSnapshot.steer_from_keys(false, true, false, false)).is_equal(Vector2i(1, 0))
	assert_that(InputSnapshot.steer_from_keys(true, true, false, false)).is_equal(Vector2i(-1, 0))
	assert_that(InputSnapshot.steer_from_keys(false, false, true, false)).is_equal(Vector2i(0, -1))
	assert_that(InputSnapshot.steer_from_keys(false, false, false, true)).is_equal(Vector2i(0, 1))
	assert_that(InputSnapshot.steer_from_keys(false, false, true, true)).is_equal(Vector2i(0, 1))
	assert_that(InputSnapshot.steer_from_keys(true, true, true, true)).is_equal(Vector2i(-1, 1))
	assert_that(InputSnapshot.steer_from_keys(false, true, true, false)).is_equal(Vector2i(1, -1))


func test_the_reader_polls_the_held_keys_when_the_snapshot_is_taken() -> void:
	var reader := InputReader.new()
	assert_that(reader.take().steer).is_equal(Vector2i.ZERO)
	Input.action_press(&"sub_left")
	Input.action_press(&"sub_down")
	assert_that(reader.take().steer).is_equal(Vector2i(-1, 1))
	assert_that(reader.take().steer).is_equal(Vector2i(-1, 1))      # a held key is a state: it is still there in the next snapshot
	Input.action_release(&"sub_left")
	assert_that(reader.take().steer).is_equal(Vector2i(0, 1))


func test_presses_between_two_ticks_are_counted_once_and_forgotten() -> void:
	var reader := InputReader.new()
	reader.press_fire()
	reader.press_fire()
	assert_int(reader.take().fire_presses).is_equal(2)
	assert_int(reader.take().fire_presses).is_equal(0)
	reader.press_fire()
	reader.forget()
	assert_int(reader.take().fire_presses).is_equal(0)


func test_the_rules_do_not_read_the_keyboard() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(DevCreatures.ARENA, 0)
	world.start_flight()
	world.tile_grid.clear()
	Input.action_press(&"sub_right")                                # a real key, held down
	world.sim.sub.logic_tick()
	world.tick()
	assert_that(world.sim.sub.velocity_units).is_equal(Vector2i.ZERO)   # ... which only the snapshot may move the sub with
	world.tick(InputSnapshot.steering(1))
	assert_int(world.sim.sub.velocity_units.x).is_greater(0)


func test_the_clock_tick_takes_the_snapshot_from_the_reader() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(DevCreatures.ARENA, 0)
	world.start_flight()
	world.tile_grid.clear()
	Input.action_press(&"sub_right")
	GameClock.step()                                                # the world listens to the clock and takes its snapshot
	assert_int(world.sim.sub.velocity_units.x).is_greater(0)


# --- the fire button: the same shot as before, taken in the tick --------------------------------------------------

func _flying_world() -> SectorWorld:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(DevCreatures.ARENA, 0)
	world.start_flight()
	world.foes_active = false
	world.tile_grid.clear()
	return world


func test_a_press_is_one_shot_in_the_next_tick_not_before() -> void:
	var world := _flying_world()
	world._unhandled_input(_action_event(&"fire_ink"))
	assert_int(world.sim.pellets.size()).is_equal(0)         # nothing happens between ticks ...
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max)
	world.tick(world.take_input())
	assert_int(world.sim.pellets.size()).is_equal(1)         # ... the tick that takes the press fires it
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max - 1)
	world.tick(world.take_input())
	assert_int(world.sim.pellets.size()).is_equal(1)         # ... once
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max - 1)


func test_presses_in_one_tick_are_shots_and_those_beyond_the_pellets_in_flight_are_refused() -> void:
	var world := _flying_world()
	var most := GameState.tuning.ink_in_flight_max
	for press in most + 1:
		world._unhandled_input(_action_event(&"fire_ink"))
	world.tick(world.take_input())
	assert_int(world.sim.pellets.size()).is_equal(most)      # so many pellets in flight at most
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max - most)       # the refused press cost nothing


func test_the_pellet_starts_where_the_sub_was_when_the_key_went_down() -> void:
	# Today's behaviour, kept: the shot comes from the sub's position and cell of the end of the previous tick, whatever the sub
	# does in the tick that takes the press (the original starts it from the new position; the port never did).
	var world := _flying_world()
	world.original.sub.place_original(68, 66, 6)
	var spawn := world.sim.sub.position - Sub.PICTURE_CENTER + Vector2(world.sim.sub.tuning.pellet_spawn_offset(6))
	world.sim.sub.velocity_units = Vector2i(48, 0)                      # the sub moves 6 px in this tick
	world.tick(InputSnapshot.firing())
	var pellet := world.sim.pellets[0]
	var tuning := world.sim.sub.tuning
	assert_that(pellet.position).is_equal(spawn + Vector2(tuning.pellet_step(6).x * tuning.ink_steps_per_tick, 0))   # started at `spawn`, moved one tick
	assert_int(world.sim.sub.original_position().x).is_greater(68)


func test_a_press_while_something_covers_the_playfield_is_not_counted() -> void:
	var world := _flying_world()
	GameClock.hold()
	world._unhandled_input(_action_event(&"fire_ink"))
	GameClock.release()
	assert_int(world.take_input().fire_presses).is_equal(0)


func test_a_press_of_a_sub_that_is_not_under_control_is_not_counted() -> void:
	var world := _flying_world()
	world.sim.sub.controlled = false
	world._unhandled_input(_action_event(&"fire_ink"))
	world.sim.sub.controlled = true
	assert_int(world.take_input().fire_presses).is_equal(0)
	world.stop_flight()
	world._unhandled_input(_action_event(&"fire_ink"))
	assert_int(world.take_input().fire_presses).is_equal(0)


func test_a_press_that_arrives_when_the_sub_is_no_longer_free_fires_nothing() -> void:
	var world := _flying_world()
	world._unhandled_input(_action_event(&"fire_ink"))
	world.sim.sub.controlled = false                                    # e.g. the sub is dissolving
	world.tick(world.take_input())
	assert_int(world.sim.pellets.size()).is_equal(0)
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max)


func test_key_repeat_is_not_a_second_press() -> void:
	var world := _flying_world()
	var echo := InputEventKey.new()
	echo.keycode = KEY_SPACE
	echo.physical_keycode = KEY_SPACE
	echo.pressed = true
	echo.echo = true
	world._unhandled_input(echo)
	assert_int(world.take_input().fire_presses).is_equal(0)


func test_a_release_is_not_a_press() -> void:
	var world := _flying_world()
	world._unhandled_input(_action_event(&"fire_ink", false))
	assert_int(world.take_input().fire_presses).is_equal(0)


func test_a_new_sector_forgets_the_presses_made_before_it() -> void:
	var world := _flying_world()
	world._unhandled_input(_action_event(&"fire_ink"))
	world.load_sector(DevCreatures.FISH, 0)
	assert_int(world.take_input().fire_presses).is_equal(0)
