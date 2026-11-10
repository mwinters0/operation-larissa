class_name TestTuning
extends GdUnitTestSuite
## Teaches: the values the rules run on are DATA, resolved ONCE by the run that uses them. The project's `data/rules/tuning.json` is the lowest layer
## and a pack's `rules/tuning.json` lies over it key by key (this test lays one more file over them with `Tuning.extra_files`); the run resolves it
## when it begins (`GameState.begin_run`) and the rules ask the run, never the file. So the base file must give the original's numbers exactly (pinned
## below, each one a number that used to be a constant or the field of `sub_tuning.tres`), a layer must change what it names and nothing else, and a
## sim made BEFORE a run began must still play by the numbers of the run (no copy that outlives the run it was made for).

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const PACK_FILE := "user://test_tuning_pack.json"
const OTHER_FILE := "user://test_tuning_other.json"

## A file that changes some of them: more air and ink, a slower sub, a longer trigger countdown, a slower lock, a lower script limit.
const PACK := {
	"sub": {"max_speed_x_units": 64, "bubble_ticks": 4, "wall_box": [0, 0, 70, 30]},
	"air": {"max_oxygen": 6},
	"ink": {"max": 30, "in_flight_max": 4},
	"sector": {"midpoint_screen": 8, "pending_ticks": 12},
	"lock_wheel": {"key_window_ticks": 20},
	"creatures": {"max_instructions_per_tick": 100},
}


func after_test() -> void:
	Tuning.extra_files = []
	for path in [PACK_FILE, OTHER_FILE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	GameState.reset()


## Lays `layer` (a Dictionary, written as the JSON file it would be) over the project's tuning, as one more file.
func _mount(layer: Dictionary = PACK, path: String = PACK_FILE) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(layer))
	file.close()
	var files := Tuning.extra_files.duplicate()
	files.append(path)
	Tuning.extra_files = files


func _new_run() -> Node:
	return auto_free(load(GAME_STATE_SCRIPT).new()) as Node          # the script of the autoload, not in any tree


## Every value of a tuning as plain data (the sub's section included), to compare two tunings field by field.
func _flat(tuning: Tuning) -> Dictionary:
	var flat := {}
	for property in tuning.get_script().get_script_property_list():
		var name: String = property["name"]
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			flat[name] = _flat_sub(tuning.sub) if name == "sub" else tuning.get(name)
	return flat


func _flat_sub(sub: SubTuning) -> Dictionary:
	var flat := {}
	for property in sub.get_script().get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			flat[property["name"]] = sub.get(property["name"])
	return flat


# --- the base game ------------------------------------------------------------------------------------

func test_no_moved_rule_value_is_a_constant_in_code() -> void:
	var names := ["INK_MAX", "MAX_OXYGEN", "MAX_TANKS", "MIDPOINT_SCREEN", "PENDING_TICKS", "CANISTER_PENDING_TICKS", "BUBBLE_TICKS",
			"MAX_INSTRUCTIONS_PER_TICK", "TICKS_PER_POSITION", "KEY_WINDOW_TICKS", "MAX_PASSES", "MOTION_TICKS", "TICKS_PER_LABEL",
			"TICKS_PER_REVOLUTION", "LAST_SUBSTEP_START"]
	var found := SourceScan.find_in(SourceScan.scripts_under("res://src"), names)
	found.append_array(SourceScan.find_in(SourceScan.scripts_under("res://addons/screen_editor"), names))
	found.append_array(SourceScan.find_in(SourceScan.scripts_under("res://addons/sector_editor"), names))
	assert_array(found).override_failure_message("a rule value is a constant again:\n" + "\n".join(found)).is_empty()


func test_the_base_file_is_the_originals_numbers() -> void:
	var t := Tuning.original()
	assert_int(t.max_oxygen).is_equal(4)
	assert_int(t.max_tanks).is_equal(6)
	assert_int(t.refill_tanks).is_equal(2)
	assert_int(t.ink_max).is_equal(21)
	assert_int(t.ink_in_flight_max).is_equal(2)
	assert_int(t.midpoint_screen).is_equal(6)
	assert_int(t.pending_ticks).is_equal(36)
	assert_int(t.canister_pending_ticks).is_equal(2)
	assert_int(t.lock_ticks_per_position).is_equal(9)
	assert_int(t.lock_key_window_ticks).is_equal(73)
	assert_int(t.lock_max_passes).is_equal(2)
	assert_int(t.max_instructions_per_tick).is_equal(512)
	assert_int(t.sub.bubble_ticks).is_equal(8)


## What `data/sub_tuning.tres` held, copied from it before the file went.
func test_the_subs_tables_are_what_the_sub_tuning_resource_held() -> void:
	var s := Tuning.original().sub
	assert_float(s.tick_hz).is_equal_approx(12.166667, 0.000001)
	assert_array([s.max_speed_x_units, s.max_speed_y_units, s.accel_units, s.decay_units]).is_equal([128, 96, 12, 6])
	assert_array(s.frame_rects).is_equal([Rect2i(10, 14, 80, 28), Rect2i(4, 16, 82, 28), Rect2i(2, 14, 92, 28), Rect2i(6, 14, 72, 28),
			Rect2i(26, 14, 44, 28), Rect2i(16, 14, 72, 28), Rect2i(0, 14, 92, 28), Rect2i(8, 16, 82, 28), Rect2i(4, 14, 80, 28)])
	assert_that(s.wall_box).is_equal(Rect2i(8, 10, 80, 32))
	assert_that(s.sprite_size).is_equal(Vector2i(96, 54))
	assert_that(s.current_probe).is_equal(Vector2i(0, 2))
	assert_array(s.cell_pictures).is_equal(PackedInt32Array([7, 6, 5, 4, 3, 2, 1, 1, 0, 0, 1, 1, 2, 3, 4, 5, 6, 7]))
	assert_array(s.cell_after_left).is_equal(PackedInt32Array([0, 1, 2, 2, 3, 4, 5, 5, 5]))
	assert_array(s.cell_after_right).is_equal(PackedInt32Array([3, 3, 3, 4, 5, 6, 6, 7, 8]))
	assert_array(s.cell_after_down).is_equal(PackedInt32Array([0, 2, 0, 3, 4, 5, 8, 6, 8]))
	assert_array(s.cell_after_up).is_equal(PackedInt32Array([2, 1, 1, 3, 4, 5, 7, 7, 6]))
	assert_array(s.cell_after_level).is_equal(PackedInt32Array([2, 2, 2, 3, 4, 5, 6, 6, 6]))
	assert_array([s.invulnerability_ticks, s.blink_ticks]).is_equal([30, 22])
	assert_array(s.ink_spawn_dx).is_equal(PackedInt32Array([4, 0, 0, 0, 40, 76, 76, 72, 72]))
	assert_array(s.ink_spawn_dy).is_equal(PackedInt32Array([26, 14, 16, 16, 16, 16, 16, 14, 26]))
	assert_array(s.ink_direction).is_equal(PackedInt32Array([0, 1, 2, 2, 3, 4, 4, 5, 6]))
	assert_array(s.ink_step_dx).is_equal(PackedInt32Array([-8, -8, -8, 0, 8, 8, 8]))
	assert_array(s.ink_step_dy).is_equal(PackedInt32Array([2, -2, 0, 0, 0, -2, 2]))
	assert_int(s.ink_steps_per_tick).is_equal(3)
	assert_array(s.ink_splash_dx).is_equal(PackedInt32Array([0, -4, -16, -28, -28]))
	assert_array(s.ink_splash_dy).is_equal(PackedInt32Array([0, -4, -12, -20, -20]))
	assert_array(s.hit_bubble_x_by_cell).is_equal(PackedInt32Array([4, 4, 4, 4, 16, 16, 16, 16, 16]))
	assert_array(s.light_cells).is_equal(PackedInt32Array([0, 1, 2, 6, 7, 8]))
	assert_array(s.light_dx_by_cell).is_equal(PackedInt32Array([46, 46, 46, 0, 0, 0, 34, 33, 35]))
	assert_array(s.light_dy_by_cell).is_equal(PackedInt32Array([0, 3, 0, 0, 0, 0, 0, 3, 0]))


func test_the_project_file_is_the_lowest_layer() -> void:
	assert_str(Tuning.files()[0]).is_equal(Tuning.BASE_PATH)
	var found := Tuning.files()
	Tuning.extra_files = []
	assert_array(Tuning.files()).is_equal(found)


# --- another pack ---------------------------------------------------------------------------------------

func test_a_file_laid_over_changes_what_it_names_and_keeps_the_rest() -> void:
	var base := Tuning.resolve()                                          # (the chain's, whatever pack that is: the layer below the test's file)
	_mount()
	var t := Tuning.resolve()
	assert_int(t.sub.max_speed_x_units).is_equal(64)
	assert_int(t.sub.bubble_ticks).is_equal(4)
	assert_that(t.sub.wall_box).is_equal(Rect2i(0, 0, 70, 30))
	assert_int(t.max_oxygen).is_equal(6)
	assert_int(t.ink_max).is_equal(30)
	assert_int(t.ink_in_flight_max).is_equal(4)
	assert_int(t.midpoint_screen).is_equal(8)
	assert_int(t.pending_ticks).is_equal(12)
	assert_int(t.lock_key_window_ticks).is_equal(20)
	assert_int(t.max_instructions_per_tick).is_equal(100)
	# (not in the file: the layer below's)
	assert_int(t.sub.max_speed_y_units).is_equal(base.sub.max_speed_y_units)
	assert_array(t.sub.frame_rects).is_equal(base.sub.frame_rects)
	assert_int(t.max_tanks).is_equal(base.max_tanks)
	assert_int(t.canister_pending_ticks).is_equal(base.canister_pending_ticks)
	assert_int(t.lock_ticks_per_position).is_equal(base.lock_ticks_per_position)
	assert_int(t.lock_max_passes).is_equal(base.lock_max_passes)
	assert_int(Tuning.original().max_oxygen).is_equal(4)                 # (the project's file alone is still the original's)


func test_extra_files_are_laid_in_order_and_the_last_has_the_last_word() -> void:
	_mount({"air": {"max_oxygen": 5, "max_tanks": 7}})
	_mount({"air": {"max_oxygen": 6}}, OTHER_FILE)
	var t := Tuning.resolve()
	assert_int(t.max_oxygen).is_equal(6)
	assert_int(t.max_tanks).is_equal(7)
	assert_array(Tuning.files().slice(-2)).is_equal([PACK_FILE, OTHER_FILE])


# --- the run owns it ------------------------------------------------------------------------------------

func test_a_run_resolves_its_tuning_when_it_begins() -> void:
	var run := _new_run()
	var chain := Tuning.resolve()
	_mount()
	assert_int(run.tuning.ink_max).is_equal(21)                          # (a state before any run has the original's)
	run.begin_run()
	assert_int(run.tuning.ink_max).is_equal(30)
	assert_int(run.ink).is_equal(30)
	assert_int(run.oxygen_model.max_oxygen).is_equal(6)
	assert_int(run.oxygen()).is_equal(6)
	run.update_oxygen(-3)
	run.update_oxygen(3)
	assert_int(run.oxygen()).is_equal(6)                                 # a full tank is the run's
	run.ink = 2
	run.refill_ink()
	assert_int(run.ink).is_equal(30)
	Tuning.extra_files = []
	assert_int(run.tuning.ink_max).is_equal(30)                          # (resolved once: the run keeps what it began with)
	run.begin_run()
	assert_int(run.tuning.ink_max).is_equal(chain.ink_max)


func test_a_saved_game_is_held_to_the_limits_of_the_run_it_enters() -> void:
	var run := _new_run()
	var player := PlayerProfile.new_player("Tuning", PlayerProfile.Game.VOYAGER)
	var chain := Tuning.resolve()
	player.tanks = 99
	player.oxygen = 99
	player.ink = 99
	assert_int(player.ink).is_equal(99)                                   # (the profile holds no limit of its own)
	run.begin_run(player)
	assert_array([run.tanks(), run.oxygen(), run.ink]).is_equal([chain.max_tanks, chain.max_oxygen, chain.ink_max])
	_mount()
	run.begin_run(player)
	assert_array([run.tanks(), run.oxygen(), run.ink]).is_equal([chain.max_tanks, 6, 30])


func test_a_new_player_begins_with_the_runs_supply() -> void:
	var run := _new_run()
	var player := PlayerProfile.new_player("Tuning", PlayerProfile.Game.VOYAGER)
	assert_array([player.tanks, player.oxygen, player.ink]).is_equal([PlayerProfile.NEW_SUPPLY, PlayerProfile.NEW_SUPPLY, PlayerProfile.NEW_SUPPLY])
	_mount()
	run.begin_run(player)
	assert_array([run.tanks(), run.oxygen(), run.ink]).is_equal([run.tuning.refill_tanks, 6, 30])
	run.capture_profile()
	assert_int(player.ink).is_equal(30)


func test_a_sim_made_before_the_run_began_plays_by_the_numbers_of_the_run() -> void:
	var run := _new_run()
	var sim := SimWorld.new(run)
	var chain := Tuning.resolve()
	assert_int(sim.sub.tuning.max_speed_x_units).is_equal(Tuning.original().sub.max_speed_x_units)      # (a run not begun holds the original's)
	_mount()
	run.begin_run()
	sim.load_sector(DevCreatures.ARENA, 0)
	assert_object(sim.sub.tuning).is_same(run.tuning.sub)
	assert_int(sim.sub.tuning.max_speed_x_units).is_equal(64)
	assert_int(sim.foe_context.max_instructions).is_equal(100)
	sim.start_flight()
	assert_int(sim.sub.tuning.ink_steps_per_tick).is_equal(chain.sub.ink_steps_per_tick)
	assert_int(run.tuning.ink_in_flight_max).is_equal(4)
	# and a later run is followed by the next load, whatever the sim was made on
	Tuning.extra_files = []
	run.begin_run()
	sim.load_sector(DevCreatures.ARENA, 0)
	assert_object(sim.sub.tuning).is_same(run.tuning.sub)
	assert_int(sim.sub.tuning.max_speed_x_units).is_equal(chain.sub.max_speed_x_units)
	assert_int(sim.foe_context.max_instructions).is_equal(chain.max_instructions_per_tick)


func test_the_sim_reads_the_countdown_and_the_midpoint_screen_from_the_run() -> void:
	_mount()
	var run := _new_run()
	run.begin_run()
	var sim := SimWorld.new(run)
	sim.begin_sector(DevCreatures.ARENA, true)
	assert_int(sim.screen_index).is_equal(8)                              # the respawn point is on the run's midpoint screen
	assert_bool(run.midpoint_reached).is_true()


func test_the_creature_context_takes_its_limit_from_the_tuning_it_is_given() -> void:
	_mount()
	var t := Tuning.resolve()
	var context := FoeVM.Context.new(t)
	assert_int(context.max_instructions).is_equal(100)
	assert_int(FoeVM.Context.new().max_instructions).is_equal(Tuning.original().max_instructions_per_tick)       # (no tuning given: the original's)


func test_the_lock_wheel_waits_are_the_runs() -> void:
	_mount()
	var wheel := LockWheel.new(7, Tuning.resolve())
	assert_int(wheel.key_window_ticks).is_equal(20)
	assert_int(wheel.ticks_per_label()).is_equal(wheel.motion_ticks() + 20)
	wheel.advance(wheel.motion_ticks() + 19)
	assert_int(wheel.state).is_equal(LockWheel.State.WAITING)
	wheel.advance(1)                                                      # label 7 is under the arrow at position 4: the window closes unused
	assert_int(wheel.passes).is_equal(1)
