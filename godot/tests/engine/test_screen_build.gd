class_name TestScreenBuild
extends GdUnitTestSuite
## Teaches: scene_runner, which loads a real scene for a test and lets us poke at it.
## Checks that a screen's data really ends up as nodes and tiles.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"


func _world(runner: GdUnitSceneRunner) -> SectorWorld:
	return runner.scene() as SectorWorld


## Counts tile bytes of a screen by kind.
func _count(screen: ScreenData, kind: TileCodec.Kind) -> int:
	var total := 0
	for byte in screen.tiles:
		if TileCodec.decode(byte).kind == kind:
			total += 1
	return total


func test_tile_layers_match_the_tile_bytes() -> void:
	var runner := scene_runner(WORLD_SCENE)
	var world := _world(runner)
	var screens_with_currents := 0
	for sector_index in [Ground.MAIN, Ground.LEDGE, Ground.MAP]:
		world.load_sector(sector_index)
		for screen_index in 12:
			world.load_screen(screen_index)
			var screen := world.sector.screens[screen_index]
			# Every solid byte (also the invisible 0x40 wall) is a used cell of Walls;
			# every current byte is a used cell of Currents.
			assert_int(world.original.walls.get_used_cells().size()).is_equal(_count(screen, TileCodec.Kind.SOLID))
			assert_int(world.original.currents.get_used_cells().size()).is_equal(_count(screen, TileCodec.Kind.CURRENT))
			if _count(screen, TileCodec.Kind.CURRENT) > 0:
				screens_with_currents += 1
	# The check above is only meaningful if some screen really has currents.
	assert_int(screens_with_currents).is_greater(0)


func test_deco_children_match_the_lists() -> void:
	var runner := scene_runner(WORLD_SCENE)
	var world := _world(runner)
	world.load_sector(Ground.MAIN)
	for screen_index in 12:
		world.load_screen(screen_index)
		var screen := world.sector.screens[screen_index]
		assert_int(world.original.back_decos.get_child_count()).is_equal(screen.bg_decos.size())
		assert_int(world.original.mid_decos.get_child_count()).is_equal(screen.mid_decos.size())
		assert_int(world.original.front_decos.get_child_count()).is_equal(screen.fg_decos.size())
		assert_int(world.original.anim_decos.get_child_count()).is_equal(screen.anim_decos.size())


func test_background_is_the_pictures_file_of_sector_and_screen() -> void:
	# A sector of the dev tour has a background behind each screen (the picture's size is the pack's; the original's is in tests/legacy/test_screen_build_legacy.gd).
	var runner := scene_runner(WORLD_SCENE)
	var world := _world(runner)
	var sector := DevPack.TOUR_SECTORS[2]
	world.load_sector(sector, 7)
	assert_str(world.original.background.texture.resource_path).ends_with("bg_s%02d_07.png" % sector)
	world.load_screen(8)
	assert_str(world.original.background.texture.resource_path).ends_with("bg_s%02d_08.png" % sector)


func test_decos_use_slot_position_and_flip_flag() -> void:
	var runner := scene_runner(WORLD_SCENE)
	var world := _world(runner)
	world.load_sector(Ground.MAIN, 1)
	var screen := world.sector.screens[1]             # (its second deco is mirrored)
	var flagged_seen := false
	for container_and_list in [[world.original.back_decos, screen.bg_decos], [world.original.mid_decos, screen.mid_decos], [world.original.front_decos, screen.fg_decos]]:
		var container: Node2D = container_and_list[0]
		var placements: Array = container_and_list[1]
		for i in placements.size():
			var deco := container.get_child(i) as Deco
			var placement := placements[i] as DecoPlacement
			assert_int(deco.frame).is_equal(placement.slot)
			assert_that(deco.position).is_equal(Vector2(placement.pos) - Sub.PLAYFIELD_ORIGIN)    # stored in window pixels
			assert_bool(deco.flip_h).is_equal(placement.flag)
			flagged_seen = flagged_seen or placement.flag
	assert_bool(flagged_seen).is_true()


func test_reload_replaces_old_nodes() -> void:
	var runner := scene_runner(WORLD_SCENE)
	var world := _world(runner)
	world.load_sector(Ground.MAIN, 0)
	world.load_screen(Ground.ANIM_SCREEN)
	world.load_screen(Ground.ANIM_SCREEN)
	var screen := world.sector.screens[Ground.ANIM_SCREEN]
	assert_int(world.original.back_decos.get_child_count()).is_equal(screen.bg_decos.size())


func test_playfield_clips_its_contents() -> void:
	var world := _world(scene_runner(WORLD_SCENE))
	assert_bool(world.clip_contents).is_true()
	assert_that(world.size).is_equal(Vector2(608, 288))


func test_debug_toggles() -> void:
	var world := _world(scene_runner(WORLD_SCENE))
	assert_bool(world.original.currents.visible).is_false()
	world.show_currents = true
	assert_bool(world.original.currents.visible).is_true()
	world.show_collisions = true
	assert_int(world.original.walls.collision_visibility_mode).is_equal(TileMapLayer.DEBUG_VISIBILITY_MODE_FORCE_SHOW)
