class_name ProblemScreen
extends Control
## The full-screen math problem (640 x 400): diagram, text, calculator, feedback, laid out like the original. The VIEW of a
## `ProblemFlow`: the flow decides what happens when; this node shows it.
##
## Teaches: a screen scene driven by a step machine (`ProblemFlow`, plain object, no nodes) and a small model (`ProblemSession`),
## child scenes (`Calculator`, and a `DiagramBase` subclass that draws the problem onto the original's art), an `AnimationPlayer` for the screen's own
## transitions (fade in, a shake and flash for a wrong answer, a flash for a right one),
## signals up (`finished`, `sfx_requested`) and an autoload down (`GameState` for the oxygen). Read `problem_flow.gd` for the
## rules of a problem (flow, messages, hint, solution) and this file for what is shown and what is clicked.
##
## The combination lock (type 0) is the odd one out: its answer is the TIMING of a key press, not a
## number. The screen then adds a `CombinationLock` that turns the wheels and talks to the monitor through
## signals; misses still cost oxygen in the flow, in one place.
##
## Oxygen: while a problem is open `GameState` holds back `tank_lost` / `game_over` (the sub only
## loses its tank when the problem is closed), see `GameState.hold_losses`.
##
## Escape does NOT skip a problem. The game logic clock stays held (`GameClock.hold`) while the screen is up.
##
## The prompt of a problem asked by a map trigger carries a sender picture (the research ship or the control room) with the
## first line beside it (`WriteMessageTextWithSender` (0x4233c8), see `PromptSender`); every later text is plain again.
##
## Usage:  var screen := PROBLEM_SCREEN.instantiate(); add_child(screen); screen.start(instance)

## The problem is over and the player pressed Enter to continue. The session says how it went.
signal finished(session: ProblemSession)
## A sound effect wants to play (its `sound` name). The screen sends its own requests to the
## `Audio` autoload in `_ready`; the signal stays for observers (tests, the sound log).
signal sfx_requested(sfx: StringName)
## The diagram's build-up is over: the prompt is on screen and answers are read (`DrawProblemDiagram` runs first,
## then `ShowProblemPrompt`, which flushes the keys). Not emitted when the problem is closed during the build-up.
signal intro_finished
## Practice mode only: one of the lock's two combination numbers was stopped right (`right`) or missed (`stage` 0 or 1).
signal lock_stage_scored(stage: int, right: bool)

## The step machine's constants and enum, under the names this screen always had.
const Step := ProblemFlow.Step
const SFX_CORRECT := ProblemFlow.SFX_CORRECT
const SFX_WRONG := ProblemFlow.SFX_WRONG
const NO_SHIP_NOTICE_TYPES := ProblemFlow.NO_SHIP_NOTICE_TYPES
const SUCCESS_REPLAY_TYPES := ProblemFlow.SUCCESS_REPLAY_TYPES
## String 11003 "Click to go on." closes the worked solution.
const STRING_GO_ON := &"click_to_go_on"
const LOG_SCREEN := preload("res://src/ui/log_screen.tscn")
const CALC_NOTICE_DIALOG := preload("res://src/problems/calc_notice_dialog.tscn")
const COLOR_WRONG := Color(1.0, 0.45, 0.4)

## Set to false to make the calculator unavailable (the player's option).
@export var calculator_allowed: bool = true
## Math Practice: wrong answers cost no oxygen (and the messages do not mention it); the hint and solution rules are the same.
@export var practice: bool = false

## How the attempts went so far (the flow's session; null before `start`).
var session: ProblemSession:
	get:
		return _flow.session
## The picture of the problem on the left monitor (a `DiagramBase` subclass); for the ballast types it is also the input.
var diagram: DiagramBase
## The same node when the problem is a ballast panel, else null.
var ballast: BallastPanelDiagram
## The wheel controller when the problem is the combination lock, else null.
var lock: CombinationLock
## The data canister's log screen while it is up (`do_access_closing` (0x417f56) -> `DoDataBank` (0x41e18f)), else null.
var log_screen: LogScreen
## Practice mode only: picks the phrase for a right answer (seed it in a test).
var rng := RandomNumberGenerator.new()

var _flow := ProblemFlow.new()                ## the rules of this problem: what happens when
var _early_events: Array = []                  ## the events of `begin` and what follows until the diagram is made (`start`): the diagram of this problem hears them first
var _diagram_hears := false                    ## is `diagram` the one of the problem being shown? (else an event waits in `_early_events`)
var _ticks := TickMeter.new()                  ## real time -> the original's ticks, for the steps that wait
var _holding_clock: bool = false
var _holding_losses: bool = false              ## this screen's one hold on `GameState.hold_losses` (a count there: a second `start` must not add one)
var _click_catcher: Control                  # covers the screen while a message is up: a click anywhere goes on
var _text_top: float = 0.0                   # where the message text starts when it is plain (the message box's top)

@onready var content: Control = %Content
@onready var background: TextureRect = %Background
@onready var title_label: Label = %TitleLabel
@onready var diagram_host: Control = %DiagramHost
@onready var text_label: RichTextLabel = %Text
@onready var sender_icon: TextureRect = %SenderIcon
@onready var sender_header: Label = %SenderHeader
@onready var feedback: Label = %Feedback
@onready var answer_box: AnswerBox = %AnswerBox
@onready var calculator: Calculator = %Calculator
@onready var animations: AnimationPlayer = %Animations


func _ready() -> void:
	_apply_layout(Catalog.screen_layout())
	calculator.submitted.connect(_on_number_submitted)
	answer_box.submitted.connect(_on_text_submitted)
	answer_box.sfx_requested.connect(func(sfx: StringName) -> void: sfx_requested.emit(sfx))
	calculator.entry_changed.connect(_on_entry_changed)                    # (the diagram may draw from what is typed: `ModDiagram`)
	answer_box.entry_changed.connect(_on_entry_changed)
	calculator.sfx_requested.connect(func(sfx: StringName) -> void: sfx_requested.emit(sfx))
	sfx_requested.connect(Audio.play_sfx)
	rng.randomize()
	_flow.rng = rng
	_flow.oxygen_sink = func(delta: int) -> int: return GameState.update_oxygen(delta)
	_flow.replay_ticks = func() -> int:            # how long the diagram's replay is (data), -1 for a type without one
		if not SUCCESS_REPLAY_TYPES.has(_flow.problem.type.id) or not diagram.has_success_replay():
			return -1
		return diagram.success_replay_length()
	_connect_flow()
	_click_catcher = Control.new()                    # the original's hotspot over the whole screen (`AddHotspot(0xd, 0, 0, 640, 400)`)
	_click_catcher.size = Vector2(640, 400)
	_click_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_click_catcher.visible = false
	_click_catcher.gui_input.connect(_on_catcher_input)
	add_child(_click_catcher)
	var notices: CalcNoticeDialog = CALC_NOTICE_DIALOG.instantiate()   # "Calculator Error" / "Fraction Mode", on top of everything
	add_child(notices)
	calculator.notice_requested.connect(notices.show_notice)
	answer_box.notice_requested.connect(notices.show_notice)


## The flow's events become what the player sees and hears.
func _connect_flow() -> void:
	_flow.step_changed.connect(_on_step_changed)
	_flow.prompt_shown.connect(func() -> void: _write_prompt(_flow.problem))
	_flow.message_shown.connect(_write_message)
	_flow.feedback_shown.connect(func(message: String, is_error: bool) -> void:
		_say(message, COLOR_WRONG if is_error else Catalog.screen_layout().color(15)))
	_flow.go_on_changed.connect(_show_go_on)
	_flow.sfx_requested.connect(func(sfx: StringName) -> void: sfx_requested.emit(sfx))
	_flow.reacted.connect(func(kind: StringName) -> void: animations.play(kind))
	_flow.input_changed.connect(_set_input)
	_flow.log_screen_requested.connect(_show_log_screen)
	_flow.intro_finished.connect(func() -> void: intro_finished.emit())
	_flow.finished.connect(_on_flow_finished)
	_flow.happened.connect(_on_event)


## Puts the shared parts where the original has them (`ProblemScreenLayout`, DESIGN 5.5): the screen
## picture, the title box and the prompt's text box. The font comes from the project Theme.
func _apply_layout(layout: ProblemScreenLayout) -> void:
	background.texture = layout.background
	background.position = Vector2(layout.background_position)
	title_label.position = Vector2(layout.title_box_x, layout.title_y)
	title_label.size = Vector2(layout.title_box_width, layout.line_height)
	title_label.add_theme_color_override("font_color", layout.color(15))
	sender_header.add_theme_color_override("font_color", layout.color(15))
	var box := Rect2(layout.message_box)
	# The monitor holds ten lines of the original's text. Prompts, hints and solutions of all stored problems are
	# at most nine lines long, so the tenth line is ours: it says what just happened (right / wrong, oxygen).
	@warning_ignore("integer_division")
	var text_lines := int(box.size.y) / layout.line_height - 1
	text_label.position = box.position
	_text_top = box.position.y
	text_label.size = Vector2(box.size.x, text_lines * layout.line_height)
	text_label.add_theme_constant_override("line_separation", layout.line_separation)      # (data, not the font's height)
	feedback.position = Vector2(box.position.x, box.position.y + text_label.size.y)
	feedback.size = Vector2(box.size.x, box.size.y - text_label.size.y)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## The verdict of the run's rule hooks on `answer` (`RuleHooks.judge_answer`: true, false, or null when no mod of the campaign judges this type, and the type's data does).
func _judge(problem: ProblemInstance, answer: Variant) -> Variant:
	return GameState.hooks.judge_answer(problem, answer)


## Shows `problem` and starts listening for answers.
func start(problem: ProblemInstance) -> void:
	if lock != null:                                  # a second problem on the same screen (tests, debug menu)
		lock.queue_free()
		lock = null
	if log_screen != null:                            # a second problem on the same screen (tests, debug menu)
		log_screen.queue_free()
		log_screen = null
		content.visible = true
	_flow.practice = practice
	_flow.answer_judge = Callable() if practice else _judge       # (Math Practice is of no campaign: the type's data judges, whatever mod an earlier game had)
	_early_events.clear()
	_diagram_hears = false                            # (the flow begins before the diagram is made: its first events wait for it)
	_flow.begin(problem)                              # the prompt is written by the flow's event
	_hold_clock()
	_hold_losses()
	title_label.text = problem.title
	feedback.text = ""
	_show_diagram(problem)
	_show_input(problem)
	animations.play(&"open")
	if lock == null and diagram.has_intro():
		_run_intro()                                  # (a coroutine: returns at its first `await`)


## `DrawProblemDiagram` (0x424f3d) builds the picture up in front of the player, and only then does the flow write the prompt and
## flush the keys. The FLOW is told how long the build-up lasts (the diagram's data) and counts it; the diagram plays inside that time
## (`_follow_flow`).
func _run_intro() -> void:
	_flow.start_intro(diagram.intro_length())
	diagram.begin_intro()


## True while a result is on screen (a timed message or the worked solution) and not the next answer.
func is_waiting_for_continue() -> bool:
	return _flow.is_waiting_for_continue()


## True while the screen takes answers.
func is_answering() -> bool:
	return _flow.is_answering()


func step() -> ProblemFlow.Step:
	return _flow.step


# --- setting up --------------------------------------------------------------------

## Draws the problem onto the original's art (`DiagramFactory`, one `DiagramBase` subclass per family).
func _show_diagram(problem: ProblemInstance) -> void:
	if diagram != null:
		diagram.queue_free()
	diagram = DiagramFactory.create(problem)
	diagram_host.add_child(diagram)
	diagram.sfx_requested.connect(func(sfx: StringName) -> void: sfx_requested.emit(sfx))   # build-up and replay sounds, clicks, the radar ping
	diagram.sfx_stop_requested.connect(Audio.stop_sfx)                                      # StopCommonSoundEffect
	diagram.step_changed(_flow.step)
	diagram.session = _flow.session
	_diagram_hears = true
	for event: Array in _early_events:                 # (`started` and whatever came before the picture: this problem's diagram is told from the start)
		diagram.told(event)
	_early_events.clear()
	diagram.animation_finished.connect(_flow.animation_finished)    # a skipped animation ends the step at once (debug screenshots, tests)
	ballast = diagram as BallastPanelDiagram
	if ballast != null:
		ballast.done_pressed.connect(_flow.hold_ballast)         # the flow holds the pressed Done button for the ticks in the panel's data
	elif diagram is LockDiagram:
		_start_lock(problem, diagram as LockDiagram)


## Picks the right way to answer: weights, the calculator, or a plain typed number.
func _show_input(problem: ProblemInstance) -> void:
	var selecting := problem.input_kind == ProblemInstance.InputKind.DENOMINATIONS
	var use_calculator := calculator_allowed and problem.type.uses_calculator and not selecting
	calculator.visible = use_calculator
	answer_box.visible = not selecting and not use_calculator and lock == null
	calculator.keyboard_enabled = use_calculator
	answer_box.keyboard_enabled = answer_box.visible
	if selecting:
		ballast.keyboard_enabled = true
	elif lock != null:
		pass                                          # the wheels need no answer box
	elif use_calculator:
		calculator.reset()
	else:
		answer_box.reset()


# --- the combination lock ------------------------------------------------------------

## Adds the wheel controller. It talks back through signals; the screen prints, scores and closes.
func _start_lock(problem: ProblemInstance, lock_diagram: LockDiagram) -> void:
	lock = CombinationLock.new()
	add_child(lock)
	lock.say.connect(_write_message)
	lock.sfx_requested.connect(func(sfx: StringName) -> void: sfx_requested.emit(sfx))
	lock.stage_right.connect(_on_lock_right)
	lock.stage_missed.connect(_on_lock_missed)
	lock.go_on_prompt.connect(_flow.lock_go_on)
	lock.finished.connect(_on_lock_finished)
	lock.practice = practice
	lock.rng = rng
	lock.tuning = GameState.tuning
	lock.setup(problem, lock_diagram)


func _on_lock_right() -> void:
	lock_stage_scored.emit(lock.stage, true)
	_flow.lock_stage_right()


## A wrong stop or no stop at all: one oxygen, no second try (DESIGN 3.7). If that used up the air the
## lock ends once the player has read the solution.
func _on_lock_missed(_reason: String) -> void:
	lock_stage_scored.emit(lock.stage, false)
	lock.abort_after_miss = _flow.lock_missed()


func _on_lock_finished() -> void:
	_flow.lock_finished(lock.misses)


## The worked solution asks for Enter with the original's bottom line (string 11003, centred under the text).
func _show_go_on(shown: bool) -> void:
	if shown:
		_say(Catalog.text(STRING_GO_ON), Catalog.screen_layout().color(15))
		feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		feedback.text = ""
		feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


# --- answers -------------------------------------------------------------------------

## The flow says something happened (`ProblemEvents`): the diagram of the problem is told, in the order it happened.
func _on_event(event: Array) -> void:
	if _diagram_hears and diagram != null:
		diagram.told(event)
	else:
		_early_events.append(event)


## What the calculator or the answer box shows changed: the diagram is told (`DiagramBase.entry_changed`).
func _on_entry_changed(text: String) -> void:
	if diagram != null:
		diagram.entry_changed(text)


func _on_number_submitted(value: NumberValue) -> void:
	submit_answer(value)


func _on_text_submitted(text: String) -> void:   # typed in the "Ans:" box
	submit_answer(NumberValue.parse(text))


## Judges an answer exactly as if the player had entered it (used by the key handlers, the
## debug menu's screenshot mode and tests). `answer` is a NumberValue, a ballast bit mask or null.
## Ignored while a message is up (the original reads no answer then).
func submit_answer(answer: Variant) -> void:
	_flow.submit_answer(answer)


## `do_access_closing` (0x417f56): the canister problem ends with the log screen on top of the problem; when the player is
## done with it the problem is over.
func _show_log_screen(sector: int) -> void:
	content.visible = false
	log_screen = LOG_SCREEN.instantiate()
	add_child(log_screen)
	log_screen.finished.connect(_flow.close)
	log_screen.start(sector)


func _say(message: String, color: Color) -> void:
	feedback.text = message
	feedback.add_theme_color_override("font_color", color)


# --- messages -------------------------------------------------------------------------

## `WriteMessageText` (0x4234c0): the plain text of the message box (hint, "Error!", solution, success text) at the top of
## the box. It also takes the sender picture of an earlier prompt away: the original clears the box (364, 48, 238, 202) first.
func _write_message(text: String) -> void:
	sender_icon.visible = false
	sender_header.visible = false
	text_label.position.y = _text_top
	text_label.text = text                                # BBCode: only `[u]` from `TextTemplate` (the underline toggle, G35)


## `ShowProblemPrompt` (0x4250c3) -> `WriteMessageText`: the prompt of a problem asked by a map trigger is written with the
## sender picture (`WriteMessageTextWithSender` (0x4233c8), `PromptSender`): the picture at (361, 48), the first line beside
## it, the rest from y 68. A prompt of Math Practice, the debug menu or the lock is plain text.
func _write_prompt(problem: ProblemInstance) -> void:
	if not PromptSender.applies_to(problem, practice):
		_write_message(problem.prompt)
		return
	var parts := PromptSender.split(problem.prompt)
	_write_message(parts[1])
	sender_icon.texture = PromptSender.texture(problem.trigger_slot)
	sender_icon.visible = true
	sender_header.text = parts[0]
	sender_header.visible = true
	text_label.position.y = PromptSender.BODY_Y


## Lets `ticks` 73 Hz ticks pass (a test can play a whole problem by calling this). The flow counts them; the diagram is shown as of
## the flow's tick.
func advance_ticks(ticks: int) -> void:
	var presenting := _flow.is_presenting()
	_flow.advance_ticks(ticks)
	if presenting:
		_follow_flow()


## The diagram plays INSIDE the time the flow gives it: it shows the picture of the flow's tick (and the sounds that fall due).
func _follow_flow() -> void:
	if diagram != null and diagram.is_playing():
		diagram.animate_to(_flow.presentation_elapsed())


## Enter or a click: ends a message early, or leaves the worked solution.
func press_continue() -> void:
	_flow.press_continue()


func _process(delta: float) -> void:
	if _flow.step == Step.ANSWERING or _flow.step == Step.SOLUTION or _flow.step == Step.OVER or _flow.step == Step.LOG:
		_ticks.reset()                                # (nothing waits for time)
		return
	var whole := _ticks.feed(delta)
	if whole > 0:
		advance_ticks(whole)


## The click-catcher covers the screen whenever the flow is not waiting for an answer (a replay takes no clicks either).
func _on_step_changed(new_step: ProblemFlow.Step) -> void:
	if diagram != null:
		diagram.step_changed(new_step)
	_click_catcher.visible = new_step != Step.ANSWERING and new_step != Step.OVER
	if new_step == Step.REPLAY and _flow.replaying:
		_play_replay()


## The right answer is replayed on the diagram before the success text (`ShowSuccessMessage` (0x4272f1)); nothing can be pressed
## until the flow's ticks for it are over.
func _play_replay() -> void:
	diagram.begin_success_replay()


## While a message is up the answer inputs read nothing (the original flushes the keys); `true` is the second try: the
## inputs are cleared and read again.
func _set_input(enabled: bool) -> void:
	if not enabled:
		calculator.keyboard_enabled = false
		answer_box.keyboard_enabled = false
		if ballast != null:
			ballast.keyboard_enabled = false
		return
	if ballast != null:
		ballast.keyboard_enabled = true
	if calculator.visible:
		calculator.keyboard_enabled = true
		calculator.reset()
	elif answer_box.visible:
		answer_box.keyboard_enabled = true
		answer_box.reset()


func _on_catcher_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		press_continue()


## Enter closes a message or the solution early.
func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not is_waiting_for_continue() or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		press_continue()


## Ends the problem: gives the clock back and tells the owner, then lets any held "ran out of
## air" through (`GameState.release_losses`), so the owner has seen the outcome first. Public so the
## debug menu and tests can close a problem without a key press.
func close() -> void:
	_flow.close()


func _on_flow_finished(done: ProblemSession) -> void:
	Audio.stop_voice()                                    # Enter cuts the speech off, as in the original
	_release_clock()
	finished.emit(done)
	_release_losses()


## The screen holds the game clock for as long as it is up (once, even if `start` is called again).
func _hold_clock() -> void:
	if not _holding_clock:
		_holding_clock = true
		GameClock.hold()


## The same for the hold on the lost tanks: once per screen, however often `start` is called, and given back exactly once.
func _hold_losses() -> void:
	if not _holding_losses:
		_holding_losses = true
		GameState.hold_losses()


func _release_losses() -> void:
	if _holding_losses:
		_holding_losses = false
		GameState.release_losses()


func _release_clock() -> void:
	if _holding_clock:
		_holding_clock = false
		GameClock.release()


## A screen that is thrown away without `close` (its scene leaves: Return to Sign In, Exit, the window closed) gives the clock back
## and DROPS its hold on the losses (`GameState.drop_losses`): a tank that the wrong answers emptied is not taken, and no game over is
## announced. The original does the same. Its answer loops wait for keys with the window's messages flowing, and Escape in them is
## `SaveAndExit` (0x42ba05: `SaveRosterData` 0x42e11d, then `QuitProgram`), the File menu `MenuReturnToSignInSave` (0x42b914:
## `SaveRosterData`, then a `LongJmp` back to the sign-in). Both leave `DoMathProblem` (0x423629) in the middle, so the code it would
## have returned (1 a lost tank, 2 game over) never reaches `DoAction`: the record is saved with the numbers of that moment (the
## spare tanks untouched; `GameState.capture_profile` saves an empty tank as 1), and no try is counted. (A screen that was closed has given its hold back already: nothing to drop.)
func _exit_tree() -> void:
	_release_clock()
	if not _flow.closed and _flow.session != null:
		_flow.abandon()
	if _holding_losses:
		_holding_losses = false
		GameState.drop_losses()
