class_name CombinationLock
extends Node
## The supply station's combination lock (problem type 0): the operand wheel turns to each number
## of a sum, then the player stops the answer wheel on the result.
##
## Teaches: a state machine that is stepped by TICKS, not by frames. `advance_ticks(n)` is the whole
## engine; `_process` only converts real time into 73 Hz ticks (the same idea as `GameClock`), so a
## test can play a whole lock in microseconds by calling `advance_ticks` itself. The timing is the
## original's (`LockWheel`); the drawing is `LockDiagram`; the texts come from the problem type.
##
## The flow (DESIGN 3.7), twice (two combination numbers):
##   INTRO      "Press Enter to begin."                      Enter -> stage 1
##   OPERANDS   the operand wheel turns to the next number, which joins the sum in the long box
##   REVEAL     the operator that follows it is held back, then blinks into its box (see OPERATOR_REVEAL);
##              OPERANDS and REVEAL alternate until the "=" has been revealed
##   ANSWER     the answer wheel turns label by label; Space, Enter or a click stops it
##   MISS_REASON "ERROR" / "OUT OF TIME" and 1 oxygen          2 s, or Enter / a click  (no air left: the lock ends here)
##   MISS_HINT   "Problem has been directed to ship ..."        2 s, or Enter / a click
##   MISS_SOLUTION the worked solution and "Click to go on."    until Enter / a click   (no second try)
##   NOTICE     "First number accepted. Get ready!" / "Lock opened."  2 s, or Enter / a click
##   DONE       `finished` is emitted
##
## Whoever shows the lock (`ProblemScreen`) listens to the signals: it prints the texts on the monitor,
## takes the oxygen at a miss and closes the problem when the lock says it is `finished`.

## Print this on the monitor.
signal say(text: String)
## The answer wheel was stopped on the right label, or a miss happened ("ERROR", "OUT OF TIME").
signal stage_right
signal stage_missed(reason: String)
## The bottom line of the monitor ("Click to go on.") is wanted (true) or can go (false). Only the worked
## solution has it: the other messages just time out.
signal go_on_prompt(shown: bool)
## The original's common sounds (DESIGN 7): the wheel ticks (`lock_tick`) and settles (`lock_settle`).
signal sfx_requested(sfx: StringName)
## The lock is over (both stages done, or the air ran out).
signal finished

enum Phase { INTRO, OPERANDS, REVEAL, ANSWER, MISS_REASON, MISS_HINT, MISS_SOLUTION, NOTICE, DONE }

const SFX_TICK := &"lock_tick"
const SFX_SETTLE := &"lock_settle"
## What the operator box does after each number has settled, as (ticks, is the operator visible) steps; after
## the last step the operator stays on. The original (`LockRevealOperator` (0x422176)) blanks the box and waits 146 ticks
## (`DelayTicks(0x92)`, a busy wait that reads no key), then shows the operator for 24 ticks, blanks it for
## 24 and shows it for good: 194 ticks = 2.66 s after EVERY number, the last one (the "=") included.
## The sum's operator text joins the long box only when that is over. No key or click shortens it.
const OPERATOR_REVEAL: Array = [[146, false], [24, true], [24, false]]
const STAGES := 2
## The stop button's hotspot 0xd (`AddHotspot(0xd, 116, 58, 113, 47)` in `LockRunStage` (0x421dc9)), window pixels. A click in it
## counts as Enter; it is only a hotspot while the key window is open, and acts on the left button's RELEASE.
const STOP_BUTTON := Rect2(116, 58, 113, 47)

var phase: Phase = Phase.INTRO
var stage: int = 0
## How many of the two combination numbers were missed (0-2).
var misses: int = 0
## Set by the owner when a miss used up the air: the lock then ends after the solution was read.
var abort_after_miss: bool = false
var diagram: LockDiagram
var problem: ProblemInstance
## Math Practice: a right second number is answered with one of the four phrases (`CorrectPhrase`) instead of "Lock opened."
## (`DoCombinationLock` (0x421780): `ShowCorrectPhrase` unless `DAT_00449f48` still says 2, i.e. unless that number was missed).
var practice: bool = false
var rng := RandomNumberGenerator.new()
## The waits of the wheels: the run's (`ProblemScreen`, the one place a lock is made in the game, hands over `GameState.tuning`). The original's numbers
## are the value a lock made on its own has: a test of the lock without a screen.
var tuning: Tuning = Tuning.original()
## The wheels in this stage. The answer wheel is a new `LockWheel` for each number but starts where the last
## one was stopped (`LockAnswerWheelPos` (0x448d25) is not reset between the two numbers).
var answer_wheel: LockWheel
var answer_position: int = 0
var operand_position: int = 0

var _program: LockProgram
var _operand_index: int = 0
var _spin: LockWheel.Spin
var _spins_done: int = 0
var _reveal_step: int = 0              # which step of OPERATOR_REVEAL is running
var _reveal_ticks: int = 0             # ticks left in that step
var _wait_ticks: int = 0              # ticks left of a timed message
var _expression: String = ""
## Turns the real time of `_process` into the lock's ticks (1/73 s).
var _meter := TickMeter.new()
## A stop (Space, Enter, click on the button) that came in while the wheel moved and was not lost: it acts the moment the key window opens.
var _stop_pending: bool = false
## Is the sound on? (Options > Sound effects.) Tests replace it.
var sound_is_on: Callable = func() -> bool: return Audio.is_bus_enabled(Audio.SFX)


## Shows `lock_diagram` and starts with the instruction text.
func setup(new_problem: ProblemInstance, lock_diagram: LockDiagram) -> void:
	problem = new_problem
	diagram = lock_diagram
	phase = Phase.INTRO
	stage = 0
	misses = 0
	answer_position = 0
	operand_position = 0
	say.emit(problem.prompt)


func _process(delta: float) -> void:
	var whole := _meter.feed(delta)
	if whole > 0:
		advance_ticks(whole)


# --- input ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.DONE:
		return
	# Only the answer wheel reads Space and has a stop button; every message ends with Enter or a click ANYWHERE (the
	# original puts a hotspot over the whole screen, `AddHotspot(0xd, 0, 0, 640, 400)`). A click acts on the button's
	# RELEASE: `PollInput` (0x410c7d) turns the left-button-up event into the hotspot id.
	var answering := phase == Phase.ANSWER
	var pressed := false
	if event is InputEventKey:
		var key := event as InputEventKey
		var is_enter := key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER
		pressed = key.pressed and not key.echo and (is_enter or (answering and key.keycode == KEY_SPACE))
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		pressed = not click.pressed and click.button_index == MOUSE_BUTTON_LEFT and (not answering or STOP_BUTTON.has_point(click.position))
	if pressed:
		get_viewport().set_input_as_handled()
		press_key()


## Space, Enter or a click. What it does depends on the phase.
func press_key() -> void:
	match phase:
		Phase.INTRO:
			_begin_stage()
		Phase.ANSWER:
			_stop_wheel()
		Phase.MISS_REASON:
			_after_reason()
		Phase.MISS_HINT:
			_after_hint()
		Phase.MISS_SOLUTION:
			_after_solution()
		Phase.NOTICE:
			_after_notice()


## Each of the answer wheel's four sub-steps of 9 ticks (`Tuning.lock_ticks_per_position`) starts with `PlaySoundEffect(0x26)`; that sound
## is not cached, so its load (`GetResource` (0x410fda) -> `PumpMessages` (0x410b8f)) drains the queue and throws away every key and click
## that came in meanwhile. Only what arrives after the LAST sub-step's sound load (the final 9 ticks of the motion) is still there when the
## key window opens; with the sound off nothing is loaded and everything survives.
func _in_last_substep() -> bool:
	return answer_wheel.ticks_in_state() >= answer_wheel.motion_ticks() - answer_wheel.ticks_per_position


## A stop while the wheel moves is lost unless it came in the last sub-step (or the sound is off); it then acts as soon as
## the key window opens. In the window it acts at once.
func _stop_wheel() -> void:
	if answer_wheel.state == LockWheel.State.MOVING:
		if _in_last_substep() or not sound_is_on.call():
			_stop_pending = true
		return
	if answer_wheel.press_stop():
		_answer_stopped()


# --- time ----------------------------------------------------------------------------------

## Lets `ticks` 73 Hz ticks pass. The whole lock runs on this.
func advance_ticks(ticks: int) -> void:
	for i in ticks:
		_tick()


func _tick() -> void:
	match phase:
		Phase.OPERANDS:
			_tick_operands()
		Phase.REVEAL:
			_tick_reveal()
		Phase.ANSWER:
			var before := answer_wheel.position
			answer_wheel.advance(1)
			if answer_wheel.position != before:
				sfx_requested.emit(SFX_TICK)
			answer_position = answer_wheel.position
			diagram.set_wheels(operand_position, answer_position)
			if answer_wheel.state == LockWheel.State.TIMED_OUT:
				_miss("OUT OF TIME")
			elif _stop_pending and answer_wheel.state == LockWheel.State.WAITING:
				_stop_pending = false
				_stop_wheel()
		Phase.MISS_REASON:
			if _message_timed_out():
				_after_reason()
		Phase.MISS_HINT:
			if _message_timed_out():
				_after_hint()
		Phase.NOTICE:
			if _message_timed_out():
				_after_notice()


# --- one stage -------------------------------------------------------------------------------

func _begin_stage() -> void:
	_program = LockProgram.from_record(problem.type, problem.record, stage)
	_operand_index = 0
	_spins_done = 0                       # the first wheel of every stage turns forward (`LockRunStage` clears the direction)
	_expression = ""
	diagram.set_boxes("", "")
	say.emit("")
	phase = Phase.OPERANDS
	_start_spin()


## The operand wheel turns to the next number. The direction alternates from number to number.
func _start_spin() -> void:
	diagram.set_operand_window(false)      # (the wheel's first redraw paints over the window)
	var slot := _program.operand_slots[_operand_index]
	var direction := 1 if _spins_done % 2 == 0 else -1
	_spin = LockWheel.Spin.new(operand_position, LockWheel.target_position(slot), direction, tuning)
	_spins_done += 1


func _tick_operands() -> void:
	var before := _spin.position()
	_spin.advance(1)
	operand_position = _spin.position()
	if operand_position != before:
		sfx_requested.emit(SFX_TICK)
	diagram.set_wheels(operand_position, answer_position)
	if _spin.is_finished():
		_operand_landed()


## The operand wheel has settled: its number joins the sum, the operator box goes dark and the
## operator that follows is revealed step by step (OPERATOR_REVEAL).
func _operand_landed() -> void:
	sfx_requested.emit(SFX_SETTLE)
	diagram.set_operand_window(true)
	var label := _program.operands[_operand_index]
	_expression += label if _operand_index == 0 else " %s" % label
	diagram.set_boxes("", _expression)
	phase = Phase.REVEAL
	_reveal_step = 0
	_reveal_ticks = OPERATOR_REVEAL[0][0]


func _tick_reveal() -> void:
	_reveal_ticks -= 1
	if _reveal_ticks > 0:
		return
	_reveal_step += 1
	if _reveal_step < OPERATOR_REVEAL.size():
		_reveal_ticks = OPERATOR_REVEAL[_reveal_step][0]
		diagram.set_boxes(_next_operator() if OPERATOR_REVEAL[_reveal_step][1] else "", _expression)
		return
	# Over: the operator stays on, joins the sum, and the wheel goes on to the next number (or the player's turn).
	_expression += " " + _next_operator()
	diagram.set_boxes(_next_operator(), _expression)
	_operand_index += 1
	if _operand_index < _program.operands.size():
		phase = Phase.OPERANDS
		_start_spin()
	else:
		_begin_answer()


## The operator that follows the number just settled: "+", "-", "x", "/", or "=" after the last one.
func _next_operator() -> String:
	var last := _operand_index == _program.operands.size() - 1
	return "=" if last else _program.operators[_operand_index]


## Now the player's part: the answer wheel starts turning from position 0.
func _begin_answer() -> void:
	answer_wheel = LockWheel.new(_program.answer_slot, tuning)
	answer_wheel.position = answer_position
	_stop_pending = false                  # (`FlushInput` (0x410c6c) runs just before the wheel starts)
	phase = Phase.ANSWER
	diagram.set_operand_window(false)      # (`LockRunStage` redraws the operand wheel once the "=" is out, before the answer wheel turns)
	diagram.set_wheels(operand_position, answer_position)


func _answer_stopped() -> void:
	if answer_wheel.state == LockWheel.State.RIGHT:
		stage_right.emit()
		_notice(true)
	else:
		_miss("ERROR")


func _miss(reason: String) -> void:
	misses += 1
	phase = Phase.MISS_REASON
	_wait_ticks = ProblemFlow.message_ticks()
	stage_missed.emit(reason)             # (the owner takes the oxygen and may set `abort_after_miss`)
	say.emit(reason)


## "ERROR" has been read. Without air the lock ends here; otherwise the hint comes, then the solution.
func _after_reason() -> void:
	if abort_after_miss:
		_finish()
		return
	phase = Phase.MISS_HINT
	_wait_ticks = ProblemFlow.message_ticks()
	say.emit(problem.type.text_at(1))


func _after_hint() -> void:
	phase = Phase.MISS_SOLUTION
	say.emit(ProblemTexts.lock_solution(problem.type, problem.record, stage))
	go_on_prompt.emit(true)


func _after_solution() -> void:
	go_on_prompt.emit(false)
	_notice()


## Counts a timed message down; true when its 146 ticks are over.
func _message_timed_out() -> bool:
	_wait_ticks -= 1
	return _wait_ticks <= 0


## "First number accepted. Get ready!" after the first stage, "Lock opened." after the second.
func _notice(was_right: bool = false) -> void:
	phase = Phase.NOTICE
	_wait_ticks = ProblemFlow.message_ticks()
	if practice and was_right and stage == STAGES - 1:
		say.emit(CorrectPhrase.pick(rng))
	else:
		say.emit(problem.type.text_at(2 + stage))


func _after_notice() -> void:
	stage += 1
	if stage >= STAGES:
		_finish()
	else:
		_begin_stage()


func _finish() -> void:
	phase = Phase.DONE
	finished.emit()
