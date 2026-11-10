class_name GameMenuBar
extends MenuBar
## File / Options / Help along the top of the window, using the original's menu texts.
##
## Teaches: `MenuBar` + `PopupMenu` children (the menu's title is the child's name), items that are
## check boxes, disabled items for features that come in later milestones, and keyboard-only use:
## F10 opens the File menu, then Left / Right switch menus, Up / Down choose, Enter picks and
## Escape closes (the popup itself provides most of that). Everything the menu wants to
## do is reported with signals; the menu changes nothing in the game itself.
##
## The words come from the original's string table (11052-11063).

## Every item is reported as signals and `GameFlow` (shown by `Game`) / `SignIn` decide what happens.
signal sign_in_requested
signal hall_of_fame_requested
signal customization_requested
signal exit_requested
## Options > Audio Settings (our addition: volumes and the music set; works before anybody has signed in).
signal audio_settings_requested
## New Player Hints / Sound Effects / Music / Voice were chosen in the game's Options menu. In the original each one
## opens a Yes / No question ("Do you want the Music on?", 0x42bcdf-0x42bdcd); the bar only reports which one, `GameFlow`
## asks and then calls `set_option`. (Math Practice's short menu still toggles directly: `option_toggled`.)
signal option_dialog_requested(option: StringName)
## A check item of the Options menu changed: `option` is "hints", "sound", "music" or "voice".
signal option_toggled(option: StringName, enabled: bool)
## An item of the Help menu was chosen: its position (0-6) and its text.
signal help_requested(index: int, topic: String)

enum FileItem { SIGN_IN, HALL_OF_FAME, EXIT }
const OPTIONS: Array[StringName] = [&"hints", &"sound", &"music", &"voice"]
## The item we add to the original's Options menu (after "Problem Customization", which has id 4).
const AUDIO_SETTINGS_ID := 5

var _in_menu_loop: bool = false

var file_menu: PopupMenu
var options_menu: PopupMenu
var help_menu: PopupMenu
## On the sign-in screen no player is playing, so "Return to Sign In" and the options that belong to
## a player are greyed out. Set before the bar enters the tree.
@export var sign_in_mode: bool = false
## In Math Practice the menus are the original's short ones: File (Return to Sign In, Exit), Options (Sound
## Effects, Customization) and Help (Math Practice, About). The signals are the same.
@export var practice_mode: bool = false


func _ready() -> void:
	if practice_mode:
		_build_practice_menus()
		return
	file_menu = _add_menu(Catalog.text(&"file_menu_title"), Catalog.text(&"file_menu_items").split("\n"))
	options_menu = _add_menu(Catalog.text(&"options_menu_title"), Catalog.text(&"options_menu_items").split("\n"))
	help_menu = _add_menu(Catalog.text(&"help_menu_title"), Catalog.text(&"help_menu_items").split("\n"))
	# Menu bar order of the original: File, Options, Help.
	file_menu.set_item_disabled(FileItem.SIGN_IN, sign_in_mode)
	file_menu.id_pressed.connect(_on_file_pressed)
	# Options: the first four are check boxes, "Problem Customization" opens a dialog.
	for i in OPTIONS.size():
		options_menu.set_item_as_checkable(i, true)
		options_menu.set_item_checked(i, true)
	for i in options_menu.item_count:
		options_menu.set_item_disabled(i, sign_in_mode)
	options_menu.add_item("Audio Settings...", AUDIO_SETTINGS_ID)       # volumes belong to the machine, not to a player
	options_menu.id_pressed.connect(_on_options_pressed)
	help_menu.id_pressed.connect(func(id: int) -> void: help_requested.emit(id, help_menu.get_item_text(id)))


## The menus of Math Practice (strings 11058-11063).
func _build_practice_menus() -> void:
	file_menu = _add_menu(Catalog.text(&"practice_file_menu_title"), Catalog.text(&"practice_file_menu_items").split("\n"))
	options_menu = _add_menu(Catalog.text(&"practice_options_menu_title"), Catalog.text(&"practice_options_menu_items").split("\n"))
	help_menu = _add_menu(Catalog.text(&"practice_help_menu_title"), Catalog.text(&"practice_help_menu_items").split("\n"))
	options_menu.set_item_as_checkable(0, true)                            # Sound Effects
	options_menu.set_item_checked(0, true)
	options_menu.add_item("Audio Settings...", AUDIO_SETTINGS_ID)
	file_menu.id_pressed.connect(func(id: int) -> void: (sign_in_requested if id == 0 else exit_requested).emit())
	options_menu.id_pressed.connect(_on_practice_options_pressed)
	help_menu.id_pressed.connect(func(id: int) -> void: help_requested.emit(id, help_menu.get_item_text(id)))


func _on_practice_options_pressed(id: int) -> void:
	match id:
		0:
			var enabled := not options_menu.is_item_checked(0)
			options_menu.set_item_checked(0, enabled)
			option_toggled.emit(&"sound", enabled)
		1:
			customization_requested.emit()
		AUDIO_SETTINGS_ID:
			audio_settings_requested.emit()


## Adds one popup menu titled `title` ("&File": the original's ampersand marks a hotkey letter, which
## the Godot MenuBar has no use for) with the given items.
func _add_menu(title: String, items: PackedStringArray) -> PopupMenu:
	var popup := PopupMenu.new()
	popup.name = title.replace("&", "")
	for i in items.size():
		popup.add_item(items[i], i)
	add_child(popup)
	popup.window_input.connect(_on_popup_input.bind(popup))
	popup.about_to_popup.connect(_enter_menu_loop)
	popup.popup_hide.connect(_exit_menu_loop)
	return popup


## While a menu is open the original is inside Windows' menu loop: `MainWindowProc` (0x41312f) answers WM_ENTERMENULOOP
## with `PauseSoundOnDeactivate` (0x413847) and WM_EXITMENULOOP with `ResumeSoundOnActivate` (0x413861). The same
## "window inactive" state as a lost focus: a sounding clip or effect is cut, the song pauses, and the game stands
## still (its input poll does not return, see `GameClock.window_active`).
func _enter_menu_loop() -> void:
	if not _in_menu_loop:
		_in_menu_loop = true
		Audio.pause_sound_on_deactivate()
		GameClock.window_active = false


func _exit_menu_loop() -> void:
	if _in_menu_loop:
		_in_menu_loop = false
		Audio.resume_sound_on_activate()
		GameClock.window_active = true


func _exit_tree() -> void:
	_exit_menu_loop()                                # (a menu that is open when the scene leaves must not freeze the next one)


## Left / Right inside an open menu moves to the neighbouring menu (the PopupMenu alone would just close).
func _on_popup_input(event: InputEvent, popup: PopupMenu) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var step := 0
	if event.is_action(&"ui_left"):
		step = -1
	elif event.is_action(&"ui_right"):
		step = 1
	if step == 0:
		return
	popup.set_input_as_handled()
	popup.hide()
	open_menu(posmod(popup.get_index() + step, get_menu_count()))


## Shows the menu `index` (0 = File) as if its title had been clicked: the keyboard way in.
func open_menu(index: int) -> void:
	var popup := get_menu_popup(index)
	var x := position.x + Catalog.menu_layout().popup_x(index)   # where the title starts: data (`data/ui/menu_layout.tres`, or the skin's), not the width of the titles in front
	popup.popup(Rect2i(Vector2i(int(x), int(position.y + size.y)), Vector2i.ZERO))


## Sets a check item of the Options menu (used at start-up to show the player's saved choice).
func set_option(option: StringName, enabled: bool) -> void:
	options_menu.set_item_checked(OPTIONS.find(option), enabled)


func _on_file_pressed(id: int) -> void:
	match id:
		FileItem.SIGN_IN:
			sign_in_requested.emit()
		FileItem.HALL_OF_FAME:
			hall_of_fame_requested.emit()
		FileItem.EXIT:
			exit_requested.emit()


func _on_options_pressed(id: int) -> void:
	if id == AUDIO_SETTINGS_ID:
		audio_settings_requested.emit()
		return
	if id >= OPTIONS.size():
		customization_requested.emit()
		return
	option_dialog_requested.emit(OPTIONS[id])


## F10 (the `menu_open` action) is the keyboard way to the menu, like Alt in Windows.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"menu_open"):
		get_viewport().set_input_as_handled()
		open_menu(0)
