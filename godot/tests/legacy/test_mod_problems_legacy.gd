class_name TestModProblemsLegacy
extends GdUnitTestSuite
## A problem-screen mod and the original game's problem types: a mod that opts in to draw every original type it may (all but the lock and the ballast panels) is asked about every stored problem of every type without a fault,
## the state it is told fits what a sandboxed script may hold (`references_max`), and the original's diagram it holds underneath is the diagram the game makes without the mod: the same pictures, the same texts, the same build-up
## and replay lengths, family by family. (The mechanics of problem-screen mods on any pack are in tests/engine/test_mod_problems.gd.)
## Teaches: proving a wrapper changes nothing by recording the thing wrapped before it exists and comparing after.


## Without the legacy pack (the original game, made by the importer from your own copy) or the sandbox this suite skips.
func before(do_skip := not LegacyPack.present() or not ModLoader.sandbox_available(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py) and fetch the sandbox (uv run tools/fetch_sandbox.py)") -> void:
	pass


func after_test() -> void:
	GameState.reset()


## What a diagram shows and how long it plays, as one comparable text: the family, every item (kind, picture, place, text), the lengths of the build-up and the replay.
func _signature(diagram: DiagramBase) -> String:
	var parts := PackedStringArray()
	for item in diagram.items:
		parts.append("%d/%d/%s/%s" % [item.kind, item.pic, item.position, item.text])
	return "%s | %s | intro %d | replay %d | %s" % [diagram.type.diagram["family"], ";".join(parts), diagram.intro_length(), diagram.success_replay_length(), diagram.has_intro()]


## [type, level, index] of every stored problem of the original types the engine does not answer through their own diagram.
func _problems() -> Array:
	var found := []
	for type_id in Catalog.PROBLEM_TYPE_COUNT:
		var type := Catalog.problem_type(type_id)
		if DiagramFactory.takes_input(String(type.diagram["family"])):
			continue
		for level in 4:
			for index in type.record_count(level):
				found.append([type_id, level, index])
	return found


func _plain_only(value: Variant, path: String, bad: Array[String]) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if not key is String:
				bad.append("%s has a key %s" % [path, key])
			_plain_only(value[key], "%s.%s" % [path, key], bad)
	elif value is Array:
		for i in (value as Array).size():
			_plain_only(value[i], "%s[%d]" % [path, i], bad)
	elif not (value == null or value is int or value is float or value is bool or value is String or value is Vector2):
		bad.append("%s is a %s" % [path, type_string(typeof(value))])


func test_a_mod_that_draws_every_original_type_it_may_leaves_the_originals_diagrams_as_they_are() -> void:
	var problems := _problems()
	assert_int(problems.size()).is_greater(100)
	var types: Array[int] = []
	var seen := {}
	var baseline := {}
	for entry: Array in problems:
		var diagram := DiagramFactory.create(ProblemInstance.build(Catalog.problem_type(entry[0]), entry[1], entry[2], 0))
		assert_bool(diagram is ModDiagram).is_false()
		baseline[entry] = _signature(diagram)
		diagram.free()
		if not seen.has(entry[0]):
			seen[entry[0]] = true
			types.append(entry[0])
	assert_int(types.size()).is_equal(Catalog.PROBLEM_TYPE_COUNT - 3)                                # (all but the lock and the two ballast panels)
	var shelf := PackShelf.new()
	shelf.add_mod_fixture("res://tests/mods/tides", {"problems": {"types": types}})
	ModProblemShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	var mod := ModHost.mod(String(shelf.id))
	assert_object(mod).override_failure_message("the mod did not load: %s" % ModHost.failure(String(shelf.id))).is_not_null()
	var faults := int(mod.get("monitor_exceptions"))
	var sonar_like := 0
	for entry: Array in problems:
		var problem := ProblemInstance.build(Catalog.problem_type(entry[0]), entry[1], entry[2], 0)
		var diagram := DiagramFactory.create(problem)
		assert_bool(diagram is ModDiagram).override_failure_message("type %d is not drawn by the mod" % entry[0]).is_true()
		var wrapped := diagram as ModDiagram
		assert_str(_signature(wrapped.plain())).override_failure_message("type %d level %d record %d: the original's diagram is not what the game makes" % entry).is_equal(baseline[entry])
		assert_int(wrapped.intro_length()).is_equal(wrapped.plain().intro_length())
		assert_bool(wrapped.drawn_lines().any(func(line: String) -> bool: return line.begins_with("text Type %d " % entry[0]))).override_failure_message("type %d: the mod drew nothing" % entry[0]).is_true()
		var state := ProblemState.build(problem, "", ProblemFlow.Step.ANSWERING)
		var bad: Array[String] = []
		_plain_only(state, "state", bad)
		assert_array(bad).is_empty()
		for key: String in state["art"]:
			assert_bool(key.is_empty() or Assets.picture_by_key(key) != null).override_failure_message("type %d: %s names no picture" % [entry[0], key]).is_true()
		if wrapped.has_intro():
			sonar_like += 1
		diagram.free()
	assert_int(int(mod.get("monitor_exceptions")) - faults).override_failure_message("the mod faulted on a problem of the original").is_equal(0)
	assert_int(sonar_like).is_greater(0)
	for locked in [0, 28, 29]:
		var diagram := DiagramFactory.create(ProblemInstance.build(Catalog.problem_type(locked), 0, 0, 0))
		assert_bool(diagram is ModDiagram).is_false()
		diagram.free()
	shelf.remove()
	Mods.sync()
