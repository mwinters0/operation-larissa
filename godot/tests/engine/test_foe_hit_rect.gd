class_name TestFoeHitRect
extends GdUnitTestSuite
## Teaches: a rectangle that changes at runtime. A creature's hit rectangle is a property of its CURRENT picture and mirroring
## (SpriteMetaTable), not of the node; the node only moves it to the playfield for the debug view.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"

var _world: SectorWorld


func before_test() -> void:
	GameClock.paused = true
	_world = scene_runner(WORLD_SCENE).scene() as SectorWorld
	_world.load_sector(DevCreatures.ARENA, DevCreatures.MIRROR_SCREEN)            # the mirror: shown mirrored, picture ray_swim_0


func after_test() -> void:
	GameClock.paused = false
	SpriteMeta.forget()                 # (a test below changes an entry of the table)


func test_hit_rect_is_the_table_entry_moved_to_the_creature() -> void:
	var foe := _world.original.foes[DevCreatures.MIRROR]
	var meta := SpriteMeta.for_zone(0)
	assert_bool(foe.vm.flip).is_true()
	var expected := Rect2(meta.hit_rect(foe.vm.frame, true))
	expected.position += foe.position
	assert_that(foe.hit_rect_world()).is_equal(expected)


func test_rect_follows_the_frame_and_the_flip() -> void:
	var foe := _world.original.foes[DevCreatures.MIRROR]
	var meta := SpriteMeta.for_zone(0)
	# Give an ink picture different rectangles for the plain and the mirrored picture (the table the creature reads is this one).
	var ink := NameRegistry.original().index_of(&"frame", "ink_burst_3", 0)
	meta.hit_rects[ink] = Rect2i(2, 3, 10, 8)
	meta.hit_rects_flipped[ink] = Rect2i(6, 1, 12, 14)
	foe.vm.frame = ink
	foe.vm.flip = false
	foe.refresh(true)
	var plain := foe.hit_rect_world()
	var plain_rect := meta.hit_rect(ink, false)
	assert_that(plain).is_equal(Rect2(Vector2(plain_rect.position) + foe.position, Vector2(plain_rect.size)))
	foe.vm.flip = true
	foe.refresh(true)
	var mirrored := foe.hit_rect_world()
	assert_that(mirrored.size).is_not_equal(plain.size)
	assert_that(mirrored.position).is_equal(Vector2(meta.hit_rect(ink, true).position) + foe.position)
	# Another picture: another size.
	var other := NameRegistry.original().index_of(&"frame", "ray_swim_0", 0)
	foe.vm.frame = other
	foe.refresh(true)
	assert_that(foe.hit_rect_world().size).is_equal(Vector2(meta.hit_rect(other, true).size))


func test_hidden_creatures_and_other_screens_cannot_be_touched() -> void:
	var foe := _world.original.foes[DevCreatures.MIRROR]
	assert_bool(foe.model.is_touchable()).is_true()
	foe.vm.hidden = true
	foe.refresh(true)
	assert_bool(foe.model.is_touchable()).is_false()
	assert_bool(foe.visible).is_false()
	_world.load_screen(DevCreatures.MIRROR_SCREEN + 1)
	assert_bool(foe.model.is_touchable()).is_false()              # the mirror's screen is not the one shown
