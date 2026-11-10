class_name TestCollisionOption
extends GdUnitTestSuite
## Teaches: a setting that switches one rule off, tested from both sides. The original reads `[ONWINCD] Collision`
## once (`ReadCollisionSetting` 0x4147ac) and consults the result in exactly one place (`update_animals`
## 0x41ed0c, where a touching creature may become "the one that hurts"); `MachineSettings` keeps it for the port.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _world: SectorWorld
var _settings_file := "user://test_machine_settings.cfg"


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	MachineSettings.settings_path = _settings_file
	DirAccess.remove_absolute(_settings_file)
	MachineSettings.collision_enabled = true


func after_test() -> void:
	MachineSettings.settings_path = MachineSettings.SETTINGS_PATH
	DirAccess.remove_absolute(_settings_file)
	MachineSettings.collision_enabled = true
	GameClock.paused = false
	GameState.reset()


## The sub parked on creature `foe` (its hurt rectangle exactly on the creature's rectangle).
func _park_on(foe: Foe) -> void:
	var rect := foe.model.hit_rect_window()
	var cell := 6
	var offset: Rect2i = _world.sim.sub.tuning.frame_rects[cell]
	_world.start_flight(rect.position.x - offset.position.x, rect.position.y - offset.position.y, cell)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_true()


func _start_world() -> Foe:
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.load_sector(DevCreatures.ARENA, 0)
	var foe := _world.original.foes[DevCreatures.POST]             # hostile (damage 1), on screen 0
	assert_bool(foe.model.is_touchable()).is_true()
	assert_int(foe.vm.damage).is_greater(0)
	_park_on(foe)
	return foe


# --- the option --------------------------------------------------------------------------------

func test_it_is_on_by_default() -> void:
	MachineSettings.load_settings()                        # no file: the original's default value "TRUE"
	assert_bool(MachineSettings.collision_enabled).is_true()


func test_only_the_word_false_switches_it_off_like_the_original_string_compare() -> void:
	assert_bool(MachineSettings.is_enabled("FALSE")).is_false()
	assert_bool(MachineSettings.is_enabled(false)).is_false()
	assert_bool(MachineSettings.is_enabled("TRUE")).is_true()
	assert_bool(MachineSettings.is_enabled("false")).is_true()      # lstrcmpA is case sensitive
	assert_bool(MachineSettings.is_enabled("")).is_true()
	assert_bool(MachineSettings.is_enabled(true)).is_true()
	assert_bool(MachineSettings.is_enabled(0)).is_true()


func test_the_file_is_read_and_written_in_the_ini_layout() -> void:
	MachineSettings.collision_enabled = false
	assert_int(MachineSettings.save_settings()).is_equal(OK)
	MachineSettings.collision_enabled = true
	MachineSettings.load_settings()
	assert_bool(MachineSettings.collision_enabled).is_false()
	var text := FileAccess.get_file_as_string(_settings_file)
	assert_str(text).contains("[ONWINCD]")
	assert_str(text).contains("Collision=false")
	var config := ConfigFile.new()                         # a hand-written INI with the original's spelling works too
	config.set_value("ONWINCD", "Collision", "FALSE")
	config.save(_settings_file)
	MachineSettings.load_settings()
	assert_bool(MachineSettings.collision_enabled).is_false()


# --- the rule ----------------------------------------------------------------------------------

func test_with_collision_on_a_touching_creature_hurts() -> void:
	var foe := _start_world()
	_world.check_contacts()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - foe.vm.damage)
	assert_bool(_world.sim.sub.is_invulnerable()).is_true()


func test_with_collision_off_a_touching_creature_does_no_damage_but_still_runs_its_contact_script() -> void:
	var foe := _start_world()
	MachineSettings.collision_enabled = false
	_world.check_contacts()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)
	assert_bool(_world.sim.sub.is_invulnerable()).is_false()
	assert_bool(foe.vm.interrupted).is_true()              # `update_animals` still starts the hit script (pc = record + 11)
	for tick in 5:
		_world.check_contacts()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)


## Zoom the dolphin (a negative damage byte) with the sub parked on it, on the screen where it swims.
func _park_on_zoom() -> void:
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.load_sector(DevCreatures.ARENA, 0)
	var zoom: Foe = null
	for foe in _world.original.foes:
		if foe.vm.damage < 0:
			zoom = foe
			break
	assert_object(zoom).is_not_null()
	_world.load_screen(zoom.vm.screen)
	zoom.vm.hidden = false                                 # (it appears when its script says so)
	GameState.oxygen_model.oxygen = 1
	_park_on(zoom)


func test_with_collision_on_zoom_refills_the_air() -> void:
	_park_on_zoom()
	_world.check_contacts()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)


func test_with_collision_off_zoom_brings_no_tank_either() -> void:
	# The switch is on the test `damage != 0`, so the friendly (negative) damage of Zoom is not applied either.
	_park_on_zoom()
	MachineSettings.collision_enabled = false
	_world.check_contacts()
	assert_int(GameState.oxygen()).is_equal(1)
