class_name TestSimWorld
extends GdUnitTestSuite
## Teaches: testing the rules with no scene at all. `SimWorld` is a plain object: this test builds one, flies it for hundreds
## of ticks with scripted hands (`InputSnapshot`), records a trace of everything that happens, and compares the trace with the
## one the scene (`SectorWorld` with all its nodes) produces from the same hands. They must be the same, because the scene owns
## the very same `SimWorld` and only draws it. It also pins the events the rules emit (the skin API, `test_skin_api.gd`).
##
## The digest of the original's flights as the scene-only game produced them is in `legacy/test_creatures_legacy.gd`.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"

## [sector, first screen] of the flights: the dev tour's sectors, the arena, the closing and the fish.
const RUNS := [[DevCreatures.ARENA, 0], [DevCreatures.ARENA, 6], [1, 2], [2, 4], [3, 0], [DevCreatures.CLOSING, 0], [DevCreatures.CLOSING, 4], [4, 1], [DevCreatures.FISH, 7], [DevCreatures.FISH, 3]]
const TICKS := 500

var _events: Array[String]


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = true
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SectorWorld.skip_animations = false
	GameState.reset()


# --- a flight with scripted hands ----------------------------------------------------------

## Flies `ticks` ticks of sector `sector` from `screen` and returns the trace, one line per tick (the events of the old scene are
## in it too); every event of the rules, with its tick, is added to `all_events`. `step` runs one tick with the given hands: for a
## bare `SimWorld` it is `sim.tick`, for the scene `world.tick`. A math problem that opens is answered at once, as if the player gave
## up. `run` is the player's game the sim works on (what `GameState` is in the game).
func _fly(sim: SimWorld, run: Object, step: Callable, sector: int, screen: int, ticks: int, all_events: Array[String] = []) -> Array[String]:
	var lines: Array[String] = ["RUN %d %d" % [sector, screen]]
	_events = []
	_listen(sim)
	sim.load_sector(sector, screen)
	all_events.append_array(_events)
	sim.foe_context.rng.seed = 4242                       # (the creature scripts roll dice)
	sim.start_flight()
	var hands := SimTrace.Hands.new(sector, screen)
	for t in ticks:
		_events.clear()
		step.call(hands.at(t))
		lines.append(_state_line(sim, run, t))
		for event in _events:
			all_events.append("T%d %s" % [t, event])
			if _legacy_event(event):
				lines.append("  ev " + event)
		if sim.problem_active:
			sim.problem_resolved(1, ProblemSession.new(null))
	return lines


## One line with everything the rules know at the end of a tick (`SimTrace.state_line`).
func _state_line(sim: SimWorld, run: Object, t: int) -> String:
	return SimTrace.state_line(sim, run, t)


## The events that the scene-only game also emitted (and so are in that digest).
func _legacy_event(event: String) -> bool:
	return event.begins_with("sfx ") or event.begins_with("pending ") or event.begins_with("requested ") \
			or event.begins_with("screen ") or event == "dock" or event == "finale"


## Records every event of the rules as one line of text (`_events`), in the order they happen (`SimTrace.listen`).
func _listen(sim: SimWorld) -> void:
	SimTrace.listen(sim, _events)


func _new_run() -> Node:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node          # the script of the autoload, not in any tree
	run.reset()
	return run


# --- tests ---------------------------------------------------------------------------------

func test_a_whole_flight_runs_with_no_nodes_at_all() -> void:
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var run := _new_run()
	var sim := SimWorld.new(run)
	var events: Array[String] = []
	for the_run in RUNS:
		_fly(sim, run, sim.tick, the_run[0], the_run[1], 200, events)
	# The only node that was made is the player's game (`run`, the script of the GameState autoload); the rules made none.
	assert_int(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - nodes_before).is_less_equal(1)
	assert_bool(sim is RefCounted).is_true()
	assert_bool(events.any(func(e: String) -> bool: return e.contains("pellet_fired"))).is_true()


func test_the_scene_and_the_bare_rules_fly_the_same_flight() -> void:
	for the_run in RUNS:
		var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
		GameState.reset()
		world.sim.steer_source = Callable()                # (scripted hands: the rest of a tick that waited for a problem keeps the snapshot's, not the keyboard's)
		var scene_events: Array[String] = []
		var scene_lines := _fly(world.sim, GameState, world.tick, the_run[0], the_run[1], TICKS, scene_events)
		_check_views_show_the_rules(world)
		var run := _new_run()
		var bare := SimWorld.new(run)
		var bare_events: Array[String] = []
		var bare_lines := _fly(bare, run, bare.tick, the_run[0], the_run[1], TICKS, bare_events)
		assert_array(scene_lines).override_failure_message("run %s: the trace of the scene differs from the bare rules" % [the_run]).is_equal(bare_lines)
		assert_array(scene_events).override_failure_message("run %s: the events of the scene differ from the bare rules" % [the_run]).is_equal(bare_events)


## What the nodes show is what the rules say: the sub, the creatures, the pellets and the pieces.
func _check_views_show_the_rules(world: SectorWorld) -> void:
	var sim := world.sim
	assert_vector(world.original.sub.position).is_equal(sim.sub.position)
	assert_bool(world.original.sub.visible).is_equal(sim.sub.active)
	for i in sim.foes.size():
		var foe := world.original.foes[i]
		assert_vector(foe.position).is_equal(Vector2(sim.foes[i].vm.x, sim.foes[i].vm.y) - SubModel.PLAYFIELD_ORIGIN)
		assert_bool(foe.visible).is_equal(sim.foes[i].is_shown())
		assert_int(foe.sprite.frame).is_equal(mini(sim.foes[i].vm.frame, foe.sprite.sprite_frames.get_frame_count(&"all") - 1))
	assert_int(world.original.pellets.get_child_count()).is_equal(sim.pellets.size())
	assert_int(world.original.collectibles.get_child_count()).is_equal(sim.pieces.size())
	assert_int(world.original.triggers_layer.get_child_count()).is_equal(sim.triggers_on_screen(sim.screen_index).size())


func test_loading_a_sector_announces_the_creatures_and_the_screen() -> void:
	var run := _new_run()
	var sim := SimWorld.new(run)
	_events = []
	_listen(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	assert_str(_events[0]).is_equal("sector_loaded %d" % DevCreatures.ARENA)
	assert_bool(_events.has("screen_loaded %d 0" % DevCreatures.ARENA)).is_true()
	# Every creature announces its first picture and, if it is on the first screen and not hidden, that it is shown.
	for foe in sim.foes:
		assert_bool(_events.has("picture %d %d" % [foe.vm.index, foe.vm.frame])).is_true()
		if foe.vm.screen == 0 and not foe.vm.hidden:
			assert_bool(_events.has("shown %d true" % foe.vm.index)).is_true()
	assert_int(_events.find("screen_loaded %d 0" % DevCreatures.ARENA)).is_greater(_events.find("sector_loaded %d" % DevCreatures.ARENA))


func test_a_fire_press_is_a_pellet_event_then_the_sound_and_the_pellet_is_data_not_a_node() -> void:
	var run := _new_run()
	var sim := SimWorld.new(run)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight()
	sim.foes_active = false
	sim.tile_grid.clear()
	_events = []
	_listen(sim)
	sim.tick(InputSnapshot.firing())
	assert_array(_events.filter(func(e: String) -> bool: return e.begins_with("pellet") or e.begins_with("sfx"))).is_equal(
			["pellet_fired 1", "sfx ink_fired"])
	assert_int(sim.pellets.size()).is_equal(1)
	assert_int(run.ink).is_equal(Tuning.resolve().ink_max - 1)
	# The in-flight limit is the length of the list.
	sim.tick(InputSnapshot.firing(3))
	assert_int(sim.pellets.size()).is_equal(run.tuning.ink_in_flight_max)


func test_a_piece_collected_names_the_piece_and_where_it_lay() -> void:
	var run := _new_run()
	var sim := SimWorld.new(run)
	sim.load_sector(DevCreatures.ARENA, DevCreatures.PIECE_SCREEN)
	sim.start_flight()
	sim.foes_active = false
	sim.tile_grid.clear()
	var piece := sim.sector.pieces[DevCreatures.PIECES[0]]
	sim.sub.place_original(piece.pos.x - 40, piece.pos.y - 25, 6)        # the picture box covers the piece
	_events = []
	_listen(sim)
	sim.tick()
	assert_array(_events.filter(func(e: String) -> bool: return e.begins_with("piece ") or e.begins_with("sfx"))).is_equal(
			["sfx piece_pickup", "piece %d %s" % [DevCreatures.PIECES[0], piece.pos]])
	assert_bool(run.has_piece(DevCreatures.PIECES[0])).is_true()
	assert_array(sim.pieces.map(func(p: PieceModel) -> int: return p.index)).is_equal([DevCreatures.PIECES[1]])    # the other of the screen is left


func test_a_trigger_fired_is_an_event_with_its_screen_and_place_in_the_list() -> void:
	var run := _new_run()
	var sim := SimWorld.new(run)
	sim.load_sector(DevCreatures.ARENA, DevCreatures.WAKER_SCREEN)           # (screen 5 has a math trigger)
	sim.start_flight()
	sim.foes_active = false
	sim.tile_grid.clear()
	var trigger := sim.triggers_on_screen(DevCreatures.WAKER_SCREEN)[0] as TriggerModel
	sim.sub.place_original(trigger.data.pos.x - 40, trigger.data.pos.y - 25, 6)
	_events = []
	_listen(sim)
	sim.tick()
	assert_array(_events.filter(func(e: String) -> bool: return e.begins_with("trigger") or e.begins_with("pending"))).is_equal(
			["trigger %d 0" % DevCreatures.WAKER_SCREEN, "pending %d" % trigger.data.slot])
	assert_bool(sim.is_trigger_armed(DevCreatures.WAKER_SCREEN, 0)).is_false()
	assert_bool(run.computer_light or run.ship_light).is_true()


func test_a_hurt_sub_is_an_event_and_a_lost_tank_waits_for_the_view_to_settle() -> void:
	var run := _new_run()
	var lost: Array[int] = []
	run.tank_lost.connect(func(code: int) -> void: lost.append(code))
	var sim := SimWorld.new(run)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight()
	var hurt := sim.foes.filter(func(f: FoeModel) -> bool: return f.vm.damage > 0 and f.is_touchable())[0] as FoeModel
	_events = []
	_listen(sim)
	# Enough air for the first hit, a view that is still busy with the second one.
	sim.sub_touches(hurt)
	assert_array(_events.filter(func(e: String) -> bool: return e.begins_with("damaged"))).is_equal(["damaged %d false" % hurt.vm.damage])
	assert_bool(sim.sub.is_invulnerable()).is_true()
	assert_array(lost).is_empty()
	sim.damage_settled_by_owner = true
	sim.sub.invulnerability = 0
	run.oxygen_model.oxygen = hurt.vm.damage                              # this hit takes the last of the tank
	hurt.vm.interrupted = false
	_events.clear()
	sim.sub_touches(hurt)
	assert_array(_events.filter(func(e: String) -> bool: return e.begins_with("damaged"))).is_equal(["damaged %d true" % hurt.vm.damage])
	assert_bool(sim.sub.is_invulnerable()).is_false()                     # (a lost tank does not make the sub invulnerable)
	assert_array(lost).is_empty()                                         # the owner is dissolving the sub: nothing announced yet
	sim.settle_damage()
	assert_int(lost.size()).is_equal(1)


func test_the_rules_count_the_dissolve_and_then_announce_the_lost_tank() -> void:
	var run := _new_run()
	var lost: Array[int] = []
	run.tank_lost.connect(func(code: int) -> void: lost.append(code))
	var sim := SimWorld.new(run)
	sim.damage_settled_by_owner = true
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight()
	var hurt := sim.foes.filter(func(f: FoeModel) -> bool: return f.vm.damage > 0 and f.is_touchable())[0] as FoeModel
	run.oxygen_model.oxygen = hurt.vm.damage
	var told: Array[String] = []
	sim.dissolve_started.connect(func(ticks: int) -> void: told.append("started %d" % ticks))
	sim.dissolve_advanced.connect(func(elapsed: int) -> void: told.append("at %d" % elapsed))
	sim.dissolve_finished.connect(func() -> void: told.append("finished %d" % lost.size()))
	sim.sub_touches(hurt)
	sim.begin_dissolve()                                                  # (what the owner does when it hears `sub_damaged`)
	assert_bool(sim.sub.controlled).is_false()                            # the RULES stop the sub
	assert_bool(sim.is_dissolving()).is_true()
	sim.advance_dissolve(5)
	sim.advance_dissolve(0)
	sim.advance_dissolve(15)
	assert_array(lost).is_empty()
	assert_bool(sim.is_dissolving()).is_true()
	sim.advance_dissolve(1)                                               # the 21st tick
	assert_array(told).is_equal(["started 21", "at 5", "at 20", "at 21", "finished 0"])    # (the loss is announced right after "finished")
	assert_int(lost.size()).is_equal(1)
	assert_bool(sim.is_dissolving()).is_false()
	sim.advance_dissolve(10)                                              # nothing left to count
	assert_int(told.size()).is_equal(5)


func test_a_view_that_does_not_settle_does_not_hold_up_the_rules() -> void:
	var run := _new_run()
	var lost: Array[int] = []
	run.tank_lost.connect(func(code: int) -> void: lost.append(code))
	var sim := SimWorld.new(run)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight()
	var hurt := sim.foes.filter(func(f: FoeModel) -> bool: return f.vm.damage > 0 and f.is_touchable())[0] as FoeModel
	run.oxygen_model.oxygen = hurt.vm.damage
	sim.sub_touches(hurt)
	assert_int(lost.size()).is_equal(1)                                   # no presenter: the loss is announced at once
