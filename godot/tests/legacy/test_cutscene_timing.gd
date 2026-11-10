class_name TestCutsceneTiming
extends GdUnitTestSuite
## Teaches: pinning a behaviour while its implementation changes. The cutscenes' `Animation` tracks are data
## (`CutsceneTimeline`s, played by animations that the scenes build at run time). The rule of that change was "the same pictures
## at the same times", so `fixtures/cutscene_timing.json` records, as the old code built them, the length of every cutscene, whether
## it loops, EVERY moment at which anything changes and every sound and event, in ticks of the original's 73 Hz timer. These tests
## check the data and the animations that the scenes really build against that record. A durations that holds up play (the 163
## frames of the ship scene, the 292 tick holds of the title, the 18 tick steps of the Expert closing, the 365 tick pages) cannot
## drift without one of them failing.
##
## (The fixture is hand-made from the old code, not from the original game's files: it holds no original bytes.)

const FIXTURE := "res://tests/fixtures/cutscene_timing.json"
const TICKS := 73.0
const TOLERANCE := 0.0015                      # ticks: the fixture rounds to 3 decimals

const NEWS := "res://src/story/news_cartoon.tscn"
const TITLE := "res://src/story/title_scene.tscn"
const PAGES := "res://src/story/story_pages.tscn"
const VOYAGER := "res://src/story/voyager_closing.tscn"
const EXPERT := "res://src/story/expert_closing.tscn"

## The data files by the name the fixture uses.
const TIMELINES := {
	"title_ship": preload("res://data/story/title_ship.tres"),
	"title_reveal": preload("res://data/story/title_reveal.tres"),
	"expert_hoist": preload("res://data/story/expert_hoist.tres"),
	"expert_deck": preload("res://data/story/expert_deck.tres"),
	"expert_wait": preload("res://data/story/expert_wait.tres"),
}

## (The news cartoon is made of the game's text, so it is the legacy pack and loaded, not preloaded: this file compiles without the game.)
const NEWS_CARTOON := LegacyPack.ROOT + "data/story/news_cartoon.tres"

var _fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	Audio.stop_music()


func after_test() -> void:
	Audio.stop_music()
	Audio.stop_voice()


## The cues of a timeline as the fixture writes them: [tick, kind, name], in time order (a sound before an event at the same moment).
func _cues_of(timeline: CutsceneTimeline) -> Array:
	var list: Array = []
	for cue_entry in timeline.cues:
		list.append([cue_entry.tick, String(cue_entry.kind), String(cue_entry.cue_name)])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	return list


func _check_timeline(timeline: CutsceneTimeline, expected: Dictionary, label: String) -> void:
	assert_float(timeline.length).override_failure_message("%s: length" % label).is_equal_approx(float(expected.length), TOLERANCE)
	assert_bool(timeline.loop).override_failure_message("%s: loop" % label).is_equal(expected.loop)
	var moments := timeline.key_times()
	var wanted: Array = expected.key_ticks
	assert_int(moments.size()).override_failure_message("%s: number of moments" % label).is_equal(wanted.size())
	for i in mini(moments.size(), wanted.size()):
		assert_float(moments[i]).override_failure_message("%s: moment %d" % [label, i]).is_equal_approx(float(wanted[i]), TOLERANCE)
	var cues := _cues_of(timeline)
	assert_int(cues.size()).override_failure_message("%s: number of cues" % label).is_equal(expected.cues.size())
	for i in mini(cues.size(), expected.cues.size()):
		var want: Array = expected.cues[i]
		assert_float(cues[i][0]).override_failure_message("%s: cue %d moment" % [label, i]).is_equal_approx(float(want[0]), TOLERANCE)
		assert_str(cues[i][1]).override_failure_message("%s: cue %d kind" % [label, i]).is_equal(want[1])
		assert_str(cues[i][2]).override_failure_message("%s: cue %d name" % [label, i]).is_equal(want[2])


## The animation's length and key times in ticks, and its method calls as [tick, kind, name].
func _check_animation(animation: Animation, expected: Dictionary, label: String) -> void:
	assert_float(animation.length * TICKS).override_failure_message("%s: animation length" % label).is_equal_approx(float(expected.length), TOLERANCE)
	assert_bool(animation.loop_mode == Animation.LOOP_LINEAR).override_failure_message("%s: animation loop" % label).is_equal(expected.loop)
	var seen := {}
	var calls: Array = []
	for track in animation.get_track_count():
		for key in animation.track_get_key_count(track):
			var tick := snappedf(animation.track_get_key_time(track, key) * TICKS, 0.001)
			seen[tick] = true
			if animation.track_get_type(track) == Animation.TYPE_METHOD:
				var method := animation.method_track_get_name(track, key)
				var args := animation.method_track_get_params(track, key)
				calls.append([tick, "sound" if method == &"play_sfx" else "event", String(args[0])])
	var moments := seen.keys()
	moments.sort()
	var wanted: Array = expected.key_ticks
	assert_int(moments.size()).override_failure_message("%s: animation moments" % label).is_equal(wanted.size())
	for i in mini(moments.size(), wanted.size()):
		assert_float(moments[i]).override_failure_message("%s: animation moment %d" % [label, i]).is_equal_approx(float(wanted[i]), TOLERANCE)
	calls.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	assert_int(calls.size()).override_failure_message("%s: animation calls" % label).is_equal(expected.cues.size())
	for i in mini(calls.size(), expected.cues.size()):
		var want: Array = expected.cues[i]
		assert_float(calls[i][0]).is_equal_approx(float(want[0]), TOLERANCE)
		assert_str(calls[i][1]).is_equal(want[1])
		assert_str(calls[i][2]).is_equal(want[2])


# --- the data -------------------------------------------------------------------------------------------------------

func test_the_fixture_says_what_it_is() -> void:
	assert_float(float(_fixture.ticks_per_second)).is_equal(CutsceneTimeline.TICKS_PER_SECOND)
	assert_int(_fixture.cutscenes.size()).is_equal(13)


func test_the_timelines_of_the_data_files_have_the_old_lengths_and_moments() -> void:
	for timeline_name: String in TIMELINES:
		_check_timeline(TIMELINES[timeline_name], _fixture.cutscenes[timeline_name], timeline_name)
	_check_timeline(load(NEWS_CARTOON), _fixture.cutscenes["news_cartoon"], "news_cartoon")


func test_the_voyager_flight_has_the_old_length_and_moments_for_every_starting_place() -> void:
	var script: VoyagerClosingScript = load("res://data/story/voyager_closing_script.tres")
	var tried := 0
	for timeline_name: String in _fixture.cutscenes:
		var expected: Dictionary = _fixture.cutscenes[timeline_name]
		if expected.has("start"):
			var start: Array = expected.start
			_check_timeline(script.timeline(int(start[0]), int(start[1]), int(start[2])), expected, timeline_name)
			tried += 1
	assert_int(tried).is_equal(5)


# --- the animations the scenes build -------------------------------------------------------------------------------------

func test_the_news_cartoon_animations_have_the_old_lengths_and_moments() -> void:
	var news: NewsCartoon = auto_free(load(NEWS).instantiate())
	add_child(news)
	_check_animation(news.script_player.get_animation(&"news"), _fixture.cutscenes.news_cartoon, "news")
	_check_animation(news.ambient.get_animation(&"ambient"), _fixture.cutscenes.news_ambient, "ambient")
	news.finish()


func test_the_title_scene_animations_have_the_old_lengths_and_moments() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	_check_animation(title.animations.get_animation(&"ship"), _fixture.cutscenes.title_ship, "ship")
	_check_animation(title.animations.get_animation(&"reveal"), _fixture.cutscenes.title_reveal, "reveal")


func test_the_story_page_fade_has_the_old_length_and_moments() -> void:
	var story: StoryPages = auto_free(load(PAGES).instantiate())
	add_child(story)
	_check_animation(story.animations.get_animation(&"show"), _fixture.cutscenes.story_page_fade, "show")
	story.skip()


func test_the_expert_closing_animations_have_the_old_lengths_and_moments() -> void:
	var closing: ExpertClosing = auto_free(load(EXPERT).instantiate())
	add_child(closing)
	for stage_name in ["hoist", "deck", "wait"]:
		_check_animation(closing.animations.get_animation(StringName(stage_name)), _fixture.cutscenes["expert_" + stage_name], stage_name)
	closing.stage = ExpertClosing.Stage.WAIT
	closing.finish()


func test_the_voyager_closing_animation_has_the_old_length_and_moments_for_every_starting_place() -> void:
	for timeline_name: String in _fixture.cutscenes:
		var expected: Dictionary = _fixture.cutscenes[timeline_name]
		if not expected.has("start"):
			continue
		var closing: VoyagerClosing = auto_free(load(VOYAGER).instantiate())
		add_child(closing)
		var start: Array = expected.start
		closing.start(int(start[0]), int(start[1]), int(start[2]))
		_check_animation(closing.animations.get_animation(&"closing"), expected, timeline_name)
		closing.skip()
