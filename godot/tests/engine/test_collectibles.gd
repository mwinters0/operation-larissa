class_name TestCollectibles
extends GdUnitTestSuite
## Teaches: testing a rule that is rectangle arithmetic (no physics sensors): move the sub on top of a piece and run a tick.
## The ground sector (`Ground.MAIN`): the canister (piece 0) lies on screen 9 with piece 6, screen 3 holds piece 3 alone and screen 5 has a math trigger.
## (The original's coordinates and picture tables are in `tests/legacy/test_collectibles_legacy.gd`.)

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
	# What the player sees on the first tick, for all pieces of all sectors: the rock picture 0 or the red / green
	# canister picture 3 (picture 4 on the next tick); never a canister picture on a rock or the other way round.
	var world := _world
	for sector_index in Catalog.sector_ids():
		world.load_sector(sector_index, 0)
		for i in world.sector.pieces.size():
			var piece := world.sector.pieces[i]
			world.load_screen(piece.screen)
			for node: Collectible in world.original.collectibles.get_children():
				var shown := node.sprite.sprite_frames.get_frame_texture(node.sprite.animation, node.sprite.frame)
				var picture := _picture_number(shown)
				assert_bool(picture in ([3, 4] if node.index == 0 else [0, 1, 2])) \
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


func test_the_canister_flashes_red_and_green_every_tick() -> void:
	var node := _world.original.collectibles.get_children().filter(func(c: Collectible) -> bool: return c.index == 0)[0] as Collectible
	var seen: Array[int] = []
	for i in 6:
		seen.append(_picture_number(node.sprite.sprite_frames.get_frame_texture(node.sprite.animation, node.sprite.frame)))
		GameClock.step()
	assert_array(seen).is_equal([seen[0], 7 - seen[0], seen[0], 7 - seen[0], seen[0], 7 - seen[0]])   # 3,4,3,4,... (or 4,3,...)
	assert_array([seen[0], seen[1]]).contains_exactly_in_any_order([3, 4])


func test_a_rock_sparkles_on_3_of_16_ticks_and_all_rocks_stay_in_step() -> void:
	_world.load_screen(9)
	var rock := _world.original.collectibles.get_children().filter(func(c: Collectible) -> bool: return c.index == 6)[0] as Collectible
	var sparkles := 0
	var start := GameClock.tick_count
	for i in 32:
		var picture := _picture_number(rock.sprite.sprite_frames.get_frame_texture(rock.sprite.animation, rock.sprite.frame))
		if picture != 0:
			sparkles += 1
		GameClock.step()
	assert_int(GameClock.tick_count).is_equal(start + 32)
	assert_int(sparkles).is_equal(6)                                    # per 16-tick cycle: pictures 1, 2, 1 (3 ticks), over 2 cycles
	# A rock built later (another screen, any time) shows the same picture as one built earlier.
	_world.load_screen(0)
	var other := _world.original.collectibles.get_child(0) as Collectible
	_world.load_screen(9)
	var again := _world.original.collectibles.get_children().filter(func(c: Collectible) -> bool: return c.index == 6)[0] as Collectible
	assert_int(other.sprite.frame).is_equal(again.sprite.frame)


func test_the_pieces_freeze_while_the_clock_is_stopped() -> void:
	var node := _world.original.collectibles.get_child(0) as Collectible
	var frame := node.sprite.frame
	GameClock.paused = false                                            # the real clock runs, but a problem screen holds it
	GameClock.hold()
	assert_int(GameClock.advance(1.0)).is_equal(0)
	assert_int(node.sprite.frame).is_equal(frame)
	GameClock.release()
	GameClock.paused = true


func test_touching_a_piece_collects_it_once() -> void:
	await _put_sub_on(6)
	assert_bool(GameState.has_piece(6)).is_true()
	assert_int(GameState.pieces_collected()).is_equal(1)
	assert_array(_sounds).is_equal([SimWorld.SFX_PIECE_PICKED_UP])
	assert_int(_world.original.collectibles.get_child_count()).is_equal(1)       # the piece is gone from the sea floor
	assert_array(_problems).is_empty()                                  # a capsule piece asks nothing


func test_touching_the_canister_starts_the_data_canister_problem_when_its_countdown_has_run_down() -> void:
	# `DoAction` (0x417ffc, 0x4182d5): the canister stores MessageLightCountdown (2 in the original, `Tuning.canister_pending_ticks`) and
	# problem id 1; the problem opens when the loop top sees the countdown at 1, i.e. in the NEXT tick (the original's), not in the tick
	# of the pick-up.
	await _put_sub_on(0)
	assert_bool(GameState.has_piece(0)).is_true()
	assert_int(_world.pending_slot).is_equal(SimWorld.CANISTER_SLOT)
	var countdown := Tuning.resolve().canister_pending_ticks
	assert_int(_world.pending_ticks).is_equal(countdown)
	assert_array(_problems).is_empty()
	for i in countdown - 2:
		_world.tick()
		assert_array(_problems).is_empty()
	_world.tick()
	assert_array(_problems).is_equal([SimWorld.CANISTER_SLOT])
	assert_bool(_world.problem_active).is_true()
	assert_int(_world.pending_slot).is_equal(-1)


## Screen 5: one armed trigger at window (400, 240), slot `TRIGGER_SLOT`.
func _on_the_trigger_screen() -> MathTrigger:
	_world.load_screen(5)
	_world.foes_active = false
	return _world.original.triggers_layer.get_child(0) as MathTrigger


# G34: taking the canister overwrites a pending trigger countdown.
func test_taking_the_canister_overwrites_a_pending_trigger_countdown() -> void:
	var trigger := _on_the_trigger_screen()
	_world.sim.touch_trigger(trigger.model)
	for i in 10:
		_world.tick()
	assert_int(_world.pending_slot).is_equal(TRIGGER_SLOT)
	assert_int(_world.pending_ticks).is_equal(Tuning.resolve().pending_ticks - 10)
	_world.sim.take_piece(0)                                         # (a piece is taken whichever screen it lies on)
	assert_int(_world.pending_slot).is_equal(SimWorld.CANISTER_SLOT)
	assert_int(_world.pending_ticks).is_equal(Tuning.resolve().canister_pending_ticks)
	assert_bool(_world.problem_active).is_false()                       # the canister did not open its problem at once
	assert_bool(_world.is_trigger_armed(5, 0)).is_false()               # the trigger is spent ...
	for i in Tuning.resolve().canister_pending_ticks - 1:
		_world.tick()
	assert_array(_problems).is_equal([SimWorld.CANISTER_SLOT])       # ... and its problem is never shown
	for i in Tuning.resolve().pending_ticks:
		_world.tick()
	assert_array(_problems).is_equal([SimWorld.CANISTER_SLOT])


func test_a_trigger_firing_in_the_tick_of_the_pick_up_wins_and_the_canister_gets_no_problem() -> void:
	# `CheckProbeCollision` runs before `DetectMathTrigger`: in one tick the canister is taken (countdown 2, id 1) and
	# then the trigger overwrites it (countdown 36, its slot). The canister is gone for good and asks nothing.
	var trigger := _on_the_trigger_screen()
	var data := _world.sector.pieces[0].duplicate() as PieceData
	data.pos = trigger.data.pos                                         # the canister lies on the trigger point
	_world.sim.pieces.append(PieceModel.new(data, 0))
	_world.sim.sub.position = Vector2(trigger.data.pos) - Sub.PLAYFIELD_ORIGIN
	_world.tick()
	assert_bool(GameState.has_piece(0)).is_true()
	assert_int(_world.pending_slot).is_equal(TRIGGER_SLOT)
	assert_int(_world.pending_ticks).is_equal(Tuning.resolve().pending_ticks)
	assert_bool(_world.is_trigger_armed(5, 0)).is_false()
	for i in Tuning.resolve().pending_ticks:
		_world.tick()
	assert_array(_problems).is_equal([TRIGGER_SLOT])                              # the trigger's problem only: no canister problem ever
	assert_bool(GameState.has_piece(0)).is_true()


func test_running_out_of_air_during_the_canister_problem_puts_the_canister_back() -> void:
	await _put_sub_on(0)
	await get_tree().process_frame
	var session := ProblemSession.new(_world.make_problem(1))
	session.oxygen_code = OxygenModel.OUT_WITH_SPARE_TANKS
	_world.problem_resolved(1, session)
	assert_bool(GameState.has_piece(0)).is_false()
	var indices: Array = _world.original.collectibles.get_children().map(func(c: Collectible) -> int: return c.index)
	assert_bool(0 in indices).is_true()


func test_a_solved_canister_stays_collected() -> void:
	await _put_sub_on(0)
	await get_tree().process_frame
	var session := ProblemSession.new(_world.make_problem(1))
	_world.problem_resolved(1, session)
	assert_bool(GameState.has_piece(0)).is_true()
	assert_bool(_world.problem_active).is_false()


func test_collected_pieces_do_not_come_back_when_the_screen_is_rebuilt() -> void:
	await _put_sub_on(6)
	_world.load_screen(9)
	assert_int(_world.original.collectibles.get_child_count()).is_equal(1)


func test_all_pieces_are_tracked_in_the_bit_mask() -> void:
	for i in _world.sector.pieces.size():
		assert_bool(GameState.collect_piece(i)).is_true()
	assert_int(GameState.pieces_mask).is_equal((1 << _world.sector.pieces.size()) - 1)
	assert_bool(GameState.collect_piece(3)).is_false()
	GameState.begin_sector()
	assert_int(GameState.pieces_mask).is_equal(0)
