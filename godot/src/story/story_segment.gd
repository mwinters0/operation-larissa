class_name StorySegment
extends Control
## The base of every part of the opening and closing sequences: a 640 x 400 screen that plays by itself,
## can be skipped, and says `finished` when it is over.
##
## Teaches: a tiny shared interface (signal + two methods) so that a director (`Opening`, `Game`) can run
## very different cutscenes in a row with one `await segment.finished`. The keys are handled by the director,
## not by the segments, so "Enter = next part, Space / Escape = skip everything" is written in one place.

signal finished

## Set once the segment is over; the coroutines of a subclass check it after every `await`.
var done: bool = false


## Enter: go on to the next step of this segment (default: the segment ends).
func advance() -> void:
	finish()


## A left mouse button RELEASE at `at` (screen position). The opening has one whole-screen hotspot (id 0xd, added by
## `OpeningSequence` 0x42b16b), and `PollInput` (0x410c7d) turns a left-button release inside a hotspot into the bare
## hotspot id, so a release anywhere is the Enter key (default: `advance()`). The press is the same hotspot with 0x8000
## added, a code nobody in the opening answers.
func click(_at: Vector2) -> void:
	advance()


## Space / Escape: leave at once.
func skip() -> void:
	finish()


## The two methods an `AnimationPlayer` built from a `CutsceneTimeline` calls on its root (`Cutscene.animation()`): a sound
## cue plays the sound of that name; an event cue is answered by the segment (`cue()`, overridden by the segments whose
## timeline has events).
func play_sfx(sfx: StringName) -> void:
	Audio.play_sfx(sfx)


func cue(event: StringName) -> void:
	push_warning("%s has no answer to the cue '%s'" % [name, event])


## Stops the speech and tells the director. Calling it twice does nothing.
func finish() -> void:
	if done:
		return
	done = true
	Audio.stop_voice()
	finished.emit()


## A `Timer`-free pause for coroutines that must stop when the segment is skipped:
## `if not await pause(2.0): return`
## (`process_always = false`: the timer stands still while the director has the scene tree paused, i.e. while
## the window is not the active one.)
func pause(seconds: float) -> bool:
	await get_tree().create_timer(seconds, false).timeout
	return not done


## The same, counted in the original's ticks (1/73 s): `if not await pause_ticks(219): return`. A step that holds up the story gets its
## length in ticks, converted to seconds in this one place.
func pause_ticks(ticks: int) -> bool:
	return await pause(TickMeter.seconds(ticks))
