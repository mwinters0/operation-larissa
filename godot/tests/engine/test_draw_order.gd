class_name TestDrawOrder
extends GdUnitTestSuite
## The order things are drawn in. In Godot that is the order of the nodes in the tree (later = in front), so the
## test just compares child indices. The order is the original's (DoAction 0x417ffc, DrawScreen 0x433f1c):
## still picture (background, back decos, tiles, mid decos), pieces, sub, creatures, ink, front decos, animated
## decos, the random bubbles. The animated decos are drawn OVER the sub (a swaying plant overlaps it); the bubbles are drawn after everything else.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const GAME_SCENE := "res://src/gameplay/game.tscn"


func _index(world: SectorWorld, node_name: String) -> int:
	return world.original.get_node(node_name).get_index()


func test_the_world_draws_in_the_order_of_the_original() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var order: Array[String] = ["Background", "BackDecos", "Walls", "MidDecos", "Collectibles", "Sub", "Foes",
			"Pellets", "FrontDecos", "AnimDecos", "Bubbles"]
	for i in order.size() - 1:
		assert_bool(_index(world, "%" + order[i]) < _index(world, "%" + order[i + 1])) \
				.override_failure_message("%s must be drawn before %s" % [order[i], order[i + 1]]).is_true()


func test_animated_decos_cover_the_sub_and_the_creatures() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_bool(world.original.anim_decos.get_index() > world.original.sub.get_index()).is_true()
	assert_bool(world.original.anim_decos.get_index() > world.original.foes_layer.get_index()).is_true()


func test_pieces_lie_behind_the_sub() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_bool(world.original.collectibles.get_index() < world.original.sub.get_index()).is_true()


func test_the_playfield_is_drawn_after_the_hud_frame() -> void:
	# The playfield starts at x = 16 and is drawn after the frame, so its first column shows. (Drawing the HUD frame last blacked it out.)
	var game := scene_runner(GAME_SCENE).scene() as Game
	assert_bool(game.get_node("%Hud").get_index() < game.get_node("%SectorWorld").get_index()).is_true()
	assert_int(int(game.world.global_position.x)).is_equal(16)


# --- the station against the layers that depend on the routine that draws them ----------------------------

func _world_at(screen: int) -> SectorWorld:
	GameClock.paused = true
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, screen)
	return world


func _before(first: Node, second: Node) -> bool:
	return first.get_index() < second.get_index()


func test_in_play_the_mid_decos_the_pieces_and_the_sub_are_drawn_over_the_station() -> void:
	# `DrawScreen` (0x433f1c) draws the station (`DrawSupplyStation` 0x4327a6) BEFORE the mid decos, into the still picture; the frame loop
	# (`DoAction`) draws the pieces and the sub over the still. 165 mid decos of the original lie over a station's picture.
	var original := _world_at(11).original
	assert_bool(_before(original.station, original.mid_decos)).is_true()
	assert_bool(_before(original.station, original.collectibles)).is_true()
	assert_bool(_before(original.station, original.sub)).is_true()
	assert_bool(_before(original.station, original.foes_layer)).is_true()


func test_during_a_launch_the_station_covers_the_sub_and_the_mid_decos_and_the_pieces_lie_over_it() -> void:
	# `ExitSupplyStation` (0x4328b0): DrawSub, the station's body and door, DrawProbePieces, update_animals, front decos, animated decos.
	var world := _world_at(0)
	var original := world.original
	world.sim.start_launch()
	assert_bool(_before(original.mid_decos, original.sub)).is_true()
	assert_bool(_before(original.sub, original.station)).is_true()
	assert_bool(_before(original.station, original.collectibles)).is_true()
	assert_bool(_before(original.collectibles, original.foes_layer)).is_true()
	assert_bool(_before(original.mid_decos, original.station)).is_true()


## Deliberate deviation from the original (G44): the original keeps the station over the mid decos after a launch until a dirty
## rectangle restores them; the port puts the mid decos over it again at once.
func test_after_a_launch_the_layers_are_in_the_order_of_play_again() -> void:
	var world := _world_at(0)
	var original := world.original
	world.sim.start_launch()
	for tick in world.sim.sequence.ticks:
		world.tick()
	assert_bool(world.sim.sequence.is_done()).is_true()
	assert_bool(_before(original.station, original.mid_decos)).is_true()
	assert_bool(_before(original.mid_decos, original.collectibles)).is_true()
	assert_bool(_before(original.collectibles, original.sub)).is_true()


func test_during_the_dock_and_the_balloon_the_station_covers_the_mid_decos_and_stays_so() -> void:
	# `EnterSupplyStation` (0x432b96) and `LaunchBalloon` (0x432eae) redraw the station over the still; the dock is followed by the balloon, and
	# nothing in between draws the play order.
	var world := _world_at(11)
	var original := world.original
	world.start_flight(400, 200, 6)
	world.sim.start_dock()
	assert_bool(_before(original.sub, original.station)).is_true()
	assert_bool(_before(original.mid_decos, original.station)).is_true()
	for tick in world.sim.sequence.ticks:
		world.tick()
	assert_bool(_before(original.mid_decos, original.station)).is_true()
	world.sim.start_balloon()
	assert_bool(_before(original.mid_decos, original.station)).is_true()
	assert_bool(_before(original.station, original.collectibles)).is_true()
	world.load_sector(0, 0)                                                  # the next sector: the order of play
	assert_bool(_before(original.station, original.mid_decos)).is_true()


func test_no_bubbles_are_drawn_while_a_supply_trip_runs() -> void:
	# `ExitSupplyStation`, `EnterSupplyStation` and `LaunchBalloon` never call `UpdateAmbientBubbles` (0x41a800).
	var world := _world_at(4)
	var bubbles := world.original.bubbles
	bubbles.rules = bubbles.rules.duplicate()
	bubbles.rules.spawn_chance = 1
	bubbles.step()
	assert_int(bubbles.active_count()).is_greater(0)
	world.sim.start_launch()
	assert_int(bubbles.active_count()).is_equal(0)
	bubbles.step()
	assert_int(bubbles.active_count()).is_equal(0)
	for tick in world.sim.sequence.ticks:
		world.tick()
	bubbles.step()
	assert_int(bubbles.active_count()).is_greater(0)                         # (the play goes on)
