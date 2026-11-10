class_name PracticeMode
extends Control
## Math Practice: sets of the game's own math problems, with a score, and no submarine.
##
## Teaches: a scene that reuses finished parts. The problems are the `ProblemScreen` of the game (now with
## `practice = true`: no oxygen is lost), the set is a pure function (`PracticeSet`), the score a tiny model
## (`PracticeScore`), the menu the same `GameMenuBar` in its short "practice" form, and the dialogs the same
## message queue, opened through a `ModalHost` that puts the problem to sleep under them. This script only runs the loop of the original's `do_math_practice` (PRACTICE.C):
##
##     choose a set (kind, level, calculator)  ->  play its problems  ->  "another set?"  ->  yes: choose again
##
## Options > Customization during a problem starts a new set at once. Escape during a problem asks whether to exit the
## PROGRAM (`SaveAndExit` 0x42ba05 from the answer entry, `JustExit` 0x42ba83 from the lock, the messages, the worked
## solution and the ballast panel); File > Return to Sign In is the menu's own question. No player is needed
## (`GameState.profile` stays null) and nothing is saved.

const SETUP_DIALOG := preload("res://src/ui/practice_setup_dialog.tscn")
const HELP_VIEWER := preload("res://src/ui/help_viewer.tscn")
const AUDIO_SETTINGS_DIALOG := preload("res://src/ui/audio_settings_dialog.tscn")

const SCORE_SIZE_WITH_CALCULATOR := Vector2(316, 65)
const SCORE_SIZE_WITHOUT_CALCULATOR := Vector2(608, 65)
## Problem types whose screen has no calculator on the right: `do_math_practice` (0x42d817) widens the score panel to 0x260 = 608 px
## before the lock (0), the ballast panel (28) and type 29 (`PracticeShowScore(0, 1)`), and `PracticeShowScore(1, 0)` narrows it
## to `PracticeScoreWidth` (0x42d119: 316 with the calculator, else 608) after the problem.
const WIDE_PANEL_TYPES: Array[int] = [0, 28, 29]
## `DlgYesNoRecord` (0x442c24) starts on No.
const YES_NO_DEFAULT_NO := 1

## The player said Yes to "exit the program?" (`QuitProgram` 0x42b900). Emitted before the tree quits (and instead of it when
## `quits_program` is false, which tests use).
signal quit_requested

var kind: PracticeSet.Kind = PracticeSet.Kind.FIVE
var level: int = 0
var calculator: bool = true
var score := PracticeScore.new()
var rng := RandomNumberGenerator.new()
var messages := MessageQueue.new(GameClock)

## False in tests: `quit_requested` is emitted but the tree is left alone.
var quits_program: bool = true

var _restart_requested: bool = false
## The original's local `local_8` of `do_math_practice`: Mental Math (1) or another kind (0) of the previous set, -1 before the first.
var _last_set_was_mental: int = -1
var _screen: ProblemScreen
## The message box and the dialogs (setup, help, audio): while one is open the problem below sleeps (it does not hear the keys).
var modals: ModalHost
var _left: bool = false
var _score_values: Array[Label] = []
var _score_names: Array[Label] = []

@onready var frame: ConsoleFrame = %Frame
@onready var score_panel: ColorRect = %ScorePanel
@onready var score_rows: GridContainer = %ScoreRows
@onready var host: Control = %ProblemHost
@onready var menu_bar: GameMenuBar = %MenuBar
@onready var overlay: Control = %Overlay
@onready var message_view: MessageBoxView = %MessageBox


func _ready() -> void:
	rng.randomize()
	Audio.stop_music()
	Audio.apply_profile(null)
	GameClock.paused = false
	frame.layout = Catalog.hud_layout()
	modals = ModalHost.new(self, [host])
	modals.attach(messages, message_view)
	menu_bar.sign_in_requested.connect(ask_to_return)
	menu_bar.exit_requested.connect(ask_to_exit)
	menu_bar.customization_requested.connect(_on_customization_requested)
	menu_bar.option_toggled.connect(_on_option_toggled)
	menu_bar.audio_settings_requested.connect(_show_audio_settings)
	menu_bar.help_requested.connect(_show_help)
	_update_score()
	_run()


# --- the loop of the original ---------------------------------------------------------------------

func _run() -> void:
	var chosen := await _ask_setup()
	while chosen and not _left:
		await _play_set()
		if _left:
			return
		if _restart_requested:                            # Options > Customization during a set: a new set at once
			_restart_requested = false
			continue
		if not await _ask_another() or _left:
			break
		chosen = await _ask_setup()
	_leave()


## "Math Practice Customized Settings". Returns false when the player cancels.
func _ask_setup() -> bool:
	var dialog: PracticeSetupDialog = SETUP_DIALOG.instantiate()
	var answer := [false]
	dialog.accepted.connect(func(new_kind: PracticeSet.Kind, new_level: int, new_calculator: bool) -> void:
		kind = new_kind
		level = new_level
		calculator = new_calculator
		answer[0] = true
		dialog.queue_free())
	dialog.cancelled.connect(dialog.queue_free)
	await modals.open(dialog, overlay, func() -> void: dialog.set_values(kind, level, calculator))
	return answer[0]



## Plays one set from the first problem to the last.
func _play_set() -> void:
	# The three counters are zeroed only for the first set and when the kind switches between Mental Math and the others
	# (0x42d95e-0x42d96e): a second set of the same sort adds to the score of the first.
	var mental := 1 if kind == PracticeSet.Kind.MENTAL else 0
	if mental != _last_set_was_mental:
		score.reset()
	_last_set_was_mental = mental
	_update_score()
	var order := PracticeSet.build(kind, level, rng)
	for type_id in order:
		if _restart_requested or _left:
			return
		var problem := ProblemFactory.make(type_id, level, rng)
		if problem == null:
			continue
		if type_id in WIDE_PANEL_TYPES:
			_update_score(true)
		var session := await ProblemRunner.run(host, problem, Callable(), _configure_screen)
		_screen = null
		# Deliberate deviation from the original (G37): `do_math_practice` (0x42d817) increments `PracticeProblemCount`
		# (0x449f3c) at 0x42d9e3 after EVERY `DoMathProblem` return, so a problem ended on screen by Options > Customization
		# (Done sets `PracticeRestartRequested` 0x449f38 in `PracticeSetupDialog`) is counted in "Number of problems" (+1, no
		# correct count) before `PracticeShowScore(1, 0)` and the break at 0x42d9f5. The port returns here, before
		# `score.record_session`, so the aborted problem is not counted.
		if _restart_requested or _left:
			return
		if type_id != PracticeSet.LOCK_TYPE:             # (the lock's two numbers were scored one by one)
			score.record_session(session)
		_update_score()                                  # (narrow again after a wide panel)


## Settings of the problem screen for practice, and the lock's per-number score.
func _configure_screen(screen: ProblemScreen) -> void:
	_screen = screen
	screen.practice = true
	screen.calculator_allowed = calculator
	screen.lock_stage_scored.connect(func(_stage: int, right: bool) -> void:
		score.record_lock_stage(right)
		_update_score())


## "You have completed this set of math problems. Do you want to practice another set?"
func _ask_another() -> bool:
	var message := messages.post(Catalog.text(&"practice_continue_title"), Catalog.text(&"practice_continue_text"), PackedStringArray(["Yes", "No"]))
	var choice: int = await message.closed
	return choice == 0


# --- the score ---------------------------------------------------------------------------------

## The lines of the original's score panel: three for ordinary sets, two ("Problems correct") for Mental Math.
func _update_score(wide: bool = false) -> void:
	var mental := kind == PracticeSet.Kind.MENTAL
	var lines: Array = [[Catalog.text(&"score_problems"), score.problems]]
	if mental:
		lines.append([Catalog.text(&"score_correct"), score.correct()])
	else:
		lines.append([Catalog.text(&"score_first_try"), score.first_try])
		lines.append([Catalog.text(&"score_second_try"), score.second_try])
	var with_calculator := calculator and not mental
	score_panel.size = SCORE_SIZE_WITH_CALCULATOR if with_calculator and not wide else SCORE_SIZE_WITHOUT_CALCULATOR
	score_rows.custom_minimum_size.x = score_panel.size.x - 32.0
	while _score_names.size() < lines.size():
		var name_label := Label.new()
		name_label.theme_type_variation = &"HudLabel"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := Label.new()
		value_label.theme_type_variation = &"HudLabel"
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score_rows.add_child(name_label)
		score_rows.add_child(value_label)
		_score_names.append(name_label)
		_score_values.append(value_label)
	for i in _score_names.size():
		var shown := i < lines.size()
		_score_names[i].visible = shown
		_score_values[i].visible = shown
		if shown:
			_score_names[i].text = lines[i][0]
			_score_values[i].text = str(lines[i][1])


# --- the menu and the keys -------------------------------------------------------------------------

## Options > Customization: choose a new set; if the player accepts, the current one is dropped.
func _on_customization_requested() -> void:
	if modals.is_open():
		return
	if await _ask_setup():
		_restart_requested = true
		if _screen != null:
			_screen.close()                               # ends the problem on screen; `_play_set` sees the flag


func _on_option_toggled(option: StringName, enabled: bool) -> void:
	if option == &"sound":
		Audio.set_bus_enabled(AudioService.SFX, enabled)


func _show_audio_settings() -> void:
	if modals.is_open():
		return
	var dialog: AudioSettingsDialog = AUDIO_SETTINGS_DIALOG.instantiate()
	dialog.closed.connect(dialog.queue_free)
	await modals.open(dialog, overlay)


func _show_help(index: int, _topic: String) -> void:
	if modals.is_open():
		return
	var viewer: HelpViewer = HELP_VIEWER.instantiate()
	await modals.open(viewer, overlay, func() -> void: viewer.show_topic(index, true))    # (it frees itself)


## File > Return to Sign In.
func ask_to_return() -> void:
	if modals.is_open():
		return
	var message := messages.post(Catalog.text(&"practice_return_title"), Catalog.text(&"practice_return_text").replace("\r", "\n"), PackedStringArray(["Yes", "No"]))
	var choice: int = await message.closed
	if choice == 0:
		_leave()


## File > Exit: the menu's own question, `JustExit` (0x42ba83: strings 11134 / 11132).
func ask_to_exit() -> void:
	if modals.is_open():
		return
	await _ask_exit(false)


## "You are about to exit the program": `save` picks `SaveAndExit` (0x42ba05, text 11130) or `JustExit` (0x42ba83, text 11134);
## both have the title 11132 and start on No. Yes leaves the program.
##
## Deliberate deviation from the original (G39): `SaveAndExit` (0x42ba05) calls `SaveRosterData` (0x42e11d) ->
## `UpdateRosterData` (0x42e09a) after Yes, which writes the 36-byte `CurrentPlayer` over `RosterSlots[CurrentRosterSlot]`
## whenever `CurrentRosterSlot` (0x442e80) >= 0. `do_math_practice` (0x42d82b-0x42d87d) has blanked `CurrentPlayer` and the slot
## stays -1 only until the first sign-in of the run, so Esc > Yes in Math Practice after a sign-in overwrites that player's roster
## slot with a nameless record (the player vanishes from the list). The port writes nothing: the roster is left unchanged.
func _ask_exit(save: bool) -> void:
	var message := messages.post(Catalog.text(&"exit_title"), Catalog.text(&"exit_text" if save else &"practice_exit_text").replace("\r", "\n"),
			PackedStringArray(["Yes", "No"]), true, 0, YES_NO_DEFAULT_NO)
	var choice: int = await message.closed
	if choice == 0:
		quit_requested.emit()
		if quits_program:
			get_tree().quit()


## Escape during a problem (`GetNumber` 0x41fb34 / `GetAnswer` 0x41ade0: `SaveAndExit`; `GetBallastAnswer` 0x4196e8,
## `LockRunStage` 0x421dc9, `DoCombinationLock`, `WaitKeyOrTicks` 0x423549, `ShowProblemSolution` 0x426a9e: `JustExit` when
## `InMathPractice` is set). Nothing happens while the diagram builds up or replays, or when no problem is on screen.
func ask_to_exit_from_problem() -> void:
	if modals.is_open() or _screen == null:
		return
	var step := _screen.step()
	if step == ProblemScreen.Step.INTRO or step == ProblemScreen.Step.REPLAY or step == ProblemScreen.Step.OVER:
		return
	var entering_a_number := step == ProblemScreen.Step.ANSWERING and _screen.lock == null and _screen.ballast == null
	await _ask_exit(entering_a_number)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"quit_to_menu"):
		get_viewport().set_input_as_handled()
		ask_to_exit_from_problem()


func _leave() -> void:
	if _left:
		return
	_left = true
	SceneRouter.go_to(SceneRouter.SIGN_IN)
