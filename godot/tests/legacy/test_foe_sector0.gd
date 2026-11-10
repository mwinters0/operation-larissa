class_name TestFoeSector0
extends GdUnitTestSuite
## Teaches: checking real data against what the scripts say. Sector 0's first two
## creatures, decoded by hand from the bytecode (tools/analysis/foe_script.py).

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _world: SectorWorld


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	GameClock.paused = true
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.load_sector(0, 0)


func after_test() -> void:
	GameClock.paused = false


func _frames(foe: Foe, ticks: int) -> Array[int]:
	var seen: Array[int] = []
	for i in ticks:
		_world.tick()
		seen.append(foe.vm.frame)
	return seen


func test_foe_1_idles_with_pictures_9_and_10_then_11() -> void:
	# SET_FRAME-free start: MOVE_REL 0 0 1; LOOP0 -9 6 runs the move 6 + 1 = 7 times (the EXE's loop
	# counter starts at 0, update_animals 0x41ed0c; picture +1 inside 9..10), then SET_FRAME 11.
	var seen := _frames(_world.original.foes[1], 9)
	assert_array(seen.slice(0, 7)).is_equal([10, 9, 10, 9, 10, 9, 10])
	assert_int(seen[7]).is_equal(11)
	assert_int(seen[8]).is_equal(12)                 # then FRAME_RANGE 12..13 takes over
	assert_int(_world.original.foes[1].sprite.frame).is_equal(12)


func test_foe_0_shows_pictures_3_4_5_4_for_6_6_6_1_ticks() -> void:
	# The script cycles 3 4 5 4 (SET_FRAME, YIELD, LOOP0 5 ...): each LOOP0 count 5 runs its body 5 + 1 = 6
	# times (update_animals 0x41ed0c), so the round is 6 + 6 + 6 + 1 = 19 ticks (DESIGN 5.4).
	var seen := _frames(_world.original.foes[0], 20)
	var expected: Array[int] = []
	for pair in [[3, 6], [4, 6], [5, 6], [4, 1], [3, 1]]:
		for i in pair[1]:
			expected.append(pair[0])
	assert_array(seen).is_equal(expected)


func test_foe_0_requests_sound_13_each_round() -> void:
	var heard: Array[StringName] = []
	_world.sfx_requested.connect(func(id: StringName) -> void: heard.append(id))
	for i in 19:
		_world.tick()
	assert_array(heard).is_empty()                   # the round is 19 ticks long...
	_world.tick()                              # ...the sound is the first thing of the 20th tick
	assert_array(heard).is_equal([&"clam_chomp"])


func test_ink_turns_foe_0_into_a_cloud_and_it_comes_back() -> void:
	var foe := _world.original.foes[0]
	var home := Vector2i(foe.vm.x, foe.vm.y)
	_frames(foe, 3)
	foe.model.hit_by_ink()
	var cloud_seen := false
	var ticks := 0
	while ticks < 200:
		_world.tick()
		ticks += 1
		if foe.vm.frame >= 28 and foe.vm.frame <= 34:
			cloud_seen = true
			assert_bool(foe.vm.interrupted).is_true()
		if not foe.vm.interrupted:
			break
	assert_bool(cloud_seen).is_true()
	assert_int(ticks).is_between(55, 80)
	assert_int(foe.vm.frame).is_between(3, 5)
	# Back on its feet, at its old place (the cloud was drawn 8 px left and 10 px up of it).
	var now := Vector2i(foe.vm.x, foe.vm.y)
	assert_int(absi(now.x - home.x)).is_less_equal(0)
	assert_int(absi(now.y - home.y)).is_less_equal(0)


func test_the_cloud_is_drawn_centred_on_the_creature() -> void:
	# Picture 3 is 72 x 60, the cloud's first picture (ink 4) is 88 x 70: 8 px left (centred) and
	# 10 px up (MOVE_REL -5 is in 2-pixel units): the cloud's bottom edge lines up with the creature's.
	var foe := _world.original.foes[0]
	foe.model.hit_by_ink()
	for i in 3:                    # two YIELDs, then SET_FRAME 32 + MOVE_REL (-4, -5) = (-8, -10) px
		_world.tick()
	assert_int(foe.vm.frame).is_equal(32)
	assert_that(Vector2i(foe.vm.x, foe.vm.y)).is_equal(Vector2i(360 - 8, 222 - 10))
