class_name TestPracticeMode
extends GdUnitTestSuite
## Teaches: testing the rules behind a screen first (the set, the score), then the screen itself with a
## scripted player. The expected numbers come straight from the decompiled `do_math_practice`.


func test_the_mental_set_is_five_locks_which_make_ten_problems() -> void:
	var order := PracticeSet.build(PracticeSet.Kind.MENTAL, 1)
	assert_array(order).is_equal(PackedInt32Array([0, 0, 0, 0, 0]))
	assert_int(PracticeSet.problem_count(order)).is_equal(10)


func test_the_five_problem_set_draws_available_types_and_may_repeat() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for level in 4:
		for round in 20:
			var order := PracticeSet.build(PracticeSet.Kind.FIVE, level, rng)
			assert_int(order.size()).is_equal(5)
			for type_id in order:
				assert_int(type_id).is_between(1, 33)
				assert_bool(PracticeSet.is_available(type_id, level)).is_true()
	# a draw may repeat a type: with one available type the five picks are all the same
	var seen := {}
	for round in 40:
		for type_id in PracticeSet.build(PracticeSet.Kind.FIVE, 0, rng):
			seen[type_id] = true
	assert_int(seen.size()).is_less(PracticeSet.available_types(0).size() + 1)


func test_the_all_set_lists_every_type_of_the_level_in_order() -> void:
	# Dev has records for the types 1-33 at every level except type 3 at level 2 (`dev_problems.NO_RECORDS`): 33, 33, 32, 33 types
	var expected := [33, 33, 32, 33]
	for level in 4:
		var order := PracticeSet.build(PracticeSet.Kind.ALL, level)
		assert_int(order.size()).is_equal(expected[level])
		assert_bool(order.has(0)).is_false()                      # the lock is Mental Math only
		for i in range(1, order.size()):
			assert_int(order[i]).is_greater(order[i - 1])
		for type_id in order:
			assert_int(Catalog.problem_type(type_id).record_count(level)).is_greater(0)


func test_the_level_filter_follows_the_stored_record_counts() -> void:
	assert_bool(PracticeSet.is_available(3, 2)).is_false()        # dev's sonar has no level-2 problems
	assert_bool(PracticeSet.is_available(3, 1)).is_true()
	assert_bool(PracticeSet.is_available(3, 3)).is_true()
	assert_bool(PracticeSet.is_available(PracticeSet.LOCK_TYPE, 0)).is_true()


func test_the_score_counts_first_and_second_tries() -> void:
	var score := PracticeScore.new()
	var problem := ProblemFactory.make(3, 0, null, 0)
	var first := ProblemSession.new(problem)
	first.finished = true
	first.solved = true
	var second := ProblemSession.new(problem)
	second.misses = 1
	second.finished = true
	second.solved = true
	var lost := ProblemSession.new(problem)
	lost.misses = 2
	lost.finished = true
	for session in [first, second, lost]:
		score.record_session(session)
	assert_int(score.problems).is_equal(3)
	assert_int(score.first_try).is_equal(1)
	assert_int(score.second_try).is_equal(1)
	assert_int(score.correct()).is_equal(2)
	score.record_lock_stage(true)
	score.record_lock_stage(false)
	assert_int(score.problems).is_equal(5)
	assert_int(score.correct()).is_equal(3)
	score.reset()
	assert_int(score.problems).is_equal(0)


func test_practice_costs_no_oxygen() -> void:
	GameState.reset()
	var screen: ProblemScreen = auto_free(load("res://src/problems/problem_screen.tscn").instantiate())
	screen.practice = true
	add_child(screen)
	screen.start(ProblemFactory.make(3, 0, null, 0))
	if screen.step() == ProblemScreen.Step.INTRO:
		screen.diagram.skip_animation()                            # (the radar sweeps first)
	var air := GameState.oxygen()
	screen.submit_answer(NumberValue.parse("9999"))                # wrong
	screen.press_continue()                                        # ("Error!" over)
	screen.submit_answer(NumberValue.parse("9998"))                # wrong again
	screen.press_continue()                                        # ("Error!" over: practice has no note, the solution follows)
	assert_int(GameState.oxygen()).is_equal(air)
	assert_int(screen.step()).is_equal(ProblemScreen.Step.SOLUTION)
	screen.close()
	GameState.reset()


func test_the_practice_scene_plays_a_mental_set_and_scores_the_locks() -> void:
	SceneRouter.dry_run = true
	var practice: PracticeMode = auto_free(load("res://src/problems/practice_mode.tscn").instantiate())
	add_child(practice)
	await await_idle_frame()
	assert_int(practice.overlay.get_child_count()).is_equal(1)       # the setup dialog
	var dialog := practice.overlay.get_child(0) as PracticeSetupDialog
	dialog.set_values(PracticeSet.Kind.MENTAL, 2, true)
	dialog.accepted.emit(PracticeSet.Kind.MENTAL, 2, true)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(practice.kind).is_equal(PracticeSet.Kind.MENTAL)
	assert_int(practice.level).is_equal(2)
	var screen: ProblemScreen = practice.host.get_child(0)
	assert_bool(screen.practice).is_true()
	screen.lock_stage_scored.emit(0, true)
	screen.lock_stage_scored.emit(1, false)
	assert_int(practice.score.problems).is_equal(2)
	assert_int(practice.score.correct()).is_equal(1)
	assert_str(practice._score_names[1].text).is_equal(Catalog.text(&"score_correct"))
	practice._left = true
	SceneRouter.dry_run = false


# --- G23: the score accumulates across sets (do_math_practice 0x42d817) --------------------------------

## Opens the practice scene with the setup dialog answered for `kind` (level 0, calculator on).
func _start_practice(kind: PracticeSet.Kind, seed_value: int = 0) -> PracticeMode:
	SceneRouter.dry_run = true
	var practice: PracticeMode = auto_free(load("res://src/problems/practice_mode.tscn").instantiate())
	practice.quits_program = false
	add_child(practice)
	await await_idle_frame()
	if seed_value != 0:
		practice.rng.seed = seed_value                                          # (a fixed set of problems)
	_answer_setup(practice, kind)
	await await_idle_frame()
	await await_idle_frame()
	return practice


func _answer_setup(practice: PracticeMode, kind: PracticeSet.Kind) -> void:
	var dialog := practice.overlay.get_child(0) as PracticeSetupDialog
	dialog.accepted.emit(kind, 0, true)


## Ends the problem on screen without an answer (it still counts as a problem) and waits for the next screen.
func _skip_problem(practice: PracticeMode) -> void:
	var old := practice._screen
	old.close()
	for i in 20:
		await await_idle_frame()
		if practice._screen != old and practice._screen != null:
			return
		if practice.messages.is_open() or practice.overlay.get_child_count() > 0:
			return


func test_the_score_adds_up_over_sets_of_the_same_sort_and_resets_when_the_kind_switches_to_mental_math_or_back() -> void:
	var practice := await _start_practice(PracticeSet.Kind.FIVE)
	for i in 5:
		await _skip_problem(practice)
	assert_int(practice.score.problems).is_equal(5)
	assert_bool(practice.messages.is_open()).is_true()                       # "practice another set?"
	practice.messages.close_current(0)                                       # Yes
	await await_idle_frame()
	_answer_setup(practice, PracticeSet.Kind.FIVE)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(practice.score.problems).is_equal(5)                           # NOT zeroed: the second set adds to the first
	for i in 3:
		await _skip_problem(practice)
	assert_int(practice.score.problems).is_equal(8)
	# "5 Math Problems" -> "All Math Problems": both are ordinary sets, the counters stay
	practice._on_customization_requested()
	await await_idle_frame()
	_answer_setup(practice, PracticeSet.Kind.ALL)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(practice.score.problems).is_equal(8)
	# ... but Mental Math switches the panel to its own two counters, which start from zero
	practice._on_customization_requested()
	await await_idle_frame()
	_answer_setup(practice, PracticeSet.Kind.MENTAL)
	await await_idle_frame()
	await await_idle_frame()
	assert_int(practice.score.problems).is_equal(0)
	practice._left = true
	SceneRouter.dry_run = false


func test_the_score_panel_is_wide_only_around_the_lock_the_ballast_panel_and_type_29() -> void:
	assert_array(PracticeMode.WIDE_PANEL_TYPES).is_equal([0, 28, 29])
	var practice := await _start_practice(PracticeSet.Kind.ALL)              # every type of the level, in order
	var widths := {}
	for i in 40:
		var screen := practice._screen
		if screen == null:
			break
		widths[screen.session.instance.type.id] = practice.score_panel.size.x
		await _skip_problem(practice)
		if practice.messages.is_open():
			break
	for type_id in widths:
		var expected := 608.0 if type_id in PracticeMode.WIDE_PANEL_TYPES else 316.0
		assert_float(widths[type_id]).is_equal(expected)
	assert_bool(widths.has(28) or widths.has(29)).is_true()
	assert_float(practice.score_panel.size.x).is_equal(316.0)                # narrowed again after the last problem
	practice._left = true
	SceneRouter.dry_run = false


# --- G33: Escape during a problem asks to exit the program --------------------------------------------

func _escape(practice: PracticeMode) -> void:
	practice.ask_to_exit_from_problem()
	await await_idle_frame()


## The text of the exit question that is up (11130 = `SaveAndExit`, 11134 = `JustExit`), or 0 when none.
func _exit_question(practice: PracticeMode) -> int:
	if not practice.messages.is_open():
		return 0
	var strings := Catalog.texts("ui_strings")
	assert_str(practice.messages.current.title).is_equal(strings.text(11132))
	assert_int(practice.messages.current.default_button).is_equal(1)         # starts on No
	for id in [11130, 11134]:
		if practice.messages.current.body == strings.text(id).replace("\r", "\n"):
			return id
	return -1


func _ready_for_answer(practice: PracticeMode) -> ProblemScreen:
	var screen := practice._screen
	if screen.step() == ProblemScreen.Step.INTRO:
		screen.diagram.skip_animation()
	await await_idle_frame()
	return screen


func test_escape_from_the_answer_entry_is_save_and_exit_and_yes_quits() -> void:
	var practice := await _start_practice(PracticeSet.Kind.ALL)             # type 1 first: a number is typed
	var screen := await _ready_for_answer(practice)
	assert_int(screen.session.instance.type.id).is_equal(1)
	var quit_seen := [0]
	practice.quit_requested.connect(func() -> void: quit_seen[0] += 1)
	SceneRouter.last_path = ""                                               # (an earlier test of any suite may have left the scene it went to)
	await _escape(practice)
	assert_int(_exit_question(practice)).is_equal(11130)                      # `SaveAndExit`
	practice.messages.close_current(1)                                       # No: the problem goes on
	await await_idle_frame()
	assert_int(quit_seen[0]).is_equal(0)
	assert_str(SceneRouter.last_path).is_empty()                             # (not "return to sign-in" either)
	await _escape(practice)
	practice.messages.close_current(0)                                       # Yes
	await await_idle_frame()
	assert_int(quit_seen[0]).is_equal(1)
	practice._left = true
	SceneRouter.dry_run = false


func test_escape_on_the_ballast_panel_and_the_lock_is_just_exit() -> void:
	var practice := await _start_practice(PracticeSet.Kind.ALL)
	var screen := practice._screen
	for i in 40:
		if screen.session.instance.type.id == 28:
			break
		await _skip_problem(practice)
		screen = practice._screen
	assert_int(screen.session.instance.type.id).is_equal(28)
	screen = await _ready_for_answer(practice)
	assert_object(screen.ballast).is_not_null()
	await _escape(practice)
	assert_int(_exit_question(practice)).is_equal(11134)                      # `JustExit`
	practice.messages.close_current(1)
	practice._left = true
	var mental := await _start_practice(PracticeSet.Kind.MENTAL)
	assert_object(mental._screen.lock).is_not_null()
	await _escape(mental)
	assert_int(_exit_question(mental)).is_equal(11134)
	mental.messages.close_current(1)
	mental._left = true
	SceneRouter.dry_run = false


func test_escape_during_a_message_or_the_solution_is_just_exit() -> void:
	var practice := await _start_practice(PracticeSet.Kind.ALL)
	var screen := practice._screen
	var strings := Catalog.texts("ui_strings")
	screen._flow.step = ProblemScreen.Step.SOLUTION                       # (the worked solution is on screen)
	await _escape(practice)
	assert_str(practice.messages.current.body).is_equal(strings.text(11134).replace("\r", "\n"))
	practice.messages.close_current(1)
	screen._flow.step = ProblemScreen.Step.MESSAGE
	await _escape(practice)
	assert_str(practice.messages.current.body).is_equal(strings.text(11134).replace("\r", "\n"))
	practice.messages.close_current(1)
	practice._left = true
	SceneRouter.dry_run = false


## A typed key, through the viewport as the player's keyboard sends it.
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


func test_under_the_exit_question_the_problem_hears_no_key_and_the_arrows_stay_in_the_question() -> void:
	var practice := await _start_practice(PracticeSet.Kind.ALL)             # type 1 first: a number is typed on the calculator
	var screen := await _ready_for_answer(practice)
	assert_bool(screen.calculator.visible).is_true()
	var before := screen.calculator.model.display_text()
	_type(KEY_ESCAPE)
	await await_idle_frame()
	assert_bool(practice.messages.is_open()).is_true()
	for key in [KEY_7, KEY_BACKSPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_TAB]:
		_type(key, "7" if key == KEY_7 else "")
		await await_idle_frame()
		var owner := practice.get_viewport().gui_get_focus_owner()
		assert_bool(practice.message_view.is_ancestor_of(owner)).override_failure_message("key %s took the focus to %s" % [key, owner]).is_true()
	for i in 10:
		await await_idle_frame()
	assert_str(screen.calculator.model.display_text()).is_equal(before)
	_type(KEY_ESCAPE)                                                        # No: back to the problem
	await await_idle_frame()
	assert_bool(practice.messages.is_open()).is_false()
	_type(KEY_7, "7")
	for i in 10:
		await await_idle_frame()
	assert_str(screen.calculator.model.display_text()).is_not_equal(before)  # the calculator hears the keys again
	practice._left = true
	SceneRouter.dry_run = false


# --- G37: a problem aborted by Options > Customization is not counted (deliberate deviation) -----------

## Deliberate deviation from the original: `do_math_practice` (0x42d817) increments `PracticeProblemCount` (0x449f3c) at 0x42d9e3
## after every `DoMathProblem` return, so the problem ended on screen by Options > Customization is counted in "Number of
## problems"; the port does not count it.
func test_a_problem_aborted_by_customization_is_not_counted_deliberate_deviation_g37() -> void:
	var practice := await _start_practice(PracticeSet.Kind.FIVE)
	await _skip_problem(practice)
	assert_int(practice.score.problems).is_equal(1)                           # a finished problem counts
	assert_object(practice._screen).is_not_null()                            # the second problem is on screen
	practice._on_customization_requested()
	await await_idle_frame()
	_answer_setup(practice, PracticeSet.Kind.FIVE)                           # Done: the problem on screen is dropped
	await await_idle_frame()
	await await_idle_frame()
	assert_int(practice.score.problems).is_equal(1)                           # (the original would show 2)
	assert_int(practice.score.correct()).is_equal(0)
	practice._left = true
	SceneRouter.dry_run = false


# --- G39: Esc > Yes in Math Practice leaves the roster alone (deliberate deviation) ---------------------

## Deliberate deviation from the original: after Yes `SaveAndExit` (0x42ba05) calls `SaveRosterData` (0x42e11d), which writes
## the blanked `CurrentPlayer` over the roster slot of the last signed-in player; the port writes nothing.
func test_escape_yes_in_practice_after_a_sign_in_leaves_the_roster_unchanged_deliberate_deviation_g39() -> void:
	var old_roster := SaveStore.roster_path
	var old_players: Array[PlayerProfile] = SaveStore.players.duplicate()
	SaveStore.roster_path = "user://test_practice_roster.json"
	SaveStore.players = []
	var player := SaveStore.add_player("Signed", 0)                           # (the player who signed in before Math Practice)
	GameState.profile = player
	var before := FileAccess.get_file_as_string(SaveStore.roster_path)
	var practice := await _start_practice(PracticeSet.Kind.ALL)               # type 1 first: Esc asks `SaveAndExit`
	await _ready_for_answer(practice)
	await _escape(practice)
	assert_int(_exit_question(practice)).is_equal(11130)
	var quit_seen := [0]
	practice.quit_requested.connect(func() -> void: quit_seen[0] += 1)
	practice.messages.close_current(0)                                       # Yes
	await await_idle_frame()
	assert_int(quit_seen[0]).is_equal(1)
	assert_int(SaveStore.players.size()).is_equal(1)
	assert_str(SaveStore.players[0].name).is_equal("Signed")
	assert_str(FileAccess.get_file_as_string(SaveStore.roster_path)).is_equal(before)
	practice._left = true
	SceneRouter.dry_run = false
	DirAccess.remove_absolute(SaveStore.roster_path)
	SaveStore.roster_path = old_roster
	SaveStore.players = old_players
	GameState.profile = null
