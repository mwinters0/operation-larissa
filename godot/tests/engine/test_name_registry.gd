class_name TestNameRegistry
extends GdUnitTestSuite
## Teaches: validating a hand-made data file. `names/original.json` is typed by people, so it can go wrong in ways the importer's files cannot: a name that
## breaks the convention, two things with one name, a number that does not exist. This suite checks the committed file against the reader's rules (convention,
## uniqueness, scopes) and the reader itself on small files made here. What the names point at in the original game (its sounds, zones, creatures ... ) is
## checked in tests/legacy/test_name_registry_legacy.gd. (Duplicate keys inside one JSON object, which a parser silently merges, and the file's layout are
## checked by tools/import/test_names.py.)

var _names: NameRegistry


func before_test() -> void:
	_names = NameRegistry.original()


## All (scope, name, number) of one kind in the committed file; the scope is NO_SCOPE for global kinds and common names.
func _stored(kind: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var scopes: Array[int] = [NameRegistry.NO_SCOPE]
	scopes.append_array(_names.named_scopes(kind))
	for scope in scopes:
		var table := _names.entries(kind) if scope == NameRegistry.NO_SCOPE else _scope_only(kind, scope)
		for name: String in table:
			found.append({"scope": scope, "name": name, "index": table[name]})
	return found


## The names of `scope` without the common ones (entries() gives both).
func _scope_only(kind: StringName, scope: int) -> Dictionary:
	var own := _names.entries(kind, scope)
	for name: String in _names.entries(kind):
		own.erase(name)
	return own


func test_the_file_is_sound() -> void:
	assert_array(_names.problems).override_failure_message("names/original.json: " + "; ".join(_names.problems)).is_empty()


func test_every_kind_is_in_the_file() -> void:
	# A kind with no names yet is still written (as {}), so the list of kinds is in the file where people edit.
	var root: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NameRegistry.STORE_PATH))
	for kind in NameRegistry.kinds():
		assert_bool((root["names"] as Dictionary).has(String(kind))).override_failure_message(String(kind)).is_true()


func test_every_name_follows_the_convention() -> void:
	var rule := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	for kind in NameRegistry.kinds():
		for entry in _stored(kind):
			var name: String = entry["name"]
			assert_bool(rule.search(name) != null).override_failure_message("%s '%s'" % [kind, name]).is_true()
			assert_str(NameRegistry.name_problem(name)).override_failure_message("%s '%s'" % [kind, name]).is_empty()


func test_no_name_can_be_mistaken_for_something_else_in_an_operand() -> void:
	for kind in NameRegistry.kinds():
		for entry in _stored(kind):
			var name: String = entry["name"]
			var what := "%s '%s'" % [kind, name]
			assert_bool(name.is_valid_int()).override_failure_message(what + " reads as a number").is_false()
			assert_int(FoeOps.parse_foe(name)).override_failure_message(what + " reads as a creature reference").is_equal(-1)
			assert_int(FoeOps.op_from_mnemonic(name)).override_failure_message(what + " is an instruction").is_equal(-1)
			assert_bool(FoeAsm.is_identifier(name)).override_failure_message(what + " is not one word").is_true()


func test_names_are_unique_within_their_scope() -> void:
	# What a lookup sees in one scope: its own names and the common ones, each name once, each number once.
	for kind in NameRegistry.kinds():
		var scopes: Array[int] = [NameRegistry.NO_SCOPE]
		scopes.append_array(_names.named_scopes(kind))
		for scope in scopes:
			var seen_names := {}
			var seen_numbers := {}
			var visible := _names.entries(kind, scope)
			for name: String in visible:
				assert_bool(seen_names.has(name)).override_failure_message("%s: '%s' twice" % [kind, name]).is_false()
				seen_names[name] = true
				assert_bool(seen_numbers.has(visible[name])).override_failure_message(
						"%s scope %d: number %d has two names" % [kind, scope, visible[name]]).is_false()
				seen_numbers[visible[name]] = true
			var own := _stored(kind).filter(func(e: Dictionary) -> bool: return e["scope"] == scope or e["scope"] == NameRegistry.NO_SCOPE)
			assert_int(visible.size()).override_failure_message("%s scope %d" % [kind, scope]).is_equal(own.size())


func test_a_scoped_name_never_hides_a_common_one() -> void:
	# Common names are valid in every scope, so no scope may reuse one for another number.
	for kind in NameRegistry.kinds():
		if not NameRegistry.is_scoped(kind):
			continue
		var common := _names.entries(kind)
		for scope in _names.named_scopes(kind):
			for name: String in _scope_only(kind, scope):
				assert_bool(common.has(name)).override_failure_message("%s zone/sector %d reuses '%s'" % [kind, scope, name]).is_false()


func test_the_flag_that_ends_the_game_is_the_one_the_world_reads() -> void:
	assert_int(_names.index_of(&"flag", "finale")).is_equal(SimWorld.FINALE_SEMAPHORE_BIT)


func test_every_number_has_a_name_that_leads_back_to_it() -> void:
	for kind in NameRegistry.kinds():
		var def: Dictionary = NameRegistry.KINDS[kind]
		var scopes: Array[int] = [NameRegistry.NO_SCOPE]
		scopes.append_array(_names.named_scopes(kind))
		var step := 1 if int(def["last"]) - int(def["first"]) < 3000 else 7     # the text ids go to 65535
		for scope in scopes:
			for index in range(def["first"], int(def["last"]) + 1, step):
				var name := _names.name_of(kind, index, scope)
				assert_str(name).override_failure_message("%s %d has no name" % [kind, index]).is_not_empty()
				assert_int(_names.index_of(kind, name, scope)).override_failure_message("%s %d -> '%s'" % [kind, index, name]).is_equal(index)


func test_made_up_names() -> void:
	assert_str(NameRegistry.fallback_name(&"sound", 3)).is_equal("sfx_03")
	assert_str(NameRegistry.fallback_name(&"frame", 7)).is_equal("frame_007")
	assert_str(NameRegistry.fallback_name(&"deco", 70)).is_equal("deco_070")
	assert_str(NameRegistry.fallback_name(&"voice", 4243)).is_equal("voice_4243")
	assert_str(NameRegistry.fallback_name(&"sector", 5)).is_equal("sector_05")
	assert_str(NameRegistry.fallback_name(&"flag", 9)).is_equal("flag_09")
	assert_str(NameRegistry.fallback_name(&"foe", 12)).is_equal("foe_12")
	assert_str(NameRegistry.fallback_name(&"sound", 52)).is_empty()        # not a sound at all
	# Only the exact spelling counts, so one number has one made-up name.
	assert_int(NameRegistry.fallback_index(&"sound", "sfx_3")).is_equal(-1)
	assert_int(NameRegistry.fallback_index(&"sound", "sfx_003")).is_equal(-1)
	assert_int(NameRegistry.fallback_index(&"sound", "sfx_+03")).is_equal(-1)
	assert_int(NameRegistry.fallback_index(&"sound", "sfx_1c")).is_equal(-1)
	assert_int(NameRegistry.fallback_index(&"sound", "sfx_52")).is_equal(-1)
	assert_int(NameRegistry.fallback_index(&"sound", "frame_003")).is_equal(-1)


# --- scopes ---------------------------------------------------------------------------------------------------------

func _registry(names: Dictionary) -> NameRegistry:
	return NameRegistry.parse(JSON.stringify({"format": NameRegistry.FORMAT, "names": names}))


func test_a_name_of_a_zone_works_only_in_that_zone() -> void:
	var registry := _registry({"frame": {"common": {"ink": 28}, "1": {"eel": 40}, "2": {"ray": 40}}})
	assert_array(registry.problems).is_empty()
	assert_int(registry.index_of(&"frame", "eel", 1)).is_equal(40)
	assert_int(registry.index_of(&"frame", "eel", 2)).is_equal(-1)
	assert_int(registry.index_of(&"frame", "eel")).is_equal(-1)            # no zone: only the common names
	assert_int(registry.index_of(&"frame", "ink", 2)).is_equal(28)         # a common name works in every zone
	assert_str(registry.name_of(&"frame", 40, 1)).is_equal("eel")
	assert_str(registry.name_of(&"frame", 40, 2)).is_equal("ray")
	assert_str(registry.name_of(&"frame", 40, 3)).is_equal("frame_040")    # nobody named it in zone 3
	assert_bool(registry.is_named(&"frame", 40, 3)).is_false()
	assert_array(registry.names(&"frame", 1)).contains_exactly(["ink", "eel"])
	assert_array(registry.names(&"frame")).contains_exactly(["ink"])
	assert_array(registry.named_scopes(&"frame")).contains_exactly([1, 2])


func test_a_global_kind_ignores_the_scope() -> void:
	var registry := _registry({"sound": {"begin": 22}})
	assert_int(registry.index_of(&"sound", "begin", 5)).is_equal(-1)       # a scope that a sound does not have
	assert_int(registry.index_of(&"sound", "begin")).is_equal(22)
	assert_bool(NameRegistry.is_scoped(&"sound")).is_false()
	assert_bool(NameRegistry.is_scoped(&"flag")).is_true()


func test_a_scope_that_does_not_exist_is_refused() -> void:
	assert_int(_names.index_of(&"frame", "ink_burst_0", 7)).is_equal(-1)    # zones are 0-6
	assert_int(_names.index_of(&"deco", "x", 5)).is_equal(-1)               # art zones are 0-4
	assert_str(_names.name_of(&"frame", 40, 7)).is_empty()


func test_the_made_up_name_works_even_when_there_is_a_real_one() -> void:
	var registry := _registry({"sound": {"loud": 22}})
	assert_str(registry.name_of(&"sound", 22)).is_equal("loud")
	assert_str(NameRegistry.fallback_name(&"sound", 22)).is_equal("sfx_22")
	assert_int(registry.index_of(&"sound", "sfx_22")).is_equal(22)          # an old script keeps working after the rename
	assert_int(registry.index_of(&"sound", "loud")).is_equal(22)


# --- the reader finds what is wrong ---------------------------------------------------------------------------------

func _problem_with(registry: NameRegistry, fragment: String) -> bool:
	for problem in registry.problems:
		if problem.contains(fragment):
			return true
	return false


func test_the_reader_reports_a_bad_name() -> void:
	for bad in ["Begin", "9lives", "two words", "has-dash", "", "über", "self", "mirror", "jump_to", "padding", "sfx_05"]:
		var registry := _registry({"sound": {bad: 5}})
		assert_array(registry.problems).override_failure_message("'%s' was accepted" % bad).is_not_empty()
		assert_int(registry.index_of(&"sound", bad)).override_failure_message(bad).is_equal(-1 if bad != "sfx_05" else 5)
	assert_bool(_problem_with(_registry({"sound": {"a" + "b".repeat(NameRegistry.MAX_NAME_LENGTH): 5}}), "longer than")).is_true()
	assert_bool(_problem_with(_registry({"sound": {"sfx_05": 7}}), "made-up name of number 5")).is_true()


func test_the_reader_reports_a_bad_number() -> void:
	assert_bool(_problem_with(_registry({"sound": {"loud": 52}}), "outside 0 to 51")).is_true()
	assert_bool(_problem_with(_registry({"sound": {"loud": -1}}), "outside")).is_true()
	assert_bool(_problem_with(_registry({"sound": {"loud": 2.5}}), "whole number")).is_true()
	assert_bool(_problem_with(_registry({"sound": {"loud": "2"}}), "whole number")).is_true()
	assert_bool(_problem_with(_registry({"flag": {"common": {"late": 16}}}), "outside 0 to 15")).is_true()


func test_the_reader_reports_two_names_for_one_number() -> void:
	assert_bool(_problem_with(_registry({"sound": {"a": 5, "b": 5}}), "both 5")).is_true()
	var common_and_zone := _registry({"frame": {"common": {"ink": 28}, "1": {"blob": 28}}})
	assert_bool(_problem_with(common_and_zone, "28 is named 'blob' and also 'ink'")).is_true()


func test_the_reader_reports_a_name_that_is_also_a_common_name() -> void:
	assert_bool(_problem_with(_registry({"frame": {"common": {"ink": 28}, "1": {"ink": 40}}}), "also a common name")).is_true()


func test_the_reader_reports_a_bad_scope_or_kind_or_format() -> void:
	assert_bool(_problem_with(_registry({"frame": {"7": {"eel": 40}}}), "'7' is not a scope")).is_true()
	assert_bool(_problem_with(_registry({"frame": {"01": {"eel": 40}}}), "'01' is not a scope")).is_true()
	assert_bool(_problem_with(_registry({"frame": {"zone one": {"eel": 40}}}), "is not a scope")).is_true()
	assert_bool(_problem_with(_registry({"sandwich": {}}), "unknown kind 'sandwich'")).is_true()
	assert_bool(_problem_with(NameRegistry.parse("{\"format\": 2, \"names\": {}}"), "format 2")).is_true()
	assert_bool(_problem_with(NameRegistry.parse("{\"format\": 1}"), "\"names\" is missing")).is_true()
	assert_bool(_problem_with(NameRegistry.parse("[1, 2]"), "not a JSON object")).is_true()
	assert_bool(_problem_with(NameRegistry.parse("{nope"), "not JSON")).is_true()
	assert_bool(_problem_with(NameRegistry.from_file("res://names/there_is_no_such_file.json"), "no such file")).is_true()


func _registry_with_audio(same_audio: Variant) -> NameRegistry:
	return NameRegistry.parse(JSON.stringify({"format": NameRegistry.FORMAT, "names": {}, "same_audio": same_audio}))


func test_the_reader_reads_the_recordings_that_are_alike() -> void:
	var registry := _registry_with_audio({"sound": [[9, 7, 8], [5, 3]]})
	assert_array(registry.problems).is_empty()
	var expected: Array[Array] = [[3, 5], [7, 8, 9]]
	assert_array(registry.same_audio_groups(&"sound")).is_equal(expected)
	assert_array(registry.same_audio(&"sound", 9)).is_equal([7, 8])
	assert_array(registry.same_audio(&"sound", 4)).is_empty()
	assert_array(NameRegistry.parse("{\"format\": 1, \"names\": {}}").same_audio_groups(&"sound")).is_empty()   # the key is optional


func test_the_reader_reports_bad_recording_groups() -> void:
	assert_bool(_problem_with(_registry_with_audio({"sound": [[5]]}), "two or more")).is_true()
	assert_bool(_problem_with(_registry_with_audio({"sound": [[5, 5]]}), "two or more")).is_true()
	assert_bool(_problem_with(_registry_with_audio({"sound": [[1, 60]]}), "two or more")).is_true()
	assert_bool(_problem_with(_registry_with_audio({"sound": [[1, "2"]]}), "two or more")).is_true()
	assert_bool(_problem_with(_registry_with_audio({"sound": [[1, 2], [2, 3]]}), "2 is in more than one group")).is_true()
	assert_bool(_problem_with(_registry_with_audio({"sandwich": [[1, 2]]}), "unknown kind 'sandwich'")).is_true()
	assert_bool(_problem_with(_registry_with_audio({"sound": 3}), "expected a list of groups")).is_true()
	assert_bool(_problem_with(_registry_with_audio([1, 2]), "expected an object")).is_true()
	# The good groups of a file with a bad one are still read.
	assert_array(_registry_with_audio({"sound": [[1, 2], [3]]}).same_audio(&"sound", 1)).is_equal([2])


func test_a_registry_with_problems_still_answers() -> void:
	var registry := _registry({"sound": {"good": 5, "Bad": 6}})
	assert_int(registry.problems.size()).is_equal(1)
	assert_int(registry.index_of(&"sound", "good")).is_equal(5)
	assert_str(registry.name_of(&"sound", 6)).is_equal("sfx_06")


func test_an_empty_registry_still_names_every_number() -> void:
	var registry := NameRegistry.parse("{\"format\": 1, \"names\": {}}")
	assert_array(registry.problems).is_empty()
	assert_str(registry.name_of(&"sound", 22)).is_equal("sfx_22")
	assert_int(registry.index_of(&"sound", "sfx_22")).is_equal(22)
	assert_int(registry.index_of(&"sound", "begin")).is_equal(-1)


# --- messages for the person who typed the name --------------------------------------------------------------

func test_unknown_names_are_explained() -> void:
	var registry := _registry({"sound": {"begin": 22}, "frame": {"common": {"ink": 28}}})
	assert_str(registry.explain_unknown(&"sound", "begin")).is_empty()
	assert_str(registry.explain_unknown(&"sound", "sfx_30")).is_empty()
	assert_str(registry.explain_unknown(&"sound", "bgin")).is_equal("unknown sound 'bgin' (did you mean 'begin'?)")
	assert_str(registry.explain_unknown(&"sound", "zzzzzz")).is_equal("unknown sound 'zzzzzz'")
	assert_str(registry.explain_unknown(&"sound", "Begin")).contains("lowercase")
	assert_str(registry.explain_unknown(&"sound", "2")).contains("not a valid name")
	assert_str(registry.explain_unknown(&"sandwich", "x")).contains("the kinds are sound, frame")
	assert_str(registry.explain_unknown(&"frame", "ink", 9)).contains("a zone (0 to 6")


func test_a_name_from_another_scope_is_pointed_out() -> void:
	var registry := _registry({"frame": {"1": {"eel": 40}}})
	var message := registry.explain_unknown(&"frame", "eel", 2)
	assert_str(message).contains("unknown frame 'eel'")
	assert_str(message).contains("one in a zone 1")


# --- the places that used to keep names of their own ---------------------------------------------------------------

func test_the_sfx_catalog_asks_the_registry() -> void:
	var catalog := Catalog.sfx_catalog()
	assert_dict(catalog.named).is_equal(_names.entries(&"sound"))
	assert_int(catalog.id_of(&"begin")).is_equal(_names.index_of(&"sound", "begin"))
	var unnamed := 0
	while _names.is_named(&"sound", unnamed):
		unnamed += 1                                                  # the first sound nobody has named yet keeps its made-up name
	var made_up := NameRegistry.fallback_name(&"sound", unnamed)
	assert_int(catalog.id_of(StringName(made_up))).is_equal(unnamed)
	assert_str(catalog.name_of(unnamed)).is_equal(made_up)
	assert_int(catalog.id_of(&"nonsense")).is_equal(-1)
