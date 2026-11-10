class_name TestGenericFinale
extends GdUnitTestSuite
## Teaches: what a campaign without a closing scene of its own gets, and how its words get into the game. Three things are tested.
## (1) `Campaign.text`: a campaign's texts are registry names OR plain words, and one function tells them apart. (2) The generic finale
## scene: a picture and a text taken from the campaign, Enter / Space / Escape / a click like the original's closing. (3) The whole
## ending through the real `Game` scene and `GameFlow`: docking at the finale of a made-up campaign shows the generic finale, then the Hall of
## Fame, then the sign-in screen - the same road the originals take. Plus: a campaign with no recordings is simply not spoken.

const GAME_SCENE := "res://src/gameplay/game.tscn"
const FINALE_SECTOR := 160
const FINALE_SCENE := "res://src/story/generic_finale.tscn"
const ROSTER := "user://test_generic_finale_roster.json"
const HALL := "user://test_generic_finale_hall.json"

var _shelf: CampaignShelf
var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]


func before_test() -> void:
	_old_roster = SaveStore.roster_path
	_old_hall = SaveStore.hall_path
	_old_players = SaveStore.players.duplicate()
	SaveStore.roster_path = ROSTER
	SaveStore.hall_path = HALL
	SaveStore.players = []
	SaveStore.hall = HallOfFame.new()
	SceneRouter.dry_run = true
	SceneRouter.last_path = ""


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
	Audio.stop_voice()
	for path in [ROSTER, HALL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key


# --- words that are names, and words that are words --------------------------------------------------------------------------

func test_a_text_is_a_registry_name_or_the_words_themselves() -> void:
	assert_str(Campaign.text("surface_ship_title")).is_equal(Catalog.text(&"surface_ship_title"))           # a name: the game's string
	assert_str(Campaign.text("Well done, gardeners!")).is_equal("Well done, gardeners!")     # not a name: as written
	assert_str(Campaign.text("")).is_equal("")
	assert_str(Campaign.text("no_such_name_at_all")).is_equal("no_such_name_at_all")   # a typo shows on the screen; no error in the log


func test_a_campaign_may_use_registry_names_or_words() -> void:
	var named := Campaign.new()                                                        # a campaign whose texts are names of the registry
	named.title = "game_voyager"
	named.sectors = PackedInt32Array([175])
	named.supply_texts = [&"supply_message_0"]
	named.log_unlock_order = PackedInt32Array([1])
	named.log_texts = [&"log_entry_2"]
	assert_str(named.display_title()).is_equal(Catalog.text(&"game_voyager"))
	assert_str(named.supply_message_text(175)).is_equal(Catalog.text(&"supply_message_0"))
	assert_str(named.log_entry_text(1)).is_equal(Catalog.text(&"log_entry_2"))
	var garden := CampaignShelf.garden()
	assert_str(garden.display_title()).is_equal("Garden of Tests")
	assert_str(garden.new_game_label()).is_equal("Garden of Tests")
	assert_str(garden.supply_message_text(175)).is_equal("Mission control: the first bed is planted.")
	assert_str(garden.log_entry_text(2)).is_equal("The second note of the garden.")
	assert_str(garden.finale_message()).is_equal("The garden is in bloom. Well done, gardeners!")
	garden.title = "surface_ship_title"                                                # ... and a name works wherever words do
	garden.finale_text = "surface_ship_title"
	assert_str(garden.display_title()).is_equal(Catalog.text(&"surface_ship_title"))
	assert_str(garden.finale_message()).is_equal(Catalog.text(&"surface_ship_title"))
	assert_array(garden.problems()).is_empty()


func test_the_finale_picture_is_a_registry_name_a_file_or_nothing() -> void:
	var garden := CampaignShelf.garden()
	assert_object(garden.finale_texture()).is_same(Assets.ui_picture(&"title_sky"))
	garden.finale_picture = "res://icon.svg"
	assert_object(garden.finale_texture()).is_not_null()
	garden.finale_picture = ""
	assert_object(garden.finale_texture()).is_null()
	assert_array(garden.problems()).is_empty()
	garden.finale_picture = "no_such_picture"
	assert_object(garden.finale_texture()).is_null()
	assert_str("\n".join(garden.problems())).contains("finale_picture 'no_such_picture'")
	garden.finale_picture = "res://nowhere/finale.png"
	assert_object(garden.finale_texture()).is_null()


# --- the scene itself --------------------------------------------------------------------------------------------------------

func _finale(campaign: Campaign) -> GenericFinale:
	var scene: GenericFinale = auto_free(load(FINALE_SCENE).instantiate())
	add_child(scene)
	scene.show_finale(campaign)
	return scene


func test_the_scene_shows_the_campaigns_title_text_and_picture() -> void:
	var scene := _finale(CampaignShelf.garden())
	assert_str(scene.title_label.text).is_equal("Garden of Tests")
	assert_str(scene.message_label.text).is_equal("The garden is in bloom. Well done, gardeners!")
	assert_object(scene.picture.texture).is_same(Assets.ui_picture(&"title_sky"))
	assert_bool(scene.picture.visible).is_true()
	assert_str(scene.continue_label.text).is_equal(Catalog.text(&"click_to_go_on"))
	assert_bool(scene.done).is_false()


func test_a_campaign_with_only_a_text_shows_no_picture_and_with_nothing_still_ends() -> void:
	var plain := CampaignShelf.garden()
	plain.finale_picture = ""
	var scene := _finale(plain)
	assert_bool(scene.picture.visible).is_false()
	assert_str(scene.message_label.text).is_equal("The garden is in bloom. Well done, gardeners!")
	plain.finale_text = ""
	var bare := _finale(plain)
	assert_str(bare.message_label.text).is_equal("")
	assert_str(bare.title_label.text).is_equal("Garden of Tests")
	bare.advance()
	assert_bool(bare.done).is_true()


func test_enter_and_skip_and_a_click_all_end_the_scene() -> void:
	var by_advance := _finale(CampaignShelf.garden())
	var ended := [0]
	by_advance.finished.connect(func() -> void: ended[0] += 1)
	by_advance.advance()
	by_advance.advance()                                                              # (twice does nothing more)
	assert_int(ended[0]).is_equal(1)
	var by_skip := _finale(CampaignShelf.garden())
	by_skip.skip()
	assert_bool(by_skip.done).is_true()
	var by_click := _finale(CampaignShelf.garden())
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	by_click._gui_input(release)
	assert_bool(by_click.done).is_true()
	var by_press := _finale(CampaignShelf.garden())
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	by_press._gui_input(press)                                                        # (the press does nothing, the release does)
	assert_bool(by_press.done).is_false()


# --- no recordings -----------------------------------------------------------------------------------------------------------

func test_a_message_with_no_recording_is_read_not_spoken_and_does_not_hold_the_screen_up() -> void:
	_shelf = CampaignShelf.new([CampaignShelf.garden()])
	var spoken: Array = []
	var listener := func(clips: Array[StringName]) -> void: spoken.append(clips)
	Audio.voice_played.connect(listener)
	for sector in [175, 176]:                                       # the first has no voice group, the second one that does not exist
		var screen: SurfaceShipScreen = auto_free(load("res://src/story/surface_ship_screen.tscn").instantiate())
		add_child(screen)
		screen.show_supply_message(sector)
		assert_str(screen.message_label.text).is_equal(Catalog.campaign(&"garden").supply_message_text(sector))
		assert_str(screen.message_label.text).starts_with("Mission control: the")
		var jingle: Array[StringName] = [Catalog.voice_cues().jingle()]
		assert_array(spoken.back()).is_equal(jingle)                  # only the "incoming transmission" sound, no lines after it
		screen.finish()                                               # Enter
		assert_bool(GameClock.paused).is_false()
	Audio.voice_played.disconnect(listener)
	assert_array(Catalog.voice_cues().clips("")).is_empty()
	assert_array(Catalog.voice_cues().clips("no_such_group")).is_empty()


func test_the_wait_of_a_silent_message_starts_when_the_jingle_is_over_not_from_a_recording() -> void:
	_shelf = CampaignShelf.new([CampaignShelf.garden()])
	var screen: SurfaceShipScreen = auto_free(load("res://src/story/surface_ship_screen.tscn").instantiate())
	add_child(screen)
	var voice_was_on := Audio.is_bus_enabled(AudioService.VOICE)
	Audio.set_bus_enabled(AudioService.VOICE, false)               # nothing to hear (no device here, either): the wait starts at once
	screen.show_supply_message(175)
	Audio.set_bus_enabled(AudioService.VOICE, voice_was_on)
	assert_int(screen.wait_ticks_left).is_equal(SurfaceShipScreen.wait_ticks())
	screen.advance_wait(SurfaceShipScreen.wait_ticks())             # 20 s of the original's ticks, and the screen ends by itself
	assert_bool(screen._closed).is_true()


func test_the_log_of_a_campaign_with_words_of_its_own_shows_them_and_speaks_nothing() -> void:
	_shelf = CampaignShelf.new([CampaignShelf.garden()])
	var screen := scene_runner("res://src/ui/log_screen.tscn").scene() as LogScreen
	var spoken: Array = []
	var listener := func(clips: Array[StringName]) -> void: spoken.append(clips)
	Audio.voice_played.connect(listener)
	screen.start(176)                                              # the garden's second sector lists its two notes
	screen.advance_scan(CanisterLog.scan_ticks())
	assert_int(screen.row_count()).is_equal(3)                     # two entries and DONE
	assert_str(screen.entry_text.text).is_equal("The first note of the garden.")     # the newest one of this sector (log_unlock_order [2, 1])
	screen.press(&"down")
	screen.press(&"enter")                                         # entry 2: a voice group that does not exist
	assert_str(screen.entry_text.text).is_equal("The second note of the garden.")
	assert_bool(Audio.is_voice_playing()).is_false()               # no clips, no speech, no error
	assert_array(spoken.back()).is_empty()
	Audio.voice_played.disconnect(listener)


# --- the whole ending, through the real game ---------------------------------------------------------------------------------

func _start_orchard() -> Game:
	var orchard := CampaignShelf.orchard()
	orchard.finales = PackedInt32Array([FINALE_SECTOR])                  # a finale with a treasure and a finale screen (dev's test sector)
	_shelf = CampaignShelf.new([orchard])
	var player: PlayerProfile = SaveStore.add_player_in("Tester", Catalog.campaign(&"orchard"))
	player.hints_enabled = false
	player.progress = FINALE_SECTOR * 2                                # the finale of the made-up campaign
	player.tries = 5
	GameState.profile = player
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	var ticks := 0
	while not game.world.sim.sub.controlled and ticks < 100:          # the launch from the station, in the rules' ticks
		game.world.tick()
		ticks += 1
	assert_bool(game.world.sim.sub.controlled).override_failure_message("the launch never ended").is_true()
	return game


func _dock_at_the_finale(game: Game) -> void:
	game.world.foe_context.semaphore |= 1 << SimWorld.FINALE_SEMAPHORE_BIT       # the treasure was touched ...
	game.world.load_screen(Catalog.sector(FINALE_SECTOR).finale_screen)                      # ... and the sub is on the finale screen
	game.world.tick()


func _hall_then_sign_in(game: Game) -> void:
	await await_idle_frame()
	assert_int(SaveStore.hall.entries.size()).is_equal(1)
	assert_str(SaveStore.hall.entries[0].name).is_equal("Tester")
	assert_str(SaveStore.hall.entries[0].campaign_id).is_equal(&"orchard")
	assert_int(SaveStore.hall.entries[0].tries).is_equal(5)
	assert_array(SaveStore.players).is_empty()                                    # the winner left the roster
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HALL))
	assert_str(saved["entries"][0]["campaign"]).is_equal("orchard")
	var view := game.dialog_layer.get_child(game.dialog_layer.get_child_count() - 1) as HallOfFameView
	assert_object(view).is_not_null()
	assert_bool(_cells_of(view).has("Orchard")).is_true()                         # the Hall shows the campaign's own name
	view.close()
	await await_idle_frame()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.SIGN_IN)


func _cells_of(view: HallOfFameView) -> Array[String]:
	var texts: Array[String] = []
	for child in view.grid.get_children():
		texts.append((child as Label).text)
	return texts


func test_the_finale_of_a_made_up_campaign_shows_the_generic_scene_then_the_hall_of_fame() -> void:
	var game := await _start_orchard()
	assert_int(game.world.sector_index).is_equal(FINALE_SECTOR)
	assert_str(game.flow.campaign.id).is_equal(&"orchard")
	_dock_at_the_finale(game)
	assert_object(game.closing).is_instanceof(GenericFinale)
	assert_bool(game.world.sim.sub.active).is_false()
	var scene := game.closing as GenericFinale
	assert_str(scene.message_label.text).is_equal("The orchard is yours.")
	assert_str(scene.title_label.text).is_equal("Orchard")
	assert_int(SaveStore.hall.entries.size()).is_equal(0)                         # not in the Hall of Fame before the scene is over
	game._unhandled_input(_key(KEY_ENTER))                                        # Enter goes on
	assert_object(game.closing).is_null()
	await _hall_then_sign_in(game)


func _skipped_by(code: Key) -> void:
	var game := await _start_orchard()
	_dock_at_the_finale(game)
	assert_object(game.closing).is_instanceof(GenericFinale)
	game._unhandled_input(_key(code))
	assert_object(game.closing).is_null()
	await _hall_then_sign_in(game)


func test_space_skips_the_generic_finale_like_the_originals_closing() -> void:
	await _skipped_by(KEY_SPACE)


func test_escape_skips_the_generic_finale_like_the_originals_closing() -> void:
	await _skipped_by(KEY_ESCAPE)


