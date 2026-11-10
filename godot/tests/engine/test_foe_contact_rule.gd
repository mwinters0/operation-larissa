class_name TestFoeContactRule
extends GdUnitTestSuite
## Teaches: checking a game rule against its definition. The rule (DESIGN 3.5): once per tick, rectangles in WINDOW pixels, edges
## included, and only the first contact of a stay costs air. The creature under test is the dev arena's post (`DevCreatures.POST`: it never
## moves, so its hit rectangle is a fixed box) and the sub is put at pixels computed from that box, one pixel in and one pixel out, on every side.
## Two creatures of the arena show how the picture follows: the hopper (a jellyfish's loose tentacle tip) hops and never glides, the glider glides
## from its first step. What the ORIGINAL sector 0 draws where is `legacy/test_creatures_legacy.gd`.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

## The cell (picture) the sub is shown in: 6, facing right; its hurt rectangle is `sub.tuning.frame_rects[CELL]` from the picture's corner.
const CELL := 6
## Where the sub waits while a test looks at the creatures.
const AWAY := Vector2i(60, 250)

var _world: SectorWorld


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.load_sector(DevCreatures.ARENA, 0)
	_world.start_flight(AWAY.x, AWAY.y, CELL)


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


## The post: the box the contacts are measured against (the swimmer and the chomper of its screen are far from where the sub is put).
func _post() -> Foe:
	return _world.original.foes[DevCreatures.POST]


# --- the picture follows the rules ------------------------------------------------------------

func test_a_creature_is_drawn_at_its_place_and_its_rectangle_is_the_tables_entry_moved_there() -> void:
	var post := _world.original.foes[DevCreatures.POST]
	var window := Vector2i(post.vm.x, post.vm.y)
	assert_that(post.position).is_equal(Vector2(window) - Sub.PLAYFIELD_ORIGIN)
	var table_rect := SpriteMeta.for_zone(0).hit_rect(post.vm.frame, post.vm.flip)
	assert_that(post.model.hit_rect_window()).is_equal(Rect2i(window + table_rect.position, table_rect.size))


func test_the_hopping_tentacle_hops_with_the_bell_and_never_glides() -> void:
	# The hopper (picture jellyfish_tentacle) moves once with Move_Foe_Relative_XY, waits two ticks, and one of its four hops is just 8 px, short
	# enough that a distance rule alone let TickSmoothing slide it into place (Foe.HOPPING_PICTURES).
	_world.load_screen(DevCreatures.BELL_SCREEN)
	var hopper := _world.original.foes[DevCreatures.HOPPER]
	var hops := 0
	var shortest := 1000.0
	for tick in 60:
		var before := hopper.position
		_world.tick()
		assert_bool(hopper.is_gliding()).override_failure_message("the hopper glides on tick %d" % tick).is_false()
		if hopper.position != before:
			hops += 1
			shortest = minf(shortest, hopper.position.distance_to(before))
	assert_int(hops).is_greater(4)
	assert_float(shortest).is_less(Foe.JUMP_LIMIT)           # (a hop the distance rule alone would have drawn gliding)


func test_other_creatures_glide_from_their_first_step() -> void:
	# The glider stands still for two ticks and then swims in short MOVE_REL steps: every step is drawn gliding, the first one after standing
	# still included (snapping that one made creatures that move and pause look jittery).
	_world.load_screen(DevCreatures.MIRROR_SCREEN)
	var glider := _world.original.foes[DevCreatures.GLIDER]
	var moves := 0
	var first_move := -1
	for tick in 20:
		var before := glider.position
		_world.tick()
		if glider.position != before:
			moves += 1
			if first_move < 0:
				first_move = tick
			assert_bool(glider.is_gliding()).override_failure_message("step on tick %d snapped" % tick).is_true()
	assert_int(moves).is_greater(10)
	assert_int(first_move).is_greater(0)                     # (it did stand still first)


# --- the edges of the rectangle -----------------------------------------------------------------

func test_touching_by_one_pixel_hurts_and_one_pixel_less_does_not() -> void:
	var rect := _post().model.hit_rect_window()
	var cell_rect := _world.sim.sub.tuning.frame_rects[CELL]
	var x := rect.position.x - cell_rect.position.x + 2
	# One pixel clear underneath: no damage.
	_place_sub(x, rect.end.y + 1 - cell_rect.position.y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_false()
	_world.check_contacts()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen)
	# The top row of the sub's rectangle is the creature's last row: they share one pixel row.
	_place_sub(x, rect.end.y - cell_rect.position.y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_true()
	_world.check_contacts()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 1)
	assert_bool(_world.sim.sub.is_invulnerable()).is_true()


func test_the_edges_count_on_every_side() -> void:
	var rect := _post().model.hit_rect_window()
	var cell_rect := _world.sim.sub.tuning.frame_rects[CELL]
	var mid_x := rect.position.x + 10 - cell_rect.position.x
	var mid_y := rect.position.y + 10 - cell_rect.position.y
	# Sub to the left of the creature: its right edge one pixel short, then exactly on the edge.
	_place_sub(rect.position.x - 1 - cell_rect.end.x, mid_y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_false()
	_place_sub(rect.position.x - cell_rect.end.x, mid_y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_true()
	# Sub to the right.
	_place_sub(rect.end.x + 1 - cell_rect.position.x, mid_y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_false()
	_place_sub(rect.end.x - cell_rect.position.x, mid_y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_true()
	# Above: the sub's bottom edge one pixel short, then exactly on the edge.
	_place_sub(mid_x, rect.position.y - 1 - cell_rect.end.y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_false()
	_place_sub(mid_x, rect.position.y - cell_rect.end.y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_true()
	# Below.
	_place_sub(mid_x, rect.end.y + 1 - cell_rect.position.y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_false()
	_place_sub(mid_x, rect.end.y - cell_rect.position.y)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_true()


func test_the_rectangle_is_exactly_the_tables_box_not_the_picture() -> void:
	# The picture is larger than the box the table gives (dev's boxes are the picture inset by a few pixels): a sub in the margin is not touching.
	var post := _post()
	var rect := post.model.hit_rect_window()
	var meta := SpriteMeta.for_zone(0)
	var picture_size := meta.sizes[post.vm.frame]
	assert_int(rect.size.x).is_less(picture_size.x)
	assert_int(rect.size.y).is_less(picture_size.y)
	var cell_rect := _world.sim.sub.tuning.frame_rects[CELL]
	_place_sub(post.vm.x - cell_rect.end.x, post.vm.y + 10 - cell_rect.position.y)          # (at the picture's own left edge: outside the box)
	assert_bool(FoeModel.rects_touch(_world.sim.sub.hurt_rect_window(), rect)).is_false()


# --- the "first contact only" rule --------------------------------------------------------------

func test_staying_inside_a_creature_costs_air_once() -> void:
	var rect := _post().model.hit_rect_window()
	var cell_rect := _world.sim.sub.tuning.frame_rects[CELL]
	var x := rect.position.x + 10 - cell_rect.position.x
	var y := rect.position.y + 10 - cell_rect.position.y
	_place_sub(x, y)
	_world.tick()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 1)
	for tick in 80:                                        # the immunity ends; still inside
		_place_sub(x, y, false)
		_world.tick()
	assert_bool(_world.sim.sub.is_invulnerable()).is_false()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 1)             # same creature as in the previous tick: no new damage
	# Swim out for one tick, and back in: it hurts again.
	_place_sub(AWAY.x, AWAY.y, false)
	_world.tick()
	_place_sub(x, y, false)
	_world.tick()
	assert_int(GameState.oxygen()).is_equal(GameState.tuning.max_oxygen - 2)


## Puts the sub's picture at window (x, y). `fresh`: also forget its velocity and immunity.
func _place_sub(x: int, y: int, fresh: bool = true) -> void:
	var invulnerability := _world.sim.sub.invulnerability
	_world.original.sub.place_original(x, y, CELL)
	if not fresh:
		_world.sim.sub.invulnerability = invulnerability
