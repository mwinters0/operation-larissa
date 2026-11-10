class_name WindowFocus
extends RefCounted
## One switch: do the window's focus notifications count? (`AudioService` and `GameClock` ask.)
##
## Teaches: a `static var` as shared configuration that needs no node, and why a global behaviour needs an off switch for
## the test runner.
##
## A normal run: yes. A run driven by a script (`godot -s ...`: the gdUnit4 test runner, the importers) has a window nobody
## is looking at, whose focus comes and goes at the whim of the desktop; a test must not find the game clock frozen or a
## speech clip killed because the compositor moved the focus. The tests of the focus behaviour switch it on themselves.

static var enabled: bool = _default()


static func _default() -> bool:
	var loop := Engine.get_main_loop()
	return loop == null or loop.get_script() == null
