class_name TestSkinCreaturesLegacy
extends GdUnitTestSuite
## Teaches: a skin written for the ORIGINAL's pictures. The 3D puffer fish of the "creatures" skin is drawn in a rectangle of the size of the
## original's puffer pictures (`PufferRig3D.PICTURE_SIZE`: a hard-coded assumption of the skin), so its footprint is only the picture's
## rectangle on the legacy pack (sector 0: a puffer fish on screens 0, 6 and 9, a rainbow fish on screens 3 and 5). The rest of the skin's tests
## are `engine/test_skin_creatures.gd`, on the dev pack's fish sector.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const ID := &"creatures"


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


## A world in sector 0 wearing the skin, as if the game had been started with `--skin=creatures`.
func _world(screen: int = 0) -> SectorWorld:
	SkinChoice.select_id(ID)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, screen)
	world.presenter.show_between_ticks(1.0)
	return world


func _presenter(world: SectorWorld) -> CreaturesPresenter:
	return world.presenter as CreaturesPresenter


func test_every_rig_is_drawn_inside_the_original_pictures_rectangle_which_holds_the_hit_rectangle() -> void:
	var world := _world(0)
	var presenter := _presenter(world)
	for t in 40:
		world.tick()
		presenter.show_between_ticks(1.0)                                   # (a tick has just ended: the creature is where the rules say)
		var view := SimView.new(world.sim)
		for creature in view.creatures():
			var rig := presenter.rig_for(creature.index)
			if rig == null or not rig.visible or not rig.is_drawing():
				continue
			var picture := Rect2(creature.motion.current, rig.picture_size(creature.picture))
			assert_vector(rig.drawn_rect().position).override_failure_message("creature %d at tick %d" % [creature.index, t]).is_equal_approx(picture.position, Vector2(0.01, 0.01))
			assert_vector(rig.drawn_rect().size).is_equal_approx(picture.size, Vector2(0.01, 0.01))
			if creature.hit_rect.has_area():
				assert_bool(picture.encloses(Rect2(creature.hit_rect))).override_failure_message(
						"creature %d, tick %d: the hit rectangle %s is not inside the picture %s" % [creature.index, t, creature.hit_rect, picture]).is_true()
		view.close()
