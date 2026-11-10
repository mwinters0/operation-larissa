class_name TestInkPellets
extends GdUnitTestSuite
## Teaches: testing gameplay through the real scene (`SectorWorld`) with the clock
## paused: the test presses the button by emitting the sub's signal and advances
## time by calling `tick()` itself (the pellets, like the rest of the playfield, have no physics overlaps to wait for).

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _world: SectorWorld
var _sounds: Array[StringName]
var _record_sound := func(id: StringName) -> void: _sounds.append(id)


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.load_sector(DevCreatures.ARENA, 0)
	_world.start_flight(68, 66, 6)               # (window pixels, facing right: the numbers of the tests below)
	_world.foes_active = false
	_world.tile_grid.clear()            # open water: only the tiles a test adds are there
	_sounds = []
	_world.sfx_requested.connect(_record_sound)


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


## One press of the fire button (what the tick does with each press in its snapshot).
func _fire() -> void:
	_world.request_fire()


## Puts the pellet's box on the creature's top-left corner (window pixels, see `PelletModel.window_rect`).
func _put_on(pellet: PelletModel, foe: Foe) -> void:
	pellet.position = Vector2(foe.model.hit_rect_window().position) - Sub.PLAYFIELD_ORIGIN


## Puts the sub's collision rectangle on the creature.
func _put_sub_on(foe: Foe) -> void:
	var at := foe.model.hit_rect_window().position - Vector2i(20, 20)
	_world.original.sub.place_original(at.x, at.y, 6)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), foe.model.hit_rect_window())).is_true()


func _live_pellets() -> Array[PelletModel]:
	var result: Array[PelletModel] = []
	for pellet in _world.sim.pellets:
		if pellet.alive:
			result.append(pellet)
	return result


## A pellet that is gone from the sky (what its splash ending does to it).
func _drop(pellet: PelletModel) -> void:
	_world.sim.pellets.erase(pellet)


func test_a_shot_beyond_the_pellets_in_flight_is_ignored_and_costs_nothing() -> void:
	var most := GameState.tuning.ink_in_flight_max
	for i in most + 1:
		_fire()
	assert_int(_world.sim.pellets.size()).is_equal(most)
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max - most)
	var fired: Array[StringName] = []
	fired.resize(most)
	fired.fill(SimWorld.SFX_INK_FIRED)
	assert_array(_sounds).is_equal(fired)


func test_each_shot_uses_one_pellet_and_empty_supply_plays_the_no_pellets_sound() -> void:
	GameState.ink = 1
	_fire()
	assert_int(GameState.ink).is_equal(0)
	for pellet in _live_pellets():
		_drop(pellet)
	_sounds.clear()
	_fire()
	assert_int(_world.sim.pellets.size()).is_equal(0)
	assert_array(_sounds).is_equal([SimWorld.SFX_NO_PELLETS])


func test_supply_refill_restores_the_full_supply() -> void:
	for i in 2:
		_fire()
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max - 2)
	GameState.refill_ink()
	assert_int(GameState.ink).is_equal(GameState.tuning.ink_max)


func test_pellet_appears_in_front_of_the_nose_and_flies_its_steps_per_tick() -> void:
	# Sub at window (68, 66) in cell 6 (facing right): muzzle offset (76, 16) from the picture's corner.
	_fire()
	var tuning := GameState.tuning.sub
	var per_tick := tuning.pellet_step(6).x * tuning.ink_steps_per_tick       # (24 pixels in the original: 3 steps of 8)
	var pellet := _live_pellets()[0]
	assert_that(pellet.position).is_equal(Vector2(100 - 48 + 76, 61 - 27 + 16))
	pellet.logic_tick()
	assert_that(pellet.position).is_equal(Vector2(128 + per_tick, 50))
	pellet.logic_tick()
	assert_that(pellet.position).is_equal(Vector2(128 + 2 * per_tick, 50))


func test_pellets_follow_the_direction_table_of_the_sub_cell() -> void:
	# Cell 7 = facing right, nose up: direction code 5 = (+8, -2) per step.
	var steps := GameState.tuning.sub.ink_steps_per_tick
	_world.sim.sub.cell = 7
	_fire()
	var pellet := _live_pellets()[0]
	var start := pellet.position
	pellet.logic_tick()
	assert_that(pellet.position - start).is_equal(Vector2(8 * steps, -2 * steps))
	# Cell 1 = facing left, nose up: (-8, -2).
	_world.sim.sub.cell = 1
	_fire()
	var other := _live_pellets()[1]
	var other_start := other.position
	other.logic_tick()
	assert_that(other.position - other_start).is_equal(Vector2(-8 * steps, -2 * steps))


func test_pellet_splashes_on_rock_for_three_ticks_and_disappears() -> void:
	# A rock tile (zone 0 picture 1) in column 20, rows 2-5.
	for row in range(2, 6):
		_world.tile_grid.set_byte(20, row, TileCodec.SOLID_BIT | 1)
	_fire()
	var pellet := _live_pellets()[0]
	var ticks := 0
	while pellet.is_flying() and ticks < 30:
		pellet.logic_tick()
		ticks += 1
	var per_tick := GameState.tuning.sub.ink_steps_per_tick * 8
	assert_int(ticks).is_equal(ceili((320 - 128) / float(per_tick)))       # (8 ticks of 24 in the original) the centre is in column 20 (x 320)
	assert_int(pellet.splash_picture).is_equal(1)
	pellet.logic_tick()
	assert_int(pellet.splash_picture).is_equal(2)
	pellet.logic_tick()
	assert_int(pellet.splash_picture).is_equal(3)
	assert_bool(pellet.alive).is_true()
	pellet.logic_tick()
	assert_bool(pellet.alive).is_false()


func test_pellet_that_leaves_the_playfield_just_disappears() -> void:
	_fire()
	var pellet := _live_pellets()[0]
	for i in 25:
		pellet.logic_tick()
	assert_bool(pellet.alive).is_false()
	assert_int(pellet.splash_picture).is_equal(0)       # no splash at the edge


func test_firing_while_facing_the_viewer_splashes_at_once() -> void:
	_world.sim.sub.cell = 4
	_fire()
	var pellet := _live_pellets()[0]
	assert_bool(pellet.is_flying()).is_false()
	assert_int(pellet.splash_picture).is_equal(1)


func test_a_slot_frees_up_when_a_pellet_is_gone() -> void:
	_fire()
	_fire()
	for pellet in _live_pellets():
		_drop(pellet)
	_fire()
	assert_int(_world.sim.pellets.size()).is_equal(1)


## As in the original (DESIGN 3.5, `UpdateStunGun` clears the flag in the same call): a pellet that is over leaves the list at once, so a clock that catches up with two ticks in one frame
## does not count it as in flight.
func test_a_finished_pellet_frees_its_slot_in_the_same_frame() -> void:
	_fire()
	_fire()
	assert_int(_world.sim.pellets.size()).is_equal(2)
	for i in 30:                                          # (all in this frame: no frame is awaited)
		_world.tick()
	assert_int(_world.sim.pellets.size()).is_equal(0)     # both flew out of the playfield and are gone
	_fire()
	_fire()
	assert_int(_world.sim.pellets.size()).is_equal(2)     # ... so two new ones may fly at once


func test_pellets_are_cleared_on_a_screen_change() -> void:
	_fire()
	_world.go(SectorData.Direction.RIGHT)
	assert_int(_world.sim.pellets.size()).is_equal(0)


func test_pellet_overlapping_a_creature_starts_its_ink_script() -> void:
	# The swimmer is on screen 0. Put a pellet right on it and run one game tick of the playfield.
	var foe := _world.original.foes[DevCreatures.SWIMMER]
	var ink_script := foe.vm.script_ink
	assert_int(ink_script).is_not_equal(foe.vm.pc)
	_fire()
	var pellet := _live_pellets()[0]
	_put_on(pellet, foe)
	_sounds.clear()
	_world.check_contacts()
	assert_bool(foe.vm.interrupted).is_true()
	assert_int(foe.vm.pc).is_equal(ink_script)
	assert_bool(pellet.is_flying()).is_false()
	assert_array(_sounds).is_equal([SimWorld.SFX_INK_SPLASH])


# --- the sub never touches its own pellets ------------------------------------------
# The original has no pellet-vs-sub test at all: StunGunX / StunGunY (0x44b04c / 0x44b054) are only read by
# StartStunGun (spawn), UpdateStunGun (motion) and update_animals (pellet vs creature rectangles).


## Open water without creatures, so that only the sub and its pellet are in the world.
func _remove_foes() -> void:
	for foe in _world.original.foes:
		foe.free()
	_world.original.foes.clear()
	_world.sim.foes.clear()


## The keys held in the next ticks (a test fills the snapshot itself: no keyboard involved).
var _steer := Vector2i.ZERO


func _hold(action: StringName) -> void:
	match action:
		&"sub_left": _steer.x = -1
		&"sub_right": _steer.x = 1
		&"sub_up": _steer.y = -1
		&"sub_down": _steer.y = 1


func _release_all() -> void:
	_steer = Vector2i.ZERO


func _keys() -> InputSnapshot:
	return InputSnapshot.steering(_steer.x, _steer.y)


func test_pellet_has_no_physics_presence() -> void:
	_fire()
	var node := _world.original.pellets.get_child(0)
	assert_bool(node is CollisionObject2D).is_false()      # not an Area2D: the sub (and the creatures) cannot touch it by physics
	assert_bool(_live_pellets()[0] is RefCounted).is_true()    # and the pellet of the rules is no node at all


func test_sub_at_full_speed_in_the_fire_direction_ignores_its_own_pellet() -> void:
	_remove_foes()
	var sub := _world.sim.sub
	sub.place_original(68, 66, 6)
	_hold(&"sub_right")
	for i in 20:                                            # reach max speed (128 units = 16 px/tick)
		sub.logic_tick(_keys())
		if sub.velocity_units.x >= sub.tuning.max_speed_x_units:
			break
	assert_int(sub.velocity_units.x).is_equal(sub.tuning.max_speed_x_units)
	_sounds.clear()
	var oxygen := GameState.oxygen()
	_fire()
	var pellet := _live_pellets()[0]
	# The scenario is a real geometric overlap: the muzzle lies inside the sub's collision rectangle.
	var pellet_window := Rect2i(Vector2i(pellet.position) + Vector2i(Sub.PLAYFIELD_ORIGIN), Vector2i(16, 16))
	assert_bool(pellet_window.intersects(sub.hurt_rect_window())).is_true()
	for i in 6:
		_world.tick(_keys())                                # (the sub and the pellet are stepped by the world's tick)
		assert_bool(pellet.is_flying()).is_true()
	_release_all()
	assert_array(_sounds).is_equal([SimWorld.SFX_INK_FIRED])      # no hit sound, no splash sound
	assert_int(GameState.oxygen()).is_equal(oxygen)
	assert_bool(sub.is_invulnerable()).is_false()
	assert_int(_live_pellets().size()).is_equal(1)


func test_sub_flying_up_faster_than_the_pellet_drifts_ignores_its_own_pellet() -> void:
	# Cell 7 (nose up): the pellet drifts up only 6 px/tick while the sub can climb 12 px/tick, so the sub
	# sweeps through the pellet's row. Nothing may happen.
	_remove_foes()
	var sub := _world.sim.sub
	sub.place_original(120, 200, 7)
	_hold(&"sub_up")
	_hold(&"sub_right")
	for i in 20:
		sub.logic_tick(_keys())
		if sub.velocity_units.y <= -sub.tuning.max_speed_y_units:
			break
	_sounds.clear()
	_fire()
	var pellet := _live_pellets()[0]
	for i in 4:
		_world.tick(_keys())                                # (the sub and the pellet are stepped by the world's tick)
		assert_bool(pellet.is_flying()).is_true()
	_release_all()
	assert_array(_sounds).is_equal([SimWorld.SFX_INK_FIRED])
	assert_bool(sub.is_invulnerable()).is_false()


# --- pellet vs creature, the rule of update_animals (0x41ed0c) --------------------------

func _inked(foe: Foe) -> bool:
	return foe.vm.interrupted and foe.vm.pc == foe.vm.script_ink


func test_pellets_ink_harmless_and_friendly_creatures_too() -> void:
	# The original's pellet test never looks at the damage byte.
	for damage in [0, -1, 3]:
		_world.load_sector(DevCreatures.ARENA, 0)
		_world.foes_active = false
		var foe := _world.original.foes[DevCreatures.SWIMMER]
		foe.vm.damage = damage
		_fire()
		var pellet := _live_pellets()[0]
		_put_on(pellet, foe)
		_world.check_contacts()
		assert_bool(_inked(foe)).is_true()
		assert_bool(pellet.is_flying()).is_false()
		for p in _live_pellets():
			_drop(p)


func test_a_creature_touching_the_sub_is_not_tested_against_pellets() -> void:
	var foe := _world.original.foes[DevCreatures.SWIMMER]
	foe.vm.damage = 0                                   # (no air lost either way)
	_fire()
	var pellet := _live_pellets()[0]
	_put_on(pellet, foe)
	_put_sub_on(foe)
	_sounds.clear()
	_world.check_contacts()
	# The creature touches the sub, so it ran its CONTACT script, and the pellet flew on without a splash sound.
	assert_bool(_inked(foe)).is_false()
	assert_bool(pellet.is_flying()).is_true()
	assert_array(_sounds).is_empty()


func test_the_same_pellet_does_ink_the_creature_when_the_sub_is_away() -> void:
	var foe := _world.original.foes[DevCreatures.SWIMMER]
	_fire()
	var pellet := _live_pellets()[0]
	_put_on(pellet, foe)
	_world.original.sub.place_original(68, 66, 6)                # far from the swimmer
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), foe.model.hit_rect_window())).is_false()
	_world.check_contacts()
	assert_bool(_inked(foe)).is_true()


func test_a_creature_busy_with_an_interrupt_script_is_skipped_and_a_second_pellet_flies_through() -> void:
	var foe := _world.original.foes[DevCreatures.SWIMMER]
	_fire()
	_fire()
	var first := _live_pellets()[0]
	var second := _live_pellets()[1]
	_put_on(first, foe)
	_put_on(second, foe)
	_world.check_contacts()
	assert_bool(_inked(foe)).is_true()
	assert_bool(first.is_flying()).is_false()           # the first slot takes it ...
	assert_bool(second.is_flying()).is_true()           # ... the creature is busy now: the other one flies through
	_world.check_contacts()
	assert_bool(second.is_flying()).is_true()


func test_hidden_creatures_are_skipped() -> void:
	var foe := _world.original.foes[DevCreatures.SWIMMER]
	foe.vm.hidden = true
	foe.refresh(true)
	_fire()
	var pellet := _live_pellets()[0]
	_put_on(pellet, foe)
	_world.check_contacts()
	assert_bool(foe.vm.interrupted).is_false()
	assert_bool(pellet.is_flying()).is_true()


func test_a_splashing_pellet_does_not_ink_creatures() -> void:
	var foe := _world.original.foes[DevCreatures.SWIMMER]
	_world.sim.sub.cell = 4                                 # facing the viewer: the pellet splashes at once
	_fire()
	var pellet := _live_pellets()[0]
	assert_bool(pellet.is_flying()).is_false()
	_put_on(pellet, foe)
	_world.check_contacts()
	assert_bool(foe.vm.interrupted).is_false()
