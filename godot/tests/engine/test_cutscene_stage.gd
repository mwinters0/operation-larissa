class_name TestCutsceneStage
extends GdUnitTestSuite
## Teaches: a scene's furniture is data (`CutsceneStage`) and ONE builder (`StageBuilder`) turns it into nodes. The tests read a small stage a scratch pack holds (so the builder is tried on
## numbers the test owns, not on the opening's), then what is told when a pack's stage or timeline is wrong: a stage that cannot be built, an actor a timeline names that no stage holds
## (`Cutscene`, `PackCheck`), each once and naming what the player sees instead. The opening's own stages are checked against its nodes in `test_opening` and `test_opening_legacy`.

const PROBE := &"probe_stage"

var _shelf: PackShelf


func after_test() -> void:
	if _shelf != null:
		_shelf.remove()
		_shelf = null
	Packs.start()
	TroubleLog.new_run()


func _actor(actor_name: StringName, kind: StringName = StageActor.PICTURE, at := Vector2.ZERO, parent: StringName = &"") -> StageActor:
	var actor := StageActor.new()
	actor.name = actor_name
	actor.kind = kind
	actor.position = at
	actor.parent = parent
	if kind == StageActor.PICTURE:
		actor.picture = &"radar_map"
	return actor


## A pack holding `stage` as `data/story/probe_stage.json`, chosen.
func _with_stage(stage: CutsceneStage) -> void:
	_shelf = PackShelf.new()
	_shelf.write_json("data/story/%s.json" % PROBE, ResourceJson.new().data_of(stage))
	_shelf.mount()


func _probe() -> CutsceneStage:
	var stage := CutsceneStage.new()
	var group := _actor(&"boat", StageActor.GROUP, Vector2(100, 50))
	var hull := _actor(&"hull", StageActor.PICTURE, Vector2(100, 50), &"boat")
	var flag := _actor(&"flag", StageActor.PICTURE, Vector2(112, 40), &"boat")
	flag.mirror = true
	var sub := _actor(&"sub", StageActor.PICTURE, Vector2(300, 200))
	sub.visible = false
	sub.clip = Rect2(0, 0, 30, 20)
	var words := _actor(&"words", StageActor.TEXT, Vector2(10, 300))
	words.size = Vector2(250, 60)
	stage.actors = [group, hull, flag, sub, words]
	return stage


func test_a_well_formed_stage_has_no_problems_and_each_mistake_is_one_sentence() -> void:
	var stage := _probe()
	assert_array(stage.problems()).is_empty()
	var bad := CutsceneStage.new()
	var no_size := _actor(&"words", StageActor.TEXT)
	var odd := _actor(&"odd", &"video")
	bad.actors = [_actor(&""), _actor(&"a"), _actor(&"a"), _actor(&"late_child", StageActor.PICTURE, Vector2.ZERO, &"later"), _actor(&"later"), no_size, odd,
			_actor(&"under_text", StageActor.PICTURE, Vector2.ZERO, &"words")]
	var found := bad.problems()
	assert_array(found).has_size(6)
	for fragment in ["no name", "two actors are called 'a'", "its parent 'later' is not an actor listed before it", "a text box needs a size", "unknown kind 'video'",
			"its parent 'words' is not an actor listed before it"]:
		assert_bool(Array(found).any(func(line: String) -> bool: return line.contains(fragment))).override_failure_message("no problem about '%s': %s" % [fragment, found]).is_true()


func test_the_node_name_of_an_actor_is_its_words_in_capitals() -> void:
	assert_str(_actor(&"mini_sub").node_name()).is_equal("MiniSub")
	assert_str(_actor(&"dot_07").node_name()).is_equal("Dot07")
	assert_str(_actor(&"map").node_name()).is_equal("Map")


func test_the_builder_makes_the_nodes_of_the_stage_and_binds_the_cast() -> void:
	_with_stage(_probe())
	var container: Node2D = auto_free(Node2D.new())
	add_child(container)
	var cast := CutsceneCast.new(container)
	var stage := StageBuilder.build(PROBE, container, cast)
	assert_object(stage).is_not_null()
	assert_array(StageNodes.differences(stage, container)).is_empty()
	for actor_name in [&"boat", &"hull", &"flag", &"sub", &"words"]:
		assert_bool(cast.has_actor(actor_name)).override_failure_message(String(actor_name)).is_true()
	var flag := cast.node_of(&"flag") as Sprite2D
	assert_object(flag.get_parent()).is_same(cast.node_of(&"boat"))
	assert_vector(flag.position).override_failure_message("a child's place is its window position less its parent's").is_equal(Vector2(12, -10))
	assert_vector(flag.get_global_transform().origin).is_equal(Vector2(112, 40))
	assert_bool(flag.flip_h).is_true()
	assert_bool((cast.node_of(&"sub") as Sprite2D).visible).is_false()
	assert_vector((cast.node_of(&"sub") as Sprite2D).region_rect.size).is_equal(Vector2(30, 20))
	assert_vector((cast.node_of(&"words") as Label).size).is_equal(Vector2(250, 60))
	assert_array(container.get_children().map(func(node: Node) -> String: return node.name)).is_equal(["Boat", "Sub", "Words"])
	assert_array(TroubleLog.session.told).is_empty()


func test_a_stage_the_chain_lacks_builds_nothing_and_is_told_once() -> void:
	TroubleLog.new_run()
	var container: Node2D = auto_free(Node2D.new())
	add_child(container)
	for i in 3:
		assert_object(StageBuilder.build(&"no_such_stage", container, CutsceneCast.new(container))).is_null()
	assert_int(container.get_child_count()).is_equal(0)
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("[story]").contains("'no_such_stage'").contains("shows nothing")


func test_an_actor_that_cannot_be_made_is_left_out_and_told_once_with_the_pack() -> void:
	var stage := _probe()
	stage.actors.append(_actor(&"orphan", StageActor.PICTURE, Vector2(5, 5), &"nobody"))
	stage.actors.append(_actor(&"after", StageActor.PICTURE, Vector2(6, 6)))
	_with_stage(stage)
	TroubleLog.new_run()
	for i in 2:
		var container: Node2D = auto_free(Node2D.new())
		add_child(container)
		var cast := CutsceneCast.new(container)
		StageBuilder.build(PROBE, container, cast)
		assert_bool(cast.has_actor(&"orphan")).is_false()
		assert_bool(cast.has_actor(&"after")).is_true()
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("[story]").contains("pack '%s'" % _shelf.id).contains("its parent 'nobody' is not an actor listed before it").contains("left out of the scene")


func test_a_timeline_that_names_an_actor_the_stage_does_not_hold_is_told_once_and_the_rest_plays() -> void:
	var timeline := CutsceneTimeline.made_in_code(100.0, "test")
	timeline.track(&"ghost", CutsceneTrack.PROP_VISIBLE, [[0.0, true]])
	timeline.track(&"words", CutsceneTrack.PROP_TEXT, [[0.0, &""]])
	_with_stage(_probe())
	var container: Node2D = auto_free(Node2D.new())
	add_child(container)
	var cast := CutsceneCast.new(container)
	StageBuilder.build(PROBE, container, cast)
	TroubleLog.new_run()
	for i in 2:
		var animation := Cutscene.animation(timeline, cast)
		assert_int(animation.get_track_count()).is_equal(1)
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("[story]").contains("made in code").contains("'ghost'").contains("nothing moves or changes for it")


func test_the_check_of_a_pack_tells_an_actor_a_timeline_names_that_no_stage_holds() -> void:
	var title := Catalog.story_stage(TitleScene.STAGE).duplicate(true) as CutsceneStage
	var kept: Array[StageActor] = []
	for actor in title.actors:
		if actor.name != &"spray":
			kept.append(actor)
	title.actors = kept
	_shelf = PackShelf.new()
	_shelf.write_json("data/story/%s.json" % TitleScene.STAGE, ResourceJson.new().data_of(title))
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(_shelf.root), options)
	var lines := report.findings.filter(func(finding: PackReport.Finding) -> bool: return finding.area == "story").map(func(finding: PackReport.Finding) -> String: return finding.message)
	assert_array(lines).has_size(1)
	assert_str(lines[0]).is_equal("timeline 'title_ship' names the actor 'spray', which stage 'title_stage' does not hold: nothing moves or changes for it")
	assert_bool(report.passes()).is_false()
	# a pack that leaves the stages alone has no such finding, and a stage with a mistake of its own is one
	var clean := PackCheck.run(Packs.dev(), options)
	assert_bool(clean.findings.any(func(finding: PackReport.Finding) -> bool: return finding.area == "story")).is_false()
	title.actors.append(_actor(&"dup"))
	title.actors.append(_actor(&"dup"))
	_shelf.write_json("data/story/%s.json" % TitleScene.STAGE, ResourceJson.new().data_of(title))
	report = PackCheck.run(Pack.open(_shelf.root), options)
	assert_bool(report.findings.any(func(finding: PackReport.Finding) -> bool: return finding.area == "story" and finding.message.contains("stage 'title_stage': two actors are called 'dup'"))).is_true()


func test_the_chain_needs_the_news_scene_and_the_titles_stage() -> void:
	assert_str(PackNeeds.FILES["data/story/%s.tres" % Opening.SCENES[0]]).is_equal("StoryScene")
	assert_str(PackNeeds.FILES["data/story/%s.tres" % TitleScene.STAGE]).is_equal("CutsceneStage")
