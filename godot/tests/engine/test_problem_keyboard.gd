extends GdUnitTestSuite
## Every problem type of the dev pack, at every level, answered from the keyboard in Math Practice: the keys reach the problem's
## input (the calculator, the typed answer or the ballast panel), and while the exit question is up they reach nothing below it and
## the focus stays in the question. A playtest of the input of every type, through the viewport as the player's keys arrive.
##
## Teaches: one loop over the content instead of one test per type, so a new problem type is covered the day it is added.

const PRACTICE := "res://src/problems/practice_mode.tscn"


func after_test() -> void:
	SceneRouter.dry_run = false


func _type(key: Key, character: String = "") -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	if not character.is_empty():
		event.unicode = character.unicode_at(0)
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for i in count:
		await await_idle_frame()


## Waits until a calculator key has stopped flashing (a key typed during the flash waits for its end).
func _settle(screen: ProblemScreen) -> void:
	await _frames(2)
	for i in 300:
		if not screen.calculator.is_flashing():
			return
		await await_idle_frame()


## What the player sees of the answer so far: the calculator's display, the typed answer, or the ballast panel's cursor.
func _input_state(screen: ProblemScreen) -> String:
	if screen.ballast != null:
		return "cursor %d" % screen.ballast.cursor
	if screen.calculator.visible:
		return screen.calculator.model.display_text()
	return screen.answer_box.text


## A key that changes `_input_state` on this screen: a digit, or Down on the ballast panel.
func _probe(screen: ProblemScreen) -> void:
	if screen.ballast != null:
		_type(KEY_DOWN)
	else:
		_type(KEY_7, "7")


func _start(level: int, calculator: bool) -> PracticeMode:
	SceneRouter.dry_run = true
	var practice: PracticeMode = auto_free(load(PRACTICE).instantiate())
	practice.quits_program = false
	add_child(practice)
	await await_idle_frame()
	(practice.overlay.get_child(0) as PracticeSetupDialog).accepted.emit(PracticeSet.Kind.ALL, level, calculator)
	await _frames(2)
	return practice


func _check_every_type(level: int, calculator: bool) -> void:
	var practice := await _start(level, calculator)
	var seen := 0
	for problem in PracticeSet.build(PracticeSet.Kind.ALL, level):
		var screen := practice._screen
		assert_object(screen).override_failure_message("level %d: no screen for the problem %d of the set" % [level, seen]).is_not_null()
		var type_id := screen.session.instance.type.id
		var where := "type %d, level %d, calculator %s" % [type_id, level, calculator]
		if screen.step() == ProblemScreen.Step.INTRO:
			screen.diagram.skip_animation()
		await _frames(2)
		assert_int(screen.step()).override_failure_message(where + ": not answering").is_equal(ProblemScreen.Step.ANSWERING)
		var owner := practice.get_viewport().gui_get_focus_owner()
		assert_bool(owner == null or not practice.host.is_ancestor_of(owner)) \
				.override_failure_message(where + ": %s holds the focus and would eat the keys" % owner).is_true()
		# the keys reach the problem
		var before := _input_state(screen)
		_probe(screen)
		await _settle(screen)
		var typed := _input_state(screen)
		assert_str(typed).override_failure_message(where + ": the key did not reach the problem").is_not_equal(before)
		# ... and not while the exit question is up
		_type(KEY_ESCAPE)
		await await_idle_frame()
		assert_bool(practice.messages.is_open()).override_failure_message(where + ": Escape asked nothing").is_true()
		for key in [KEY_UP, KEY_TAB]:
			_type(key)
			await await_idle_frame()
		_probe(screen)
		await _settle(screen)
		owner = practice.get_viewport().gui_get_focus_owner()
		assert_bool(practice.message_view.is_ancestor_of(owner)).override_failure_message(where + ": the focus left the question for %s" % owner).is_true()
		assert_str(_input_state(screen)).override_failure_message(where + ": a key reached the problem under the question").is_equal(typed)
		_type(KEY_ESCAPE)                                                      # No
		await await_idle_frame()
		assert_bool(practice.messages.is_open()).is_false()
		if screen.ballast == null:
			_type(KEY_8, "8")
		else:
			_probe(screen)
		await _settle(screen)
		assert_str(_input_state(screen)).override_failure_message(where + ": the keys did not come back after the question (%s -> %s)" % [typed, _input_state(screen)]).is_not_equal(typed)
		seen += 1
		screen.close()
		for i in 20:
			await await_idle_frame()
			if practice._screen != screen:
				break
	assert_int(seen).is_greater(0)
	practice._left = true


func test_every_type_at_level_1_with_the_calculator() -> void:
	await _check_every_type(0, true)


func test_every_type_at_level_2_with_the_calculator() -> void:
	await _check_every_type(1, true)


func test_every_type_at_level_3_with_the_calculator() -> void:
	await _check_every_type(2, true)


func test_every_type_at_level_4_with_the_calculator() -> void:
	await _check_every_type(3, true)


func test_every_type_at_level_1_with_the_typed_answer() -> void:
	await _check_every_type(0, false)
