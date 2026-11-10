extends Control
## Debug menu for the math problems: pick any of the 34 types (and the ones a pack of the chain adds, `Catalog.problem_type_ids`) and any of the 4
## educational levels and play that problem, whether or not a trigger can ask for it.
##
## Teaches: a throw-away tool built from ItemList + Buttons that reuses the real
## `ProblemRunner`, so it exercises exactly the code the game uses.
##
## Keys: Up/Down choose the type, 1-4 start the problem at that level, R repeats the last one.
##
## Command line (after `--`), for screenshots:
##   godot --path godot res://src/debug/problem_menu.tscn -- --type=2 --level=1 [--record=0]
##         [--answers=wrong,right] [--wait=3.5] --snapshot=/some/where/shot.png
## `--answers` feeds "wrong" / "right" answers (comma separated) before the picture is taken.

@onready var menu: Control = %Menu
@onready var type_list: ItemList = %TypeList
@onready var level_buttons: HBoxContainer = %LevelButtons
@onready var info_label: Label = %InfoLabel
@onready var result_label: Label = %ResultLabel

var _last_type: int = 0
var _last_level: int = 0
## The type number of each line of the list.
var _type_ids: Array[int] = []


func _ready() -> void:
	_type_ids = Catalog.problem_type_ids()
	for t in _type_ids:
		type_list.add_item("%2d  %s" % [t, Catalog.problem_type(t).title])
	type_list.item_selected.connect(_on_type_selected)
	for level in 4:
		var button := Button.new()
		button.text = "Level %d" % level
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_play.bind(level))
		level_buttons.add_child(button)
	GameState.reset()
	type_list.select(0)
	_on_type_selected(0)
	type_list.grab_focus()
	_run_command_line()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_4:
		_play(key_event.keycode - KEY_1)
	elif key_event.keycode == KEY_R:
		_play(_last_level, _last_type)


func _on_type_selected(index: int) -> void:
	var type := Catalog.problem_type(_type_ids[index])
	var parts: PackedStringArray = []
	for level in 4:
		var button := level_buttons.get_child(level) as Button
		var count := type.record_count(level)
		button.disabled = count == 0
		parts.append("L%d: %d" % [level, count])
	info_label.text = "%s\nStored problems per level   %s" % [type.title, "   ".join(parts)]


func _play(level: int, type_id: int = -1) -> void:
	var chosen := type_id if type_id >= 0 else (_type_ids[type_list.get_selected_items()[0]] if type_list.is_anything_selected() else 0)
	var problem := ProblemFactory.make(chosen, level)
	if problem == null:
		result_label.text = "No problem of type %d at level %d" % [chosen, level]
		return
	_last_type = chosen
	_last_level = level
	await _show(problem)


func _show(problem: ProblemInstance) -> void:
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	menu.hide()                    # the problem is drawn over the console, like in the game
	add_child(screen)
	screen.start(problem)
	var session: ProblemSession = await screen.finished
	screen.queue_free()
	menu.show()
	result_label.text = "Last: %s L%d  %s, %d wrong answer(s)" % [
			problem.title, problem.level, "solved" if session.solved else "not solved", session.misses]
	type_list.grab_focus()


# --- screenshot support -----------------------------------------------------------

func _run_command_line() -> void:
	var options := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() > 1 else ""
	if not options.has("type"):
		return
	var problem := ProblemFactory.make(options["type"].to_int(), options.get("level", "0").to_int(), null,
			options.get("record", "-1").to_int())
	if problem == null:
		get_tree().quit(1)
		return
	var screen: ProblemScreen = ProblemRunner.SCREEN_SCENE.instantiate()
	menu.hide()
	add_child(screen)
	screen.start(problem)
	if screen.step() == ProblemScreen.Step.INTRO and options.get("answers", "") != "":
		await screen.intro_finished                      # (answers are discarded while the diagram builds up)
	for answer in options.get("answers", "").split(",", false):
		await get_tree().create_timer(0.4).timeout
		if answer == "continue":                          # Enter: ends a message ("Error!", the note to the ship, the solution)
			screen.press_continue()
			continue
		if screen.step() == ProblemScreen.Step.MESSAGE:   # (the previous answer's message would swallow this one)
			screen.press_continue()
		screen.submit_answer(_scripted_answer(problem, answer))
	if options.has("snapshot"):
		# `--wait=SECONDS` lets the intro animations of some diagrams (sonar sweep, blinking barnacles) finish
		await get_tree().create_timer(options.get("wait", "0.7").to_float()).timeout
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(options["snapshot"])
		get_tree().quit(0 if error == OK else 1)


## "right" = the stored answer (or the stored selection), "wrong" = something that is surely not.
func _scripted_answer(problem: ProblemInstance, word: String) -> Variant:
	if problem.input_kind == ProblemInstance.InputKind.DENOMINATIONS:
		return problem.record.int_at(1) if word == "right" else 0
	if word == "right":
		return problem.expected if problem.expected != null else NumberValue.from_double(
				(problem.record.value_at(2) + problem.record.value_at(3)) / 2.0)
	return NumberValue.decimal(-1)
