class_name TestDiagramAnimations
extends GdUnitTestSuite
## Teaches: testing an ANIMATION without waiting for it. A diagram describes its build-up (and the replay after a right answer) as a `DiagramTimeline`:
## steps with a tick, a sound and the picture that shows from then on. The tests read that list for diagrams of specs the test writes (`ProblemKit.diagram_of`:
## the "intro" modes sequence, bars, lockstep and run, and the "success" modes pictures and overlay), then play a short timeline for real to check that the
## Tween keeps the schedule and that the owner's clock (`animate_to`) shows only what is due. Ticks are the original's 1/73 s.
## The original's per-type timings (type 2 ... 33) and its radar are tests/legacy/test_diagram_animations_legacy.gd; dev's own build-up is the last test here.

const K = preload("res://tests/engine/problem_kit.gd")
const PANEL := {"pic": 0, "pos": [20, 60]}
const BAR_SOUND := 35
const POP_SOUND := 41


func _bar() -> StringName:
	return Catalog.sfx_catalog().name_of(BAR_SOUND)


func _pop() -> StringName:
	return Catalog.sfx_catalog().name_of(POP_SOUND)


## A diagram of `spec` (family "items") with the record `numbers`.
func _drawn(spec: Dictionary, numbers: Array = [0, 0, 0]) -> DiagramBase:
	spec["family"] = "items"
	return auto_free(K.diagram_of(spec, numbers)) as DiagramBase


## Four pictures that come one after the other, every `interval` ticks, each with a sound.
func _four_pieces(interval: int = 15) -> DiagramBase:
	var items: Array = [PANEL]
	for i in 4:
		items.append({"pic": 2 + i, "pos": [60 + 40 * i, 150], "animate": true})
	return _drawn({"items": items, "intro": {"mode": "sequence", "sfx": BAR_SOUND, "interval": interval}})


## [[tick, sfx], ...] for a sound at every multiple of `every` ticks, `count` times.
static func _every(every: int, count: int, sfx: int) -> Array:
	var expected := []
	for i in count:
		expected.append([i * every, sfx])
	return expected


# --- no animation, and the end state ---------------------------------------------------------

func test_a_diagram_without_an_animation_spec_has_no_timeline() -> void:
	var diagram := _drawn({"items": [PANEL, {"pic": 2, "pos": [60, 150]}]})
	assert_bool(diagram.intro.is_empty()).is_true()
	assert_bool(diagram.has_intro()).is_false()
	assert_bool(diagram.has_success_replay()).is_false()
	assert_int(diagram.intro_length()).is_equal(0)


func test_a_diagram_is_not_drawn_in_part_until_an_animation_runs() -> void:
	var diagram := _four_pieces()
	assert_array(diagram._shown).is_equal(diagram.items)                # a fresh diagram shows the end state
	assert_bool(diagram.is_playing()).is_false()


# --- the build-up modes -------------------------------------------------------------------

func test_sequence_one_group_per_interval_with_a_sound_each() -> void:
	var diagram := _four_pieces(15)
	assert_array(diagram.intro.sounds()).is_equal(_every(15, 4, BAR_SOUND))
	assert_int(diagram.intro.end_tick).is_equal(15 * 4)                     # the wait after the last piece too
	assert_int(diagram.intro.steps.size()).is_equal(4)
	assert_int(diagram.intro.steps[0].items.size()).is_equal(2)             # the panel appears together with the first piece
	assert_int(diagram.intro.steps[3].items.size()).is_equal(5)


func test_sequence_without_a_trailing_wait_ends_with_the_last_piece() -> void:
	var items: Array = [PANEL, {"pic": 2, "pos": [60, 150], "animate": true}, {"pic": 3, "pos": [100, 150], "animate": true}]
	var diagram := _drawn({"items": items, "intro": {"mode": "sequence", "sfx": BAR_SOUND, "interval": 30, "trailing": false}})
	assert_int(diagram.intro.end_tick).is_equal(30)


func test_every_intro_ends_in_the_picture_the_static_diagram_shows() -> void:
	for diagram in [_four_pieces(), _bars(), _lockstep(), _run()]:
		var steps: Array[DiagramStep] = diagram.intro.steps
		assert_array(steps).is_not_empty()
		assert_int(steps[0].tick).is_equal(0)
		assert_array(steps.back().items).is_equal(diagram.items)           # same items, same drawing order
		var previous_count := 0
		var previous_tick := 0
		for step in steps:
			assert_int(step.tick).is_greater_equal(previous_tick)         # in time order
			assert_int(step.items.size()).is_greater_equal(previous_count) # items only come, none go
			previous_tick = step.tick
			previous_count = step.items.size()
		assert_int(diagram.intro.end_tick).is_greater_equal(previous_tick)


## Bars: each copy of a repeated group one by one, `gap` ticks between the groups (a column of 3 and a column of 2).
func _bars() -> DiagramBase:
	return _drawn({"items": [PANEL,
			{"pic": 1, "pos": [90, 226], "repeat": {"count": {"field": 0, "divisor": 5}, "step": [0, -26]}, "animate": true},
			{"pic": 1, "pos": [130, 226], "repeat": {"count": {"field": 1, "divisor": 5}, "step": [0, -26]}, "animate": true}],
			"intro": {"mode": "bars", "sfx": BAR_SOUND, "interval": 6, "gap": 30}}, [15, 10, 0])


func test_bars_one_copy_per_interval_and_a_gap_between_the_columns() -> void:
	var diagram := _bars()
	var expected := []
	var tick := 0
	for bar_copies in [3, 2]:
		for _c in bar_copies:
			expected.append([tick, BAR_SOUND])
			tick += 6
		tick += 30                                                       # (the gap also follows the last column in the sum below)
	var sounds := diagram.intro.sounds()
	assert_array(sounds).is_equal(expected)
	assert_int(diagram.intro.end_tick).is_equal(tick - 30)                # nothing waits after the last column
	var sound_steps := diagram.intro.steps.filter(func(step: DiagramStep) -> bool: return step.sfx >= 0)
	for i in sound_steps.size():
		assert_int(sound_steps[i].items.size()).is_equal(2 + i)         # the panel is there from the start, each sound adds one copy


func _lockstep() -> DiagramBase:
	return _drawn({"items": [PANEL,
			{"pic": 1, "pos": [90, 226], "repeat": {"count": {"field": 0}, "step": [0, -26]}, "animate": true},
			{"pic": 2, "pos": [130, 226], "repeat": {"count": {"field": 1}, "step": [0, -26]}, "animate": true}],
			"intro": {"mode": "lockstep", "sfx": POP_SOUND, "interval": 10}}, [3, 2, 0])


func test_lockstep_copy_i_of_every_group_together() -> void:
	var diagram := _lockstep()
	assert_array(diagram.intro.sounds()).is_equal(_every(10, 3, POP_SOUND))      # as long as the longest group
	assert_int(diagram.intro.end_tick).is_equal(30)
	assert_int(diagram.intro.steps[0].items.size()).is_equal(3)                 # the panel and the first copy of each group
	assert_int(diagram.intro.steps[2].items.size()).is_equal(6)                 # the third copy of the first group only


func _run() -> DiagramBase:
	return _drawn({"items": [PANEL, {"pic": 3, "pos": [60, 226], "repeat": {"count": {"field": 0}, "step": [20, 0]}, "animate": true}],
			"intro": {"mode": "run", "sfx": POP_SOUND, "interval": 10, "lead": 30, "trail": 60}}, [5, 0, 0])


func test_run_one_sound_for_the_whole_run_and_the_stop_when_it_is_up() -> void:
	var diagram := _run()
	assert_array(diagram.intro.sounds()).is_equal([[30, POP_SOUND]])               # a single sound, `lead` ticks in
	assert_array(Array(diagram.intro.stops())).is_equal([30 + 10 * 5])
	assert_int(diagram.intro.end_tick).is_equal(30 + 10 * 5 + 60)
	assert_int(diagram.intro.steps[0].items.size()).is_equal(1)                    # only the panel, until the lead is over
	assert_int(diagram.intro.steps.size()).is_equal(1 + 5 + 1)                     # the panel, one step per copy, the stop


# --- the replay after a right answer ----------------------------------------------------------

func _replay_pictures() -> DiagramBase:
	return _drawn({"items": [PANEL, {"pic": 5, "pos": [60, 150]}],
			"success": {"mode": "pictures", "pos": [100, 100], "flip_field": 0, "sfx": POP_SOUND, "end": 88,
			"frames": [{"tick": 22, "pic": 6}, {"tick": 44, "pic": 7}]}}, [1, 0, 0])


func test_the_replay_of_two_pictures_has_its_sounds_and_its_length_from_the_data() -> void:
	var diagram := _replay_pictures()
	assert_bool(diagram.has_success_replay()).is_true()
	var replay := diagram.success_replay
	assert_array(replay.sounds()).is_equal([[22, POP_SOUND], [44, POP_SOUND]])
	assert_int(replay.end_tick).is_equal(88)
	assert_int(diagram.success_replay_length()).is_equal(88)
	assert_bool(replay.steps[0].items.back().flip).is_true()                     # mirrored by the field
	assert_int(replay.steps[1].items.back().pic).is_equal(7)
	assert_int(replay.steps[1].items.size()).is_equal(2)                         # the panel and the picture: a frame replaces the last


func test_the_replay_that_writes_the_answer_onto_the_picture_has_no_sound_and_no_delay() -> void:
	var diagram := _drawn({"items": [PANEL], "success": {"mode": "overlay", "items": [{"text": {"literal": "42"}, "box": [100, 40], "y": 150}]}})
	var replay := diagram.success_replay
	assert_int(replay.steps.size()).is_equal(1)
	assert_int(replay.steps[0].tick).is_equal(0)
	assert_int(replay.end_tick).is_equal(0)
	assert_array(replay.sounds()).is_empty()
	assert_int(replay.steps[0].items.size()).is_equal(2)                         # the picture and the answer on top


# --- playing them ---------------------------------------------------------------------------------

## Adds `diagram` to the tree (a Tween needs it) and records every sound it asks for with the time in ms.
func _play_recorded(diagram: DiagramBase, replay: bool) -> Array:
	add_child(diagram)
	var heard := []
	var started := Time.get_ticks_msec()
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: heard.append([Time.get_ticks_msec() - started, sfx_id]))
	diagram.sfx_stop_requested.connect(func() -> void: heard.append([Time.get_ticks_msec() - started, -1]))
	if replay:
		diagram.play_success_replay()
	else:
		diagram.play_intro()
	await assert_signal(diagram).wait_until(4000).is_emitted("animation_finished")
	heard.append([Time.get_ticks_msec() - started, -2])                       # the end
	return heard


func test_a_diagram_plays_its_sounds_on_schedule() -> void:
	var diagram := _four_pieces(15)                                           # 4 pieces, 15 ticks (205 ms) apart, 60 ticks (822 ms) in all
	var heard: Array = await _play_recorded(diagram, false)
	assert_int(heard.size()).is_equal(5)
	for i in 4:
		assert_str(heard[i][1]).is_equal(_bar())
	# (the first wait is not measured: the Tween's first frame may be late, which shortens it)
	for i in range(2, 4):
		assert_int(int(heard[i][0]) - int(heard[i - 1][0])).is_between(205 - 60, 205 + 60)
	assert_int(int(heard[4][0]) - int(heard[3][0])).is_between(205 - 60, 205 + 60)     # the wait after the last piece
	assert_bool(diagram.is_playing()).is_false()
	assert_array(diagram._shown).is_equal(diagram.items)


func test_the_first_sound_comes_with_the_first_frame() -> void:
	var diagram := _four_pieces()
	add_child(diagram)
	var heard := []
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: heard.append(sfx_id))
	diagram.play_intro()
	assert_array(heard).is_equal([_bar()])                                       # nothing waits for the Tween's first frame
	assert_bool(diagram.is_playing()).is_true()
	assert_int(diagram._shown.size()).is_equal(2)                                # the panel and the first piece
	diagram.skip_animation()
	assert_bool(diagram.is_playing()).is_false()
	assert_array(diagram._shown).is_equal(diagram.items)


func test_a_success_replay_plays_its_sounds_on_schedule() -> void:
	var diagram := _replay_pictures()                                          # sounds at 22 and 44 ticks, over at 88: 301 ms apart, 603 ms to the end
	var heard: Array = await _play_recorded(diagram, true)
	assert_int(heard.size()).is_equal(3)
	assert_str(heard[0][1]).is_equal(_pop())
	assert_str(heard[1][1]).is_equal(_pop())
	assert_int(int(heard[1][0]) - int(heard[0][0])).is_between(301 - 60, 301 + 60)
	assert_int(int(heard[2][0]) - int(heard[1][0])).is_between(603 - 60, 603 + 60)
	assert_array(diagram._shown).is_equal(diagram.success_replay.steps.back().items)   # the replay's last picture stays


func test_a_skip_cuts_a_long_sound_off() -> void:
	var diagram := _run()                                                       # one sound for the whole run: a skip must silence it
	add_child(diagram)
	var events := []
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: events.append("play %s" % sfx_id))
	diagram.sfx_stop_requested.connect(func() -> void: events.append("stop"))
	diagram.play_intro()
	assert_array(events).is_empty()                                             # the lead comes first
	diagram.skip_animation()
	assert_array(events).is_equal(["stop"])
	assert_bool(diagram.is_playing()).is_false()


func test_a_diagram_without_a_replay_returns_at_once() -> void:
	var diagram := _four_pieces()
	add_child(diagram)
	await diagram.play_success_replay()                                          # would hang if it waited for a signal
	assert_bool(diagram.is_playing()).is_false()


# --- the ballast panel's Done button (GetBallastAnswer 0x4196e8) ----------------------------------

func test_ballast_done_clicks_shows_the_pressed_ok_and_tells_the_flow_how_long_to_hold() -> void:
	var problem := ProblemFactory.make(28, 0, null, 0)
	var panel := auto_free(DiagramFactory.create(problem)) as BallastPanelDiagram
	add_child(panel)
	var clicks := []
	var holds := []
	panel.sfx_requested.connect(func(sfx_id: StringName) -> void: clicks.append(sfx_id))
	panel.done_pressed.connect(func(mask: int, hold_ticks: int) -> void: holds.append([mask, hold_ticks]))
	var total: Dictionary = panel.spec["total"]
	panel.toggle(2)
	clicks.clear()
	panel._press(panel.slot_count())                                          # Done
	assert_array(clicks).is_equal([&"click"])                                      # Done clicks like every button
	assert_array(holds).is_equal([[1 << 2, int(total["hold_ticks"])]])            # the length of the hold is the panel's DATA ...
	assert_bool(panel.is_done_pressed()).is_true()                             # ... and whoever owns the problem counts it (ProblemFlow)
	assert_int(panel.pictures(int(total["done_pic"])).size()).is_equal(1)       # the pressed OK instead of the idle button
	assert_int(panel.pictures(int(total["idle_pic"])).size()).is_equal(0)
	panel.toggle(0)                                                            # nothing can be changed meanwhile
	assert_int(panel.selected).is_equal(1 << 2)
	# asked again after a wrong answer: the panel is ready again
	panel.keyboard_enabled = true
	assert_bool(panel.is_done_pressed()).is_false()
	assert_int(panel.pictures(int(total["done_pic"])).size()).is_equal(0)


# --- the clock belongs to the owner -----------------------------------------------------------------
# `ProblemFlow` counts the ticks of a build-up and tells the diagram where it is: the diagram only shows what is due.

func test_a_diagram_shows_only_what_is_due_at_the_tick_it_is_told() -> void:
	var diagram := _four_pieces(15)                                            # 4 pieces, a sound every 15 ticks, over at tick 60
	var heard := []
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: heard.append(sfx_id))
	assert_int(diagram.intro_length()).is_equal(60)
	diagram.begin_intro()
	assert_array(heard).has_size(1)                                            # tick 0 shows in the very first frame
	assert_bool(diagram.is_playing()).is_true()
	diagram.animate_to(14)
	assert_array(heard).has_size(1)
	diagram.animate_to(15)
	assert_array(heard).has_size(2)
	diagram.animate_to(45)                                                     # (ticks 30 and 45 come together when time jumps)
	assert_array(heard).has_size(4)
	diagram.animate_to(59)
	assert_bool(diagram.is_playing()).is_true()
	diagram.animate_to(60)
	assert_bool(diagram.is_playing()).is_false()
	assert_array(diagram._shown).is_equal(diagram.items)
	diagram.animate_to(1000)                                                   # an animation that is over ignores the clock
	assert_array(heard).has_size(4)


func test_a_jump_far_ahead_still_plays_every_sound_once() -> void:
	var diagram := _four_pieces(30)
	var heard := []
	diagram.sfx_requested.connect(func(sfx_id: StringName) -> void: heard.append(sfx_id))
	diagram.begin_intro()
	diagram.animate_to(100000)
	assert_array(heard).has_size(4)
	assert_bool(diagram.is_playing()).is_false()


# --- the pack's own build-up ------------------------------------------------------------------------

func test_dev_type_3_builds_up_in_the_steps_its_data_names() -> void:
	# `dev_problems.sonar_diagram`: three pictures, one every `interval` ticks, a sound at each
	var problem := ProblemFactory.make(3, 0, null, 0)
	var diagram := auto_free(DiagramFactory.create(problem)) as DiagramBase
	var plan: Dictionary = problem.type.diagram["intro"]
	var interval: int = plan["interval"]
	assert_bool(diagram.has_intro()).is_true()
	assert_array(diagram.intro.sounds()).is_equal(_every(interval, 3, int(plan["sfx"])))
	assert_int(diagram.intro_length()).is_equal(3 * interval)
	assert_array(diagram.intro.steps.back().items).is_equal(diagram.items)
	var quiet := auto_free(DiagramFactory.create(ProblemFactory.make(6, 0, null, 0))) as DiagramBase
	assert_bool(quiet.has_intro()).is_false()                                     # the other types draw at once
