class_name TestClosingSequences
extends GdUnitTestSuite
## Teaches: checking a choreography by sampling it. The Voyager closing is one animation built from loop counts;
## we seek to moments in it and look where the pieces are. The Expert closing is checked the same way, and
## both are checked for tracks that name no node.

const VOYAGER := "res://src/story/voyager_closing.tscn"
const EXPERT := "res://src/story/expert_closing.tscn"

## The original's loops as this test reads them (CLOSING.C; the importer has its own copy of the numbers in
## tools/import/step_story.py, the data files are written from that). Keeping them here as well means that a wrong number in the
## data cannot make its own test agree; tests/legacy/test_cutscene_timing.gd pins the lengths and moments of every cutscene.
const VOYAGER_STEP := 6.0 / 73.0                       # VoyagerClosingSequence: 6 ticks a step
const VOYAGER_TURN_TABLE: Array[int] = [2, 2, 2, 2, 3, 4, 5, 5, 5]
const VOYAGER_TURN_DONE_CELL := 2
const VOYAGER_FLY_UNTIL_X := -136
const EXPERT_STEP := 18.0 / 73.0                       # ExpertClosingSequence: 18 ticks a step
const EXPERT_TURN_TABLE: Array[int] = [3, 3, 3, 4, 5, 6, 6, 6, 6]
const EXPERT_TURN_DONE_CELL := 6
const EXPERT_START_CELL := 4
const IDLE_STEPS := 20
const HOOK_START_BOTTOM := 0x24
const HOOK_STEP := 12
const DESCENT_STEPS := 16
const ASCENT_STEPS := 17


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	Audio.stop_music()


func after_test() -> void:
	Audio.stop_music()
	Audio.stop_voice()


func _unresolved(player: AnimationPlayer) -> PackedStringArray:
	var missing := PackedStringArray()
	var root := player.get_node(player.root_node)
	for animation_name in player.get_animation_list():
		var animation := player.get_animation(animation_name)
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			var node := root.get_node_or_null(NodePath(path.get_concatenated_names()))
			if node == null:
				missing.append("%s: %s" % [animation_name, path])
			elif animation.track_get_type(track) == Animation.TYPE_VALUE and path.get_concatenated_subnames() != "":
				if not String(path.get_subname(0)) in node:
					missing.append("%s: %s has no %s" % [animation_name, node.name, path.get_subname(0)])
	return missing


func test_voyager_closing_flight() -> void:
	var closing: VoyagerClosing = auto_free(load(VOYAGER).instantiate())
	add_child(closing)
	closing.start(184, 212, 6)
	assert_array(_unresolved(closing.animations)).is_empty()
	var animation := closing.animations.get_animation(&"closing")
	# 18 steps of 4 px up: after them the sub is 72 px higher
	closing.animations.seek(18 * VOYAGER_STEP - 0.001, true)
	assert_float(closing.sub.position.y).is_equal_approx(212.0 - 72.0 - 32.0, 0.5)
	assert_bool(closing.sub.visible).is_true()
	assert_bool(closing.heli_body.visible).is_false()
	# the whole flight: the helicopter ends outside the playfield, to the left
	closing.animations.seek(animation.length - 0.3, true)
	assert_bool(closing.sub.visible).is_false()
	assert_bool(closing.heli_body.visible).is_true()
	assert_bool(closing.heli_rotor.visible).is_true()
	assert_float(closing.heli_body.position.x + 16.0).is_less_equal(VOYAGER_FLY_UNTIL_X + 8.0)
	closing.skip()


func test_voyager_closing_turns_to_the_original_cell() -> void:
	# whichever way the sub faces, the turn table leads to cell 2
	for start_cell in 9:
		var cell := start_cell
		var steps := 0
		while cell != VOYAGER_TURN_DONE_CELL:
			cell = VOYAGER_TURN_TABLE[cell]
			steps += 1
			assert_int(steps).is_less(10)
	# and the data the closing runs on is the same table
	assert_array(Array(Catalog.voyager_closing_script().turn_table)).is_equal(VOYAGER_TURN_TABLE)
	assert_int(Catalog.voyager_closing_script().turn_done_cell).is_equal(VOYAGER_TURN_DONE_CELL)
	assert_int(Catalog.voyager_closing_script().fly_until_x).is_equal(VOYAGER_FLY_UNTIL_X)


func test_voyager_pages_are_the_surface_ships_message() -> void:
	assert_str(VoyagerClosing.page_text(0)).starts_with("Congratulations!")
	assert_str(VoyagerClosing.page_text(0)).contains("Substance X")
	assert_str(VoyagerClosing.page_text(1)).contains("other part must be recovered")
	assert_str(VoyagerClosing.page_text(2)).starts_with("Return to the surface ship")
	for page in VoyagerClosing.PAGES:
		assert_array(Catalog.voice_cues().closing_page(page)).is_not_empty()


func test_voyager_closing_skip_ends_it_once() -> void:
	var closing: VoyagerClosing = auto_free(load(VOYAGER).instantiate())
	add_child(closing)
	closing.start(184, 212, 6)
	var count := [0]
	closing.finished.connect(func() -> void: count[0] += 1)
	closing.skip()
	closing.skip()
	assert_int(count[0]).is_equal(1)


## Seeks `closing` to the start of step `step` of the animation `name` and applies the keys there.
func _at_step(closing: ExpertClosing, name: StringName, step: int) -> void:
	closing.animations.play(name)
	closing.animations.seek(step * EXPERT_STEP + 0.001, true)


## Plays the hoist out (the way the director's clock would) so that the closing is on its deck stage.
func _to_stage(closing: ExpertClosing, stage: ExpertClosing.Stage) -> void:
	var hoist := closing.animations.get_animation(&"hoist")
	closing.animations.advance(hoist.length + 0.01)
	if stage == ExpertClosing.Stage.WAIT:
		var deck := closing.animations.get_animation(&"deck")
		closing.animations.advance(deck.length + 0.01)


func _expert() -> ExpertClosing:
	var closing: ExpertClosing = auto_free(load(EXPERT).instantiate())
	add_child(closing)
	return closing


func test_expert_closing_tracks_name_real_nodes() -> void:
	var closing := _expert()
	assert_array(_unresolved(closing.animations)).is_empty()
	assert_bool(closing.deck.visible).is_false()
	assert_int(closing.stage).is_equal(ExpertClosing.Stage.HOIST)


## Steps of the sub's turn from the starting cell, and of the whole hoist (each step ends with an 18-tick wait).
func _expert_turn_steps() -> int:
	var cell := EXPERT_START_CELL
	var steps := 0
	while cell != EXPERT_TURN_DONE_CELL:
		cell = EXPERT_TURN_TABLE[cell]
		steps += 1
	return steps


func _expert_hoist_steps() -> int:
	return _expert_turn_steps() + IDLE_STEPS + DESCENT_STEPS + ASCENT_STEPS


func test_expert_hoist_has_the_original_number_of_steps() -> void:
	# ExpertClosingSequence: 2 turn steps (cell 4 -> 5 -> 6), 20 idle, 16 of the hook coming down, 17 going up
	assert_int(_expert_turn_steps()).is_equal(2)
	assert_int(_expert_hoist_steps()).is_equal(2 + 20 + 16 + 17)
	var closing := _expert()
	var hoist := closing.animations.get_animation(&"hoist")
	assert_float(hoist.length).is_equal_approx(55 * 18.0 / 73.0, 0.0001)
	# the ascent ends when the cable's bottom has reached the top edge: 228 - 17 * 12 = 24 <= 32 < 228 - 16 * 12
	var bottom := HOOK_START_BOTTOM + HOOK_STEP * DESCENT_STEPS
	assert_int(bottom - ASCENT_STEPS * HOOK_STEP).is_less_equal(0x20)
	assert_int(bottom - (ASCENT_STEPS - 1) * HOOK_STEP).is_greater(0x20)


func test_expert_hook_is_open_for_10_steps_closing_for_5_and_closed_from_the_16th() -> void:
	var closing := _expert()
	var first_descent := _expert_turn_steps() + IDLE_STEPS      # step index of descent step 1
	_at_step(closing, &"hoist", first_descent - 1)
	assert_bool(closing.cable.visible).is_false()                                    # nothing hangs during the turn and the idle
	for d in range(1, 17):
		_at_step(closing, &"hoist", first_descent + d - 1)
		assert_bool(closing.cable.visible).is_true()
		assert_int(closing.cable.bottom).is_equal(0x24 + 12 * d)
		assert_int(closing.cable.hook_frame).is_equal(0 if d <= 10 else (1 if d <= 15 else 2))
	for a in range(1, 18):                                                            # the ascent keeps the hook closed
		_at_step(closing, &"hoist", first_descent + 15 + a)
		assert_int(closing.cable.hook_frame).is_equal(2)
		assert_int(closing.cable.bottom).is_equal(228 - 12 * a)


func test_expert_cable_is_hook_three_links_ball_then_links() -> void:
	var closing := _expert()
	var cable := closing.cable
	assert_str(cable.piece_pictures[0]).is_equal("crane_hook_0")                                # the hook (open at first)
	for i in range(1, 4):
		assert_str(cable.piece_pictures[i]).is_equal("crane_link")                    # links, 8 x 12
	assert_str(cable.piece_pictures[4]).is_equal("crane_ball")                                # the ball, 28 x 22
	for i in range(5, cable.piece_pictures.size()):
		assert_str(cable.piece_pictures[i]).is_equal("crane_link")
	assert_vector(Vector2(cable.pieces[4].texture.get_size())).is_equal(Vector2(28, 22))
	# every piece sits right above the one below it (the ExpertClosingDrawCable loop: y -= height)
	assert_int(cable.piece_tops[0]).is_equal(-25)
	assert_int(cable.piece_tops[1]).is_equal(-(26 + 11))
	assert_int(cable.piece_tops[4]).is_equal(-(26 + 3 * 12 + 21))
	assert_int(cable.piece_tops[5]).is_equal(-(26 + 3 * 12 + 22 + 11))
	# x: hook 220, ball 228, links 236 (window pixels)
	_at_step(closing, &"hoist", _expert_turn_steps() + IDLE_STEPS + 15)
	assert_float(cable.pieces[0].position.x + 16.0).is_equal(220.0)
	assert_float(cable.pieces[4].position.x + 16.0).is_equal(228.0)
	assert_float(cable.pieces[1].position.x + 16.0).is_equal(236.0)
	assert_float(cable.pieces[0].position.y + 32.0).is_equal(228.0 - 25.0)          # the hook's top row: bottom - 25


func test_expert_hoisted_object_is_the_zone_foe_bundle_pair_at_x_200() -> void:
	var closing := _expert()
	# sector 31 is zone 6 (GetZone), whose foe bundle is logical resource 461 = bundle 112: items 0 / 1 are the two
	# 84 x 72 pictures 2002 / 2003, slots 35 / 36 of the zone's foe frames
	var frames := closing.artifact.sprite_frames
	assert_vector(Vector2(frames.get_frame_texture(&"all", 35).get_size())).is_equal(Vector2(84, 72))
	assert_vector(Vector2(frames.get_frame_texture(&"all", 36).get_size())).is_equal(Vector2(84, 72))
	assert_str(Packs.source_of(frames.get_frame_texture(&"all", 35))).ends_with("foe_z6_alien_artifact_0_35.png")
	_at_step(closing, &"hoist", 0)
	assert_int(closing.artifact.frame).is_equal(35)
	assert_vector(closing.artifact.position).is_equal(Vector2(200 - 16, 0xe8 - 32))
	_at_step(closing, &"hoist", 1)
	assert_int(closing.artifact.frame).is_equal(36)                                   # toggled on every call
	_at_step(closing, &"hoist", 2)
	assert_int(closing.artifact.frame).is_equal(35)
	# it rises with the sub, 12 px per step of the ascent, after the 36 steps of turn, idle and descent
	_at_step(closing, &"hoist", _expert_hoist_steps() - 1)
	assert_float(closing.artifact.position.y).is_equal(0xe8 - 17 * 12.0 - 32.0)
	assert_float(closing.sub.position.y).is_equal(212.0 - 17 * 12.0 - 32.0)
	assert_float(closing.sub.position.x).is_equal(184.0 - 16.0)


func test_expert_sub_turns_to_face_right_during_the_first_steps() -> void:
	var closing := _expert()
	var tuning := Tuning.original().sub
	_at_step(closing, &"hoist", 0)
	assert_int(closing.sub.frame).is_equal(tuning.picture_for(5, 0))
	_at_step(closing, &"hoist", 1)
	assert_int(closing.sub.frame).is_equal(tuning.picture_for(6, 1))
	assert_bool(closing.sub.flip_h).is_false()


func test_expert_deck_shot_timing_and_rise() -> void:
	var closing := _expert()
	var deck := closing.animations.get_animation(&"deck")
	assert_float(deck.length).is_equal_approx(146 * 18.0 / 73.0, 0.0001)             # 6 + 140 steps
	# the sub, the artifact and the cable rise 12 px per step for 6 steps, from 0x123 / 0x137 / 0x133
	_at_step(closing, &"deck", 0)
	assert_vector(closing.deck_sub.position).is_equal(Vector2(184 - 16, 0x123 - 12 - 32))
	assert_vector(closing.deck_artifact.position).is_equal(Vector2(200 - 16, 0x137 - 12 - 32))
	assert_int(closing.deck_cable.bottom).is_equal(0x133 - 12)
	assert_int(closing.deck_cable.hook_frame).is_equal(2)
	_at_step(closing, &"deck", 5)
	assert_vector(closing.deck_sub.position).is_equal(Vector2(184 - 16, 0x123 - 72 - 32))
	assert_vector(closing.deck_artifact.position).is_equal(Vector2(200 - 16, 0x137 - 72 - 32))
	assert_int(closing.deck_cable.bottom).is_equal(0x133 - 72)
	_at_step(closing, &"deck", 145)                                                   # and stay there
	assert_vector(closing.deck_sub.position).is_equal(Vector2(184 - 16, 0x123 - 72 - 32))
	# the cable is cut at the crane arm (y 154); the deck's pictures keep the original order, the sea on top
	assert_float(closing.deck_cable.position.y + 32.0).is_equal(154.0)
	var order := [closing.ship, closing.crew_layer, closing.deck_artifact, closing.deck_sub, closing.deck_cable, closing.pod, closing.sea]
	for i in range(1, order.size()):
		assert_int(order[i].get_index()).is_greater(order[i - 1].get_index())


func test_expert_deck_crew_follows_the_six_programs() -> void:
	var closing := _expert()
	# step 0: three sailors are on the deck, three are still off screen (their programs begin with a wait)
	_at_step(closing, &"deck", 0)
	var shown := []
	for sailor in closing.crew_layer.get_children():
		shown.append((sailor as Sprite2D).visible)
	assert_array(shown).is_equal([false, true, true, true, false, false])
	var s1 := closing.crew_layer.get_child(1) as Sprite2D
	assert_vector(s1.position).is_equal(Vector2(332 - 16, 214 - 32))
	assert_str(Packs.source_of(s1.texture)).ends_with("ui_2036.png")                     # item 24
	var s3 := closing.crew_layer.get_child(3) as Sprite2D
	assert_vector(s3.position).is_equal(Vector2(436 - 16, 214 - 32))
	assert_bool(s3.flip_h).is_true()                                                  # walks to the right, drawn mirrored
	_at_step(closing, &"deck", 79)
	assert_bool((closing.crew_layer.get_child(0) as Sprite2D).visible).is_false()      # sailor 0 waits 80 steps
	_at_step(closing, &"deck", 80)
	var s0 := closing.crew_layer.get_child(0) as Sprite2D
	assert_bool(s0.visible).is_true()
	assert_vector(s0.position).is_equal(Vector2(496 - 16, 214 - 32))
	assert_str(Packs.source_of(s0.texture)).ends_with("ui_2025.png")
	_at_step(closing, &"deck", 112)
	assert_vector(s0.position).is_equal(Vector2(368 - 16, 214 - 32))                   # 32 steps of 4 px to the left


func test_expert_crew_programs_come_from_the_data() -> void:
	var crew := Catalog.closing_crew()
	assert_int(crew.scripts.size()).is_equal(6)
	assert_array(crew.start_x).is_equal(PackedInt32Array([496, 332, 368, 436, 496, 496]))
	assert_array(crew.start_y).is_equal(PackedInt32Array([214, 214, 224, 214, 214, 214]))
	var counts := []
	var pictures := {}
	for n in 6:
		var actor := ClosingCrewActor.new(crew, n)
		counts.append(actor.record_count())
		var program := crew.scripts[n]
		assert_int(program[program.size() - 4]).is_equal(ClosingCrewActor.Op.END)       # every program ends with the end op
		for r in actor.record_count():
			if program[r * 4] != ClosingCrewActor.Op.WAIT and program[r * 4] != ClosingCrewActor.Op.END:   # draws or moves
				pictures[crew.first_picture + program[r * 4 + 1]] = true
	assert_array(counts).is_equal([38, 47, 47, 50, 28, 26])
	# the sailors use all 17 pictures 2022-2038, every one imported
	assert_array(pictures.keys()).contains_exactly_in_any_order(range(2022, 2039))
	for id: int in pictures:
		assert_object(Assets.ui_picture_by_number(id)).is_not_null()


func test_expert_crew_actor_runs_the_step_rules() -> void:
	var actor := ClosingCrewActor.new(Catalog.closing_crew(), 0)
	for step in 80:                                                                    # record 0: wait 80 steps, nothing drawn
		actor.step()
		assert_bool(actor.visible).is_false()
	actor.step()                                                                       # then a draw, then 28 moves of 4 px left
	assert_bool(actor.visible).is_true()
	assert_int(actor.picture).is_equal(2025)
	assert_int(actor.x).is_equal(496)
	actor.step()
	assert_int(actor.x).is_equal(492)
	assert_int(actor.picture).is_equal(2024)
	# the last step of the deck shot (step 145 counted from 0): every sailor stands still
	var crew := Catalog.closing_crew()
	var all: Array[ClosingCrewActor] = []
	for n in 6:
		all.append(ClosingCrewActor.new(crew, n))
	for step in 146:
		for a in all:
			a.step()
	assert_array(all.map(func(a: ClosingCrewActor) -> int: return a.x)).is_equal([368, 408, 432, 456, 480, 504])
	assert_bool(all.all(func(a: ClosingCrewActor) -> bool: return a.visible)).is_true()


func test_expert_pod_blinks_through_its_three_pictures() -> void:
	var closing := _expert()
	var pictures := []
	var mirrored := []
	for step in 4:
		_at_step(closing, &"deck", step)
		pictures.append(Packs.source_of(closing.pod.texture).get_file())
		mirrored.append(closing.pod.flip_h)
	assert_array(pictures).is_equal(["deck_pod_0_2015.png", "deck_pod_1_2016.png", "deck_pod_2_2017.png", "deck_pod_1_2016.png"])
	assert_array(mirrored).is_equal([false, false, false, true])
	assert_vector(closing.pod.position).is_equal(Vector2(568 - 16, 104 - 32))
	# the wait goes on from phase 146 % 4 = 2 and repeats for as long as nobody presses a key
	var wait := closing.animations.get_animation(&"wait")
	assert_int(wait.loop_mode).is_equal(Animation.LOOP_LINEAR)
	assert_float(wait.length).is_equal_approx(4 * 18.0 / 73.0, 0.0001)
	_at_step(closing, &"wait", 0)
	assert_str(Packs.source_of(closing.pod.texture)).ends_with("deck_pod_2_2017.png")


func test_expert_keys_are_ignored_until_the_last_stage() -> void:
	var closing := _expert()
	var count := [0]
	closing.finished.connect(func() -> void: count[0] += 1)
	for event in _key_events():
		closing._unhandled_input(event)
	closing.advance()                                                                  # Enter
	closing.skip()                                                                     # Space / Escape
	assert_int(count[0]).is_equal(0)
	_to_stage(closing, ExpertClosing.Stage.DECK)
	assert_int(closing.stage).is_equal(ExpertClosing.Stage.DECK)
	assert_bool(closing.deck.visible).is_true()
	assert_bool(closing.playfield.visible).is_false()
	for event in _key_events():
		closing._unhandled_input(event)
	closing.advance()
	closing.skip()
	assert_int(count[0]).is_equal(0)
	assert_int(closing.stage).is_equal(ExpertClosing.Stage.DECK)                      # the deck does not end by itself


func test_expert_waits_for_a_key_after_the_deck_and_a_key_ends_it_once() -> void:
	var closing := _expert()
	var count := [0]
	closing.finished.connect(func() -> void: count[0] += 1)
	_to_stage(closing, ExpertClosing.Stage.WAIT)
	assert_int(closing.stage).is_equal(ExpertClosing.Stage.WAIT)
	assert_str(String(closing.animations.current_animation)).is_equal("wait")
	closing.animations.advance(60.0)                                                  # a minute later it is still waiting
	assert_int(count[0]).is_equal(0)
	assert_bool(closing.animations.is_playing()).is_true()
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	closing._unhandled_input(key)
	closing.advance()
	assert_int(count[0]).is_equal(1)


func test_expert_click_ends_the_wait() -> void:
	var closing := _expert()
	var count := [0]
	closing.finished.connect(func() -> void: count[0] += 1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	closing._unhandled_input(click)
	assert_int(count[0]).is_equal(0)                                                  # the click area exists only in the last stage
	_to_stage(closing, ExpertClosing.Stage.WAIT)
	closing._unhandled_input(click)
	assert_int(count[0]).is_equal(1)


func _key_events() -> Array[InputEventKey]:
	var events: Array[InputEventKey] = []
	for keycode in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE, KEY_A]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = true
		events.append(key)
	return events


func test_expert_turn_table_ends_facing_right() -> void:
	for start_cell in 9:
		var cell := start_cell
		var steps := 0
		while cell != EXPERT_TURN_DONE_CELL:
			cell = EXPERT_TURN_TABLE[cell]
			steps += 1
			assert_int(steps).is_less(10)
