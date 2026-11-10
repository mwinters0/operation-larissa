class_name TestTankLossDissolve
extends GdUnitTestSuite
## Teaches: testing an animation without looking at it. The pattern is data and arithmetic (`DissolvePattern`), so it is
## checked against a literal transcription of the original's loops (`dissolve` 0x414f81); the bytes of the EXE's tables are
## `legacy/test_creatures_legacy.gd`'s business. The scene part checks the ORDER of events around the dissolve (sound, dissolve,
## respawn) and how long it takes.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _world: SectorWorld
var _events: Array
var _on_tank_lost := func(code: int) -> void: _events.append("tank_lost %d" % code)
var _on_game_over := func() -> void: _events.append("game_over")


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	SectorWorld.skip_animations = false
	_events = []


func after_test() -> void:
	if GameState.tank_lost.is_connected(_on_tank_lost):
		GameState.tank_lost.disconnect(_on_tank_lost)
		GameState.game_over.disconnect(_on_game_over)
	GameClock.paused = false
	GameState.reset()
	SectorWorld.skip_animations = false


## The original's two loops (dissolve 0x414f81), copied line by line: the pass in which every pixel of a `width` x
## `height` box is covered by a 2 x 2 block, FINAL_COPY for the pixels no block reaches.
func _reference_passes(width: int, height: int) -> Array:
	var covered: Array = []
	for y in height:
		var row: Array = []
		row.resize(width)
		row.fill(DissolvePattern.FINAL_COPY)
		covered.append(row)
	for pass_index in 16:
		var local_8 := 0
		while local_8 < height:
			var iVar2: int = -DissolvePattern.ROW_ORDER[local_8 % 16]
			while iVar2 < width - 2:
				var column: int = iVar2 + DissolvePattern.COLUMN_ORDER[pass_index]
				if column >= 0 and column < width - 2:
					for dy in 2:
						for dx in 2:
							if local_8 + dy < height and covered[local_8 + dy][column + dx] == DissolvePattern.FINAL_COPY:
								covered[local_8 + dy][column + dx] = pass_index
				iVar2 += 16
			local_8 += 2
	return covered


# --- the tables and the pattern -------------------------------------------------------------


func test_both_orders_are_permutations_of_0_to_15() -> void:
	var sorted_columns := DissolvePattern.COLUMN_ORDER.duplicate()
	sorted_columns.sort()
	var sorted_rows := DissolvePattern.ROW_ORDER.duplicate()
	sorted_rows.sort()
	assert_array(sorted_columns).is_equal(range(16))
	assert_array(sorted_rows).is_equal(range(16))


func test_every_pixel_changes_in_the_pass_the_original_loops_give_it() -> void:
	for size in [Vector2i(96, 58), Vector2i(80, 58), Vector2i(96, 41), Vector2i(53, 30), Vector2i(17, 7)]:
		var reference := _reference_passes(size.x, size.y)
		for y in size.y:
			for x in size.x:
				assert_int(DissolvePattern.pass_of(x, y, size.x)) \
						.override_failure_message("pixel (%d, %d) of a %s box" % [x, y, size]) \
						.is_equal(reference[y][x])


func test_the_last_column_is_left_to_the_closing_copy_and_nothing_else_is() -> void:
	var left_over := DissolvePattern.pixels_in_step(DissolvePattern.FINAL_COPY, 96, 58)
	assert_int(left_over.size()).is_equal(58)                       # one pixel column x 58 rows
	for pixel in left_over:
		assert_int(pixel.x).is_equal(95)


func test_every_pass_shows_something_new_and_the_first_one_covers_an_eighth() -> void:
	# A 2 x 2 block every 16 pixels covers 2 / 16 of a row, but a block may overlap what an earlier pass did,
	# so the later passes add less than the first (96 * 58 / 8 = 696 pixels).
	var total := 0
	for step in DissolvePattern.PASSES:
		var count := DissolvePattern.pixels_in_step(step, 96, 58).size()
		total += count
		assert_int(count).is_greater(0)
		if step == 0:
			assert_int(count).is_between(600, 760)
	assert_int(total + 58).is_equal(96 * 58)                         # (58 = the last column, left to the closing copy)


func test_a_block_is_two_by_two_and_the_pass_one_pattern_shifts_row_by_row() -> void:
	# Pass 0 has column residue 11: the blocks of the first pair of rows (shift 13) sit at x = 11 - 13 + 16 n = 14, 30, ...
	assert_bool(DissolvePattern.block_in_pass(0, 14, 0, 96)).is_true()
	assert_bool(DissolvePattern.block_in_pass(0, 30, 0, 96)).is_true()
	assert_bool(DissolvePattern.block_in_pass(0, 14, 1, 96)).is_false()     # only even rows start a block
	# the second pair of rows (y = 2, shift 6): x = 11 - 6 = 5, 21 ...
	assert_bool(DissolvePattern.block_in_pass(0, 5, 2, 96)).is_true()
	assert_bool(DissolvePattern.block_in_pass(0, 14, 2, 96)).is_false()
	# The pixels of such a block (2 x 2) all change in that pass.
	for pixel in [Vector2i(14, 0), Vector2i(15, 0), Vector2i(14, 1), Vector2i(15, 1)]:
		assert_int(DissolvePattern.pass_of(pixel.x, pixel.y, 96)).is_equal(0)


func test_the_mask_image_holds_the_pass_of_every_pixel() -> void:
	var mask := DissolvePattern.make_mask(96, 58)
	assert_int(mask.get_width()).is_equal(96)
	assert_int(mask.get_height()).is_equal(58)
	for pixel in [Vector2i(0, 0), Vector2i(14, 0), Vector2i(50, 21), Vector2i(95, 57)]:
		assert_int(roundi(mask.get_pixelv(pixel).r * 255.0)).is_equal(DissolvePattern.pass_of(pixel.x, pixel.y, 96))


# --- the box ---------------------------------------------------------------------------------

func test_the_box_is_the_sub_picture_box_cut_to_the_playfield_window() -> void:
	assert_that(DissolvePattern.box_for(200, 100)).is_equal(Rect2i(200, 100, 96, 58))
	assert_that(DissolvePattern.box_for(16, 32)).is_equal(Rect2i(16, 32, 96, 58))       # exactly at the corner: not cut
	assert_that(DissolvePattern.box_for(-10, 100)).is_equal(Rect2i(16, 100, 70, 58))    # SubX < 16: 96 - (16 - SubX)
	assert_that(DissolvePattern.box_for(528, 100)).is_equal(Rect2i(528, 100, 96, 58))   # the last uncut SubX
	assert_that(DissolvePattern.box_for(560, 100)).is_equal(Rect2i(560, 100, 64, 58))   # 624 - SubX
	assert_that(DissolvePattern.box_for(200, 20)).is_equal(Rect2i(200, 32, 96, 46))     # SubY < 32: 58 - (32 - SubY)
	assert_that(DissolvePattern.box_for(200, 261)).is_equal(Rect2i(200, 261, 96, 58))
	assert_that(DissolvePattern.box_for(200, 290)).is_equal(Rect2i(200, 290, 96, 30))   # 320 - SubY


# --- in the game -----------------------------------------------------------------------------

func _start_world() -> void:
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.load_sector(DevCreatures.ARENA, 0)
	_world.start_flight(200, 150, 6)
	_world.sfx_requested.connect(func(sfx_id: StringName) -> void: _events.append("sfx %s" % sfx_id))
	GameState.tank_lost.connect(_on_tank_lost)
	GameState.game_over.connect(_on_game_over)


func test_losing_the_last_air_plays_the_sound_then_dissolves_then_announces_the_loss() -> void:
	_start_world()
	GameState.oxygen_model.oxygen = 1
	_world.sub_touches(_world.sim.foes[DevCreatures.POST])                     # a hostile creature, damage 1
	assert_array(_events).is_equal(["sfx creature_hit"])             # PlaySoundEffect(0x1a) first; no respawn yet
	assert_int(GameState.oxygen()).is_equal(0)             # (the console already shows the empty tank)
	assert_bool(_world.sim.sub.controlled).is_false()          # the sub stands still while it dissolves
	assert_int(GameClock.holds).is_equal(1)                # and so does everything else
	assert_bool(_world.sim.sub.is_invulnerable()).is_false()   # (ApplyCreatureDamage sets no immunity on a lost tank)
	var material := _world.original.sub.sprite.material as ShaderMaterial
	assert_object(material).is_not_null()
	assert_float(material.get_shader_parameter("passes_done")).is_between(0.0, 17.0)
	await assert_signal(GameState).wait_until(3000).is_emitted("tank_lost", [OxygenModel.OUT_WITH_SPARE_TANKS])
	assert_array(_events).is_equal(["sfx creature_hit", "tank_lost -1"])
	assert_int(GameClock.holds).is_equal(0)
	assert_object(_world.original.sub.sprite.material).is_null()
	assert_bool(_world.original.sub.visual.visible).is_false()      # the sub is gone ...
	_world.start_flight()                                  # the respawn puts it back
	assert_bool(_world.original.sub.visual.visible).is_true()


func test_the_dissolve_is_21_ticks_of_the_original_counted_by_the_rules() -> void:
	# The original has no wait in `dissolve` (0x414f81: copies and `FlushRect` only), so the pace was the port's to choose: one frame of
	# a 60 Hz screen for each of the 16 passes and the closing copy, 17 / 60 s = 0.2833 s = 20.68 ticks of 1/73 s. The rules count
	# whole ticks, so it is 21 of them (0.2877 s): a Deliberate deviation of 4 ms (DESIGN).
	assert_int(SimWorld.dissolve_length()).is_equal(21)
	assert_float(TickMeter.seconds(SimWorld.dissolve_length())).is_equal_approx(0.2877, 0.0001)
	assert_float(TickMeter.seconds(SimWorld.dissolve_length()) - (DissolvePattern.PASSES + 1) / 60.0).is_between(0.0, 0.005)
	assert_int(ceili((DissolvePattern.PASSES + 1) / 60.0 * TickMeter.TICKS_PER_SECOND)).is_equal(SimWorld.dissolve_length())


func test_the_sub_is_stopped_and_the_clock_held_by_the_rules_dissolve_not_by_the_picture() -> void:
	_start_world()
	_world.replace_presenter(SectorPresenter.new())                # a presenter that draws nothing
	GameState.oxygen_model.oxygen = 1
	_world.sub_touches(_world.sim.foes[DevCreatures.POST])
	assert_bool(_world.sim.sub.controlled).is_false()
	assert_int(GameClock.holds).is_equal(1)
	assert_bool(_world.sim.is_dissolving()).is_true()
	_world.sim.advance_dissolve(SimWorld.dissolve_length() - 1)       # (the world's own frames would count too; the rules do not care who feeds them)
	assert_int(GameClock.holds).is_equal(1)
	_world.sim.advance_dissolve(1)
	assert_int(GameClock.holds).is_equal(0)                        # released at the 21st tick, whatever was drawn
	assert_array(_events).is_equal(["sfx creature_hit", "tank_lost -1"])


func test_the_dissolve_hides_the_sub_pixel_by_pixel_and_ends_with_all_of_it_gone() -> void:
	_start_world()
	GameState.oxygen_model.oxygen = 1
	_world.sub_touches(_world.sim.foes[DevCreatures.POST])
	var material := _world.original.sub.sprite.material as ShaderMaterial
	var box := DissolvePattern.box_for(200, 150)
	assert_that(material.get_shader_parameter("box_size")).is_equal(Vector2(box.size))
	# The box starts at the picture's top-left corner: window (200, 150) is playfield (184, 118).
	assert_that(material.get_shader_parameter("box_origin")).is_equal(Vector2(184, 118))
	assert_object(material.get_shader_parameter("pass_mask")).is_not_null()
	# The dissolve is paced by time (21 ticks of 1/73 s, about 0.29 s), not by frames, and without a display frames come as fast as the
	# machine allows: so look at every frame until the last pass has run, not at a fixed number of frames.
	var last_pass := float(DissolvePattern.PASSES + 1)
	var seen: Array[float] = []
	while seen.is_empty() or (seen.back() < last_pass and seen.size() < 2000):
		seen.append(material.get_shader_parameter("passes_done"))
		await await_idle_frame()
	assert_float(seen[0]).is_equal(0.0)                    # it starts with the whole sub
	for i in range(1, seen.size()):
		assert_float(seen[i]).is_greater_equal(seen[i - 1])    # and only ever removes more
	assert_float(seen.max()).is_equal(last_pass)


func test_enter_during_the_dissolve_does_not_open_the_waiting_problem_and_the_loss_is_still_announced() -> void:
	# The original is busy inside one call while the sub dissolves and reads no key. A problem opened over the dissolve held the
	# losses (`GameState.hold_losses`) and threw away the tank that was waiting: no `tank_lost`, no respawn, a sub that is gone.
	_start_world()
	var requested: Array[int] = []
	_world.problem_requested.connect(func(slot: int) -> void: requested.append(slot))
	_world.sim.take_piece(0)                                           # the data canister: its problem is waiting
	assert_int(_world.sim.pending_slot).is_equal(SimWorld.CANISTER_SLOT)
	GameState.oxygen_model.oxygen = 1
	_world.sub_touches(_world.sim.foes[DevCreatures.POST])
	assert_bool(_world.sim.is_dissolving()).is_true()
	var enter := InputEventAction.new()
	enter.action = &"show_problem"
	enter.pressed = true
	_world._unhandled_input(enter)
	assert_array(requested).is_empty()
	assert_int(_world.sim.pending_slot).is_equal(SimWorld.CANISTER_SLOT)   # (still waiting: it opens after the respawn)
	assert_bool(GameState.has_held_loss()).is_true()
	_world.sim.advance_dissolve(SimWorld.dissolve_length())
	assert_array(_events).is_equal(["sfx piece_pickup", "sfx creature_hit", "tank_lost -1"])
	_world._unhandled_input(enter)                                     # and Enter works again once the dissolve is over
	assert_array(requested).is_equal([SimWorld.CANISTER_SLOT])


func test_a_hit_that_leaves_air_does_not_dissolve_anything() -> void:
	_start_world()
	_world.sub_touches(_world.sim.foes[DevCreatures.POST])
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 1)
	assert_bool(_world.sim.sub.is_invulnerable()).is_true()
	assert_bool(_world.sim.sub.controlled).is_true()
	assert_object(_world.original.sub.sprite.material).is_null()
	assert_int(GameClock.holds).is_equal(0)


func test_losing_the_last_tank_dissolves_too_and_then_ends_the_game() -> void:
	_start_world()
	GameState.oxygen_model.oxygen = 1
	GameState.oxygen_model.tanks = 0
	_world.sub_touches(_world.sim.foes[DevCreatures.POST])
	assert_array(_events).is_equal(["sfx creature_hit"])
	await assert_signal(GameState).wait_until(3000).is_emitted("game_over")
	assert_array(_events).is_equal(["sfx creature_hit", "game_over"])


func test_without_animations_the_loss_is_announced_at_once() -> void:
	_start_world()
	SectorWorld.skip_animations = true
	GameState.oxygen_model.oxygen = 1
	_world.sub_touches(_world.sim.foes[DevCreatures.POST])
	assert_array(_events).is_equal(["sfx creature_hit", "tank_lost -1"])
	assert_bool(_world.sim.sub.controlled).is_true()


func test_a_lost_tank_from_a_math_problem_does_not_dissolve() -> void:
	_start_world()
	GameState.oxygen_model.oxygen = 1
	GameState.update_oxygen(-1)                            # what a wrong answer does
	assert_array(_events).is_equal(["tank_lost -1"])
	assert_object(_world.original.sub.sprite.material).is_null()
