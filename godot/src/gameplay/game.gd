class_name Game
extends Node
## The VIEW of one player's mission: the scene that holds the playfield, the console, the menu bar and the layers where screens and
## dialogs are put, and that shows what the flow decides. The decisions are not here: they are `GameFlow` (`flow`,
## src/rules/game_flow.gd), a plain object that knows no node.
##
## Teaches: a scene that SHOWS a flow and contains neither rules nor flow. `SectorWorld` knows the water, `GameState` knows
## the numbers, `SaveStore` the files, `Hud` shows them, `MessageQueue` orders the dialogs, `GameFlow` decides what happens at the
## seams; this script only turns the flow's requests into nodes, and answers by finishing what the flow awaits:
##
##   * a math problem is requested  -> the flow makes it, `show_problem` puts a `ProblemScreen` up, the flow tells the world how it went
##   * the sub docks at the last screen -> pieces missing? `show_pieces_missing`. Otherwise the combination lock; solved: the supply
##     station message (`show_supply_message`, the surface ship screen), the balloon, the next sector (`IncrementSector`)
##   * `GameState.tank_lost` (result code 1)  -> respawn: screen 6 past the midpoint, else the station; pieces kept
##   * `GameState.game_over` (result code 2) -> the sector starts over: ink refilled, pieces cleared, tries + 1
##   * after sector 14 (29) comes the finale sector (30 / 31): launched from the station like any sector, no pieces to find; the
##     creature that holds the Substance X / Alien Artifact sets a semaphore bit, and on the finale screen the closing sequence
##     plays (`show_closing`)
##   * after the closing sequence the player goes into the Hall of Fame (`show_hall_of_fame`)
##
## THE CONTRACT (`GameFlow.VIEW_METHODS`): `show_pieces_missing`, `show_supply_message`, `show_problem`, `show_closing` and
## `show_hall_of_fame` (each comes back when the player is done with the screen), `play_sector_music`, `stop_music`, `go_to_sign_in`
## and `quit_game`. What else stays here: the `ModalHost` that puts the problem layer to sleep while a message or a dialog is up, holding the music and
## the game clock for them, the menu bar and its dialogs (help, customization, audio settings), and the keys of the closing sequence.
##
## The player comes from `GameState.profile` (set by the sign-in screen). Started on its own (F6, or the tests) the scene runs in
## "free play" with a throw-away player that is never saved.
##
## Layout of the 640 x 400 window: the menu strip (y 0-22), the playfield at (16, 32), and the console
## under it (the `Hud`). Escape asks "Do you want to exit?". The F3 cheat keys live in `GameDebug`
## (src/debug), a child scene that removes itself from release builds.

const SURFACE_SHIP_SCREEN := preload("res://src/story/surface_ship_screen.tscn")
const HALL_OF_FAME := preload("res://src/ui/hall_of_fame.tscn")
const HELP_VIEWER := preload("res://src/ui/help_viewer.tscn")
const CUSTOMIZATION_DIALOG := preload("res://src/ui/customization_dialog.tscn")
const AUDIO_SETTINGS_DIALOG := preload("res://src/ui/audio_settings_dialog.tscn")
const VOYAGER_CLOSING := preload("res://src/story/voyager_closing.tscn")
const EXPERT_CLOSING := preload("res://src/story/expert_closing.tscn")
const GENERIC_FINALE := preload("res://src/story/generic_finale.tscn")

## Free play only: the sector to start in and the educational level of the demo player (0-3).
@export var start_sector: int = 0
@export var edu_level: int = 1

var messages := MessageQueue.new(GameClock)
## What happens next (see above). Made in `_ready`, when the playfield exists.
var flow: GameFlow
## True while the music is held for a message box (see `_on_message_shown`).
var _music_held_for_message: bool = false
## True once the scene has let go of the autoloads (`_leave`).
var _left: bool = false

## The closing sequence while it plays (it takes the keys), else null.
var closing: StorySegment

# The state the flow keeps, for the tests and tools that ask the scene.
var profile: PlayerProfile:
	get:
		return flow.profile
## True when no player was chosen (the scene was started directly): nothing is saved.
var free_play: bool:
	get:
		return flow.free_play
## True while a scripted sequence (docking, a respawn) runs; the dock and loss handlers wait.
var busy: bool:
	get:
		return flow.busy

@onready var world: SectorWorld = %SectorWorld
@onready var menu_bar: GameMenuBar = %MenuBar
@onready var problem_layer: CanvasLayer = %ProblemLayer
@onready var dialog_layer: CanvasLayer = %DialogLayer
@onready var message_view: MessageBoxView = %MessageBox

## The message box and the dialogs: while one is open the problem screen below sleeps (the calculator would type the digits and
## Enter would submit).
var modals: ModalHost


func _ready() -> void:
	flow = GameFlow.new(GameState, SaveStore, messages)
	flow.world = world
	flow.view = self
	flow.enter(start_sector, edu_level)
	GameClock.paused = false

	modals = ModalHost.new(self, [problem_layer])
	modals.attach(messages, message_view)
	messages.message_shown.connect(_on_message_shown)
	SceneRouter.leaving.connect(_on_scene_leaving)
	flow.option_changed.connect(_on_option_changed)
	menu_bar.exit_requested.connect(flow.ask_to_exit)
	menu_bar.sign_in_requested.connect(flow.ask_to_return_to_sign_in)
	menu_bar.hall_of_fame_requested.connect(show_hall_of_fame)
	menu_bar.customization_requested.connect(show_customization)
	menu_bar.audio_settings_requested.connect(show_audio_settings)
	menu_bar.option_dialog_requested.connect(flow.ask_option)
	menu_bar.option_toggled.connect(flow.set_option)
	menu_bar.help_requested.connect(_on_help_requested)
	for option: StringName in GameFlow.OPTION_QUESTIONS:
		menu_bar.set_option(option, flow.option_is_on(option))
	Audio.apply_profile(profile)                          # the player's own Sound / Music / Voice switches

	await flow.begin_mission()


## Saves when the window is closed (the red cross, Alt+F4): the same as choosing Exit. Then the program tears the tree down.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and flow != null:
		flow.save_progress()
		_leave()


# --- leaving ------------------------------------------------------------------------------------

## The scene goes away (`SceneRouter.leaving`, before its children exit).
func _on_scene_leaving(_path: String) -> void:
	_leave()


## Godot runs the children's `_exit_tree` before this one, so a scene that is only taken out of the tree (a test, a tool) gets here last;
## its children are safe on their own (a problem screen drops its held loss, the world its dissolve).
func _exit_tree() -> void:
	_leave()


## The scene lets go of everything that outlives it, ONCE, before its children exit whenever it is told in time (`SceneRouter.leaving`,
## the window closed, `quit_game`): the flow stops listening to the autoloads, so nothing a child gives back on its way out (a lost tank,
## a game over) reaches it; the message queue forgets its messages and gives back the clock; the song and the speech stop and a pause
## the message box held is given back. See docs/engine/ARCHITECTURE.md, "Lifetimes of state".
func _leave() -> void:
	if _left or flow == null:
		return
	_left = true
	if SceneRouter.leaving.is_connected(_on_scene_leaving):
		SceneRouter.leaving.disconnect(_on_scene_leaving)
	flow.leave()
	messages.message_shown.disconnect(_on_message_shown)
	messages.discard()
	Audio.stop_music()
	Audio.stop_voice()
	if _music_held_for_message:
		_music_held_for_message = false
		Audio.resume_sound()


func _unhandled_input(event: InputEvent) -> void:
	if closing != null:                                   # during the closing sequence the keys belong to it
		_closing_key(event)
	elif event.is_action_pressed(&"quit_to_menu"):
		get_viewport().set_input_as_handled()
		flow.ask_to_exit()


## Enter: the next part of the closing sequence; Space / Escape: leave it at once.
func _closing_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			closing.advance()
		KEY_SPACE, KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closing.skip()


# --- the flow, as the tests and the tools ask for it ------------------------------------------------

## Starts sector `index` (see `GameFlow.begin_sector`).
func begin_sector(index: int, past_midpoint: bool) -> void:
	await flow.begin_sector(index, past_midpoint)


## The lock is open (see `GameFlow.complete_sector`).
func complete_sector() -> void:
	await flow.complete_sector()


func ask_to_exit() -> void:
	await flow.ask_to_exit()


func ask_to_return_to_sign_in() -> void:
	await flow.ask_to_return_to_sign_in()


func ask_option(option: StringName) -> void:
	await flow.ask_option(option)


func leave_to_sign_in() -> void:
	flow.leave_to_sign_in()


func save_progress() -> bool:
	return flow.save_progress()


# --- what the flow asks the view to do ---------------------------------------------------------------

## The surface ship's screen with "Ship's magnetometer indicates the presence of N object(s) in this sector ..."
## (`PiecesNotCollectedMessage` 0x432ac4); returns when the player presses Enter.
func show_pieces_missing(missing: int) -> void:
	var screen: SurfaceShipScreen = SURFACE_SHIP_SCREEN.instantiate()
	problem_layer.add_child(screen)
	screen.show_pieces_missing(missing)
	await screen.finished
	screen.queue_free()


## The surface ship's screen with the mission control message (`DisplaySupplyStationMessage` 0x432e32); returns when
## the player continues (Enter, or 20 s after the speech).
func show_supply_message(completed_sector: int) -> void:
	var screen: SurfaceShipScreen = SURFACE_SHIP_SCREEN.instantiate()
	problem_layer.add_child(screen)
	screen.show_supply_message(completed_sector)
	await screen.finished
	screen.queue_free()


## Puts a `ProblemScreen` over the console and returns the finished session. `after_prompt` is called once the prompt is drawn
## (the hints come after the prompt, i.e. after the diagram has built up).
func show_problem(problem: ProblemInstance, calculator_allowed: bool, after_prompt: Callable) -> ProblemSession:
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	screen.calculator_allowed = calculator_allowed
	problem_layer.add_child(screen)
	screen.start(problem)
	if screen.step() == ProblemScreen.Step.INTRO:
		screen.intro_finished.connect(after_prompt, CONNECT_ONE_SHOT)
	else:
		after_prompt.call()
	var session: ProblemSession = await screen.finished
	screen.queue_free()
	return session


## The closing sequence of the campaign on top of the sector (the sub is stopped): `campaign.closing_scene` names it. The Voyager one gets
## the sub's place and picture, the Expert one draws its own. A campaign whose `closing_scene` is none of the original's two gets the
## generic finale (`GenericFinale`: its `finale_text` and `finale_picture`). Returns when it is over; the keys are `_closing_key`'s for all.
func show_closing(campaign: Campaign, sub_at: Vector2i, sub_cell: int) -> void:
	var scenes := {&"voyager": VOYAGER_CLOSING, &"expert": EXPERT_CLOSING}
	closing = (scenes.get(campaign.closing_scene, GENERIC_FINALE) as PackedScene).instantiate()
	problem_layer.add_child(closing)
	if closing is VoyagerClosing:
		(closing as VoyagerClosing).start(sub_at.x, sub_at.y, sub_cell)
	elif closing is GenericFinale:
		(closing as GenericFinale).show_finale(campaign)
	await closing.finished
	closing.queue_free()
	closing = null


func show_hall_of_fame() -> void:
	if messages.is_open():
		return
	await _show_modal(HALL_OF_FAME.instantiate())


## (Re)starts the song of `sector`.
func play_sector_music(sector: int) -> void:
	Audio.play_music(AudioService.music_for_sector(sector))


func stop_music() -> void:
	Audio.stop_music()


func go_to_sign_in() -> void:
	SceneRouter.go_to(SceneRouter.SIGN_IN)


func quit_game() -> void:
	_leave()
	get_tree().quit()


# --- messages and dialogs -----------------------------------------------------------------

## The sound while a message is up (the problem screen below sleeps through `modals`).
func _on_message_shown(message: MessageQueue.Message) -> void:
	# Like `RunModalDialog` (0x4174ec): `pause_sound` (0x414145) cuts a clip or effect that sounds and holds the song.
	if message != null and not _music_held_for_message:
		_music_held_for_message = true
		Audio.pause_sound()
	elif message == null and _music_held_for_message:
		_music_held_for_message = false
		Audio.resume_sound()


## An Options question was answered: the menu's check mark, and the sound system (the setting itself is the flow's).
func _on_option_changed(option: StringName, enabled: bool) -> void:
	menu_bar.set_option(option, enabled)
	match option:
		&"sound":
			Audio.set_bus_enabled(AudioService.SFX, enabled)
		&"music":
			Audio.set_music_on(enabled)
		&"voice":
			Audio.set_bus_enabled(AudioService.VOICE, enabled)


func _on_help_requested(index: int, _topic: String) -> void:
	var viewer: HelpViewer = HELP_VIEWER.instantiate()
	await _show_modal(viewer, func() -> void: viewer.show_topic(index))


## Adds a dialog on top of the game (a modal of `modals`: the problem screen sleeps) and holds the game clock and the sound until it
## frees itself. `configure` runs once the dialog is in the tree (its `@onready` nodes exist only then).
func _show_modal(dialog: Control, configure: Callable = Callable()) -> void:
	GameClock.hold()
	Audio.pause_sound()                                   # (`PauseSoundForDialog`: RunPagedDialog, show_hall_of_fame, the customization dialog ...)
	await modals.open(dialog, dialog_layer, configure)
	Audio.resume_sound()
	GameClock.release()


## Options > Audio Settings: the volumes and the music set (saved by the dialog itself).
func show_audio_settings() -> void:
	if messages.is_open():
		return
	var dialog: AudioSettingsDialog = AUDIO_SETTINGS_DIALOG.instantiate()
	dialog.closed.connect(dialog.queue_free)
	await _show_modal(dialog)


## Options > Problem Customization: the player may change the math level and the calculator (the flow records it).
func show_customization() -> void:
	if messages.is_open():
		return
	var dialog: CustomizationDialog = CUSTOMIZATION_DIALOG.instantiate()
	dialog.accepted.connect(flow.customize)
	dialog.accepted.connect(func(_level: int, _calculator: bool) -> void: dialog.queue_free())
	dialog.cancelled.connect(dialog.queue_free)
	await _show_modal(dialog, func() -> void: dialog.set_values(profile.effective_edu_level(), profile.calculator_on))
