class_name TestClosingStages
extends GdUnitTestSuite
## Teaches: the closings are scenes whose nodes a stage file owns. The new kinds of actor (a picture set the view holds, a chain that one number lowers, a fill, a group that clips) are tried on a small stage of a scratch
## pack; the Expert and Voyager closings are then built from the dev pack's stages and held to them (`StageNodes`), and what is told when a pack's stage lacks an actor a closing's timeline names, or names a picture set the
## closing does not hand in, is pinned (`PackCheck`, `StageBuilder`, `StageChain`), each once and with the pack.

const PROBE := &"probe_stage"

var _shelf: PackShelf


func before_test() -> void:
	Audio.stop_music()


func after_test() -> void:
	Audio.stop_music()
	Audio.stop_voice()
	if _shelf != null:
		_shelf.remove()
		_shelf = null
	Packs.start()
	TroubleLog.new_run()


func _actor(actor_name: StringName, kind: StringName, at: Vector2, parent: StringName = &"") -> StageActor:
	var actor := StageActor.new()
	actor.name = actor_name
	actor.kind = kind
	actor.position = at
	actor.parent = parent
	return actor


## A stage of a box that clips, a fill, a picture set of the sub, and a chain of a hook and two links standing as for an extent of 0.
func _probe() -> CutsceneStage:
	var box := _actor(&"box", StageActor.GROUP, Vector2(16, 32))
	box.size = Vector2(200, 100)
	var water := _actor(&"water", StageActor.FILL, Vector2(16, 32), &"box")
	water.size = Vector2(200, 100)
	water.color = Color(0, 0, 0.5)
	var sub := _actor(&"sub", StageActor.FRAMES, Vector2(40, 60), &"box")
	sub.frames = &"sub"
	var chain := _actor(&"rope", StageActor.CHAIN, Vector2(16, 40), &"box")
	chain.size = Vector2(200, 92)
	chain.pictures = [&"crane_hook_0", &"crane_hook_1", &"crane_hook_2"]
	var hook := _actor(&"rope_hook", StageActor.PICTURE, Vector2(100, -20), &"rope")
	var link_one := _actor(&"rope_link_1", StageActor.PICTURE, Vector2(108, -32), &"rope")
	link_one.picture = &"crane_link"
	var link_two := _actor(&"rope_link_2", StageActor.PICTURE, Vector2(108, -44), &"rope")
	link_two.picture = &"crane_link"
	var stage := CutsceneStage.new()
	stage.actors = [box, water, sub, chain, hook, link_one, link_two]
	return stage


func _with_stage(stage: CutsceneStage) -> void:
	_shelf = PackShelf.new()
	_shelf.write_json("data/story/%s.json" % PROBE, ResourceJson.new().data_of(stage))
	_shelf.mount()


func _build(stage: CutsceneStage, sets: Dictionary[StringName, SpriteFrames] = {&"sub": Catalog.sub_frames()}) -> Array:
	_with_stage(stage)
	var container: Node2D = auto_free(Node2D.new())
	add_child(container)
	var cast := CutsceneCast.new(container)
	cast.frame_sets = sets
	StageBuilder.build(PROBE, container, cast)
	return [container, cast]


func test_the_builder_makes_a_clipping_box_a_fill_a_picture_set_and_a_chain() -> void:
	var made := _build(_probe())
	var container: Node2D = made[0]
	var cast: CutsceneCast = made[1]
	assert_array(StageNodes.differences(_probe(), container)).is_empty()
	var box := cast.node_of(&"box") as Control
	assert_bool(box.clip_contents).is_true()
	assert_vector(box.size).is_equal(Vector2(200, 100))
	assert_vector((cast.node_of(&"water") as ColorRect).get_global_rect().position).is_equal(Vector2(16, 32))
	var sub := cast.node_of(&"sub") as AnimatedSprite2D
	assert_object(sub.sprite_frames).is_same(Catalog.sub_frames())
	assert_str(String(sub.animation)).is_equal("all")
	assert_bool(sub.is_playing()).is_false()
	assert_vector(sub.global_position).is_equal(Vector2(40, 60))
	assert_array(TroubleLog.session.told).is_empty()


func test_a_chain_lowers_all_its_pieces_by_its_extent_and_its_hook_shows_the_picture_of_its_frame() -> void:
	var made := _build(_probe())
	var cast: CutsceneCast = made[1]
	var chain := cast.node_of(&"rope") as StageChain
	var hook := chain.get_child(0) as Sprite2D
	assert_str(PictureRef.key_of(hook.texture)).is_equal("ui_picture/crane_hook_0")
	assert_vector(hook.global_position).is_equal(Vector2(100, -20))
	chain.extent = 50
	assert_vector(hook.global_position).is_equal(Vector2(100, 30))
	assert_vector((chain.get_child(2) as Sprite2D).global_position).is_equal(Vector2(108, 6))
	chain.extent = 20                                                              # (lowered by the difference, not by the value)
	assert_vector(hook.global_position).is_equal(Vector2(100, 0))
	chain.frame = 2
	assert_str(PictureRef.key_of(hook.texture)).is_equal("ui_picture/crane_hook_2")
	assert_str(PictureRef.key_of((chain.get_child(1) as Sprite2D).texture)).is_equal("ui_picture/crane_link")          # (only the hook changes)
	# a timeline's tracks play it: `extent` and `frame` are the words of the data, no renaming
	var timeline := CutsceneTimeline.made_in_code(20.0, "test")
	timeline.track(&"rope", CutsceneTrack.PROP_EXTENT, [[0.0, 90], [10.0, 40]])
	timeline.track(&"rope", CutsceneTrack.PROP_FRAME, [[0.0, 1]])
	var player: AnimationPlayer = auto_free(AnimationPlayer.new())
	(made[0] as Node).add_child(player)
	Cutscene.install_timeline(player, &"drop", timeline, cast)
	player.play(&"drop")
	player.seek(TickMeter.seconds(10) + 0.001, true)
	assert_int(chain.extent).is_equal(40)
	assert_int(chain.frame).is_equal(1)
	assert_str(PictureRef.key_of(hook.texture)).is_equal("ui_picture/crane_hook_1")


func test_a_hook_frame_the_stage_gives_no_picture_for_is_told_once_with_the_pack_and_the_hook_keeps_its_picture() -> void:
	var made := _build(_probe())
	var chain := (made[1] as CutsceneCast).node_of(&"rope") as StageChain
	chain.frame = 1
	TroubleLog.new_run()
	chain.frame = 7
	chain.frame = 7
	assert_int(chain.frame).is_equal(1)
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("[story]").contains("the chain 'rope' of the stage '%s' of pack '%s'" % [PROBE, _shelf.id]).contains("picture 7").contains("the stage gives it 3").contains("the hook keeps its picture")


func test_each_new_kind_has_its_own_mistakes_in_one_sentence() -> void:
	var no_set := _actor(&"no_set", StageActor.FRAMES, Vector2.ZERO)
	var unknown_set := _actor(&"unknown_set", StageActor.FRAMES, Vector2.ZERO)
	unknown_set.frames = &"zone"
	var no_pictures := _actor(&"no_pictures", StageActor.CHAIN, Vector2.ZERO)
	var no_size := _actor(&"no_size", StageActor.FILL, Vector2.ZERO)
	var stage := CutsceneStage.new()
	stage.actors = [no_set, unknown_set, no_pictures, no_size]
	assert_array(stage.problems([&"sub"])).is_equal(["actor 'no_set': a frames actor needs the name of its picture set",
			"actor 'unknown_set': the picture set 'zone' is not one this scene hands in (sub)", "actor 'no_pictures': a chain needs the pictures its hook shows", "actor 'no_size': a fill needs a size"])
	assert_array(_probe().problems([&"sub"])).is_empty()
	assert_array(_probe().problems()).has_size(1)                                    # (a scene that hands in no set cannot show the sub)
	assert_str(_probe().problems()[0]).contains("'sub'").contains("it hands in none")


func test_a_picture_set_the_scene_does_not_hand_in_leaves_its_actor_out_and_is_told_once_with_the_pack() -> void:
	TroubleLog.new_run()
	var made := _build(_probe(), {})
	assert_bool((made[1] as CutsceneCast).has_actor(&"sub")).is_false()
	assert_bool((made[1] as CutsceneCast).has_actor(&"rope")).is_true()
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("[story]").contains("pack '%s'" % _shelf.id).contains("the picture set 'sub' is not one this scene hands in").contains("left out of the scene")


# --- the closings on the dev pack's stages -------------------------------------------------------------------------

func test_the_expert_closing_is_built_from_the_stage_and_plays_its_three_animations_in_turn() -> void:
	TroubleLog.new_run()
	var closing: ExpertClosing = auto_free(load("res://src/story/expert_closing.tscn").instantiate())
	add_child(closing)
	assert_array(StageNodes.differences(Catalog.story_stage(ExpertClosing.STAGE), closing.stage_root)).is_empty()
	assert_array(TroubleLog.session.told).is_empty()
	assert_array(closing.cast.frame_sets.keys()).is_equal(Array(ExpertClosing.FRAME_SETS))
	assert_bool((closing.cast.node_of(&"deck") as CanvasItem).visible).is_false()
	assert_bool((closing.cast.node_of(&"playfield") as CanvasItem).visible).is_true()
	for animation_name in ExpertClosing.TIMELINES:
		assert_bool(closing.animations.has_animation(animation_name)).is_true()
	closing.animations.advance(closing.animations.get_animation(&"hoist").length + 0.01)
	assert_int(closing.stage).is_equal(ExpertClosing.Stage.DECK)
	assert_bool((closing.cast.node_of(&"deck") as CanvasItem).visible).is_true()
	assert_bool((closing.cast.node_of(&"playfield") as CanvasItem).visible).is_false()
	closing.animations.advance(closing.animations.get_animation(&"deck").length + 0.01)
	assert_int(closing.stage).is_equal(ExpertClosing.Stage.WAIT)
	var count := [0]
	closing.finished.connect(func() -> void: count[0] += 1)
	closing.advance()
	closing.advance()
	assert_int(count[0]).is_equal(1)


func test_the_voyager_closing_is_built_from_the_stage_and_its_flight_is_made_for_the_place_of_the_sub() -> void:
	TroubleLog.new_run()
	var closing: VoyagerClosing = auto_free(load("res://src/story/voyager_closing.tscn").instantiate())
	add_child(closing)
	closing.start(184, 212, 6)
	assert_array(StageNodes.differences(Catalog.story_stage(VoyagerClosing.STAGE), closing.stage_root)).is_empty()
	assert_array(TroubleLog.session.told).is_empty()
	assert_array(closing.cast.frame_sets.keys()).is_equal(Array(VoyagerClosing.FRAME_SETS))
	var animation := closing.animations.get_animation(&"closing")
	closing.animations.seek(animation.length - 0.05, true)
	assert_bool((closing.cast.node_of(&"helicopter") as CanvasItem).visible).is_true()
	assert_bool((closing.cast.node_of(&"sub") as CanvasItem).visible).is_false()
	closing.skip()


func test_the_closings_need_their_stages_and_the_dev_pack_checks_clean() -> void:
	assert_str(PackNeeds.FILES["data/story/expert_closing_stage.tres"]).is_equal("CutsceneStage")
	assert_str(PackNeeds.FILES["data/story/voyager_closing_stage.tres"]).is_equal("CutsceneStage")
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Packs.dev(), options)
	assert_array(report.findings.filter(func(finding: PackReport.Finding) -> bool: return finding.area == "story")).is_empty()


# --- what the check of a pack says ---------------------------------------------------------------------------------

func _story_lines_of_a_pack_with(stage_name: StringName, stage: CutsceneStage) -> Array:
	_shelf = PackShelf.new()
	_shelf.write_json("data/story/%s.json" % stage_name, ResourceJson.new().data_of(stage))
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(_shelf.root), options)
	return report.findings.filter(func(finding: PackReport.Finding) -> bool: return finding.area == "story").map(func(finding: PackReport.Finding) -> String: return finding.message)


func _without(stage_name: StringName, actor_name: StringName) -> CutsceneStage:
	var stage := Catalog.story_stage(stage_name).duplicate(true) as CutsceneStage
	var kept: Array[StageActor] = []
	for actor in stage.actors:
		if actor.name != actor_name:
			kept.append(actor)
	stage.actors = kept
	return stage


func test_the_check_tells_an_actor_a_timeline_of_the_expert_closing_names_that_its_stage_lacks() -> void:
	var lines := _story_lines_of_a_pack_with(ExpertClosing.STAGE, _without(ExpertClosing.STAGE, &"pod"))
	assert_array(lines).is_equal(["timeline 'expert_deck' names the actor 'pod', which stage 'expert_closing_stage' does not hold: nothing moves or changes for it",
			"timeline 'expert_wait' names the actor 'pod', which stage 'expert_closing_stage' does not hold: nothing moves or changes for it"])


func test_the_check_tells_an_actor_the_flight_of_the_voyager_closing_names_that_its_stage_lacks() -> void:
	var lines := _story_lines_of_a_pack_with(VoyagerClosing.STAGE, _without(VoyagerClosing.STAGE, &"rotor"))
	assert_array(lines).is_equal(["timeline 'voyager_closing_script' names the actor 'rotor', which stage 'voyager_closing_stage' does not hold: nothing moves or changes for it"])


func test_the_check_tells_a_picture_set_the_closing_does_not_hand_in() -> void:
	var stage := Catalog.story_stage(ExpertClosing.STAGE).duplicate(true) as CutsceneStage
	(stage.find(&"artifact") as StageActor).frames = &"zone"
	var lines := _story_lines_of_a_pack_with(ExpertClosing.STAGE, stage)
	assert_array(lines).is_equal(["stage 'expert_closing_stage': actor 'artifact': the picture set 'zone' is not one this scene hands in (sub, artifact)"])
