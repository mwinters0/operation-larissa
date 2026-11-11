class_name ProblemState
extends RefCounted
## What a mod that draws a problem screen is told: PLAIN DATA made from a `ProblemInstance` and what the player has entered (the problem-screen API, `docs/create/CONTENT.md`, "Problem screens"), never an object of the rules.
## `build` is the one builder of the state a script gets (`problem_frame(state)`); like `SkinState` it makes the Dictionaries fresh per call and read-only (`ModLoader.freeze`), and it holds no object. The state is
## the problem's VALUES (the record's fields, the way the original's diagram code reads them: a ruler is drawn to the length it asks about), what the type's data says about its picture (the diagram family, its spec, the
## keys of its art, so that a mod can draw an original type from the same facts the original's diagram does) and the screen's state; it is not the judgement. The script is never told
## whether an entry is right, how many tries are used, the oxygen, the hint or the solution: the game's checker (`AnswerChecker`, `ProblemSession`, `ProblemFlow`) is the only thing that knows, and nothing a script
## returns reaches it.
##
## Teaches: a read-only edge drawn by copying into the plainest form there is: values. And what NOT to put on it: the verdict.

## The window a problem screen is drawn in (pixels), the same as `DiagramBase.WINDOW_SIZE`.
const WINDOW_SIZE := Vector2i(640, 400)
## The steps a script is told apart: the diagram builds up (`intro`), an answer is awaited (`answering`), anything else is on screen (`waiting`: a message, the solution, a replay).
const STEPS: Array[String] = ["intro", "answering", "waiting"]


## The state of `problem` with `entry` typed so far (what the calculator or the answer box shows) at `step`.
static func build(problem: ProblemInstance, entry: String, step: ProblemFlow.Step) -> Dictionary:
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
		"window": Vector2(WINDOW_SIZE),
	}
	ModLoader.freeze(state)
	return state


## The skin keys (`problem_art/pa_1843`) of the pictures of `type`'s art bundle, in the order the diagram spec numbers them (`pic`): what a script names to draw one of them. "" for a file that has no key.
static func art_keys(type: ProblemType) -> Array:
	var keys: Array = []
	for path in type.art_files:
		keys.append(GameSkin.key_of(path))
	return keys


## The name of the step a script is told (one of `STEPS`).
static func step_name(step: ProblemFlow.Step) -> String:
	match step:
		ProblemFlow.Step.INTRO:
			return STEPS[0]
		ProblemFlow.Step.ANSWERING:
			return STEPS[1]
	return STEPS[2]

