class_name TestClosingTriggerLegacy
extends GdUnitTestSuite
## Teaches: the finale trigger, found by decompiling `DoAction`: the creature that holds the treasure sets
## semaphore bit 15 when the sub touches it, and the closing sequence starts as soon as the sub is on screen 2
## (sector 30) or screen 10 (sector 31) with the bit set. In sector 30 the creature is on screen 4, so the bit
## stays set while the sub swims back up.

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


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


func test_the_finale_screens() -> void:
	assert_int(SimWorld.finale_screen(30)).is_equal(2)
	assert_int(SimWorld.finale_screen(31)).is_equal(10)
	assert_int(SimWorld.finale_screen(14)).is_equal(-1)


func test_touching_the_finale_creature_sets_the_bit_even_though_it_does_no_damage() -> void:
	_start(30, 4)
	var treasure := _world.original.foes[0]
	assert_int(treasure.vm.damage).is_equal(0)
	assert_int(treasure.vm.screen).is_equal(4)                # the open question of the plan: the object is on screen 4 ...
	_world.sub_touches(treasure.model)                              # ... and its contact script raises bit 15
	for i in 4:
		_world.tick()
	assert_int((_world.foe_context.semaphore >> SimWorld.FINALE_SEMAPHORE_BIT) & 1).is_equal(1)
	assert_bool(treasure.vm.hidden).is_true()                 # "HIDE; SEM_SET 15; SOUND 27"


func test_expert_object_sets_the_bit_on_screen_10() -> void:
	_start(31, 10)
	_world.sub_touches(_world.sim.foes[0])
	for i in 4:
		_world.tick()
	assert_int((_world.foe_context.semaphore >> SimWorld.FINALE_SEMAPHORE_BIT) & 1).is_equal(1)


## The screen-0 guard of each finale sector (sector 30 foe 3, sector 31 foe 2) clears bit 15 on every tick, so a
## bit left over from earlier (the original never clears the flags) cannot end the game without the treasure.
func test_the_screen_0_guard_clears_the_finale_bit() -> void:
	for sector_index in [30, 31]:
		_start(sector_index, 0)
		_world.foe_context.semaphore |= 1 << SimWorld.FINALE_SEMAPHORE_BIT
		_world.tick()
		assert_int((_world.foe_context.semaphore >> SimWorld.FINALE_SEMAPHORE_BIT) & 1).is_equal(0)
