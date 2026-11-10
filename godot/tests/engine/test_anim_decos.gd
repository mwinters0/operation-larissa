class_name TestAnimDecos
extends GdUnitTestSuite
## Animated decorations: playback on the game clock (a deco of the ground sector with a list of dev's own; the legacy half,
## `tests/legacy/test_anim_decos_legacy.gd`, checks the original's frame lists against its pictures).
##
## Teaches: driving a node by emitting the signal it listens to, instead of waiting.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"


func before_test() -> void:
	# Stop the real clock so only the ticks sent by the test reach the decos.
	GameClock.paused = true


func after_test() -> void:
	GameClock.paused = false


func test_advances_one_frame_per_tick() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(Ground.MAIN)
	world.load_screen(Ground.ANIM_SCREEN)     # one animated deco
	var deco := world.original.anim_decos.get_child(0) as AnimDeco
	var list := deco.data.frames
	var expected_cursor := deco.data.start_cursor % list.size()
	assert_int(deco.frame).is_equal(list[expected_cursor])
	# Walk through two full loops of the list, one tick at a time.
	for i in list.size() * 2:
		GameClock.step()
		expected_cursor = (expected_cursor + 1) % list.size()
		assert_int(deco.frame).is_equal(list[expected_cursor])


func test_the_picture_changes_where_the_list_changes() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(Ground.MAIN)
	world.load_screen(Ground.ANIM_SCREEN)
	var deco := world.original.anim_decos.get_child(0) as AnimDeco
	assert_array(Array(deco.data.frames)).is_equal(Ground.ANIM_FRAMES)         # (the sector's list: 4 ticks of picture 0, then 4 of picture 1)
	# One whole loop of the list: we see exactly its two pictures, and the picture changes twice (at the two ends of the runs).
	var seen := {deco.frame: true}
	var changes := 0
	var previous := deco.frame
	for i in Ground.ANIM_FRAMES.size():
		GameClock.step()
		seen[deco.frame] = true
		changes += 1 if deco.frame != previous else 0
		previous = deco.frame
	assert_int(seen.size()).is_equal(2)
	assert_int(changes).is_equal(2)


func test_no_motion_without_ticks() -> void:
	var runner := scene_runner(WORLD_SCENE)
	var world := runner.scene() as SectorWorld
	world.load_sector(Ground.MAIN)
	world.load_screen(Ground.ANIM_SCREEN)
	var deco := world.original.anim_decos.get_child(0) as AnimDeco
	var before := deco.frame
	await runner.simulate_frames(30)
	assert_int(deco.frame).is_equal(before)


func test_animation_rate_is_12_17_ticks_per_second() -> void:
	# Drive the real clock with simulated 60 fps frames for 30 s. The deco must have
	# moved on by exactly as many list entries as ticks were emitted, and that
	# number must be 12.17 per second (+-2 %).
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(Ground.MAIN)
	world.load_screen(Ground.ANIM_SCREEN)
	var deco := world.original.anim_decos.get_child(0) as AnimDeco
	var list := deco.data.frames
	var start := deco.data.start_cursor % list.size()
	var ticks_before := GameClock.tick_count
	GameClock.paused = false
	GameClock.set_process(false)       # no real-time ticks, only the simulated ones
	for frame in 60 * 30:
		GameClock.advance(1.0 / 60.0)
	GameClock.set_process(true)
	var ticks := GameClock.tick_count - ticks_before
	assert_float(ticks / 30.0).is_between(GameClock.TICK_HZ * 0.98, GameClock.TICK_HZ * 1.02)
	assert_int(deco.frame).is_equal(list[(start + ticks) % list.size()])
