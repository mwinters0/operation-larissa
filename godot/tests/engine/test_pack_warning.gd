class_name TestPackWarning
extends GdUnitTestSuite
## Teaches: the game opens on a warning screen only when its chain is not whole. `Main.first_scene` is that decision: a fallback (`Packs.fallback_reason()` is not null: no pack
## at all, the one asked for is missing, a pack has errors, the chain lacks things) goes to `PackWarning`, a whole chain (`--pack=dev`, a pack over dev, a complete pack)
## goes straight to the opening. What the screen is depends on `Packs.dev_fallback`: in a debug build it says what happened, that the dev pack stands in, and one key or
## click goes on; in a release build it is a refusal that blocks play, offers the pack screen (to choose another pack, checked again) and quits on any other key or click.
## Runs on dev alone: it makes its own packs in a scratch folder, and the incomplete one is a pack that holds only a manifest (`PackShelf.empty_complete_pack_dir`).

const PROBE_ID := &"zz_warning_probe"

var _scratch: String
var _probe_dir: String
var _real_folders: Array[String]
var _real_mode: bool


func before_test() -> void:
	_scratch = "user://test_warning_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_scratch)
	_real_folders = Packs.folders.duplicate()
	_real_mode = Packs.dev_fallback
	SceneRouter.dry_run = true
	SceneRouter.last_path = ""


func after_test() -> void:
	SceneRouter.dry_run = false
	Packs.dev_fallback = _real_mode
	Packs.folders = _real_folders
	PackFiles.remove_tree(_scratch)
	Packs.start()                                            # (the command-line choice again: no test of this suite leaves a choice of its own behind)


func _screen() -> PackWarning:
	var screen := (load(SceneRouter.PACK_WARNING) as PackedScene).instantiate() as PackWarning
	add_child(screen)
	return auto_free(screen)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


# --- which scene the game opens on ----------------------------------------------------------------------------------------

func test_no_pack_found_opens_on_the_warning() -> void:
	Packs.dev_fallback = true
	Packs.folders = [_scratch]                               # an empty folder: nothing but dev
	Packs.start(PackedStringArray())
	assert_object(Packs.fallback_reason()).is_not_null()
	assert_str(Main.first_scene()).is_equal(SceneRouter.PACK_WARNING)


func test_a_pack_asked_for_that_is_not_there_opens_on_the_warning() -> void:
	Packs.dev_fallback = true
	Packs.folders = [_scratch]
	Packs.start(PackedStringArray(["--pack=nowhere"]))
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.NOT_FOUND)
	assert_str(Main.first_scene()).is_equal(SceneRouter.PACK_WARNING)


func test_choosing_dev_on_purpose_shows_no_warning_in_either_mode() -> void:
	for mode in [true, false]:
		Packs.dev_fallback = mode
		Packs.start(PackedStringArray(["--pack=dev"]))
		assert_object(Packs.fallback_reason()).is_null()
		assert_str(Main.first_scene()).is_equal(SceneRouter.OPENING)


func test_a_pack_that_is_chosen_and_whole_shows_no_warning() -> void:
	# a pack laid over dev: the chain is whole (the pack, then dev as its base), so there is nothing to warn about
	PackFiles.write_text(_scratch + "/whole/pack.json", JSON.stringify({"id": "whole", "title": "Whole", "version": "1", "base": "dev"}))
	Packs.folders = [_scratch]
	Packs.start(PackedStringArray(["--pack=whole"]))
	var reason := Packs.fallback_reason()
	assert_array(Packs.chain_ids()).is_equal([&"whole", Packs.DEV])
	assert_object(reason).override_failure_message("fallback: %s" % [reason.text() if reason != null else ""]).is_null()
	assert_str(Main.first_scene()).is_equal(SceneRouter.OPENING)
	Packs.dev_fallback = false
	Packs.start(PackedStringArray(["--pack=whole"]))
	assert_object(Packs.fallback_reason()).is_null()
	assert_str(Main.first_scene()).is_equal(SceneRouter.OPENING)


# --- the screen -----------------------------------------------------------------------------------------------------------

func test_the_screen_says_the_reason_that_it_is_not_for_play_and_where_to_read() -> void:
	Packs.dev_fallback = true
	Packs.folders = [_scratch]
	Packs.start(PackedStringArray())
	var screen := _screen()
	assert_str(screen.reason_label.text).is_equal(Packs.fallback_reason().text())
	assert_str(screen.reason_label.text).contains("dev pack")
	assert_str(screen.not_for_play_label.text).contains("not meant for play")
	assert_str(screen.where_label.text).is_equal(Packs.fallback_reason().advice()).contains("importer").contains("docs/play/LEGACY.md")


func test_the_screen_names_the_pack_that_was_asked_for() -> void:
	Packs.dev_fallback = true
	Packs.folders = [_scratch]
	Packs.start(PackedStringArray(["--pack=nowhere"]))
	assert_str(_screen().reason_label.text).contains("'nowhere'")


func test_a_key_goes_on_to_the_opening_once() -> void:
	Packs.dev_fallback = true
	Packs.folders = [_scratch]
	Packs.start(PackedStringArray())
	var screen := _screen()
	var count := [0]
	screen.continued.connect(func() -> void: count[0] += 1)
	screen._unhandled_input(_key(KEY_SPACE))
	screen._unhandled_input(_key(KEY_ENTER))
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.OPENING)
	assert_int(count[0]).is_equal(1)


func test_a_modifier_key_alone_does_not_leave_the_screen() -> void:
	Packs.dev_fallback = true
	Packs.folders = [_scratch]
	Packs.start(PackedStringArray())
	var screen := _screen()
	screen._unhandled_input(_key(KEY_SHIFT))
	assert_str(SceneRouter.last_path).is_empty()


func test_a_click_goes_on_to_the_opening() -> void:
	Packs.dev_fallback = true
	Packs.folders = [_scratch]
	Packs.start(PackedStringArray())
	var screen := _screen()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	screen._unhandled_input(click)
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.OPENING)


# --- a chain that lacks things, in a debug build ---------------------------------------------------------------------------

## The probe: a complete pack that holds nothing, so the chain [probe] lacks `missing` things. It is the only place packs are found.
func _probe() -> void:
	_probe_dir = PackShelf.empty_complete_pack_dir(PROBE_ID)
	Packs.folders = [_probe_dir, _scratch]


func test_debug_a_chain_that_lacks_things_says_how_many_and_that_dev_stands_in() -> void:
	_probe()
	Packs.dev_fallback = true
	Packs.start(PackedStringArray(["--pack=" + PROBE_ID]))
	assert_str(Main.first_scene()).is_equal(SceneRouter.PACK_WARNING)
	var missing := Packs.fallback_reason().missing
	assert_int(missing).is_greater(0)
	var screen := _screen()
	assert_str(screen.title_label.text).is_equal(PackWarning.TITLE)
	assert_str(screen.reason_label.text).contains("is incomplete").contains("%d missing" % missing)
	assert_str(screen.not_for_play_label.text).contains("%d things are missing" % missing).contains("placeholders stand in")
	assert_str(screen.where_label.text).contains("damaged or out of date").contains("docs/play/LEGACY.md")
	assert_bool(screen.pack_screen_button.visible).is_false()
	assert_bool(screen.quit_button.visible).is_false()
	screen._unhandled_input(_key(KEY_SPACE))                 # the player can go on, on dev under the pack
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.OPENING)
	assert_array(Packs.chain_ids()).is_equal([PROBE_ID, Packs.DEV])


# --- the refusal, in a release build -----------------------------------------------------------------------------------------

func _refused_screen() -> PackWarning:
	_probe()
	Packs.dev_fallback = false
	Packs.start(PackedStringArray(["--pack=" + PROBE_ID]))
	assert_bool(Packs.is_refused()).is_true()
	return _screen()


func _click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


func test_release_the_screen_is_a_refusal_with_the_problem_the_count_and_where_to_read() -> void:
	var screen := _refused_screen()
	var missing := Packs.fallback_reason().missing
	assert_str(screen.title_label.text).is_equal(PackWarning.TITLE_REFUSED)
	assert_str(screen.reason_label.text).contains("is incomplete").contains("cannot play")
	assert_str(screen.missing_label.text).is_equal("%d things are missing." % missing)
	assert_bool(screen.missing_label.visible).is_true()
	assert_str(screen.where_label.text).contains("docs/play/LEGACY.md")
	assert_bool(screen.not_for_play_label.visible).is_false()
	assert_str(screen.prompt_label.text).is_equal(PackWarning.PROMPT_REFUSED)
	assert_bool(screen.pack_screen_button.visible).is_true()
	assert_bool(screen.quit_button.visible).is_true()


func test_release_play_is_blocked() -> void:
	var screen := _refused_screen()
	screen.go_on()
	assert_str(SceneRouter.last_path).is_empty()


func test_release_any_key_quits_once() -> void:
	var screen := _refused_screen()
	var count := [0]
	screen.quit_requested.connect(func() -> void: count[0] += 1)
	screen._unhandled_input(_key(KEY_SHIFT))                 # a modifier alone is no key
	assert_int(count[0]).is_equal(0)
	screen._unhandled_input(_key(KEY_SPACE))
	screen._unhandled_input(_key(KEY_ENTER))
	assert_int(count[0]).is_equal(1)
	assert_str(SceneRouter.last_path).is_empty()


func test_release_any_click_quits() -> void:
	var screen := _refused_screen()
	var count := [0]
	screen.quit_requested.connect(func() -> void: count[0] += 1)
	screen._unhandled_input(_click())
	assert_int(count[0]).is_equal(1)


func test_release_the_quit_button_quits_and_the_buttons_take_no_key_focus() -> void:
	var screen := _refused_screen()
	var count := [0]
	screen.quit_requested.connect(func() -> void: count[0] += 1)
	assert_int(screen.quit_button.focus_mode).is_equal(Control.FOCUS_NONE)
	assert_int(screen.pack_screen_button.focus_mode).is_equal(Control.FOCUS_NONE)
	screen.quit_button.pressed.emit()
	assert_int(count[0]).is_equal(1)


func test_release_p_and_the_button_open_the_pack_screen_and_keys_do_not_quit_meanwhile() -> void:
	var screen := _refused_screen()
	var count := [0]
	screen.quit_requested.connect(func() -> void: count[0] += 1)
	screen._unhandled_input(_key(KEY_P))
	assert_object(screen._dialog).is_not_null()
	assert_bool(screen._dialog.choosing).is_true()
	assert_bool(screen._dialog.use_button.visible).is_true()
	screen._unhandled_input(_key(KEY_SPACE))
	screen._unhandled_input(_click())
	assert_int(count[0]).is_equal(0)
	screen._dialog.close()
	assert_object(screen._dialog).is_null()
	screen._unhandled_input(_key(KEY_SPACE))                 # the pack screen is gone: a key quits again
	assert_int(count[0]).is_equal(1)


func test_release_choosing_a_whole_pack_on_the_pack_screen_checks_again_and_goes_on() -> void:
	var screen := _refused_screen()
	PackFiles.write_text(_scratch + "/whole/pack.json", JSON.stringify({"id": "whole", "title": "Whole", "version": "1", "base": "dev"}))
	screen.pack_screen_button.pressed.emit()
	var dialog := screen._dialog
	dialog.select(&"whole")
	dialog.use_selected()
	assert_array(Packs.chain_ids()).is_equal([&"whole", Packs.DEV])
	assert_object(Packs.fallback_reason()).is_null()
	assert_str(SceneRouter.last_path).is_equal(SceneRouter.OPENING)


func test_release_choosing_a_pack_that_is_still_refused_stays_on_the_screen() -> void:      # (a manifest and nothing else: a complete pack that lacks everything)
	var screen := _refused_screen()
	PackFiles.write_text(_scratch + "/lonely/pack.json", JSON.stringify({"id": "lonely", "title": "Lonely", "version": "1"}))
	screen.open_pack_screen()
	screen._dialog.select(&"lonely")
	screen._dialog.use_selected()
	assert_array(Packs.chain_ids()).is_equal([&"lonely"])
	assert_bool(Packs.is_refused()).is_true()
	assert_str(SceneRouter.last_path).is_empty()
	assert_object(screen._dialog).is_null()
	assert_str(screen.reason_label.text).contains("'lonely'").contains("is incomplete")
	assert_str(screen.where_label.text).contains("damaged or out of date").contains("docs/play/LEGACY.md")


func test_release_with_no_pack_at_all_the_screen_says_to_run_the_importer() -> void:
	Packs.dev_fallback = false
	Packs.folders = [_scratch]
	Packs.start(PackedStringArray())
	var screen := _screen()
	assert_str(screen.reason_label.text).is_equal("No pack was found, so the game cannot play.")
	assert_str(screen.where_label.text).contains("your own copy of the original").contains("docs/play/LEGACY.md")
	assert_bool(screen.missing_label.visible).is_false()
	screen.open_pack_screen()                                # the pack screen works with no pack in the chain
	assert_object(screen._dialog).is_not_null()
	assert_str(screen._dialog.intro.text).contains("(no pack)")


func test_the_pack_screen_and_the_list_say_the_same_reason() -> void:
	_probe()
	for mode in [true, false]:
		Packs.dev_fallback = mode
		Packs.start(PackedStringArray(["--pack=" + PROBE_ID]))
		var summary := PackChoice.summary()
		assert_str(summary).contains(Packs.fallback_reason().text()).contains(Packs.fallback_reason().advice())
