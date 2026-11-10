class_name FakeFlowView
extends RefCounted
## The view of the flow: it writes down every request in `log` (one line each) and answers at once, unless a request is `hold`-ed:
## then the call stays open - like a screen the player has not left yet - until `release` is called.

signal released
var log: Array
var held: Array[StringName] = []
## What the problem screen reports: the oxygen code of the session it hands back.
var oxygen_code: int = OxygenModel.OK
var run: Object


func _init(shared_log: Array, game_run: Object) -> void:
	log = shared_log
	run = game_run


func hold(request: StringName) -> void:
	held.append(request)


func release(request: StringName) -> void:
	held.erase(request)
	released.emit()


func _wait(request: StringName) -> void:
	while held.has(request):
		await released


func show_pieces_missing(missing: int) -> void:
	log.append("pieces missing %d (ship light %s)" % [missing, run.ship_light])
	await _wait(&"pieces_missing")


func show_supply_message(completed_sector: int) -> void:
	log.append("supply message %d" % completed_sector)
	await _wait(&"supply_message")


func show_problem(problem: ProblemInstance, calculator_allowed: bool, after_prompt: Callable) -> ProblemSession:
	log.append("problem %d (calculator %s)" % [problem.type.id, calculator_allowed])
	after_prompt.call()                                  # (the screen calls it when the prompt is on screen)
	await _wait(&"problem")
	var session := ProblemSession.new(problem)
	session.oxygen_code = oxygen_code
	session.finished = true
	session.solved = oxygen_code == OxygenModel.OK
	return session


func show_closing(campaign: Campaign, sub_at: Vector2i, sub_cell: int) -> void:
	log.append("closing %s at %s cell %d" % [campaign.closing_scene, sub_at, sub_cell])
	await _wait(&"closing")


func show_hall_of_fame() -> void:
	log.append("hall of fame")
	await _wait(&"hall_of_fame")


func play_sector_music(sector: int) -> void:
	log.append("music %d" % sector)


func stop_music() -> void:
	log.append("stop music")


func go_to_sign_in() -> void:
	log.append("sign in")


func quit_game() -> void:
	log.append("quit")
