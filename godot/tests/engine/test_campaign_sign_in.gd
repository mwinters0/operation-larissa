class_name TestCampaignSignIn
extends GdUnitTestSuite
## Teaches: a screen that offers a LIST OF DATA instead of two fixed choices. The new-player dialog has the original's two buttons; with more
## campaigns installed it adds one button for each (a copy of the second, below it), and the sign-in screen and the Hall of Fame show
## whatever name the campaign gives its game. The campaigns are the pack's own (copied by `CampaignShelf`) and made-up ones.

const SIGN_IN_SCENE := "res://src/ui/sign_in.tscn"
const DIALOG_SCENE := "res://src/ui/new_player_dialog.tscn"
const ROSTER := "user://test_campaign_sign_in_roster.json"
const HALL := "user://test_campaign_sign_in_hall.json"

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
	SceneRouter.dry_run = true
	SceneRouter.last_path = ""
	GameState.profile = null
	SignIn.welcome_enabled = false
	SignIn.returning_from_practice = false
	SignIn.new_player_added = false
	SignIn.prompt_when_empty = false


func after_test() -> void:
	if _shelf != null:
		_shelf.remove()
		_shelf = null
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SceneRouter.dry_run = false
	GameState.profile = null
	Audio.stop_voice()
	Audio.apply_profile(null)
	SignIn.new_player_added = false
	SignIn.prompt_when_empty = true
	SignIn.welcome_enabled = true
	SignIn.returning_from_practice = false
	for path in [ROSTER, HALL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## A campaign like the garden under another id and name.
func _variant(id: StringName, title: String) -> Campaign:
	var campaign := CampaignShelf.garden()
	campaign.id = id
	campaign.title = title
	return campaign


func _dialog() -> NewPlayerDialog:
	var dialog: NewPlayerDialog = auto_free(load(DIALOG_SCENE).instantiate())
	add_child(dialog)
	return dialog


func _buttons_of(dialog: NewPlayerDialog) -> Array[Button]:
	var found: Array[Button] = []
	for child in dialog.voyager_button.get_parent().get_children():
		if child is Button:
			found.append(child as Button)
	return found


func test_with_only_the_packs_campaigns_the_dialog_offers_just_those() -> void:
	_shelf = CampaignShelf.new()                                        # (the pack's own campaigns: the project has a third one of its own, which is left out)
	var dialog := _dialog()
	var offered := Catalog.campaigns()
	var shown := _buttons_of(dialog).filter(func(button: Button) -> bool: return button.visible)
	assert_array(shown.map(func(button: Button) -> String: return button.text)).is_equal(offered.map(func(each: Campaign) -> String: return each.new_game_label()))
	assert_object(shown[0]).is_same(dialog.voyager_button)               # the scene's own two buttons serve the first two campaigns
	if offered.size() < 2:
		assert_bool(dialog.expert_button.visible).is_false()


func test_the_dialog_offers_every_campaign_and_answers_with_the_id_of_the_one_chosen() -> void:
	_shelf = CampaignShelf.new([_variant(&"garden", "Garden of Tests"), _variant(&"herb", "Herb Patch"), _variant(&"orchard", "Orchard")])
	var dialog := _dialog()
	await await_idle_frame()
	var offered := Catalog.campaigns()                                   # (the pack's own, the originals' first, then by id, and the made-up ones)
	var buttons := _buttons_of(dialog)
	assert_array(buttons.map(func(button: Button) -> String: return button.text)).is_equal(offered.map(func(each: Campaign) -> String: return each.new_game_label()))
	for label in ["Garden of Tests", "Herb Patch", "Orchard"]:
		assert_bool(buttons.any(func(button: Button) -> bool: return button.text == label)).is_true()
	assert_object(buttons[0]).is_same(dialog.voyager_button)            # the scene's first button is the first campaign's
	dialog.name_edit.text_submitted.emit("Gus")
	var chosen: Array = []
	dialog.confirmed.connect(func(player_name: String, id: StringName) -> void: chosen.append([player_name, id]))
	var herb := buttons.find_custom(func(button: Button) -> bool: return button.text == "Herb Patch")
	buttons[herb].pressed.emit()
	buttons[0].pressed.emit()
	assert_array(chosen).is_equal([["Gus", &"herb"], ["Gus", offered[0].id]])


func test_the_buttons_of_many_campaigns_stand_in_one_column_inside_the_window() -> void:
	_shelf = CampaignShelf.new([_variant(&"garden", "Garden of Tests"), _variant(&"herb", "Herb Patch"), _variant(&"meadow", "Meadow"),
			_variant(&"orchard", "Orchard"), _variant(&"pond", "Pond")])
	var dialog := _dialog()
	dialog.name_edit.text_submitted.emit("Gus")                            # the game step
	await await_idle_frame()
	await await_idle_frame()
	var buttons := _buttons_of(dialog)
	var panel := dialog.game_panel.get_global_rect()
	var window := Rect2(Vector2.ZERO, Vector2(640, 400))
	assert_bool(dialog.game_panel.visible).is_true()
	assert_bool(window.encloses(panel)).override_failure_message("panel %s is not inside the 640 x 400 window" % panel).is_true()
	for i in buttons.size():
		var rect := buttons[i].get_global_rect()
		assert_bool(panel.encloses(rect)).override_failure_message("button %d at %s is outside the panel %s" % [i, rect, panel]).is_true()
		if i > 0:
			assert_float(rect.position.y).is_greater_equal(buttons[i - 1].get_global_rect().end.y)     # below the one before, not on top of it
			assert_float(rect.position.x).is_equal(buttons[0].get_global_rect().position.x)           # one column
			assert_float(rect.size.x).is_equal(buttons[0].get_global_rect().size.x)


func test_a_new_player_of_another_campaign_is_listed_by_the_campaigns_name_and_can_start() -> void:
	_shelf = CampaignShelf.new([CampaignShelf.orchard()])
	var screen := scene_runner(SIGN_IN_SCENE).scene() as SignIn
	var profile := screen.add_player_in("Ola", Catalog.campaign(&"orchard"))
	assert_str(profile.campaign_id).is_equal(&"orchard")
	assert_int(profile.progress).is_equal(Catalog.default_campaign().sectors[0] * 2)     # the campaign's first sector (the orchard borrows the pack's)
	var row := screen.tree.get_selected()
	assert_str(row.get_text(1)).is_equal("Orchard")
	assert_str(row.get_text(3)).is_equal("1 of 2")
	assert_bool(screen.start_button.disabled).is_false()
	profile.customized = true
	screen.refresh()
	assert_str(screen.tree.get_selected().get_text(1)).is_equal("Orchard (c)")


func test_a_player_whose_campaign_is_gone_stays_in_the_list_but_cannot_start() -> void:
	var lost := PlayerProfile.new_player("Lost", 0)
	lost.campaign_id = &"vanished"
	lost.progress = 77
	SaveStore.players = [lost]
	var screen := scene_runner(SIGN_IN_SCENE).scene() as SignIn
	var row := screen.tree.get_selected()
	assert_str(row.get_text(0)).is_equal("Lost")
	assert_str(row.get_text(1)).is_equal("vanished")
	assert_str(row.get_text(3)).is_equal("not installed")
	assert_bool(screen.start_button.disabled).is_true()
	await screen.request_start()                                           # (Start does nothing, whoever presses it)
	assert_str(SceneRouter.last_path).is_equal("")
	assert_int(lost.progress).is_equal(77)
	screen.add_player("Ann", 0)                                            # another player can still be added and played
	assert_bool(screen.start_button.disabled).is_false()


func test_the_hall_of_fame_shows_the_name_of_the_campaign() -> void:
	_shelf = CampaignShelf.new([CampaignShelf.orchard()])
	var winner := PlayerProfile.new_player_in("Ola", Catalog.campaign(&"orchard"))
	winner.customized = true
	SaveStore.hall = HallOfFame.new()
	SaveStore.hall.add(HallEntry.from_profile(winner))
	var gone := HallEntry.new()
	gone.name = "Old"
	gone.campaign_id = &"vanished"
	SaveStore.hall.add(gone)
	var view: HallOfFameView = auto_free(load("res://src/ui/hall_of_fame.tscn").instantiate())
	add_child(view)
	var cells: Array[String] = []
	for child in view.grid.get_children():
		cells.append((child as Label).text)
	assert_bool(cells.has("Orchard " + Catalog.text(&"customized_marker"))).is_true()
	assert_bool(cells.has("vanished")).is_true()
	SaveStore.hall = HallOfFame.new()
