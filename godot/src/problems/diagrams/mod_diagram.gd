class_name ModDiagram
extends DiagramBase
## The diagram of a problem type whose screen a MOD draws: a type a pack adds (diagram family `mod`) or an original type a mod opted in to draw by number (`ModProblems`, `DiagramFactory`). The type is plain data like the
## original's 34 (words, records, how an answer is judged); this node only shows the picture on the left monitor, by asking the mod's sandboxed script what to draw: `problem_frame(state)` gets the problem's values and the
## screen's state as plain data (`ProblemState.build`) and returns a draw list that the game checks (`ModDraw.validate`) and draws in the `ModLayer` nodes of a `ModLayerStack` of its own. The script is asked again only when
## what it was told changes (the entry the player has typed so far, the step), never per frame, and it decides nothing: the calculator or the answer box, `AnswerChecker`, `ProblemSession` and `ProblemFlow` are the game's,
## so the answer, the tries, the oxygen and every duration are what they are for any type whatever the script returns.
##
## THE PLAIN PICTURE. Under the mod's layers this node holds the diagram the type's data names, made by `DiagramFactory.plain` (the original's `SonarDiagram`, `PieDiagram` ... for an original type, the generic `items` of
## the diagram spec for a `mod` family): it is what shows when the mod is absent (the chain has no such mod, it was refused or unloaded), quarantined, or has not yet returned a good list, so the problem is always shown and
## always completes. A frame the script spoils (an error, a result that is not a list) leaves the last good one on. The plain diagram is also what plays the build-up and the replay after a right answer: the lengths, the
## ticks and the sounds are the original's whether it is seen or the mod's layers are, and a mod cannot add a tick to a problem.
##
## A picture the mod names by key is resolved under the skin in use (`ModDraw`); when the skin changes the last good answer is checked and resolved again, so the screen shows what one opened under that skin shows.
##
## Teaches: one builder for every way a problem is opened (`DiagramFactory.create`, reached by `ProblemScreen.start` from the game, the practice set, the debug menu and the tests), a view that is derived from its
## owners each time (the problem, the entry, the mod chain, the skin) so that it is the same whichever way it came about, and a wrapper that forwards what it does not change.

var _entry := ""
var _step := ProblemFlow.Step.ANSWERING
## The hash of the state the script was last asked about, its last good answer (null: none), and the nodes showing it.
var _asked_hash := 0
var _answer: Variant = null
var _stack := ModLayerStack.new()
var _showing_mod := false
## The diagram the type's data names: the plain picture, and the animation.
var _plain: DiagramBase


func _init() -> void:
	clip_contents = true
	_stack.name = "Drawn"
	add_child(_stack)


func _enter_tree() -> void:
	if not SkinChoice.events.changed.is_connected(_on_skin_changed):
		SkinChoice.events.changed.connect(_on_skin_changed)


func _exit_tree() -> void:
	if SkinChoice.events.changed.is_connected(_on_skin_changed):
		SkinChoice.events.changed.disconnect(_on_skin_changed)


func setup(new_problem: ProblemInstance) -> void:
	super.setup(new_problem)
	_asked_hash = 0
	_refresh()


## The plain diagram of the problem (`DiagramFactory.plain`) is the picture and the animation; this node draws nothing itself.
func _build() -> void:
	_make_plain()


func _draw() -> void:
	pass


## The plain diagram's timelines are the ones that count (`intro_length`, `success_replay_length`): this node plays none of its own.
func _schedule_intro() -> DiagramTimeline:
	return DiagramTimeline.new()


func _schedule_success_replay() -> DiagramTimeline:
	return DiagramTimeline.new()


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
	_answer = answer["value"]
	_show_answer(screens)


## The last good answer of the script, checked and resolved now (a picture by key is the one the skin in use shows), and shown; a list that is not one leaves what is on.
func _show_answer(screens: ModProblems) -> void:
	var drawn := ModDraw.validate(_answer, Packs.pack(screens.pack_id), screens.assets)
	if drawn != null:
		_showing_mod = true
		_plain.visible = false
		_stack.show_drawn(drawn, screens.assets)


## The skin in use changed: what the mod drew is resolved under the new skin without asking the script, and the plain picture is made again (unless it is playing: its animation ends in the picture of the skin it began under).
func _on_skin_changed(_skin: GameSkin) -> void:
	if problem == null:
		return
	if not _plain.is_playing():
		_make_plain()
		_plain.visible = not _showing_mod
	var screens := ModHost.problem_screen(type.id)
	if _showing_mod and screens != null:
		_show_answer(screens)


## The picture the type's data describes, drawn by the plain diagram.
func _show_plain() -> void:
	_answer = null
	_asked_hash = 0
	if not _showing_mod:
		return
	_showing_mod = false
	_stack.clear()
	_plain.visible = true


## Makes the plain diagram of the problem (the only one: a second `setup` or a new skin replaces it); its sounds and its end are this node's.
func _make_plain() -> void:
	if _plain != null:
		remove_child(_plain)
		_plain.queue_free()
	_plain = DiagramFactory.plain(problem)
	add_child(_plain)
	move_child(_plain, 0)
	_plain.sfx_requested.connect(sfx_requested.emit)
	_plain.sfx_stop_requested.connect(sfx_stop_requested.emit)
	_plain.animation_finished.connect(animation_finished.emit)
	items = _plain.items


## What is on screen, as lines, for a test: the layers and their commands (a picture by its file), or the plain picture's items.
func drawn_lines() -> Array[String]:
	var lines: Array[String] = []
	if not _showing_mod:
		lines.append("plain %d items" % _plain.items.size())
		return lines
	for layer in _stack.layers():
		lines.append("layer %s" % ("shaded" if layer.material != null else "plain"))
		for command: Array in layer.commands:
			lines.append(ModDraw.describe(command))
	return lines


## The layers (for a test).
func layers() -> Array[ModLayer]:
	return _stack.layers()


## The plain diagram (for a test).
func plain() -> DiagramBase:
	return _plain


# --- the animation is the plain diagram's: the mod never changes a length ---------------------------------------------------

func intro_length() -> int:
	return _plain.intro_length()


func success_replay_length() -> int:
	return _plain.success_replay_length()


func begin_intro() -> void:
	_plain.begin_intro()


func begin_success_replay() -> void:
	_plain.begin_success_replay()


func begin_animation(timeline: DiagramTimeline, keeps_last_step: bool) -> void:
	_plain.begin_animation(timeline, keeps_last_step)


func animate_to(tick: int) -> void:
	_plain.animate_to(tick)


func play_intro() -> void:
	await _plain.play_intro()


func play_success_replay() -> void:
	await _plain.play_success_replay()


func has_intro() -> bool:
	return _plain.has_intro()


func has_success_replay() -> bool:
	return _plain.has_success_replay()


func is_playing() -> bool:
	return _plain.is_playing()


func skip_animation() -> void:
	_plain.skip_animation()
