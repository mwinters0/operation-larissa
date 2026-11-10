class_name TestMessageQueue
extends GdUnitTestSuite
## Teaches: testing ordering and time. The queue is plain logic; time is the GameClock, which
## the test advances by hand with `step()`, so nothing here waits for real seconds.

var _queue: MessageQueue
var _log: Array


func before_test() -> void:
	GameClock.paused = false
	_queue = MessageQueue.new(GameClock)
	_log = []
	_queue.message_shown.connect(func(m: MessageQueue.Message) -> void: _log.append("show " + (m.title if m != null else "-")))
	_queue.message_closed.connect(func(m: MessageQueue.Message, choice: int) -> void: _log.append("close %s %d" % [m.title, choice]))


func after_test() -> void:
	GameClock.paused = false
	if GameClock.tick.is_connected(_queue._on_tick):
		GameClock.tick.disconnect(_queue._on_tick)


func test_the_first_message_shows_at_once() -> void:
	_queue.post("A", "text")
	assert_str(_queue.current.title).is_equal("A")
	assert_array(_log).is_equal(["show A"])


func test_messages_are_shown_in_the_order_they_were_posted() -> void:
	_queue.post("A", "")
	_queue.post("B", "")
	_queue.post("C", "")
	assert_int(_queue.waiting_count()).is_equal(2)
	_queue.close_current()
	assert_str(_queue.current.title).is_equal("B")
	_queue.close_current()
	assert_str(_queue.current.title).is_equal("C")
	_queue.close_current()
	assert_bool(_queue.is_open()).is_false()
	assert_array(_log).is_equal(["show A", "close A 0", "show B", "close B 0", "show C", "close C 0", "show -"])


func test_the_answer_comes_back_through_the_signal() -> void:
	var message := _queue.post("Exit", "sure?", PackedStringArray(["Yes", "No"]))
	var answers: Array = []
	message.closed.connect(func(choice: int) -> void: answers.append(choice))
	_queue.close_current(1)
	assert_array(answers).is_equal([1])
	assert_int(message.choice).is_equal(1)


func test_a_modal_message_stops_the_clock_and_gives_it_back() -> void:
	_queue.post("A", "")
	assert_bool(GameClock.paused).is_true()
	_queue.close_current()
	assert_bool(GameClock.paused).is_false()


func test_the_clock_stays_paused_if_it_was_paused_before() -> void:
	GameClock.paused = true                  # for instance a math problem is open
	_queue.post("A", "")
	_queue.close_current()
	assert_bool(GameClock.paused).is_true()


func test_a_clock_pause_lasts_through_a_queue_of_messages() -> void:
	_queue.post("A", "")
	_queue.post("B", "")
	_queue.close_current()
	assert_bool(GameClock.paused).is_true()
	_queue.close_current()
	assert_bool(GameClock.paused).is_false()


func test_a_message_opened_over_a_problem_and_closed_after_it_does_not_leave_the_clock_stopped() -> void:
	var message := _queue.post("Hint", "")            # the message is up first (the clock held by it) ...
	GameClock.hold()                                  # ... a problem screen opens under it ...
	_queue.close_current()                            # ... the message closes: the problem still holds the clock
	assert_bool(GameClock.paused).is_true()
	GameClock.release()                               # the problem is over
	assert_bool(GameClock.paused).is_false()          # (it used to stay stopped for good)
	assert_int(message.choice).is_equal(0)


func test_a_message_opened_over_a_problem_gives_back_only_its_own_hold() -> void:
	GameClock.hold()                                  # the problem screen
	_queue.post("Hint", "")
	GameClock.release()                               # the problem ends while the message is still up (e.g. Enter)
	assert_bool(GameClock.paused).is_true()
	_queue.close_current()
	assert_bool(GameClock.paused).is_false()


func test_a_timed_message_closes_itself_after_its_ticks() -> void:
	_queue.post("Toast", "", PackedStringArray(["OK"]), false, 3)
	assert_bool(GameClock.paused).is_false()            # it does not stop the game
	GameClock.step()
	GameClock.step()
	assert_bool(_queue.is_open()).is_true()
	GameClock.step()
	assert_bool(_queue.is_open()).is_false()
	assert_array(_log).contains(["close Toast -1"])


func test_ticks_do_not_close_a_message_without_a_timer() -> void:
	_queue.post("A", "")
	for i in 20:
		GameClock.step()
	assert_bool(_queue.is_open()).is_true()


func test_ship_and_computer_messages_have_the_original_titles() -> void:
	_queue.post_ship("hello")
	assert_str(_queue.current.title).is_equal("Surface Ship Message")
	_queue.close_current()
	_queue.post_computer("hi")
	assert_str(_queue.current.title).is_equal("Computer Message")


func test_message_box_view_shows_the_current_message_and_its_buttons() -> void:
	var view := scene_runner("res://src/ui/message_box.tscn").scene() as MessageBoxView
	var modals := ModalHost.new(view, [])
	modals.attach(_queue, view)
	assert_bool(view.visible).is_false()
	_queue.post("Exit", "Really?", PackedStringArray(["Yes", "No"]))
	assert_bool(view.visible).is_true()
	assert_str(view.title_label.text).is_equal("Exit")
	assert_int(view.button_row.get_child_count()).is_equal(2)
	(view.button_row.get_child(1) as Button).pressed.emit()
	assert_bool(view.visible).is_false()
	assert_int(_log.size()).is_greater(2)


func test_a_message_posted_by_the_close_handler_stays_up() -> void:
	# `await message.closed` resumes INSIDE close_current: the next page of a story is posted right there.
	var queue := MessageQueue.new(GameClock)
	var shown := []
	queue.message_shown.connect(func(message: MessageQueue.Message) -> void: shown.append(message))
	var first := queue.post("A", "first")
	first.closed.connect(func(_choice: int) -> void: queue.post("B", "second"))
	queue.close_current()
	assert_bool(queue.is_open()).is_true()
	assert_object(shown.back()).is_not_null()                 # the last thing the view heard is a message, not "nothing"
	assert_str((shown.back() as MessageQueue.Message).body).is_equal("second")
