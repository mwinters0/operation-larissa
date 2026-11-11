class_name SignIn
extends Control
## The sign-in screen: pick a saved player (or make a new one) and start the game.
##
## Teaches: a screen scene built from Controls and the project Theme, `Tree` with columns for a table,
## keyboard-first navigation (Up / Down / Home / End, Enter or S = Start, Insert or N = New, M = Practice, Escape or E = exit, Ctrl+R or Delete =
## remove), the letter keys being the ones `SignInScreenLoop` (0x430c33) reads (capitals and small letters alike),
## modal dialogs opened through a `ModalHost` and answered with signals, and the autoload `SaveStore` as the
## model: this scene only SHOWS `SaveStore.players` and asks it to change. When the player presses
## Start, the chosen profile goes into `GameState.profile` and `SceneRouter` loads the game scene.
##
## Start also plays the "security scan": the two strips of four lights under the frame sweep a red light
## across the green ones while the scanner sound plays. That is an `AnimationPlayer` with one discrete
## `texture` track per strip (a "value" track whose `update` mode is DISCRETE jumps from picture to picture
## instead of blending), built in code from the original's tick counts so no number is typed twice.
##
## The speech is SYNCHRONOUS, as in the original (`SignInSpeech` 0x42fe4d loops on `IsWavePlaying` until each clip has ended):
##   * every entry to the screen (`sign_in` 0x431420 sets `SignInWelcomePending` on each call; `SignInScreenLoop` 0x430c33 then
##     says `SignInSpeech(1)`, so a Return to Sign-In or a finished game hears it again; Math Practice and a cancelled dialog
##     return into the same loop iteration and do not): "This is a highly classified mission ..." and "Please
##     enter your name ...". The list does not react meanwhile. ANY key or mouse press cuts the speech (both clips), and
##     that same key or click is then delivered to the list (the original's `PeekInput` 0x410d50 only PEEKS: the event
##     stays pending until the screen's `WaitForInput` takes it);
##   * Start (`sign_in` 0x431420 -> `SignInSpeech(2 / 3)`): 18 ticks, the scan, the clearance clip, then the begin-or-resume-mission
##     clip. The game starts only when the last clip has ended. Esc, Enter or a click cuts the speech (the
##     whole rest of it: the event stays pending); Enter also ends the scan; any other key is swallowed;
##   * with the Voice option off no clip is started, `IsWavePlaying` is false at once and nothing is waited for.
##
## Original: SIGNIN.C, with the "Security Clearance" frame (picture 1054) and the buttons Start / New /
## Practice / Exit (DESIGN 2 item 2); the scan is `AnimateSecurityScan` (0x42fca0) (DESIGN 2 item 2, "Security scan").

const NEW_PLAYER_DIALOG := preload("res://src/ui/new_player_dialog.tscn")
const HALL_OF_FAME := preload("res://src/ui/hall_of_fame.tscn")
const HELP_VIEWER := preload("res://src/ui/help_viewer.tscn")
const AUDIO_SETTINGS_DIALOG := preload("res://src/ui/audio_settings_dialog.tscn")
const PACK_DIALOG := preload("res://src/ui/pack_dialog.tscn")
## The theme's look of a button that is pressed (`_show_pressed`).
const PRESSED_LOOK := &"SignInPressed"

## The original counts time in 1/73 s ticks (`DelayTicks`).
const TICK_SECONDS := 1.0 / 73.0
## The waits of this screen are data (`sign_in.*` of `data/rules/durations.json`, `Durations`); the original's numbers are in the
## comments. Start: the screen waits 18 ticks (`DelayTicks(0x12)`), then runs the scan.
static func pre_scan_ticks() -> int:
	return Durations.at("sign_in.pre_scan_ticks")


## New (and Start, when the game is customized): the button looks pressed for 36 ticks before the dialog opens
## (`DelayTicks(0x24)` 0x4311be and 0x431142 in `SignInScreenLoop`).
static func pressed_ticks() -> int:
	return Durations.at("sign_in.pressed_ticks")


## One picture of the scan stays 5 ticks (`DelayTicks(5)`); four pictures make a sweep; the scan is six sweeps.
static func scan_picture_ticks() -> int:
	return maxi(Durations.at("sign_in.scan_ticks_per_picture"), 1)


static func scan_sweeps() -> int:
	return maxi(Durations.at("sign_in.scan_sweeps"), 1)

## The scan's pictures (bundle 115 of the original, 100 x 22 px, each a strip of four lights, `scanner_strip_0` ..
## `scanner_strip_4`): 0-3 have the red light at position 0-3, 4 is all green (the strip drawn into the frame, and what the
## screen shows at rest).
const SCAN_PICTURE_COUNT := 5
const SCAN_PATH_LEFT := ^"Frame/LeftLights:texture"
const SCAN_PATH_RIGHT := ^"Frame/RightLights:texture"
## The scanner effect (`sound` name `scanner`, the original's common sound 0x1d).
const SFX_SCANNER := &"scanner"
## Keys that produce no character: the original's input queue never sees them.
const MODIFIER_KEYS: Array[Key] = [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]

signal scan_finished
## The player answered Yes to "exit the program?": the original's `QuitProgram` (0x42b900). The screen emits this and then
## quits the tree unless `quits_program` is false (tests).
signal quit_requested

var messages := MessageQueue.new(GameClock)

## The welcome speech ("This is a highly classified mission ...") is spoken on EVERY entry to the screen, as in the original
## (`sign_in` 0x431420 sets `SignInWelcomePending` 0x442fc8 on each call) ... except when Math Practice hands back: the original
## calls the practice from inside the loop and returns into the same iteration (0x43122f-0x431234), the port reloads the scene
## and so `request_practice` sets this flag for the next `_ready`. A `static var` belongs to the class.
static var returning_from_practice: bool = false

## Tests only: false keeps the welcome speech from holding the list back (it has its own tests).
static var welcome_enabled: bool = true

## The original's `NewPlayerAdded` (0x442f98): set by `AddNewPlayer` (0x430851) and never cleared during the run of the program.
## `sign_in` (0x431420) says the begin clip after the clearance clip when it is set, else the resume clip: so once a
## player was added with New, every later Start of the run says begin, whoever the player is.
static var new_player_added: bool = false

## With no player in the roster `SignInRun` (0x43136f) never shows the list: it asks for a new player until one is made (the
## exit question in between). Tests that want the bare list switch this off.
static var prompt_when_empty: bool = true

## False in tests: `quit_requested` is emitted but the tree is left alone.
var quits_program: bool = true

@onready var tree: Tree = %Players
@onready var start_button: Button = %Start
@onready var new_button: Button = %New
@onready var practice_button: Button = %Practice
@onready var exit_button: Button = %Exit
@onready var packs_button: Button = %Packs
@onready var menu_bar: GameMenuBar = %MenuBar
@onready var message_view: MessageBoxView = %MessageBox
@onready var overlay: CanvasLayer = %Overlay
@onready var info_label: Label = %Info
@onready var frame: TextureRect = $Frame
@onready var left_lights: TextureRect = %LeftLights
@onready var right_lights: TextureRect = %RightLights
@onready var scan_animation: AnimationPlayer = %ScanAnimation
@onready var button_row: HBoxContainer = $Buttons

## The message box and the dialogs (new player, hall of fame, help, audio, packs): while one is open the list and the buttons sleep.
var modals: ModalHost
## True while the screen itself is busy (the welcome speech, the pressed look before New, the way into the game): its buttons and
## keys sleep.
var _busy: bool = false

## What the screen is doing with the keyboard and the mouse (`SignInSpeech`'s polling loops).
enum Listening { NOTHING, FIRST_VISIT_SPEECH, SCAN, CLEARANCE_SPEECH }
var _listening: Listening = Listening.NOTHING
## The original's `PendingInput` for the scan and the clearance speech: the first input that arrived while the scan ran.
## `CUT` (Esc, Enter, a click) cuts the speech that follows; `OTHER` (any other key) is swallowed when the speech starts.
enum Pending { NONE, CUT, OTHER }
var _pending: Pending = Pending.NONE
## The key or click that cut the first-visit speech: it goes on to the list afterwards.
var _cut_event: InputEvent
var _leaving: bool = false


func _ready() -> void:
	frame.texture = Assets.ui_picture(&"sign_in_frame")              # (pictures are found by name, not by file: the scene holds none)
	left_lights.texture = scan_pictures()[SCAN_PICTURE_COUNT - 1]    # at rest the scanner is all green
	right_lights.texture = left_lights.texture
	var skipped_welcome := returning_from_practice                         # (a flag for ONE entry)
	returning_from_practice = false
	Audio.stop_music()                                    # (coming back from a game) the original has no music here
	Audio.apply_profile(null)                             # nobody is signed in: all sounds on
	menu_bar.audio_settings_requested.connect(show_audio_settings)
	modals = ModalHost.new(self, [tree, button_row, packs_button], tree)
	modals.attach(messages, message_view)
	var library := AnimationLibrary.new()
	library.add_animation(&"scan", _scan_animation())
	scan_animation.add_animation_library(&"", library)
	scan_animation.animation_finished.connect(_on_scan_animation_finished)
	tree.columns = 4
	tree.column_titles_visible = true
	tree.hide_root = true
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		tree.set_focus_neighbor(side, ^".")                               # (an arrow at the edge of the list keeps the focus on it; Tab leaves)
	for column in 4:
		tree.set_column_title(column, ["Name", "Game", "Zone", "Sector"][column])
	tree.set_column_expand(0, true)
	tree.item_activated.connect(request_start)
	tree.item_selected.connect(_update_buttons)
	start_button.pressed.connect(request_start)
	new_button.pressed.connect(request_new_player)
	practice_button.pressed.connect(request_practice)
	exit_button.pressed.connect(ask_to_exit)
	packs_button.pressed.connect(show_packs)
	menu_bar.hall_of_fame_requested.connect(show_hall_of_fame)
	menu_bar.exit_requested.connect(ask_to_exit)
	menu_bar.help_requested.connect(show_help)
	SaveStore.roster_changed.connect(refresh)
	SaveStore.write_failed.connect(_on_write_failed)
	refresh()
	tree.grab_focus()
	if SaveStore.players.is_empty() and prompt_when_empty:
		_ask_for_first_player()                                           # (`SignInRun`: the list loop, and its welcome speech, never run)
		return
	if welcome_enabled and not skipped_welcome:
		await _first_visit_speech()                                       # (the screen is drawn; nobody waits for _ready)


func _exit_tree() -> void:
	_leaving = true
	if _listening != Listening.NOTHING:
		Audio.stop_voice()                                                # (a speech coroutine that waits ends with the screen)


# --- the speech (SignInSpeech 0x42fe4d) -----------------------------------------------------

## `SignInSpeech(1)` (when `SignInWelcomePending` is set): the two welcome clips; the list sleeps until they have ended or a key / click cuts them.
func _first_visit_speech() -> void:
	_busy = true
	_listening = Listening.FIRST_VISIT_SPEECH
	await _speak(Catalog.voice_cues().sign_in_first_visit())
	if _leaving:
		return
	_listening = Listening.NOTHING
	_busy = false
	tree.grab_focus()
	if _cut_event != null:                                                # the cutting key / click is now the list's
		var event := _cut_event
		_cut_event = null
		await get_tree().process_frame
		if not _leaving:
			Input.parse_input_event(event)


## Says `clips` and returns when they have ended or were cut off. With the Voice option off nothing is started and
## nothing is waited for (the original skips `PlayWave`, `IsWavePlaying` is false at once).
func _speak(clips: Array[StringName]) -> void:
	var audible := Audio.is_bus_enabled(AudioService.VOICE) and not clips.is_empty()
	Audio.play_voice_sequence(clips)
	if audible and Audio.is_voice_playing():
		await Audio.voice_finished


## The keyboard and the mouse while the screen is busy with its speech or its scan (the polling loops of `SignInSpeech`
## and `AnimateSecurityScan` 0x42fca0).
func _listen(event: InputEvent) -> void:
	var key := event as InputEventKey
	var button := event as InputEventMouseButton
	var is_key := key != null and key.pressed and not key.echo and key.keycode not in MODIFIER_KEYS
	var is_press := button != null and button.pressed and button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	var is_release := button != null and not button.pressed and button.button_index == MOUSE_BUTTON_LEFT
	if not (is_key or is_press or is_release):
		return
	get_viewport().set_input_as_handled()                                 # (the list and the buttons sleep)
	var cuts := (is_key and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]) or is_release
	match _listening:
		Listening.FIRST_VISIT_SPEECH:
			if (is_key or is_press) and _cut_event == null:
				_cut_event = event.duplicate()
				Audio.stop_voice()
		Listening.SCAN:
			# `PeekInput` keeps the first input: Enter (or a click: 0xc33) ends the scan, nothing else does, and a first
			# input of another kind keeps the later Enter from being seen at all
			if _pending != Pending.NONE:
				return
			_pending = Pending.CUT if (cuts or is_press) else Pending.OTHER
			if (is_key and key.keycode in [KEY_ENTER, KEY_KP_ENTER]) or is_release:
				skip_scan()
		Listening.CLEARANCE_SPEECH:
			if cuts:
				Audio.stop_voice()


# --- the list ----------------------------------------------------------------------------

## Rebuilds the table from the roster, keeping the selection if the player still exists; if it is gone (removed), the row that
## took its place is selected (the one after it, or the last).
func refresh() -> void:
	var previous := selected_profile()
	var previous_row := tree.get_selected().get_index() if tree.get_selected() != null else 0
	tree.clear()
	var root := tree.create_item()
	var to_select: TreeItem = null
	for profile in SaveStore.players:
		var row := tree.create_item(root)
		row.set_metadata(0, profile)
		row.set_text(0, profile.name)
		var campaign := profile.campaign()
		row.set_text(1, profile.campaign_title() + (" (c)" if profile.customized else ""))
		if not profile.is_playable():                                    # (a campaign that is not installed: the record waits for it)
			row.set_text(2, "-")
			row.set_text(3, "not installed")
		else:
			row.set_text(2, "Final" if profile.at_finale() else "%d" % (profile.zone() + 1))
			row.set_text(3, "Final" if profile.at_finale() else "%d of %d" % [campaign.position_of(profile.sector()) + 1, campaign.sector_count()])
		if profile == previous:
			to_select = row
	if to_select == null and root.get_child_count() > 0:
		to_select = root.get_child(mini(previous_row, root.get_child_count() - 1))
	if to_select != null:
		to_select.select(0)
	info_label.text = "%d of %d names" % [SaveStore.players.size(), SaveStore.MAX_PLAYERS] if not SaveStore.players.is_empty() else ""
	packs_button.visible = PackChoice.any()                              # (our addition: with no pack installed the screen is the original's; the P key is always there)
	_update_buttons()


func selected_profile() -> PlayerProfile:
	var item := tree.get_selected()
	return item.get_metadata(0) as PlayerProfile if item != null else null


## Selects the row of `profile` (for tests and for coming back from a game).
func select(profile: PlayerProfile) -> void:
	var item := tree.get_root().get_first_child() if tree.get_root() != null else null
	while item != null:
		if item.get_metadata(0) == profile:
			item.select(0)
			return
		item = item.get_next()


## Home (0x124) selects the first name and End (0x123) the last, as `SignInScreenLoop` (0x430c33) does; the Godot `Tree` has no
## `ui_home` / `ui_end`. `index` -1 is the last row. The row is scrolled into view and selected as an arrow key does it.
func _select_row(index: int) -> void:
	var root := tree.get_root()
	if root == null or root.get_child_count() == 0:
		return
	var row := root.get_child(index)
	row.select(0)                                                        # (emits `item_selected`, which refreshes the buttons)
	tree.scroll_to_item(row)


func _update_buttons() -> void:
	var profile := selected_profile()
	start_button.disabled = profile == null or not profile.is_playable()


# --- actions -----------------------------------------------------------------------------

## Start: the selected player enters the game.
## Start: the security scan runs, then the selected player enters the game. A coroutine: callers that need to
## know when the screen has changed `await` it (the buttons just call it).
func request_start() -> void:
	var profile := selected_profile()
	if profile == null or _asleep() or not profile.is_playable():
		return
	_show_pressed(start_button)                                          # (it stays pressed: the screen leaves for the game)
	await _enter_game(profile)


## What follows the end of the list loop, for Start and for a successful New alike (`sign_in` 0x431420): the player's switches,
## the customized notice, the scan, the clearance clip and the begin-or-resume clip, then the game.
func _enter_game(profile: PlayerProfile) -> void:
	GameState.begin_run(profile)                                         # `SignIn` (0x42e028): the chosen record becomes the current player's
	Audio.apply_profile(profile)                                         # `sign_in` (0x431420): SoundOn / MusicOn / VoiceOn := the player's, before the speech
	_busy = true                                                         # the screen is busy: its buttons and keys sleep
	if profile.customized:
		# "This Voyager game has been customized ...": after 36 ticks, still on the sign-in screen, before the scan
		await get_tree().create_timer(pressed_ticks() * TICK_SECONDS).timeout
		var notice := messages.post("Operation Neptune", GameFlow.customized_notice_text(profile))
		await notice.closed
	await get_tree().create_timer(pre_scan_ticks() * TICK_SECONDS).timeout
	_pending = Pending.NONE                                              # (`FlushInput`)
	_listening = Listening.SCAN
	await run_scan()
	if _leaving:
		return
	# the clearance clip, then the begin clip (or the resume clip): the game starts when the last clip has ended
	var resuming := not new_player_added                                 # `NewPlayerAdded` (0x442f98), not the player's progress
	_listening = Listening.CLEARANCE_SPEECH
	if _pending != Pending.CUT:                                          # (a cut that is already pending cuts the clips at their first poll)
		await _speak(Catalog.voice_cues().sign_in_start(resuming))
		if _leaving:
			return
	_listening = Listening.NOTHING
	SceneRouter.go_to(SceneRouter.GAME)


## The security scan: the scanner sound and the lights sweeping (left strip 0, 1, 2, 3; right strip 3, 2, 1, 0; six
## times). Returns when the animation is over. The original cuts the sound at that moment (the wave device is
## reset before the next sound), so the 3.15 s effect is heard for about the first 1.6 s.
func run_scan() -> void:
	Audio.play_sfx(SFX_SCANNER)
	scan_animation.play(&"scan")
	await scan_finished
	Audio.stop_sfx()


## Enter (or a released click) shortens the scan, the way `AnimateSecurityScan` (0x42fca0) does: it looks at the input once
## per picture, and with Enter pending its inner loop (the four pictures of a sweep) ends after the picture that is showing;
## the outer loop still runs the remaining sweeps, each with its first picture only (5 ticks). So the scan does not stop at
## once: the picture finishes, then every sweep that is left shows picture 0.
func skip_scan() -> void:
	if not scan_animation.is_playing() or scan_animation.current_animation != &"scan":
		return
	var library := scan_animation.get_animation_library(&"")
	if library.has_animation(&"scan_cut"):
		library.remove_animation(&"scan_cut")
	library.add_animation(&"scan_cut", _cut_scan_animation(scan_animation.current_animation_position))
	scan_animation.play(&"scan_cut")


## The five scanner pictures, asked of `Assets` each time: they depend on the pack chain and the skin in use, so nothing keeps them
## (the textures themselves are cached where they are loaded).
static func scan_pictures() -> Array[Texture2D]:
	var pictures: Array[Texture2D] = []
	for i in SCAN_PICTURE_COUNT:
		pictures.append(Assets.ui_picture(StringName("scanner_strip_%d" % i)))
	return pictures


## Seconds the scan still takes when the skip arrives `elapsed` seconds into it (see `skip_scan`).
static func seconds_left_after_skip(elapsed: float) -> float:
	var picture_seconds := scan_picture_ticks() * TICK_SECONDS
	var step := clampi(int(elapsed / picture_seconds), 0, scan_sweeps() * 4 - 1)
	var sweeps_left := scan_sweeps() - 1 - step / 4
	return (step + 1) * picture_seconds - elapsed + sweeps_left * picture_seconds


## The rest of the scan after a skip at `elapsed`: the picture that is showing, then picture 0 once per sweep that is left,
## then the all-green picture.
func _cut_scan_animation(elapsed: float) -> Animation:
	var picture_seconds := scan_picture_ticks() * TICK_SECONDS
	var step := clampi(int(elapsed / picture_seconds), 0, scan_sweeps() * 4 - 1)
	var sweeps_left := scan_sweeps() - 1 - step / 4
	var rest := (step + 1) * picture_seconds - elapsed
	var animation := Animation.new()
	var left := animation.add_track(Animation.TYPE_VALUE)
	var right := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(left, SCAN_PATH_LEFT)
	animation.track_set_path(right, SCAN_PATH_RIGHT)
	for track in [left, right]:
		animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	var pictures := scan_pictures()
	animation.track_insert_key(left, 0.0, pictures[step % 4])
	animation.track_insert_key(right, 0.0, pictures[3 - step % 4])
	for sweep in sweeps_left:
		animation.track_insert_key(left, rest + sweep * picture_seconds, pictures[0])
		animation.track_insert_key(right, rest + sweep * picture_seconds, pictures[3])
	animation.length = rest + sweeps_left * picture_seconds
	animation.track_insert_key(left, animation.length, pictures[4])
	animation.track_insert_key(right, animation.length, pictures[4])
	return animation


func _on_scan_animation_finished(_animation_name: StringName) -> void:
	scan_finished.emit()


## The scan as an Animation: one DISCRETE value track per strip of lights. Picture `i % 4` on the left and `3 - i % 4`
## on the right, one picture per `scan_picture_ticks()`, and the all-green picture at the very end.
func _scan_animation() -> Animation:
	var animation := Animation.new()
	var left := animation.add_track(Animation.TYPE_VALUE)
	var right := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(left, SCAN_PATH_LEFT)
	animation.track_set_path(right, SCAN_PATH_RIGHT)
	for track in [left, right]:
		animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	var step_seconds := scan_picture_ticks() * TICK_SECONDS
	var steps := scan_sweeps() * 4
	var pictures := scan_pictures()
	for step in steps:
		animation.track_insert_key(left, step * step_seconds, pictures[step % 4])
		animation.track_insert_key(right, step * step_seconds, pictures[3 - step % 4])
	animation.length = steps * step_seconds
	animation.track_insert_key(left, animation.length, pictures[4])
	animation.track_insert_key(right, animation.length, pictures[4])
	return animation


## New: asks for a name and a game, adds the player and starts the game at once (`AddNewPlayer` 0x430851 returns the slot,
## `SignInScreenLoop` ends and `sign_in` runs the scan and "Begin mission"). Esc in either dialog cancels the whole New.
func request_new_player() -> void:
	if _asleep():
		return
	_busy = true
	_show_pressed(new_button)
	await get_tree().create_timer(pressed_ticks() * TICK_SECONDS).timeout
	_release_buttons()
	_busy = false
	if SaveStore.is_full():
		messages.post("Operation Neptune", Catalog.text(&"roster_full_text").replace("\r", "\n").replace("\u0006", "Ctrl+R").replace("\u001c or \u001b", "Up or Down"))
		return
	_open_new_player_dialog(_on_new_player_done)


## The name dialog, then the game level dialog (`AddNewPlayer`). `done` is called with the new player (already in the roster and
## selected), or with null when the player backed out with Esc.
func _open_new_player_dialog(done: Callable) -> void:
	var dialog: NewPlayerDialog = NEW_PLAYER_DIALOG.instantiate()
	dialog.cancelled.connect(func() -> void:
		dialog.queue_free()
		done.call(null))
	dialog.confirmed.connect(func(player_name: String, campaign_id: StringName) -> void:
		dialog.queue_free()                                              # (no check for a name already taken: the original has none)
		done.call(add_player_in(player_name, Catalog.campaign(campaign_id))))
	modals.open(dialog, overlay)


## New succeeded: the list loop ends and the game starts at once, the New button still pressed.
func _on_new_player_done(profile: PlayerProfile) -> void:
	if profile != null and not _leaving:
		_show_pressed(new_button)
		await _enter_game(profile)


## `SignInRun` (0x43136f) with an empty roster: `AddNewPlayer` again and again; when it is cancelled the exit question
## (strings 11191 / 11192) follows, Yes quits and No asks for a new player again. The list is never shown.
func _ask_for_first_player() -> void:
	_open_new_player_dialog(_on_first_player_done)


func _on_first_player_done(profile: PlayerProfile) -> void:
	if _leaving:
		return
	if profile != null:
		_show_pressed(new_button)
		await _enter_game(profile)
	elif not await _ask_exit_question() and not _leaving:
		_ask_for_first_player()


## A save did not reach the disk: the "Write Error" dialog (`write_users_dat` 0x41bce2).
func _on_write_failed(_path: String) -> void:
	SaveStore.post_write_error(messages)


## `AddNewPlayer` without the dialogs: the record copies the Sound / Music / Voice switches that are on now and
## `NewPlayerAdded` is set for the rest of the run.
func add_player(player_name: String, game: int) -> PlayerProfile:
	return add_player_in(player_name, Catalog.campaign_for_game(game))


## `add_player` for any campaign: the new-player dialog hands the one the player chose.
func add_player_in(player_name: String, campaign: Campaign) -> PlayerProfile:
	var profile := SaveStore.add_player_in(player_name, campaign, Audio.is_bus_enabled(AudioService.SFX),
			Audio.is_bus_enabled(AudioService.MUSIC), Audio.is_bus_enabled(AudioService.VOICE))
	if profile != null:
		new_player_added = true
		select(profile)
	return profile


## Ctrl+R (character 0x12 in `SignInScreenLoop` 0x430c33): the question title 11188 and text 11186 + name + 11187
## (`ConcatStrings` 0x42f486), Yes / No; Yes erases the selected name for good (`RemoveRosterSlot` 0x42f6eb).
func request_remove() -> void:
	var profile := selected_profile()
	if profile == null or _asleep():
		return
	var message := messages.post(Catalog.text(&"remove_player_title"), remove_question(profile.name), PackedStringArray(["Yes", "No"]))
	var choice: int = await message.closed
	if choice == 0:
		SaveStore.remove_player(profile)
		if SaveStore.players.is_empty() and prompt_when_empty:
			_ask_for_first_player()                                      # the loop ends with no player: `SignInRun` asks for a new one


## The text of the remove question: string 11186 + the name + string 11187, as `ConcatStrings` joins them. The two strings
## carry the original's font markers (ÿ, code, ÿ: the name is set in another style), which have no width and go here.
static func remove_question(player_name: String) -> String:
	var markers := RegEx.create_from_string("ÿ[\\x00-\\x1f]*ÿ")
	var text := markers.sub(Catalog.text(&"remove_player_before"), "", true) + player_name + markers.sub(Catalog.text(&"remove_player_after"), "", true)
	return text.replace("\r", "\n")


## Practice: the math practice scene (`PracticeMode`). It needs no player, so nothing is saved.
func request_practice() -> void:
	if _asleep():
		return
	_show_pressed(practice_button)                                       # (no pause: the practice screen replaces this one)
	returning_from_practice = true                                       # (the original returns into the same loop iteration: no welcome)
	SceneRouter.go_to(SceneRouter.PRACTICE)


func ask_to_exit() -> void:
	if _asleep():
		return
	await _ask_exit_question()


## "Exit" / "Do you want to exit ..." (strings 11191 / 11192): Yes leaves the program (`QuitProgram` 0x42b900). Returns true on Yes.
func _ask_exit_question() -> bool:
	_show_pressed(exit_button)
	var message := messages.post(Catalog.text(&"sign_in_exit_title"), Catalog.text(&"sign_in_exit_text").replace("\r", "\n"), PackedStringArray(["Yes", "No"]))
	var choice: int = await message.closed
	if choice == 0:
		quit_requested.emit()
		if quits_program:
			get_tree().quit()
		return true
	_release_buttons()
	return false


## The pressed look of the original's picture buttons (`SetSignInButtonLooks` 0x42f611 draws the pressed picture of one of
## the four buttons): the theme's type variation `SignInPressed` (`ThemeBuilder`: the "pressed" box and font colour of a Button as its normal look). Nothing is copied: the button looks the variation up, so a skin put on while it is pressed shows in it.
func _show_pressed(button: Button) -> void:
	_release_buttons()
	button.theme_type_variation = PRESSED_LOOK


func _release_buttons() -> void:
	for button: Button in [start_button, new_button, practice_button, exit_button]:
		button.theme_type_variation = &""


## True while `button` wears the pressed look (for tests).
func looks_pressed(button: Button) -> bool:
	return button.theme_type_variation == PRESSED_LOOK


func show_hall_of_fame() -> void:
	if _asleep():
		return
	modals.open(HALL_OF_FAME.instantiate(), overlay)                     # (it frees itself)


func show_audio_settings() -> void:
	if _asleep():
		return
	var dialog: AudioSettingsDialog = AUDIO_SETTINGS_DIALOG.instantiate()
	dialog.closed.connect(dialog.queue_free)
	modals.open(dialog, overlay)


## Packs (our addition): the pack screen. The P key opens it from this screen always; the small Packs button shows only when a pack
## is installed in the player's folder, so a game with no pack installed looks as the original did. A pack that was installed or removed changes who can be played
## (a record of a campaign of a pack waits for it), so the roster is shown again.
func show_packs() -> void:
	if _asleep():
		return
	var dialog: PackDialog = PACK_DIALOG.instantiate()
	dialog.changed.connect(refresh)
	dialog.closed.connect(func() -> void:
		dialog.queue_free()
		refresh())
	modals.open(dialog, overlay)


func show_help(index: int, _topic: String) -> void:
	if _asleep():
		return
	var viewer: HelpViewer = HELP_VIEWER.instantiate()
	modals.open(viewer, overlay, func() -> void: viewer.show_topic(index))    # (it frees itself)


## The list and the buttons do nothing while the screen is busy or a message or a dialog is open.
func _asleep() -> bool:
	return _busy or modals.is_open()


func _input(event: InputEvent) -> void:
	if _listening != Listening.NOTHING:
		_listen(event)


func _unhandled_key_input(event: InputEvent) -> void:
	if _asleep() or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	# `SignInScreenLoop` reads characters (WM_CHAR): S / s Start, N / n New, M / m Practice, and the two letters of string 11208
	# ("Ee") Exit, as Esc; with Ctrl or Alt held no such character arrives
	var letter := ""
	if not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed and key.keycode >= KEY_A and key.keycode <= KEY_Z:
		letter = char(key.keycode)                                        # (the keycode of a letter is its capital)
	if letter == "S":
		get_viewport().set_input_as_handled()
		request_start()
		return
	if letter == "N":
		get_viewport().set_input_as_handled()
		request_new_player()
		return
	if letter == "M":
		get_viewport().set_input_as_handled()
		request_practice()
		return
	if letter == "P":
		get_viewport().set_input_as_handled()
		show_packs()                                                      # (not a key of the original: `SignInScreenLoop` has no use for it)
		return
	if letter != "" and letter in Catalog.text(&"expert_key_letters").to_upper():
		get_viewport().set_input_as_handled()
		ask_to_exit()
		return
	# Deliberate deviation from the original: `SignInScreenLoop` (0x430c33) removes a name only on character 0x12
	# (Ctrl+R) and ignores the Delete key (0x12e); the port takes Delete as well, the key a player expects.
	var ctrl_r := key.keycode == KEY_R and key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed
	if ctrl_r or key.keycode == KEY_DELETE:
		get_viewport().set_input_as_handled()                             # Ctrl+R = character 0x12 (or Delete): remove the highlighted name
		request_remove()
		return
	match key.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			ask_to_exit()
		KEY_HOME:
			get_viewport().set_input_as_handled()
			_select_row(0)
		KEY_END:
			get_viewport().set_input_as_handled()
			_select_row(-1)
		KEY_INSERT:
			get_viewport().set_input_as_handled()
			request_new_player()
