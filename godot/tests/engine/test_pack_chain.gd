class_name TestPackChain
extends GdUnitTestSuite
## Teaches: how the game chooses its packs. One pack is chosen (`--pack=<id>`, else the first pack found in the order of the ids) and the packs it is
## laid over follow (`"base"` in the manifest); a thing is asked of the chain from the top and the first pack that has it wins. When the chain cannot be made, `dev`
## goes at the bottom and `Packs.fallback_reason()` says why. This suite makes its own packs in a scratch folder that stands in for the
## folders packs are found in (`Packs.folders`), so it needs no original game and skips nothing.

var _scratch: String
var _real_folders: Array[String]


func before_test() -> void:
	_scratch = "user://test_chain_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_scratch)
	_real_folders = Packs.folders.duplicate()


func after_test() -> void:
	Packs.folders = _real_folders
	PackFiles.remove_tree(_scratch)
	Packs.start()                                            # (the command-line choice again: no test of this suite leaves a choice of its own behind)


## A pack called `id` in the scratch folder, laid over `base` (none when empty), with the files `rel -> text` given.
func _pack(id: String, base := "", files: Dictionary = {}) -> void:
	var manifest := {"id": id, "title": "Test %s" % id, "version": "1"}
	if not base.is_empty():
		manifest["base"] = base
	PackFiles.write_text("%s/%s/pack.json" % [_scratch, id], JSON.stringify(manifest))
	for rel: String in files:
		PackFiles.write_text("%s/%s/%s" % [_scratch, id, rel], files[rel])


func _only_the_scratch_folder() -> void:
	Packs.folders = [_scratch]


# --- finding and choosing -------------------------------------------------------------------------------------------------

func test_without_an_option_the_first_pack_found_in_the_order_of_the_ids_is_chosen() -> void:
	_pack("zebra", "dev")
	_pack("apple", "dev")
	_pack("mango", "dev")
	_only_the_scratch_folder()
	assert_array(Packs.available().map(func(p: Pack) -> StringName: return p.id)).is_equal([&"apple", &"mango", &"zebra"])
	assert_bool(Packs.choose()).is_true()
	assert_array(Packs.chain_ids()).is_equal([&"apple", Packs.DEV])
	assert_object(Packs.fallback_reason()).is_null()
	assert_str(Packs.asked()).is_equal(&"")


func test_the_option_pack_chooses_among_the_packs_found() -> void:
	_pack("apple", "dev")
	_pack("zebra", "dev")
	_only_the_scratch_folder()
	Packs.start(PackedStringArray(["--something-else", "--pack=zebra"]))
	assert_array(Packs.chain_ids()).is_equal([&"zebra", Packs.DEV])
	assert_str(Packs.asked()).is_equal(&"zebra")
	assert_object(Packs.fallback_reason()).is_null()
	Packs.reset()                                            # the same choice again
	assert_array(Packs.chain_ids()).is_equal([&"zebra", Packs.DEV])


func test_the_default_choice_on_this_machine_is_the_first_pack_of_the_project_or_the_users_folder() -> void:
	var expected: Array = Packs.available().map(func(p: Pack) -> StringName: return p.id)
	Packs.start(PackedStringArray())
	if expected.is_empty():
		assert_array(Packs.chain_ids()).is_equal([Packs.DEV])
	else:
		assert_str(Packs.chosen().id).is_equal(expected[0])


func test_the_only_pack_found_with_no_base_is_chosen_alone_and_asked_what_it_holds() -> void:
	# a pack with no "base" is complete. This one is only a manifest, so it is chosen and then found incomplete (the start-up check, `test_pack_start_check.gd`): dev under it,
	# or nothing in a release build.
	var project_scratch := "user://test_chain_alone_%d" % Time.get_ticks_usec()
	PackFiles.write_text(project_scratch + "/alone/pack.json", JSON.stringify({"id": "alone", "title": "Alone", "version": "1", "format": 1}))
	Packs.folders = [project_scratch]
	var real_mode := Packs.dev_fallback
	var ids: Array = Packs.available().map(func(p: Pack) -> StringName: return p.id)
	Packs.dev_fallback = true
	var chosen := Packs.choose()                              # no --pack: the lexical default
	var chain: Array = Packs.chain_ids()
	var reason := Packs.fallback_reason()
	Packs.dev_fallback = false
	Packs.choose()
	var refused_chain: Array = Packs.chain_ids()
	Packs.dev_fallback = real_mode
	PackFiles.remove_tree(project_scratch)
	assert_array(ids).is_equal([&"alone"])
	assert_bool(chosen).is_false()
	assert_array(chain).is_equal([&"alone", Packs.DEV])
	assert_int(reason.why).is_equal(Packs.Fallback.Why.MISSING_ASSETS)
	assert_array(refused_chain).is_equal([&"alone"])          # nothing is put under it in a release build
	Packs.folders = _real_folders


func test_a_chain_follows_the_bases_down_to_a_pack_with_none() -> void:
	_pack("top", "middle")
	_pack("middle", "bottom")
	_pack("bottom", "dev")
	_only_the_scratch_folder()
	assert_bool(Packs.choose(&"top")).is_true()
	assert_array(Packs.chain_ids()).is_equal([&"top", &"middle", &"bottom", Packs.DEV])
	assert_object(Packs.fallback_reason()).is_null()
	assert_str(Packs.pack(&"middle").base).is_equal(&"bottom")


func test_the_project_wins_when_the_same_id_is_in_both_places() -> void:
	var project_copy := "%s/test_both" % Packs.PROJECT_PACKS_DIR
	var user_copy := "%s/test_both" % Packs.USER_PACKS_DIR
	PackFiles.write_text(project_copy + "/pack.json", JSON.stringify({"id": "test_both", "title": "In the project", "version": "1", "base": "dev"}))
	PackFiles.write_text(user_copy + "/pack.json", JSON.stringify({"id": "test_both", "title": "In the user folder", "version": "1", "base": "dev"}))
	var listed: Array = Packs.available().filter(func(p: Pack) -> bool: return p.id == &"test_both")
	PackFiles.remove_tree(project_copy)
	PackFiles.remove_tree(user_copy)
	assert_array(listed).has_size(1)
	assert_str(listed[0].title).is_equal("In the project")


# --- dev ----------------------------------------------------------------------------------------------------------------

func test_dev_is_the_pack_of_the_project_and_never_offered() -> void:
	assert_str(Packs.dev().root).is_equal("res://packs/dev")
	assert_array(Packs.available().map(func(p: Pack) -> StringName: return p.id)).not_contains([Packs.DEV])


func test_a_dev_in_the_users_folder_is_left_out_and_the_reason_is_kept() -> void:
	_pack("dev", "")
	_pack("other", "dev")
	Packs.folders = [Packs.PROJECT_PACKS_DIR, _scratch]
	var ids: Array = Packs.available().map(func(p: Pack) -> StringName: return p.id)
	assert_array(ids).contains([&"other"]).not_contains([Packs.DEV])
	assert_array(Packs.ignored()).has_size(1)
	assert_str(Packs.ignored()[0]).contains("'dev'").contains("reserved for the dev pack").contains("id of your own")
	assert_str(Packs.dev().root).is_equal("res://packs/dev")             # the shipped one is the one that is used
	assert_bool(Packs.choose(Packs.DEV)).is_true()
	assert_str(Packs.chosen().root).is_equal("res://packs/dev")


func test_choosing_dev_on_purpose_is_no_fallback() -> void:
	_only_the_scratch_folder()
	assert_bool(Packs.choose(Packs.DEV)).is_true()
	assert_array(Packs.chain_ids()).is_equal([Packs.DEV])
	assert_object(Packs.fallback_reason()).is_null()
	Packs.start(PackedStringArray(["--pack=dev"]))
	assert_array(Packs.chain_ids()).is_equal([Packs.DEV])
	assert_object(Packs.fallback_reason()).is_null()


# --- when the chain cannot be made ---------------------------------------------------------------------------------------

func test_no_pack_at_all_leaves_dev_alone_and_says_so() -> void:
	_only_the_scratch_folder()
	assert_bool(Packs.choose()).is_false()
	assert_array(Packs.chain_ids()).is_equal([Packs.DEV])
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.NO_PACK)
	assert_str(Packs.fallback_reason().text()).contains("No pack was found").contains("dev")


func test_a_pack_asked_for_that_is_not_there_leaves_dev_alone() -> void:
	_pack("apple", "dev")
	_only_the_scratch_folder()
	Packs.start(PackedStringArray(["--pack=nope"]))
	assert_array(Packs.chain_ids()).is_equal([Packs.DEV])
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.NOT_FOUND)
	assert_str(Packs.fallback_reason().pack_id).is_equal(&"nope")
	assert_str(Packs.fallback_reason().text()).contains("'nope'")


func test_a_missing_base_puts_dev_under_the_chain_found() -> void:
	_pack("top", "middle")
	_pack("middle", "ghost")
	_only_the_scratch_folder()
	assert_bool(Packs.choose(&"top")).is_false()
	assert_array(Packs.chain_ids()).is_equal([&"top", &"middle", Packs.DEV])
	var reason := Packs.fallback_reason()
	assert_int(reason.why).is_equal(Packs.Fallback.Why.MISSING_BASE)
	assert_str(reason.pack_id).is_equal(&"middle")
	assert_str(reason.detail).is_equal("ghost")
	assert_str(reason.text()).contains("'middle'").contains("'ghost'")


func test_bases_that_go_round_in_a_circle_put_dev_under_the_chain_found() -> void:
	_pack("one", "two")
	_pack("two", "one")
	_only_the_scratch_folder()
	assert_bool(Packs.choose(&"one")).is_false()
	assert_array(Packs.chain_ids()).is_equal([&"one", &"two", Packs.DEV])
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.CYCLE)
	assert_str(Packs.fallback_reason().pack_id).is_equal(&"one")


func test_a_pack_with_no_base_is_complete_so_it_is_asked_for_everything_and_dev_is_put_under_it() -> void:
	_pack("lonely", "")
	_only_the_scratch_folder()
	assert_bool(Packs.choose(&"lonely")).is_false()
	assert_array(Packs.chain_ids()).is_equal([&"lonely", Packs.DEV])
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.MISSING_ASSETS)
	assert_bool(Packs.fallback_reason().complete_pack).is_true()


func test_a_pack_with_errors_is_listed_but_never_the_default_and_cannot_be_used() -> void:
	PackFiles.write_text("%s/broken/pack.json" % _scratch, "{\"id\": \"broken\"}")
	_pack("fine", "dev")
	_only_the_scratch_folder()
	assert_array(Packs.available().map(func(p: Pack) -> StringName: return p.id)).contains([&"fine"])
	Packs.choose()
	assert_array(Packs.chain_ids()).is_equal([&"fine", Packs.DEV])
	assert_object(Packs.fallback_reason()).is_null()


func test_a_manifest_base_must_be_a_pack_id_and_not_the_pack_itself() -> void:
	_pack("selfish", "selfish")
	_pack("loud", "Not An Id")
	_only_the_scratch_folder()
	assert_str("\n".join(Pack.open(_scratch + "/selfish").errors)).contains("cannot be its own base")
	assert_str("\n".join(Pack.open(_scratch + "/loud").errors)).contains("is not a pack id")
	PackFiles.write_text(_scratch + "/numeric/pack.json", JSON.stringify({"id": "numeric", "title": "N", "version": "1", "base": true}))
	assert_str("\n".join(Pack.open(_scratch + "/numeric").errors)).contains("\"base\" must be a string")
	assert_str(Pack.open(_scratch + "/selfish").manifest().get("base", "")).is_equal("selfish")


# --- lookups down the chain -------------------------------------------------------------------------------------------------

func test_a_whole_file_comes_from_the_first_pack_of_the_chain_that_has_it() -> void:
	_pack("top", "bottom", {"assets/both.png": "top's", "assets/top_only.png": "x"})
	_pack("bottom", "dev", {"assets/both.png": "bottom's", "assets/bottom_only.png": "y"})
	_only_the_scratch_folder()
	Packs.choose(&"top")
	assert_str(Packs.path("assets/both.png")).is_equal(_scratch + "/top/assets/both.png")
	assert_str(Packs.path("assets/top_only.png")).is_equal(_scratch + "/top/assets/top_only.png")
	assert_str(Packs.path("assets/bottom_only.png")).is_equal(_scratch + "/bottom/assets/bottom_only.png")
	assert_object(Packs.holder("assets/both.png")).is_same(Packs.pack(&"top"))
	assert_bool(Packs.has("assets/bottom_only.png")).is_true()
	assert_bool(Packs.has("assets/nobody.png")).is_false()
	assert_object(Packs.holder("assets/nobody.png")).is_null()
	assert_str(Packs.path("assets/nobody.png")).is_equal(Packs.chain().back().path_of("assets/nobody.png"))      # named in the bottom pack, for the message
	Packs.choose(&"bottom")
	assert_str(Packs.path("assets/both.png")).is_equal(_scratch + "/bottom/assets/both.png")


func test_a_data_pack_never_answers_for_a_resource_file_only_for_its_data_form() -> void:
	_pack("top", "dev", {"data/zones.tres": "[gd_resource type=\"Resource\" format=3]\n", "data/bubble_rules.tres": "[gd_resource type=\"Resource\" format=3]\n",
			"data/bubble_rules.json": "{}"})
	_only_the_scratch_folder()
	Packs.choose(&"top")
	assert_bool(Packs.chain()[0].has("data/zones.tres")).is_true()
	assert_object(Packs.holder("data/zones.tres")).is_not_same(Packs.chain()[0])         # it has the file, it does not provide it
	assert_object(Packs.holder("data/bubble_rules.tres")).is_same(Packs.chain()[0])      # it has the data form of it, which it does
	assert_object(Packs.holder("data/bubble_rules.json")).is_same(Packs.chain()[0])


func test_the_path_in_a_pack_folder_of_the_project_is_made_relative() -> void:
	assert_str(Packs.relative("res://packs/another/data/zones.tres")).is_equal("data/zones.tres")
	assert_str(Packs.relative("res://packs/dev/assets/ui/hud/x.png")).is_equal("assets/ui/hud/x.png")
	assert_str(Packs.relative("res://data/ui/menu_layout.tres")).is_empty()
	assert_str(Packs.relative("res://packs/another")).is_empty()


func test_a_data_pack_in_the_middle_of_a_chain_still_answers_its_kinds_of_lookup() -> void:
	_pack("top", "middle", {"texts.json": JSON.stringify({"a": "from top"})})
	_pack("middle", "dev", {"texts.json": JSON.stringify({"a": "from middle", "b": "from middle"}), "rules/durations.json": "{}"})
	_only_the_scratch_folder()
	Packs.choose(&"top")
	assert_str(Packs.text("a")).is_equal("from top")             # the pack nearest the top has the last word
	assert_str(Packs.text("b")).is_equal("from middle")          # the pack under it still answers what the top one leaves out
	assert_object(Packs.text("c")).is_null()


func test_a_borrowed_chain_is_given_back() -> void:
	_pack("loan", "dev")
	_only_the_scratch_folder()
	Packs.choose(Packs.DEV)
	var saved := Packs.snapshot()
	Packs.use(Pack.open(_scratch + "/loan"))
	assert_array(Packs.chain_ids()).is_equal([&"loan", Packs.DEV])
	Packs.restore(saved)
	assert_array(Packs.chain_ids()).is_equal([Packs.DEV])
	assert_str(Packs.asked()).is_equal(Packs.DEV)
