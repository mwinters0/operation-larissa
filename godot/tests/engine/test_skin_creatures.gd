class_name TestSkinCreatures
extends GdUnitTestSuite
## Teaches: checking a skin that is made of code (the "creatures" skin: `skins/creatures/`). Four things are looked at.
##   * It is a skin like any other: found by `SkinChoice.available()`, its own presenter scene is the one a world builds.
##   * It is written against the skin API: a scan of its source (comments and strings do not count) for the rules' words, and one run
##     with a world to see its rigs hear the events of the rules.
##   * The two rigs do what they say: the `AnimationTree` of the rainbow fish goes to its states for the events and gets the speed as a
##     parameter; the puffer fish's `SubViewport` is transparent, has a world of its own, and the footprint is the picture's rectangle (the one the hit rectangle lies in).
##   * It changes nothing: the scripted visit of `SectorScenario` gives the trace of plain objects with this skin, and when the skin is
##     switched on and off in the middle of the visit (`test_skins_dont_change_the_game.gd` compares every skin).

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
const FOLDER := "res://skins/creatures"
const ID := &"creatures"
## What a skin's own scripts must never name: the rules (`sim` is the base class's handle on them, which the skin's code never uses),
## the rule objects behind the copies of the API, the clock and the keyboard.
const FORBIDDEN: Array[String] = [
	"sim", "SimWorld\\.tick", "FoeModel", "FoeVM", "SubModel", "PelletModel", "PieceModel", "TriggerModel", "StationSequence",
	"GameClock", "GameState", "Input", "InputReader",
]
## The dev fish sector (`DevCreatures.FISH`, zone 0): a puffer fish on screens 0, 6 and 9, a rainbow fish on screens 3 and 5. The skin names the original's
## fish by their registry picture names (`CreatureSpecies`), and dev's pictures have the same names: a hard-coded assumption of the skin.
const SECTOR := DevCreatures.FISH
const PUFFERS: Array[int] = DevCreatures.PUFFERS
const RAINBOW_FISH: Array[int] = DevCreatures.RAINBOW_FISH


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


## A world in the fish sector wearing the skin, as if the game had been started with `--skin=creatures`.
func _world(screen: int = 0) -> SectorWorld:
	SkinChoice.select_id(ID)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(SECTOR, screen)
	world.presenter.show_between_ticks(1.0)
	return world


func _presenter(world: SectorWorld) -> CreaturesPresenter:
	return world.presenter as CreaturesPresenter


# --- a skin like any other ---------------------------------------------------------------------------------

func test_the_skin_ships_and_is_found() -> void:
	assert_array(SkinChoice.available()).contains([&"original", ID])
	var skin := SkinChoice.load_skin(ID)
	assert_str(String(skin.id)).is_equal("creatures")
	assert_object(skin.presenter_scene_or_null()).is_not_null()
	assert_str(skin.presenter_scene.resource_path).is_equal(FOLDER + "/creatures_presenter.tscn")
	assert_bool(skin.has_pictures()).is_false()            # (it maps no picture: the original's pictures, the rigs are the difference)


func test_a_world_with_the_skin_has_its_presenter_and_it_can_be_switched_at_run_time() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(SECTOR, 0)
	assert_bool(world.presenter is CreaturesPresenter).is_false()
	SkinChoice.select_id(ID)
	assert_object(world.presenter).is_instanceof(CreaturesPresenter)
	assert_object(world.original).is_instanceof(OriginalPresenter)          # (it is the original with something added)
	assert_int(_presenter(world).rig_count()).is_equal(PUFFERS.size() + RAINBOW_FISH.size())          # (also the creatures of the other screens)
	SkinChoice.select(SkinChoice.original())
	assert_bool(world.presenter is CreaturesPresenter).is_false()


# --- written against the skin API --------------------------------------------------------------------------

func test_the_skins_code_never_names_the_rules() -> void:
	var files := SourceScan.scripts_under(FOLDER)
	assert_int(files.size()).is_greater(5)
	var found := SourceScan.find_in(files, FORBIDDEN)
	assert_array(found).override_failure_message("the skin reaches round the skin API:\n" + "\n".join(found)).is_empty()
	# (the scan sees what it should: the original presenter, which is allowed to, names `sim`)
	assert_array(SourceScan.find("res://src/gameplay/original_presenter.gd", ["sim"])).is_not_empty()


func test_the_rigs_hear_the_events_of_the_rules() -> void:
	var world := _world(3)
	var presenter := _presenter(world)
	assert_int(presenter.rig_count()).is_equal(PUFFERS.size() + RAINBOW_FISH.size())
	for index in RAINBOW_FISH:
		assert_object(presenter.rig_for(index)).is_instanceof(RainbowFishRig)
	for index in PUFFERS:
		assert_object(presenter.rig_for(index)).is_instanceof(PufferRig3D)
	assert_object(presenter.rig_for(DevCreatures.CLAM)).is_null()            # (the clam is the original's)
	# the original's pictures of the replaced creatures are hidden, the clam's is not
	assert_bool(world.original.foes[RAINBOW_FISH[0]].sprite.visible).is_false()
	assert_bool(world.original.foes[PUFFERS[0]].sprite.visible).is_false()
	assert_bool(world.original.foes[DevCreatures.CLAM].sprite.visible).is_true()
	# the fish on the shown screen is drawn, those on other screens are not
	assert_bool(presenter.rig_for(RAINBOW_FISH[0]).visible).is_true()
	assert_bool(presenter.rig_for(RAINBOW_FISH[1]).visible).is_false()


# --- the rainbow fish and its AnimationTree -----------------------------------------------------------------

func test_the_fish_is_driven_by_an_animation_tree() -> void:
	var rig := _presenter(_world(3)).rig_for(RAINBOW_FISH[0]) as RainbowFishRig
	var tree := rig.get_node("Tree") as AnimationTree
	assert_object(tree).is_not_null()
	assert_bool(tree.active).is_true()
	var machine := tree.tree_root as AnimationNodeStateMachine
	for state in [&"swim", &"chomp", &"turn", &"inked"]:
		assert_bool(machine.has_node(state)).override_failure_message("no state %s" % state).is_true()
	assert_object(machine.get_node(&"swim")).is_instanceof(AnimationNodeBlendSpace1D)
	var player := rig.get_node("Player") as AnimationPlayer
	for animation in [&"hover", &"cruise", &"chomp", &"turn", &"inked"]:
		assert_bool(player.has_animation(animation)).override_failure_message("no animation %s" % animation).is_true()
	await await_millis(100)
	assert_str(String(rig.current_state())).is_equal("swim")


func test_the_tree_goes_to_its_states_for_the_events_and_back() -> void:
	var rig := _presenter(_world(3)).rig_for(RAINBOW_FISH[0]) as RainbowFishRig
	await await_millis(100)
	rig.show_mirror(not rig.mirrored)                                          # it turned round
	await await_millis(100)
	assert_str(String(rig.current_state())).is_equal("turn")
	await await_millis(900)                                                     # (the turn is 0.4 s and ends by itself, back to swim)
	assert_str(String(rig.current_state())).is_equal("swim")
	rig.hit_by_ink()
	await await_millis(100)
	assert_str(String(rig.current_state())).is_equal("inked")
	rig.show_picture(CreatureSpecies.slot_of(0, "rainbow_fish_swim_0"))        # a fish again
	await await_millis(300)
	assert_str(String(rig.current_state())).is_equal("swim")
	rig.show_picture(CreatureSpecies.slot_of(0, "rainbow_fish_spit_0"))        # the mouth opens
	await await_millis(100)
	assert_str(String(rig.current_state())).is_equal("chomp")


func test_the_speed_of_the_creature_is_the_trees_blend_position() -> void:
	var world := _world(3)
	var rig := _presenter(world).rig_for(RAINBOW_FISH[0]) as RainbowFishRig
	var state := SimView.CreatureState.new()
	state.index = RAINBOW_FISH[0]
	state.picture = rig.picture
	state.shown = true
	state.motion = SimView.Motion.new(Vector2(100, 100), Vector2(104, 100))        # 4 px in a tick: a swimming fish
	rig.follow(state)
	await await_millis(500)
	assert_float(rig.blend_position()).is_equal_approx(1.0, 0.01)
	state.motion = SimView.Motion.new(Vector2(104, 100), Vector2(104, 100))        # still: hovering
	rig.follow(state)
	await await_millis(500)
	assert_float(rig.blend_position()).is_equal_approx(0.0, 0.01)


# --- the puffer fish and its SubViewport ----------------------------------------------------------------------

func test_the_puffer_fish_is_a_3d_model_in_a_transparent_viewport_of_its_own() -> void:
	var rig := _presenter(_world(0)).rig_for(PUFFERS[0]) as PufferRig3D
	var viewport := rig.viewport()
	assert_bool(viewport.transparent_bg).is_true()
	assert_bool(viewport.own_world_3d).is_true()
	assert_vector(Vector2(viewport.size)).is_equal(Vector2(PufferRig3D.PICTURE_SIZE * PufferRig3D.RENDER_SCALE))
	assert_bool(SkinChoice.current().render_settings().is_applied_to(viewport)).is_true()      # (a SubViewport does not inherit the window's settings)
	assert_object(rig.picture_node().texture).is_instanceof(ViewportTexture)
	assert_vector(rig.picture_node().scale).is_equal(Vector2.ONE / PufferRig3D.RENDER_SCALE)
	var meshes := rig.model().find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_greater(30)                                    # body, tail, fins, eyes, dots, spines
	assert_bool(rig.model().find_children("*", "Camera3D", true, false).is_empty()).is_true()        # (the camera and the light are beside the model)
	var camera := viewport.find_children("*", "Camera3D", true, false)[0] as Camera3D
	assert_int(camera.projection).is_equal(Camera3D.PROJECTION_ORTHOGONAL)
	assert_float(camera.size).is_equal(48.0)


func test_the_model_follows_the_pictures_and_the_mirror_of_the_rules() -> void:
	var rig := _presenter(_world(0)).rig_for(PUFFERS[0]) as PufferRig3D
	assert_bool(rig.is_drawing()).is_true()
	assert_int(rig.viewport().render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)          # (on the shown screen: rendered)
	assert_float(rig.heading_target()).is_equal_approx(PufferRig3D.THREE_QUARTER, 0.001)
	rig.show_mirror(true)
	assert_float(rig.heading_target()).is_equal_approx(PI - PufferRig3D.THREE_QUARTER, 0.001)          # (it turns round to face the other way)
	rig.show_picture(CreatureSpecies.slot_of(0, "puffer_puffed_0"))
	assert_float(rig.inflate_target()).is_equal(1.0)
	rig.show_picture(CreatureSpecies.slot_of(0, "puffer_swell"))
	assert_float(rig.inflate_target()).is_equal(0.5)
	rig.show_picture(CreatureSpecies.slot_of(0, "puffer_swim_1"))
	assert_float(rig.inflate_target()).is_equal(0.0)


func test_a_puffer_hit_by_ink_is_left_to_the_original_cloud_and_not_rendered() -> void:
	var world := _world(0)
	var presenter := _presenter(world)
	var rig := presenter.rig_for(PUFFERS[0]) as PufferRig3D
	rig.show_picture(CreatureSpecies.slot_of(0, "ink_burst_5"))
	presenter.show_between_ticks(0.5)
	assert_bool(rig.is_drawing()).is_false()
	assert_bool(world.original.foes[PUFFERS[0]].sprite.visible).is_true()                  # (the original's cloud shows)
	assert_int(rig.viewport().render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)
	rig.show_picture(CreatureSpecies.slot_of(0, "puffer_swim_0"))
	presenter.show_between_ticks(0.5)
	assert_bool(world.original.foes[PUFFERS[0]].sprite.visible).is_false()


func test_a_puffer_on_another_screen_is_not_rendered() -> void:
	var rig := _presenter(_world(0)).rig_for(PUFFERS[1]) as PufferRig3D            # (screen 6)
	assert_bool(rig.visible).is_false()
	assert_int(rig.viewport().render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)



# --- the footprint --------------------------------------------------------------------------------------------

func test_every_rig_is_drawn_at_the_creatures_place_and_the_rainbow_fish_inside_its_pictures_rectangle() -> void:
	# The 3D puffer has a picture size of its own (`PufferRig3D.PICTURE_SIZE`, the size of the original's puffer pictures: a hard-coded assumption
	# of the skin, so its size is looked at in `legacy/test_skin_creatures_legacy.gd`); here every rig is where the creature is, and the rainbow fish
	# is drawn in the very rectangle of the pack's picture, which holds the hit rectangle.
	var world := _world(3)
	var presenter := _presenter(world)
	var seen := 0
	for t in 40:
		world.tick()
		presenter.show_between_ticks(1.0)                                   # (a tick has just ended: the creature is where the rules say)
		var view := SimView.new(world.sim)
		for creature in view.creatures():
			var rig := presenter.rig_for(creature.index)
			if rig == null or not rig.visible or not rig.is_drawing():
				continue
			seen += 1
			assert_vector(rig.drawn_rect().position).override_failure_message("creature %d at tick %d" % [creature.index, t]).is_equal_approx(creature.motion.current, Vector2(0.01, 0.01))
			if rig is RainbowFishRig:
				var picture := Rect2(creature.motion.current, rig.picture_size(creature.picture))
				assert_vector(rig.drawn_rect().size).is_equal_approx(picture.size, Vector2(0.01, 0.01))
				if creature.hit_rect.has_area():
					assert_bool(picture.encloses(Rect2(creature.hit_rect))).override_failure_message(
							"creature %d, tick %d: the hit rectangle %s is not inside the picture %s" % [creature.index, t, creature.hit_rect, picture]).is_true()
		view.close()
	assert_int(seen).is_greater(0)


# --- it changes nothing ---------------------------------------------------------------------------------------

## The trace of `SectorScenario` on `sector`: with plain objects (`&"none"`), or in a world wearing the creatures skin.
func _play(sector: int, shell: StringName) -> SectorScenario:
	GameState.reset()
	if shell == &"none":
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		run.reset()
		var scenario := SectorScenario.new(HeadlessStage.new(run), run)
		scenario.play(sector)
		return scenario
	SkinChoice.select_id(ID)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_object(world.presenter).is_instanceof(CreaturesPresenter)
	var fraction := [0.0]
	world.sim.ticked.connect(func() -> void:                                 # (the picture is asked to follow after every tick, as the frames of the game do)
		fraction[0] = fmod(fraction[0] + 0.37, 1.0)
		world.presenter.show_between_ticks(fraction[0]))
	var scenario := SectorScenario.new(world, GameState)
	scenario.play(sector)
	return scenario


func test_a_scripted_visit_gives_the_trace_of_plain_objects() -> void:
	for sector in [SECTOR, DevCreatures.ARENA]:
		var plain := _play(sector, &"none")
		var skinned := _play(sector, ID)
		assert_int(plain.trace.lines.size()).is_greater(100)
		assert_int(skinned.trace.lines.size()).override_failure_message("sector %d: another number of lines" % sector).is_equal(plain.trace.lines.size())
		for i in plain.trace.lines.size():
			if skinned.trace.lines[i] != plain.trace.lines[i]:
				fail("sector %d: the rules differ at line %d\n  plain: %s\n  skin:  %s" % [sector, i, plain.trace.lines[i], skinned.trace.lines[i]])
				break


func test_switching_to_the_skin_and_back_in_the_middle_of_a_visit_changes_nothing() -> void:
	var plain := _play(SECTOR, &"none")
	GameState.reset()
	SkinChoice.select(SkinChoice.original())
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var count := [0]
	var with_rigs := [0]
	var scenario := SectorScenario.new(world, GameState)
	scenario.after_tick = func() -> void:
		count[0] += 1
		if count[0] % 20 == 0:                                                # (the skin on, off, on, ... every 20 ticks of the flight)
			SkinChoice.select_id(ID if (count[0] / 20) % 2 == 1 else SkinChoice.ORIGINAL)
		if world.presenter is CreaturesPresenter and (world.presenter as CreaturesPresenter).rig_count() > 0:
			with_rigs[0] += 1
		world.presenter.show_between_ticks(0.5)
	scenario.play(SECTOR)
	assert_int(count[0]).is_equal(SectorScenario.FLY_TICKS)
	assert_int(with_rigs[0]).is_greater(20)                                    # (the rigs were there for part of the flight)
	assert_array(scenario.trace.lines).is_equal(plain.trace.lines)
