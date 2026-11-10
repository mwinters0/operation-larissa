class_name TestDevRuleValues
extends GdUnitTestSuite
## The dev pack states EVERY rule value with a number of its own (`rules/tuning.json`, written by `tools/dev_pack/dev_rules.py`), and the engine tests run on it. So a
## rule that still reads the original's number instead of the run's fails here (or in the test that assumed it). This suite pins both halves: the
## dev layer is complete, clean and different from the original's on every key it states, and each value REACHES the code that uses it, through the
## game's own entries (`GameState.begin_run`, `SimWorld.load_sector`, `ProblemScreen.start`), not through a part built on a hand-made tuning.
##
## Teaches: proving that data is read, by giving every datum a value that cannot be mistaken for the default. A new rule value in the project's file
## fails `test_the_dev_layer_states_every_value_of_the_base` until the dev generator states it (or this file says why not), and a value stated
## but read from the wrong place fails the test of its reader.

## Keys of the project's file that the dev layer leaves out, and why. Everything else must be stated.
const OMITTED: Dictionary[String, String] = {
	"sub.frame_rects": "a table by sprite cell: the cells of dev's sub are drawn at the original's sizes (a layer states only what it changes)",
	"sub.sprite_size": "the size of the sub's picture, which dev draws at the original's size",
	"sub.current_probe": "where under the sub the current is read, a point of the picture",
	"sub.cell_pictures": "a table by the 18 picture slots of the sprite sheet, which dev draws as the original's",
	"sub.cell_after_left": "the cell transition tables: the sub's turning, a table by cell",
	"sub.cell_after_right": "the cell transition tables: the sub's turning, a table by cell",
	"sub.cell_after_down": "the cell transition tables: the sub's turning, a table by cell",
	"sub.cell_after_up": "the cell transition tables: the sub's turning, a table by cell",
	"sub.cell_after_level": "the cell transition tables: the sub's turning, a table by cell",
	"sub.ink_spawn_dx": "where a pellet leaves the sub, by cell: points of the picture",
	"sub.ink_spawn_dy": "where a pellet leaves the sub, by cell: points of the picture",
	"sub.ink_direction": "the direction code of a pellet by cell: a table of the sprite sheet",
	"sub.ink_step_dx": "the step of a pellet by direction code: a table the sprite sheet's cells index",
	"sub.ink_step_dy": "the step of a pellet by direction code: a table the sprite sheet's cells index",
	"sub.ink_splash_dx": "where the splash pictures sit: points of the pictures",
	"sub.ink_splash_dy": "where the splash pictures sit: points of the pictures",
	"sub.hit_bubble_x_by_cell": "where the hit bubbles sit, by cell: points of the picture",
	"sub.light_cells": "which cells show the message light: a table of the sprite sheet",
	"sub.light_dx_by_cell": "where the message light sits, by cell: points of the picture",
	"sub.light_dy_by_cell": "where the message light sits, by cell: points of the picture",
}

## The member of `Tuning` (or of `SubTuning` for a `sub.` key, the key's own name) that each stated key becomes.
const MEMBERS: Dictionary[String, String] = {
	"air.max_oxygen": "max_oxygen", "air.max_tanks": "max_tanks", "air.refill_tanks": "refill_tanks",
	"ink.max": "ink_max", "ink.in_flight_max": "ink_in_flight_max",
	"sector.midpoint_screen": "midpoint_screen", "sector.pending_ticks": "pending_ticks", "sector.canister_pending_ticks": "canister_pending_ticks",
	"lock_wheel.ticks_per_position": "lock_ticks_per_position", "lock_wheel.key_window_ticks": "lock_key_window_ticks",
	"lock_wheel.max_passes": "lock_max_passes",
	"creatures.max_instructions_per_tick": "max_instructions_per_tick",
}

const SCREEN_SCENE := "res://src/problems/problem_screen.tscn"

var _dev: Tuning


func before_test() -> void:
	GameClock.paused = false
	GameState.reset()
	_dev = GameState.tuning


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


# --- the file ---------------------------------------------------------------------------------------------

## The flat `section.key` -> value of a parsed tuning file (notes, the keys that begin with an underscore, are skipped).
func _leaves(file: Dictionary) -> Dictionary:
	var found := {}
	for section: String in file:
		if section.begins_with("_"):
			continue
		for key: String in file[section]:
			if not key.begins_with("_"):
				found["%s.%s" % [section, key]] = file[section][key]
	return found


## The dev pack's `rules/tuning.json` (the last layer of the chain the tests run on), parsed.
func _layer() -> Dictionary:
	var path := ""
	for file in Tuning.files():
		if file != Tuning.BASE_PATH and file.ends_with("/" + Tuning.PACK_PATH):
			path = file
	assert_str(path).override_failure_message("the chain the engine tests run on has no %s" % Tuning.PACK_PATH).is_not_empty()
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _base() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Tuning.BASE_PATH))


## The value of the member that the key `section.key` becomes, in `tuning`.
func _member(tuning: Tuning, key: String) -> Variant:
	if key.begins_with("sub."):
		return tuning.sub.get(key.trim_prefix("sub."))
	assert_bool(MEMBERS.has(key)).override_failure_message("%s is stated by the dev layer, but this test does not know the member it becomes: add it to MEMBERS" % key).is_true()
	return tuning.get(MEMBERS[key])


func test_the_dev_layer_passes_the_check_with_no_error_and_no_warning() -> void:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	Tuning.check(_layer(), errors, warnings)
	assert_array(errors).override_failure_message("errors: %s" % [errors]).is_empty()
	assert_array(warnings).override_failure_message("warnings: %s" % [warnings]).is_empty()


func test_the_dev_layer_states_every_value_of_the_base() -> void:
	var stated := _leaves(_layer())
	var missing: Array[String] = []
	for key: String in _leaves(_base()):
		if not stated.has(key) and not OMITTED.has(key):
			missing.append(key)
	assert_array(missing).override_failure_message("the dev layer (tools/dev_pack/dev_rules.py) must give these an override of their own, or OMITTED here must say why not: %s" % [missing]).is_empty()
	for key: String in OMITTED:
		assert_bool(_leaves(_base()).has(key)).override_failure_message("OMITTED names %s, which the project's file lacks" % key).is_true()
		assert_bool(stated.has(key)).override_failure_message("%s is stated by the dev layer: take it off OMITTED" % key).is_false()


func test_every_value_the_dev_layer_states_differs_from_the_originals() -> void:
	var base := _leaves(_base())
	var original := Tuning.original()
	var dev := Tuning.resolve()
	var same: Array[String] = []
	var stated := _leaves(_layer())
	assert_int(stated.size()).is_greater(20)
	for key: String in stated:
		assert_bool(base.has(key)).override_failure_message("the dev layer states %s, which the project's file lacks" % key).is_true()
		if _member(dev, key) == _member(original, key):
			same.append(key)
	assert_array(same).override_failure_message("the same as the original's: %s" % [same]).is_empty()


func test_the_engine_tests_run_on_the_dev_values() -> void:
	assert_object(GameState.tuning).is_not_same(Tuning.original())
	assert_int(GameState.tuning.max_oxygen).is_equal(Tuning.resolve().max_oxygen)
	assert_int(GameState.tuning.max_oxygen).is_not_equal(Tuning.original().max_oxygen)


# --- the air and the ink -----------------------------------------------------------------------------------

func test_the_oxygen_model_is_made_with_the_dev_limits() -> void:
	assert_int(GameState.oxygen_model.max_oxygen).is_equal(_dev.max_oxygen)
	assert_int(GameState.oxygen()).is_equal(_dev.max_oxygen)
	GameState.update_oxygen(-1)
	GameState.update_oxygen(1)                                            # Zoom's tank: refills the air up to the limit
	assert_int(GameState.oxygen()).is_equal(_dev.max_oxygen)
	for i in 3 * _dev.max_tanks:                                          # a full tank gives a spare tank: up to the limit
		GameState.update_oxygen(1)
	assert_int(GameState.tanks()).is_equal(_dev.max_tanks)


func test_a_new_player_and_a_refill_have_the_dev_spare_tanks() -> void:
	GameState.begin_run(PlayerProfile.new_player("Dev", PlayerProfile.Game.VOYAGER))
	assert_int(GameState.tanks()).is_equal(_dev.refill_tanks)
	GameState.oxygen_model.tanks = 0
	GameState.update_oxygen(3)                                            # a supply station: at least the dev number of spare tanks
	assert_int(GameState.tanks()).is_equal(_dev.refill_tanks)


func test_the_ink_supply_is_the_dev_maximum() -> void:
	assert_int(GameState.ink).is_equal(_dev.ink_max)
	GameState.fire_ink()
	GameState.fire_ink()
	GameState.refill_ink()
	assert_int(GameState.ink).is_equal(_dev.ink_max)


func test_a_saved_record_is_held_to_the_dev_limits() -> void:
	var player := PlayerProfile.new_player("Dev", PlayerProfile.Game.VOYAGER)
	player.tanks = 99
	player.oxygen = 99
	player.ink = 99
	GameState.begin_run(player)
	assert_array([GameState.tanks(), GameState.oxygen(), GameState.ink]).is_equal([_dev.max_tanks, _dev.max_oxygen, _dev.ink_max])


# --- the sector --------------------------------------------------------------------------------------------

## A sim on the run, with the sub flying in open water of the arena.
func _sim() -> SimWorld:
	var sim := SimWorld.new(GameState)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(68, 66, 6)
	sim.foes_active = false
	sim.tile_grid.clear()
	return sim


func test_the_respawn_is_on_the_dev_midpoint_screen() -> void:
	var sim := SimWorld.new(GameState)
	sim.begin_sector(DevCreatures.ARENA, true)
	assert_int(sim.screen_index).is_equal(_dev.midpoint_screen)
	assert_bool(GameState.midpoint_reached).is_true()


func test_the_midpoint_is_reached_on_the_dev_screen_with_the_pieces_before_it() -> void:
	var sector := Catalog.sector(0)
	GameState.screen_entered(_dev.midpoint_screen - 1, sector)
	for i in sector.pieces.size():
		GameState.collect_piece(i)
	GameState.update_midpoint(sector)
	assert_bool(GameState.past_midpoint).is_false()                       # (one screen short of it)
	GameState.screen_entered(_dev.midpoint_screen, sector)
	GameState.update_midpoint(sector)
	assert_bool(GameState.past_midpoint).is_true()


## Ticks the sim until it asks for a problem; how many ticks that took (0: it never did, within a minute).
func _ticks_until_a_problem(sim: SimWorld) -> int:
	var asked: Array[int] = []
	sim.problem_requested.connect(func(slot: int) -> void: asked.append(slot))
	var ticks := 0
	while asked.is_empty() and ticks < 1000:
		sim.tick()
		ticks += 1
	return ticks if not asked.is_empty() else 0


func test_a_math_trigger_counts_down_the_dev_ticks() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(0, 5)                                                 # the dev tour's first sector: a trigger on screen 5
	sim.start_flight(68, 66, 6)
	sim.foes_active = false
	sim.touch_trigger(sim.triggers_on_screen(5)[0])
	assert_int(sim.pending_ticks).is_equal(_dev.pending_ticks)
	assert_int(_ticks_until_a_problem(sim)).is_equal(_dev.pending_ticks - 1)        # the problem opens when the countdown has run to 1


func test_the_data_canister_counts_down_the_dev_ticks() -> void:
	var sim := SimWorld.new(GameState)
	sim.load_sector(0, 3)
	sim.start_flight(68, 66, 6)
	sim.foes_active = false
	sim.take_piece(0)
	assert_int(sim.pending_ticks).is_equal(_dev.canister_pending_ticks)
	assert_int(_ticks_until_a_problem(sim)).is_equal(_dev.canister_pending_ticks - 1)


func test_no_more_pellets_fly_than_the_dev_limit() -> void:
	var sim := _sim()
	for i in _dev.ink_in_flight_max + 2:
		sim.request_fire()
	assert_int(sim.pellets.size()).is_equal(_dev.ink_in_flight_max)
	assert_int(GameState.ink).is_equal(_dev.ink_max - _dev.ink_in_flight_max)


func test_a_pellet_takes_the_dev_number_of_steps_a_tick() -> void:
	var sim := _sim()
	sim.request_fire()
	var pellet := sim.pellets[0]
	var before := pellet.position
	pellet.logic_tick()
	var step := _dev.sub.pellet_step(6)                                   # the sub faces right
	assert_that(pellet.position - before).is_equal(Vector2(step * _dev.sub.ink_steps_per_tick))
	assert_int(_dev.sub.ink_steps_per_tick).is_not_equal(Tuning.original().sub.ink_steps_per_tick)


# --- the sub -----------------------------------------------------------------------------------------------

func test_the_sub_accelerates_and_tops_out_by_the_dev_numbers() -> void:
	var sim := _sim()
	var sub := sim.sub
	assert_object(sub.tuning).is_same(_dev.sub)
	sub.velocity_units = Vector2i.ZERO
	sub.logic_tick(InputSnapshot.steering(1, 1))
	assert_that(sub.velocity_units).is_equal(Vector2i(_dev.sub.accel_units, _dev.sub.accel_units))
	for i in 40:
		sub.logic_tick(InputSnapshot.steering(1, 1))
	assert_that(sub.velocity_units).is_equal(Vector2i(_dev.sub.max_speed_x_units, _dev.sub.max_speed_y_units))
	sub.logic_tick()                                                      # no key: the speed decays
	assert_that(sub.velocity_units).is_equal(Vector2i(_dev.sub.max_speed_x_units - _dev.sub.decay_units, _dev.sub.max_speed_y_units - _dev.sub.decay_units))


func test_the_dev_clock_converts_the_speed_to_pixels_per_second() -> void:
	var sim := _sim()
	var sub := sim.sub
	sub.velocity_units = Vector2i(_dev.sub.max_speed_x_units, 0)
	assert_float(sub.velocity_px_per_s().x).is_equal_approx(_dev.sub.max_speed_x_units * _dev.sub.tick_hz / 8.0, 0.001)


func test_the_hit_protects_for_the_dev_ticks_with_bubbles_and_a_blink() -> void:
	var sim := _sim()
	var sub := sim.sub
	sub.start_invulnerability()
	assert_int(sub.invulnerability).is_equal(_dev.sub.invulnerability_ticks)
	var bubbles := 0
	var blinks := 0
	var protected := 0
	while sub.is_invulnerable() and protected < 1000:
		bubbles += 1 if sub.bubble_picture() >= 0 else 0
		blinks += 1 if sub.is_blinking() else 0
		protected += 1
		sub.logic_tick()
	assert_array([protected, bubbles, blinks]).is_equal([_dev.sub.invulnerability_ticks, _dev.sub.bubble_ticks, _dev.sub.blink_ticks])


func test_the_sub_stops_against_a_wall_by_the_dev_wall_box() -> void:
	var sim := _sim()
	var column := 25
	for row in 18:
		sim.tile_grid.set_byte(column, row, TileCodec.SOLID_BIT | 1)
	for i in 80:
		sim.sub.logic_tick(InputSnapshot.steering(1, 0))
	var box := _dev.sub.wall_box
	assert_int(sim.sub.original_position().x).is_equal(16 * column + 16 - box.end.x)
	assert_int(sim.sub.velocity_units.x).is_equal(0)
	assert_bool(box != Tuning.original().sub.wall_box).is_true()


# --- the creatures -----------------------------------------------------------------------------------------

func test_a_creature_script_is_stopped_after_the_dev_number_of_instructions() -> void:
	var sim := _sim()
	assert_int(sim.foe_context.max_instructions).is_equal(_dev.max_instructions_per_tick)
	var data := FoeData.new()
	data.frame_max = 255
	data.pos = Vector2i(100, 50)
	var vm := FoeVM.new()
	vm.setup(data, PackedByteArray([FoeOps.Op.JMP, 253, 255]), 0)         # jumps to itself, never yields
	vm.tick(sim.foe_context)
	assert_str(vm.fault).contains("more than %d instructions" % _dev.max_instructions_per_tick)


# --- the combination lock ----------------------------------------------------------------------------------

func test_the_lock_wheel_takes_the_dev_waits_as_the_problem_screen_builds_it() -> void:
	var screen := scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	screen.start(ProblemFactory.make(0, 0, null, 0))                       # the lock is the problem screen's own, handed the run's tuning
	if screen.step() == ProblemScreen.Step.INTRO:
		screen.diagram.skip_animation()
	assert_object(screen.lock).is_not_null()
	assert_object(screen.lock.tuning).is_same(GameState.tuning)
	screen.lock.press_key()
	for i in 3000:
		if screen.lock.phase == CombinationLock.Phase.ANSWER:
			break
		screen.lock.advance_ticks(1)
	var wheel := screen.lock.answer_wheel
	assert_int(wheel.ticks_per_position).is_equal(_dev.lock_ticks_per_position)
	assert_int(wheel.key_window_ticks).is_equal(_dev.lock_key_window_ticks)
	assert_int(wheel.max_passes).is_equal(_dev.lock_max_passes)
	# the first window to press a key in lasts the dev ticks, and an unused right position may pass the dev number of times
	var window := 0
	for i in 5000:
		if wheel.is_waiting_for_key():
			window += 1
		elif window > 0:
			break
		wheel.advance(1)
	assert_int(window).is_equal(_dev.lock_key_window_ticks)
	for i in 20000:
		if wheel.is_finished():
			break
		wheel.advance(1)
	assert_int(wheel.state).is_equal(LockWheel.State.TIMED_OUT)
	assert_int(wheel.passes).is_equal(_dev.lock_max_passes)
