class_name TestOpeningList
extends GdUnitTestSuite
## Teaches: the opening as a LIST a pack writes (`OpeningList`, `data/story/opening.tres`): the director plays what the chain holds, in its order, with its rule for the answer that leads on and for starting over. Dev's opening is
## shaped unlike the original's (four parts, the first a scene of its own). The tests lay another list over dev in a scratch pack and play it: a pack's own opening, an empty one (straight to sign-in), a part the chain does not hold
## (told once, naming the pack and what happens instead, and skipped), the answer that leads on, the time-out that starts it over. `PackCheck` and `PackNeeds` read the same list.

const OPENING := "res://src/story/opening.tscn"

var _shelf: PackShelf


func before_test() -> void:
	SceneRouter.dry_run = true
	SceneRouter.last_path = ""
	Audio.stop_music()


func after_test() -> void:
	SceneRouter.dry_run = false
	Audio.stop_music()
	Audio.stop_voice()
	if _shelf != null:
		_shelf.remove()
		_shelf = null
	TroubleLog.new_run()


func _part(kind: StringName, part_name: StringName, leads_on := &"") -> OpeningPart:
	var part := OpeningPart.new()
	part.kind = kind
	part.name = part_name
	part.leads_on = leads_on
	return part


func _list(parts: Array[OpeningPart], starts_over := false) -> OpeningList:
	var list := OpeningList.new()
	list.parts = parts
	list.starts_over = starts_over
	return list


## A scratch pack over dev that holds `list` as its opening.
func _with(list: OpeningList) -> void:
	_shelf = PackShelf.new()
	_shelf.write_json("data/story/opening.json", ResourceJson.new().data_of(list))
	_shelf.mount()
	TroubleLog.new_run()


func _opening() -> Opening:
	var opening: Opening = auto_free(load(OPENING).instantiate())
	opening.go_to_sign_in = false
	add_child(opening)
	return opening


func _scene_of(opening: Opening) -> String:
	var segment := opening.current as TimelineSegment
	return String(segment.scene_name) if segment != null else ""


func _lines(fragment: String) -> Array:
	return TroubleLog.session.told.filter(func(line: String) -> bool: return line.contains(fragment))


func _findings() -> Array:
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(_shelf.root), options)
	return report.findings.filter(func(finding: PackReport.Finding) -> bool: return finding.area == "story").map(func(finding: PackReport.Finding) -> String: return finding.message)


# --- dev's opening --------------------------------------------------------------------------------------------

func test_dev_holds_an_opening_of_its_own_shape_that_the_chain_resolves() -> void:
	var list := Catalog.opening()
	assert_object(list).is_same(Packs.dev().resource(Catalog.STORY_REL % "opening"))
	assert_array(list.parts.map(func(part: OpeningPart) -> String: return "%s %s" % [part.kind, part.name])).is_equal(["scene logo", "scene news_cartoon", "scene title", "story story_script"])
	assert_array(list.parts.map(func(part: OpeningPart) -> String: return String(part.leads_on))).is_equal(["", "", "intro", ""])
	assert_bool(list.starts_over).is_true()
	assert_array(list.unresolved()).is_empty()
	assert_str(PackNeeds.FILES["data/story/opening.tres"]).is_equal("OpeningList")
	var named := PackNeeds.named_by_opening()
	assert_str(named["data/story/logo.tres"]).is_equal("StoryScene")
	assert_str(named["data/story/logo_stage.tres"]).is_equal("CutsceneStage")
	assert_str(named["data/story/logo_show.tres"]).is_equal("CutsceneTimeline")
	assert_str(named["data/story/story_script.tres"]).is_equal("StoryScript")
	assert_str(PackNeeds.class_of("data/story/title_reveal.tres")).is_equal("CutsceneTimeline")


func test_the_director_plays_the_parts_in_the_order_of_the_list() -> void:
	var opening := _opening()
	await await_idle_frame()
	assert_object(opening.list).is_same(Catalog.opening())
	assert_str(_scene_of(opening)).is_equal("logo")
	opening.current.advance()
	await await_idle_frame()
	assert_str(_scene_of(opening)).is_equal("news_cartoon")
	opening.current.advance()
	await await_idle_frame()
	assert_str(_scene_of(opening)).is_equal("title")


func test_the_logo_scene_of_dev_ends_by_its_own_verb() -> void:
	var logo: TimelineSegment = auto_free(TimelineSegment.of(&"logo"))
	add_child(logo)
	assert_array(logo.stage.get_children().map(func(node: Node) -> String: return node.name)).is_equal(["Emblem", "Byline"])
	assert_bool(logo.cast.node_of(&"byline").visible).is_false()
	var timeline := Catalog.story_timeline(&"logo_show")
	assert_bool(timeline.cues.any(func(entry: CutsceneCue) -> bool: return entry.kind == CutsceneCue.EVENT and entry.cue_name == &"end")).is_true()
	assert_bool(logo.done).is_false()
	logo.script_player.seek(CutsceneTimeline.seconds(150.0) + 0.01, true)       # (`seek` calls no cue: the verb is called as the timeline reaches it)
	logo.cue(&"end")
	assert_bool(logo.done).is_true()


# --- a pack's own opening --------------------------------------------------------------------------------------

func test_a_pack_that_holds_an_opening_of_its_own_plays_it_and_nothing_else() -> void:
	_with(_list([_part(OpeningPart.SCENE, &"title"), _part(OpeningPart.SCENE, &"logo")]))
	var opening := _opening()
	await await_idle_frame()
	assert_str(_scene_of(opening)).is_equal("title")
	opening.current.skip()
	await await_idle_frame()
	assert_str(_scene_of(opening)).is_equal("logo")
	opening.current.skip()
	await await_idle_frame()
	await await_idle_frame()
	assert_object(opening.current).is_null()
	assert_array(TroubleLog.session.told).is_empty()


func test_an_empty_opening_goes_straight_to_the_sign_in_screen_and_says_nothing() -> void:
	_with(_list([] as Array[OpeningPart], true))
	var opening: Opening = auto_free(load(OPENING).instantiate())
	add_child(opening)
	await await_idle_frame()
	await await_idle_frame()
	assert_object(opening.current).is_null()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)
	assert_array(TroubleLog.session.told).is_empty()
	assert_array(_findings()).is_empty()


func test_a_chain_with_no_opening_at_all_is_told_once_and_goes_to_the_sign_in_screen() -> void:
	PackShelf.without_dev()
	var folders := Packs.folders.duplicate()
	var dir := PackShelf.empty_complete_pack_dir(&"zz_bare_opening")
	Packs.folders = [dir]
	Packs.use(Pack.open("%s/zz_bare_opening" % dir))
	TroubleLog.new_run()
	assert_object(Catalog.opening()).is_null()
	var opening: Opening = auto_free(load(OPENING).instantiate())
	add_child(opening)
	await await_idle_frame()
	await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)
	assert_array(TroubleLog.session.told).is_equal(["[story] no pack of the chain holds the opening (data/story/opening.tres): the game goes straight to the sign-in screen"])
	PackShelf.remove_empty_packs()
	Packs.folders.assign(folders)
	PackShelf.with_dev_again()


func test_a_part_the_chain_does_not_hold_is_told_once_with_the_pack_and_skipped() -> void:
	_with(_list([_part(OpeningPart.SCENE, &"no_such_scene"), _part(OpeningPart.STORY, &"no_such_story"), _part(OpeningPart.SCENE, &"logo")]))
	var opening := _opening()
	await await_idle_frame()
	assert_str(_scene_of(opening)).is_equal("logo")                     # (the two parts before it are skipped)
	var pack := String(_shelf.id)
	var scene_line := "[story] pack '%s': the opening's part 1 (scene 'no_such_scene') names the scene 'no_such_scene', which no pack of the chain holds (data/story/no_such_scene.tres): that part is skipped" % pack
	var story_line := "[story] pack '%s': the opening's part 2 (story 'no_such_story') names the story 'no_such_story', which no pack of the chain holds (data/story/no_such_story.tres): that part is skipped" % pack
	assert_array(TroubleLog.session.told).is_equal([scene_line, story_line])
	opening.current.skip()
	await await_idle_frame()
	assert_array(TroubleLog.session.told).has_size(2)                    # (once per run, however often the parts are met)


func test_the_check_of_a_pack_tells_the_same_parts_and_answers() -> void:
	_with(_list([_part(OpeningPart.SCENE, &"no_such_scene"), _part(&"video", &"intro_film"), _part(OpeningPart.SCENE, &"logo", &"intro"),
			_part(OpeningPart.STORY, &"story_script", &"intro"), _part(OpeningPart.SCENE, &"title", &"maybe")]))
	var lines := _findings()
	for expected in ["opening: part 1 (scene 'no_such_scene') names the scene 'no_such_scene', which no pack of the chain holds (data/story/no_such_scene.tres): that part is skipped",
			"opening: part 2 (video 'intro_film') is of the kind 'video', which is none of scene, story: that part is skipped",
			"opening: part 3 (scene 'logo') goes on with the answer 'intro', but nothing in it asks (a scene needs the cue 'prompt'): the opening ends after it",
			"opening: part 4 (story 'story_script') goes on with the answer 'intro', but nothing in it asks (a scene needs the cue 'prompt'): the opening ends after it",
			"opening: part 5 (scene 'title') goes on with the answer 'maybe', which none of start, intro is: the opening ends after it"]:
		assert_array(lines).override_failure_message("not told: %s\nthe check says:\n%s" % [expected, "\n".join(lines)]).contains([expected])
	assert_int(lines.size()).override_failure_message("\n".join(lines)).is_equal(5)
	assert_bool(PackCheck.run(Pack.open(_shelf.root), _no_reach()).passes()).is_false()


func _no_reach() -> PackCheck.Options:
	var options := PackCheck.Options.new()
	options.reach = false
	return options


# --- which answer leads on, and starting over ----------------------------------------------------------------------

func _answer_the_title(opening: Opening, answer: StringName) -> void:
	await await_idle_frame()
	var title := opening.current as TimelineSegment
	assert_str(String(title.scene_name)).is_equal("title")
	title.advance()
	title.advance()
	title.advance()
	title.buttons[answer].pressed.emit()
	await await_idle_frame()
	await await_idle_frame()


func test_the_answer_a_part_leads_on_with_is_the_lists_to_say() -> void:
	_with(_list([_part(OpeningPart.SCENE, &"title", &"start"), _part(OpeningPart.SCENE, &"logo")]))
	var opening := _opening()
	await _answer_the_title(opening, StageActor.START)
	assert_str(_scene_of(opening)).is_equal("logo")                      # Start leads on in this list ...
	opening.queue_free()
	await await_idle_frame()
	var other := _opening()
	await _answer_the_title(other, StageActor.INTRO)
	assert_object(other.current).is_null()                                # ... and Intro leaves for the sign-in screen
	assert_str(_scene_of(other)).is_equal("")


func test_a_part_with_no_answer_to_wait_for_always_goes_on() -> void:
	_with(_list([_part(OpeningPart.SCENE, &"title"), _part(OpeningPart.SCENE, &"logo")]))
	var opening := _opening()
	await _answer_the_title(opening, StageActor.START)
	assert_str(_scene_of(opening)).is_equal("logo")


func test_a_story_that_runs_out_its_time_starts_the_opening_over_only_when_the_list_says_so() -> void:
	var script := Catalog.story_script(&"story_script")
	var last_page_ticks := script.last_page_ticks
	script.last_page_ticks = 0.0
	for starts_over in [true, false]:
		_with(_list([_part(OpeningPart.SCENE, &"logo"), _part(OpeningPart.STORY, &"story_script")], starts_over))
		var opening := _opening()
		await await_idle_frame()
		opening.current.skip()                                                          # the logo
		await await_idle_frame()
		var story := opening.current as StoryPages
		assert_object(story).is_not_null()
		await await_idle_frame()
		for page in script.pages.size() - 1:
			story.advance()
		await await_idle_frame()
		Audio.stop_voice()                                                              # the last page's speech ends: nothing is left of its hold
		await await_idle_frame()
		await await_idle_frame()
		if starts_over:
			assert_str(_scene_of(opening)).is_equal("logo")
		else:
			assert_object(opening.current).is_null()
		opening.queue_free()
		await await_idle_frame()
		_shelf.remove()
		_shelf = null
	script.last_page_ticks = last_page_ticks
