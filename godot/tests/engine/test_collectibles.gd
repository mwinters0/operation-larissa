class_name TestCollectibles
extends GdUnitTestSuite
## Teaches: testing a rule that is rectangle arithmetic (no physics sensors): move the sub on top of a piece and run a tick.
## The ground sector (`Ground.MAIN`): the canister (piece 0) lies on screen 9 with piece 6, screen 3 holds piece 3 alone and screen 5 has a math trigger.
## (The original's coordinates and picture tables are checked in `tests/legacy/test_collectibles_legacy.gd`.)

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const TRIGGER_SLOT := 10

var _world: SectorWorld
var _sounds: Array
var _problems: Array


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_sounds = []
	_problems = []
	_world.sfx_requested.connect(func(id: StringName) -> void: _sounds.append(id))
	_world.problem_requested.connect(func(slot: int) -> void: _problems.append(slot))
	_world.load_sector(Ground.MAIN, 9)
	_world.start_flight()


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


func _put_sub_on(piece: int) -> void:
	_world.sim.sub.position = Vector2(_world.sector.pieces[piece].pos) - Sub.PLAYFIELD_ORIGIN + Collectible.PICTURE_SIZE / 2.0
	_world.tick()


func test_the_screen_shows_the_pieces_that_lie_on_it() -> void:
	var indices: Array = _world.original.collectibles.get_children().map(func(c: Collectible) -> int: return c.index)
	indices.sort()
	assert_array(indices).is_equal([0, 6])


func test_other_screens_show_other_pieces() -> void:
	_world.load_screen(0)
	assert_int(_world.original.collectibles.get_child_count()).is_equal(1)
	assert_int((_world.original.collectibles.get_child(0) as Collectible).index).is_equal(1)


# --- which picture a piece gets (DrawProbePieces 0x42dc3b: piece id 1 = the canister, all others rocks) ---------------

func test_in_every_sector_only_piece_0_is_the_canister() -> void:
	for sector_index in Catalog.sector_ids():
		var pieces := Catalog.sector(sector_index).pieces
		assert_int(pieces.size()).is_less_equal(SectorData.MAX_PIECES)
		for i in pieces.size():
			assert_bool(pieces[i].is_canister).is_equal(i == 0)


func test_every_pieces_picture_is_a_rock_except_the_canister() -> void:
	# What the player sees on the first tick, for all pieces of all sectors: a picture of the canister's animation on the canister and
	# one of the rock's animation on every other piece; the two animations share no picture.
	var canister := _animation_pictures(Collectible.CANISTER_ANIMATION)
	var rock := _animation_pictures(Collectible.ROCK_ANIMATION)
	for picture in canister:
		assert_bool(picture in rock).is_false()
	var world := _world
	for sector_index in Catalog.sector_ids():
		world.load_sector(sector_index, 0)
		for i in world.sector.pieces.size():
			var piece := world.sector.pieces[i]
			world.load_screen(piece.screen)
			for node: Collectible in world.original.collectibles.get_children():
				var shown := node.sprite.sprite_frames.get_frame_texture(node.sprite.animation, node.sprite.frame)
				var picture := _picture_number(shown)
				assert_bool(picture in (canister if node.index == 0 else rock)) \
						.override_failure_message("sector %d piece %d shows picture %d" % [sector_index, node.index, picture]).is_true()


func test_a_screen_with_one_piece_that_is_not_the_canister_shows_a_rock() -> void:
	_world.load_screen(3)                                               # the screen of piece 3
	assert_int(_world.original.collectibles.get_child_count()).is_equal(1)
	var node := _world.original.collectibles.get_child(0) as Collectible
	assert_int(node.index).is_equal(3)
	assert_str(node.sprite.animation).is_equal("rock")


func _picture_number(texture: Texture2D) -> int:
	var frames := Catalog.pieces_frames()
	for i in frames.get_frame_count(&"all"):
		if frames.get_frame_texture(&"all", i) == texture:
			return i
	return -1


## The pictures (numbers in the pieces bundle) of an animation of `pieces_frames`, one entry per frame.
func _animation_pictures(animation: StringName) -> Array[int]:
	var frames := Catalog.pieces_frames()
	var found: Array[int] = []
	for i in frames.get_frame_count(animation):
		found.append(_picture_number(frames.get_frame_texture(animation, i)))
	return found


func test_the_canister_flashes_by_its_animation_one_frame_a_tick() -> void:
	var node := _world.original.collectibles.get_children().filter(func(c: Collectible) -> bool: return c.index == 0)[0] as Collectible
	var pictures := _animation_pictures(Collectible.CANISTER_ANIMATION)
	assert_int(pictures.size()).is_greater(1)
	var changes := 0
	var previous := -1
	for i in pictures.size() * 2:
		var picture := _picture_number(node.sprite.sprite_frames.get_frame_texture(node.sprite.animation, node.sprite.frame))
		assert_int(picture).is_equal(pictures[GameClock.tick_count % pictures.size()])
		assert_int(picture).is_equal(Collectible.picture_for(true, GameClock.tick_count))
		changes += 1 if picture != previous else 0
		previous = picture
		GameClock.step()
	assert_int(changes).is_greater(1)                                   # it does flash


func test_a_rock_sparkles_by_its_animation_and_all_rocks_stay_in_step() -> void:
	_world.load_screen(9)
	var rock := _world.original.collectibles.get_children().filter(func(c: Collectible) -> bool: return c.index == 6)[0] as Collectible
	var pictures := _animation_pictures(Collectible.ROCK_ANIMATION)
	var resting := pictures[0]
	var sparkles_per_cycle := pictures.filter(func(picture: int) -> bool: return picture != resting).size()
	assert_int(sparkles_per_cycle).is_between(1, pictures.size() - 1)
	var sparkles := 0
	var start := GameClock.tick_count
	for i in pictures.size() * 2:
		var picture := _picture_number(rock.sprite.sprite_frames.get_frame_texture(rock.sprite.animation, rock.sprite.frame))
		assert_int(picture).is_equal(pictures[GameClock.tick_count % pictures.size()])
		if picture != resting:
			sparkles += 1
		GameClock.step()
	assert_int(GameClock.tick_count).is_equal(start + pictures.size() * 2)
	assert_int(sparkles).is_equal(sparkles_per_cycle * 2)               # the same cycle twice
	# A rock built later (another screen, any time) shows the same picture as one built earlier.
	_world.load_screen(0)
	var other := _world.original.collectibles.get_child(0) as Collectible
	_world.load_screen(9)
	var again := _world.original.collectibles.get_children().filter(func(c: Collectible) -> bool: return c.index == 6)[0] as Collectible
	assert_int(other.sprite.frame).is_equal(again.sprite.frame)
