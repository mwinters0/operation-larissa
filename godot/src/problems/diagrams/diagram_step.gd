class_name DiagramStep
extends RefCounted
## One moment of a diagram animation: at `tick` the picture becomes `items` and, maybe, a sound starts or stops.
##
## Teaches: describing an animation as DATA (a list of keyframes) instead of a chain of timers. A
## `DiagramTimeline` holds the steps, the tests read them (which sound at which tick?) and `DiagramBase`
## shows the ones that are due as the step machine counts the ticks (`DiagramBase.animate_to`).

## When the step happens, in ticks of 1/73 s after the animation started (the original's `DelayTicks` unit).
var tick: int = 0
## The sound effect that starts with the step (the original's common effect number), or -1 for none.
var sfx: int = -1
## How many times the original CALLS `PlaySoundEffect` at this moment. Usually 1; `AnimateBarnacles` calls it once per
## healthy barnacle in a row, and since the single wave device restarts on every call only one sound is heard, so
## the port emits `sfx` once whatever this says.
var sfx_calls: int = 1
## `StopCommonSoundEffect` happens with the step (the sound that was started earlier is cut off).
var stop_sfx: bool = false
## Everything the diagram shows from this step on (picture, text and rectangle items, in drawing order).
var items: Array[DiagramItem] = []
