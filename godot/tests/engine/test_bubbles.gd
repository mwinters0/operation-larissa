class_name TestBubbles
extends GdUnitTestSuite
## The ambient bubbles (BUBBLES.C, DESIGN 9): the rules as data, the spawn rule, the motion, the lifetime, the cap
## of two, where they are not allowed, the draw order, and that nothing about the sub or the air changes them.
## Also the two overlays on the sub that look like bubbles (hit bubbles, message light).
##
## Teaches: replaying a seeded random generator in the test as an independent model of the rule, and driving a
## tick-based node by calling its `step()` by hand with the real clock stopped. The numbers are the pack's own (`BubbleRules` is data: dev's
## has four bubbles, the original's two); a test that needs a number of its own makes a `BubbleRules` of its own. The original's rules are
## in `legacy/test_creatures_legacy.gd`.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _rules: BubbleRules


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_rules = Catalog.bubble_rules()


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


## A Bubbles node outside any world. `chance` replaces the pack's spawn chance (1 = starts every tick).
func _make(seed_value: int, chance: int = -1) -> Bubbles:
	var node := Bubbles.new()
	node.rules = _rules.duplicate() as BubbleRules
	if chance > 0:
		node.rules.spawn_chance = chance
	add_child(auto_free(node))
	node.seed_rng(seed_value)
	return node


# --- the rules as data ------------------------------------------------------------------------------------------

func test_the_rules_are_consistent_data() -> void:
	assert_int(_rules.slot_count()).is_greater(0)
	assert_int(_rules.slot_rise_per_tick.size()).is_equal(_rules.slot_count())
	assert_int(_rules.slot_loop.size()).is_equal(_rules.slot_count())
	assert_int(_rules.spawn_chance).is_greater(0)
	assert_int(_rules.spawn_y).is_greater(_rules.top_y)
	for slot in _rules.slot_count():
		assert_int(_rules.slot_rise_per_tick[slot]).is_greater(0)
		assert_int(_rules.slot_loop[slot].size()).is_greater(0)
		assert_int(_rules.slot_first_picture[slot]).is_less(_rules.picture_sizes.size())
		for picture in _rules.slot_loop[slot]:
			assert_int(picture).is_less(_rules.picture_sizes.size())
	assert_int(Catalog.fx_frames().get_frame_count(&"all")).is_greater_equal(_rules.picture_sizes.size())


func test_the_picture_order_is_the_first_picture_and_then_the_loop_for_ever() -> void:
	var made := BubbleRules.new()                                     # (rules made here: a column and a cluster)
	made.slot_first_picture = PackedInt32Array([2, 5])
	made.slot_loop = [PackedInt32Array([7, 8, 9]), PackedInt32Array([4, 3])]
	var column: Array[int] = []
	var cluster: Array[int] = []
	for age in 9:
		column.append(made.picture_at(0, age))
		cluster.append(made.picture_at(1, age))
	assert_array(column).is_equal([2, 7, 8, 9, 7, 8, 9, 7, 8])
	assert_array(cluster).is_equal([5, 4, 3, 4, 3, 4, 3, 4, 3])


func test_x_is_even_and_at_least_the_left_margin() -> void:
	var made := BubbleRules.new()
	made.x_base = 30
	for r in 100:
		var x := made.x_for(r)
		assert_int(x % 2).is_equal(0)
		assert_bool(x >= made.x_base - 1).is_true()
	assert_int(made.x_for(0)).is_equal(30)
	assert_int(made.x_for(1)).is_equal(30)        # 31 is odd: rounded down
	assert_int(made.x_for(2)).is_equal(32)
	made.x_base = 31                              # an odd margin: the first even x is below it
	assert_int(made.x_for(0)).is_equal(30)


func test_screens_without_bubbles_and_the_finales_blocked_screens() -> void:
	var made := BubbleRules.new()
	made.no_bubble_screens = [Vector2i(7, 0), Vector2i(7, 1)]
	made.finale_sector = 9
	made.finale_screens = PackedInt32Array([1, 2])
	assert_bool(made.allowed_on(7, 0)).is_false()
	assert_bool(made.allowed_on(7, 1)).is_false()
	assert_bool(made.allowed_on(7, 2)).is_true()
	assert_bool(made.allowed_on(8, 0)).is_true()
	assert_bool(made.allowed_on(9, 1)).is_false()
	assert_bool(made.allowed_on(9, 2)).is_false()
	assert_bool(made.allowed_on(9, 3)).is_true()
	assert_bool(made.allowed_on(8, 1)).is_true()


# --- spawn --------------------------------------------------------------------------------------------------------

func test_a_fixed_seed_replays_the_same_bubbles() -> void:
	var a := _make(1234)
	var b := _make(1234)
	var other := _make(99)
	var trace_a: Array[String] = []
	var trace_b: Array[String] = []
	var trace_other: Array[String] = []
	for tick in 300:
		a.step()
		b.step()
		other.step()
		trace_a.append(_snapshot(a))
		trace_b.append(_snapshot(b))
		trace_other.append(_snapshot(other))
	assert_array(trace_a).is_equal(trace_b)
	assert_bool(trace_a != trace_other).is_true()
	assert_bool(trace_a.any(func(line: String) -> bool: return line.replace("-", "").replace("|", "") != "")).is_true()     # something did appear


func test_the_spawn_follows_the_documented_random_draws() -> void:
	# An independent model: one draw for the 1-in-`spawn_chance` test per idle bubble, then (only on a hit) one for x.
	var node := _make(777)
	var model := RandomNumberGenerator.new()
	model.seed = 777
	var model_x: Array[int] = []
	var started: Array[bool] = []
	for slot in _rules.slot_count():
		model_x.append(-1)
		started.append(false)
	for tick in 400:
		node.step()
		for slot in _rules.slot_count():
			if started[slot]:
				continue
			if model.randi_range(0, _rules.spawn_chance - 1) != 0:
				continue
			var width := _rules.picture_sizes[_rules.slot_first_picture[slot]].x & ~1
			model_x[slot] = _rules.x_for(model.randi_range(0, _rules.x_span - width - 1))
			started[slot] = true
			# This slot's first bubble must have started on exactly this tick, at exactly that x.
			assert_bool(node.bubble(slot).active).is_true()
			assert_int(node.bubble(slot).window_pos.x).is_equal(model_x[slot])
			assert_int(node.bubble(slot).window_pos.y).is_equal(_rules.spawn_y)
			assert_int(node.bubble(slot).frame).is_equal(_rules.slot_first_picture[slot])
		if not started.has(false):
			break
	assert_bool(started.has(true)).is_true()


func test_the_spawn_rate_is_about_one_in_spawn_chance_per_idle_bubble() -> void:
	# Sample the rule directly: count the ticks (with the bubble forced idle again each time) that start one.
	var node := _make(2024)
	var starts := 0
	var trials := 5000
	for i in trials:
		node.clear()
		node.step()
		if node.bubble(0).active:
			starts += 1
	assert_int(starts).is_between(roundi(trials / float(_rules.spawn_chance) * 0.6), roundi(trials / float(_rules.spawn_chance) * 1.4))


func test_x_stays_inside_the_playfield_for_every_width() -> void:
	var node := _make(5, 1)
	for i in 200:
		node.clear()
		node.step()
		for slot in _rules.slot_count():
			var bubble := node.bubble(slot)
			var width := bubble.sprite_frames.get_frame_texture(&"all", bubble.frame).get_width()
			assert_bool(bubble.window_pos.x >= _rules.x_base - 1).is_true()
			assert_bool(bubble.window_pos.x + width <= _rules.x_base + _rules.x_span).is_true()


# --- motion and lifetime ----------------------------------------------------------------------------------------

func test_rising_speed_and_pictures_each_tick() -> void:
	var node := _make(1, 1)                    # chance 1: all start on the first tick
	node.step()
	var x0: Array[int] = []
	for slot in _rules.slot_count():
		x0.append(node.bubble(slot).window_pos.x)
		assert_int(node.bubble(slot).window_pos.y).is_equal(_rules.spawn_y)
	for age in range(1, 6):
		node.step()
		for slot in _rules.slot_count():
			var bubble := node.bubble(slot)
			assert_int(bubble.window_pos.y).is_equal(_rules.spawn_y - _rules.slot_rise_per_tick[slot] * age)
			assert_int(bubble.frame).is_equal(_rules.picture_at(slot, age))
			assert_int(bubble.window_pos.x).is_equal(x0[slot])           # a bubble never moves sideways


func test_the_sprite_sits_at_the_window_position_minus_the_playfield_origin() -> void:
	var node := _make(3, 1)
	node.step()
	node.step()
	var column := node.bubble(0)
	assert_vector(column.position).is_equal(Vector2(column.window_pos) - Sub.PLAYFIELD_ORIGIN)


func test_a_bubble_ends_when_its_picture_is_above_the_playfield() -> void:
	var node := _make(8)
	var frames := Catalog.fx_frames()
	for slot in _rules.slot_count():
		node.clear()
		node.rules.spawn_chance = 1                              # start all on the next tick ...
		node.step()
		node.rules.spawn_chance = 1000000                        # ... and (practically) never again
		var expected_life := 0                                  # independent arithmetic from the picture heights
		var y := _rules.spawn_y
		while true:
			expected_life += 1
			y -= _rules.slot_rise_per_tick[slot]
			var height := frames.get_frame_texture(&"all", _rules.picture_at(slot, expected_life)).get_height()
			if height + y < _rules.top_y:
				break
		for tick in expected_life - 1:
			node.step()
			assert_bool(node.bubble(slot).active).is_true()
		node.step()                                              # this tick it leaves
		assert_bool(node.bubble(slot).active).is_false()
		assert_bool(node.bubble(slot).visible).is_false()
		assert_int(expected_life).is_greater(1)


func test_there_are_never_more_bubbles_than_slots_and_they_start_again() -> void:
	var node := _make(11, 1)                  # chance 1: a free slot refills on the very next tick
	var starts := 0
	var was_active: Array[bool] = []
	was_active.resize(_rules.slot_count())
	was_active.fill(false)
	for tick in 400:
		node.step()
		assert_int(node.active_count()).is_less_equal(_rules.slot_count())
		for slot in _rules.slot_count():
			var now := node.bubble(slot).active
			if now and not was_active[slot]:
				starts += 1
			was_active[slot] = now
	assert_int(node.get_child_count()).is_equal(_rules.slot_count())             # the pool never grows
	assert_int(starts).is_greater(_rules.slot_count())


# --- screens --------------------------------------------------------------------------------------------------------

func test_a_new_screen_clears_the_bubbles() -> void:
	var node := _make(4, 1)
	node.enter_screen(DevCreatures.ARENA, 4)
	node.step()
	assert_int(node.active_count()).is_equal(_rules.slot_count())
	node.enter_screen(DevCreatures.ARENA, 5)
	assert_int(node.active_count()).is_equal(0)
	assert_bool(node.bubble(0).visible).is_false()


func test_no_bubble_on_the_blocked_screens_even_when_every_tick_would_start_one() -> void:
	var node := _make(4, 1)
	var arena := DevCreatures.ARENA
	node.rules.no_bubble_screens = [Vector2i(arena, 0), Vector2i(arena, 1), Vector2i(arena, 2), Vector2i(arena, 3)]
	node.rules.finale_sector = DevCreatures.CLOSING
	node.rules.finale_screens = PackedInt32Array([2])
	for screen in 4:
		node.enter_screen(arena, screen)
		for tick in 20:
			node.step()
		assert_int(node.active_count()).is_equal(0)
	node.enter_screen(arena, 4)
	node.step()
	assert_int(node.active_count()).is_equal(_rules.slot_count())
	node.enter_screen(DevCreatures.CLOSING, 2)
	for tick in 20:
		node.step()
	assert_int(node.active_count()).is_equal(0)


func test_the_world_resets_the_bubbles_on_every_screen_it_loads() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.original.bubbles.rules = world.original.bubbles.rules.duplicate()
	world.original.bubbles.rules.spawn_chance = 1
	world.original.bubbles.rules.no_bubble_screens = [Vector2i(DevCreatures.ARENA, 2)]
	var slots := world.original.bubbles.rules.slot_count()
	world.load_sector(DevCreatures.ARENA, 4)
	world.original.bubbles.step()
	assert_int(world.original.bubbles.active_count()).is_equal(slots)
	world.load_screen(5)
	assert_int(world.original.bubbles.active_count()).is_equal(0)
	world.original.bubbles.step()
	assert_int(world.original.bubbles.active_count()).is_equal(slots)
	world.load_screen(2)                                        # blocked screen
	world.original.bubbles.step()
	assert_int(world.original.bubbles.active_count()).is_equal(0)


func test_the_clock_drives_the_bubbles() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.original.bubbles.rules = world.original.bubbles.rules.duplicate()
	world.original.bubbles.rules.spawn_chance = 1
	world.load_sector(DevCreatures.ARENA, 4)
	GameClock.step()
	assert_int(world.original.bubbles.active_count()).is_equal(world.original.bubbles.rules.slot_count())


# --- draw order -----------------------------------------------------------------------------------------------------

func test_the_bubbles_are_drawn_last_over_everything() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var last := world.original.get_child(world.original.get_child_count() - 1)
	assert_object(last).is_same(world.original.bubbles)
	for layer: Node in [world.original.sub, world.original.foes_layer, world.original.pellets, world.original.front_decos, world.original.anim_decos]:
		assert_bool(world.original.bubbles.get_index() > layer.get_index()).is_true()


# --- nothing depends on the sub or the air ----------------------------------------------------------------------------

func test_the_air_and_a_hit_change_nothing() -> void:
	var calm := _make(31)
	var stressed := _make(31)
	var calm_trace: Array[String] = []
	var stressed_trace: Array[String] = []
	for tick in 200:
		if tick == 50:
			GameState.update_oxygen(-2)                  # low air
		calm.step()
		stressed.step()
		calm_trace.append(_snapshot(calm))
		stressed_trace.append(_snapshot(stressed))
	assert_array(stressed_trace).is_equal(calm_trace)


# --- what DrawSub puts on the sub (the blue blobs of the screenshots) ----------------------------------------------

func test_the_light_is_drawn_at_the_cell_s_spot_and_only_from_the_side() -> void:
	var tuning := Tuning.resolve().sub
	assert_int(tuning.light_cells.size()).is_greater(0)
	var side_cell := tuning.light_cells[0]
	var other_side_cell := tuning.light_cells[tuning.light_cells.size() - 1]
	var front_cell := -1                                       # a cell the light is not drawn in
	for cell in tuning.light_dx_by_cell.size():
		if not tuning.light_cells.has(cell):
			front_cell = cell
			break
	assert_int(front_cell).is_greater(-1)
	var sub := auto_free(load("res://src/gameplay/sub.tscn").instantiate()) as Sub
	add_child(sub)
	sub.model.message_light = true
	sub.model.cell = side_cell
	sub.model.propeller_phase = 1
	sub.refresh()
	assert_bool(sub.light.visible).is_true()
	# The light's top-left corner is the table's spot from the sub picture's top-left corner, per cell.
	assert_vector(sub.light.position + Sub.PICTURE_CENTER).is_equal(Vector2(tuning.light_dx_by_cell[side_cell], tuning.light_dy_by_cell[side_cell]))
	sub.model.cell = other_side_cell
	sub.refresh()
	assert_vector(sub.light.position + Sub.PICTURE_CENTER).is_equal(Vector2(tuning.light_dx_by_cell[other_side_cell], tuning.light_dy_by_cell[other_side_cell]))
	sub.model.cell = front_cell                               # seen from the front: no light
	sub.refresh()
	assert_bool(sub.light.visible).is_false()
	sub.model.cell = side_cell
	sub.model.propeller_phase = 0                             # the blink: off on every other tick
	sub.refresh()
	assert_bool(sub.light.visible).is_false()


## "x,y,frame" of every bubble, "-" for an idle one: a one-line picture of the state to compare runs.
func _snapshot(node: Bubbles) -> String:
	var parts: Array[String] = []
	for slot in _rules.slot_count():
		var bubble := node.bubble(slot)
		parts.append("%d,%d,%d" % [bubble.window_pos.x, bubble.window_pos.y, bubble.frame] if bubble.active else "-")
	return "|".join(parts)
