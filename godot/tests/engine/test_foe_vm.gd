class_name TestFoeVM
extends GdUnitTestSuite
## Teaches: table-driven tests for a virtual machine. Each test assembles a few
## bytes by hand, runs the VM tick by tick and checks the creature's state. Reading
## the byte arrays next to the comments is the quickest way to learn the opcodes.

const Op := FoeOps.Op


## A VM running `bytes` (script offset 0) and a context with `foe_count` creatures.
func _vm(bytes: Array, frame_min: int = 0, frame_max: int = 255) -> FoeVM:
	var data := FoeData.new()
	data.frame_min = frame_min
	data.frame_max = frame_max
	data.pos = Vector2i(100, 50)
	data.frame = frame_min
	var vm := FoeVM.new()
	vm.setup(data, PackedByteArray(bytes), 0)
	return vm


func _ctx(vms: Array[FoeVM] = []) -> FoeVM.Context:
	var ctx := FoeVM.Context.new()
	ctx.foes = vms
	ctx.rng.seed = 1
	return ctx


## Runs `ticks` ticks and returns the frame number after each of them.
func _frames(vm: FoeVM, ctx: FoeVM.Context, ticks: int) -> Array[int]:
	var seen: Array[int] = []
	for i in ticks:
		vm.tick(ctx)
		seen.append(vm.frame)
	return seen


func test_yield_ends_the_tick_and_keeps_the_pc_after_it() -> void:
	var vm := _vm([Op.SET_FRAME, 5, Op.YIELD, Op.SET_FRAME, 6, Op.YIELD])
	var ctx := _ctx()
	assert_array(_frames(vm, ctx, 3)).is_equal([5, 6, 6])      # then pc runs off the end...
	assert_str(vm.fault).contains("outside the buffer")         # ...which is a fault, not a crash


func test_jmp_is_relative_to_the_end_of_the_instruction() -> void:
	# 0: YIELD   1: JMP -4  (operands at 2-3, the instruction ends at 4, 4 - 4 = 0)
	var vm := _vm([Op.SET_FRAME, 1, Op.YIELD, Op.SET_FRAME, 2, Op.YIELD, Op.JMP, 250, 255])
	# JMP at 6: ends at 9, 9 - 6 = 3 -> loops between the two SET_FRAMEs
	assert_array(_frames(vm, _ctx(), 4)).is_equal([1, 2, 2, 2])
	var loop := _vm([Op.YIELD, Op.JMP, 252, 255])
	for i in 5:
		loop.tick(_ctx())
	assert_str(loop.fault).is_empty()
	assert_int(loop.pc).is_equal(1)         # alternates between 1 (after a YIELD) and 4->0


func test_handler_calls_a_subroutine_and_ret_returns_after_the_header() -> void:
	# 0: HANDLER len 4 -> subroutine at 3 + 4 = 7
	# 3: SET_FRAME 1   5: YIELD   6: YIELD (padding)
	# 7: SET_FRAME 9   9: YIELD   10: RET   -> goes back to 3
	var vm := _vm([Op.HANDLER, 4, 0, Op.SET_FRAME, 1, Op.YIELD, Op.YIELD,
			Op.SET_FRAME, 9, Op.YIELD, Op.RET])
	var ctx := _ctx()
	assert_array(_frames(vm, ctx, 2)).is_equal([9, 1])


func test_handler_can_call_backwards() -> void:
	# 0: JMP +5 (to 8)   3: SET_FRAME 7  5: YIELD  6: RET
	# 8: HANDLER len -8 -> 11 - 8 = 3 (call), 11: SET_FRAME 2, 13: YIELD
	var vm := _vm([Op.JMP, 5, 0, Op.SET_FRAME, 7, Op.YIELD, Op.RET, Op.YIELD,
			Op.HANDLER, 248, 255, Op.SET_FRAME, 2, Op.YIELD])
	assert_array(_frames(vm, _ctx(), 2)).is_equal([7, 2])


func test_loops_run_the_body_count_plus_one_times_with_all_three_counters() -> void:
	# update_animals (0x41ed0c, asm 0x41f080-0x41f0cf): the stored counter starts at 0, so the first
	# visit computes -1, loads `count` and jumps back without counting: the body runs count + 1 times.
	for loop_op in [Op.LOOP0, Op.LOOP1, Op.LOOP2]:
		# 0: MOVE_REL 2 0 0 (moves 4 px right and ends the tick)   4: LOOP -9, count 3
		# 9: SET_FRAME 9   11: YIELD
		var vm := _vm([Op.MOVE_REL, 2, 0, 0, loop_op, 247, 255, 3, 0, Op.SET_FRAME, 9, Op.YIELD])
		var ctx := _ctx()
		for i in 4:
			vm.tick(ctx)
		assert_int(vm.x).is_equal(100 + 4 * 4)       # the body (the move) ran 3 + 1 times
		assert_int(vm.frame).is_equal(0)             # and the code after the loop has not run yet
		vm.tick(ctx)
		assert_int(vm.frame).is_equal(9)


func test_a_loop_with_count_1_runs_its_body_twice_and_count_0_never_ends() -> void:
	var once := _vm([Op.MOVE_REL, 2, 0, 0, Op.LOOP0, 247, 255, 1, 0, Op.SET_FRAME, 9, Op.YIELD])
	var ctx := _ctx()
	once.tick(ctx)
	once.tick(ctx)
	assert_int(once.x).is_equal(100 + 2 * 4)
	assert_int(once.frame).is_equal(0)
	once.tick(ctx)
	assert_int(once.frame).is_equal(9)
	# count 0: -1 -> load 0 -> jump back; 0 - 1 = -1 again, forever (no stored script uses it).
	var never := _vm([Op.MOVE_REL, 2, 0, 0, Op.LOOP0, 247, 255, 0, 0, Op.SET_FRAME, 9, Op.YIELD])
	for i in 50:
		never.tick(ctx)
	assert_int(never.x).is_equal(100 + 50 * 4)
	assert_int(never.frame).is_equal(0)


func test_a_finished_loop_can_run_again() -> void:
	# 0: MOVE_REL (4 bytes)  4: LOOP0 count 2 (to 0)  9: SET_FRAME 9  11: YIELD  12: JMP to 0.
	# The counter is back at 0 after the loop falls through, so every round is 3 moves + 1 pause.
	var vm := _vm([Op.MOVE_REL, 1, 0, 0, Op.LOOP0, 247, 255, 2, 0, Op.SET_FRAME, 9, Op.YIELD,
			Op.JMP, 241, 255])
	var ctx := _ctx()
	var xs: Array[int] = []
	for i in 8:
		vm.tick(ctx)
		xs.append(vm.x)
	assert_array(xs).is_equal([102, 104, 106, 106, 108, 110, 112, 112])


func test_loops_use_independent_counters() -> void:
	# LOOP0 (count 1, outer) around LOOP1 (count 1, inner): 2 x 2 moves, a pause tick between rounds.
	# 0: MOVE_REL  4: LOOP1 -> 0 (ends 9)  9: LOOP0 -> 0 (ends 14, offset -14)  14: YIELD
	var vm := _vm([Op.MOVE_REL, 1, 0, 0, Op.LOOP1, 247, 255, 1, 0,
			Op.LOOP0, 242, 255, 1, 0, Op.YIELD])
	var ctx := _ctx()
	for i in 4:
		vm.tick(ctx)
	assert_int(vm.x).is_equal(100 + 4 * 2)
	vm.tick(ctx)                                            # both loops are over: the YIELD
	assert_int(vm.x).is_equal(100 + 4 * 2)
	assert_str(vm.fault).is_empty()


func test_set_frame_uses_bit_7_as_the_mirror_flag() -> void:
	var vm := _vm([Op.SET_FRAME, 0x8B, Op.YIELD, Op.SET_FRAME, 11, Op.YIELD])
	vm.tick(_ctx())
	assert_int(vm.frame).is_equal(11)
	assert_bool(vm.flip).is_true()
	vm.tick(_ctx())
	assert_bool(vm.flip).is_false()


func test_move_rel_moves_in_2_pixel_steps_and_wraps_the_frame() -> void:
	# dx = -4 (252) -> -8 px; dy = +3 -> +6 px (positions are kept in 2-pixel units); picture +1, wrapping inside [9, 10]
	var vm := _vm([Op.MOVE_REL, 252, 3, 1, Op.JMP, 249, 255], 9, 10)
	var ctx := _ctx()
	var frames := _frames(vm, ctx, 4)
	assert_array(frames).is_equal([10, 9, 10, 9])
	assert_int(vm.x).is_equal(100 - 4 * 8)
	assert_int(vm.y).is_equal(50 + 4 * 6)


func test_move_rel_with_bit_7_mirrors_and_with_0_keeps_the_picture() -> void:
	var vm := _vm([Op.MOVE_REL, 0, 0, 0x81, Op.MOVE_REL, 0, 0, 0], 4, 6)
	vm.tick(_ctx())
	assert_bool(vm.flip).is_true()
	assert_int(vm.frame).is_equal(5)
	vm.tick(_ctx())
	assert_bool(vm.flip).is_false()
	assert_int(vm.frame).is_equal(5)


func test_move_rel_wraps_below_min_to_max_and_above_max_to_min() -> void:
	# update_animals case MOVE_REL: picture + increment < min -> max; > max -> min.
	var below := _vm([Op.MOVE_REL, 0, 0, 1], 9, 12)
	below.frame = 3                                         # outside the range, below its min
	below.tick(_ctx())
	assert_int(below.frame).is_equal(12)
	var above := _vm([Op.MOVE_REL, 0, 0, 1], 9, 12)
	above.frame = 12
	above.tick(_ctx())
	assert_int(above.frame).is_equal(9)
	var inside := _vm([Op.MOVE_REL, 0, 0, 2], 9, 12)
	inside.frame = 9
	inside.tick(_ctx())
	assert_int(inside.frame).is_equal(11)


func test_set_pos_clamps_the_picture_into_frame_range() -> void:
	# update_animals cases SET_POS / SET_POS_SCREEN: below min -> min, above max -> max, bit 7 = mirror.
	for op in [Op.SET_POS, Op.SET_POS_SCREEN]:
		var tail: Array = [] if op == Op.SET_POS else [2]
		var low := _vm([op, 1, 1, 3] + tail, 9, 12)
		low.tick(_ctx())
		assert_int(low.frame).is_equal(9)
		var high := _vm([op, 1, 1, 0x80 | 40] + tail, 9, 12)
		high.tick(_ctx())
		assert_int(high.frame).is_equal(12)
		assert_bool(high.flip).is_true()
		var inside := _vm([op, 1, 1, 10] + tail, 9, 12)
		inside.tick(_ctx())
		assert_int(inside.frame).is_equal(10)
	# SET_FRAME does not clamp.
	var free := _vm([Op.SET_FRAME, 40, Op.YIELD], 9, 12)
	free.tick(_ctx())
	assert_int(free.frame).is_equal(40)


func test_frame_range_changes_the_wrap_limits() -> void:
	var vm := _vm([Op.FRAME_RANGE, 20, 21, Op.SET_FRAME, 21, Op.MOVE_REL, 0, 0, 1])
	vm.tick(_ctx())
	assert_int(vm.frame).is_equal(20)                      # 21 + 1 > 21 -> back to 20


func test_set_pos_places_the_creature_at_4x_and_2y() -> void:
	var vm := _vm([Op.SET_POS, 41, 56, 0x80 | 22, Op.YIELD])
	vm.tick(_ctx())
	assert_that(Vector2i(vm.x, vm.y)).is_equal(Vector2i(164, 112))     # x in 4-pixel units, y in 2-pixel units
	assert_int(vm.frame).is_equal(22)
	assert_bool(vm.flip).is_true()


func test_set_pos_screen_also_changes_the_screen() -> void:
	var vm := _vm([Op.SET_POS_SCREEN, 10, 20, 3, 7, Op.YIELD])
	vm.tick(_ctx())
	assert_int(vm.screen).is_equal(7)
	assert_int(vm.x).is_equal(40)


func test_set_pos_and_ret_from_an_interrupt_are_jumps_move_rel_is_not() -> void:
	# 0: SET_POS 25 25 0 ; 4: MOVE_REL 1 0 0 ; 8: SET_POS_SCREEN 25 25 0 0 ; 13: YIELD ; 14: RET (hit script)
	var vm := _vm([Op.SET_POS, 25, 25, 0, Op.MOVE_REL, 1, 0, 0,
			Op.SET_POS_SCREEN, 25, 25, 0, 0, Op.YIELD, Op.RET])
	var ctx := _ctx()
	vm.tick(ctx)
	assert_bool(vm.jumped).is_true()                       # SET_POS: 8 px or 80, the Foe node draws it there at once
	vm.tick(ctx)
	assert_bool(vm.jumped).is_false()                      # MOVE_REL: a step, drawn gliding
	vm.tick(ctx)
	assert_bool(vm.jumped).is_true()                       # SET_POS_SCREEN
	vm.tick(ctx)
	assert_bool(vm.jumped).is_false()                      # YIELD only
	vm.interrupt(14)
	vm.tick(ctx)
	assert_bool(vm.jumped).is_true()                       # RET puts the saved position back


func test_hide_ends_the_tick_and_show_does_not() -> void:
	var vm := _vm([Op.HIDE, Op.SHOW, Op.SET_FRAME, 8, Op.YIELD])
	var ctx := _ctx()
	vm.tick(ctx)
	assert_bool(vm.hidden).is_true()
	assert_int(vm.frame).is_equal(0)                       # HIDE ended the tick
	vm.tick(ctx)
	assert_bool(vm.hidden).is_false()
	assert_int(vm.frame).is_equal(8)                       # SHOW went straight on


func test_if_executes_the_next_instruction_or_skips_it_whole() -> void:
	# IF_SUBX_GT 10 (sub_x > 40): SET_FRAME 5 | YIELD
	var script := [Op.IF_SUBX_GT, 10, Op.SET_FRAME, 5, Op.YIELD]
	var ctx := _ctx()
	var yes := _vm(script, 1, 1)
	ctx.sub_x = 41
	yes.tick(ctx)
	assert_int(yes.frame).is_equal(5)
	var no := _vm(script, 1, 1)
	ctx.sub_x = 40
	no.tick(ctx)
	assert_int(no.frame).is_equal(1)                       # SET_FRAME (2 bytes) was skipped


func test_if_skips_an_instruction_with_four_operand_bytes() -> void:
	# The skipped LOOP0 has 4 operand bytes: skipping must advance by 1 + 4.
	var vm := _vm([Op.IF_SUBX_LT, 10, Op.LOOP0, 0, 0, 5, 0, Op.SET_FRAME, 3, Op.YIELD], 1, 1)
	var ctx := _ctx()
	ctx.sub_x = 100                                        # not < 40: skip the loop
	vm.tick(ctx)
	assert_int(vm.frame).is_equal(3)


func test_if_conditions_for_x_and_y_use_the_documented_scales() -> void:
	var ctx := _ctx()
	for case in [
			[Op.IF_SUBX_GT, 10, 41, 0, true], [Op.IF_SUBX_GT, 10, 40, 0, false],
			[Op.IF_SUBX_LT, 10, 39, 0, true], [Op.IF_SUBX_LT, 10, 40, 0, false],
			[Op.IF_SUBY_GT, 10, 0, 21, true], [Op.IF_SUBY_GT, 10, 0, 20, false],
			[Op.IF_SUBY_LT, 10, 0, 19, true], [Op.IF_SUBY_LT, 10, 0, 20, false]]:
		var vm := _vm([case[0], case[1], Op.SET_FRAME, 9, Op.YIELD], 1, 1)
		ctx.sub_x = case[2]
		ctx.sub_y = case[3]
		vm.tick(ctx)
		assert_bool(vm.frame == 9).is_equal(case[4])


func test_if_rand_gt_255_never_fires_and_0_almost_always() -> void:
	var ctx := _ctx()
	var fired := 0
	for i in 200:
		var never := _vm([Op.IF_RAND_GT, 255, Op.SET_FRAME, 9, Op.YIELD], 1, 1)
		never.tick(ctx)
		assert_int(never.frame).is_equal(1)
		var often := _vm([Op.IF_RAND_GT, 0, Op.SET_FRAME, 9, Op.YIELD], 1, 1)
		often.tick(ctx)
		fired += 1 if often.frame == 9 else 0
	assert_int(fired).is_greater(190)


func test_semaphore_set_clear_and_test() -> void:
	var ctx := _ctx()
	var setter := _vm([Op.SEM_SET, 15, Op.YIELD])
	setter.tick(ctx)
	assert_int(ctx.semaphore).is_equal(0x8000)
	var tester := _vm([Op.IF_SEM, 15, Op.SET_FRAME, 4, Op.YIELD], 1, 1)
	tester.tick(ctx)
	assert_int(tester.frame).is_equal(4)
	var clearer := _vm([Op.SEM_CLR, 15, Op.YIELD])
	clearer.tick(ctx)
	assert_int(ctx.semaphore).is_equal(0)
	var tester2 := _vm([Op.IF_SEM, 15, Op.SET_FRAME, 4, Op.YIELD], 1, 1)
	tester2.tick(ctx)
	assert_int(tester2.frame).is_equal(1)


func test_sleep_and_wake_address_creatures_by_index_or_relative() -> void:
	var a := _vm([Op.SLEEP_FOE, 2, Op.WAKE_FOE, 1, Op.YIELD])
	var b := _vm([Op.YIELD])
	var c := _vm([Op.YIELD])
	a.index = 0
	b.index = 1
	c.index = 2
	b.dormant = true
	var ctx := _ctx([a, b, c])
	a.tick(ctx)
	assert_bool(c.dormant).is_true()
	assert_bool(b.dormant).is_false()
	# Relative: bit 7 set, low 7 bits are a signed offset from the running creature.
	var d := _vm([Op.SLEEP_FOE, 0x80 | 1, Op.SLEEP_FOE, 0x80 | 0x7F, Op.YIELD])   # +1, then -1
	d.index = 1
	var e := _vm([Op.YIELD])
	var f := _vm([Op.YIELD])
	e.index = 0
	f.index = 2
	ctx = _ctx([e, d, f])
	d.tick(ctx)
	assert_bool(f.dormant).is_true()
	assert_bool(e.dormant).is_true()


func test_sleeping_creature_and_other_screens_do_not_run() -> void:
	var vm := _vm([Op.SET_FRAME, 5, Op.YIELD])
	var ctx := _ctx()
	vm.screen = 3
	ctx.current_screen = 2
	vm.tick(ctx)
	assert_int(vm.frame).is_equal(0)                       # not on the current screen
	ctx.current_screen = 3
	vm.dormant = true
	vm.tick(ctx)
	assert_int(vm.frame).is_equal(0)                       # dormant
	vm.dormant = false
	vm.tick(ctx)
	assert_int(vm.frame).is_equal(5)


func test_sound_is_only_requested_on_the_current_screen() -> void:
	var vm := _vm([Op.SOUND, 13, Op.YIELD])
	var ctx := _ctx()
	vm.screen = 4
	ctx.current_screen = 4
	vm.tick(ctx)
	assert_array(ctx.sounds).is_equal([13])
	var other := _vm([Op.SOUND, 13, Op.YIELD])
	other.screen = 1
	other.interrupted = true                               # runs even off-screen...
	ctx.sounds.clear()
	other.tick(ctx)
	assert_array(ctx.sounds).is_empty()                    # ...but is not heard


func test_interrupt_runs_the_entry_script_and_ret_restores_everything() -> void:
	# 0: YIELD  1: JMP -4 (back to 0).   4: hit script: MOVE_REL 4 0 0 ; 8: YIELD ; 9: RET
	var vm := _vm([Op.YIELD, Op.JMP, 252, 255, Op.MOVE_REL, 4, 0, 0, Op.YIELD, Op.RET])
	var ctx := _ctx()
	vm.tick(ctx)
	vm.frame = 7
	var pc_before := vm.pc
	vm.interrupt(4)
	assert_bool(vm.interrupted).is_true()
	assert_bool(vm.can_be_interrupted()).is_false()        # busy: a second interrupt is refused
	vm.tick(ctx)
	assert_int(vm.x).is_equal(108)                         # the hit script moved it...
	vm.tick(ctx)                                           # (YIELD)
	vm.tick(ctx)                                           # RET, then the normal script goes on
	assert_bool(vm.interrupted).is_false()
	assert_int(vm.x).is_equal(100)                         # ...and RET put it back
	assert_int(vm.frame).is_equal(7)
	assert_int(vm.pc).is_greater_equal(0)
	assert_int(pc_before).is_equal(1)


func test_an_interrupted_creature_keeps_running_on_other_screens() -> void:
	var vm := _vm([Op.YIELD, Op.JMP, 252, 255, Op.SET_FRAME, 9, Op.YIELD, Op.RET])
	var ctx := _ctx()
	vm.screen = 5
	ctx.current_screen = 2
	vm.interrupt(4)
	vm.tick(ctx)
	assert_int(vm.frame).is_equal(9)


func test_creature_that_sleeps_itself_in_an_interrupt_script_never_returns() -> void:
	# The Zoom pattern: SLEEP_FOE self ; HIDE
	var vm := _vm([Op.SLEEP_FOE, 0, Op.HIDE])
	vm.index = 0
	var ctx := _ctx([vm])
	vm.interrupt(0)
	vm.tick(ctx)
	assert_bool(vm.dormant).is_true()
	assert_bool(vm.hidden).is_true()
	assert_bool(vm.interrupted).is_false()


## G42: the original's SLEEP_FOE zeroes the saved pc of the creature RUNNING it, whichever creature it names.
func test_putting_another_creature_to_sleep_ends_the_interrupt_without_restoring() -> void:
	# creature 0 (the interrupted one) runs: SET_FRAME 7 ; SLEEP_FOE 1 ; SET_POS 10 20 3 ; YIELD ; RET
	var a := _vm([Op.SET_FRAME, 7, Op.SLEEP_FOE, 1, Op.SET_POS, 10, 20, 3, Op.YIELD, Op.RET, Op.YIELD])
	a.index = 0
	var b := _vm([Op.YIELD])
	b.index = 1
	var ctx := _ctx([a, b])
	var frame_before := a.frame
	var pc_before := a.pc
	a.interrupt(0)
	assert_bool(a.interrupted).is_true()
	a.tick(ctx)
	assert_bool(b.dormant).is_true()
	assert_bool(a.dormant).is_false()
	assert_bool(a.interrupted).is_false()
	# Nothing was restored: the creature is where the interrupt script put it, not at its old pc / picture.
	assert_int(a.x).is_equal(40)
	assert_int(a.y).is_equal(40)
	assert_int(a.frame).is_equal(3)
	assert_int(a.frame).is_not_equal(frame_before)
	assert_int(a.pc).is_equal(8)                                # just after SET_POS, not the saved pc
	assert_int(a.pc).is_not_equal(pc_before)
	# The script simply carries on (the YIELD), still at the interrupt script's position.
	a.tick(ctx)
	assert_int(a.pc).is_equal(9)
	assert_int(a.x).is_equal(40)
	assert_str(a.fault).is_empty()


func test_waking_a_creature_does_not_end_the_interrupt() -> void:
	var a := _vm([Op.WAKE_FOE, 1, Op.YIELD, Op.RET])
	a.index = 0
	var b := _vm([Op.YIELD])
	b.index = 1
	b.dormant = true
	var ctx := _ctx([a, b])
	a.interrupt(0)
	a.tick(ctx)
	assert_bool(b.dormant).is_false()
	assert_bool(a.interrupted).is_true()
	# WAKE_FOE of itself does not end it either.
	var c := _vm([Op.WAKE_FOE, 0, Op.YIELD, Op.RET])
	c.index = 0
	c.interrupt(0)
	c.tick(_ctx([c]))
	assert_bool(c.interrupted).is_true()


func test_sleeping_a_creature_while_not_interrupted_changes_nothing_else() -> void:
	var a := _vm([Op.SLEEP_FOE, 1, Op.YIELD])
	a.index = 0
	var b := _vm([Op.YIELD])
	b.index = 1
	a.tick(_ctx([a, b]))
	assert_bool(b.dormant).is_true()
	assert_bool(a.interrupted).is_false()


func test_bad_scripts_fault_instead_of_crashing() -> void:
	var unknown := _vm([99])
	unknown.tick(_ctx())
	assert_str(unknown.fault).contains("unknown opcode")
	var outside := _vm([Op.JMP, 100, 0])
	outside.tick(_ctx())
	assert_str(outside.fault).contains("outside the buffer")
	var endless := _vm([Op.JMP, 253, 255])
	endless.tick(_ctx())
	assert_str(endless.fault).contains("without a YIELD")
	var missing := _vm([Op.SLEEP_FOE, 9, Op.YIELD])
	missing.tick(_ctx())
	assert_str(missing.fault).contains("does not exist")
	# A faulted creature stays frozen.
	var frame := unknown.frame
	unknown.tick(_ctx())
	assert_int(unknown.frame).is_equal(frame)


func test_operand_table_matches_the_original() -> void:
	# (the original's 25 entries, then the port's own `Mod_Instruction`)
	assert_array(FoeOps.OPERAND_COUNT.slice(0, 25)).is_equal([0, 2, 2, 0, 4, 4, 4, 1, 1, 1, 2, 1, 3, 3, 4, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1])
	assert_int(FoeOps.OPERAND_COUNT.size()).is_equal(26)
	assert_str(FoeOps.op_name(Op.MOVE_REL)).is_equal("Move_Foe_Relative_XY")
	assert_str(FoeOps.disassemble_one(PackedByteArray([12, 252, 3, 1]), 0, 0)).is_equal("0000: Move_Foe_Relative_XY 252 3 1")


## Deliberate deviation from the original (G41): the original's contact also interrupts a dormant creature (its hit
## script waits until it is woken); the port refuses the interrupt. (The damage of a touch applies either way.)
func test_a_dormant_creature_is_not_interrupted_by_the_sub() -> void:
	var vm := _vm([Op.YIELD])
	vm.dormant = true
	assert_bool(vm.can_be_interrupted()).is_false()
	vm.dormant = false
	assert_bool(vm.can_be_interrupted()).is_true()
