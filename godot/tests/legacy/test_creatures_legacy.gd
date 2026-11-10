class_name TestCreaturesLegacy
extends GdUnitTestSuite
## Teaches: checking the engine against the ORIGINAL game's own creatures, rules tables and recorded flights. This is the legacy half of the
## creature, combat and bubble tests of `tests/engine/` (those run on the dev pack with numbers of its own): what only the original's data can
## prove stays here and runs on the legacy pack. The sub fits under the second jellyfish of sector 0 screen 2 (a screenshot of the original is
## the ground truth), the creatures' hit rectangles are the raw tables of the game, the dissolve's two orders are the bytes of
## the EXE, the bubbles' rules are the decoded ones, and the flights of the rules are the digest of the scene before the rules were split from the nodes.
##
## Measured on a screenshot of the original, sector 0 screen 2 (registered against the background art): the sub picture's top-left corner is at
## window (395, 158), cell 6 (right-facing); the 2nd jellyfish hangs from the top of the playfield (picture at window (428, 36), i.e. playfield
## (412, 4)); its tail (creature 6) ends 24 px above the sub's hurt rectangle.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const RAW_DIR := "res://../extracted/data/NEP_raw/"

## Where the original screenshot shows the sub (SubX, SubY) and its cell.
const GAP_SUB := Vector2i(395, 158)
const GAP_CELL := 6
const SCREEN := 2
## Creatures 3 + 4 are the first jellyfish and its tail, 5 + 6 the second.
const JELLY_2 := 5
const TAIL_2 := 6

## [sector, first screen] of the flights.
const RUNS := [[0, 0], [0, 6], [1, 2], [2, 4], [5, 0], [16, 3], [30, 0], [30, 4], [9, 1], [12, 7]]
const TICKS := 500
## SHA-256 of the whole trace of RUNS, as the scene-only game produced it - except for one deliberate change since:
## a tick in which a waiting problem opens stops after the loop top and runs the rest when the problem is resolved (`SimWorld.tick`,
## `problem_resolved`; `DoAction` goes on when `DoMathProblem` returns). This harness resolves the problem right AFTER the tick, so the
## state line of the four ticks in RUNS that open one (the first is run [0, 6], tick 35) is written before the
## rest of the tick has run: only those lines (and the place of an event in them) differ from the old trace; the flights are otherwise
## the same. The digest before that change was 9585177de8de2b90c0d2449108e387afbc9e61e3777a177f186397d6440013a1.
## If a rule changes on purpose (a "Deliberate deviation"), the digest changes with it: print the trace of every run, look at the first lines
## that differ, and put the new digest below.
const PRE_D3_DIGEST := "25e1f8ac32c6ea6d19a4e3adbb7cba91d975b13825f8df6ef41eec25ccd8047e"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"

var _world: SectorWorld
var _probe: AudioProbe
var _events: Array[String]
var _rules: BubbleRules


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	Audio.stop_sfx()
	_probe = AudioProbe.new()
	_rules = Catalog.bubble_rules()
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.load_sector(0, SCREEN)
	_world.start_flight(GAP_SUB.x, GAP_SUB.y, GAP_CELL)


func after_test() -> void:
	_probe.stop()
	Audio.stop_sfx()
	GameClock.paused = false
	GameState.reset()


func test_creatures_are_drawn_where_the_original_draws_them() -> void:
	# Window pixels (428, 36) minus the playfield's (16, 32).
	assert_that(_world.original.foes[JELLY_2].position).is_equal(Vector2(412, 4))
	assert_that(_world.original.foes[3].position).is_equal(Vector2(200, 4))
	# The hit rectangle is the picture's table entry moved to the window position (428, 36).
	var jelly := _world.original.foes[JELLY_2]
	var table_rect := SpriteMeta.for_zone(0).hit_rect(jelly.vm.frame, jelly.vm.flip)
	assert_that(jelly.model.hit_rect_window()).is_equal(Rect2i(Vector2i(428, 36) + table_rect.position, table_rect.size))


func test_the_jellyfish_tails_hop_with_the_bell_and_never_glide() -> void:
	# The tails (creatures 4 and 6, `foe4_start`, picture 44) move once with MOVE_REL in time with the bell's
	# picture, then wait two ticks. One of their four steps is just 8 px ((200, 84) -> (208, 82)), short enough that
	# a distance rule alone let TickSmoothing slide it into place (Foe.HOPPING_PICTURES).
	var hops := 0
	for tick in 60:
		var before := _world.original.foes[TAIL_2].position
		_world.tick()
		for i in [TAIL_2 - 2, TAIL_2]:
			assert_bool(_world.original.foes[i].is_gliding()).override_failure_message("tail %d glides on tick %d" % [i, tick]).is_false()
		if _world.original.foes[TAIL_2].position != before:
			hops += 1
	assert_int(hops).is_greater(4)


func test_other_creatures_glide_from_their_first_step() -> void:
	# Sector 0 screen 4: creature 12 swims (short MOVE_REL steps); every step is drawn gliding, the first one after
	# standing still included (snapping that one made creatures that move and pause look jittery).
	_world.load_sector(0, 4)
	var moves := 0
	for tick in 20:
		var before := _world.original.foes[12].position
		_world.tick()
		if _world.original.foes[12].position != before:
			moves += 1
			assert_bool(_world.original.foes[12].is_gliding()).override_failure_message("step on tick %d snapped" % tick).is_true()
	assert_int(moves).is_greater(10)


func test_the_sub_fits_under_the_2nd_jellyfish_for_its_whole_cycle() -> void:
	var sub_rect := _world.sim.sub.hurt_rect_window()
	var min_gap := 1000
	var overlapped_in_x := false
	for tick in 400:                                       # many full cycles of the jellyfish and its tail
		_world.tick()
		assert_int(GameState.oxygen()).is_equal(4)
		assert_bool(_world.sim.sub.is_invulnerable()).is_false()
		for foe in _world.original.foes:
			if not foe.model.is_touchable():
				continue
			var rect := foe.model.hit_rect_window()
			assert_bool(FoeModel.rects_touch(sub_rect, rect)).is_false()
			if rect.end.x >= sub_rect.position.x and rect.position.x <= sub_rect.end.x:
				overlapped_in_x = true                     # directly above the sub: the real test
				min_gap = mini(min_gap, sub_rect.position.y - rect.end.y)
	assert_bool(overlapped_in_x).is_true()
	assert_int(min_gap).is_greater(0)
	assert_int(min_gap).is_less(40)                        # a tight fit, the original's screenshot shows ~24 px


func test_touching_the_tail_by_one_pixel_hurts_and_one_pixel_less_does_not() -> void:
	var tail := _world.original.foes[TAIL_2]
	var guard := 0
	while not tail.model.is_touchable() and guard < 100:         # the tail blinks out of sight for a while
		_world.tick()
		guard += 1
	assert_bool(tail.model.is_touchable()).is_true()
	var tail_rect := tail.model.hit_rect_window()
	var cell_rect := _world.sim.sub.tuning.frame_rects[GAP_CELL]
	var x := tail_rect.position.x - cell_rect.position.x + 2
	# One pixel clear underneath: no damage.
	_place_sub(x, tail_rect.end.y + 1 - cell_rect.position.y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), tail_rect)).is_false()
	_world.check_contacts()
	assert_int(GameState.oxygen()).is_equal(4)
	# The top row of the sub's rectangle is the tail's last row: they share one pixel row.
	_place_sub(x, tail_rect.end.y - cell_rect.position.y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), tail_rect)).is_true()
	_world.check_contacts()
	assert_int(GameState.oxygen()).is_equal(3)
	assert_bool(_world.sim.sub.is_invulnerable()).is_true()


func test_every_creature_rectangle_equals_the_raw_table_doubled() -> void:
	# (NEP.DLL table, SpriteMetaTable file, number of sprites): 8 bytes per sprite = (x1, y1, x2, y2)
	# unflipped, then flipped, in half pixels.
	var tables: Array = [
		[10020, "common"], [10017, "ink"], [10035, "zone0"], [10050, "zone1"], [10065, "zone2"],
		[10080, "zone3"], [10095, "zone4"], [10714, "zone5"], [10720, "zone6"]]
	var checked := 0
	for entry: Array in tables:
		var raw := FileAccess.get_file_as_bytes(RAW_DIR + "NEP_%d.bin" % entry[0])
		if raw.is_empty():
			continue                                       # a checkout without extracted/: nothing to compare with
		var meta: SpriteMetaTable = load(LegacyPack.ROOT + "data/sprite_meta/sprite_meta_%s.tres" % entry[1])
		assert_int(raw.size()).is_greater_equal(8 * meta.count())
		for slot in meta.count():
			for flipped in 2:
				var at := 8 * slot + 4 * flipped
				var expected := Rect2i(raw[at] * 2, raw[at + 1] * 2,
						(raw[at + 2] - raw[at]) * 2, (raw[at + 3] - raw[at + 1]) * 2)
				assert_that(meta.hit_rect(slot, flipped == 1)).is_equal(expected)
				checked += 1
	assert_int(checked).is_greater(0)


func test_the_sub_rectangles_equal_the_original_table() -> void:
	var table: Array = [[10, 14, 90, 42], [4, 16, 86, 44], [2, 14, 94, 42], [6, 14, 78, 42], [26, 14, 70, 42],
			[16, 14, 88, 42], [0, 14, 92, 42], [8, 16, 90, 44], [4, 14, 84, 42]]
	var tuning := Tuning.original().sub
	for cell in 9:
		var t: Array = table[cell]
		assert_that(tuning.frame_rects[cell]).is_equal(Rect2i(t[0], t[1], t[2] - t[0], t[3] - t[1]))


## Puts the sub's picture at window (x, y). `fresh`: also forget its velocity and immunity.
func _place_sub(x: int, y: int, fresh: bool = true) -> void:
	var invulnerability := _world.sim.sub.invulnerability
	_world.original.sub.place_original(x, y, GAP_CELL)
	if not fresh:
		_world.sim.sub.invulnerability = invulnerability


func test_the_purple_shell_plays_effect_13_once_per_round_through_audio() -> void:
	_world.load_sector(0, 0)
	_probe.clear()
	for i in 39:                                      # two rounds of 19 ticks (LOOP0 runs count + 1 times)
		_world.tick()
	assert_array(_probe.sfx).is_equal([&"clam_chomp", &"clam_chomp"])
	assert_int(Audio.busy_sfx_players()).is_greater(0)  # a real stream was started, not just announced


func test_the_rules_are_the_decoded_ones() -> void:
	assert_int(_rules.slot_count()).is_equal(2)
	assert_int(_rules.spawn_chance).is_equal(50)
	assert_array(_rules.slot_rise_per_tick).is_equal(PackedInt32Array([10, 6]))
	assert_int(_rules.spawn_y).is_equal(320)
	assert_int(_rules.top_y).is_equal(32)


func test_no_bubbles_on_the_first_four_screens_of_sector_0_and_two_finale_screens() -> void:
	for screen in 4:
		assert_bool(_rules.allowed_on(0, screen)).is_false()
	assert_bool(_rules.allowed_on(0, 4)).is_true()
	assert_bool(_rules.allowed_on(0, 5)).is_true()
	assert_bool(_rules.allowed_on(1, 0)).is_true()
	assert_bool(_rules.allowed_on(30, 1)).is_false()
	assert_bool(_rules.allowed_on(30, 2)).is_false()
	assert_bool(_rules.allowed_on(30, 3)).is_true()
	assert_bool(_rules.allowed_on(31, 1)).is_true()


func test_the_hit_bubbles_sit_where_the_table_says() -> void:
	var tuning := Tuning.original().sub
	assert_array(tuning.hit_bubble_x_by_cell).is_equal(PackedInt32Array([4, 4, 4, 4, 16, 16, 16, 16, 16]))


func test_the_two_orders_are_the_bytes_of_the_exe() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/data/dissolve_tables.json"))
	assert_array(DissolvePattern.COLUMN_ORDER).is_equal(_ints(data["column_order"]))   # 0x441188
	assert_array(DissolvePattern.ROW_ORDER).is_equal(_ints(data["row_order"]))         # 0x441198
	assert_int(DissolvePattern.PASSES).is_equal(int(data["passes"]))
	assert_int(DissolvePattern.BLOCK).is_equal(int(data["block"]))


## JSON numbers come back as floats.
func _ints(numbers: Array) -> Array[int]:
	var result: Array[int] = []
	for number in numbers:
		result.append(int(number))
	return result


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


func test_the_flights_are_the_same_as_before_the_rules_were_split_from_the_nodes() -> void:
	var run := _new_run()
	var lines: Array[String] = []
	for the_run in RUNS:
		var sim := SimWorld.new(run)
		run.reset()
		lines.append_array(_fly(sim, run, sim.tick, the_run[0], the_run[1], TICKS))
	var trace := "\n".join(lines) + "\n"
	assert_str(trace.sha256_text()).override_failure_message(
			"the rules fly differently from the scene of commit 0175b86 (see the header of this file)").is_equal(PRE_D3_DIGEST)
