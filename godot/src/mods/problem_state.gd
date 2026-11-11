class_name ProblemState
extends RefCounted
## What a mod that draws a problem screen is told: PLAIN DATA made from a `ProblemInstance` and what the player has entered (the problem-screen API, `docs/create/CONTENT.md`, "Problem screens"), never an object of the rules.
## `build` is the one builder of the state a script gets (`problem_frame(state)`); like `SkinState` it makes the Dictionaries fresh per call and read-only (`ModLoader.freeze`), and it holds no object. The state is
## the problem's VALUES (the record's fields, the way the original's diagram code reads them: a ruler is drawn to the length it asks about), what the type's data says about its picture (the diagram family, its spec, the
## keys of its art, so that a mod can draw an original type from the same facts the original's diagram does) and the screen's state; it is not the judgement. The script is never told
## whether an entry is right, the oxygen, the hint or the solution: the game's checker (`AnswerChecker`, `ProblemSession`, `ProblemFlow`) is the only thing that knows, and nothing a script
## returns reaches it. It is told which TRY the player is on (`attempt`: the first, or the second after a miss, which the player sees) and, after the rules decided, what happened (`ProblemEvents`, the `events` argument of `problem_frame`): the
## state is the truth and the events are changes, so a script bound in the middle of a problem builds the same picture from the state.
##
## Teaches: a read-only edge drawn by copying into the plainest form there is: values. And what NOT to put on it: the verdict.

## The window a problem screen is drawn in (pixels), the same as `DiagramBase.WINDOW_SIZE`.
const WINDOW_SIZE := Vector2i(640, 400)
## The steps a script is told apart (`ProblemEvents.STEPS`): the diagram builds up (`intro`), an answer is awaited (`answering`), anything else is on screen (`waiting`: a message, the solution, a replay).
const STEPS: Array[String] = ProblemEvents.STEPS


## The state of `problem` with `entry` typed so far (what the calculator or the answer box shows) at `step`, on try `attempt` (1 or 2), with the animation's position `clock` (`clock`, `idle_clock` for a script that is not told one).
static func build(problem: ProblemInstance, entry: String, step: ProblemFlow.Step, attempt: int = 1, clock_of_animation: Dictionary = {}) -> Dictionary:
	var state := {
		"type": problem.type.id,
		"level": problem.level,
		"title": problem.title,
		"prompt": problem.prompt,
		"fields": HookState.fields(problem),
		"family": String(problem.type.diagram.get("family", "")),
		"diagram": problem.type.diagram.duplicate(true),
		"art": art_keys(problem.type),
		"entry": entry,
		"step": step_name(step),
		"attempt": clampi(attempt, 1, 2),
		"clock": clock_of_animation if not clock_of_animation.is_empty() else idle_clock(),
		"window": Vector2(WINDOW_SIZE),
	}
	ModLoader.freeze(state)
	return state


## WHERE THE PRESENTATION IS (`clock` of the state, API version `ModSpec.DRAWS_THE_GAME_API_VERSION`): `animation` is "intro" (the diagram builds up), "replay" (the right answer is replayed) or "" (no animation runs), `tick` how many of its ticks are over (0 to
## `length`), `length` how many ticks it lasts and `since` the tick the script was last told in this animation (-1: this is the first call of it), so that tick `n` went by since the last call exactly when `since < n <= tick`. The ticks are the original's (1/73 s)
## and the lengths are the original's data, counted by `ProblemFlow` and shown by `DiagramBase.animate_to`: the clock only reports them, stands still when they do, and the script cannot make an animation longer or shorter.
static func clock(animation: String, tick: int, length: int, since: int) -> Dictionary:
	return {"animation": animation, "tick": tick, "length": length, "since": since}


## The clock of a screen with no animation running, and what a script of an API before the clock is told always.
static func idle_clock() -> Dictionary:
	return clock("", 0, 0, -1)


## The skin keys (`problem_art/pa_1843`) of the pictures of `type`'s art bundle, in the order the diagram spec numbers them (`pic`): what a script names to draw one of them. "" for a file that has no key.
static func art_keys(type: ProblemType) -> Array:
	var keys: Array = []
	for path in type.art_files:
		keys.append(GameSkin.key_of(path))
	return keys


## The name of the step a script is told (one of `STEPS`).
static func step_name(step: ProblemFlow.Step) -> String:
	return ProblemEvents.step_name(step)

