@tool
class_name FoeDebuggerPlugin
extends EditorDebuggerPlugin
## Receives what the running sandbox says about the creatures' scripts and hands it to the Foe Script screen.
##
## Teaches: `EditorDebuggerPlugin`, the editor's end of the DEBUGGER CHANNEL. The game, a separate process started by
## the editor, can call `EngineDebugger.send_message("foe_sandbox:lines", [data])` (see `FoeSandbox._report_to_editor`);
## the editor routes every message whose prefix (the text before the first ":") a debugger plugin claims in `_has_capture`
## to its `_capture`. The data are plain Variants (Array, Dictionary, numbers) because they cross a process boundary.
## This class is only the thin part that the editor itself must create (an `EditorDebuggerPlugin` cannot even be
## instantiated outside the editor); what to do with a message is `Relay`, a plain object with signals, so the path from
## message to marked line can be tested by calling `Relay.handle` (tests/engine/test_foe_sandbox_debug.gd).

## The part of the message names before the ":".
const PREFIX := "foe_sandbox"

var relay := Relay.new()


## Turns a message into a signal.
class Relay extends RefCounted:
	## A report of `FoeSandbox.line_report()`: where every creature on the shown screen is in the `.foe` text.
	signal lines_reported(report: Dictionary)
	## The game ended: nothing is running any more, so no line is current.
	signal run_ended

	## True when the message was one of ours.
	func handle(message: String, data: Array) -> bool:
		if message != FoeSandbox.LINES_MESSAGE or data.is_empty() or not data[0] is Dictionary:
			return false
		lines_reported.emit(data[0])
		return true


func _has_capture(capture: String) -> bool:
	return capture == PREFIX


func _capture(message: String, data: Array, _session_id: int) -> bool:
	return relay.handle(message, data)


func _setup_session(session_id: int) -> void:
	get_session(session_id).stopped.connect(relay.run_ended.emit)
