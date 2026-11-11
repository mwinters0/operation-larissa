class_name TestOpeningLegacy
extends GdUnitTestSuite
## (The legacy half: the opening on the original's timelines. The same cutscenes on dev's own: tests/engine/test_opening.gd.)
## Teaches: testing cutscenes without watching them. An `AnimationPlayer` finds its nodes by PATH, so the
## commonest cutscene bug is a track whose path matches no node (it fails silently). These tests check that
## every track of every built animation resolves, that the segments obey the director's interface (`advance`,
## `skip`, `finished`), and that the director leads to the sign-in screen.

const NEWS := "res://src/story/news_cartoon.tscn"
const TITLE := "res://src/story/title_scene.tscn"
const PAGES := "res://src/story/story_pages.tscn"
const OPENING := "res://src/story/opening.tscn"

## The three clocks of the opening, in seconds: the cartoon redraws every 10 ticks of the original's 73 Hz timer, the ship scene
## every 12, and each title picture holds for 292. (The numbers themselves are in data/story/; tests/legacy/test_cutscene_timing.gd pins
## them. These are the test's own reading of the original, so that a wrong timeline cannot make its own test agree.)
const NEWS_STEP := 10.0 / 73.0
const TITLE_STEP := 12.0 / 73.0
const HOLD_SECONDS := 292.0 / 73.0
const TITLE_FRAMES := 163


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func before_test() -> void:
	SceneRouter.dry_run = true
	SceneRouter.last_path = ""
	Audio.stop_music()


func after_test() -> void:
	SceneRouter.dry_run = false
	Audio.stop_music()
	Audio.stop_voice()


## True when every track of every animation of `player` names a node (and for value tracks a property) that exists.
func _unresolved_tracks(player: AnimationPlayer) -> PackedStringArray:
	var missing := PackedStringArray()
	var root := player.get_node(player.root_node)
	for animation_name in player.get_animation_list():
		var animation := player.get_animation(animation_name)
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			var node := root.get_node_or_null(NodePath(path.get_concatenated_names()))
			if node == null:
				missing.append("%s: %s" % [animation_name, path])
			elif animation.track_get_type(track) == Animation.TYPE_VALUE and path.get_concatenated_subnames() != "":
				var property := String(path.get_subname(0))
				if not property in node:
					missing.append("%s: %s has no property %s" % [animation_name, node.name, property])
	return missing


func test_news_cartoon_builds_and_every_track_finds_its_node() -> void:
	var news: NewsCartoon = auto_free(load(NEWS).instantiate())
	add_child(news)
	assert_array(_unresolved_tracks(news.script_player)).is_empty()
	assert_array(_unresolved_tracks(news.ambient)).is_empty()
	# 21 dots of the capsule's trail, 6 bulletins typed after the empty first 3.4 s, 11 speech clips
	assert_int(news._dots.size()).is_equal(21)
	assert_float(news.script_player.get_animation(&"news").length).is_greater(40.0)
	assert_int(Catalog.voice_cues().clips("opening_cartoon").size()).is_equal(11)


func test_the_six_bulletins_are_the_original_wording() -> void:
	assert_str(NewsCartoon.bulletin(0)).starts_with("RED ALERT")
	assert_str(NewsCartoon.bulletin(5)).contains("OPERATION NEPTUNE")
	var group_total := 0
	for group in NewsCartoon.speech_groups():
		group_total += int(group[1])
	assert_int(group_total).is_equal(11)


func test_news_cartoon_skip_ends_it_once() -> void:
	var news: NewsCartoon = auto_free(load(NEWS).instantiate())
	add_child(news)
	var count := [0]
	news.finished.connect(func() -> void: count[0] += 1)
	news.advance()
	news.skip()
	assert_int(count[0]).is_equal(1)
	assert_bool(news.script_player.is_playing()).is_false()


func test_title_scene_phases_and_choice() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	assert_array(_unresolved_tracks(title.animations)).is_empty()
	assert_int(title.phase).is_equal(TitleScene.Phase.SHIP)
	assert_float(title.animations.get_animation(&"ship").length).is_equal_approx(163.0 * 12.0 / 73.0, 0.01)
	# the ship sails right across the screen and stands still (x = 56) while the sub is dropped
	title.animations.seek(57.0 * TITLE_STEP, true)
	assert_float(title.ship.position.x).is_equal(56.0)
	title.animations.seek(80.0 * TITLE_STEP, true)
	assert_float(title.ship.position.x).is_equal(56.0)
	# Enter leaves the ship scene for the reveal, each further Enter ends one hold; at the prompt it means Intro
	# (G30: `TitleRevealText` 0x42a211 / `WaitEnterSpaceEscOrTicks` 0x428fbe wait twice up to 292 ticks)
	title.advance()
	assert_int(title.phase).is_equal(TitleScene.Phase.REVEAL)
	assert_bool(title.prompt.visible).is_false()
	var count := [0]
	title.finished.connect(func() -> void: count[0] += 1)
	title.advance()                                       # "Presents" -> "OPERATION"
	assert_int(title.phase).is_equal(TitleScene.Phase.REVEAL)
	assert_int(count[0]).is_equal(0)
	title.advance()                                       # "OPERATION" -> "NEPTUNE" + the prompt
	assert_int(title.phase).is_equal(TitleScene.Phase.PROMPT)
	assert_bool(title.prompt.visible).is_true()
	assert_int(count[0]).is_equal(0)
	title.advance()
	assert_bool(title.wants_intro).is_true()
	assert_int(count[0]).is_equal(1)


func _title_visible(title: TitleScene) -> Array:
	var names := ["Presents", "Operation", "Neptune", "Copyright"]
	return names.map(func(n: String) -> bool: return (title.stage.get_node(n) as Sprite2D).visible)


## G30: Enter ends only the hold that is running; it never skips a picture and never jumps to the finished title.
func test_enter_in_the_reveal_ends_one_hold_at_a_time() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	title.advance()                                       # out of the ship scene: "Presents" first
	title.animations.seek(0.1, true)
	assert_array(_title_visible(title)).is_equal([true, false, false, false])
	title.advance()                                       # 1st hold over: "OPERATION" alone
	assert_array(_title_visible(title)).is_equal([false, true, false, false])
	assert_int(title.phase).is_equal(TitleScene.Phase.REVEAL)
	assert_float(title.animations.current_animation_position).is_greater(HOLD_SECONDS)
	assert_float(title.animations.current_animation_position).is_less(HOLD_SECONDS + 0.1)
	title.advance()                                       # 2nd hold over: "NEPTUNE", the copyright and the prompt
	assert_array(_title_visible(title)).is_equal([false, true, true, true])
	assert_int(title.phase).is_equal(TitleScene.Phase.PROMPT)
	assert_bool(title.prompt.visible).is_true()
	assert_bool(title.done).is_false()


func test_enter_in_the_middle_of_the_second_hold_goes_straight_to_the_prompt() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	title.advance()
	title.animations.seek(HOLD_SECONDS + 1.5, true)
	title.advance()
	assert_int(title.phase).is_equal(TitleScene.Phase.PROMPT)
	assert_array(_title_visible(title)).is_equal([false, true, true, true])


func test_space_and_escape_leave_the_opening_from_every_part_of_the_title() -> void:
	for steps in 3:
		var title: TitleScene = auto_free(load(TITLE).instantiate())
		add_child(title)
		for i in steps:
			title.advance()
		title.skip()
		assert_bool(title.done).is_true()
		assert_bool(title.wants_intro).is_false()


func test_title_scene_start_means_no_story() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	title.advance()
	title.skip()
	assert_bool(title.wants_intro).is_false()
	assert_bool(title.done).is_true()


func test_story_pages_show_nine_pages_in_order() -> void:
	var story: StoryPages = auto_free(load(PAGES).instantiate())
	add_child(story)
	assert_array(_unresolved_tracks(story.animations)).is_empty()
	assert_int(Catalog.story_script().pages.size()).is_equal(9)
	await await_idle_frame()
	assert_int(story.page_index).is_equal(0)
	assert_object(story.caption.texture).is_not_null()
	for expected in range(1, 9):
		story.advance()
		await await_idle_frame()
		assert_int(story.page_index).is_equal(expected)
	story.advance()                                       # the last Enter ends the story
	await await_idle_frame()
	assert_bool(story.done).is_true()


## One Enter ends one page. Cutting the speech off ends `Audio.speak` inside `stop_voice`; when the speech had counted its whole hold already
## (pages 0, 1, 4 and 6 have speech as long as the hold) the page's own clock then ends the page, and `advance` must not end the next one too.
func test_one_enter_ends_exactly_one_page_also_when_the_speech_already_counted_the_whole_hold() -> void:
	Audio.apply_profile(null)                              # (the voice on: the page speaks)
	var story: StoryPages = auto_free(load(PAGES).instantiate())
	add_child(story)
	await await_idle_frame()
	assert_bool(Audio.is_voice_playing()).is_true()
	assert_int(story.page_index).is_equal(0)
	Audio.speech_ticks = 100000                            # (as if the page had been spoken to its end: nothing of the hold is left)
	story.advance()
	assert_int(story.page_index).is_equal(1)
	Audio.speech_ticks = 100000
	story.advance()
	assert_int(story.page_index).is_equal(2)
	story.skip()


## G31: `OpeningSequence` (0x42b16b) keeps the whole-screen hotspot 0xd for the whole opening; a left-button RELEASE anywhere is
## Enter, a press is nothing.
func _mouse(opening: Control, position: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	opening._input(event)


func test_a_click_goes_on_in_every_story_page() -> void:
	var opening: Opening = auto_free(load(OPENING).instantiate())
	opening.go_to_sign_in = false
	add_child(opening)
	await await_idle_frame()
	opening.current.skip()                                # (the director would go on to the title: play the parts by hand)
	await await_idle_frame()
	var title := opening.current as TitleScene
	assert_object(title).is_not_null()
	title.advance()
	title.advance()
	title.advance()
	title.advance()                                       # Intro
	await await_idle_frame()
	var story := opening.current as StoryPages
	assert_object(story).is_not_null()
	await await_idle_frame()
	assert_int(story.page_index).is_equal(0)
	_mouse(opening, Vector2(320, 200), true)              # a press does nothing
	assert_int(story.page_index).is_equal(0)
	for expected in range(1, 9):
		_mouse(opening, Vector2(500, 300), false)         # a release anywhere: Enter
		await await_idle_frame()
		assert_int(story.page_index).is_equal(expected)
	assert_bool(story.click_label.visible).is_true()      # "Click to go on."
	_mouse(opening, Vector2(10, 10), false, MOUSE_BUTTON_RIGHT)    # not the right button
	assert_bool(story.done).is_false()
	_mouse(opening, Vector2(10, 10), false)               # the last page
	assert_bool(story.done).is_true()


func test_a_click_is_enter_in_the_cartoon_and_the_ship_scene_and_the_reveal() -> void:
	var opening: Opening = auto_free(load(OPENING).instantiate())
	opening.go_to_sign_in = false
	add_child(opening)
	await await_idle_frame()
	var cartoon := opening.current as NewsCartoon
	_mouse(opening, Vector2(100, 100), true)
	assert_bool(cartoon.done).is_false()
	_mouse(opening, Vector2(100, 100), false)
	assert_bool(cartoon.done).is_true()
	await await_idle_frame()
	var title := opening.current as TitleScene
	assert_int(title.phase).is_equal(TitleScene.Phase.SHIP)
	_mouse(opening, Vector2(600, 20), false)
	assert_int(title.phase).is_equal(TitleScene.Phase.REVEAL)
	_mouse(opening, Vector2(600, 20), false)
	_mouse(opening, Vector2(600, 20), false)
	assert_int(title.phase).is_equal(TitleScene.Phase.PROMPT)
	assert_bool(title.done).is_false()


func test_the_prompt_buttons_act_on_the_press_and_a_click_elsewhere_is_intro() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	title.advance()
	title.advance()
	title.advance()
	await await_idle_frame()
	assert_int(title.phase).is_equal(TitleScene.Phase.PROMPT)
	assert_int(title.start_button.action_mode).is_equal(BaseButton.ACTION_MODE_BUTTON_PRESS)    # 0x8975 = the left DOWN code
	assert_int(title.intro_button.action_mode).is_equal(BaseButton.ACTION_MODE_BUTTON_PRESS)
	# the release over a button is the button's own hotspot (0x975 / 0x977): nobody answers it
	title.click(title.start_button.get_global_rect().get_center())
	title.click(title.intro_button.get_global_rect().get_center())
	assert_bool(title.done).is_false()
	title.click(Vector2(320, 100))                        # anywhere else: hotspot 0xd = Enter = Intro
	assert_bool(title.done).is_true()
	assert_bool(title.wants_intro).is_true()


func test_a_press_on_the_start_button_chooses_start() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	title.advance()
	title.advance()
	title.advance()
	title.start_button.button_down.emit()
	title.start_button.pressed.emit()
	assert_bool(title.done).is_true()
	assert_bool(title.wants_intro).is_false()


## Deliberate deviation from the original (DESIGN 2.1): the release that ends the click on Intro does not skip story page 1.
func test_the_release_after_the_intro_press_does_not_skip_story_page_1() -> void:
	var opening: Opening = auto_free(load(OPENING).instantiate())
	opening.go_to_sign_in = false
	add_child(opening)
	await await_idle_frame()
	opening.current.advance()
	await await_idle_frame()
	var title := opening.current as TitleScene
	title.advance()
	title.advance()
	title.advance()
	var intro_at := title.intro_button.get_global_rect().get_center()
	_mouse(opening, intro_at, true)                       # the press (the button reacts to it) ...
	title.intro_button.pressed.emit()
	await await_idle_frame()
	var story := opening.current as StoryPages
	assert_object(story).is_not_null()
	await await_idle_frame()
	_mouse(opening, intro_at, false)                      # ... and its release: swallowed
	await await_idle_frame()
	assert_int(story.page_index).is_equal(0)
	_mouse(opening, Vector2(300, 200), true)              # a later click is an Enter again
	_mouse(opening, Vector2(300, 200), false)
	await await_idle_frame()
	assert_int(story.page_index).is_equal(1)


func test_the_teletype_wraps_the_whole_bulletin_before_it_is_typed() -> void:
	var news: NewsCartoon = auto_free(load(NEWS).instantiate())
	add_child(news)
	await await_idle_frame()
	var label := news.teletype
	assert_int(label.visible_characters_behavior).is_equal(TextServer.VC_CHARS_AFTER_SHAPING)
	label.text = NewsCartoon.bulletin(0)
	label.visible_ratio = 1.0
	await await_idle_frame()
	var full_lines := label.get_line_count()
	assert_int(full_lines).is_greater(1)
	# however little is revealed, the line breaks stay where the full text puts them
	for ratio in [0.05, 0.3, 0.55, 0.8]:
		label.visible_ratio = ratio
		await await_idle_frame()
		assert_int(label.get_line_count()).is_equal(full_lines)


func test_the_opening_stands_still_while_the_window_is_inactive() -> void:
	var opening: Opening = auto_free(load(OPENING).instantiate())
	add_child(opening)
	await await_idle_frame()
	var cartoon := opening.current
	assert_bool(cartoon.can_process()).is_true()
	opening.set_window_active(false)                       # (MainWindowProc 0x41312f: WM_ACTIVATE -> PauseSoundOnDeactivate)
	assert_bool(get_tree().paused).is_true()
	assert_bool(opening.can_process()).is_true()           # the director hears the focus come back
	assert_bool(cartoon.can_process()).is_false()          # animations, tweens and the timers of the part stop
	assert_bool((cartoon as NewsCartoon).script_player.can_process()).is_false()
	opening.set_window_active(true)
	assert_bool(get_tree().paused).is_false()
	assert_bool(cartoon.can_process()).is_true()


func test_no_effect_starts_while_the_window_is_inactive() -> void:
	var old_enabled := WindowFocus.enabled
	WindowFocus.enabled = true
	Audio.apply_profile(null)
	Audio.stop_sfx()
	Audio.pause_sound_on_deactivate()
	Audio.play_sfx(&"correct")
	assert_int(Audio.busy_sfx_players()).is_equal(0)
	Audio.resume_sound_on_activate()
	Audio.play_sfx(&"correct")
	assert_int(Audio.busy_sfx_players()).is_equal(1)
	Audio.stop_sfx()
	WindowFocus.enabled = old_enabled


func test_every_story_picture_exists() -> void:
	var script: StoryScript = Catalog.story_script()
	assert_object(Assets.ui_picture(script.background)).is_not_null()
	for picture in script.ring_pictures:
		assert_object(Assets.ui_picture(picture)).is_not_null()
	for i in script.pages.size():
		var page := script.pages[i]
		assert_object(Assets.ui_picture(page.heading)).is_not_null()
		assert_object(Assets.ui_picture(page.frame)).is_not_null()
		assert_object(Assets.ui_picture(page.caption)).is_not_null()
		assert_int(page.extra_positions.size()).is_equal(page.extra_pictures.size())
		for picture in page.extra_pictures:
			assert_object(Assets.ui_picture(picture)).is_not_null()
		assert_int(Catalog.voice_cues().story_page(i).size()).is_greater(0)


func test_opening_skip_leads_to_sign_in() -> void:
	var opening: Opening = auto_free(load(OPENING).instantiate())
	add_child(opening)
	await await_idle_frame()
	assert_object(opening.current).is_instanceof(NewsCartoon)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	opening._unhandled_key_input(key)
	await await_idle_frame()
	await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)


func test_opening_enter_walks_through_the_parts() -> void:
	var opening: Opening = auto_free(load(OPENING).instantiate())
	add_child(opening)
	await await_idle_frame()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	opening._unhandled_key_input(enter)                    # the cartoon ends
	await await_idle_frame()
	assert_object(opening.current).is_instanceof(TitleScene)
	opening._unhandled_key_input(enter)                    # the ship scene ends: "Presents"
	opening._unhandled_key_input(enter)                    # "OPERATION"
	opening._unhandled_key_input(enter)                    # "NEPTUNE" and the prompt
	opening._unhandled_key_input(enter)                    # Intro
	await await_idle_frame()
	assert_object(opening.current).is_instanceof(StoryPages)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	opening._unhandled_key_input(space)
	await await_idle_frame()
	await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)


# --- the drop of the mini-sub (user report: "the submarine follows the ship impossibly") -----------------

func _title_at(title: TitleScene, frame: int) -> void:
	title.animations.seek(frame * TITLE_STEP, true)


func test_the_sub_hangs_then_falls_and_sinks_out_of_sight() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	var sub: Sprite2D = title.stage.get_node("MiniSub")
	_title_at(title, 60)                                  # hanging from the crane, fully drawn
	assert_bool(sub.visible).is_true()
	assert_float(sub.region_rect.size.y).is_equal(44.0)
	var hanging_y := sub.global_position.y
	_title_at(title, 70)                                  # falling: 6 px per frame from frame 69
	assert_float(sub.global_position.y).is_equal(hanging_y + 12.0)
	_title_at(title, 74)                                  # the water line (row 312) cuts it off from below
	assert_float(sub.region_rect.size.y).is_equal(39.0)
	assert_float(sub.global_position.y + sub.region_rect.size.y).is_equal(313.0)
	_title_at(title, 80)
	assert_float(sub.region_rect.size.y).is_equal(3.0)
	for frame in range(81, TITLE_FRAMES):            # gone for good, however far the ship sails on
		_title_at(title, frame)
		assert_bool(sub.visible).is_false()


func test_the_sub_does_not_move_with_the_ship_once_dropped() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	var sub: Sprite2D = title.stage.get_node("MiniSub")
	_title_at(title, 76)                                  # sinking while the ship stands still
	var dropped_y := sub.global_position.y
	var ship_y := title.ship.position.y
	_title_at(title, 78)
	assert_float(title.ship.position.y).is_equal(ship_y)
	assert_float(sub.global_position.y).is_equal(dropped_y + 12.0)   # its own y, not the ship's
	_title_at(title, 120)                                 # ship moving on, 8 px per frame, wobbling 2 px
	assert_float(title.ship.position.x).is_greater(56.0)
	assert_float(sub.global_position.y).is_greater_equal(318.0)      # still below the waterline: it never rose again
	assert_bool(sub.visible).is_false()


func test_the_splash_follows_the_sub_and_has_its_sound() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	var left: Sprite2D = title.stage.get_node("SplashLeft")
	var animation := title.animations.get_animation(&"ship")
	var sound_times := PackedFloat32Array()
	for track in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_METHOD:
			for key in animation.track_get_key_count(track):
				sound_times.append(animation.track_get_key_time(track, key))
	assert_array(sound_times).is_equal(PackedFloat32Array([73.0 * TITLE_STEP]))
	_title_at(title, 74)
	assert_bool(left.visible).is_false()                  # the sound comes two frames before the first picture
	for index in 5:
		_title_at(title, 75 + index)
		assert_bool(left.visible).is_true()
		assert_object(left.texture).is_equal(Assets.ui_picture(StringName("spray_%d" % index)))
	_title_at(title, 80)
	assert_bool(left.visible).is_false()


func test_enter_during_the_ship_scene_leaves_no_ship_part_behind() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	_title_at(title, 76)                                  # the splash is showing and the spray is visible
	title.advance()
	assert_bool(title.ship.visible).is_false()
	assert_bool((title.stage.get_node("Spray") as Sprite2D).visible).is_false()
	assert_bool((title.stage.get_node("SplashLeft") as Sprite2D).visible).is_false()
	assert_bool((title.stage.get_node("SplashRight") as Sprite2D).visible).is_false()


func test_the_title_pictures_appear_at_once_without_a_wipe() -> void:
	var title: TitleScene = auto_free(load(TITLE).instantiate())
	add_child(title)
	var reveal := title.animations.get_animation(&"reveal")
	assert_float(reveal.length).is_greater(2.0 * HOLD_SECONDS)
	for track in reveal.get_track_count():
		assert_str(String(reveal.track_get_path(track)).get_slice(":", 1)).is_not_equal("region_rect")
	title.animations.play(&"reveal")
	title.animations.seek(0.1, true)
	assert_bool((title.stage.get_node("Presents") as Sprite2D).visible).is_true()
	assert_bool((title.stage.get_node("Operation") as Sprite2D).visible).is_false()
	title.animations.seek(HOLD_SECONDS + 0.1, true)
	assert_bool((title.stage.get_node("Presents") as Sprite2D).visible).is_false()
	assert_bool((title.stage.get_node("Operation") as Sprite2D).visible).is_true()
	title.animations.seek(2.0 * HOLD_SECONDS + 0.05, true)
	assert_bool((title.stage.get_node("Neptune") as Sprite2D).visible).is_true()
	assert_bool((title.stage.get_node("Copyright") as Sprite2D).visible).is_true()


# --- the news cartoon's crew and lights ----------------------------------------------------------------

func _news_at(news: NewsCartoon, seconds: float) -> void:
	news.script_player.seek(seconds, true)


func test_the_man_on_the_left_appears_after_30_seconds_and_walks_in() -> void:
	var news: NewsCartoon = auto_free(load(NEWS).instantiate())
	add_child(news)
	var walker: Sprite2D = news.stage.get_node("Crew4")
	_news_at(news, 0.0)
	assert_bool(walker.visible).is_false()
	_news_at(news, 29.9)
	assert_bool(walker.visible).is_false()
	_news_at(news, 30.05)                                 # call 220 = 2190 ticks
	assert_bool(walker.visible).is_true()
	assert_float(walker.position.x).is_equal(0.0)
	assert_bool(walker.flip_h).is_true()                  # facing right
	_news_at(news, 30.05 + 9.0 * NEWS_STEP)        # 9 calls later: 9 x 12 px
	assert_float(walker.position.x).is_equal(108.0)
	assert_int([1024, 1025, 1026].has(_picture_id(walker)) as int).is_equal(1)
	_news_at(news, 30.05 + 40.0 * NEWS_STEP)       # standing in the middle of the console
	assert_float(walker.position.x).is_equal(324.0)
	_news_at(news, 41.0)                                  # walking on to the right ...
	assert_float(walker.position.x).is_greater(324.0)
	for member in 4:                                      # the others have been there from the start
		_news_at(news, 0.1)
		assert_bool((news.stage.get_node("Crew%d" % member) as Sprite2D).visible).is_true()


func _picture_id(sprite: Sprite2D) -> int:
	var path := Packs.source_of(sprite.texture)
	return int(path.get_file().get_basename().rsplit("_", true, 1)[1])          # <name>_<number>.png, or ui_<number>.png


func test_the_alarm_lights_come_on_one_after_the_other() -> void:
	var news: NewsCartoon = auto_free(load(NEWS).instantiate())
	add_child(news)
	var left: Sprite2D = news.stage.get_node("Alarm0")
	var centre: Sprite2D = news.stage.get_node("Alarm1")
	_news_at(news, 4.5)
	assert_bool(centre.visible).is_false()
	_news_at(news, 5.5)                                   # call 37 = 360 ticks
	assert_bool(centre.visible).is_true()
	assert_bool(left.visible).is_false()
	_news_at(news, 32.5)                                  # call 234 = 2330 ticks
	assert_bool(left.visible).is_true()


func test_the_capsule_trail_and_ring_follow_the_originals_calls() -> void:
	var news: NewsCartoon = auto_free(load(NEWS).instantiate())
	add_child(news)
	_news_at(news, 9.0 * NEWS_STEP)
	assert_bool((news._dots[0] as Sprite2D).visible).is_false()
	_news_at(news, 10.0 * NEWS_STEP + 0.01)        # the first dot is drawn in call 11 (t = 10 steps)
	assert_bool((news._dots[0] as Sprite2D).visible).is_true()
	assert_bool((news._dots[1] as Sprite2D).visible).is_false()
	var last_dot := (21 * 11 - 1) * NEWS_STEP
	_news_at(news, last_dot + 0.01)
	assert_bool((news._dots[20] as Sprite2D).visible).is_true()
	assert_bool(news._ring.visible).is_false()
	_news_at(news, last_dot + 6.0 * NEWS_STEP + 0.01)
	assert_bool(news._ring.visible).is_true()
