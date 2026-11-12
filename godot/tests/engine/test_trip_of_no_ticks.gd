class_name TestTripOfNoTicks
extends GdUnitTestSuite
## A station trip whose numbers leave it no ticks (a balloon that starts where it ends: the pack check only warns "the balloon does not rise"; a launch or dock that drives no distance through a door that takes no time) still ends.
## The rules end a trip in the tick that counts its last step (`SimWorld._advance_sequence`) and the world's owner waits for that (`SectorWorld.launch` / `dock` / `send_balloon` await `SimWorld.sequence_over`), so a trip that
## is over before its first tick would be waited for for ever: the sub never under control after the launch, the next sector never begun after the balloon. A trip takes at least `StationSequence.MIN_TICKS`.
##
## Teaches: a wait on a signal needs the signal to be certain, so the number that decides it is clamped where it is made (`StationSequence._init`), and the test asks the world, which awaits, not only the arithmetic.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const PACK_FILE := "user://test_trip_of_no_ticks.json"

## Every trip made as short as the data can make it.
const NO_TICKS := {
	"station": {
		"launch": {"opening_ticks": 0, "closing_ticks": 0, "from_x": 0, "to_x": 0},
		"dock": {"opening_ticks": 0, "closing_ticks": 0, "from_x": 352, "to_x": 352},
		"balloon": {"from_y": 144, "to_y": 144},
	},
}


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false
	Durations.use_base()
	GameState.reset()


func after_test() -> void:
	Durations.use_base()
	GameClock.paused = false
	SectorWorld.skip_animations = false
	GameState.reset()
	if FileAccess.file_exists(PACK_FILE):
		DirAccess.remove_absolute(PACK_FILE)


func _mount() -> void:
	var file := FileAccess.open(PACK_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(NO_TICKS))
	file.close()
	Durations.extra_files = [PACK_FILE]
	Durations.read_files()


func test_a_trip_the_data_leaves_no_ticks_takes_one() -> void:
	_mount()
	for trip in [StationSequence.launch(), StationSequence.dock(), StationSequence.balloon()]:
		assert_int(trip.ticks).override_failure_message("trip %d" % trip.kind).is_equal(StationSequence.MIN_TICKS)
		assert_bool(trip.is_done()).is_false()
		assert_bool(trip.advance()).is_true()


## The world awaits the trip the way the flow does; the awaiting coroutine comes back when the rules say the trip is over (a tick of the clock they are given).
func test_the_world_gets_back_from_every_trip_once_its_one_tick_is_counted() -> void:
	_mount()
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	world.start_flight()
	var over: Array[String] = []
	var wait := func(name: String, trip: Callable) -> void:
		await trip.call()
		over.append(name)
	wait.call("launch", world.launch)
	assert_array(over).is_empty()                                  # (not before its tick)
	world.tick()
	assert_array(over).is_equal(["launch"])
	assert_bool(world.sim.sub.controlled).is_true()
	wait.call("dock", world.dock)
	world.tick()
	assert_array(over).is_equal(["launch", "dock"])
	assert_bool(world.sim.sub.active).is_false()                   # (the sub is in the station)
	wait.call("balloon", world.send_balloon)
	world.tick()
	assert_array(over).is_equal(["launch", "dock", "balloon"])
