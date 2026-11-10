class_name TestCampaignSignInLegacy
extends GdUnitTestSuite
## Teaches: the new-player dialog of the original has two buttons, Voyager and Expert, with the original's words; with no other campaign installed
## they are the only two it shows. (The dialog for any list of campaigns: tests/engine/test_campaign_sign_in.gd.)

const DIALOG_SCENE := "res://src/ui/new_player_dialog.tscn"

var _shelf: CampaignShelf


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func after_test() -> void:
	if _shelf != null:
		_shelf.remove()
		_shelf = null


func test_with_only_the_originals_the_dialog_is_unchanged() -> void:
	_shelf = CampaignShelf.new()                                        # (the legacy pack's campaigns: the originals' two)
	var dialog: NewPlayerDialog = auto_free(load(DIALOG_SCENE).instantiate())
	add_child(dialog)
	var buttons: Array[Button] = []
	for child in dialog.voyager_button.get_parent().get_children():
		if child is Button:
			buttons.append(child as Button)
	assert_int(buttons.size()).is_equal(2)
	assert_str(buttons[0].text).is_equal(Catalog.text(&"voyager_game_button"))
	assert_str(buttons[1].text).is_equal(Catalog.text(&"expert_game_button"))
	assert_object(buttons[0]).is_same(dialog.voyager_button)
	assert_object(buttons[1]).is_same(dialog.expert_button)
