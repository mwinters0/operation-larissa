class_name TestCutsceneTiming
extends GdUnitTestSuite
## Teaches: pinning a behaviour while its implementation changes, without committing the original's numbers. The cutscenes' `Animation` tracks
## are data (`CutsceneTimeline`s, played by animations that the scenes build at run time). The rule of that data is "the same
## pictures at the same times", so `fixtures/cutscene_timing.json` holds one SHA-256 per cutscene of its timing record
## (`CutsceneTimingRecord`: the length, whether it loops, EVERY moment at which anything changes and every sound and event, in
## thousandths of a tick of the original's 73 Hz timer). These tests hash the legacy pack's timelines and the animations that the scenes
## really build from them and compare; a duration that holds up play cannot drift without one of them failing. The fixture is written from the
## legacy pack by `tools/import/godot/write_cutscene_timing.gd` and holds no tick. The fade of a story page is ours, not the original's, so
## it is checked by what it is made of.

const FIXTURE := "res://tests/fixtures/cutscene_timing.json"
const TICKS := 73.0
const TOLERANCE := 0.0015                      # ticks

const NEWS := "res://src/story/news_cartoon.tscn"
const TITLE := "res://src/story/title_scene.tscn"
const PAGES := "res://src/story/story_pages.tscn"
const VOYAGER := "res://src/story/voyager_closing.tscn"
const EXPERT := "res://src/story/expert_closing.tscn"

## The data files by the name the fixture uses.
const TIMELINES := ["title_ship", "title_reveal", "expert_hoist", "expert_deck", "expert_wait", "news_cartoon"]

## (The choreography is the legacy pack's and loaded, not preloaded: this file compiles without the game.)
const STORY_DIR := LegacyPack.ROOT + "data/story/"

var _fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	Audio.stop_music()


func after_test() -> void:
	Audio.stop_music()
	Audio.stop_voice()


## The hash of a cutscene's record in the fixture.
func _wanted(timeline_name: String) -> String:
	return _fixture.cutscenes[timeline_name].sha256


func _check_timeline(timeline: CutsceneTimeline, timeline_name: String) -> void:
	assert_str(CutsceneTimingRecord.digest(CutsceneTimingRecord.of_timeline(timeline))).override_failure_message("%s: the timeline's timing record" % timeline_name).is_equal(_wanted(timeline_name))


## The animation's record: its length and key times, and its method calls as sounds and events.
func _check_animation(animation: Animation, timeline_name: String) -> void:
	assert_str(CutsceneTimingRecord.digest(CutsceneTimingRecord.of_animation(animation))).override_failure_message("%s: the animation's timing record" % timeline_name).is_equal(_wanted(timeline_name))


# --- the data -------------------------------------------------------------------------------------------------------

func test_the_fixture_says_what_it_is() -> void:
	assert_float(float(_fixture.ticks_per_second)).is_equal(CutsceneTimeline.TICKS_PER_SECOND)
	assert_int(_fixture.cutscenes.size()).is_equal(12)
	for timeline_name: String in _fixture.cutscenes:
		assert_str(_wanted(timeline_name)).has_length(64)


func test_the_timelines_of_the_data_files_have_the_recorded_lengths_and_moments() -> void:
	for timeline_name: String in TIMELINES:
		_check_timeline(load(STORY_DIR + timeline_name + ".tres"), timeline_name)


func test_the_voyager_flight_has_the_recorded_length_and_moments_for_every_starting_place() -> void:
	var script: VoyagerClosingScript = load(STORY_DIR + "voyager_closing_script.tres")
	var tried := 0
	for timeline_name: String in _fixture.cutscenes:
		var expected: Dictionary = _fixture.cutscenes[timeline_name]
		if expected.has("start"):
			var start: Array = expected.start
			_check_timeline(script.timeline(int(start[0]), int(start[1]), int(start[2])), timeline_name)
			tried += 1
	assert_int(tried).is_equal(5)


# --- the animations the scenes build -------------------------------------------------------------------------------------

func test_the_news_cartoon_animations_have_the_recorded_lengths_and_moments() -> void:
	var news: NewsCartoon = auto_free(load(NEWS).instantiate())
	add_child(news)
	_check_animation(news.script_player.get_animation(&"news"), "news_cartoon")
	_check_animation(news.ambient.get_animation(&"ambient"), "news_ambient")
	news.finish()


func test_the_title_scene_animations_have_the_recorded_lengths_and_moments() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	_check_animation(title.animations.get_animation(&"ship"), "title_ship")
	_check_animation(title.animations.get_animation(&"reveal"), "title_reveal")


## The fade of a page is ours (half a second long, a fade of 0.2 s), and the caption follows the pack's delay after the page.
func test_the_story_page_fade_is_made_of_the_fade_and_the_captions_delay() -> void:
	var story: StoryPages = auto_free(load(PAGES).instantiate())
	add_child(story)
	var animation := story.animations.get_animation(&"show")
	var fade := story.FADE_SECONDS * TICKS
	var delay := Catalog.story_script().caption_delay_ticks
	assert_float(animation.length * TICKS).is_equal_approx(0.5 * TICKS, TOLERANCE)
	assert_bool(animation.loop_mode == Animation.LOOP_NONE).is_true()
	var moments := {}
	for track in animation.get_track_count():
		for key in animation.track_get_key_count(track):
			moments[snappedf(animation.track_get_key_time(track, key) * TICKS, 0.001)] = true
	var found := moments.keys()
	found.sort()
	assert_array(found).has_size(3)
	assert_float(found[0]).is_equal(0.0)
	assert_float(found[1]).is_equal_approx(fade, TOLERANCE)
	assert_float(found[2]).is_equal_approx(fade + delay, TOLERANCE)
	story.skip()


func test_the_expert_closing_animations_have_the_recorded_lengths_and_moments() -> void:
	var closing: ExpertClosing = auto_free(load(EXPERT).instantiate())
	add_child(closing)
	for stage_name in ["hoist", "deck", "wait"]:
		_check_animation(closing.animations.get_animation(StringName(stage_name)), "expert_" + stage_name)
	closing.stage = ExpertClosing.Stage.WAIT
	closing.finish()


func test_the_voyager_closing_animation_has_the_recorded_length_and_moments_for_every_starting_place() -> void:
	for timeline_name: String in _fixture.cutscenes:
		var expected: Dictionary = _fixture.cutscenes[timeline_name]
		if not expected.has("start"):
			continue
		var closing: VoyagerClosing = auto_free(load(VOYAGER).instantiate())
		add_child(closing)
		var start: Array = expected.start
		closing.start(int(start[0]), int(start[1]), int(start[2]))
		_check_animation(closing.animations.get_animation(&"closing"), timeline_name)
		closing.skip()
