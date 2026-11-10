class_name TestPromptSender
extends GdUnitTestSuite
## The sender picture beside the first line of a map trigger's prompt (G9): `LoadPromptSenderPicture` (0x423378) and
## `WriteMessageTextWithSender` (0x4233c8). Teaches: pinning the original's rules with a table of boundary values,
## then checking that the screen applies them (which picture, where, for which text, and when it goes away).

const SCREEN_SCENE := "res://src/problems/problem_screen.tscn"

var _screen: ProblemScreen


func before_test() -> void:
	GameState.reset()
	GameClock.paused = false
	_screen = scene_runner(SCREEN_SCENE).scene() as ProblemScreen


func after_test() -> void:
	GameClock.paused = false
	GameState.reset()


const HEADER := "Alert:"
const BODY := "Input the number you see."

## A problem (the sounder, type 6, level 2 unless told otherwise) asked by trigger `slot`, whose prompt has a header line: dev's prompts are one line,
## and the sender picture needs the first line apart from the rest (the prompt is a plain field, so the test sets it).
func _asked_by(slot: int, type_id: int = 6, level: int = 2) -> ProblemInstance:
	var problem := ProblemFactory.make(type_id, level, null, 0)
	problem.trigger_slot = slot
	problem.prompt = HEADER + "\n" + BODY
	return problem


# --- the rule: which picture ------------------------------------------------------------------

func test_slots_2_to_19_and_60_up_are_the_research_ship() -> void:
	for slot in [2, 3, 10, 18, 19, 60, 61, 62]:
		assert_str(PromptSender.picture_name(slot)).is_equal("prompt_sender_ship")


func test_the_lock_the_canister_and_the_computer_slots_are_the_control_room() -> void:
	for slot in [0, 1, 20, 21, 40, 58, 59]:
		assert_str(PromptSender.picture_name(slot)).is_equal("prompt_sender_control_room")


func test_the_picture_choice_is_the_message_light_choice() -> void:
	# `DoAction` (0x417ffc) lights the ship for the same slots (2-19, 60 up); the canister (1) is the computer's.
	for slot in range(1, TriggerTable.SLOTS):
		var ship_light := GameState.light_for_slot(slot).x == 1
		assert_bool(PromptSender.picture_name(slot) == PromptSender.PICTURE_SHIP).is_equal(ship_light)


func test_the_pictures_are_55_by_20() -> void:
	for slot in [2, 20]:
		var texture := PromptSender.texture(slot)
		assert_object(texture).is_not_null()
		assert_vector(Vector2(texture.get_size())).is_equal(Vector2(PromptSender.PICTURE_SIZE))
	assert_str(PromptSender.texture(2).resource_path).ends_with("prompt_sender_ship_2412.png")
	assert_str(PromptSender.texture(20).resource_path).ends_with("prompt_sender_control_room_2413.png")


func test_the_header_starts_beside_the_picture() -> void:
	assert_vector(Vector2(PromptSender.PICTURE_POSITION)).is_equal(Vector2(361, 48))      # (0x169, 0x30)
	assert_int(PromptSender.HEADER_X).is_equal(414)                                         # 0x168 + 54 (55 rounded down to even)
	assert_int(PromptSender.BODY_Y).is_equal(68)                                            # 0x44


func test_the_text_is_split_at_the_first_newline() -> void:
	assert_array(PromptSender.split("Alert:\nInput the number.\nAnd more.")).is_equal(["Alert:", "Input the number.\nAnd more."])
	assert_array(PromptSender.split("No header at all")).is_equal(["", "No header at all"])


# --- the rule: for which prompts --------------------------------------------------------------

func test_every_trigger_slot_problem_remembers_its_slot_and_a_direct_one_does_not() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_int(ProblemFactory.for_trigger_slot(5, 0, rng).trigger_slot).is_equal(5)
	assert_int(ProblemFactory.for_canister(Catalog.sector(0), 0, rng).trigger_slot).is_equal(1)
	assert_int(ProblemFactory.make(6, 2).trigger_slot).is_equal(-1)


func test_applies_to_trigger_prompts_but_not_practice_or_the_lock() -> void:
	assert_bool(PromptSender.applies_to(_asked_by(5), false)).is_true()
	assert_bool(PromptSender.applies_to(_asked_by(5), true)).is_false()           # `InMathPractice`
	assert_bool(PromptSender.applies_to(_asked_by(-1), false)).is_false()          # no trigger
	var lock := ProblemFactory.make(0, 0)
	lock.trigger_slot = 0
	assert_bool(PromptSender.applies_to(lock, false)).is_false()                   # `DoCombinationLock`, not `ShowProblemPrompt`
	for type_id in range(1, 34):                                                   # (every type has records at some level)
		var level := 0
		while Catalog.problem_type(type_id).record_count(level) == 0:
			level += 1
		assert_bool(PromptSender.applies_to(_asked_by(5, type_id, level), false)).is_true()


# --- the screen ----------------------------------------------------------------------------

func test_a_ship_prompt_shows_the_ship_the_header_beside_it_and_the_rest_below() -> void:
	var problem := _asked_by(5)
	_screen.start(problem)
	var parts := PromptSender.split(problem.prompt)
	assert_bool(_screen.sender_icon.visible).is_true()
	assert_str(_screen.sender_icon.texture.resource_path).ends_with("prompt_sender_ship_2412.png")
	assert_vector(_screen.sender_icon.position).is_equal(Vector2(361, 48))
	assert_str(_screen.sender_header.text).is_equal(parts[0])
	assert_vector(_screen.sender_header.position).is_equal(Vector2(414, 48))
	assert_str(_screen.text_label.text).is_equal(parts[1])
	assert_float(_screen.text_label.position.x).is_equal(float(Catalog.screen_layout().message_box.position.x))     # the pack's message box
	assert_float(_screen.text_label.position.y).is_equal(68.0)


func test_a_computer_prompt_and_the_canister_show_the_control_room() -> void:
	_screen.start(_asked_by(30))
	assert_str(_screen.sender_icon.texture.resource_path).ends_with("prompt_sender_control_room_2413.png")
	_screen.start(_asked_by(1))
	assert_str(_screen.sender_icon.texture.resource_path).ends_with("prompt_sender_control_room_2413.png")
	_screen.start(_asked_by(60))
	assert_str(_screen.sender_icon.texture.resource_path).ends_with("prompt_sender_ship_2412.png")


func test_practice_and_direct_problems_have_no_picture() -> void:
	var direct := ProblemFactory.make(6, 2)
	direct.prompt = HEADER + "\n" + BODY
	_screen.start(direct)
	assert_bool(_screen.sender_icon.visible).is_false()
	assert_bool(_screen.sender_header.visible).is_false()
	assert_str(_screen.text_label.text).starts_with(HEADER)                           # the whole prompt, header included
	assert_float(_screen.text_label.position.y).is_equal(float(Catalog.screen_layout().message_box.position.y))    # from the top of the box
	_screen.practice = true
	_screen.start(_asked_by(5))
	assert_bool(_screen.sender_icon.visible).is_false()


func test_only_the_prompt_has_the_picture_the_hint_and_the_solution_do_not() -> void:
	var problem := _asked_by(5)
	_screen.start(problem)
	_screen.submit_answer(NumberValue.parse("98765"))                                 # wrong: "Error!"
	assert_bool(_screen.sender_icon.visible).is_false()
	assert_bool(_screen.sender_header.visible).is_false()
	assert_float(_screen.text_label.position.y).is_equal(float(Catalog.screen_layout().message_box.position.y))    # from the top of the box
	_screen.press_continue()
	assert_str(_screen.text_label.text).is_equal(problem.hint)                        # the hint: plain text, from the top
	assert_bool(_screen.sender_icon.visible).is_false()
	_screen.submit_answer(NumberValue.parse("98766"))                                 # wrong again
	_screen.press_continue()
	_screen.press_continue()                                                           # "directed to ship" -> the solution
	assert_str(_screen.text_label.text).is_equal(problem.solution)
	assert_bool(_screen.sender_icon.visible).is_false()
	assert_float(_screen.text_label.position.y).is_equal(float(Catalog.screen_layout().message_box.position.y))    # from the top of the box


func test_the_success_text_is_plain_too() -> void:
	var problem := _asked_by(5)
	_screen.start(problem)
	_screen.submit_answer(problem.expected)
	assert_str(_screen.text_label.text).is_equal(problem.success)
	assert_bool(_screen.sender_icon.visible).is_false()
	assert_float(_screen.text_label.position.y).is_equal(float(Catalog.screen_layout().message_box.position.y))    # from the top of the box


func test_the_picture_waits_for_the_diagram_to_build_up() -> void:
	var problem := _asked_by(25, 3, 0)                                                # sonar: the beam sweeps first (as in test_problem_flow)
	_screen.start(problem)
	assert_int(_screen.step()).is_equal(ProblemScreen.Step.INTRO)
	assert_bool(_screen.sender_icon.visible).is_false()                              # `ShowProblemPrompt` runs after `DrawProblemDiagram`
	assert_bool(_screen.sender_header.visible).is_false()
	_screen.diagram.skip_animation()
	assert_bool(_screen.sender_icon.visible).is_true()
	assert_str(_screen.sender_icon.texture.resource_path).ends_with("prompt_sender_control_room_2413.png")
	assert_str(_screen.sender_header.text).is_equal(PromptSender.split(problem.prompt)[0])
