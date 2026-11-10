class_name TestFoeDormantScreen
extends GdUnitTestSuite
## Teaches: who runs and who sleeps. Only creatures on the shown screen execute,
## and never a dormant one; but all of them exist from the start so that one
## creature's script can wake another on a screen you cannot see.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _world: SectorWorld


func before_test() -> void:
	GameClock.paused = true
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld


func after_test() -> void:
	GameClock.paused = false


func _snapshot(foe: Foe) -> Array:
	return [foe.vm.x, foe.vm.y, foe.vm.frame, foe.vm.pc]


func test_only_creatures_on_the_current_screen_run() -> void:
	_world.load_sector(DevCreatures.ARENA, DevCreatures.POST_SCREEN)
	var here := _world.original.foes[DevCreatures.SWIMMER]
	var there := _world.original.foes[DevCreatures.RUNNER]       # on screen 6
	assert_int(there.vm.screen).is_equal(DevCreatures.RUNNER_SCREEN)
	var here_before := _snapshot(here)
	var there_before := _snapshot(there)
	for i in 30:
		_world.tick()
	assert_array(_snapshot(here)).is_not_equal(here_before)
	assert_array(_snapshot(there)).is_equal(there_before)
	# Switching screens swaps the roles; nothing was lost on the way.
	_world.load_screen(DevCreatures.RUNNER_SCREEN)
	for i in 30:
		_world.tick()
	assert_array(_snapshot(there)).is_not_equal(there_before)


func test_dormant_creatures_do_not_run_even_on_the_current_screen() -> void:
	_world.load_sector(DevCreatures.ARENA, DevCreatures.SLEEPER_SCREEN)
	var sleeper := _world.original.foes[DevCreatures.SLEEPER]       # dormant + hidden
	assert_bool(sleeper.vm.dormant).is_true()
	var before := _snapshot(sleeper)
	for i in DevCreatures.WAKER_TICKS - 1:
		_world.tick()
	assert_array(_snapshot(sleeper)).is_equal(before)
	# Wake it by hand (a script would use Wake_Foe) and it starts running.
	sleeper.vm.dormant = false
	for i in 30:
		_world.tick()
	assert_array(_snapshot(sleeper)).is_not_equal(before)


func test_a_script_wakes_a_creature_on_a_screen_that_is_not_shown() -> void:
	_world.load_sector(DevCreatures.ARENA, DevCreatures.WAKER_SCREEN)
	var sleeper := _world.original.foes[DevCreatures.SLEEPER]       # on screen 3; the waker is on screen 5
	assert_int(sleeper.vm.screen).is_not_equal(DevCreatures.WAKER_SCREEN)
	assert_bool(sleeper.vm.dormant).is_true()
	for i in DevCreatures.WAKER_TICKS - 1:
		_world.tick()
	assert_bool(sleeper.vm.dormant).is_true()
	_world.tick()
	assert_bool(sleeper.vm.dormant).is_false()
	var woken := _snapshot(sleeper)
	for i in 10:
		_world.tick()
	assert_array(_snapshot(sleeper)).is_equal(woken)                  # (awake, but its screen is not the one shown)


func test_creatures_on_other_screens_exist_but_are_invisible_and_untouchable() -> void:
	_world.load_sector(DevCreatures.ARENA, DevCreatures.POST_SCREEN)
	assert_int(_world.original.foes.size()).is_equal(DevCreatures.CREATURES)
	var shown := 0
	for foe in _world.original.foes:
		assert_bool(foe.visible).is_equal(foe.vm.screen == 0 and not foe.vm.hidden)
		assert_bool(foe.model.is_touchable()).is_equal(foe.vm.screen == 0 and not foe.vm.hidden)
		shown += int(foe.visible)
	assert_int(shown).is_greater(0)
