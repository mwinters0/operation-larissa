class_name DiagramTimeline
extends RefCounted
## The build-up (or success replay) animation of a diagram as a list of `DiagramStep`s.
##
## Teaches: keeping the time line apart from the playing of it. The timeline is plain data that a unit test
## can check tick by tick. `end_tick` is the LENGTH of the animation: `ProblemFlow` counts that many ticks and tells the diagram where
## it is (`DiagramBase.animate_to(tick)`), so no tween or timer decides how long the build-up or the replay holds up play.
##
## Ticks are the original's 1/73 s units (`DelayTicks`, `set_alarm`). `end_tick` is when the original's drawing function returns
## (after its last delay), which is when the prompt appears / the success message is written.

const TICKS_PER_SECOND := TickMeter.TICKS_PER_SECOND

var steps: Array[DiagramStep] = []
var end_tick: int = 0


func is_empty() -> bool:
	return steps.is_empty()


## Adds a step (steps must be added in time order) and returns it.
func add_step(tick: int, items: Array, sfx: int = -1, stop_sfx: bool = false) -> DiagramStep:
	var step := DiagramStep.new()
	step.tick = tick
	step.items.assign(items)
	step.sfx = sfx
	step.stop_sfx = stop_sfx
	steps.append(step)
	end_tick = maxi(end_tick, tick)
	return step


## [[tick, sfx], ...] of every step that starts a sound, in order.
func sounds() -> Array:
	var found := []
	for step in steps:
		if step.sfx >= 0:
			found.append([step.tick, step.sfx])
	return found


## Ticks of the steps that stop the sound.
func stops() -> PackedInt32Array:
	var found := PackedInt32Array()
	for step in steps:
		if step.stop_sfx:
			found.append(step.tick)
	return found


## How long the whole animation takes.
func duration() -> float:
	return seconds(end_tick)


static func seconds(ticks: int) -> float:
	return float(ticks) / TICKS_PER_SECOND
