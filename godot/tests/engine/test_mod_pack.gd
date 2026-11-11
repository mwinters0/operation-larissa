class_name TestModPack
extends GdUnitTestSuite
## Teaches: the whole life of a mod pack, with a real mod from `tests/mods/`: a well-formed one is loaded from the chain, logs and loads a file of its own pack; the mods
## are DERIVED from the chain (`ModHost.sync`: another chain, another set; a pack borrowed and put back costs no reload); a faulty one is quarantined and the rest go on; a
## mod over its limits is stopped. The hostile mod (`tests/mods/hostile`, adapted from godot-sandbox's audit mod) tries every escape of the sandbox, and each attempt must be
## refused and leave the game as it was (`test_a_hostile_mod_is_contained`, `test_the_api_answers_a_hostile_mod_with_nothing`).
## These tests need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`, docs/SETUP.md).

const FIXTURES := "res://tests/mods"
const DOT := "pictures/ui_picture/dot.png"

var _shelves: Array[PackShelf] = []
var _messages: Array[String] = []


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func after_test() -> void:
	ModLoader.pretend_no_sandbox = false
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	Mods.sync()


## A mod pack from the fixture `name`, over the pack the suite runs on (or over `base`), chosen with `Packs.use` and synced.
func _mod_pack(name: String, base: StringName = &"", mod: Dictionary = {}) -> PackShelf:
	var shelf := PackShelf.new(&"", base)
	shelf.add_mod_fixture("%s/%s" % [FIXTURES, name], mod)
	shelf.add_picture(DOT, Color.RED)
	_shelves.append(shelf)
	assert_object(shelf.mount()).override_failure_message("the mod pack '%s' cannot be used: %s" % [name, Pack.open(shelf.root).errors]).is_not_null()
	Mods.sync()
	return shelf


func _mod(shelf: PackShelf) -> Node:
	return ModHost.mod(String(shelf.id))


func _no_new_faults(mod: Node, body: Callable) -> bool:
	var before := int(mod.get("monitor_exceptions"))
	body.call()
	return int(mod.get("monitor_exceptions")) == before


# --- a well-formed mod --------------------------------------------------------------------------------------------

func test_a_mod_pack_is_loaded_from_the_chain_and_can_log() -> void:
	_messages.clear()
	Mods.mod_logged.connect(func(id: String, text: String) -> void: _messages.append("%s: %s" % [id, text]))
	var shelf := _mod_pack("hello")
	assert_array(Mods.loaded_ids()).contains([String(shelf.id)])
	assert_str(ModHost.failure(String(shelf.id))).is_empty()
	assert_array(_messages).contains(["%s: hello from %s" % [shelf.id, shelf.id]])
	var mod := _mod(shelf)
	mod.call("say", "second\u001b[31m message")
	assert_str(_messages.back()).override_failure_message("a control character reached the log: %s" % _messages.back()).is_equal("%s: second [31m message" % shelf.id)
	assert_int(mod.call("api_version")).is_equal(ModSpec.API_VERSION)
	var keys: Array = mod.call("api_keys")
	keys.sort()
	assert_array(keys).is_equal(["api_version", "id", "load", "log"])


func test_a_mod_loads_a_file_of_its_own_pack_through_the_door() -> void:
	var shelf := _mod_pack("hello")
	var mod := _mod(shelf)
	var got: Variant = mod.call("picture", DOT)
	assert_object(got).is_instanceof(Texture2D)
	assert_object(got).is_same(shelf.pack.texture(DOT))                    # (the object the door made, not a second copy)
	assert_object(mod.call("picture", "pictures/ui_picture/none.png")).is_null()
	for i in 2:                                                              # (a file the pack lacks, and a path that is none: told once each)
		mod.call("picture", "pictures/ui_picture/none.png")
		mod.call("picture", "../outside.png")
	var told := TroubleLog.session.told.filter(func(line: String) -> bool: return line.contains("mod '%s'" % shelf.id))
	assert_array(told).has_size(2)
	assert_str(told[0]).contains("asks to load 'pictures/ui_picture/none.png', which its pack does not hold")
	assert_str(told[1]).contains("asks to load ../outside.png, which is no path inside its pack")


func test_the_limits_of_a_manifest_are_clamped_to_the_ceilings() -> void:
	var shelf := _mod_pack("hostile")
	var mod := _mod(shelf)
	assert_bool(mod.get("restrictions")).is_true()
	assert_int(mod.get("execution_timeout")).is_equal(ModSpec.MAX_EXECUTION_TIMEOUT)
	assert_int(mod.get("memory_max")).is_equal(ModSpec.MAX_MEMORY)
	assert_int(mod.get("allocations_max")).is_equal(ModSpec.MAX_ALLOCATIONS)
	assert_int(mod.get("references_max")).is_equal(ModSpec.MAX_REFERENCES)
	assert_int(mod.get("coroutines_max")).is_equal(ModSpec.MAX_COROUTINES)
	var lowered := _mod_pack("hello")
	assert_int(_mod(lowered).get("execution_timeout")).is_equal(50)        # (a manifest may lower a limit)
	assert_int(_mod(lowered).get("memory_max")).is_equal(8)


# --- the mods are derived from the chain -----------------------------------------------------------------------------

func test_the_loaded_mods_are_the_mods_of_the_chain() -> void:
	var below := _mod_pack("hello")
	var above := _mod_pack("faulty", below.id)
	assert_array(Packs.chain_ids().slice(0, 2)).is_equal([above.id, below.id])
	assert_array(Mods.loaded_ids()).is_equal([String(below.id), String(above.id)])       # (the bottom of the chain first)
	var mod_below := _mod(below)
	Packs.use(Pack.open(below.root))                                                       # another chain: the pack above leaves
	Mods.sync()
	assert_array(Mods.loaded_ids()).is_equal([String(below.id)])
	assert_object(_mod(below)).is_same(mod_below)                                          # (what stays in the chain is not loaded again)
	Packs.use(Pack.open(above.root))
	Mods.sync()
	assert_array(Mods.loaded_ids()).is_equal([String(below.id), String(above.id)])
	Packs.start()                                                                          # the suite's own pack again: no mod
	Mods.sync()
	assert_array(Mods.loaded_ids()).is_empty()


func test_a_pack_borrowed_and_put_back_inside_one_call_costs_no_reload() -> void:
	var shelf := _mod_pack("hello")
	var mod := _mod(shelf)
	var saved := Packs.snapshot()
	Packs.use(Pack.open(PackShelf.new(&"", &"").root))                                    # (a check borrows the chain ...)
	Packs.restore(saved)                                                                   # (... and gives it back)
	Mods.sync()
	assert_object(_mod(shelf)).is_same(mod)
	assert_bool(is_instance_valid(mod)).is_true()


func test_a_changed_script_is_loaded_again() -> void:
	var shelf := _mod_pack("hello")
	var first := _mod(shelf)
	var path := "%s/hello.sgd" % shelf.root
	var stamp := FileAccess.get_modified_time(path)
	OS.delay_msec(1100)                                                                    # (the key reads the file's time, in whole seconds)
	shelf.write_text("hello.sgd", FileAccess.get_file_as_string(path) + "\n# edited\n")
	assert_int(FileAccess.get_modified_time(path)).is_greater(stamp)
	Packs.refresh()
	Mods.sync()
	assert_object(_mod(shelf)).is_not_null()
	assert_bool(is_instance_valid(first)).is_false()                                       # (the old one was unloaded)


func test_a_dirtied_host_is_rebuilt_from_the_chain_by_one_sync() -> void:
	var shelf := _mod_pack("hello")
	var mod := _mod(shelf)
	Mods._failed["ghost"] = {"key": "gone", "reason": "left over"}
	Mods._reported["ghost"] = true
	Mods._stale = false
	Mods.sync()
	assert_dict(Mods._failed).is_empty()
	assert_dict(Mods._reported).is_empty()
	assert_array(Mods.loaded_ids()).is_equal([String(shelf.id)])
	assert_object(_mod(shelf)).is_same(mod)


func test_a_script_that_does_not_load_is_refused_with_its_reason_and_the_others_go_on() -> void:
	var good := _mod_pack("hello")
	var broken := PackShelf.new(&"", good.id)
	_shelves.append(broken)
	broken.add_mod_fixture("%s/hello" % FIXTURES)
	broken.write_text("hello.sgd", "func mod_init(a):\n\tthis is not code\n")
	assert_object(broken.mount()).is_not_null()                                            # (the pack is sound: only the Sandbox can tell the script is not)
	Mods.sync()
	assert_array(Mods.loaded_ids()).is_equal([String(good.id)])
	assert_str(ModHost.failure(String(broken.id))).contains("did not compile")
	var elsewhere := PackShelf.new(&"", good.id)
	_shelves.append(elsewhere)
	elsewhere.add_mod_fixture("%s/hello" % FIXTURES)
	elsewhere.write_text("hello.sgd", "func not_a_mod():\n\tpass\n")
	elsewhere.mount()
	Mods.sync()
	assert_str(ModHost.failure(String(elsewhere.id))).contains("mod_init")


# --- faults and limits -----------------------------------------------------------------------------------------------

func test_a_faulty_mod_is_quarantined_and_the_other_mods_go_on() -> void:
	var good := _mod_pack("hello")
	var bad := _mod_pack("faulty", good.id)
	var loader := Mods.loader()
	var mod := _mod(bad)
	for i in ModLoader.MAX_FAULTS:
		mod.call("boom")
	loader.check_health()
	assert_bool(ModHost.is_quarantined(String(bad.id))).is_true()
	assert_bool(ModHost.is_quarantined(String(good.id))).is_false()
	assert_str(_mod(good).call("api_keys")[0]).is_not_empty()                              # the good mod still answers
	loader.resume(String(bad.id))
	assert_bool(ModHost.is_quarantined(String(bad.id))).is_false()


func test_a_mod_over_its_limits_is_stopped_and_stays_loaded() -> void:
	var shelf := _mod_pack("spinner")
	var mod := _mod(shelf)
	var timeouts := int(mod.get("monitor_execution_timeouts"))
	var faults := int(mod.get("monitor_exceptions"))
	mod.call("spin")                                                                       # (an endless loop: stopped by the instruction limit)
	assert_int(mod.get("monitor_execution_timeouts")).is_equal(timeouts + 1)
	assert_int(mod.get("monitor_exceptions")).is_greater(faults)
	faults = int(mod.get("monitor_exceptions"))
	mod.call("recurse")                                                                    # (a call chain that outgrows the memory the manifest allows)
	assert_int(mod.get("monitor_exceptions")).is_greater(faults)
	assert_int(mod.get("monitor_execution_timeouts")).is_equal(timeouts + 1)             # (the second was no timeout: it ran out of memory)
	assert_str(mod.call("fine")).is_equal("still here")
	Mods.loader().forgive(String(shelf.id))


func test_a_mod_that_asks_for_no_instruction_limit_gets_the_lowest_and_a_spinning_process_is_stopped() -> void:
	var shelf := _mod_pack("process_spinner")                                              # (its manifest says "execution_timeout": 0)
	var mod := _mod(shelf)
	assert_int(shelf.pack.mod.limits["execution_timeout"]).is_equal(1)
	assert_int(mod.get("execution_timeout")).is_equal(1)
	var timeouts := int(mod.get("monitor_execution_timeouts"))
	mod.call("_process", 0.0)                                                              # (never returns on its own: the Sandbox stops it)
	assert_int(mod.get("monitor_execution_timeouts")).is_greater(timeouts)
	assert_str(mod.call("fine")).is_equal("still here")
	Mods.loader().forgive(String(shelf.id))


# --- the hostile mod -----------------------------------------------------------------------------------------------------

## Everything a game can observe of itself that a mod must not change.
func _game_fingerprint() -> Dictionary:
	var root := get_tree().root
	return {
		"root_name": root.name,
		"root_children": root.get_children().map(func(child: Node) -> String: return child.name),
		"chain": Packs.chain_ids(),
		"oxygen": GameState.oxygen,
		"tanks": GameState.tanks,
		"sector": GameState.sector,
		"ink": GameState.ink,
		"mods": Mods.loaded_ids(),
	}


func test_a_hostile_mod_is_contained() -> void:
	var shelf := _mod_pack("hostile")
	var mod := _mod(shelf)
	assert_object(mod).is_not_null()
	var before := _game_fingerprint()
	var attempts := 0
	for method in mod.get_method_list():
		var attempt: String = method["name"]
		if not attempt.begins_with("try_"):
			continue
		attempts += 1
		var faults := int(mod.get("monitor_exceptions"))
		var result: Variant = mod.call(attempt)
		assert_bool(int(mod.get("monitor_exceptions")) > faults) \
				.override_failure_message("%s was not refused: %s" % [attempt, result]).is_true()
	assert_int(attempts).is_greater_equal(25)
	assert_dict(_game_fingerprint()).is_equal(before)
	assert_str(String(mod.name)).is_equal(String(shelf.id))                                # (it did not rename its own node)
	Mods.loader().forgive(String(shelf.id))
	assert_bool(ModHost.is_quarantined(String(shelf.id))).is_false()
	assert_array(Mods.loaded_ids()).contains([String(shelf.id)])                           # ("the mod is still running": the game decides what to do with it)


func test_the_api_answers_a_hostile_mod_with_nothing() -> void:
	var shelf := _mod_pack("hostile")
	var mod := _mod(shelf)
	var faults := int(mod.get("monitor_exceptions"))
	var checked := 0
	for method in mod.get_method_list():
		var name: String = method["name"]
		if not name.begins_with("check_"):
			continue
		checked += 1
		var result: Variant = mod.call(name)
		if name == "check_load_own_picture":
			assert_object(result).is_instanceof(Texture2D)                                 # (what it is entitled to)
		elif name == "check_bound_arguments":
			assert_array(result).is_equal([String(shelf.id)])                              # (only its own id: the game binds nothing else to a granted Callable)
		else:
			assert_object(result).override_failure_message("%s got %s" % [name, result]).is_null()
	assert_int(checked).is_greater_equal(10)
	assert_int(mod.get("monitor_exceptions")).is_equal(faults)                              # (nothing raised: the API just has nothing to give)


func test_the_mod_api_is_read_only() -> void:
	var shelf := _mod_pack("hello")
	var api: Dictionary = ModApi.new(Mods.loader()).build("x", shelf.pack)
	ModLoader.freeze(api)
	assert_bool(api.is_read_only()).is_true()
	assert_bool(ModLoader.detach({"a": [1]}) is Dictionary).is_true()
	var inner := {"a": [1]}
	var copy: Dictionary = ModLoader.detach(inner)
	(copy["a"] as Array).append(2)
	assert_array(inner["a"]).is_equal([1])


# --- a build without the extension ----------------------------------------------------------------------------------

func test_a_build_without_the_extension_refuses_a_mod_pack_and_does_not_crash() -> void:
	var shelf := PackShelf.new()
	shelf.add_mod_fixture("%s/hello" % FIXTURES)
	_shelves.append(shelf)
	ModLoader.pretend_no_sandbox = true
	var pack := Pack.open(shelf.root)
	assert_array(pack.errors).contains([ModLoader.missing_extension_text()])
	assert_bool(pack.is_valid()).is_false()
	assert_object(shelf.mount()).is_null()                                                # (the chain cannot be made with it)
	assert_bool(Packs.chain_ids().has(shelf.id)).is_false()
	assert_str(Packs.fallback_reason().text()).contains("cannot be used")
	assert_array(Mods.loaded_ids()).is_empty()
	assert_array(PackCheck.run(pack).errors()).is_not_empty()
	ModLoader.pretend_no_sandbox = false
	assert_bool(Pack.open(shelf.root).is_valid()).is_true()                                 # (with the extension, the same folder is a pack)
