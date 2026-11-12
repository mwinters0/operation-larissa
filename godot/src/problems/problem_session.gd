class_name ProblemSession
extends RefCounted
## The attempt rules of a math problem (DESIGN 5.2): hint after the first miss, solution
## after the second, one oxygen per miss.
##
## Teaches: a tiny state machine with no nodes. `ProblemScreen` forwards the player's
## answers to `submit` and reacts to the returned `Outcome`; the rules can be unit tested
## without any UI.

enum Outcome {
	CORRECT_FIRST,     ## right at the first try: success message, nothing lost
	CORRECT_SECOND,    ## right at the second try: success message, 1 oxygen was lost earlier
	WRONG_HINT,        ## first miss: -1 oxygen, show the hint
	WRONG_SOLUTION,    ## second miss: -1 oxygen, show the worked solution; the problem is over
	INVALID,           ## nothing usable was typed: no attempt is used up
	ALREADY_OVER,      ## the problem is finished, nothing to submit
}

var instance: ProblemInstance
## Wrong answers so far (0-2). Each one costs one oxygen.
var misses: int = 0
var finished: bool = false
var solved: bool = false
## What `GameState.update_oxygen` answered when a miss used up the air (`OxygenModel.OK` if it
## never did). The screen fills it in; the owner of the problem decides what a lost tank means.
var oxygen_code: int = OxygenModel.OK
## Asked before the type's own comparison: `func(problem: ProblemInstance, answer: Variant) -> Variant` gives true or false when a mod of the campaign judges the answers of this type (`RuleHooks.judge_answer`, which the owner
## points it at) and null when nobody does or the mod faulted: then the type's data judges (`ProblemInstance.check`). Unset: the data judges, as in the original.
var judge := Callable()


func _init(problem: ProblemInstance) -> void:
	instance = problem


## The session of a problem that could not be made (`ProblemFactory` returned null and told why): over at once, nothing lost, no
## instance. The owner answers the world with it, because the world entered "a problem is open" when it asked (`SimWorld.open_problem`)
## and only `problem_resolved` leaves that: the sub goes on as if the problem were solved without a screen, and a data canister stays taken.
static func not_made() -> ProblemSession:
	var none := ProblemSession.new(null)
	none.finished = true
	return none


## Oxygen the player has lost to wrong answers so far (the screen applies it to GameState
## one point at a time, as each miss happens).
func oxygen_lost() -> int:
	return misses


func submit(answer: Variant) -> Outcome:
	if finished:
		return Outcome.ALREADY_OVER
	if answer == null:
		return Outcome.INVALID
	var verdict: Variant = judge.call(instance, answer) if judge.is_valid() else null
	var right: bool = verdict if verdict is bool else instance.check(answer)
	if right:
		finished = true
		solved = true
		return Outcome.CORRECT_FIRST if misses == 0 else Outcome.CORRECT_SECOND
	misses += 1
	if misses >= 2:
		finished = true
		return Outcome.WRONG_SOLUTION
	return Outcome.WRONG_HINT
