class_name ModDiagram
extends DiagramBase
## The diagram of a problem type whose screen a MOD draws: a type a pack adds (diagram family `mod`) or an original type a mod opted in to draw by number (`ModProblems`, `DiagramFactory`). The type is plain data like the
## original's 34 (words, records, how an answer is judged); this node only shows the picture on the left monitor, by asking the mod's sandboxed script what to draw: `problem_frame(state)` gets the problem's values and the
## screen's state as plain data (`ProblemState.build`) and returns a draw list that the game checks (`ModDraw.validate`) and draws in the `ModLayer` nodes of a `ModLayerStack` of its own. The script is asked again only when
## what it was told changes (the entry the player has typed so far, the step, and, for a script that `ModSpec.tells_problem_state`, the clock of the build-up or the replay), never per frame, and it decides nothing: the calculator or the answer box, `AnswerChecker`, `ProblemSession` and `ProblemFlow` are the game's,
## so the answer, the tries, the oxygen and every duration are what they are for any type whatever the script returns.
##
## WHAT HAPPENED. The screen tells each presentation event (`ProblemEvents`: started, step, verdict, damage, success, timeout, decided by `ProblemFlow` before this node hears of it) to `told`. A script that is told them (`ModSpec.tells_problem_state`) is
## handed the ones since its last call as the second argument of `problem_frame(state, events)`, on the FRAME AFTER they happened (`_process`), the newest `ProblemEvents.MAX_EVENTS`; the state it is given is as of that call. An event
## of a call that faults, or that comes while no mod runs, is not told again; a script that is bound later is told what happens after it (the state, with the step, the entry and the try, is what it builds from). The plain diagram under
## the layers hears the same events (`DiagramBase.told`).
##
## THE PLAIN PICTURE. Under the mod's layers this node holds the diagram the type's data names, made by `DiagramFactory.plain` (the original's `SonarDiagram`, `PieDiagram` ... for an original type, the generic `items` of
## the diagram spec for a `mod` family): it is what shows when the mod is absent (the chain has no such mod, it was refused or unloaded), quarantined, or has not yet returned a good list, so the problem is always shown and
## always completes. A frame the script spoils (an error, a result that is not a list) leaves the last good one on. The plain diagram is also what plays the build-up and the replay after a right answer: the lengths, the
## ticks and the sounds are the original's whether it is seen or the mod's layers are, and a mod cannot add a tick to a problem.
##
## THE CLOCK (for a script that `ModSpec.tells_problem_state`). While the plain diagram plays the build-up or the replay, the script is asked again as each tick of it goes by and the state's `clock` (`ProblemState.clock`) says which animation, how many
## of its ticks are over, how long it is and the tick the script was last told: all of it the plain diagram's (`animation_name`, `animation_tick`, `animation_length`, from the `animate_to` the step machine's count drives), so a mod draws frame N of a
## length the engine owns, stands still when the machine's time does (a held clock feeds no tick) and cannot lengthen or shorten anything: the flow waits for the plain diagram's timeline, whatever is drawn over it. A script of an older API (before `ModSpec.DRAWS_THE_GAME_API_VERSION`) is told
## the idle clock and asked as before. The animation's last call carries the end tick, so a sound due at the end is not missed; the call after it carries the idle clock. The flow ends an animation a moment before the screen has shown its last tick, so the step that ends it is told on the frame after, with the clock caught up
## (the end tick was told, then the idle clock).
## SOUNDS. A script of the API that has the clock may return `{"draw": [...], "sounds": ["diagram_pop"]}` instead of a draw list (a `draw` that is missing leaves what is on screen, a `sounds` that is missing asks for none): `ModSounds` keeps the names of the chain's sounds
## within its bounds and this node asks for each as the plain diagram does (`sfx_requested`). A mod whose manifest says `own_sounds` has the plain diagram's own sounds (the build-up's, the replay's) left unplayed for as long as it runs and is not quarantined; the lengths are
## the same, since a sound holds nothing up.
##
## A picture the mod names by key is resolved under the skin in use (`ModDraw`); when the skin changes the last good answer is checked and resolved again, so the screen shows what one opened under that skin shows.
##
## Teaches: one builder for every way a problem is opened (`DiagramFactory.create`, reached by `ProblemScreen.start` from the game, the practice set, the debug menu and the tests), a view that is derived from its
## owners each time (the problem, the entry, the mod chain, the skin) so that it is the same whichever way it came about, and a wrapper that forwards what it does not change.

var _entry := ""
var _step := ProblemFlow.Step.ANSWERING
## The events since the script's last call (`ProblemEvents`), told on the next frame.
var _events: Array = []
## The hash of the state the script was last asked about, its last good answer (null: none), and the nodes showing it.
var _asked_hash := 0
var _answer: Variant = null
var _stack := ModLayerStack.new()
var _showing_mod := false
## The diagram the type's data names: the plain picture, and the animation.
var _plain: DiagramBase
## What the script asks for in sounds: the bounds of this screen.
var _sounds := ModSounds.new()
## The animation the script was last told and the tick it was told in it (`since` of the clock).
var _told_animation: StringName = &""
var _told_tick := -1


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


## Something happened (`ProblemEvents`): the plain diagram hears it, and a script that is told events hears it on the next frame.
func told(event: Array) -> void:
	if _plain != null:
		_plain.told(event)
	var screens := ModHost.problem_screen(type.id)
	if screens == null or not screens.spec.tells_problem_state():
		return
	ProblemEvents.push(_events, event)
	set_process(true)


## The frame after an event: the script is asked (with the events), whatever it was last told.
func _process(_delta: float) -> void:
	set_process(false)
	_refresh(true)


## The entry the player has typed so far changed (the calculator's display or the answer box's text).
func entry_changed(text: String) -> void:
	_entry = text
	_refresh()


## The step of the problem changed.
func step_changed(new_step: ProblemFlow.Step) -> void:
	_step = new_step
	if _plain != null and _plain.is_playing() and new_step != ProblemFlow.Step.INTRO and new_step != ProblemFlow.Step.REPLAY:
		set_process(true)                               # (the flow ended the animation before the screen showed its last tick: the script is told on the frame after, when the clock has caught up with the step)
		return
	_refresh()


## Asks the script again if what it is told is not what it was last told, and shows its answer; shows the plain picture when there is no script to ask. The events wait for the frame after they happened: only `with_events` (that frame) hands them over.
func _refresh(with_events := false) -> void:
	var screens := ModHost.problem_screen(type.id)
	var node := ModHost.mod(screens.pack_id) if screens != null else null
	if node == null:
		_events.clear()
		_show_plain()
		return
	var state := ProblemState.build(problem, _entry, _step, _attempt(), _clock(screens))
	var due := with_events and not _events.is_empty()
	if not due and state.hash() == _asked_hash:
		return
	_asked_hash = state.hash()
	var told_events: Array = _events if with_events else []
	var arguments: Array = [state, told_events] if screens.spec.tells_problem_state() else [state]
	if with_events:
		_events = []
	var answer := ModLoader.call_mod(node, ModProblems.FUNCTION, arguments)
	_told_animation = StringName(state["clock"]["animation"])
	_told_tick = int(state["clock"]["tick"]) if _told_animation != &"" else -1
	if not answer["ok"]:                        # (a fault: the frame went wrong, the last one stays)
		return
	var value: Variant = answer["value"]
	if screens.spec.tells_problem_state() and value is Dictionary:        # (`{"draw": ..., "sounds": ...}`)
		var parts: Dictionary = value
		if parts.has("draw"):
			_answer = parts["draw"]
		if is_inside_tree():                              # (the call that builds the screen has nobody to hear it: a sound is for the frames after, the `started` event)
			for sound in _sounds.accept(parts.get("sounds")):
				sfx_requested.emit(sound)
	else:
		_answer = value
	_show_answer(screens)


## Where the animation is, for a script that is told (`ProblemState.clock`): the plain diagram's, which the step machine's ticks drive; the idle clock for one that is not.
func _clock(screens: ModProblems) -> Dictionary:
	if not screens.spec.tells_problem_state() or _plain == null:
		return ProblemState.idle_clock()
	var animation := _plain.animation_name()
	var since := _told_tick if animation == _told_animation and animation != &"" else -1
	return ProblemState.clock(String(animation), _plain.animation_tick(), _plain.animation_length(), since)


## The plain diagram's animation moved a tick or ended, and the script is told (it is asked at once: a tick is never missed, whatever the frame rate).
func _on_animation_moved() -> void:
	if problem == null:
		return
	var screens := ModHost.problem_screen(type.id)
	if screens == null or not screens.spec.tells_problem_state():
		return
	var animation := _plain.animation_name()
	if animation != &"" and animation == _told_animation and _plain.animation_tick() == _told_tick:
		return                                          # (the same tick again: nothing went by)
	_refresh()


## A sound of the plain diagram (the build-up's, the replay's): played unless a running mod that drew this type makes them itself.
func _plain_sound(sound: StringName) -> void:
	if not _plain_is_silenced():
		sfx_requested.emit(sound)


func _plain_sound_stop() -> void:
	if not _plain_is_silenced():
		sfx_stop_requested.emit()


func _plain_is_silenced() -> bool:
	var screens := ModHost.problem_screen(type.id) if type != null else null
	return screens != null and screens.own_sounds and ModHost.mod(screens.pack_id) != null


## The try the player is on (1, or 2 after a miss), from the attempts so far.
func _attempt() -> int:
	return 1 if session == null else mini(session.misses, 1) + 1


## The last good answer of the script, checked and resolved now (a picture by key is the one the skin in use shows), and shown; a list that is not one leaves what is on.
func _show_answer(screens: ModProblems) -> void:
	var drawn := ModDraw.validate(_answer, Packs.pack(screens.pack_id), screens.assets)
	if drawn != null:
		_showing_mod = true
		_plain.visible = false
		_stack.set_phase(float(maxi(_told_tick, 0)))              # (the tick of the animation the script was told; drawn when something changes, not every frame: a shader that moves by itself uses `TIME`)
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
	_plain.sfx_requested.connect(_plain_sound)
	_plain.sfx_stop_requested.connect(_plain_sound_stop)
	_plain.animation_advanced.connect(_on_animation_moved)
	_plain.animation_finished.connect(_on_animation_finished)
	items = _plain.items


## The animation is over (or skipped): the script is told the idle clock, then whoever waits for the end hears it.
func _on_animation_finished() -> void:
	_on_animation_moved()
	animation_finished.emit()


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


## The plain diagram's clock (`animation_name`, `animation_tick`, `animation_length`): the position every drawing of the animation goes by.
func animation_name() -> StringName:
	return _plain.animation_name()


func animation_tick() -> int:
	return _plain.animation_tick()


func animation_length() -> int:
	return _plain.animation_length()


## The bounds on the sounds this screen's mod asks for (for a test).
func sounds() -> ModSounds:
	return _sounds


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
