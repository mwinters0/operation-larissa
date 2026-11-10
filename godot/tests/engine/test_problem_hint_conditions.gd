class_name TestProblemHintConditions
extends GdUnitTestSuite
## Teaches: testing a rule of the original by calling the one function that holds it. `DoMathProblem` (0x423629) shows
## the one-time help dialogs after the prompt: hint 3 ("type your answer") when the PLAYER's calculator option is off,
## hint 4 (calculator) when it is on, hint 6 (fractions) at EduLevel 1 or 3; none for the lock and the ballast panels.

const GAME_SCENE := "res://src/gameplay/game.tscn"
const ROSTER := "user://test_hint_cond_roster.json"
const HALL := "user://test_hint_cond_hall.json"

var _old_roster: String
var _old_hall: String
var _old_players: Array[PlayerProfile]


func before_test() -> void:
	_old_roster = SaveStore.roster_path
	_old_hall = SaveStore.hall_path
	_old_players = SaveStore.players.duplicate()
	SaveStore.roster_path = ROSTER
	SaveStore.hall_path = HALL
	SaveStore.players = []
	SaveStore.hall = HallOfFame.new()
	SectorWorld.skip_animations = true
	SceneRouter.dry_run = true
	GameState.profile = SaveStore.add_player("Hints", 0)
	GameClock.paused = false


func after_test() -> void:
	SaveStore.roster_path = _old_roster
	SaveStore.hall_path = _old_hall
	SaveStore.players = _old_players
	SaveStore.hall = HallOfFame.new()
	SectorWorld.skip_animations = false
	SceneRouter.dry_run = false
	GameState.profile = null
	GameClock.paused = false
	GameState.hints.reset()
	GameState.reset()
	for path in [ROSTER, HALL]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Opens the game with the given option and level, asks for the hints of `type_id` and returns which of 3, 4, 6 were shown.
func _hints_shown(type_id: int, calculator_on: bool, edu_level: int) -> Array:
	var game := scene_runner(GAME_SCENE).scene() as Game
	await await_idle_frame()
	GameState.hints.reset()
	game.profile.calculator_on = calculator_on
	GameState.edu_level = edu_level
	var level := 0
	while ProblemFactory.make(type_id, level) == null:
		level += 1
	game.flow.show_problem_hints(ProblemFactory.make(type_id, level))
	var shown := []
	for id in [HintSystem.TYPE_ANSWER, HintSystem.CALCULATOR, HintSystem.FRACTIONS]:
		if GameState.hints.has_been_shown(id):
			shown.append(id)
	return shown


func test_hint_3_or_4_follows_the_players_calculator_option() -> void:
	assert_array(await _hints_shown(6, false, 0)).is_equal([HintSystem.TYPE_ANSWER])
	assert_array(await _hints_shown(6, true, 0)).is_equal([HintSystem.CALCULATOR])


func test_fractions_hint_at_edu_level_1_and_3_only() -> void:
	assert_array(await _hints_shown(6, true, 1)).is_equal([HintSystem.CALCULATOR, HintSystem.FRACTIONS])
	assert_array(await _hints_shown(6, true, 3)).is_equal([HintSystem.CALCULATOR, HintSystem.FRACTIONS])
	assert_array(await _hints_shown(6, true, 2)).is_equal([HintSystem.CALCULATOR])


func test_no_problem_hints_for_the_lock_and_the_ballast_panels() -> void:
	assert_array(await _hints_shown(0, true, 1)).is_empty()
	assert_array(await _hints_shown(28, true, 1)).is_empty()
	assert_array(await _hints_shown(29, false, 3)).is_empty()
