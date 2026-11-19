class_name TestTimelineSegment
extends GdUnitTestSuite
## Teaches: a scene that is a FILE (`StoryScene`) played by one script (`TimelineSegment`). The tests write a small scene, its stage and its timelines into a scratch pack and play it (so the segment is tried on numbers the
## test owns, not on the opening's): the stage is built, the loop loops, the one-shot timelines play in order, an `end` cue ends the scene once, the speech is said step by step after each pause, `speak` is a verb a cue may call.
## Then what is told when a scene is wrong: a scene or timeline no pack holds, a song or voice group that does not resolve, a verb the engine lacks, an actor a timeline names that the stage lacks (`PackCheck`), each once and naming what
## the player gets instead. The news cartoon's own scene file is checked against the original in `test_opening_legacy` and `test_cutscene_timing`.

const SCENE := &"probe_scene"
const STAGE := &"probe_stage"
const MAIN_SCENE := &"news_cartoon"        # a scene the opening of dev lists (`PackCheck` looks at the scenes the opening names)

var _shelf: PackShelf
var _spoken: Array = []                     # [msec, clips] of every voice request while a test listens


func before_test() -> void:
	Audio.set_bus_enabled(AudioService.VOICE, false)         # (a request is then a signal and a short silent wait: `speech.silent_ticks`)
	_spoken = []
	Audio.voice_played.connect(_on_voice)


func after_test() -> void:
	Audio.voice_played.disconnect(_on_voice)
	Audio.set_bus_enabled(AudioService.VOICE, true)
	Audio.stop_voice()
	Audio.stop_music()
	if _shelf != null:
		_shelf.remove()
		_shelf = null
	Packs.start()
	TroubleLog.new_run()


func _on_voice(clips: Array[StringName]) -> void:
	_spoken.append([Time.get_ticks_msec(), clips])


func _timeline(length: float, loops := false) -> CutsceneTimeline:
	return CutsceneTimeline.made_in_code(length, "test", loops)


func _stage() -> CutsceneStage:
	var lamp := StageActor.new()
	lamp.name = &"lamp"
	lamp.picture = &"radar_map"
	lamp.position = Vector2(30, 40)
	var stage := CutsceneStage.new()
	stage.actors = [lamp]
	return stage


func _step(pause: int, group: StringName) -> SpeechStep:
	var step := SpeechStep.new()
	step.pause_ticks = pause
	step.group = group
	return step


## The probe scene: the stage `probe_stage`, the loop `probe_loop`, the one-shots `probe_a` and `probe_b` (which says `end`), no song, two steps of speech.
func _scene() -> StoryScene:
	var scene := StoryScene.new()
	scene.stage = STAGE
	scene.loops = [&"probe_loop"]
	scene.timelines = [&"probe_a", &"probe_b"]
	scene.speech = [_step(0, &"probe_g0"), _step(20, &"probe_g1")]
	return scene


## A scratch pack, chosen, that holds the probe scene, its stage and timelines, and voice groups; `changes` may alter them before they are written (`scene`, `timelines`).
func _with_probe(changes: Callable = Callable()) -> void:
	var scene := _scene()
	var timelines := {
		&"probe_loop": _timeline(10.0, true).track(&"lamp", CutsceneTrack.PROP_VISIBLE, [[0.0, true], [5.0, false]]),
		&"probe_a": _timeline(3.0).track(&"lamp", CutsceneTrack.PROP_VISIBLE, [[0.0, true]]),
		&"probe_b": _timeline(60.0).cue(60.0, CutsceneCue.EVENT, &"end"),
	}
	if changes.is_valid():
		changes.call(scene, timelines)
	_shelf = PackShelf.new()
	var writer := ResourceJson.new()
	_shelf.write_json("data/story/%s.json" % SCENE, writer.data_of(scene))
	_shelf.write_json("data/story/%s.json" % STAGE, writer.data_of(_stage()))
	for timeline_name: StringName in timelines:
		_shelf.write_json("data/story/%s.json" % timeline_name, writer.data_of(timelines[timeline_name]))
	_shelf.write_json("voice_cues.json", {"groups": {"probe_g0": ["sign_in_begin_0"], "probe_g1": ["sign_in_begin_1", "sign_in_begin_0"]}})
	_shelf.write_json(Durations.PACK_PATH, {"speech": {"silent_ticks": 1}, "prompt": {"timeout_ticks": 5000, "music_delay_ticks": 3}})
	_shelf.mount()
	TroubleLog.new_run()


func _segment() -> TimelineSegment:
	var segment: TimelineSegment = auto_free(TimelineSegment.of(SCENE))
	add_child(segment)
	return segment


func _lines(fragment: String) -> Array:
	return TroubleLog.session.told.filter(func(line: String) -> bool: return line.contains(fragment))


# --- playing a scene -----------------------------------------------------------------------------------------

func test_a_scene_builds_its_stage_plays_its_loop_and_its_timelines_in_order_and_ends_once() -> void:
	_with_probe()
	var segment := _segment()
	var started: Array[StringName] = []
	segment.script_player.animation_started.connect(func(animation_name: StringName) -> void: started.append(animation_name))
	var ended := [0]
	segment.finished.connect(func() -> void: ended[0] += 1)
	assert_array(segment.stage.get_children().map(func(node: Node) -> String: return node.name)).is_equal(["Lamp"])
	assert_vector((segment.cast.node_of(&"lamp") as Sprite2D).position).is_equal(Vector2(30, 40))
	assert_int(segment.loop_players.size()).is_equal(1)
	assert_str(segment.loop_players[0].current_animation).is_equal("probe_loop")
	assert_str(segment.script_player.current_animation).is_equal("probe_a")
	await await_millis(1500)
	assert_array(started).is_equal([&"probe_b"])                         # (`probe_a` began with the scene; its end started the next)
	assert_int(ended[0]).is_equal(1)
	assert_bool(segment.done).is_true()
	assert_bool(segment.loop_players[0].is_playing()).is_false()
	segment.skip()
	assert_int(ended[0]).is_equal(1)
	assert_array(TroubleLog.session.told).is_empty()


func test_the_speech_is_said_step_by_step_each_after_its_pause() -> void:
	_with_probe()
	var segment := _segment()
	await await_millis(600)
	assert_int(_spoken.size()).is_equal(2)
	assert_array(_spoken[0][1]).is_equal([&"sign_in_begin_0"])
	assert_array(_spoken[1][1]).is_equal([&"sign_in_begin_1", &"sign_in_begin_0"])
	assert_int(_spoken[1][0] - _spoken[0][0]).override_failure_message("the second step waits its pause of 20 ticks (274 ms)").is_greater_equal(250)
	segment.skip()


func test_the_song_of_the_scene_starts_with_it() -> void:
	_with_probe(func(scene: StoryScene, _timelines: Dictionary) -> void: scene.song = &"title")
	var segment := _segment()
	assert_str(Audio.song).is_equal("title")
	segment.skip()


func test_speak_is_a_verb_a_cue_may_call() -> void:
	_with_probe(func(_scene: StoryScene, timelines: Dictionary) -> void:
		(timelines[&"probe_a"] as CutsceneTimeline).cue(0.0, CutsceneCue.EVENT, &"speak probe_g1"))
	var segment := _segment()
	await await_millis(100)
	assert_array(_spoken.filter(func(entry: Array) -> bool: return entry[1].size() == 2)).has_size(1)
	segment.skip()


func test_a_skip_stops_the_speech_and_the_scene() -> void:
	_with_probe()
	var segment := _segment()
	segment.skip()
	assert_bool(segment.done).is_true()
	await await_millis(600)
	assert_int(_spoken.size()).is_less_equal(1)               # (the first step may have begun at once; the second never does)


func test_a_scene_no_pack_holds_ends_at_once_and_is_told_once() -> void:
	TroubleLog.new_run()
	var ended := [0]
	for i in 2:
		var segment: TimelineSegment = auto_free(TimelineSegment.of(&"no_such_scene"))
		segment.finished.connect(func() -> void: ended[0] += 1)
		add_child(segment)
		await await_idle_frame()
	assert_int(ended[0]).is_equal(2)
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).is_equal("[story] no pack of the chain holds the scene 'no_such_scene' (data/story/no_such_scene.tres): that part of the opening is skipped")


# --- the verbs --------------------------------------------------------------------------------------------------

func test_the_verbs_are_a_table_each_with_a_method() -> void:
	for verb: StringName in StoryVerbs.VERBS:
		assert_bool((auto_free(TimelineSegment.new()) as TimelineSegment).has_method("_verb_%s" % verb)).override_failure_message(String(verb)).is_true()
	assert_array(StoryVerbs.parse(&"speak news_speech_0")).is_equal(["speak", "news_speech_0"])
	assert_str(StoryVerbs.problem(&"end")).is_empty()
	assert_str(StoryVerbs.problem(&"end now")).is_equal("'end' takes 0 words after it, not 1")
	assert_str(StoryVerbs.problem(&"speak")).is_equal("'speak' takes 1 word after it, not 0")
	assert_str(StoryVerbs.problem(&"jump")).is_equal("'jump' is not a verb of the engine (end, speak, prompt)")
	assert_str(StoryVerbs.problem(&"")).contains("is not a verb")
	assert_str(StoryVerbs.problem(&"speak no_such_group")).is_equal("the voice group 'no_such_group' holds no clips in voice_cues")


func test_a_cue_with_a_verb_the_engine_lacks_does_nothing_and_is_told_once_with_the_pack() -> void:
	_with_probe(func(_scene: StoryScene, timelines: Dictionary) -> void:
		(timelines[&"probe_a"] as CutsceneTimeline).cue(1.0, CutsceneCue.EVENT, &"jump high"))
	var segment := _segment()
	segment.cue(&"jump high")
	segment.cue(&"jump high")
	await await_millis(100)
	var told := _lines("'jump high'")
	assert_array(told).is_equal(["[story] pack '%s': the scene 'probe_scene' has the cue 'jump high': 'jump' is not a verb of the engine (end, speak, prompt); the cue does nothing" % _shelf.id])
	assert_bool(segment.done).is_false()
	segment.skip()


# --- what a scene names that the chain lacks ---------------------------------------------------------------------

func test_every_name_a_scene_holds_that_the_chain_cannot_answer_is_told_once_and_the_rest_plays() -> void:
	_with_probe(func(scene: StoryScene, timelines: Dictionary) -> void:
		scene.loops = [&"probe_loop", &"no_loop"]
		scene.timelines = [&"probe_a", &"probe_b", &"no_timeline"]
		scene.song = &"no_song"
		scene.speech = [_step(0, &"probe_g0"), _step(5, &"no_group"), _step(-4, &"probe_g1")])
	var segment := _segment()
	var pack := String(_shelf.id)
	for fragment in ["names the timeline 'no_loop', which no pack of the chain holds: it is not played",
			"names the timeline 'no_timeline', which no pack of the chain holds: it is not played",
			"names the song 'no_song', which is neither one of the game's nor audio/music/no_song.ogg of a pack: it has no music",
			"speaks the voice group 'no_group', which no pack of the chain holds in voice_cues: that step is left out",
			"has a speech step with a pause of -4 ticks: it is taken as 0"]:
		assert_array(_lines(fragment)).override_failure_message(fragment).has_size(1)
		assert_str(_lines(fragment)[0]).starts_with("[story] pack '%s': the scene 'probe_scene' " % pack)
	assert_int(segment.loop_players.size()).is_equal(1)                  # (the loop that exists plays)
	await await_millis(1500)
	assert_array(_spoken.map(func(entry: Array) -> int: return entry[1].size())).is_equal([1, 2])      # (the step with no group is left out whole)
	assert_bool(segment.done).is_true()                                  # (and the one-shots that exist end the scene)


func test_a_loop_that_does_not_loop_and_a_one_shot_that_does_are_told() -> void:
	_with_probe(func(scene: StoryScene, _timelines: Dictionary) -> void:
		scene.loops = [&"probe_a"]
		scene.timelines = [&"probe_loop", &"probe_b"])
	var scene := Catalog.story_scene(SCENE)
	var lines := scene.unresolved()
	assert_array(lines).is_equal(["lists the timeline 'probe_a' as looping, but it does not loop: it plays once and stops",
			"lists the timeline 'probe_loop' to play once, but it loops: the timelines after it are never played"])


func test_a_scene_that_names_a_missing_stage_is_told_by_the_builder_once() -> void:
	_with_probe(func(scene: StoryScene, _timelines: Dictionary) -> void: scene.stage = &"no_stage")
	var segment := _segment()
	assert_array(_lines("no_stage")).has_size(1)
	assert_str(_lines("no_stage")[0]).contains("the stage 'no_stage'").contains("the scene shows nothing")
	segment.skip()


# --- the pack check ----------------------------------------------------------------------------------------------

## The findings of the area `story` of a check of the scratch pack, which holds `scene` as a scene the opening of dev names, and its stage and timelines as written by `_with_probe`'s files.
func _story_findings(scene: StoryScene, stage: CutsceneStage, timelines: Dictionary) -> Array:
	_shelf = PackShelf.new()
	var writer := ResourceJson.new()
	_shelf.write_json("data/story/%s.json" % MAIN_SCENE, writer.data_of(scene))
	if stage != null:
		_shelf.write_json("data/story/%s.json" % scene.stage, writer.data_of(stage))
	for timeline_name: StringName in timelines:
		_shelf.write_json("data/story/%s.json" % timeline_name, writer.data_of(timelines[timeline_name]))
	_shelf.write_json("voice_cues.json", {"groups": {"probe_g0": ["sign_in_begin_0"]}})
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(_shelf.root), options)
	return report.findings.filter(func(finding: PackReport.Finding) -> bool: return finding.area == "story").map(func(finding: PackReport.Finding) -> String: return finding.message)


func test_the_check_of_a_pack_tells_each_thing_a_scene_names_that_the_chain_lacks() -> void:
	var scene := _scene()
	scene.loops = [&"probe_loop", &"no_loop"]
	scene.timelines = [&"probe_a", &"no_timeline"]
	scene.song = &"no_song"
	scene.speech = [_step(0, &"probe_g0"), _step(5, &"no_group")]
	var timelines := {
		&"probe_loop": _timeline(10.0, true),
		&"probe_a": _timeline(3.0).cue(1.0, CutsceneCue.EVENT, &"jump").cue(2.0, CutsceneCue.EVENT, &"speak").cue(3.0, CutsceneCue.EVENT, &"speak no_group_either"),
	}
	var lines := _story_findings(scene, _stage(), timelines)
	for expected in ["scene 'news_cartoon' names the timeline 'no_loop', which no pack of the chain holds: it is not played",
			"scene 'news_cartoon' names the timeline 'no_timeline', which no pack of the chain holds: it is not played",
			"scene 'news_cartoon' names the song 'no_song', which is neither one of the game's nor audio/music/no_song.ogg of a pack: it has no music",
			"scene 'news_cartoon' speaks the voice group 'no_group', which no pack of the chain holds in voice_cues: that step is left out",
			"scene 'news_cartoon' has the cue 'jump': 'jump' is not a verb of the engine (end, speak, prompt); the cue does nothing",
			"scene 'news_cartoon' has the cue 'speak': 'speak' takes 1 word after it, not 0; the cue does nothing",
			"scene 'news_cartoon' has the cue 'speak no_group_either': the voice group 'no_group_either' holds no clips in voice_cues; the cue does nothing"]:
		assert_array(lines).override_failure_message("not told: %s\nthe check says:\n%s" % [expected, "\n".join(lines)]).contains([expected])
	assert_int(lines.size()).override_failure_message("\n".join(lines)).is_equal(7)


func test_the_check_of_a_pack_tells_a_stage_the_chain_lacks_and_an_actor_the_stage_lacks() -> void:
	var scene := _scene()
	scene.loops = []
	scene.timelines = [&"probe_a"]
	scene.speech = []
	var timelines := {&"probe_a": _timeline(3.0).track(&"ghost", CutsceneTrack.PROP_VISIBLE, [[0.0, true]]).track(&"lamp", CutsceneTrack.PROP_VISIBLE, [[0.0, true]])}
	var lines := _story_findings(scene, _stage(), timelines)
	assert_array(lines).is_equal(["timeline 'probe_a' names the actor 'ghost', which stage 'probe_stage' does not hold: nothing moves or changes for it"])
	_shelf.remove()
	_shelf = null
	lines = _story_findings(scene, null, timelines)
	assert_array(lines).is_equal(["scene 'news_cartoon' names the stage 'probe_stage', which no pack of the chain holds: nothing is drawn"])


func test_a_scene_that_is_fine_has_no_findings_and_the_opening_scene_of_dev_is_fine() -> void:
	assert_array(Catalog.story_scene(MAIN_SCENE).unresolved()).is_empty()
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Packs.dev(), options)
	assert_bool(report.findings.any(func(finding: PackReport.Finding) -> bool: return finding.area == "story")).is_false()


# --- a scene that asks: the chain, the holds, the prompt --------------------------------------------------------

## What the title is made of, small: a stage with a lamp and the two buttons of a prompt (Start on S, Intro on I, hidden), the timelines `probe_a` (plain), `probe_hold` (marks at 0, 20 and 40 ticks, a sound at 20 and the cue `prompt` at 40, its first
## keys hide the lamp) and `probe_b` (the last, no marks), the song `title` that stops where `probe_b` begins, and `opening` that starts after the prompt.
func _asking(changes: Callable = Callable()) -> void:
	var hold := _timeline(60.0).track(&"lamp", CutsceneTrack.PROP_VISIBLE, [[0.0, false]]).cue(20.0, CutsceneCue.SOUND, &"opening_end").cue(40.0, CutsceneCue.EVENT, &"prompt")
	hold.marks = {&"first": 0.0, &"second": 20.0, &"third": 40.0}
	_with_probe(func(scene: StoryScene, timelines: Dictionary) -> void:
		scene.loops = []
		scene.speech = []
		scene.timelines = [&"probe_a", &"probe_hold", &"probe_b"]
		scene.song = &"title"
		scene.song_stops_at = &"probe_b"
		scene.prompt_song = &"opening"
		timelines[&"probe_a"] = _timeline(4000.0).track(&"lamp", CutsceneTrack.PROP_VISIBLE, [[0.0, true]])
		timelines[&"probe_hold"] = hold
		timelines[&"probe_b"] = _timeline(4000.0)
		if changes.is_valid():
			changes.call(scene, timelines))
	var writer := ResourceJson.new()
	var stage := _stage()
	stage.actors.append(_asking_button(&"start_button", Vector2(10, 300), StageActor.START, "S"))
	stage.actors.append(_asking_button(&"intro_button", Vector2(110, 300), StageActor.INTRO, "I"))
	_shelf.write_json("data/story/%s.json" % STAGE, writer.data_of(stage))
	Packs.start()
	_shelf.mount()


func _asking_button(button_name: StringName, at: Vector2, answer: StringName, key: String) -> StageActor:
	var actor := StageActor.new()
	actor.name = button_name
	actor.kind = StageActor.BUTTON
	actor.picture = &"start_button_up"
	actor.pressed_picture = &"start_button_down"
	actor.position = at
	actor.visible = false
	actor.choice = answer
	actor.hotkey = key
	return actor


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _lamp(segment: TimelineSegment) -> Sprite2D:
	return segment.cast.node_of(&"lamp") as Sprite2D


## Enter through to the prompt: out of `probe_a`, then the two holds of `probe_hold`.
func _to_the_prompt(segment: TimelineSegment) -> void:
	segment.advance()
	segment.advance()
	segment.advance()


func test_enter_goes_on_to_the_next_timeline_and_its_first_keys_are_applied_at_once() -> void:
	_asking()
	var segment := _segment()
	assert_str(segment.script_player.current_animation).is_equal("probe_a")
	assert_bool(_lamp(segment).visible).is_true()
	segment.advance()
	assert_str(segment.script_player.current_animation).is_equal("probe_hold")
	assert_bool(_lamp(segment).visible).override_failure_message("the first keys of the next timeline set the stage it needs, before the next frame").is_false()
	assert_bool(segment.done).is_false()
	assert_bool(segment.prompting).is_false()
	segment.skip()


func test_a_timeline_that_ends_goes_on_to_the_next_and_its_first_keys_apply() -> void:
	_asking(func(_scene: StoryScene, timelines: Dictionary) -> void:
		timelines[&"probe_a"] = _timeline(3.0).track(&"lamp", CutsceneTrack.PROP_VISIBLE, [[0.0, true]]))
	var segment := _segment()
	await await_millis(400)
	assert_str(segment.script_player.current_animation).is_equal("probe_hold")
	assert_bool(_lamp(segment).visible).is_false()
	assert_bool(segment.done).is_false()
	segment.skip()


func test_enter_in_a_timeline_with_marks_ends_the_hold_that_runs_and_fires_the_cues_of_the_mark() -> void:
	_asking()
	var segment := _segment()
	segment.advance()                                             # `probe_a` ends: the first hold begins at its mark `first`
	assert_float(segment.script_player.current_animation_position).is_less(CutsceneTimeline.seconds(20.0))
	segment.advance()                                             # the first hold ends: the mark `second`, a hair past it
	assert_float(segment.script_player.current_animation_position).is_equal_approx(CutsceneTimeline.seconds(20.0), 0.01)
	assert_bool(segment.prompting).is_false()
	segment.advance()                                             # the second hold ends: the mark `third`, and its cue `prompt` is done
	assert_float(segment.script_player.current_animation_position).is_equal_approx(CutsceneTimeline.seconds(40.0), 0.01)
	assert_bool(segment.prompting).is_true()
	assert_bool(segment.done).is_false()
	segment.skip()


func test_enter_in_the_last_timeline_with_nothing_to_answer_ends_the_scene() -> void:
	_asking(func(scene: StoryScene, _timelines: Dictionary) -> void: scene.timelines = [&"probe_a", &"probe_b"])
	var segment := _segment()
	segment.advance()
	assert_str(segment.script_player.current_animation).is_equal("probe_b")
	assert_bool(segment.done).is_false()
	segment.advance()
	assert_bool(segment.done).is_true()
	assert_bool(segment.choice == StageActor.INTRO).is_false()


func test_the_prompt_shows_the_buttons_and_enter_a_click_elsewhere_or_the_time_out_mean_intro() -> void:
	_asking()
	var segment := _segment()
	assert_bool(segment.buttons.values().any(func(button: TextureButton) -> bool: return button.visible)).is_false()
	_to_the_prompt(segment)
	assert_array(segment.buttons.keys()).contains_exactly_in_any_order([StageActor.START, StageActor.INTRO])
	assert_bool(segment.buttons.values().all(func(button: TextureButton) -> bool: return button.visible)).is_true()
	assert_int(segment.prompt_timeout_ticks).is_equal(5000)
	segment.cue(&"prompt")                                                      # (a second `prompt` changes nothing)
	assert_int(segment.prompt_timeout_ticks).is_equal(5000)
	segment.advance()
	assert_bool(segment.done).is_true()
	assert_bool(segment.choice == StageActor.INTRO).is_true()
	# a click elsewhere is Enter, the release over a button is nobody's
	var clicked := _segment()
	_to_the_prompt(clicked)
	clicked.click(clicked.buttons[StageActor.START].get_global_rect().get_center())
	clicked.click(clicked.buttons[StageActor.INTRO].get_global_rect().get_center())
	assert_bool(clicked.done).is_false()
	clicked.click(Vector2(320, 100))
	assert_bool(clicked.choice == StageActor.INTRO).is_true()


func test_nobody_choosing_in_time_means_intro_and_an_answer_stops_the_countdown() -> void:
	_asking()
	_shelf.write_json(Durations.PACK_PATH, {"speech": {"silent_ticks": 1}, "prompt": {"timeout_ticks": 8, "music_delay_ticks": 3}})
	Packs.start()
	_shelf.mount()
	var timed_out := _segment()
	_to_the_prompt(timed_out)
	assert_int(timed_out.prompt_timeout_ticks).is_equal(8)
	assert_bool(timed_out.done).is_false()
	await await_millis(300)                                                      # (8 ticks: 110 ms)
	assert_bool(timed_out.done).is_true()
	assert_bool(timed_out.choice == StageActor.INTRO).is_true()
	var answered := _segment()
	_to_the_prompt(answered)
	answered.buttons[StageActor.START].pressed.emit()
	await await_millis(300)
	assert_str(answered.choice).is_equal("start")                                # (the countdown ran out on a scene that was over: nothing changed)


func test_a_button_answers_on_its_press_and_its_key_answers_the_same_once_the_prompt_is_up() -> void:
	_asking()
	var pressed := _segment()
	_to_the_prompt(pressed)
	pressed.buttons[StageActor.START].pressed.emit()
	assert_bool(pressed.done).is_true()
	assert_str(pressed.choice).is_equal("start")
	assert_bool(pressed.choice == StageActor.INTRO).is_false()
	for entry: Array in [[KEY_S, &"start"], [KEY_I, &"intro"]]:
		var keyed := _segment()
		keyed._unhandled_key_input(_key(entry[0]))                              # (no prompt yet: a key is nothing)
		keyed._unhandled_key_input(_key(KEY_X))
		assert_bool(keyed.done).is_false()
		_to_the_prompt(keyed)
		keyed._unhandled_key_input(_key(KEY_X))
		assert_bool(keyed.done).is_false()
		keyed._unhandled_key_input(_key(entry[0]))
		assert_bool(keyed.done).is_true()
		assert_str(keyed.choice).is_equal(String(entry[1]))


func test_skip_leaves_without_an_answer_from_every_part_of_the_scene() -> void:
	_asking()
	for steps in 4:
		var segment := _segment()
		for i in steps:
			segment.advance()
		segment.skip()
		assert_bool(segment.done).is_true()
		assert_bool(segment.choice == StageActor.INTRO).is_false()


func test_the_song_stops_where_the_scene_says_and_the_prompts_song_starts_after_its_delay() -> void:
	_asking()
	var segment := _segment()
	assert_str(Audio.song).is_equal("title")
	segment.advance()
	assert_str(Audio.song).override_failure_message("the song goes on into `probe_hold`").is_equal("title")
	segment.advance()
	segment.advance()
	assert_bool(segment.prompting).is_true()
	assert_str(Audio.song).is_equal("title")
	await await_millis(150)                                                      # (`prompt.music_delay_ticks` is 3: 41 ms)
	assert_str(Audio.song).is_equal("opening")
	segment.skip()


func test_the_song_stops_when_the_timeline_the_scene_names_begins() -> void:
	_asking(func(scene: StoryScene, _timelines: Dictionary) -> void: scene.timelines = [&"probe_a", &"probe_b"])
	var segment := _segment()
	assert_str(Audio.song).is_equal("title")
	segment.advance()
	assert_str(Audio.song).is_equal("")
	segment.skip()


func test_a_scene_that_asks_has_no_warning_when_it_is_whole() -> void:
	_asking()
	assert_array(Catalog.story_scene(SCENE).unresolved()).is_empty()
	var segment := _segment()
	_to_the_prompt(segment)
	segment.skip()
	assert_array(TroubleLog.session.told).is_empty()


func test_what_a_scene_that_asks_names_wrongly_is_told_once_and_the_prompt_still_ends_by_enter() -> void:
	_asking(func(scene: StoryScene, _timelines: Dictionary) -> void:
		scene.song_stops_at = &"probe_a_typo"
		scene.prompt_song = &"no_such_song")
	var writer := ResourceJson.new()
	_shelf.write_json("data/story/%s.json" % STAGE, writer.data_of(_stage()))                 # (a stage with no button at all)
	Packs.start()
	_shelf.mount()
	TroubleLog.new_run()
	var segment := _segment()
	var pack := String(_shelf.id)
	for fragment in ["stops the song at the timeline 'probe_a_typo', which it does not play once: the song plays on",
			"names the prompt's song 'no_such_song', which is neither one of the game's nor audio/music/no_such_song.ogg of a pack: the prompt has no music",
			"has the cue 'prompt', but its stage 'probe_stage' has no button: the prompt shows none, and only Enter, a click and the time-out answer it"]:
		assert_array(_lines(fragment)).override_failure_message(fragment).has_size(1)
		assert_str(_lines(fragment)[0]).starts_with("[story] pack '%s': the scene 'probe_scene' " % pack)
	_to_the_prompt(segment)
	assert_bool(segment.buttons.is_empty()).is_true()
	segment.advance()
	assert_bool(segment.choice == StageActor.INTRO).is_true()


func test_the_check_of_a_pack_tells_what_a_scene_that_asks_names_wrongly_and_a_button_that_cannot_be_made() -> void:
	var scene := _scene()
	scene.loops = []
	scene.speech = []
	scene.timelines = [&"probe_a"]
	scene.song_stops_at = &"elsewhere"
	var stage := _stage()
	var odd := _asking_button(&"odd", Vector2.ZERO, &"maybe", "Nonsense")
	stage.actors.append(odd)
	var lines := _story_findings(scene, stage, {&"probe_a": _timeline(3.0).cue(1.0, CutsceneCue.EVENT, &"prompt")})
	for expected in ["scene 'news_cartoon' stops the song at the timeline 'elsewhere', which it does not play once: the song plays on",
			"stage 'probe_stage': actor 'odd': a button answers 'maybe', not one of start, intro"]:
		assert_array(lines).override_failure_message("not told: %s\nthe check says:\n%s" % [expected, "\n".join(lines)]).contains([expected])
	assert_array(lines).has_size(2)
