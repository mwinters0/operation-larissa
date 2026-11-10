class_name TestModManifest
extends GdUnitTestSuite
## Teaches: a manifest entry that names code is validated by naming each rule once (`ModSpec.parse`), then checked again where the files are (`PackCheck`): the entry script is a
## plain `.sgd` file name, the API version it needs is one the game provides, its limits are lowered to the game's ceilings and never raised, and a pack that is not trusted
## holds no code but `.sgd`. Every mistake is a sentence, not a crash. These tests need the godot-sandbox extension for the packs they open (`uv run tools/fetch_sandbox.py`).

const FIXTURES := "res://tests/mods"

var _shelves: Array[PackShelf] = []


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func after_test() -> void:
	ModLoader.pretend_no_sandbox = false
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()


func _parse(data: Variant) -> Array:
	var errors: Array[String] = []
	var spec := ModSpec.parse(data, errors)
	return [spec, errors]


func _shelf(mod: Dictionary = {}) -> PackShelf:
	var shelf := PackShelf.new()
	shelf.add_mod_fixture("%s/hello" % FIXTURES, mod)
	_shelves.append(shelf)
	return shelf


func _report(shelf: PackShelf) -> PackReport:
	var options := PackCheck.Options.new()
	options.reach = false
	return PackCheck.run(Pack.open(shelf.root), options)


func _says(report: PackReport, severity: PackReport.Severity, fragment: String) -> bool:
	return report.findings.any(func(f: PackReport.Finding) -> bool: return f.severity == severity and f.message.contains(fragment))


# --- ModSpec ---------------------------------------------------------------------------------------------------------------

func test_a_plain_entry_is_a_mod_with_the_ceilings_as_its_limits() -> void:
	var got := _parse({"entry": "orchard.sgd"})
	var spec: ModSpec = got[0]
	assert_array(got[1]).is_empty()
	assert_str(spec.entry).is_equal("orchard.sgd")
	assert_int(spec.requires_api).is_equal(1)
	assert_int(spec.limits["execution_timeout"]).is_equal(ModSpec.MAX_EXECUTION_TIMEOUT)
	assert_int(spec.limits["memory_max"]).is_equal(ModSpec.MAX_MEMORY)
	assert_dict(spec.to_dict()).is_equal({"entry": "orchard.sgd"})


func test_limits_are_lowered_never_raised() -> void:
	var spec: ModSpec = _parse({"entry": "a.sgd", "limits": {"execution_timeout": 0, "memory_max": 4, "allocations_max": 999999, "references_max": 0, "coroutines_max": -5}})[0]
	assert_int(spec.limits["execution_timeout"]).is_equal(1)                                  # (0 would be no instruction counting: never; it is the lowest limit)
	assert_int(spec.limits["memory_max"]).is_equal(4)
	assert_int(spec.limits["allocations_max"]).is_equal(ModSpec.MAX_ALLOCATIONS)             # (a request over the ceiling is the ceiling)
	assert_int(spec.limits["references_max"]).is_equal(1)                                    # (the others are at least 1)
	assert_int(spec.limits["coroutines_max"]).is_equal(1)
	assert_dict(spec.to_dict()["limits"]).is_equal({"execution_timeout": 1, "memory_max": 4, "references_max": 1, "coroutines_max": 1})
	var round_trip: ModSpec = _parse(spec.to_dict())[0]
	assert_dict(round_trip.limits).is_equal(spec.limits)


func test_every_mistake_in_the_entry_is_a_sentence() -> void:
	var bad := {
		"not an object": "orchard.sgd",
		"no entry": {},
		"empty entry": {"entry": ""},
		"entry not a string": {"entry": 3},
		"a folder": {"entry": "mods/orchard.sgd"},
		"climbing out": {"entry": "../orchard.sgd"},
		"a backslash": {"entry": "mods\\orchard.sgd"},
		"a GDScript": {"entry": "orchard.gd"},
		"no name": {"entry": ".sgd"},
		"a drive": {"entry": "c:orchard.sgd"},
		"a key it does not know": {"entry": "a.sgd", "scripts": ["b.sgd"]},
		"api from the future": {"entry": "a.sgd", "requires_api": ModSpec.API_VERSION + 1},
		"api zero": {"entry": "a.sgd", "requires_api": 0},
		"api a word": {"entry": "a.sgd", "requires_api": "one"},
		"api a fraction": {"entry": "a.sgd", "requires_api": 1.5},
		"limits not an object": {"entry": "a.sgd", "limits": 5},
		"a limit it does not know": {"entry": "a.sgd", "limits": {"cpu": 5}},
		"a limit not a number": {"entry": "a.sgd", "limits": {"memory_max": "big"}},
	}
	for what: String in bad:
		var got := _parse(bad[what])
		assert_object(got[0]).override_failure_message("%s was accepted" % what).is_null()
		assert_array(got[1]).override_failure_message("%s gave no sentence" % what).is_not_empty()


func test_a_whole_float_is_a_whole_number() -> void:
	var spec: ModSpec = _parse({"entry": "a.sgd", "requires_api": 1.0, "limits": {"memory_max": 8.0}})[0]                # (JSON numbers are floats)
	assert_object(spec).is_not_null()
	assert_int(spec.limits["memory_max"]).is_equal(8)


# --- Pack ------------------------------------------------------------------------------------------------------------------

func test_a_pack_reads_its_mod_entry_and_writes_it_back() -> void:
	var shelf := _shelf({"requires_api": 1, "limits": {"memory_max": 4}})
	var pack := Pack.open(shelf.root)
	assert_array(pack.errors).is_empty()
	assert_str(pack.mod.entry).is_equal("hello.sgd")
	assert_int(pack.mod.limits["memory_max"]).is_equal(4)
	assert_dict(pack.manifest()["mod"]).is_equal({"entry": "hello.sgd", "limits": {"memory_max": 4}})


func test_a_pack_with_a_bad_mod_entry_has_errors_and_cannot_be_chosen() -> void:
	var shelf := _shelf({"entry": "../hello.sgd"})
	var pack := Pack.open(shelf.root)
	assert_array(pack.errors).is_not_empty()
	assert_bool(pack.is_valid()).is_false()
	assert_object(shelf.mount()).is_null()


func test_a_pack_that_needs_a_newer_api_is_refused_with_both_numbers() -> void:
	var pack := Pack.open(_shelf({"requires_api": 99}).root)
	assert_str(pack.errors[0]).contains("99").contains(str(ModSpec.API_VERSION))


func test_no_extension_means_a_manifest_error_that_says_how_to_get_it() -> void:
	var shelf := _shelf()
	ModLoader.pretend_no_sandbox = true
	var pack := Pack.open(shelf.root)
	assert_array(pack.errors).is_equal([ModLoader.missing_extension_text()])
	assert_str(pack.errors[0]).contains("fetch_sandbox")
	var data_pack := PackShelf.new()                                                          # (a data pack never needs the extension)
	_shelves.append(data_pack)
	assert_array(Pack.open(data_pack.root).errors).is_empty()


func test_a_pack_that_is_not_trusted_holds_sgd_and_no_other_code() -> void:
	var shelf := _shelf()
	assert_array(Pack.open(shelf.root).problems()).is_empty()                                 # (the .sgd is no resource of the game)
	for name in ["x.gd", "x.gdc", "x.cs", "x.tscn", "x.tres", "x.gdextension", "x.so", "x.dll", "x.dylib", "x.elf", "x.pck", "x.wasm"]:
		shelf.write_bytes(name, PackedByteArray([1]))
		var problems := Pack.open(shelf.root).problems()
		assert_array(problems).override_failure_message("%s was accepted" % name).is_not_empty()
		DirAccess.remove_absolute("%s/%s" % [shelf.root, name])
	assert_array(Pack.open(shelf.root).problems()).is_empty()


func test_a_pack_does_not_make_itself_trusted_by_having_a_mod() -> void:
	assert_bool(Pack.open(_shelf().root).trusted).is_false()


# --- PackCheck -------------------------------------------------------------------------------------------------------------

func test_a_sound_mod_pack_passes_the_check() -> void:
	var report := _report(_shelf())
	assert_bool(report.passes()).override_failure_message(report.text()).is_true()
	assert_array(report.warnings()).override_failure_message(report.text()).is_empty()       # (a pack of nothing but a mod is not "a pack that holds nothing")


func test_the_check_names_a_missing_or_broken_entry_script() -> void:
	var missing := _shelf()
	DirAccess.remove_absolute("%s/hello.sgd" % missing.root)
	assert_bool(_says(_report(missing), PackReport.Severity.ERROR, "hello.sgd is not in the pack")).is_true()
	var empty := _shelf()
	empty.write_text("hello.sgd", "  \n")
	assert_bool(_says(_report(empty), PackReport.Severity.ERROR, "empty")).is_true()
	var no_init := _shelf()
	no_init.write_text("hello.sgd", "func other():\n\tpass\n")
	assert_bool(_says(_report(no_init), PackReport.Severity.ERROR, "mod_init")).is_true()
	var huge := _shelf()
	huge.write_text("hello.sgd", "func mod_init(a):\n\tpass\n" + "#".repeat(ModSpec.MAX_SOURCE_BYTES))
	assert_bool(_says(_report(huge), PackReport.Severity.ERROR, "larger than")).is_true()


func test_the_check_warns_of_a_script_that_is_never_run() -> void:
	var extra := _shelf()
	extra.write_text("other.sgd", "func mod_init(a):\n\tpass\n")
	var report := _report(extra)
	assert_bool(report.passes()).is_true()
	assert_bool(_says(report, PackReport.Severity.WARNING, "other.sgd is never run")).is_true()
	var no_mod := PackShelf.new()
	_shelves.append(no_mod)
	no_mod.write_text("lonely.sgd", "func mod_init(a):\n\tpass\n")
	no_mod.write_text("texts.json", "{}")
	assert_bool(_says(_report(no_mod), PackReport.Severity.WARNING, "lonely.sgd is never run")).is_true()


func test_the_check_reports_the_manifest_error_of_a_bad_entry() -> void:
	var report := _report(_shelf({"entry": "dir/hello.sgd"}))
	assert_bool(report.passes()).is_false()
	assert_bool(_says(report, PackReport.Severity.ERROR, "plain file name")).is_true()
