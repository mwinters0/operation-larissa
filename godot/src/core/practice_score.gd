class_name PracticeScore
extends RefCounted
## The score of one practice set: how many problems, how many right at the first and at the second try.
##
## Teaches: a tiny model with the counting rules in one place (and a unit test). The screen shows the numbers
## the original shows: "Number of problems", "Correct on 1st try", "Correct on 2nd try" (and, for Mental Math,
## "Problems correct"). A problem the player gets wrong twice counts as a problem only.

var problems: int = 0
var first_try: int = 0
var second_try: int = 0


func reset() -> void:
	problems = 0
	first_try = 0
	second_try = 0


## All right answers, whichever try they came at ("Problems correct" in Mental Math, where there is only one try).
func correct() -> int:
	return first_try + second_try


## A finished math problem: right at the first try, right at the second try (after one miss), or lost.
func record_session(session: ProblemSession) -> void:
	problems += 1
	if session.solved:
		if session.misses == 0:
			first_try += 1
		else:
			second_try += 1


## One of the lock's two combination numbers (Mental Math): right, or a miss (there is no second try).
func record_lock_stage(right: bool) -> void:
	problems += 1
	if right:
		first_try += 1
