class_name ModDiagram
extends DiagramBase
## The diagram of a problem type whose screen a MOD draws (diagram family `mod`, `ModProblems`). The type is plain data like the original's 34 (words, records, how an answer is judged); this node only shows the picture on the
## left monitor, by asking the mod's sandboxed script what to draw: `problem_frame(state)` gets the problem's values and the screen's state as plain data (`ProblemState.build`) and returns a draw list that the game checks
## (`ModDraw.validate`) and draws in the `ModLayer` nodes of a `ModLayerStack` of its own. The script is asked again only when what it was told changes (the entry the player has typed so far, the step), never per frame, and it decides nothing:
## the calculator or the answer box, `AnswerChecker`, `ProblemSession` and `ProblemFlow` are the game's, so the answer, the tries, the oxygen and every duration are what they are for any type whatever the script returns.
##
## THE PLAIN PICTURE. A mod that is absent (the chain has no such mod, it was refused or unloaded), quarantined, or has not yet returned a good list leaves what the type's data describes: the generic `items` of the diagram
## spec (`DiagramBase`), so the problem is always shown and always completes. A frame the script spoils (an error, a result that is not a list) leaves the last good one on. The diagram never animates: its length is the
## game's, and a mod cannot add a tick to a problem.
##
## Teaches: one builder for every way a problem is opened (`DiagramFactory.create`, reached by `ProblemScreen.start` from the game, the practice set, the debug menu and the tests), and a view that is derived from its
## owners each time (the problem, the entry, the mod chain) so that it is the same whichever way it came about.

var _entry := ""
var _step := ProblemFlow.Step.ANSWERING
## The hash of the state the script was last asked about, and the nodes showing its answer.
var _asked_hash := 0
var _stack := ModLayerStack.new()
var _showing_mod := false


func _init() -> void:
	clip_contents = true
	_stack.name = "Drawn"
	add_child(_stack)


func setup(new_problem: ProblemInstance) -> void:
	super.setup(new_problem)
	_asked_hash = 0
	_refresh()


## The entry the player has typed so far changed (the calculator's display or the answer box's text).
func entry_changed(text: String) -> void:
	_entry = text
	_refresh()


## The step of the problem changed.
func step_changed(new_step: ProblemFlow.Step) -> void:
	_step = new_step
	_refresh()


## Asks the script again if what it is told is not what it was last told, and shows its answer; shows the plain picture when there is no script to ask.
func _refresh() -> void:
	var screens := ModHost.problem_screen(type.id)
	var node := ModHost.mod(screens.pack_id) if screens != null else null
	if node == null:
		_show_plain()
		return
	var state := ProblemState.build(problem, _entry, _step)
	if state.hash() == _asked_hash:
		return
	_asked_hash = state.hash()
	var answer := ModLoader.call_mod(node, ModProblems.FUNCTION, [state])
	if not answer["ok"]:                        # (a fault: the frame went wrong, the last one stays)
		return
	var drawn := ModDraw.validate(answer["value"], Packs.pack(screens.pack_id), screens.assets)
	if drawn != null:                           # (not a list: likewise)
		_show_mod(drawn, screens.assets)


## What the mod draws, in `ModLayer` nodes; the plain picture is not drawn while it does.
func _show_mod(drawn: ModDraw.Drawn, assets: ModAssets) -> void:
	_showing_mod = true
	_shown = []
	_stack.show_drawn(drawn, assets)
	queue_redraw()


## The picture the type's data describes (`DiagramBase`'s items).
func _show_plain() -> void:
	if not _showing_mod and _shown == items:
		return
	_showing_mod = false
	_stack.clear()
	_shown = items
	_asked_hash = 0
	queue_redraw()


## What is on screen, as lines, for a test: the layers and their commands (a picture by its file), or the plain picture's items.
func drawn_lines() -> Array[String]:
	var lines: Array[String] = []
	if not _showing_mod:
		lines.append("plain %d items" % items.size())
		return lines
	for layer in _stack.layers():
		lines.append("layer %s" % ("shaded" if layer.material != null else "plain"))
		for command: Array in layer.commands:
			lines.append(ModDraw.describe(command))
	return lines


## The layers (for a test).
func layers() -> Array[ModLayer]:
	return _stack.layers()


## The mod never animates the picture: the lengths of a problem's steps are the game's.
func _schedule_intro() -> DiagramTimeline:
	return DiagramTimeline.new()


func _schedule_success_replay() -> DiagramTimeline:
	return DiagramTimeline.new()
