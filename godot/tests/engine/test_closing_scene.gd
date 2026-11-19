class_name TestClosingScene
extends GdUnitTestSuite
## Teaches: the end of a game is a scene FILE that a campaign names, played by the same segment as the opening. What a closing needs of the engine is scene data and verbs: no black backdrop (it is laid over the sector), keys and clicks
## read and dropped until the verb `listen`, picture sets of the engine by fixed names (`FrameSets`: the sub's, the creatures of the zone of the sector in play, which the director hands in), and a name the chain does not hold is told once
## and the generic finale plays. The dev pack's closing (`dev_closing`, two timelines and a stage of its own shape) is played through the real `Game` here; the legacy pack's Expert closing is pinned in tests/legacy/test_closing_sequences.gd.
## A closing may also FLY the sub and show the surface ship's message: a flight file among the scene's timelines is made at the start for the place the director hands in (`ScenePlace`), its last step is a mark that Enter goes to, and the verb
## `messages` shows the scene's pages in the message box (`dev_flight_closing`: a flight and two pages, played through `Game` and on its own; the legacy pack's Voyager closing is pinned in tests/legacy/test_closing_sequences.gd).

const GAME_SCENE := "res://src/gameplay/game.tscn"
const FINALE_SECTOR := 160
const DEV_CLOSING := &"dev_closing"
const DEV_ZONE := 4
const DEV_FLIGHT_CLOSING := &"dev_flight_closing"
const FLIGHT_AT := Vector2i(184, 212)                 # where the sub is when the flight begins, and the cell it shows
const FLIGHT_CELL := 6

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
	var segment: TimelineSegment = auto_free(TimelineSegment.of(scene_name, ScenePlace.over(zone)))
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
	assert_int(closing.place.zone).is_equal(game.world.sector.zone)                                  # the zone of the sector in play, handed in by the view
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
	assert_str(named["data/story/dev_flight_closing.tres"]).is_equal("StoryScene")               # (the dev pack's second closing is named by its campaign `test_c`, which has no finale)
	assert_str(named["data/story/dev_flight.tres"]).is_equal("SubFlight")
	for rel: String in PackNeeds.FILES:
		assert_bool(rel.contains("expert") or rel.contains("dev_closing")).override_failure_message("%s is listed in FILES, but a campaign names it" % rel).is_false()
	for rel: String in PackNeeds.FILES:
		assert_bool(rel.contains("voyager") or rel.contains("flight")).override_failure_message("%s is listed in FILES, but a campaign names it" % rel).is_false()


func test_a_campaign_that_names_no_scene_the_chain_holds_still_names_the_file() -> void:
	var orchard := CampaignShelf.orchard()
	orchard.closing_scene = &"no_such_closing"
	_shelf = CampaignShelf.new([orchard])
	var named := PackNeeds.named_by_closings()
	assert_str(named["data/story/no_such_closing.tres"]).is_equal("StoryScene")
	assert_bool(named.has("data/story/no_such_closing_stage.tres")).is_false()                      # (a scene that is not there names nothing)
	assert_bool(PackNeeds.hard(PackNeeds.gaps(Packs.chain())).is_empty()).is_true()                    # (and is no gap: the generic finale plays)


# --- a flight file among a scene's timelines: made at the start for the place the sub is in ----------------------------------

func _flight_segment(at := FLIGHT_AT, cell := FLIGHT_CELL) -> TimelineSegment:
	return _segment_at(DEV_FLIGHT_CLOSING, ScenePlace.over(DEV_ZONE, at, cell))


func _segment_at(scene_name: StringName, place: ScenePlace) -> TimelineSegment:
	var segment: TimelineSegment = auto_free(TimelineSegment.of(scene_name, place))
	add_child(segment)
	return segment


func test_one_resolver_answers_a_timeline_for_a_timeline_file_and_for_a_flight_file_made_for_the_place() -> void:
	var film := StoryScene.timeline_named(&"dev_closing_film")
	assert_object(film).is_same(Catalog.story_timeline(&"dev_closing_film"))                  # (a timeline file is itself)
	var flight := Catalog.story_flight(&"dev_flight")
	assert_object(Catalog.story_timeline(&"dev_flight")).is_null()                              # (a flight file is no timeline)
	assert_object(Catalog.story_flight(&"dev_closing_film")).is_null()
	var here := StoryScene.timeline_named(&"dev_flight", ScenePlace.over(DEV_ZONE, FLIGHT_AT, FLIGHT_CELL))
	assert_float(here.length).is_equal(flight.timeline(FLIGHT_AT.x, FLIGHT_AT.y, FLIGHT_CELL).length)
	var turned := StoryScene.timeline_named(&"dev_flight", ScenePlace.over(DEV_ZONE, FLIGHT_AT, 2))        # (a sub that shows cell 2 has no turn to make)
	assert_float(turned.length).is_less(here.length)
	var further := StoryScene.timeline_named(&"dev_flight", ScenePlace.over(DEV_ZONE, Vector2i(FLIGHT_AT.x + 200, FLIGHT_AT.y), FLIGHT_CELL))
	assert_float(further.length).is_greater(here.length)                                       # (it flies left until it has left the screen)
	var at_the_origin := StoryScene.timeline_named(&"dev_flight")                               # (no place: the window's origin, cell 0, as the check of a pack asks)
	assert_float(at_the_origin.length).is_equal(StoryScene.timeline_named(&"dev_flight", ScenePlace.nowhere()).length)
	assert_float(at_the_origin.length).is_equal(flight.timeline(0, 0, 0).length)
	assert_object(StoryScene.timeline_named(&"no_such_timeline")).is_null()


func test_the_segment_makes_the_flight_when_it_is_built_for_the_place_it_is_handed() -> void:
	var closing := _flight_segment()
	assert_bool(closing.place.sub_at == FLIGHT_AT).is_true()
	assert_int(closing.place.sub_cell).is_equal(FLIGHT_CELL)
	var made := StoryScene.timeline_named(&"dev_flight", closing.place)
	assert_float(closing.script_player.get_animation(&"dev_flight").length).is_equal_approx(CutsceneTimeline.seconds(made.length), 0.0001)
	assert_float(StoryScene.timeline_named(&"dev_flight", ScenePlace.over(DEV_ZONE, Vector2i(500, 180), 0)).length).is_not_equal(made.length)    # (another place, another flight)
	var elsewhere := _flight_segment(Vector2i(500, 180), 0)
	assert_float(elsewhere.script_player.get_animation(&"dev_flight").length).is_not_equal(closing.script_player.get_animation(&"dev_flight").length)
	assert_str(String(closing.script_player.current_animation)).is_equal("dev_flight")
	assert_object(closing.get_node_or_null("Backdrop")).is_null()
	assert_array(TroubleLog.session.told).is_empty()


func test_a_flight_is_not_made_when_it_cannot_end_and_the_scene_says_so() -> void:
	var flight := Catalog.story_flight(&"dev_flight").duplicate() as SubFlight
	assert_array(Array(flight.problems())).is_empty()
	flight.fly_pixels = 0
	flight.rotor_pictures = []
	flight.change_pictures = []
	flight.step_ticks = 0.0
	flight.turn_table = PackedInt32Array([1, 0, 2])
	flight.turn_done_cell = 2
	assert_array(Array(flight.problems())).is_equal([
		"has steps of 0.0 ticks: it is not played", "moves the helicopter 0 pixels a step to the left, so it never leaves: it is not played", "has no rotor pictures: it is not played",
		"has no pictures of the change into a helicopter: it is not played", "has a turn table that does not lead cell 0 to cell 2: it is not played"])
	flight.turn_table = PackedInt32Array()
	assert_array(Array(flight.problems())).contains(["has no turn table: it is not played"])


# --- the last step of the flight is a mark: Enter goes to it, and the pages follow -----------------------------------------

func test_the_flights_last_step_is_a_mark_with_the_cue_the_flight_names() -> void:
	var flight := StoryScene.timeline_named(&"dev_flight", ScenePlace.over(DEV_ZONE, FLIGHT_AT, FLIGHT_CELL))
	assert_array(flight.marks.keys()).is_equal([SubFlight.END_MARK])
	var last_step: float = flight.marks[SubFlight.END_MARK]
	assert_float(last_step).is_less(flight.length)                                             # (the margin the animation runs on past it)
	var cues := flight.cues.filter(func(entry: CutsceneCue) -> bool: return entry.kind == CutsceneCue.EVENT)
	assert_array(cues.map(func(entry: CutsceneCue) -> StringName: return entry.cue_name)).is_equal([&"messages"])
	assert_float((cues[0] as CutsceneCue).tick).is_equal(last_step)
	assert_array(Array(Catalog.story_scene(DEV_FLIGHT_CLOSING).unresolved())).is_empty()


func test_enter_during_the_flight_goes_to_its_last_step_and_the_first_page_shows_with_the_helicopter_gone() -> void:
	var closing := _flight_segment()
	assert_bool(closing.messages.is_open()).is_false()
	assert_bool((closing.cast.node_of(&"sub") as CanvasItem).visible).is_true()
	closing.advance()
	assert_bool(closing.done).is_false()
	assert_bool(closing.messages.is_open()).is_true()
	assert_str(closing.messages.current.title).is_equal("Surface Ship Message")
	assert_str(closing.messages.current.body).is_equal(closing.scene.messages[0].shown())
	assert_bool((closing.cast.node_of(&"sub") as CanvasItem).visible).is_false()               # (the flight is where it ends: the helicopter has left, the sub is gone)
	assert_bool((closing.cast.node_of(&"helicopter") as CanvasItem).visible).is_true()
	assert_bool(closing.message_view.visible).is_true()
	closing.advance()                                                                            # (Enter belongs to the box now: it does not end the scene)
	assert_bool(closing.done).is_false()
	assert_bool(closing.messages.is_open()).is_true()
	closing.skip()


func test_the_flight_played_to_its_last_step_shows_the_pages_once() -> void:
	var closing := _flight_segment()
	var animation := closing.script_player.get_animation(&"dev_flight")
	closing.script_player.advance(animation.length + 0.01)
	await await_idle_frame()                                                                     # (an animation calls its methods at the end of the frame)
	assert_bool(closing.messages.is_open()).is_true()
	assert_str(closing.messages.current.body).is_equal(closing.scene.messages[0].shown())
	closing.cue(&"messages")                                                                     # (a second cue does not start the pages again)
	assert_int(closing.messages.waiting_count()).is_equal(0)
	closing.skip()


# --- the verb messages -----------------------------------------------------------------------------------------------------

func _press_enter_on_the_box(closing: TimelineSegment) -> void:
	(closing.message_view.button_row.get_child(0) as Button).pressed.emit()


func test_the_messages_show_in_order_each_read_aloud_and_enter_closes_a_page_and_cuts_its_speech() -> void:
	var closing := _flight_segment()
	var spoken := []
	var on_voice := func(clips: Array[StringName]) -> void: spoken.append(clips)
	Audio.voice_played.connect(on_voice)
	var count := [0]
	closing.finished.connect(func() -> void: count[0] += 1)
	var cues := Catalog.voice_cues()
	closing.advance()
	assert_array(spoken).has_size(1)
	assert_array(spoken[0]).is_equal(cues.clips("jingle") + cues.clips("closing_page_0"))                  # (the first page: the jingle, then its words)
	assert_str(closing.messages.current.body).is_equal(closing.scene.messages[0].shown())
	var cut := [0]
	var on_cut := func() -> void: cut[0] += 1
	Audio.voice_finished.connect(on_cut)
	_press_enter_on_the_box(closing)                                                            # Enter closes the page and cuts its speech
	assert_int(cut[0]).is_greater(0)
	Audio.voice_finished.disconnect(on_cut)
	assert_bool(closing.done).is_false()
	assert_bool(closing.messages.is_open()).is_true()
	assert_str(closing.messages.current.body).is_equal(closing.scene.messages[1].shown())
	assert_array(spoken).has_size(2)
	assert_array(spoken[1]).is_equal(cues.clips("closing_page_1"))
	assert_int(count[0]).is_equal(0)
	_press_enter_on_the_box(closing)                                                            # the scene is over after the last page
	Audio.voice_played.disconnect(on_voice)
	assert_bool(closing.done).is_true()
	assert_bool(closing.messages.is_open()).is_false()
	assert_int(count[0]).is_equal(1)
	assert_array(spoken).has_size(2)


func test_space_or_escape_closes_the_page_that_shows_and_ends_the_scene_once() -> void:
	var closing := _flight_segment()
	var count := [0]
	closing.finished.connect(func() -> void: count[0] += 1)
	closing.advance()
	closing.skip()
	closing.skip()
	assert_bool(closing.done).is_true()
	assert_bool(closing.messages.is_open()).is_false()                                          # (the page is closed, and the clock it held is let go)
	assert_int(closing.messages.waiting_count()).is_equal(0)
	assert_int(count[0]).is_equal(1)
	assert_bool(GameClock.paused).is_false()


func test_skipping_during_the_flight_ends_the_scene_with_no_page_shown() -> void:
	var closing := _flight_segment()
	closing.skip()
	assert_bool(closing.done).is_true()
	assert_bool(closing.messages.is_open()).is_false()
	closing.cue(&"messages")                                                                     # (a cue that comes after the end shows nothing)
	assert_bool(closing.messages.is_open()).is_false()


func test_a_scene_with_messages_has_the_box_over_everything_and_one_without_has_none() -> void:
	var closing := _flight_segment()
	assert_object(closing.message_view).is_not_null()
	assert_int(closing.message_view.get_index()).is_equal(closing.get_child_count() - 1)
	assert_bool(closing.message_view.visible).is_false()
	var film := _segment()
	assert_object(film.messages).is_null()
	assert_object(film.message_view).is_null()
	assert_object(film.modals).is_null()
	assert_array(film.find_children("*", "MessageBoxView", true, false)).is_empty()


func test_the_message_verb_takes_no_words_and_a_scene_with_nothing_to_show_ends_at_the_cue() -> void:
	assert_int(StoryVerbs.VERBS[&"messages"]).is_equal(0)
	assert_str(StoryVerbs.problem(&"messages")).is_empty()
	assert_str(StoryVerbs.problem(&"messages now")).contains("takes 0 words after it")
	var closing := _flight_segment()
	closing.scene = _flight_scene()                                                              # (a copy: the scene the chain holds is shared)
	closing.scene.messages = []
	closing.cue(&"messages")
	assert_bool(closing.done).is_true()


func test_the_text_of_a_message_loses_its_own_heading_line_because_the_box_draws_one() -> void:
	var pack := PackShelf.new()
	pack.write_json("texts.json", {"heading_probe": "Surface Ship Message:\nCongratulations!\n", "plain_probe": "No heading here.\n"})
	pack.mount()
	var message := SceneMessage.new()
	message.text = &"heading_probe"
	assert_str(message.shown()).is_equal("Congratulations!")
	message.text = &"plain_probe"
	assert_str(message.shown()).is_equal("No heading here.")
	assert_bool(message.has_text()).is_true()
	message.text = &"no_such_text_anywhere"
	assert_bool(message.has_text()).is_false()
	message.text = &""
	assert_bool(message.has_text()).is_false()
	pack.remove()
	Packs.start()


# --- what the new scene data is judged for ------------------------------------------------------------------------------------

## A copy of the dev flight closing that a test may change (`Resource.duplicate` drops the typed array of messages, so the fields are copied one by one).
func _flight_scene() -> StoryScene:
	var scene := StoryScene.new()
	var held := Catalog.story_scene(DEV_FLIGHT_CLOSING)
	scene.stage = held.stage
	scene.timelines = held.timelines.duplicate()
	scene.backdrop = held.backdrop
	for message in held.messages:
		scene.messages.append(_message(message.text, message.speech.duplicate()))
	return scene


func _message(text_name: StringName, groups: Array[StringName]) -> SceneMessage:
	var message := SceneMessage.new()
	message.text = text_name
	message.speech = groups
	return message


func test_a_message_whose_text_no_pack_holds_is_told_and_left_out_and_a_silent_group_is_told() -> void:
	var scene := _flight_scene()
	scene.messages = [_message(&"no_such_text_anywhere", []), _message(&"closing_page_0", [&"no_such_group"]), null]
	assert_array(Array(scene.unresolved())).is_equal([
		"has a message whose text 'no_such_text_anywhere' no pack of the chain holds: that message is left out",
		"speaks the voice group 'no_such_group' with the message 'closing_page_0', which no pack of the chain holds in voice_cues: that group is not spoken",
		"has a message whose text '' no pack of the chain holds: that message is left out"])
	assert_array(scene.shown_messages().map(func(message: SceneMessage) -> StringName: return message.text)).is_equal([&"closing_page_0"])


func test_messages_with_no_cue_and_a_cue_with_no_messages_are_told_because_one_does_nothing_without_the_other() -> void:
	var never := _flight_scene()
	never.timelines = [&"dev_closing_film"]
	never.deaf_until_listen = false
	assert_array(Array(never.unresolved())).is_equal(["has messages, but no timeline of it has the cue 'messages': they are never shown"])
	var nothing := _flight_scene()
	nothing.messages = []
	assert_array(Array(nothing.unresolved())).is_equal(["has the cue 'messages', but no messages: the cue shows nothing"])


func test_a_scene_that_names_a_flight_that_is_not_sound_is_told_what_is_wrong_with_it_and_the_flight_is_not_played() -> void:
	var pack := PackShelf.new()
	var flight := Catalog.story_flight(&"dev_flight").duplicate() as SubFlight
	flight.rotor_pictures = []
	pack.write_json("data/story/dev_flight.json", ResourceJson.new().data_of(flight))
	pack.mount()
	assert_object(StoryScene.timeline_named(&"dev_flight")).is_null()
	var lines := _flight_scene().unresolved()
	assert_bool(Array(lines).has("names the flight 'dev_flight', which has no rotor pictures: it is not played")).is_true()
	TroubleLog.new_run()
	var closing := _segment_at(DEV_FLIGHT_CLOSING, ScenePlace.over(DEV_ZONE, FLIGHT_AT, FLIGHT_CELL))
	assert_array(TroubleLog.session.told.filter(func(line: String) -> bool: return line.contains("names the flight 'dev_flight'"))).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("[story] pack 'dev'").contains("the scene 'dev_flight_closing'").contains("which has no rotor pictures: it is not played")
	assert_bool(closing.script_player.has_animation(&"dev_flight")).is_false()
	closing.skip()
	pack.remove()
	Packs.start()


func test_the_closing_files_a_campaign_names_include_a_flight_file_as_a_sub_flight() -> void:
	var orchard := CampaignShelf.orchard()
	orchard.closing_scene = DEV_FLIGHT_CLOSING
	_shelf = CampaignShelf.new([orchard])
	var named := PackNeeds.named_by_closings()
	assert_str(named["data/story/dev_flight_closing.tres"]).is_equal("StoryScene")
	assert_str(named["data/story/dev_flight_stage.tres"]).is_equal("CutsceneStage")
	assert_str(named["data/story/dev_flight.tres"]).is_equal("SubFlight")
	assert_str(PackNeeds.class_of("data/story/dev_flight.tres")).is_equal("SubFlight")


# --- the game hands the scene the place of the sub -------------------------------------------------------------------------------

func test_the_game_hands_the_flight_the_zone_and_the_place_and_cell_of_the_sub_and_enter_goes_to_the_pages() -> void:
	var game := await _start(DEV_FLIGHT_CLOSING)
	_dock_at_the_finale(game)
	var at: Vector2i = game.world.sim.sub.original_position()
	var cell: int = game.world.sim.sub.cell
	var closing := game.closing as TimelineSegment
	assert_object(closing).is_not_null()
	assert_str(closing.scene_name).is_equal(DEV_FLIGHT_CLOSING)
	assert_int(closing.place.zone).is_equal(game.world.sector.zone)
	assert_bool(closing.place.sub_at == at).is_true()
	assert_int(closing.place.sub_cell).is_equal(cell)
	assert_float(closing.script_player.get_animation(&"dev_flight").length).is_equal_approx(CutsceneTimeline.seconds(Catalog.story_flight(&"dev_flight").timeline(at.x, at.y, cell).length), 0.0001)
	assert_bool(game.world.sim.sub.active).is_false()
	assert_str(Audio.song).is_equal(AudioService.NO_MUSIC)                                       # (the sector's song stopped before the closing; the scene has none)
	game._unhandled_input(_key(KEY_ENTER))                                                      # Enter in the flight: to the pages
	assert_object(game.closing).is_same(closing)
	assert_bool(closing.messages.is_open()).is_true()
	game._unhandled_input(_key(KEY_ENTER))                                                      # Enter on a page is the box's
	assert_object(game.closing).is_same(closing)
	_press_enter_on_the_box(closing)
	_press_enter_on_the_box(closing)
	assert_object(game.closing).is_null()
	await _hall_then_sign_in(game)
	assert_array(TroubleLog.session.told).is_empty()


func test_space_during_the_pages_of_the_game_ends_the_closing_and_goes_to_the_hall_of_fame() -> void:
	var game := await _start(DEV_FLIGHT_CLOSING)
	_dock_at_the_finale(game)
	var closing := game.closing as TimelineSegment
	closing.advance()
	game._unhandled_input(_key(KEY_SPACE))
	assert_object(game.closing).is_null()
	assert_bool(closing.messages.is_open()).is_false()
	await _hall_then_sign_in(game)
