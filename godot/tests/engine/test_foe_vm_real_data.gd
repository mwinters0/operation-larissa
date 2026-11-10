class_name TestFoeVMRealData
extends GdUnitTestSuite
## Teaches: a "soak test" on real data. Every creature of every sector of the chain runs for
## 2,000 ticks while the sub wanders about, the screen changes and ink pellets
## and hits interrupt it. Nothing may fault (unknown opcode, program counter
## outside the buffer, endless loop) and positions must stay sane.

const TICKS := 2000


func test_all_sectors_run_without_faults() -> void:
	for sector_index in Catalog.sector_ids():
		var sector := Catalog.sector(sector_index)
		var ctx := FoeVM.Context.new()
		ctx.rng.seed = sector_index + 1
		var vms: Array[FoeVM] = []
		for i in sector.foes.size():
			var vm := FoeVM.from_data(sector.foes[i], i, sector)
			vms.append(vm)
			ctx.foes.append(vm)
		for t in TICKS:
			# Visit the 12 screens in turn, 20 ticks each.
			ctx.current_screen = (t / 20) % 12
			ctx.sub_x = ctx.rng.randi_range(-32, 576)
			ctx.sub_y = ctx.rng.randi_range(3, 290)
			for vm in vms:
				vm.tick(ctx)
			ctx.sounds.clear()
			# Every 37 ticks something hits a creature on this screen, alternating hit and ink.
			if t % 37 == 0:
				for vm in vms:
					if vm.screen == ctx.current_screen and vm.can_be_interrupted():
						vm.interrupt(vm.script_ink if (t / 37) % 2 == 0 else vm.script_hit)
						break
		for vm in vms:
			assert_str(vm.fault).is_empty()
			assert_bool(absi(vm.x) < 5000 and absi(vm.y) < 5000).is_true()
			assert_bool(vm.frame >= 0 and vm.frame < 128).is_true()


