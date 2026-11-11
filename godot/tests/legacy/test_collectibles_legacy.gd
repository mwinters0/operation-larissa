class_name TestCollectiblesLegacy
extends GdUnitTestSuite
## The original's pieces: sector 0 holds the canister (piece 0) at window (176, 256) on screen 9 and piece 6 at (576, 144) on the same screen; the animation tables of
## the pieces are the decompiled ones; the canister problem of sector 0 delivers log entry 4. The pieces' rules, with the ground sector of dev, are in
## `tests/engine/test_collectibles.gd`.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _world: SectorWorld


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.load_sector(0, 9)
	_world.start_flight()


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func test_sector_0_screen_9_shows_the_canister_and_piece_6_at_their_coordinates() -> void:
	var indices: Array = _world.original.collectibles.get_children().map(func(c: Collectible) -> int: return c.index)
	indices.sort()
	assert_array(indices).is_equal([0, 6])
	assert_that(_world.sector.pieces[0].pos).is_equal(Vector2i(176, 256))
	assert_that(_world.sector.pieces[6].pos).is_equal(Vector2i(576, 144))


func test_the_original_sectors_have_seven_to_eleven_pieces_and_the_finales_at_most_one() -> void:
	for sector_index in Catalog.ORIGINAL_SECTOR_COUNT:
		var pieces := Catalog.sector(sector_index).pieces
		if sector_index >= 30:
			assert_int(pieces.size()).is_less_equal(1)              # the finale sectors have none (30) or one (31)
		else:
			assert_int(pieces.size()).is_between(7, 11)


func test_the_animation_tables_are_the_decompiled_ones() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../extracted/tables/piece_animation.json"))
	assert_int(int(data["period"])).is_equal(16)
	for tick in 40:
		assert_int(Collectible.picture_for(true, tick)).is_equal(int(data["canister_pictures"][tick % 2]))
		assert_int(Collectible.picture_for(false, tick)).is_equal(int(data["rock_pictures"][tick % 16]))
	assert_str(Collectible.animation_for(true)).is_equal(Collectible.CANISTER_ANIMATION)
	assert_str(Collectible.animation_for(false)).is_equal(Collectible.ROCK_ANIMATION)


func test_the_canister_problem_has_the_sectors_log_entry() -> void:
	var problem := _world.make_problem(SimWorld.CANISTER_SLOT)
	assert_str(problem.title).is_equal("Data Canister")
	assert_str(problem.success).starts_with("ENTRY 1.04")            # sector 0 delivers entry 4 (`Campaign.log_unlock_order`)
