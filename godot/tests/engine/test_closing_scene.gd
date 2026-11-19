class_name TestClosingScene
extends GdUnitTestSuite
## Teaches: the end of a game is a scene FILE that a campaign names, played by the same segment as the opening. What a closing needs of the engine is scene data and verbs: no black backdrop (it is laid over the sector), keys and clicks
## read and dropped until the verb `listen`, picture sets of the engine by fixed names (`FrameSets`: the sub's, the creatures of the zone of the sector in play, which the director hands in), and a name the chain does not hold is told once
## and the generic finale plays. The dev pack's closing (`dev_closing`, two timelines and a stage of its own shape) is played through the real `Game` here; the legacy pack's Expert closing is pinned in tests/legacy/test_closing_sequences.gd.

const GAME_SCENE := "res://src/gameplay/game.tscn"
const FINALE_SECTOR := 160
const DEV_CLOSING := &"dev_closing"
const DEV_ZONE := 4

var _roster := Scratch.path("test_closing_scene_roster.json")
var _hall := Scratch.path("test_closing_scene_hall.json")

var _shelf: CampaignShelf
var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]


func before_test() -> void:
	_old_roster = SaveStore.roster_path
	_old_hall = SaveStore.hall_path
	_old_players = SaveStore.players.duplicate()
	SaveStore.roster_path = _roster
	SaveStore.hall_path = _hall
	SaveStore.players = []
	SaveStore.hall = HallOfFame.new()
	SceneRouter.dry_run = true
	SceneRouter.last_path = ""
	Audio.stop_music()
	TroubleLog.new_run()


func after_test() -> void:
	if _shelf != null:
		_shelf.remove()
		_shelf = null
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SaveStore.hall = HallOfFame.new()
	SceneRouter.dry_run = false
	GameState.profile = null
	GameClock.paused = false
	GameState.hints.reset()
	GameState.reset()
	Audio.stop_music()
	Audio.stop_voice()
	for path in [_roster, _hall]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _segment(scene_name: StringName = DEV_CLOSING, zone := DEV_ZONE) -> TimelineSegment:
	var segment: TimelineSegment = auto_free(TimelineSegment.of(scene_name, zone))
	add_child(segment)
	return segment


func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key


func _click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


## Every way the player has to end a scene that is deaf until `listen`, each as one call on the segment.
func _every_way_to_end() -> Dictionary[String, Callable]:
	return {
		"Enter": func(segment: TimelineSegment) -> void: segment.advance(),
		"Space / Escape": func(segment: TimelineSegment) -> void: segment.skip(),
		"a click the director forwards": func(segment: TimelineSegment) -> void: segment.click(Vector2(100, 100)),
		"any other key": func(segment: TimelineSegment) -> void: segment._unhandled_input(_key(KEY_A)),
		"a mouse press": func(segment: TimelineSegment) -> void: segment._unhandled_input(_click()),
	}


# --- keys and clicks are dropped until the verb `listen` -----------------------------------------------------------

func test_every_key_and_click_is_dropped_until_the_verb_listen() -> void:
	var ways := _every_way_to_end()
	for way: String in ways:
		var segment := _segment()
		assert_bool(segment.scene.deaf_until_listen).is_true()
		for each: Callable in ways.values():
			each.call(segment)
		assert_bool(segment.done).override_failure_message("%s ended the scene before `listen`" % way).is_false()
		assert_bool(segment.listening).is_false()


func test_from_the_verb_listen_any_key_or_click_ends_the_scene_once() -> void:
	var ways := _every_way_to_end()
	for way: String in ways:
		var segment := _segment()
		var count := [0]
		segment.finished.connect(func() -> void: count[0] += 1)
		segment.cue(&"listen")
		assert_bool(segment.listening).is_true()
		assert_bool(segment.done).is_false()
		(ways[way] as Callable).call(segment)
		(ways[way] as Callable).call(segment)
		assert_bool(segment.done).override_failure_message("%s did not end the scene after `listen`" % way).is_true()
		assert_int(count[0]).is_equal(1)


func test_a_key_that_is_held_down_or_let_go_is_no_key_press() -> void:
	var segment := _segment()
	segment.cue(&"listen")
	var echo := _key(KEY_A)
	echo.echo = true
	var release := _key(KEY_A)
	release.pressed = false
	var mouse_release := _click()
	mouse_release.pressed = false
	for event: InputEvent in [echo, release, mouse_release]:
		segment._unhandled_input(event)
	assert_bool(segment.done).is_false()


func test_a_scene_that_is_not_deaf_goes_on_with_enter_as_the_opening_does() -> void:
	var cartoon := _segment(&"news_cartoon", FrameSets.NO_ZONE)
	assert_bool(cartoon.scene.deaf_until_listen).is_false()
	cartoon._unhandled_input(_key(KEY_A))                                           # (any other key is not the scene's: the director reads Enter and Space)
	assert_bool(cartoon.done).is_false()
	cartoon.skip()
	assert_bool(cartoon.done).is_true()


func test_listen_is_a_verb_of_no_words() -> void:
	assert_int(StoryVerbs.VERBS[&"listen"]).is_equal(0)
	assert_str(StoryVerbs.problem(&"listen")).is_empty()
	assert_str(StoryVerbs.problem(&"listen now")).contains("takes 0 words after it")


# --- no backdrop: the scene is laid over the sector ----------------------------------------------------------------

func test_a_closing_has_no_backdrop_and_the_opening_has_its_black_one() -> void:
	var closing := _segment()
	assert_bool(closing.scene.backdrop).is_false()
	assert_object(closing.get_node_or_null("Backdrop")).is_null()
	assert_int(closing.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)                  # (the sector under it and the menu bar above it keep the mouse)
	var cartoon := _segment(&"news_cartoon", FrameSets.NO_ZONE)
	assert_bool(cartoon.scene.backdrop).is_true()
	assert_object((cartoon.get_node("Backdrop") as ColorRect).color).is_equal(Color.BLACK)


# --- the picture sets are the engine's, by fixed names ---------------------------------------------------------------

func test_the_table_of_picture_sets_offers_the_sub_always_and_a_zones_creatures_only_to_a_scene_over_a_sector() -> void:
	assert_array(FrameSets.SETS.keys()).is_equal([FrameSets.SUB, FrameSets.ZONE_CREATURES])
	assert_array(FrameSets.offered(FrameSets.NO_ZONE)).is_equal([FrameSets.SUB])
	assert_array(FrameSets.offered(Catalog.ZONE_COUNT)).is_equal([FrameSets.SUB])                  # (no such zone)
	assert_array(FrameSets.offered(DEV_ZONE)).is_equal([FrameSets.SUB, FrameSets.ZONE_CREATURES])
	assert_array(FrameSets.over_a_sector()).is_equal([FrameSets.SUB, FrameSets.ZONE_CREATURES])
	var sets := FrameSets.make(DEV_ZONE)
	assert_object(sets[FrameSets.SUB]).is_same(Catalog.sub_frames())
	assert_object(sets[FrameSets.ZONE_CREATURES]).is_same(Catalog.foes_frames(DEV_ZONE))
	assert_array(FrameSets.make(FrameSets.NO_ZONE).keys()).is_equal([FrameSets.SUB])
	assert_str(FrameSets.SUB).is_equal("sub")
	assert_str(FrameSets.ZONE_CREATURES).is_equal("zone_creatures")


func test_the_cast_gets_its_sets_and_the_zone_of_its_pictures_from_the_zone_handed_in() -> void:
	var holder: Node = auto_free(Node.new())
	var cast := CutsceneCast.of(holder, DEV_ZONE)
	assert_int(cast.frame_zone).is_equal(DEV_ZONE)
	assert_array(cast.frame_sets.keys()).is_equal(FrameSets.offered(DEV_ZONE))
	assert_object(cast.sub_tuning).is_same(GameState.tuning.sub)
	var bare := CutsceneCast.of(holder)
	assert_int(bare.frame_zone).is_equal(FrameSets.NO_ZONE)
	assert_array(bare.frame_sets.keys()).is_equal([FrameSets.SUB])
	assert_int(cast.frame_number(&"hammerhead_swim_0")).is_equal(35)                         # (a picture of the zone's creatures, by its name in that zone)


func test_the_closing_is_handed_the_creatures_of_the_zone_and_the_opening_has_none() -> void:
	var closing := _segment()
	assert_object((closing.cast.node_of(&"creature") as AnimatedSprite2D).sprite_frames).is_same(Catalog.foes_frames(DEV_ZONE))
	assert_object((closing.cast.node_of(&"sub") as AnimatedSprite2D).sprite_frames).is_same(Catalog.sub_frames())
	assert_array(TroubleLog.session.told).is_empty()
	assert_array(_segment(&"news_cartoon", FrameSets.NO_ZONE).cast.frame_sets.keys()).is_equal([FrameSets.SUB])


func test_a_scene_with_no_zone_that_asks_for_the_creatures_of_the_zone_is_told_once_per_actor() -> void:
	var closing := _segment(DEV_CLOSING, FrameSets.NO_ZONE)
	assert_bool(closing.cast.has_actor(&"creature")).is_false()
	assert_bool(closing.cast.has_actor(&"sub")).is_true()
	var about_the_set: Array = TroubleLog.session.told.filter(func(line: String) -> bool: return line.contains("the picture set"))
	assert_array(about_the_set).has_size(2)                                                    # (the creature of each shot; the timelines that move them are told by `Cutscene`)
	for line: String in about_the_set:
		assert_str(line).contains("[story]").contains("pack 'dev'").contains("the picture set 'zone_creatures' is not one this scene hands in (sub)").contains("left out of the scene")


# --- what the scene file says is judged ---------------------------------------------------------------------------------

func _scene(timelines: Array[StringName], deaf: bool) -> StoryScene:
	var scene := StoryScene.new()
	scene.stage = &"dev_closing_stage"
	scene.timelines = timelines
	scene.deaf_until_listen = deaf
	scene.backdrop = false
	return scene


func test_the_dev_closing_scene_is_fine_and_a_looping_last_timeline_is_accepted() -> void:
	var scene := Catalog.story_scene(DEV_CLOSING)
	assert_array(Array(scene.unresolved())).is_empty()
	assert_bool(Catalog.story_timeline(scene.timelines[scene.timelines.size() - 1]).loop).is_true()
	assert_array(Array(_scene([&"dev_closing_film", &"dev_closing_wait"], true).unresolved())).is_empty()


func test_a_looping_timeline_that_is_not_the_last_is_told_because_the_ones_after_it_never_play() -> void:
	var lines := _scene([&"dev_closing_wait", &"dev_closing_film"], true).unresolved()
	assert_array(Array(lines)).is_equal(["lists the timeline 'dev_closing_wait' to play once, but it loops and is not the last: the timelines after it are never played"])


func test_a_scene_that_drops_every_key_but_never_listens_and_a_listen_with_nothing_to_wait_for_are_told() -> void:
	var never := _scene([&"dev_closing_film"], true).unresolved()
	assert_array(Array(never)).is_equal(["drops every key and click until the cue 'listen', which no timeline of it has: no key or click ends it, only the cue 'end'"])
	var needless := _scene([&"dev_closing_film", &"dev_closing_wait"], false).unresolved()
	assert_array(Array(needless)).is_equal(["has the cue 'listen', but does not drop keys until it (deaf_until_listen is off): the cue does nothing"])


# --- the campaign names the scene; the game plays it ------------------------------------------------------------------------

func _start(closing_scene: StringName) -> Game:
	var orchard := CampaignShelf.orchard()
	orchard.finales = PackedInt32Array([FINALE_SECTOR])                  # a finale with a treasure and a finale screen (dev's test sector)
	orchard.closing_scene = closing_scene
	_shelf = CampaignShelf.new([orchard])
	var player: PlayerProfile = SaveStore.add_player_in("Tester", Catalog.campaign(&"orchard"))
	player.hints_enabled = false
	player.progress = FINALE_SECTOR * 2
	player.tries = 5
	GameState.profile = player
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var ticks := 0
	while not game.world.sim.sub.controlled and ticks < 100:
		game.world.tick()
		ticks += 1
	assert_bool(game.world.sim.sub.controlled).override_failure_message("the launch never ended").is_true()
	return game


func _dock_at_the_finale(game: Game) -> void:
	game.world.foe_context.semaphore |= 1 << SimWorld.FINALE_SEMAPHORE_BIT
	game.world.load_screen(Catalog.sector(FINALE_SECTOR).finale_screen)
	game.world.tick()


## The Hall of Fame follows the closing: the winner is in it, and closing it goes to the sign-in screen (the dialog is closed here so that no test leaves a modal that holds the clock).
func _hall_then_sign_in(game: Game) -> void:
	await await_idle_frame()
	assert_int(SaveStore.hall.entries.size()).is_equal(1)
	assert_str(SaveStore.hall.entries[0].campaign_id).is_equal(&"orchard")
	var view := game.dialog_layer.get_child(game.dialog_layer.get_child_count() - 1) as HallOfFameView
	assert_object(view).is_not_null()
	view.close()
	await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)


func test_the_closing_scene_a_campaign_names_is_played_over_the_sector_in_play_and_the_song_stops_with_it() -> void:
	var game := await _start(DEV_CLOSING)
	_dock_at_the_finale(game)
	var closing := game.closing as TimelineSegment
	assert_object(closing).is_not_null()
	assert_str(closing.scene_name).is_equal(DEV_CLOSING)
	assert_int(closing.zone).is_equal(game.world.sector.zone)                                  # the zone of the sector in play, handed in by the view
	assert_array(closing.cast.frame_sets.keys()).is_equal(FrameSets.offered(game.world.sector.zone))
	assert_object(closing.get_parent()).is_same(game.problem_layer)
	assert_bool(game.world.sim.sub.active).is_false()
	assert_str(Audio.song).is_equal(&"closing")                                                 # the scene's `song`
	game._unhandled_input(_key(KEY_ENTER))                                                      # Enter and Space are thrown away until `listen`
	game._unhandled_input(_key(KEY_SPACE))
	assert_object(game.closing).is_same(closing)
	assert_int(SaveStore.hall.entries.size()).is_equal(0)
	closing.cue(&"listen")                                                                      # (the real thing: the first moment of the last timeline)
	game._unhandled_input(_key(KEY_ENTER))
	assert_object(game.closing).is_null()
	assert_str(Audio.song).is_equal(AudioService.NO_MUSIC)                                       # not carried into the Hall of Fame
	await _hall_then_sign_in(game)
	assert_array(TroubleLog.session.told).is_empty()


func test_the_dev_closing_reaches_its_wait_and_a_key_there_ends_the_game_through_the_hall_of_fame() -> void:
	var game := await _start(DEV_CLOSING)
	_dock_at_the_finale(game)
	var closing := game.closing as TimelineSegment
	closing.script_player.advance(closing.script_player.get_animation(&"dev_closing_film").length + 0.01)
	await await_idle_frame()
	assert_bool(closing.listening).is_true()
	closing._unhandled_input(_key(KEY_A))                                                       # any key, which the director (`Game`) does not read
	assert_object(game.closing).is_null()
	await _hall_then_sign_in(game)


func test_a_closing_scene_no_pack_holds_is_told_once_with_the_campaign_and_the_generic_finale_plays() -> void:
	var game := await _start(&"no_such_closing")
	_dock_at_the_finale(game)
	assert_object(game.closing).is_instanceof(GenericFinale)
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("[story]").contains("campaign 'orchard'").contains("closing_scene 'no_such_closing'").contains("data/story/no_such_closing.tres").contains("the generic finale plays")
	assert_bool(TroubleLog.session.tell(TroubleLog.session.told[0])).is_false()                    # (the same cause is not told again)
	game._unhandled_input(_key(KEY_ENTER))
	assert_object(game.closing).is_null()
	await _hall_then_sign_in(game)


func test_a_campaign_with_no_closing_scene_plays_the_generic_finale_and_tells_nothing() -> void:
	var game := await _start(&"")
	_dock_at_the_finale(game)
	assert_object(game.closing).is_instanceof(GenericFinale)
	assert_array(TroubleLog.session.told).is_empty()
	game._unhandled_input(_key(KEY_ENTER))
	await _hall_then_sign_in(game)


# --- what a chain needs follows from the campaigns -----------------------------------------------------------------------

func test_what_the_closings_name_is_derived_from_the_campaigns_of_the_chain() -> void:
	var named := PackNeeds.named_by_closings()
	assert_str(named["data/story/dev_closing.tres"]).is_equal("StoryScene")
	assert_str(named["data/story/dev_closing_stage.tres"]).is_equal("CutsceneStage")
	assert_str(named["data/story/dev_closing_film.tres"]).is_equal("CutsceneTimeline")
	assert_str(named["data/story/dev_closing_wait.tres"]).is_equal("CutsceneTimeline")
	assert_str(PackNeeds.class_of("data/story/dev_closing_wait.tres")).is_equal("CutsceneTimeline")
	for rel: String in PackNeeds.FILES:
		assert_bool(rel.contains("expert") or rel.contains("dev_closing")).override_failure_message("%s is listed in FILES, but a campaign names it" % rel).is_false()
	assert_bool(PackNeeds.FILES.has("data/story/voyager_closing_stage.tres")).is_true()           # (the Voyager closing is still the game's: its files are listed)


func test_a_campaign_that_names_no_scene_the_chain_holds_still_names_the_file() -> void:
	var orchard := CampaignShelf.orchard()
	orchard.closing_scene = &"no_such_closing"
	_shelf = CampaignShelf.new([orchard])
	var named := PackNeeds.named_by_closings()
	assert_str(named["data/story/no_such_closing.tres"]).is_equal("StoryScene")
	assert_bool(named.has("data/story/no_such_closing_stage.tres")).is_false()                      # (a scene that is not there names nothing)
	assert_bool(PackNeeds.hard(PackNeeds.gaps(Packs.chain())).is_empty()).is_true()                    # (and is no gap: the generic finale plays)
