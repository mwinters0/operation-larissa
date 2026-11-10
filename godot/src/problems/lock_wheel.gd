class_name LockWheel
extends RefCounted
## The timing of the combination lock's wheels (problem type 0), in the original's 73 Hz ticks.
##
## Teaches: a small state machine driven by a counter instead of by the frame rate. Nothing here
## knows about nodes or seconds; `advance(ticks)` moves time forward and the tests call it with
## exact tick counts. `CombinationLock` (the Control) only converts real time into ticks. The structure
## (8 labels, 32 positions) is the wheel's; the waits are the run's `Tuning` (`lock_wheel` section: the original's
## numbers are below), which the wheel is given when it is made. The numbers are verified from `DoCombinationLock`
## (docs/data/lock_wheel.json, DESIGN 3.7):
##
##   * a wheel has 8 labels and 32 positions (4 per label); position 0 puts label 0 under the arrow
##   * the ANSWER wheel moves one label (4 positions of 9 ticks = 36 ticks), then waits 73 ticks
##     for a key; a label therefore takes 109 ticks = 1.49 s and a revolution 872 ticks = 11.95 s
##   * keys are read in the 73 tick window; while the wheel moves (4 sub-steps of 9 ticks, each loading sound 0x26, which
##     throws the queued input away) only a key of the last sub-step survives, to act when the window opens (CombinationLock)
##   * the label `s` is under the arrow at position `(8 - s) * 4` (position 0 for label 0)
##   * the lock gives up ("OUT OF TIME") when the right position went by twice without a key
##   * a wrong stop is an "ERROR"; both cost one oxygen and are NOT repeated
##
## The OPERAND wheel (`Spin`) just turns to the next operand, 9 ticks per quarter label.

const TICKS_PER_SECOND := 73.0
const POSITIONS := 32
const LABELS := 8
const POSITIONS_PER_LABEL := 4

enum State {
	MOVING,        ## the wheel turns to the next label (keys are ignored)
	WAITING,       ## a label is under the arrow: a key stops the wheel
	RIGHT,         ## the player stopped on the right label
	WRONG,         ## the player stopped on another label ("ERROR")
	TIMED_OUT,     ## the right label passed twice ("OUT OF TIME")
}

## Which label (0-7) of the answer wheel is the right one.
var target_slot: int = 0
var state: State = State.MOVING
## Where the wheel is, 0-31 (it counts up: the labels travel clockwise).
var position: int = 0
## How many times the window at the right position has run out unused.
var passes: int = 0
## The waits, from the `Tuning` the wheel was made with: ticks of one position of the wheel (9), of the window in which a key stops the
## wheel (73), and how many times the right position may pass without a key before time is up (2).
var ticks_per_position: int
var key_window_ticks: int
var max_passes: int
var _ticks_in_state: int = 0
## Total ticks since the start (for tests and for the screen).
var elapsed_ticks: int = 0


func _init(answer_slot: int, tuning: Tuning) -> void:
	target_slot = answer_slot
	ticks_per_position = tuning.lock_ticks_per_position
	key_window_ticks = tuning.lock_key_window_ticks
	max_passes = tuning.lock_max_passes


## Ticks the wheel turns for one label (4 positions: 36), then the key window follows.
func motion_ticks() -> int:
	return ticks_per_position * POSITIONS_PER_LABEL


## Ticks one label takes, motion and key window (109).
func ticks_per_label() -> int:
	return motion_ticks() + key_window_ticks


## Ticks of a whole revolution of the wheel (872).
func ticks_per_revolution() -> int:
	return ticks_per_label() * LABELS


## The wheel position that puts label `slot` under the arrow.
static func target_position(slot: int) -> int:
	return ((LABELS - slot) * POSITIONS_PER_LABEL) % POSITIONS


func is_finished() -> bool:
	return state == State.RIGHT or state == State.WRONG or state == State.TIMED_OUT


## Ticks of the current movement or wait that are over.
func ticks_in_state() -> int:
	return _ticks_in_state


func is_waiting_for_key() -> bool:
	return state == State.WAITING


## The label (0-7) that is under the arrow right now (only exact when the wheel is not between two labels).
func label_under_arrow() -> int:
	return posmod(LABELS - floori(position / float(POSITIONS_PER_LABEL)), LABELS)


## Lets `ticks` ticks of game time pass (one at a time, so every boundary is hit exactly).
func advance(ticks: int) -> void:
	for i in ticks:
		if is_finished():
			return
		_tick()


func _tick() -> void:
	elapsed_ticks += 1
	_ticks_in_state += 1
	match state:
		State.MOVING:
			if _ticks_in_state % ticks_per_position == 0:
				position = (position + 1) % POSITIONS
			if _ticks_in_state >= motion_ticks():
				_enter(State.WAITING)
		State.WAITING:
			if _ticks_in_state >= key_window_ticks:
				if position == target_position(target_slot):
					passes += 1
					if passes >= max_passes:
						_enter(State.TIMED_OUT)
						return
				_enter(State.MOVING)


## Space, Enter or a click: stops the wheel if a key is being read. Returns true if it counted.
func press_stop() -> bool:
	if state != State.WAITING:
		return false
	_enter(State.RIGHT if position == target_position(target_slot) else State.WRONG)
	return true


func _enter(new_state: State) -> void:
	state = new_state
	_ticks_in_state = 0


## The operand wheel turning from one position to another in a fixed direction.
class Spin extends RefCounted:
	var from_position: int
	var to_position: int
	var direction: int
	var steps: int
	var ticks: int = 0
	## Ticks of one position (`Tuning.lock_ticks_per_position`).
	var ticks_per_position: int

	## `direction` is +1 (labels travel clockwise) or -1.
	func _init(from_pos: int, to_pos: int, spin_direction: int, tuning: Tuning) -> void:
		ticks_per_position = tuning.lock_ticks_per_position
		from_position = posmod(from_pos, LockWheel.POSITIONS)
		to_position = posmod(to_pos, LockWheel.POSITIONS)
		direction = spin_direction
		steps = posmod((to_position - from_position) * direction, LockWheel.POSITIONS)
		if steps == 0:
			steps = LockWheel.POSITIONS            # the original turns at least one step: the same number again is a full revolution

	func advance(more_ticks: int) -> void:
		ticks = mini(ticks + more_ticks, steps * ticks_per_position)

	func position() -> int:
		return posmod(from_position + direction * floori(ticks / float(ticks_per_position)), LockWheel.POSITIONS)

	func is_finished() -> bool:
		return ticks >= steps * ticks_per_position

	func total_ticks() -> int:
		return steps * ticks_per_position
