class_name TickMeter
extends RefCounted
## Turns real time into the original's ticks (1/73 s): "this much time went by, how many whole ticks is that?"
##
## Teaches: one small converter instead of the same three lines in every screen. The RULES count in ticks (a message stays
## 146 ticks, a pressed Done button is held 73, the log scan lasts 240); a VIEW that is shown on a real screen has only seconds
## (`_process(delta)`), so it feeds them in here and hands the whole ticks to the rules. The part of a tick that is left over is
## kept for next time, so no time is lost at any frame rate. A test skips all this and gives the rules the ticks directly.

const TICKS_PER_SECOND := 73.0

var _fraction: float = 0.0


## `delta` seconds went by: the whole ticks that makes (the rest is kept).
func feed(delta: float) -> int:
	_fraction += delta * TICKS_PER_SECOND
	var whole := floori(_fraction)
	if whole > 0:
		_fraction -= whole
	return maxi(whole, 0)


## Forget the part of a tick that is left over (a new step starts from a whole tick).
func reset() -> void:
	_fraction = 0.0


## The seconds `ticks` ticks last (for a `Timer` or an `AnimationPlayer` that must be told in seconds).
static func seconds(ticks: int) -> float:
	return float(ticks) / TICKS_PER_SECOND
