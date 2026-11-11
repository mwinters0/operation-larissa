class_name ProblemEvents
extends RefCounted
## The presentation events of a problem: what HAPPENED on the problem screen, named, after the rules decided it. `ProblemFlow` is the one emitter (it decides when each thing happens, so no diagram infers one from what it sees), `ProblemScreen` passes
## each to its diagram (`DiagramBase.told`), and a diagram that a mod draws (`ModDiagram`) hands the ones since its last frame to the script, `problem_frame(state, events)` (API version `ModSpec.PROBLEM_EVENTS_API_VERSION`).
## An event is a plain Array `[name, arguments...]`, the shape of the sector's events (`SkinState.event`): the name a String, each argument a number, a bool or a name. It says what happened and is told AFTER the rules decided it: a verdict is never
## told before the answer is judged, and nothing a script returns reaches the flow, so an event is no way to change an outcome.
##
## The set is the same for every problem type, the original's 34 and a pack's. The lock and the ballast panels hear them too (their diagram ignores them); no mod draws those two.
##
##   started    -                     the problem opened. The first event of a problem.
##   step       name                  the step the state tells (`ProblemState.STEPS`: intro, answering, waiting) changed to `name`. It comes LAST of the events one input causes (the answer, the tick, Enter), when the flow has settled:
##                                    a step the flow passes through on its way (Enter on a message goes through "answering" to the closing) is not told.
##   verdict    right, attempt        an answer was judged: `right` (true or false), `attempt` the try it was (1 or 2). An entry with nothing usable in it ("Type a number first.") is no answer and no verdict.
##   damage     amount, tank_lost     a wrong answer cost `amount` oxygen (1); `tank_lost`: that used up the air. Not told in Math Practice, where wrong answers cost nothing. Follows the `verdict`.
##   success    solved                the success replay and text begin. `solved`: the player answered right (false: the success text that follows the worked solution of a second miss). In Math Practice a right answer is told, too.
##   timeout    -                     a message ran its time out (146 ticks) with no Enter or click. The step it leads to follows.
##
## Events are CHANGES; the state (`ProblemState.build`) is the truth. A script bound in the middle of a problem is told what happens after it, not what already happened, and builds its picture from the state it is given, which has the
## step, the entry and the `attempt` the player is on.
##
## Teaches: one name for every moment of a presentation, told by the rules' owner in one shape, so that a stranger's drawing code and the engine's own views hear the same thing.

## The steps the state tells and the `step` event names (`ProblemState.build`): the diagram builds up (`intro`), an answer is awaited (`answering`), anything else is on screen (`waiting`: a message, the solution, a replay, the end).
const STEPS: Array[String] = ["intro", "answering", "waiting"]
## The names, in the order of the table above.
const STARTED := &"started"
const STEP := &"step"
const VERDICT := &"verdict"
const DAMAGE := &"damage"
const SUCCESS := &"success"
const TIMEOUT := &"timeout"
const NAMES: Array[StringName] = [STARTED, STEP, VERDICT, DAMAGE, SUCCESS, TIMEOUT]
## The most events a call into a script carries (the newest): a screen that is not drawn for a while does not build a list as long as the problem.
const MAX_EVENTS := 64


## One event: `[name, arguments...]`, the name a String (the shape of `SkinState.event`); an argument is a number, a bool or a String.
static func make(event_name: StringName, args: Array = []) -> Array:
	var event: Array = [String(event_name)]
	event.append_array(args)
	return event


## The name of the step a script is told (one of `STEPS`).
static func step_name(step: ProblemFlow.Step) -> String:
	match step:
		ProblemFlow.Step.INTRO:
			return STEPS[0]
		ProblemFlow.Step.ANSWERING:
			return STEPS[1]
	return STEPS[2]


## Adds `event` to `queue`, the newest `MAX_EVENTS` kept.
static func push(queue: Array, event: Array) -> void:
	queue.append(event)
	if queue.size() > MAX_EVENTS:
		queue.pop_front()
