class_name ProblemFlow
extends RefCounted
## The step machine of ONE math problem: what happens when, and in which order (build-up, prompt, answer, check, hint,
## solution, success replay, over). `ProblemScreen` is only its view.
##
## Teaches: separating RULES from PRESENTATION. This class knows nothing about nodes, textures, fonts, `Input`
## or the scene tree. It is told what happened ("the player submitted this", "5 ticks went by", "the diagram finished its
## animation") and answers with named EVENTS (signals): "show this message", "play this sound", "switch the inputs off". The
## view turns each event into pixels and sounds. A test can play a whole problem with plain objects, no scene at all
## (`tests/engine/test_problem_flow_machine.gd`), and a different view (another skin, a "debug rectangles" presenter) can show the
## same machine without changing one outcome or one duration.
##
## What it does NOT do: touch the oxygen (it calls `oxygen_sink`, which the view points at `GameState`), hold the game clock,
## stop the speech or load a picture. Those belong to whoever shows the problem.
##
## The flow (DESIGN 5.2, `DoMathProblem` (0x423629)): the prompt is shown; the player submits an answer. Every message after that is
## a `Step.MESSAGE`: it stays up for 146 ticks (2 s, data) or until Enter / a click (`WaitKeyOrTicks(0x92)` (0x423549)), then the flow
## goes on by itself.
##   right:        success text (practice: one of four short phrases)                     -> the problem is over
##   wrong:        -1 oxygen, "Error!"; out of air -> over, else the hint stays up for the 2nd try
##   wrong again:  -1 oxygen, "Error!"; out of air -> over, else "Problem has been directed to ship ..." (most types),
##                 the worked solution until Enter / a click (`Step.SOLUTION`), then the success text
## Time is counted in the original's ticks (1/73 s); the view feeds real time in through `advance_ticks`.
##
## WHO OWNS THE LENGTH of a step that holds up play: this machine, with the numbers from data. Messages stay 146 ticks (`message_ticks()`); the build-up and the
## replay last as many ticks as the diagram's timeline says (data, `DiagramTimeline.end_tick`) and the view is TOLD that number
## (`start_intro(ticks)`, `replay_ticks`); a pressed Done button of the ballast panel is held for the ticks in its data
## (`hold_ballast`). The view plays inside that time: it asks `presentation_elapsed()` where the step is and shows that.
## A replaced picture, a slower tween or another frame rate cannot make a step longer or shorter.

## The step of the problem. INTRO: the diagram builds up, no prompt, keys discarded. ANSWERING: waiting for an answer.
## MESSAGE: a timed message. SOLUTION: the worked solution, until Enter or a click. REPLAY: the diagram replays the right
## answer before the success text (nothing can be pressed). HOLD: the ballast panel's Done button stays pressed for a moment
## before the answer is judged (`GetBallastAnswer` (0x4196e8)). OVER: closed. LOG: the data canister's log screen is up; nothing
## is counted, the view calls `close` when the player is done with it.
enum Step { INTRO, ANSWERING, MESSAGE, SOLUTION, REPLAY, HOLD, OVER, LOG }

## The step changed (the view shows or hides the click-catcher for it).
signal step_changed(step: Step)
## The prompt of the problem is to be written (the view knows about the sender picture beside the first line).
signal prompt_shown
## `text` is the plain text of the message box (hint, "Error!", solution, success text, "" to clear it).
signal message_shown(text: String)
## One line under the text: `is_error` is the red "Type a number first." / "-1 oxygen" kind.
signal feedback_shown(text: String, is_error: bool)
## The bottom line "Click to go on." (string 11003) is wanted (true) or can go (false).
signal go_on_changed(shown: bool)
## A sound effect (its `sound` name).
signal sfx_requested(sfx: StringName)
## The screen reacts to an answer: &"right" (a flash) or &"wrong" (a shake).
signal reacted(kind: StringName)
## The inputs (calculator, answer box, ballast panel) are switched off (`false`: the original flushes the keys), or switched on
## AND CLEARED again (`true`: the second try).
signal input_changed(enabled: bool)
## The data canister's log screen is to open on `sector` (`do_access_closing` (0x417f56)); when it is done the view calls `close`.
signal log_screen_requested(sector: int)
## The build-up is over: the prompt is on screen and answers are read. Not emitted when the problem is closed during it.
signal intro_finished
## The problem is over (also when the air ran out); the session says how it went.
signal finished(finished_session: ProblemSession)

const SFX_CORRECT := &"correct"
const SFX_WRONG := &"wrong"
## String ids: "Error!" after every wrong answer, and the note that the problem went to the ship.
const STRING_ERROR := &"error_title"
const STRING_DIRECTED_TO_SHIP := &"directed_to_ship_notice"
## `ShowWrongAnswerNotice` (0x426317) skips the "directed to ship" note after the second miss for these ten types (table at
## 0x442984) [V]. Why these ten is [I]: nothing in the code says.
const NO_SHIP_NOTICE_TYPES: Array[int] = [9, 14, 17, 20, 21, 25, 30, 31, 32, 33]
## `ShowSuccessMessage` (0x4272f1) first replays the diagram for these types (their `Prob*_SuccessAnimation` /
## `AnimateThermometerSolution`, with their own sounds and `DelayTicks`).
const SUCCESS_REPLAY_TYPES: Array[int] = [6, 11, 12, 16, 22, 23, 26, 27]

## Math Practice: wrong answers cost no oxygen (and the messages do not mention it); the hint and solution rules are the same.
var practice: bool = false
## Picks the phrase for a right answer in practice (seed it in a test).
var rng := RandomNumberGenerator.new()
## Takes one oxygen away: `func(delta: int) -> int` returns the `OxygenModel` code (the view points it at `GameState`).
var oxygen_sink: Callable = func(_delta: int) -> int: return OxygenModel.OK
## Points the session's `judge` (the mod's verdict on an answer, `RuleHooks.judge_answer`); unset, the data of the type judges.
var answer_judge := Callable()
## Asked when a right answer is in: how many ticks does the diagram's success replay take? -1 if there is none before the success
## text. Only the view knows its diagram, so it answers (`func() -> int`); the number is data (`DiagramTimeline.end_tick`).
var replay_ticks: Callable = func() -> int: return -1

var problem: ProblemInstance
var session: ProblemSession
var step: Step = Step.ANSWERING
var closed: bool = false
## True during `Step.REPLAY` when the view plays a replay; the step lasts `replay_ticks` ticks.
var replaying: bool = false

var _ticks_left: int = 0                     # ticks left of the build-up, the replay or the hold
var _elapsed: int = 0                        # ticks gone by in it (the view shows the diagram as of this tick)
var _held_mask: int = 0                      # the weights chosen while the Done button is held

var _message_ticks: int = 0                  # ticks left of the message on screen
var _after_message: Callable                 # what happens when the message is over (time-out, Enter or click)


# --- starting ------------------------------------------------------------------------------

## How long a message stays up when nobody presses Enter or clicks: `WaitKeyOrTicks(0x92)` = 146 ticks of 1/73 s = 2 s
## (`problem.message_ticks` of `data/rules/durations.json`, `Durations`).
static func message_ticks() -> int:
	return maxi(Durations.at("problem.message_ticks"), 0)


## Starts over with `new_problem`: a new session, the prompt is shown.
func begin(new_problem: ProblemInstance) -> void:
	problem = new_problem
	session = ProblemSession.new(problem)
	session.judge = answer_judge
	closed = false
	replaying = false
	_ticks_left = 0
	_elapsed = 0
	_message_ticks = 0
	_after_message = Callable()
	_set_step(Step.ANSWERING)
	prompt_shown.emit()


## `DrawProblemDiagram` (0x424f3d) builds the picture up in front of the player (its own sounds and `DelayTicks`), and only
## then `ShowProblemPrompt` writes the prompt and flushes the keys. Until then: no prompt, no answers, clicks swallowed.
## The build-up lasts `ticks` ticks (the diagram's data); then the prompt comes.
func start_intro(ticks: int) -> void:
	_write_message("")
	input_changed.emit(false)
	_ticks_left = ticks
	_elapsed = 0
	_set_step(Step.INTRO)
	if ticks <= 0:
		animation_finished()


## How many ticks of the build-up or the replay are over (the view shows the diagram as of this tick). It keeps counting for the
## tick that ended the step, so the view can show the last picture.
func presentation_elapsed() -> int:
	return _elapsed


## True while the diagram is playing: the build-up or a replay.
func is_presenting() -> bool:
	return step == Step.INTRO or step == Step.REPLAY


## The diagram's animation is over before its time (it was skipped: the debug screenshots and the tests do that), or its last tick
## came. Ends the build-up or the success replay.
func animation_finished() -> void:
	if closed:
		return
	if step == Step.INTRO:
		prompt_shown.emit()
		_set_step(Step.ANSWERING)
		input_changed.emit(true)
		intro_finished.emit()
	elif step == Step.REPLAY and replaying:                    # (once: only a replay that is playing ends, and only one time)
		replaying = false
		_after_replay()


# --- answers -------------------------------------------------------------------------------

## Judges an answer exactly as if the player had entered it. `answer` is a NumberValue, a ballast bit mask or null.
## Ignored unless the screen is waiting for one (the original reads no answer then).
func submit_answer(answer: Variant) -> void:
	if step != Step.ANSWERING:
		return
	var outcome := session.submit(answer)
	match outcome:
		ProblemSession.Outcome.INVALID:
			feedback_shown.emit("Type a number first.", true)
		ProblemSession.Outcome.CORRECT_FIRST, ProblemSession.Outcome.CORRECT_SECOND:
			_on_right()
		ProblemSession.Outcome.WRONG_HINT:
			_on_wrong(false)
		ProblemSession.Outcome.WRONG_SOLUTION:
			_on_wrong(true)


## Right answer (`DoMathProblem` (0x423629)): sound 0x20, then in the game the success text, in practice a phrase.
func _on_right() -> void:
	sfx_requested.emit(SFX_CORRECT)
	reacted.emit(&"right")
	input_changed.emit(false)
	if practice:
		_show_message(CorrectPhrase.pick(rng), close)           # `ShowCorrectPhrase` (0x4235e5); no success text, no replay
	else:
		_show_success()


## The text for a right answer, or after the solution of a second miss: `ShowSuccessMessage` (0x4272f1).
## The data canister has no success text of its own: its log screen takes over and reads its entry aloud.
func _show_success() -> void:
	input_changed.emit(false)
	_after_message = Callable()
	var ticks: int = replay_ticks.call()
	var plays := ticks >= 0                                     # (a local: `replaying` can change under our feet, see below)
	replaying = plays
	_ticks_left = maxi(ticks, 0)
	_elapsed = 0
	_set_step(Step.REPLAY)                                      # (the view starts the diagram's replay)
	# A replay with nothing to wait for (one step at tick 0: the overlay types 6, 11, 16) is over INSIDE `_set_step`: the diagram
	# reports `animation_finished` while the view starts it, the flow has already gone on (`_after_replay` ran, the step is
	# another one) and must not go on a second time (two success messages, two log screens).
	if step != Step.REPLAY:
		return
	if not plays:
		_after_replay()
	elif ticks == 0:
		animation_finished()                                    # everything happens at tick 0, and the view did not say so


func _after_replay() -> void:
	if problem.log_index >= 0:                                  # the data canister: no text, its log screen follows
		_set_step(Step.LOG)                                     # (out of REPLAY: its ticks must not end the replay again)
		log_screen_requested.emit(problem.log_sector)
		return
	if problem.success.is_empty():
		_wait_for_continue(close)                               # no text: the box keeps what it shows
	else:
		_show_message(problem.success, close)


## Wrong answer: sound 0x21 and -1 oxygen (not in practice), then "Error!" (`ShowWrongAnswerNotice(type, 0)` (0x426317)).
func _on_wrong(second: bool) -> void:
	_lose_oxygen()
	input_changed.emit(false)
	_show_message(Catalog.text(STRING_ERROR), func() -> void: _after_error(second))


func _after_error(second: bool) -> void:
	if not practice and session.oxygen_code != OxygenModel.OK:
		session.finished = true                                 # out of air: no hint, no solution, the problem is over
		close()
	elif not second:
		_write_message(problem.hint)                            # `ShowProblemHint` (0x4263bb): stays up for the second try
		_set_step(Step.ANSWERING)
		input_changed.emit(true)
	elif not practice and not NO_SHIP_NOTICE_TYPES.has(problem.type.id):
		_show_message(Catalog.text(STRING_DIRECTED_TO_SHIP), _show_solution)   # `ShowWrongAnswerNotice(type, 1)`
	else:
		_show_solution()


## `ShowProblemSolution` (0x426a9e): the worked solution and "Click to go on." (string 11003) on the bottom line,
## until Enter or a click (no time-out). In the game the success text follows; in practice the problem is over.
func _show_solution() -> void:
	_write_message(problem.solution)
	go_on_changed.emit(true)
	_after_message = _after_solution                            # (before the step: whoever hears the step may press Enter)
	_set_step(Step.SOLUTION)


func _after_solution() -> void:
	go_on_changed.emit(false)
	if practice:
		close()
	else:
		_show_success()


## One oxygen per wrong answer; the first "ran out of air" code is kept for the caller.
func _lose_oxygen() -> void:
	sfx_requested.emit(SFX_WRONG)
	reacted.emit(&"wrong")
	if practice:
		return                                                  # practice costs nothing
	var code: int = oxygen_sink.call(-1)
	if code != OxygenModel.OK and session.oxygen_code == OxygenModel.OK:
		session.oxygen_code = code


# --- the combination lock -------------------------------------------------------------------
# The lock (`CombinationLock`) turns the wheels and times its own messages; it reports to the screen, the screen reports here,
# so that misses still cost oxygen in ONE place.

## The answer wheel was stopped on the right label.
func lock_stage_right() -> void:
	sfx_requested.emit(SFX_CORRECT)
	reacted.emit(&"right")


## A wrong stop or no stop at all: one oxygen, no second try (DESIGN 3.7). Returns whether that used up the air: the lock then
## ends once the player has read the solution.
func lock_missed() -> bool:
	_lose_oxygen()
	feedback_shown.emit("" if practice else "-1 oxygen", true)         # (the lock itself prints "ERROR" / "OUT OF TIME")
	return session.oxygen_code != OxygenModel.OK


## The worked solution of the lock asks for Enter with the original's bottom line.
func lock_go_on(shown: bool) -> void:
	go_on_changed.emit(shown)


## The Done button of the ballast panel was pressed with the weights `mask`: `GetBallastAnswer` (0x4196e8) shows the pressed OK picture,
## waits `ticks` ticks (73 = 1 s, in the panel's data) and only then hands the selection to the answer check.
func hold_ballast(mask: int, ticks: int) -> void:
	if step != Step.ANSWERING:
		return
	_held_mask = mask
	_ticks_left = ticks
	_elapsed = 0
	_set_step(Step.HOLD)
	if ticks <= 0:
		_end_hold()


func _end_hold() -> void:
	_set_step(Step.ANSWERING)
	submit_answer(_held_mask)


## Both combination numbers are done (or the air ran out): `misses` of them were missed.
func lock_finished(misses: int) -> void:
	session.misses = misses
	session.finished = true
	session.solved = misses == 0
	close()


# --- messages -------------------------------------------------------------------------------

## `WriteMessageText` (0x4234c0) + `WaitKeyOrTicks(0x92)`: `text` replaces the box's text for 146 ticks, or until Enter /
## a click; then `then` is called.
func _show_message(text: String, then: Callable) -> void:
	_write_message(text)
	_wait_for_continue(then)


## The waiting half of a message: 146 ticks, Enter or a click, then `then`.
func _wait_for_continue(then: Callable) -> void:
	_message_ticks = message_ticks()
	_after_message = then
	_set_step(Step.MESSAGE)


func _write_message(text: String) -> void:
	message_shown.emit(text)


## Lets `ticks` 73 Hz ticks pass (a test can play a whole problem by calling this). Only the steps that wait for time count them:
## a message, the build-up, the replay and the hold.
func advance_ticks(ticks: int) -> void:
	match step:
		Step.MESSAGE:
			_message_ticks -= ticks
			if _message_ticks <= 0:
				press_continue()
		Step.INTRO, Step.REPLAY, Step.HOLD:
			_elapsed += ticks
			_ticks_left -= ticks
			if _ticks_left <= 0:
				if step == Step.HOLD:
					_end_hold()
				else:
					animation_finished()


## Enter or a click: ends a message early, or leaves the worked solution.
func press_continue() -> void:
	if step != Step.MESSAGE and step != Step.SOLUTION:
		return
	var then := _after_message
	_after_message = Callable()
	_set_step(Step.ANSWERING)                                   # (the callback decides what comes next)
	if then.is_valid():
		then.call()


## True while a result is on screen (a timed message or the worked solution) and not the next answer.
func is_waiting_for_continue() -> bool:
	return step == Step.MESSAGE or step == Step.SOLUTION


func is_answering() -> bool:
	return step == Step.ANSWERING


## Ends the problem and tells the view. Public so the debug menu and tests can close a problem without a key press.
func close() -> void:
	if closed:
		return
	closed = true
	_set_step(Step.OVER)
	finished.emit(session)


## The view threw the screen away without a `close`: nothing more is announced.
func abandon() -> void:
	closed = true


func _set_step(new_step: Step) -> void:
	step = new_step
	step_changed.emit(new_step)
