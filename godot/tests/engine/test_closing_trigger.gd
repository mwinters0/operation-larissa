class_name TestClosingTrigger
extends GdUnitTestSuite
## Teaches: the finale trigger. A creature that holds the treasure sets semaphore bit 15 when the sub touches it, and the closing sequence starts as soon
## as the sub is on the sector's finale screen (`SectorData.finale_screen`) with the bit set. Dev's sector 160 has its finale screen on 2 and the treasure
## on screen 4, so the bit stays set while the sub swims back; sector 161 has both on screen 10. (The original's sectors 30 and 31:
## tests/legacy/test_closing_trigger_legacy.gd.)

const UP := 160
const HERE := 161
const UP_SCREEN := 2
const UP_TREASURE_SCREEN := 4
const HERE_SCREEN := 10

var _world: SectorWorld


func before_test() -> void:
	SectorWorld.skip_animations = true
	GameState.reset()
	_world = scene_runner("res://src/gameplay/sector_world.tscn").scene() as SectorWorld


func after_test() -> void:
	SectorWorld.skip_animations = false
	GameState.reset()


func _start(sector_index: int, screen: int) -> Array:
	_world.load_sector(sector_index, screen)
	_world.start_flight()
	var count := [0]
	_world.finale_reached.connect(func() -> void: count[0] += 1)
	return count


func test_no_bit_no_closing() -> void:
	var count := _start(UP, UP_SCREEN)
	_world.tick()
	assert_int(count[0]).is_equal(0)


func test_the_bit_on_the_wrong_screen_waits_for_the_right_one() -> void:
	var count := _start(UP, UP_TREASURE_SCREEN)
	_world.foe_context.semaphore |= 1 << SimWorld.FINALE_SEMAPHORE_BIT
	_world.tick()
	assert_int(count[0]).is_equal(0)
	_world.load_screen(UP_TREASURE_SCREEN - 1)
	_world.tick()
	assert_int(count[0]).is_equal(0)
	_world.load_screen(UP_SCREEN)
	_world.tick()
	assert_int(count[0]).is_equal(1)
	_world.tick()
	assert_int(count[0]).is_equal(1)                       # only once


func test_a_sector_closes_on_its_finale_screen_when_the_treasure_is_there_too() -> void:
	var count := _start(HERE, HERE_SCREEN)
	_world.foe_context.semaphore |= 1 << SimWorld.FINALE_SEMAPHORE_BIT
	_world.tick()
	assert_int(count[0]).is_equal(1)


func test_another_bit_does_not_end_the_game() -> void:
	var count := _start(HERE, HERE_SCREEN)
	_world.foe_context.semaphore |= 1 << 3
	_world.tick()
	assert_int(count[0]).is_equal(0)


func test_ordinary_sectors_never_close() -> void:
	var count := _start(DevPack.TOUR_SECTORS[0], UP_SCREEN)
	_world.foe_context.semaphore |= 1 << SimWorld.FINALE_SEMAPHORE_BIT
	_world.tick()
	assert_int(count[0]).is_equal(0)


## Deliberate deviation from the original (G40): the original never clears `FoeSemaphore` (0x448cac), so flags
## survive sectors and respawns. The port starts every sector load, a respawn included, with all flags 0.
func test_every_sector_load_starts_with_all_flags_clear() -> void:
	_start(DevPack.TOUR_SECTORS[1], 0)
	_world.foe_context.semaphore = 0xFFFF
	_world.load_sector(DevPack.TOUR_SECTORS[2], 0)             # the next sector
	assert_int(_world.foe_context.semaphore).is_equal(0)
	_world.foe_context.semaphore = 0xFFFF
	_world.load_sector(DevPack.TOUR_SECTORS[2], 0)             # the same sector again, as a respawn does
	assert_int(_world.foe_context.semaphore).is_equal(0)




func test_the_finale_screens_are_the_sectors_own_field() -> void:
	assert_int(SimWorld.finale_screen(UP)).is_equal(UP_SCREEN)
	assert_int(SimWorld.finale_screen(HERE)).is_equal(HERE_SCREEN)
	assert_int(SimWorld.finale_screen(DevPack.TOUR_SECTORS[0])).is_equal(-1)


func test_touching_the_treasure_sets_the_bit_even_though_it_does_no_damage() -> void:
	_start(UP, UP_TREASURE_SCREEN)
	var treasure := _world.original.foes[0]
	assert_int(treasure.vm.damage).is_equal(0)
	assert_int(treasure.vm.screen).is_equal(UP_TREASURE_SCREEN)
	_world.sub_touches(treasure.model)                              # its contact script raises bit 15 and hides it
	for i in 4:
		_world.tick()
	assert_int((_world.foe_context.semaphore >> SimWorld.FINALE_SEMAPHORE_BIT) & 1).is_equal(1)
	assert_bool(treasure.vm.hidden).is_true()


func test_a_treasure_on_the_finale_screen_ends_the_game_right_after_the_touch() -> void:
	var count := _start(HERE, HERE_SCREEN)
	_world.sub_touches(_world.sim.foes[0])
	for i in 4:
		_world.tick()
	assert_int((_world.foe_context.semaphore >> SimWorld.FINALE_SEMAPHORE_BIT) & 1).is_equal(1)
	assert_int(count[0]).is_equal(1)
