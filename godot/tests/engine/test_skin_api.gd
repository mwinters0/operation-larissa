class_name TestSkinApi
extends GdUnitTestSuite
## Teaches: an API that is pinned by a test. `docs/create/SKIN_API.md` says what a skin is given - the events of the rules with
## copies of what they are about, the state of everything that moves with its previous place, the tick fraction - and this file plays
## the claims:
##   * a presenter that has ONLY the skin API (`SkinRecorder`: it throws `sim` away) hears every event of a scripted visit, with
##     enough data in the copies to write the rules' own trace line for it, and each event comes in the step of the tick the document says;
##   * the timed things say how long they take and when they began (`SequenceState`, the dissolve), and the numbers add up;
##   * `Motion.at(fraction)` puts a sub, a creature, a pellet and the balloon exactly where the original look draws them;
##   * what the API hands out is a copy: a presenter that scribbles over all of it (`SkinVandal`) changes nothing the rules do;
##   * the document, the list `SimView.EVENTS` and the signals of `SimView` say the same.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const PRESENTER_SCENE := "res://src/gameplay/original_presenter.tscn"
const DOC := "res://../docs/create/SKIN_API.md"
## Sectors of the scripted visits: the arena, a sector of the tour, and a sector with a finale screen (it has the closing).
const SECTORS := [DevCreatures.ARENA, 3, DevCreatures.CLOSING]

## In which step of a tick each event may come (`SimWorld.TICK_ORDER`; "" = between two ticks: a load, the owner's call, a test's call).
## The same table is in the document. `sound_requested` is not here: any step may ask for a sound.
const STEPS := {
	&"ticked": ["pellets"],                                  # (after the last step)
	&"sector_loaded": [""],
	&"screen_loaded": ["", "sub"],
	&"screen_changed": ["sub"],
	&"creature_picture_changed": ["", "creatures", "sub"],
	&"creature_mirror_changed": ["", "creatures", "sub"],
	&"creature_visibility_changed": ["", "creatures", "sub"],
	&"creature_hit_by_ink": ["", "contacts"],
	&"creature_hit_by_sub": ["", "contacts"],
	&"sub_damaged": ["", "contacts"],
	&"piece_collected": ["", "pieces"],
	&"pieces_reset": ["", "pending_problem"],               # (the owner resolves the problem, which may be in the middle of its tick)
	&"trigger_fired": ["", "triggers"],
	&"pellet_fired": ["", "fire"],
	&"pellet_splashed": ["", "fire", "contacts", "pellets"],
	&"pellet_gone": ["", "sub", "pellets"],
	&"sub_placed": [""],
	&"problem_pending": ["", "triggers"],
	&"beacon_changed": ["", "pending_problem", "pieces", "triggers"],
	&"problem_requested": ["", "pending_problem"],
	&"problem_finished": ["", "pending_problem"],
	&"dock_reached": ["dock"],
	&"finale_reached": ["finale"],
	&"sequence_started": [""],
	&"sequence_finished": ["sub"],
	&"dissolve_started": ["", "contacts"],
	&"dissolve_advanced": [""],
	&"dissolve_finished": [""],
}


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


## A run of the player's game that is in no tree, and a visit to `sector` with a presenter (or none) bound to its rules.
func _visit(sector: int, presenter: SectorPresenter = null) -> SectorScenario:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.reset()
	var stage := HeadlessStage.new(run)
	var scenario := SectorScenario.new(stage, run)
	if presenter != null:
		auto_free(presenter)
		presenter.bind(stage.sim)
	scenario.play(sector)
	return scenario


# --- the events -------------------------------------------------------------------------------------

func test_a_presenter_with_only_the_skin_api_hears_what_the_rules_say() -> void:
	var seen := {}
	for sector in SECTORS:
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.reset()
		var stage := HeadlessStage.new(run)
		var scenario := SectorScenario.new(stage, run)
		var skin := SkinRecorder.new()
		auto_free(skin)
		skin.bind(stage.sim)
		assert_object(skin.sim).is_null()                                      # (it has no handle on the rules)
		var said: Array[String] = []
		SimTrace.listen(stage.sim, said)                                       # (what the rules said, as the trace writes it)
		scenario.play(sector)
		assert_int(said.size()).is_greater(40)
		for i in said.size():
			if said[i] != skin.lines[i]:
				fail("sector %d: the skin heard something else at event %d\n  rules: %s\n  skin:  %s" % [sector, i, said[i], skin.lines[i]])
				break
		assert_int(skin.lines.size()).is_equal(said.size())
		for call: Array in skin.calls:
			seen[call[0]] = true
	# Every event of the list came at least once in these visits, or is taken by the tests below.
	for event in SimView.EVENTS:
		if not seen.has(event) and not [&"piece_collected", &"pieces_reset", &"creature_hit_by_ink", &"screen_changed"].has(event):
			fail("the visits never sent '%s'" % event)


func test_each_event_comes_in_the_step_of_the_tick_the_document_says() -> void:
	var observed := {}
	for sector in SECTORS:
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.reset()
		var stage := HeadlessStage.new(run)
		stage.sim.trace_ticks = true
		var skin := SkinRecorder.new()
		auto_free(skin)
		skin.step_of = func() -> String: return "" if stage.sim.tick_trace.is_empty() else String(stage.sim.tick_trace.back())
		skin.bind(stage.sim)
		stage.sim.ticked.connect(func() -> void: stage.sim.tick_trace.clear())       # (after the skin's `ticked`: outside a tick the list is empty)
		stage.sim.problem_finished.connect(func(_slot: int, session: ProblemSession) -> void:
			if session.oxygen_code != OxygenModel.OK:
				stage.sim.tick_trace.clear())                                       # (a problem that cost the tank ends its tick: no `ticked`)
		SectorScenario.new(stage, run).play(sector)
		for call: Array in skin.calls:
			var steps: Array = observed.get(call[0], [])
			if not steps.has(call[3]):
				steps.append(call[3])
			observed[call[0]] = steps
	for event: StringName in observed:
		if event == &"sound_requested":
			continue
		assert_bool(STEPS.has(event)).override_failure_message("no step table for '%s'" % event).is_true()
		for step: String in observed[event]:
			assert_bool((STEPS[event] as Array).has(step)).override_failure_message("'%s' came in step '%s', the table says %s" % [event, step, STEPS[event]]).is_true()
	# and `ticked` is the last thing of every tick: nothing but `ticked` and the next tick's events come after it (see `test_presenter.gd`)
	assert_array(observed[&"ticked"]).is_equal(["pellets"])


## A trip begins between two ticks (the table, and `SimView.SequenceState.started_tick`: its first tick is `started_tick`), the balloon
## after the dock included: `SimWorld._advance_sequence` says `sequence_finished` for the dock in the `sub` step, but the stage's `dock`
## (as `SectorWorld.dock`) waits for `sequence_over`, which comes when that tick is over, so `GameFlow.complete_sector` starts the
## balloon between two ticks and its `sequence_finished` comes in `started_tick + ticks - 1`, as the document says.
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.reset()
	var stage := HeadlessStage.new(run)
	stage.sim.trace_ticks = true
	var starts: Array[String] = []
	stage.sim.sequence_started.connect(func(trip: StationSequence) -> void:
		starts.append("%d in '%s'" % [trip.kind, "" if stage.sim.tick_trace.is_empty() else String(stage.sim.tick_trace.back())]))
	stage.sim.ticked.connect(func() -> void: stage.sim.tick_trace.clear())
	stage.sim.problem_finished.connect(func(_slot: int, session: ProblemSession) -> void:
		if session.oxygen_code != OxygenModel.OK:
			stage.sim.tick_trace.clear())                                           # (a problem that cost the tank ends its tick)
	SectorScenario.new(stage, run).play(DevCreatures.ARENA)
	assert_bool(starts.any(func(start: String) -> bool: return start.begins_with("%d in" % StationSequence.Kind.BALLOON))).is_true()
	assert_array(starts.filter(func(start: String) -> bool: return not start.ends_with("''"))).is_empty()


func test_the_event_list_the_signals_and_the_document_are_one_list() -> void:
	var sim := SimWorld.new(GameState)
	var view := SimView.new(sim)
	var signals: Array[StringName] = []
	var inherited := RefCounted.new().get_signal_list().map(func(info: Dictionary) -> String: return info["name"])
	for info in view.get_signal_list():
		if not inherited.has(info["name"]):
			signals.append(StringName(info["name"]))
	signals.sort()
	var listed: Array[StringName] = SimView.EVENTS.duplicate()
	listed.sort()
	assert_array(signals).is_equal(listed)
	var doc := FileAccess.get_file_as_string(DOC)
	assert_str(doc).is_not_empty()
	for event in SimView.EVENTS:
		assert_bool(doc.contains("`%s" % event)).override_failure_message("docs/create/SKIN_API.md does not mention the event '%s'" % event).is_true()
	for name in ["sub()", "creatures()", "creature(", "pellets()", "pieces()", "triggers()", "sequence()", "is_dissolving()", "dissolve_progress()",
			"is_solid(", "tick_number", "show_between_ticks", "Motion", "at(fraction)", "progress(fraction)", "balloon_position(fraction)"]:
		assert_bool(doc.contains(name)).override_failure_message("docs/create/SKIN_API.md does not mention '%s'" % name).is_true()
	assert_bool(FileAccess.get_file_as_string("res://src/gameplay/sector_presenter.gd").contains("docs/create/SKIN_API.md")).is_true()
	assert_bool(FileAccess.get_file_as_string("res://../docs/engine/ARCHITECTURE.md").contains("../create/SKIN_API.md")).is_true()
	view.close()


# --- events that the scripted visits do not reach ---------------------------------------------------------

func test_pieces_a_pellet_on_a_creature_and_a_screen_change_come_with_their_data() -> void:
	var sim := SimWorld.new(GameState)
	var skin := SkinRecorder.new()
	auto_free(skin)
	skin.bind(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foes_active = false
	sim.load_screen(sim.sector.pieces[0].screen)       # (the screen of the data canister, piece 0)
	sim.start_flight(100, 100, 6)
	# a piece: taken by the rules, the copy says which and where it lay
	var piece := sim.pieces.filter(func(p: PieceModel) -> bool: return p.is_canister())[0] as PieceModel
	sim.take_piece(piece.index)
	var taken: SimView.PieceState = skin.calls_of(&"piece_collected")[0][1][0]
	assert_int(taken.index).is_equal(piece.index)
	assert_that(taken.position).is_equal(Vector2(piece.position()) - SubModel.PLAYFIELD_ORIGIN)
	assert_bool(taken.is_canister).is_true()
	assert_array(skin.view.pieces().map(func(p: SimView.PieceState) -> int: return p.index)).not_contains([piece.index])
	# the canister problem failed: the canister lies there again
	sim.problem_resolved(SimWorld.CANISTER_SLOT, _failed_session())
	assert_array(skin.calls_of(&"pieces_reset")).has_size(1)
	assert_bool(skin.view.pieces().any(func(p: SimView.PieceState) -> bool: return p.is_canister)).is_true()
	# a pellet that hits a creature: the creature's copy and the pellet's
	sim.load_screen(DevCreatures.MIRROR_SCREEN)                 # (the mirror and the glider are shown here)
	var foe: FoeModel = sim.foes[DevCreatures.MIRROR]
	assert_bool(foe.is_touchable()).is_true()
	var pellet := sim.fire_pellet()
	pellet.position = Vector2(foe.vm.x, foe.vm.y) - SubModel.PLAYFIELD_ORIGIN
	pellet.previous_position = pellet.position
	sim.sub.active = false                             # (the sub touches nothing: only the pellet does)
	sim.check_contacts()
	var inked: SimView.CreatureState = skin.calls_of(&"creature_hit_by_ink")[0][1][0]
	assert_int(inked.index).is_equal(foe.vm.index)
	assert_that(inked.motion.current).is_equal(Vector2(foe.vm.x, foe.vm.y) - SubModel.PLAYFIELD_ORIGIN)
	var splashed: SimView.PelletState = skin.calls_of(&"pellet_splashed")[0][1][0]
	assert_int(splashed.id).is_equal(pellet.id)
	assert_bool(splashed.splashing).is_true()
	# a screen change: the screen is laid out first, then the edge is announced with its direction
	sim.sub.active = true
	sim.load_screen(0)
	sim.start_flight(560, 60, 6)
	var before := skin.calls.size()
	sim.sub.position.x = SubModel.RIGHT_EDGE + 1.0
	sim.sub.crossed_edge.emit(SectorData.Direction.RIGHT)
	var names: Array = skin.calls.slice(before).map(func(call: Array) -> StringName: return call[0])
	assert_bool(sim.screen_index != 0).is_true()
	assert_int(names.find(&"screen_loaded")).is_less(names.find(&"screen_changed"))
	assert_array(skin.calls_of(&"screen_changed")[0][1]).is_equal([sim.screen_index, SectorData.Direction.RIGHT])


## The beacon has an event for going on and for going out, so a skin that follows events stops blinking when the rules do.
func test_the_beacon_says_when_it_goes_on_and_when_it_goes_out() -> void:
	var sim := SimWorld.new(GameState)
	var skin := SkinRecorder.new()
	auto_free(skin)
	skin.bind(sim)
	sim.load_sector(Ground.MAIN, 5)
	sim.start_flight()
	var trigger: TriggerModel = sim.triggers_on_screen(5)[0]
	var lit := func() -> Array: return skin.calls_of(&"beacon_changed").map(func(call: Array) -> bool: return call[1][0])
	sim.touch_trigger(trigger)
	assert_array(lit.call()).is_equal([true])
	assert_bool(skin.view.sub().message_light).is_true()
	sim.open_pending_problem()                                     # (the countdown ran out, or Enter)
	assert_array(lit.call()).is_equal([true, false])
	assert_bool(skin.view.sub().message_light).is_false()
	sim.problem_resolved(trigger.data.slot, ProblemSession.new(null))
	trigger.armed = true
	sim.touch_trigger(trigger)
	sim.take_piece(0)                                              # the canister takes the countdown over: its count shows no dome
	assert_array(lit.call()).is_equal([true, false, true, false])
	trigger.armed = true
	sim.touch_trigger(trigger)
	sim.load_sector(Ground.MAIN, 0)                                # a respawn puts it out
	assert_array(lit.call()).is_equal([true, false, true, false, true, false])
	assert_bool(skin.view.sub().message_light).is_false()


func _failed_session() -> ProblemSession:
	var session := ProblemSession.new(null)
	session.oxygen_code = OxygenModel.OUT_WITH_SPARE_TANKS
	return session


# --- how long things take, and when they began -----------------------------------------------------------------

func test_a_trip_says_how_long_it_is_and_in_which_tick_it_began() -> void:
	var sim := SimWorld.new(GameState)
	var skin := SkinRecorder.new()
	auto_free(skin)
	skin.bind(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foes_active = false
	for t in 7:
		sim.tick()
	sim.start_launch()                                 # (between ticks 6 and 7: the next tick is number 7)
	var started: SimView.SequenceState = skin.calls_of(&"sequence_started")[0][1][0]
	var launch := StationSequence.launch().ticks                      # (the pack's own length: data/rules/durations.json)
	assert_int(started.ticks).is_equal(launch)
	assert_int(started.started_tick).is_equal(7)
	assert_int(started.elapsed).is_equal(0)
	assert_bool(started.done).is_false()
	assert_int(skin.view.sequence().ticks).is_equal(launch)
	var ticks := 0
	while not sim.sequence.is_done():
		sim.tick()
		ticks += 1
	assert_int(ticks).is_equal(launch)
	var finished: SimView.SequenceState = skin.calls_of(&"sequence_finished")[0][1][0]
	assert_bool(finished.done).is_true()
	assert_int(finished.elapsed).is_equal(launch)
	assert_int(skin.calls_of(&"sequence_finished")[0][2]).is_equal(started.started_tick + started.ticks - 1)      # (the tick it ended in)
	# the progress of the drawing: (elapsed - 1 + fraction) / ticks, a tick behind the rules like every `Motion`
	var balloon := StationSequence.balloon().ticks
	assert_int(balloon).is_greater(11)
	var middle := SimView.SequenceState.of(_trip_after(StationSequence.Kind.BALLOON, 11))
	assert_float(middle.progress(0.0)).is_equal_approx(10.0 / balloon, 0.0001)
	assert_float(middle.progress(0.5)).is_equal_approx(10.5 / balloon, 0.0001)
	assert_float(middle.progress(1.0)).is_equal_approx(11.0 / balloon, 0.0001)
	assert_float(SimView.SequenceState.of(_trip_after(StationSequence.Kind.BALLOON, 0)).progress(0.3)).is_equal(0.0)
	assert_float(SimView.SequenceState.of(_trip_after(StationSequence.Kind.BALLOON, balloon)).progress(0.3)).is_equal(1.0)


func _trip_after(kind: StationSequence.Kind, elapsed: int) -> StationSequence:
	var trip := StationSequence.new(kind)
	for i in elapsed:
		trip.advance()
	return trip


func test_the_dissolve_says_how_long_it_is_and_how_far_it_has_gone() -> void:
	var sim := SimWorld.new(GameState)
	var skin := SkinRecorder.new()
	auto_free(skin)
	skin.bind(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	assert_bool(skin.view.is_dissolving()).is_false()
	assert_float(skin.view.dissolve_progress()).is_equal(0.0)
	sim.begin_dissolve()
	var length := SimWorld.dissolve_length()
	assert_array(skin.calls_of(&"dissolve_started")[0][1]).is_equal([length])
	sim.advance_dissolve(5)
	assert_bool(skin.view.is_dissolving()).is_true()
	assert_int(skin.view.dissolve_elapsed()).is_equal(5)
	assert_int(skin.view.dissolve_ticks()).is_equal(length)
	assert_float(skin.view.dissolve_progress()).is_equal_approx(5.0 / length, 0.0001)
	sim.advance_dissolve(100)
	assert_array(skin.calls_of(&"dissolve_advanced").map(func(call: Array) -> Array: return call[1])).is_equal([[5, length], [length, length]])
	assert_array(skin.calls_of(&"dissolve_finished")).has_size(1)
	assert_bool(skin.view.is_dissolving()).is_false()


func test_ticks_are_counted_from_zero_and_ticked_says_which() -> void:
	var sim := SimWorld.new(GameState)
	var skin := SkinRecorder.new()
	auto_free(skin)
	skin.bind(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	assert_int(skin.view.tick_number).is_equal(0)
	for t in 5:
		sim.tick()
	assert_array(skin.calls_of(&"ticked").map(func(call: Array) -> int: return call[2])).is_equal([0, 1, 2, 3, 4])
	assert_int(skin.view.tick_number).is_equal(5)


# --- the rectangles, for a skin's own overlay ------------------------------------------------------------

func test_the_view_has_every_rectangle_the_debug_overlay_draws() -> void:
	# The debug rectangles read the rules; a skin's own overlay has only `view`. They must be able to draw the same boxes:
	# the sub's hurt rectangle and wall box, the creatures' hit rectangles, and the walls tile by tile.
	var sim := SimWorld.new(GameState)
	var view := SimView.new(sim)
	var rects := DebugRectPresenter.new()
	auto_free(rects)
	rects.bind(sim)
	sim.load_sector(DevCreatures.ARENA, 3)
	sim.foes_active = true
	sim.start_flight()
	for t in 30:
		sim.tick(InputSnapshot.steering(1, 0))
	rects.show_between_ticks(1.0)                           # (the end of the tick: no glide)
	var boxes := rects.boxes()
	var sub := view.sub()
	assert_that(_kind(boxes, &"sub_hurt")[0].rect).is_equal(Rect2(sub.hurt_rect))
	assert_that(_kind(boxes, &"sub_walls")[0].rect).is_equal(Rect2(sub.wall_rect))
	assert_int(sub.wall_rect.size.x).is_greater(0)
	assert_bool(sub.wall_rect.size.x <= sub.hurt_rect.size.x + 96 and sub.wall_rect.size.y <= 54).is_true()       # (it is the sub's box, not the screen's)
	var hit_boxes := _kind(boxes, &"creature")
	var hit_rects: Array[Rect2] = []
	for creature in view.creatures():
		if creature.hit_rect.size != Vector2i.ZERO and sim.foes[creature.index].is_touchable():
			hit_rects.append(Rect2(creature.hit_rect))
	assert_int(hit_boxes.size()).is_equal(hit_rects.size())
	for box in hit_boxes:
		assert_bool(hit_rects.has(box.rect)).override_failure_message("creature box %s is not in the view" % box.rect).is_true()
	var solid_tiles := 0
	for column in TileGrid.COLUMNS:
		for row in TileGrid.ROWS:
			solid_tiles += 1 if view.is_solid(column, row) else 0
	var wall_tiles := 0
	for box in _kind(boxes, &"wall"):
		wall_tiles += roundi(box.rect.size.x / TileGrid.TILE_SIZE)
	assert_int(wall_tiles).is_equal(solid_tiles)
	view.close()


func _kind(boxes: Array[DebugRectPresenter.Box], kind: StringName) -> Array[DebugRectPresenter.Box]:
	return boxes.filter(func(box: DebugRectPresenter.Box) -> bool: return box.kind == kind)


# --- the state --------------------------------------------------------------------------------------------

func test_the_state_accessors_say_what_the_rules_say() -> void:
	var sim := SimWorld.new(GameState)
	var view := SimView.new(sim)
	sim.load_sector(DevCreatures.ARENA, 3)
	assert_int(view.sector_index).is_equal(DevCreatures.ARENA)
	assert_int(view.screen_index).is_equal(3)
	assert_int(view.zone).is_equal(sim.sector.zone)
	assert_int(view.creatures().size()).is_equal(sim.foes.size())
	assert_int(view.pieces().size()).is_equal(sim.pieces.size())
	assert_int(view.triggers().size()).is_equal(sim.triggers_on_screen(3).size())
	for column in range(0, TileGrid.COLUMNS, 5):
		for row in TileGrid.ROWS:
			assert_bool(view.is_solid(column, row)).is_equal(sim.tile_grid.is_solid(column, row))
			assert_that(view.current_at(column, row)).is_equal(sim.tile_grid.current_at(column, row))
	sim.foes_active = true
	sim.start_flight()
	for t in 40:
		sim.tick(InputSnapshot.steering(1, 0) if t < 25 else InputSnapshot.firing())
	var sub := view.sub()
	assert_that(sub.motion.current).is_equal(sim.sub.position)
	assert_that(sub.motion.previous).is_equal(sim.sub.previous_position)
	assert_that(sub.top_left()).is_equal(sim.sub.position - SubModel.PICTURE_CENTER)
	assert_int(sub.cell).is_equal(sim.sub.cell)
	assert_int(sub.picture).is_equal(sim.sub.tuning.picture_for(sim.sub.cell, sim.sub.propeller_phase))
	assert_bool(sub.active).is_true()
	for foe in sim.foes:
		var creature := view.creature(foe.vm.index)
		assert_int(creature.picture).is_equal(foe.vm.frame)
		assert_bool(creature.mirrored).is_equal(foe.vm.flip)
		assert_bool(creature.shown).is_equal(foe.is_shown())
		assert_that(creature.motion.current).is_equal(Vector2(foe.vm.x, foe.vm.y) - SubModel.PLAYFIELD_ORIGIN)
		assert_that(creature.motion.previous).is_equal(Vector2(foe.previous_pos) - SubModel.PLAYFIELD_ORIGIN)
	assert_int(view.pellets().size()).is_equal(sim.pellets.size())
	for i in sim.pellets.size():
		assert_that(view.pellets()[i].motion.current).is_equal(sim.pellets[i].position)
	view.close()


func test_what_the_api_hands_out_is_a_copy() -> void:
	var sim := SimWorld.new(GameState)
	var skin := SkinRecorder.new()
	auto_free(skin)
	skin.bind(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.start_flight(100, 100, 6)
	sim.foes_active = false
	sim.tick(InputSnapshot.steering(1, 0))
	sim.tick(InputSnapshot.firing())
	var sub := skin.view.sub()
	var position_in_rules := sim.sub.position
	sub.motion.current = Vector2(-1, -1)
	sub.cell = 99
	assert_that(sim.sub.position).is_equal(position_in_rules)
	assert_that(skin.view.sub().motion.current).is_equal(position_in_rules)
	var creature := skin.view.creature(0)
	var frame := sim.foes[0].vm.frame
	var x := sim.foes[0].vm.x
	creature.picture = -5
	creature.motion.current = Vector2(7, 7)
	assert_int(sim.foes[0].vm.frame).is_equal(frame)
	assert_int(sim.foes[0].vm.x).is_equal(x)
	var pellets := skin.view.pellets()
	assert_array(pellets).is_not_empty()
	pellets[0].motion.current = Vector2.ZERO
	pellets.clear()
	assert_that(sim.pellets[0].position).is_not_equal(Vector2.ZERO)
	assert_array(skin.view.pellets()).has_size(sim.pellets.size())
	# an event's argument is a copy as well
	var fired: SimView.PelletState = skin.calls_of(&"pellet_fired")[0][1][0]
	fired.id = 12345
	assert_int(sim.pellets[0].id).is_not_equal(12345)
	assert_that(skin.view.sequence()).is_null()                      # (no trip yet)
	# the rules hand nothing of their own to a presenter that has only the view
	assert_object(skin.sim).is_null()


func test_a_presenter_that_scribbles_over_everything_changes_nothing_the_rules_do() -> void:
	for sector in SECTORS:
		var plain := _visit(sector)
		var vandal := SkinVandal.new()
		var vandalised := _visit(sector, vandal)
		assert_int(vandal.scribbles).override_failure_message("the vandal did nothing").is_greater(1000)
		assert_array(vandalised.trace.lines).override_failure_message("sector %d: the rules noticed the vandal" % sector).is_equal(plain.trace.lines)


# --- smooth movement, as the original look draws it ---------------------------------------------------------

## An original presenter in the tree, bound to `sim`.
func _original_for(sim: SimWorld) -> OriginalPresenter:
	var presenter := auto_free((load(PRESENTER_SCENE) as PackedScene).instantiate()) as OriginalPresenter
	add_child(presenter)
	presenter.bind(sim)
	return presenter


func test_previous_current_and_the_fraction_put_things_where_the_original_look_draws_them() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _original_for(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foe_context.rng.seed = 4242
	sim.start_flight(100, 120, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var glided := 0
	var pellets_checked := 0
	for t in 80:
		var input := InputSnapshot.steering(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		input.fire_presses = 1 if t % 9 == 0 else 0
		sim.tick(input)
		var sub := presenter.view.sub()
		var creatures := presenter.view.creatures()
		var pellets := presenter.view.pellets()
		for fraction in [0.0, 0.25, 0.5, 1.0]:
			presenter.show_between_ticks(fraction)
			# the sub: the node is at the current place, its picture is shifted back by the rest of the tick
			var drawn := presenter.sub.position + presenter.sub.visual.position
			_near(drawn, sub.motion.at(fraction), "tick %d, fraction %s: the sub" % [t, fraction])
			for creature in creatures:
				var node := presenter.foes[creature.index]
				var expected := creature.motion.at(fraction) if node.is_gliding() else creature.motion.current
				_near(node.position + node.sprite.position, expected, "tick %d, fraction %s: creature %d" % [t, fraction, creature.index])
				if node.is_gliding():
					assert_bool(creature.jumped or creature.was_hidden != creature.hidden).is_false()      # (the data tells why a step is not a glide)
					glided += 1
			for pellet in pellets:
				for node: InkPellet in presenter.pellets.get_children():
					if node.model.id == pellet.id:
						_near(node.position + node.sprite.position - pellet.splash_offset, pellet.motion.at(fraction), "tick %d, fraction %s: pellet %d" % [t, fraction, pellet.id])
						pellets_checked += 1
	assert_int(glided).override_failure_message("no creature glided in the test").is_greater(0)
	assert_int(pellets_checked).override_failure_message("no pellet flew in the test").is_greater(0)


func test_the_balloon_is_where_the_original_look_draws_it() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _original_for(sim)
	sim.load_sector(DevCreatures.ARENA, 11)
	sim.foes_active = false
	sim.start_balloon()
	for t in StationSequence.balloon().ticks - 1:
		sim.tick()
		var trip := presenter.view.sequence()
		assert_bool(trip.done).is_false()
		for fraction in [0.0, 0.5, 1.0]:
			presenter.show_between_ticks(fraction)
			_near(presenter.station.balloon.position, trip.balloon_position(fraction), "tick %d, fraction %s: the balloon" % [t, fraction])


func test_the_door_and_the_sub_of_a_launch_follow_the_trip() -> void:
	var sim := SimWorld.new(GameState)
	var presenter := _original_for(sim)
	sim.load_sector(DevCreatures.ARENA, 0)
	sim.foes_active = false
	sim.start_launch()
	for t in StationSequence.launch().ticks:
		sim.tick()
		var trip := presenter.view.sequence()
		assert_int(trip.elapsed).is_equal(t + 1)
		assert_int(trip.door_picture()).is_equal(sim.sequence.door_picture())
		assert_bool(presenter.station.door.visible).is_equal(trip.door_picture() >= 0)
		assert_bool(trip.is_drive()).is_true()
	assert_bool(presenter.view.sub().controlled).is_true()               # (sequence_finished: the player has the sub again)


## `actual` is `expected` up to the rounding of a float.
func _near(actual: Vector2, expected: Vector2, message: String) -> void:
	assert_float(actual.distance_to(expected)).override_failure_message("%s: drawn at %s, the skin API says %s" % [message, actual, expected]).is_less(0.01)
