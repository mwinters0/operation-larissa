class_name TestFoeSandboxDebug
extends GdUnitTestSuite
## Teaches: testing the two ends of a debugging feature without the editor. The SANDBOX end: the command line is parsed by a
## static function, the scene is run with its arguments in the environment variable (the way the editor hands them over) and
## must open on the creature's screen with the creature selected and its `.foe` line shown. The EDITOR end: the Foe Script
## panel decides what to run (`run_in_sandbox`) and says so with a signal; the debugger plugin turns a message from the game
## into a signal; the panel marks the lines. What needs the real editor (the button, `play_custom_scene`, the debugger channel
## carrying the message between two processes) is checked by hand.

const TEMP_DIR := "user://foe_sandbox_test"
## The sector the sandbox is opened on: the dev arena, whose creatures are on several screens.
const SECTOR := DevCreatures.ARENA

var _requests: Array[String] = []
var _panel: FoeEditorPanel


func before_test() -> void:
	_requests.clear()
	_panel = FoeEditorPanel.new()
	add_child(_panel)
	_panel.sandbox_requested.connect(func(arguments: String) -> void: _requests.append(arguments))


func after_test() -> void:
	_panel.free()
	OS.unset_environment(FoeSandbox.ARGS_ENV)
	GameClock.paused = false
	if not DirAccess.dir_exists_absolute(TEMP_DIR):
		return
	for folder in DirAccess.get_directories_at(TEMP_DIR):
		for file_name in DirAccess.get_files_at(TEMP_DIR + "/" + folder):
			DirAccess.remove_absolute(TEMP_DIR + "/" + folder + "/" + file_name)
		DirAccess.remove_absolute(TEMP_DIR + "/" + folder)
	DirAccess.remove_absolute(TEMP_DIR)


## The first creature of `sector` whose screen is not 0 (so that "opens on its screen" means something).
func _creature_off_screen_zero(sector: SectorData) -> int:
	for i in sector.foes.size():
		if sector.foes[i].screen != 0:
			return i
	return -1


# --- the arguments -----------------------------------------------------------

func test_the_arguments_are_parsed() -> void:
	var parsed := FoeSandbox.parse_args(PackedStringArray(["--sector=7", "--screen=3", "--foe=12", "--pause", "--ticks=5", "--snapshot=a.png"]))
	assert_int(parsed["sector"]).is_equal(7)
	assert_int(parsed["screen"]).is_equal(3)
	assert_int(parsed["foe"]).is_equal(12)
	assert_bool(parsed["pause"]).is_true()
	assert_bool(parsed["fly"]).is_false()
	assert_int(parsed["ticks"]).is_equal(5)
	assert_str(parsed["snapshot"]).is_equal("a.png")
	var touching := FoeSandbox.parse_args(PackedStringArray(["--touch=4"]))
	assert_int(touching["touch"]).is_equal(4)
	assert_bool(touching["fly"]).is_true()                         # touching needs the sub flying


func test_the_defaults_and_unknown_words() -> void:
	var parsed := FoeSandbox.parse_args(PackedStringArray(["--nonsense", "--foe=", "--foe=x", "plain"]))
	assert_int(parsed["sector"]).is_equal(0)
	assert_int(parsed["screen"]).is_equal(-1)                      # -1: not given
	assert_int(parsed["foe"]).is_equal(-1)
	assert_bool(parsed["pause"]).is_false()


func test_a_creature_decides_the_screen_unless_a_screen_is_given() -> void:
	var sector := Catalog.sector(SECTOR)
	var foe := _creature_off_screen_zero(sector)
	assert_int(foe).is_greater(-1)
	var screen := sector.foes[foe].screen
	assert_int(FoeSandbox.opening_screen(FoeSandbox.parse_args(PackedStringArray(["--foe=%d" % foe])), sector)).is_equal(screen)
	assert_int(FoeSandbox.opening_screen(FoeSandbox.parse_args(PackedStringArray(["--foe=%d" % foe, "--screen=0"])), sector)).is_equal(0)
	assert_int(FoeSandbox.opening_screen(FoeSandbox.parse_args(PackedStringArray([])), sector)).is_equal(0)
	assert_int(FoeSandbox.opening_screen(FoeSandbox.parse_args(PackedStringArray(["--foe=9999"])), sector)).is_equal(0)


func test_the_sandbox_opens_on_the_creature_selected_and_shows_its_line() -> void:
	var sector := Catalog.sector(SECTOR)
	var foe := _creature_off_screen_zero(sector)
	OS.set_environment(FoeSandbox.ARGS_ENV, "--sector=%d --foe=%d --pause" % [SECTOR, foe])
	var runner := scene_runner("res://src/debug/foe_sandbox.tscn")
	var sandbox := runner.scene() as FoeSandbox
	assert_int(sandbox.world.sector_index).is_equal(SECTOR)
	assert_int(sandbox.world.screen_index).is_equal(sector.foes[foe].screen)
	assert_int(sandbox.selected_foe).is_equal(foe)
	assert_bool(GameClock.paused).is_true()
	var report := sandbox.line_report()
	assert_int(report["selected"]).is_equal(foe)
	var line: int = report["lines"][foe]
	assert_int(line).is_greater(0)
	assert_int(line).is_equal(sector.foe_line_of(sandbox.world.sim.foes[foe].vm.pc))
	# the list shows the selected creature first, with its source line next to the live disassembly
	assert_str(sandbox.list_label.text).starts_with(">#%d " % foe)
	assert_str(sandbox.list_label.text).contains("line %d" % line)
	assert_str(sandbox.list_label.text).contains(sector.foe_source_map.describe(sandbox.world.sim.foes[foe].vm.pc))
	# stepping moves the creature on, and the report follows
	var before: Dictionary = sandbox.line_report()["lines"].duplicate()
	for i in 6:
		GameClock.step()
	for number in before:
		assert_int(sandbox.line_report()["lines"][number]).is_equal(sector.foe_line_of(sandbox.world.sim.foes[number].vm.pc))


func test_tab_selects_the_next_creature_on_the_screen() -> void:
	OS.set_environment(FoeSandbox.ARGS_ENV, "--sector=%d --pause" % SECTOR)
	var sandbox := scene_runner("res://src/debug/foe_sandbox.tscn").scene() as FoeSandbox
	var shown := sandbox.foes_on_screen()
	assert_int(shown.size()).is_greater(1)
	assert_int(sandbox.selected_foe).is_equal(-1)
	sandbox.select_next_foe(1)
	assert_int(sandbox.selected_foe).is_equal(shown[0].vm.index)
	sandbox.select_next_foe(1)
	assert_int(sandbox.selected_foe).is_equal(shown[1].vm.index)
	sandbox.select_next_foe(-1)
	sandbox.select_next_foe(-1)
	assert_int(sandbox.selected_foe).is_equal(shown[-1].vm.index)            # wraps round


func _press(node: Node, keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	node.call(&"_unhandled_key_input", key)


## [ ] and R start a sector as the game starts one (`ToolRun.begin_sector`): the pieces and the midpoint of the sector before stay
## behind, so a lost tank afterwards does not put the sub on screen 6 of a sector it never crossed.
func test_changing_or_reloading_the_sector_starts_its_collecting_over() -> void:
	OS.set_environment(FoeSandbox.ARGS_ENV, "--sector=%d --pause" % SECTOR)
	var sandbox := scene_runner("res://src/debug/foe_sandbox.tscn").scene() as FoeSandbox
	for keycode: Key in [KEY_BRACKETRIGHT, KEY_R, KEY_BRACKETLEFT]:
		GameState.collect_piece(0)
		GameState.past_midpoint = true
		_press(sandbox, keycode)
		assert_int(GameState.pieces_mask).override_failure_message("key %s kept the pieces" % OS.get_keycode_string(keycode)).is_equal(0)
		assert_bool(GameState.past_midpoint).override_failure_message("key %s kept the midpoint" % OS.get_keycode_string(keycode)).is_false()
		assert_int(GameState.sector).is_equal(sandbox.world.sector_index)
	GameState.reset()


# --- the editor: Run in sandbox -------------------------------------------------

## A scratch copy of sector `index` (its .foe and .tres) in user://, so that the panel may save it.
func _sector_copy(index: int) -> FoeScript:
	var dir := Catalog.sector_dir(index, TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for path in [Catalog.sector_path(index), Catalog.foe_path(index)]:
		var file := FileAccess.open(dir + "/" + path.get_file(), FileAccess.WRITE)
		file.store_string(FileAccess.get_file_as_string(path))
		file.close()
	return ResourceLoader.load(Catalog.foe_path(index, TEMP_DIR), "", ResourceLoader.CACHE_MODE_REPLACE) as FoeScript


## Puts the caret on the first instruction line under the label `label`.
func _caret_under(doc: FoeEditorPanel.Document, label: String) -> void:
	for n in doc.edit.get_line_count():
		if doc.edit.get_line(n).strip_edges() == label + ":":
			doc.edit.set_caret_line(n + 1)
			return
	fail("no label %s" % label)


func test_run_in_sandbox_asks_for_the_creature_at_the_caret() -> void:
	var doc := _panel.open_script(_sector_copy(SECTOR))
	var sector := Catalog.sector(SECTOR)
	var foe := _creature_off_screen_zero(sector)
	_caret_under(doc, sector.foes[foe].start_label)
	var owners := _panel.creatures_at_caret()
	assert_array(owners).contains([foe])
	assert_str(_panel.run_in_sandbox()).is_empty()
	assert_array(_requests).has_size(1)
	assert_str(_requests[0]).is_equal("--sector=%d --foe=%d" % [SECTOR, owners[0]])
	assert_array(doc.notes).has_size(1)
	assert_str(doc.notes[0]).contains("creature #%d on screen %d" % [owners[0], sector.foes[owners[0]].screen])
	# another creature of the list, paused
	assert_str(_panel.run_in_sandbox(foe, true)).is_empty()
	assert_str(_requests[1]).is_equal("--sector=%d --foe=%d --pause" % [SECTOR, foe])
	# the arguments mean the same to the sandbox
	var parsed := FoeSandbox.parse_args(_requests[1].split(" "))
	assert_int(parsed["sector"]).is_equal(SECTOR)
	assert_int(parsed["foe"]).is_equal(foe)
	assert_bool(parsed["pause"]).is_true()


func test_a_line_no_creature_runs_still_opens_the_sector() -> void:
	var doc := _panel.open_script(_sector_copy(SECTOR))
	doc.edit.set_caret_line(doc.edit.get_line_count() - 1)         # the empty line after the last instruction
	assert_array(_panel.creatures_at_caret()).is_empty()
	assert_str(_panel.run_in_sandbox()).is_empty()
	assert_str(_requests[0]).is_equal("--sector=%d" % SECTOR)
	assert_str(doc.notes[0]).contains("no creature runs line %d" % doc.edit.get_line_count())


func test_unsaved_text_is_saved_before_the_run_and_a_broken_text_is_not_run() -> void:
	var script := _sector_copy(SECTOR)
	var doc := _panel.open_script(script)
	doc.edit.text = doc.edit.text + "\n; an unsaved note\n"
	assert_bool(doc.is_dirty()).is_true()
	assert_str(_panel.run_in_sandbox()).is_empty()
	assert_bool(doc.is_dirty()).is_false()                         # saved
	assert_str(FileAccess.get_file_as_string(script.resource_path)).contains("; an unsaved note")
	# a text that does not assemble: nothing is saved or run, and the message says why
	var good := FileAccess.get_file_as_string(script.resource_path)
	doc.edit.text = doc.edit.text + "\n    Not_An_Instruction 1\n"
	var message := _panel.run_in_sandbox()
	assert_str(message).starts_with("Not run").contains("problem")
	assert_array(_requests).has_size(1)                            # no second request
	assert_str(FileAccess.get_file_as_string(script.resource_path)).is_equal(good)
	assert_str(doc.notes[0]).is_equal(message)


func test_a_file_without_a_sector_is_not_run() -> void:
	var path := TEMP_DIR + "/loose.foe"
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("a:\n    Wait_Next_Tick\n    Jump_To a\n")
	file.close()
	_panel.open_script(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as FoeScript)
	assert_str(_panel.run_in_sandbox()).contains("no sector beside this file")
	assert_array(_requests).is_empty()
	DirAccess.remove_absolute(path)


func test_nothing_is_run_without_an_open_file() -> void:
	assert_str(_panel.run_in_sandbox()).contains("open a sector's .foe file")
	assert_array(_requests).is_empty()


# --- the debugger channel -----------------------------------------------------------

func test_the_debugger_plugin_turns_the_message_into_a_signal() -> void:
	var relay := FoeDebuggerPlugin.Relay.new()              # (the plugin itself can only be created inside the editor)
	var received: Array[Dictionary] = []
	relay.lines_reported.connect(func(report: Dictionary) -> void: received.append(report))
	var report := {"sector": SECTOR, "screen": 1, "selected": 2, "lines": {2: 14}}
	assert_bool(relay.handle(FoeSandbox.LINES_MESSAGE, [report])).is_true()
	assert_array(received).is_equal([report] as Array[Dictionary])
	assert_bool(relay.handle("foe_sandbox:something_else", [report])).is_false()
	assert_bool(relay.handle(FoeSandbox.LINES_MESSAGE, [])).is_false()
	assert_bool(relay.handle(FoeSandbox.LINES_MESSAGE, ["not a report"])).is_false()
	assert_str(FoeSandbox.LINES_MESSAGE).starts_with(FoeDebuggerPlugin.PREFIX + ":")
	assert_int(received.size()).is_equal(1)


func test_the_panel_marks_the_lines_the_creatures_are_on_and_clears_them() -> void:
	var doc := _panel.open_script(_sector_copy(SECTOR))
	# the name of the file decides the sector: the scratch copy keeps the sector's file name
	_panel.show_running_lines({"sector": SECTOR, "selected": 2, "lines": {2: 10, 5: 10, 6: 12}})
	assert_int(doc.running_gutter).is_greater(-1)
	assert_str(doc.edit.get_line_gutter_text(9, doc.running_gutter)).is_equal("*2 #5")
	assert_str(doc.edit.get_line_gutter_text(11, doc.running_gutter)).is_equal("#6")
	# a new report replaces the old marks
	_panel.show_running_lines({"sector": SECTOR, "selected": -1, "lines": {1: 3}})
	assert_str(doc.edit.get_line_gutter_text(9, doc.running_gutter)).is_empty()
	assert_str(doc.edit.get_line_gutter_text(2, doc.running_gutter)).is_equal("#1")
	# a report for another sector marks nothing here, and an empty one (the sandbox runs again) clears
	_panel.show_running_lines({"sector": SECTOR + 1, "selected": 0, "lines": {0: 3}})
	assert_str(doc.edit.get_line_gutter_text(2, doc.running_gutter)).is_empty()
	_panel.show_running_lines({"sector": SECTOR, "selected": 1, "lines": {1: 3}})
	_panel.show_running_lines({"sector": SECTOR, "selected": 1, "lines": {}})
	assert_str(doc.edit.get_line_gutter_text(2, doc.running_gutter)).is_empty()
	_panel.show_running_lines({"sector": SECTOR, "selected": 1, "lines": {1: 3}})
	_panel.clear_running_lines()
	assert_str(doc.edit.get_line_gutter_text(2, doc.running_gutter)).is_empty()
