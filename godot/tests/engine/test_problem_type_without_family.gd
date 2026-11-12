class_name TestProblemTypeWithoutFamily
extends GdUnitTestSuite
## A problem type of a pack that names no diagram `family` (or one the game does not draw) still opens, with the plain list of items its data holds for a picture, and the game says so once through the `TroubleLog`. The screen takes the
## clock and the lost tanks when it is started (`ProblemScreen.start`), after the diagram is made; a diagram that could not be made stopped `start` half way (an error out of `DiagramFactory.create`), so the screen came up with no
## picture, no input and the world below it waiting for a `finished` that no one could cause.
##
## Teaches: a lookup in data a pack may not have filled in (`Dictionary.get` with the answer the game falls back to) at the one place that reads it (`DiagramFactory.family_of`), and the warning that goes with the fallback.

const SCREEN_SCENE := "res://src/problems/problem_screen.tscn"


func before_test() -> void:
	GameState.reset()                                             # (a run begins: the session's `TroubleLog` is a new one)
	GameClock.paused = false


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


## Type 6 (the sounder) at level 2 with its `diagram` as `diagram` says.
func _problem_with(diagram: Dictionary) -> ProblemInstance:
	var type := Catalog.problem_type(6).duplicate(true) as ProblemType
	type.diagram = diagram
	return ProblemInstance.build(type, 2, 0)


func test_a_diagram_that_names_no_family_is_the_plain_list_of_items_and_is_told_once() -> void:
	var problem := _problem_with({"items": []})
	for i in 3:
		auto_free(DiagramFactory.create(problem))
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("problem type 6").contains("names no family").contains("plain list of items")


func test_a_family_the_game_does_not_draw_is_named_in_the_warning() -> void:
	auto_free(DiagramFactory.create(_problem_with({"family": "hologram", "items": []})))
	assert_array(TroubleLog.session.told).has_size(1)
	assert_str(TroubleLog.session.told[0]).contains("problem type 6").contains("family 'hologram' is not one the game draws")


func test_the_screen_of_such_a_type_is_up_with_its_input_and_gives_the_clock_back() -> void:
	var screen := scene_runner(SCREEN_SCENE).scene() as ProblemScreen
	var finished: Array[ProblemSession] = []
	screen.finished.connect(func(session: ProblemSession) -> void: finished.append(session))
	var problem := _problem_with({})
	var holds := GameClock.holds
	screen.start(problem)
	assert_object(screen.diagram).is_not_null()
	assert_int(GameClock.holds).is_equal(holds + 1)
	screen.diagram.skip_animation()
	assert_bool(screen.is_answering()).is_true()
	assert_bool(screen.calculator.visible or screen.answer_box.visible).is_true()
	screen.close()
	assert_int(finished.size()).is_equal(1)
	assert_int(GameClock.holds).is_equal(holds)
