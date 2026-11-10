class_name TestSectorOverview
extends GdUnitTestSuite
## Teaches: testing a map tool without looking at it. The overview has three parts that can be checked headless: WHERE the screens go
## (`SectorLayout`: every screen placed or reported, every link either between neighbouring cells or listed as a conflict), WHERE the creatures
## go (`CreaturePaths`: the same every time, the same as the rules' own `SimWorld`, and touching nothing of the game), and what the overview
## says about a sector (`SectorOverviewModel`, the reachability from `SectorReach`), plus a smoke test of the scene itself.
##
## The findings about the ORIGINAL data (its three sectors with one-way links, its two finales with unused screens) are in `tests/legacy/test_sector_overview_legacy.gd`.

const SCENE := "res://src/debug/sector_overview.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"

## Where the creature traces are compared with the rules: [sector, screen] (creatures of the ground sector, the map sector, the tangle and the finale).
const TRACED := [[Ground.MAIN, 4], [Ground.MAIN, 7], [Ground.MAIN, 1], [Ground.MAP, 2], [Ground.MAP, 9], [Ground.TANGLE, 3], [Ground.FINALE, 2], [Ground.FINALE, 4]]


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()
	Catalog.sectors_dir = Catalog.SECTORS_DIR


# --- the layout ---------------------------------------------------------------------------------------------------

static func _tables(left: Array, right: Array, up: Array, down: Array) -> Array:
	return [PackedInt32Array(left), PackedInt32Array(right), PackedInt32Array(up), PackedInt32Array(down)]


func test_every_screen_of_every_sector_is_placed_exactly_once() -> void:
	for index in Catalog.sector_ids():
		var layout := SectorLayout.from_sector(Catalog.sector(index))
		var cells := {}
		for screen in SectorData.SCREEN_COUNT:
			assert_bool(layout.cell_of.has(screen)).override_failure_message("sector %d: screen %d has no cell" % [index, screen]).is_true()
			var cell: Vector2i = layout.cell_of[screen]
			assert_bool(cells.has(cell)).override_failure_message("sector %d: screens %d and %d share the cell %s" % [index, cells.get(cell, -1), screen, cell]).is_false()
			cells[cell] = screen
			assert_int(layout.screen_at[cell]).is_equal(screen)
			assert_bool(layout.bounds.has_point(cell)).override_failure_message("sector %d: screen %d at %s is outside the bounds %s" % [index, screen, cell, layout.bounds]).is_true()
		assert_int(layout.cell_of[0].x).is_equal(0)
		assert_int(layout.cell_of[0].y).is_equal(0)


func test_every_link_is_between_neighbouring_cells_or_reported() -> void:
	for index in Catalog.sector_ids():
		var sector := Catalog.sector(index)
		var layout := SectorLayout.from_sector(sector)
		var table_entries := 0
		for side in 4:
			for screen in SectorData.SCREEN_COUNT:
				var target := sector.neighbor(screen, side as SectorData.Direction)
				if target < 0:
					continue
				table_entries += 1
				var found: Array = layout.links.filter(func(link: Dictionary) -> bool: return link["screen"] == screen and link["side"] == side)
				assert_int(found.size()).override_failure_message("sector %d screen %d side %d: not exactly one link" % [index, screen, side]).is_equal(1)
				var link: Dictionary = found[0]
				assert_int(link["target"]).is_equal(target)
				var adjacent: bool = layout.cell_of[target] == layout.cell_of[screen] + SectorLayout.STEPS[side] and target != screen
				assert_bool(adjacent).override_failure_message("sector %d: screen %d %s -> %d: adjacency %s but the verdict is %d" % [
						index, screen, SectorLayout.SIDE_NAMES[side], target, adjacent, link["kind"]]).is_equal(link["kind"] in [SectorLayout.Kind.OK, SectorLayout.Kind.ONE_WAY])
				assert_bool(layout.is_adjacent(screen, side)).is_equal(adjacent)
				if not adjacent:
					assert_bool(link["kind"] in [SectorLayout.Kind.MISPLACED, SectorLayout.Kind.SELF, SectorLayout.Kind.INVALID]).is_true()
					assert_bool(layout.conflicts().any(func(c: Dictionary) -> bool: return c["screen"] == screen and c["side"] == side)).is_true()
					assert_bool(not str(link["text"]).is_empty()).is_true()
		assert_int(layout.links.size()).is_equal(table_entries)


func test_the_clean_sectors_are_clean_maps() -> void:
	for index in Ground.clean_sectors():
		if index == Ground.FINALE:
			continue                                                        # (the finale uses screens 0-4 only: the next test)
		var layout := SectorLayout.from_sector(Catalog.sector(index))
		assert_array(layout.one_way_links()).override_failure_message("sector %d: %s" % [index, layout.report()]).is_empty()
		assert_array(layout.conflicts()).override_failure_message("sector %d: %s" % [index, layout.report()]).is_empty()
		assert_array(layout.detached()).override_failure_message("sector %d: detached screens" % index).is_empty()
		assert_int(layout.report().size()).is_equal(0)


func test_the_screens_a_finale_never_reaches_are_detached_and_the_rest_is_clean() -> void:
	var layout := SectorLayout.from_sector(Catalog.sector(Ground.FINALE))
	assert_array(layout.detached()).is_equal([5, 6, 7, 8, 9, 10, 11])
	assert_array(layout.one_way_links()).is_empty()
	assert_array(layout.conflicts()).is_empty()


func test_the_map_sector_is_a_grid_of_four_by_three() -> void:
	var layout := SectorLayout.from_sector(Catalog.sector(Ground.MAP))
	for screen in SectorData.SCREEN_COUNT:
		assert_that(layout.cell_of[screen]).is_equal(Vector2i(screen % 4, screen / 4))


func test_the_tangle_sector_reports_what_its_tables_do() -> void:
	# screen 9 leads left to 5 (5 leads right to 6); screen 4 leads up to 8 (8 has no way down); the ring: 11 leads right to 0 and 0 leads left to 11
	var layout := SectorLayout.from_sector(Catalog.sector(Ground.TANGLE))
	assert_int(layout.conflicts().size()).override_failure_message("\n".join(layout.report())).is_equal(3)
	assert_array(layout.detached()).is_empty()
	# what is wrong is always in the report: a view that prints it hides nothing
	var report := layout.report()
	assert_int(report.size()).is_equal(layout.detached().size() + layout.conflicts().size() + layout.one_way_links().size())
	var text := "\n".join(report)
	assert_str(text).contains("screen 4, up -> screen 8").contains("screen 9, left -> screen 5")
	# the ring is laid out as a row that is cut at screen 0: 11 is left of 0, 10 left of 11 ...
	assert_that(layout.cell_of[0]).is_equal(Vector2i(0, 0))
	assert_that(layout.cell_of[11]).is_equal(Vector2i(-1, 0))
	assert_that(layout.cell_of[10]).is_equal(Vector2i(-2, 0))


func test_the_report_says_which_screen_is_in_the_way() -> void:
	# screen 3 leads left to 1, but the cell left of 3 is the one screen 2 sits in
	var layout := SectorLayout.compute(_tables([-1, 0, 1, 1], [1, 2, 3, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]))
	var report := "\n".join(layout.report())
	assert_str(report).contains("screen 3, left -> screen 1").contains("where screen 2 sits")


func test_the_layout_is_the_same_every_time() -> void:
	for index in [Ground.MAIN, Ground.MAP, Ground.TANGLE, Ground.FINALE]:
		var sector := Catalog.sector(index)
		var first := SectorLayout.from_sector(sector)
		var second := SectorLayout.from_sector(sector)
		assert_dict(second.cell_of).is_equal(first.cell_of)
		assert_array(second.links).is_equal(first.links)


func test_a_corridor_of_two_way_links_is_a_row() -> void:
	# 0 - 1 - 2 in a row, 3 below 1
	var layout := SectorLayout.compute(_tables(
			[-1, 0, 1, -1], [1, 2, -1, -1], [-1, -1, -1, 1], [-1, 3, -1, -1]))
	assert_dict(layout.cell_of).is_equal({0: Vector2i(0, 0), 1: Vector2i(1, 0), 2: Vector2i(2, 0), 3: Vector2i(1, 1)})
	assert_array(layout.report()).is_empty()


func test_a_wrap_around_is_reported_not_hidden() -> void:
	# a ring: 0 -> 1 -> 2 -> 0 to the right, and back to the left
	var layout := SectorLayout.compute(_tables([2, 0, 1], [1, 2, 0], [-1, -1, -1], [-1, -1, -1]))
	assert_int(layout.cell_of.size()).is_equal(3)
	assert_int(layout.conflicts().size()).is_equal(2)         # 2 right -> 0 and 0 left -> 2
	assert_array(layout.detached()).is_empty()
	for link in layout.conflicts():
		assert_int(link["kind"]).is_equal(SectorLayout.Kind.MISPLACED)


func test_links_that_disagree_about_where_a_screen_is_are_reported() -> void:
	# 0 right -> 1 and 0 down -> 2 (both lead back), but 2 right -> 1: 1 cannot be right of both 0 and 2
	var layout := SectorLayout.compute(_tables([-1, 0, -1], [1, -1, 1], [-1, -1, 0], [2, -1, -1]))
	assert_int(layout.cell_of.size()).is_equal(3)
	assert_bool(layout.cell_of[1] != layout.cell_of[2]).is_true()
	var wrong := layout.conflicts()
	assert_int(wrong.size()).is_equal(1)
	assert_int(wrong[0]["screen"]).is_equal(2)
	assert_int(wrong[0]["target"]).is_equal(1)
	assert_str(wrong[0]["text"]).contains("not at the neighbouring cell")


func test_a_screen_leading_to_itself_and_a_bad_number_are_reported() -> void:
	var layout := SectorLayout.compute(_tables([-1, -1], [0, 9], [-1, -1], [-1, 1]))
	var kinds := layout.links.map(func(link: Dictionary) -> int: return link["kind"])
	assert_bool(kinds.has(SectorLayout.Kind.SELF)).is_true()
	assert_bool(kinds.has(SectorLayout.Kind.INVALID)).is_true()
	assert_int(layout.cell_of.size()).is_equal(2)


func test_a_one_way_link_still_places_the_screen_and_is_marked() -> void:
	var layout := SectorLayout.compute(_tables([-1, -1], [1, -1], [-1, -1], [-1, -1]))
	assert_dict(layout.cell_of).is_equal({0: Vector2i(0, 0), 1: Vector2i(1, 0)})
	assert_int(layout.one_way_links().size()).is_equal(1)
	assert_array(layout.detached()).is_empty()


func test_a_screen_nothing_leads_to_is_placed_apart_and_named() -> void:
	var layout := SectorLayout.compute(_tables([-1, -1, -1], [1, -1, -1], [-1, -1, -1], [-1, -1, -1]))
	assert_array(layout.detached()).is_equal([2])
	assert_int(layout.group_of[2]).is_equal(1)
	assert_bool(layout.cell_of[2].y > layout.cell_of[0].y).is_true()
	assert_bool(layout.report().size() >= 1).is_true()


# --- the creature paths ----------------------------------------------------------------------------------------------

func _digest(paths: Array[CreaturePaths.Path]) -> Array:
	return paths.map(func(path: CreaturePaths.Path) -> int: return path.digest())


func test_a_trace_is_the_same_every_time() -> void:
	for pair in TRACED:
		var sector := Catalog.sector(pair[0])
		var first := CreaturePaths.trace_screen(sector, pair[1], 150)
		var second := CreaturePaths.trace_screen(sector, pair[1], 150)
		assert_array(_digest(second)).override_failure_message("sector %d screen %d" % pair).is_equal(_digest(first))
		assert_int(first.size()).is_equal(second.size())
	# a different sub place or seed is allowed to differ, but is itself the same every time
	var again := CreaturePaths.trace_screen(Ground.main(), 4, 150, CreaturePaths.SUB_RIGHT, 7)
	assert_array(_digest(CreaturePaths.trace_screen(Ground.main(), 4, 150, CreaturePaths.SUB_RIGHT, 7))).is_equal(_digest(again))


func test_a_trace_changes_nothing_of_the_game() -> void:
	var sector := Ground.main()
	var before: Array = []
	for foe in sector.foes:
		before.append([foe.pos, foe.frame, foe.flip, foe.dormant, foe.hidden, foe.pc, foe.script_hit, foe.script_ink])
	var bytes := sector.foe_bytecode.duplicate()
	var ticks := GameClock.tick_count
	CreaturePaths.trace_sector(sector, 100)
	var after: Array = []
	for foe in sector.foes:
		after.append([foe.pos, foe.frame, foe.flip, foe.dormant, foe.hidden, foe.pc, foe.script_hit, foe.script_ink])
	assert_array(after).is_equal(before)
	assert_array(sector.foe_bytecode).is_equal(bytes)
	assert_int(GameClock.tick_count).is_equal(ticks)


func test_a_trace_is_what_the_rules_do() -> void:
	# the same creatures, in the same order, with the same dice and the sub standing at the same place: `SimWorld` and the trace agree
	# on where every creature of the screen is after N ticks
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.reset()
	var compared := 0
	var moved := 0
	for pair in TRACED:
		for ticks in [1, 30, 150]:
			var sim := SimWorld.new(run)
			sim.load_sector(pair[0], pair[1])
			sim.foe_context.rng.seed = CreaturePaths.DEFAULT_SEED
			sim.sub.position = Vector2(CreaturePaths.SUB_CENTRE) - SubModel.PLAYFIELD_ORIGIN + SubModel.PICTURE_CENTER
			assert_vector(sim.sub.original_position()).is_equal(CreaturePaths.SUB_CENTRE)
			for t in ticks:
				sim.tick()
			var traced := CreaturePaths.trace_screen(Catalog.sector(pair[0]), pair[1], ticks, CreaturePaths.SUB_CENTRE)
			for path in traced:
				var vm := sim.foes[path.foe_index].vm
				var message := "sector %d screen %d creature %d after %d ticks" % [pair[0], pair[1], path.foe_index, ticks]
				if vm.screen != pair[1]:
					continue                                                       # it left the screen: the trace keeps the place it left from
				compared += 1
				moved += 0 if path.still else 1
				assert_vector(path.end_pos).override_failure_message(message).is_equal(Vector2i(vm.x, vm.y))
				assert_int(path.end_frame).override_failure_message(message).is_equal(vm.frame)
				assert_bool(path.end_flip).override_failure_message(message).is_equal(vm.flip)
				assert_bool(path.end_hidden).override_failure_message(message).is_equal(vm.hidden)
	assert_bool(compared > 20 and moved > 10).override_failure_message("only %d creatures compared, %d of them moving" % [compared, moved]).is_true()


func test_a_trace_names_the_creatures_that_move() -> void:
	var moving := 0
	var standing := 0
	for screen in SectorData.SCREEN_COUNT:
		for path in CreaturePaths.trace_screen(Ground.main(), screen, 200):
			if path.still:
				standing += 1
			else:
				moving += 1
				assert_bool(not path.segments.is_empty() or path.ticks_hidden > 0).is_true()
				assert_bool(path.bounds.size.x >= 0.0).is_true()
	assert_bool(moving > 0).is_true()
	# creature 3 of the ground sector (screen 1) paces right and left: its path is more than one point
	var fish := CreaturePaths.trace_screen(Ground.main(), 1, 200).filter(func(path: CreaturePaths.Path) -> bool: return path.foe_index == 3)
	assert_int(fish.size()).is_equal(1)
	assert_bool(fish[0].still).is_false()


func test_a_dormant_creature_that_nothing_wakes_stands_still() -> void:
	# the ground sector, screen 1: creature 5 is dormant and hidden (the awake creature 3 is on the same screen)
	var paths := CreaturePaths.trace_screen(Ground.main(), 1, 100)
	var sleeper: Array = paths.filter(func(path: CreaturePaths.Path) -> bool: return path.foe_index == Ground.MAIN_DORMANT)
	assert_int(sleeper.size()).is_equal(1)
	assert_bool(sleeper[0].still).is_true()


# --- the model -------------------------------------------------------------------------------------------------------------

func test_the_model_lists_everything_the_data_holds() -> void:
	for index in Catalog.sector_ids():
		var model := SectorOverviewModel.for_sector(index)
		var sector := model.sector
		var pieces := 0
		var canisters := 0
		var creatures := 0
		var triggers := 0
		for screen in SectorData.SCREEN_COUNT:
			pieces += model.objects_of(screen, SectorOverviewModel.Kind.PIECE).size()
			canisters += model.objects_of(screen, SectorOverviewModel.Kind.CANISTER).size()
			creatures += model.objects_of(screen, SectorOverviewModel.Kind.CREATURE).size()
			triggers += model.objects_of(screen, SectorOverviewModel.Kind.TRIGGER).size()
			assert_int(model.objects_of(screen, SectorOverviewModel.Kind.TRIGGER).size()).is_equal(sector.screens[screen].triggers.size())
		assert_int(pieces + canisters).override_failure_message("sector %d pieces" % index).is_equal(sector.pieces.size())
		assert_int(canisters).override_failure_message("sector %d canisters" % index).is_equal(0 if sector.pieces.is_empty() else 1)
		if not sector.pieces.is_empty():                                     # the canister is piece 0
			assert_int(model.objects_of(sector.pieces[0].screen, SectorOverviewModel.Kind.CANISTER)[0]["index"]).is_equal(0)
		assert_int(creatures).override_failure_message("sector %d creatures" % index).is_equal(sector.foes.size())
		assert_int(model.objects_of(0, SectorOverviewModel.Kind.LAUNCH).size()).is_equal(1)
		assert_int(model.objects_of(0, SectorOverviewModel.Kind.START).size()).is_equal(1)
		assert_int(model.objects_of(SimWorld.DOCK_SCREEN, SectorOverviewModel.Kind.DOCK).size()).is_equal(1)
		assert_int(model.objects_of(SimWorld.finale_screen(index), SectorOverviewModel.Kind.FINALE).size()).is_equal(1 if SimWorld.finale_screen(index) >= 0 else 0)
		for screen in SectorData.SCREEN_COUNT:
			assert_str(model.screen_text(screen)).contains("Screen %d" % screen)


func test_an_object_is_found_where_it_is_drawn() -> void:
	var model := SectorOverviewModel.for_sector(Ground.MAIN)
	var piece := model.objects_of(model.sector.pieces[1].screen, SectorOverviewModel.Kind.PIECE)[0]
	var rect: Rect2 = piece["rect"]
	var found := model.object_at(piece["screen"], rect.get_center())
	assert_str(found["title"]).is_equal(piece["title"])
	assert_bool(model.object_at(piece["screen"], Vector2(-500, -500)).is_empty()).is_true()
	assert_bool(not model.object_at(piece["screen"], rect.position - Vector2(3, 3), 5.0).is_empty()).is_true()


func test_the_reachability_overlay_is_the_sweeps_answer() -> void:
	# the ground sector: everything can be reached; a copy with a piece sealed into a pocket of rock: the overlay says what the sweep says
	var plain := SectorOverviewModel.for_sector(Ground.MAIN).reach()
	assert_bool(plain.piece_reachable.all(func(reachable: bool) -> bool: return reachable)).is_true()
	assert_bool(plain.dock_reachable).is_true()
	var sealed := Ground.copy_of()
	sealed.screens[11] = sealed.screens[11].duplicate_deep() as ScreenData
	for i in ScreenData.TILE_BYTES:
		sealed.screens[11].tiles[i] = 0x41
	for row in range(6, 12):
		for column in range(15, 26):
			sealed.screens[11].tiles[row * ScreenData.TILE_COLUMNS + column] = 0
	sealed.pieces[3].screen = 11
	sealed.pieces[3].pos = Vector2i(300, 150)
	var model := SectorOverviewModel.new(sealed)
	var reach := model.reach()
	var sweep := ReachSweep.analyze(ReachSweep.prepare_for(sealed))
	assert_int(reach.piece_reachable.size()).is_equal(sweep["pieces"].size())
	for i in reach.piece_reachable.size():
		assert_bool(reach.piece_reachable[i]).override_failure_message("piece %d" % i).is_equal(sweep["pieces"][i]["orig_level"] >= 0)
	assert_bool(reach.piece_reachable[3]).is_false()
	assert_int(reach.states).is_equal(sweep["states"])
	if sweep.has("dock"):
		assert_bool(reach.dock_reachable).is_equal(sweep["dock"] >= 0)
	assert_int(reach.screen_reached.size()).is_equal(SectorData.SCREEN_COUNT)
	assert_bool(reach.screen_reached[0]).is_true()
	assert_str(model.reach_summary()).contains("reachable")
	# the picture of it: one pixel per column of 2 playfield pixels, and the launch point (middle of the sub) is lit
	var picture := plain.mask(0)
	assert_int(picture.get_width()).is_equal(SectorReach.X_COUNT)
	assert_int(picture.get_height()).is_equal(SectorReach.Y_COUNT)
	var launch := SectorReach.LAUNCH
	assert_int(picture.get_pixel((launch.y - SectorReach.X_MIN) / 2, launch.z - SectorReach.Y_MIN).a8).is_greater(0)


func test_the_mask_lines_up_with_the_playfield() -> void:
	# the middle of the sub at the launch point is at window (96 + 48, 202 + 27), the playfield pixel (128, 197): column 64, row 199
	var launch := SectorReach.LAUNCH
	var centre := Vector2(launch.y + 48, launch.z + 27) - SectorOverviewModel.ORIGIN
	var column := (launch.y - SectorReach.X_MIN) / 2
	var row := launch.z - SectorReach.Y_MIN
	assert_float(centre.x).is_equal(2.0 * column)
	assert_float(centre.y).is_equal(row - 2.0)


# --- the scene ---------------------------------------------------------------------------------------------------------------

func test_the_scene_loads_for_a_few_sectors() -> void:
	var overview := auto_free((load(SCENE) as PackedScene).instantiate()) as SectorOverview
	add_child(overview)
	await get_tree().process_frame
	for index in [Ground.MAIN, Ground.MAP, Ground.TANGLE, Ground.FINALE, Ground.LEDGE]:
		overview.load_sector(index)
		await get_tree().process_frame
		assert_int(overview.sector_index).is_equal(index)
		assert_int(overview.canvas().model.sector.index).is_equal(index)
		assert_bool(overview.canvas().custom_minimum_size.x > 0.0).is_true()
		# every screen has a place inside the canvas
		for screen in SectorData.SCREEN_COUNT:
			var rect := overview.canvas().screen_rect(screen)
			assert_bool(rect.position.x >= 0.0 and rect.position.y >= 0.0).is_true()
			assert_bool(rect.end.x <= overview.canvas().custom_minimum_size.x + 0.5 and rect.end.y <= overview.canvas().custom_minimum_size.y + 0.5).is_true()
	overview.set_overlay(SectorOverviewCanvas.Overlay.CURRENTS, true)
	overview.set_overlay(SectorOverviewCanvas.Overlay.REACHABILITY, true)
	overview.set_overlay(SectorOverviewCanvas.Overlay.PATHS, true)
	await get_tree().process_frame
	await get_tree().process_frame


func test_clicking_an_object_inspects_it_and_a_double_click_on_a_screen_opens_it() -> void:
	var overview := auto_free((load(SCENE) as PackedScene).instantiate()) as SectorOverview
	add_child(overview)
	await get_tree().process_frame
	overview.load_sector(Ground.MAIN)
	var canvas := overview.canvas()
	canvas.zoom = 0.5
	var opened: Array = []
	overview.screen_open_requested.connect(func(sector: int, screen: int) -> void: opened.append([sector, screen]))
	var picked: Array = []
	canvas.object_picked.connect(func(object: Dictionary) -> void: picked.append(object))
	# the first creature of screen 4
	var creature := canvas.model.objects_of(4, SectorOverviewModel.Kind.CREATURE)[0]
	var at := canvas.origin_of(4) + (creature["rect"] as Rect2).get_center() * canvas.zoom
	canvas.click(at)
	assert_array(picked).is_not_empty()
	assert_int(picked.back()["kind"]).is_equal(SectorOverviewModel.Kind.CREATURE)
	assert_int(picked.back()["index"]).is_equal(creature["index"])
	assert_bool(opened.is_empty()).is_true()
	# an empty spot of the screen: it is selected; double click: it is opened
	var empty := Vector2.ZERO
	for x in range(10, 600, 20):                    # a place of screen 3 that no object is near
		var candidate := canvas.origin_of(3) + Vector2(x, 100.0) * canvas.zoom
		if canvas.model.object_at(3, canvas.playfield_point(3, candidate), 6.0 / canvas.zoom).is_empty():
			empty = candidate
			break
	assert_bool(empty != Vector2.ZERO).is_true()
	canvas.click(empty)
	assert_int(canvas.selected_screen).is_equal(3)
	assert_bool(opened.is_empty()).is_true()
	canvas.click(empty, true)
	assert_array(opened).is_equal([[Ground.MAIN, 3]])
	# outside every screen: nothing is selected
	canvas.click(Vector2(1, 1))
	assert_bool(canvas.selected_object.is_empty()).is_true()


## The map is derived from the sector it shows: when the sector says it changed (the screen editor's save, the Sector Inspector) or its
## creature script does, the map is built again from it, and the selected screen stays selected.
func test_the_map_follows_a_change_of_its_sector() -> void:
	var overview := auto_free((load(SCENE) as PackedScene).instantiate()) as SectorOverview
	add_child(overview)
	await get_tree().process_frame
	var sector := Ground.main().duplicate() as SectorData                 # (a copy: the catalog's sector is left alone)
	overview.show_sector(sector)
	overview.select_screen(4)
	var before := overview.model
	var creatures := before.objects_of(2, SectorOverviewModel.Kind.CREATURE).size()
	var foes := sector.foes.duplicate()
	foes.append(sector.new_foe(2, Vector2i(200, 150)))
	sector.foes = foes                                                    # a creature was added on screen 2 and saved
	sector.emit_changed()
	sector.emit_changed()
	await get_tree().process_frame
	assert_object(overview.model).is_not_same(before)
	assert_object(overview.canvas().model).is_same(overview.model)
	assert_int(overview.model.objects_of(2, SectorOverviewModel.Kind.CREATURE).size()).is_equal(creatures + 1)
	assert_int(overview.canvas().selected_screen).is_equal(4)
	var after_sector := overview.model
	sector.foe_script.emit_changed()                                      # the Foe Script screen saved the text
	await get_tree().process_frame
	assert_object(overview.model).is_not_same(after_sector)


func test_without_a_host_opening_a_screen_zooms_in() -> void:
	var overview := auto_free((load(SCENE) as PackedScene).instantiate()) as SectorOverview
	add_child(overview)
	await get_tree().process_frame
	overview.load_sector(Ground.MAIN)
	await get_tree().process_frame
	overview.open_screen(5)
	await get_tree().process_frame
	assert_bool(overview.canvas().zoom >= 0.3).is_true()


func test_the_number_box_follows_a_sector_made_after_the_panel_was_built() -> void:
	var dir := "user://overview_range_test"
	PackFiles.remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	assert_bool(SectorFactory.new_from_template(32, 0, 0, dir).ok()).is_true()
	Catalog.sectors_dir = dir
	var overview := auto_free((load(SCENE) as PackedScene).instantiate()) as SectorOverview
	add_child(overview)
	await get_tree().process_frame
	var box: SpinBox = overview._sector_box
	assert_float(box.max_value).is_equal(32.0)
	var made := SectorFactory.new_from_template(36, 0, 0, dir)         # "New sector..." while the editor runs
	assert_bool(made.ok()).override_failure_message(made.error).is_true()
	overview.hide()
	overview.show()                                                     # the Sector Overview tab is chosen again
	assert_float(box.max_value).is_equal(36.0)
	box.value = 36                                                      # typing 36 now loads it
	await get_tree().process_frame
	assert_int(overview.sector_index).is_equal(36)
	Catalog.sectors_dir = Catalog.SECTORS_DIR
	PackFiles.remove_tree(dir)
