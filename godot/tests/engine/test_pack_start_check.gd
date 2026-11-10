class_name TestPackStartCheck
extends GdUnitTestSuite
## Teaches: what the game does at start when the chain it chose is not whole, and that it is one setting that decides (`Packs.dev_fallback`). A chain that resolves is
## asked once what it lacks (`PackNeeds`, no skin, no `dev` under it): a hard gap makes it a fallback (`MISSING_ASSETS`), a soft gap is only logged. In a debug build `dev` is
## put under the chain and answers what it lacks; in a release build nothing is added and the chain is refused. A chain that holds `dev` for real (`--pack=dev`, a data
## pack laid over it) is whole in both. The sentences by situation (`Fallback.text`, `advice`) are asserted here too. The incomplete pack is a complete
## pack that is only a manifest (`PackShelf.empty_complete_pack_dir`); the others are scratch folders in `user://`.

const PROBE_ID := &"zz_start_probe"
## A duration the dev pack's `rules/durations.json` changes from the base file's.
const DEV_KEY := "station.launch.opening_ticks"

var _scratch: String
var _probe_dir: String
var _real_folders: Array[String]
var _real_mode: bool


func before_test() -> void:
	_scratch = "user://test_start_check_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_scratch)
	_real_folders = Packs.folders.duplicate()
	_real_mode = Packs.dev_fallback


func after_test() -> void:
	Packs.dev_fallback = _real_mode
	Packs.folders = _real_folders
	PackFiles.remove_tree(_scratch)
	Packs.start()                                            # (the command-line choice again: no test of this suite leaves a choice of its own behind)


## The complete pack that is only a manifest: it answers nothing, so the chain [probe] lacks everything. It is the only place packs are found.
func _probe() -> void:
	_probe_dir = PackShelf.empty_complete_pack_dir(PROBE_ID)
	Packs.folders = [_probe_dir, _scratch]


func _data_pack(id: String, base: String) -> void:
	var manifest := {"id": id, "title": "Test %s" % id, "version": "1"}
	if not base.is_empty():
		manifest["base"] = base
	PackFiles.write_text("%s/%s/pack.json" % [_scratch, id], JSON.stringify(manifest))


func _folders_with_scratch() -> void:
	Packs.folders = [_probe_dir, _scratch]


## What the closure finds missing in the probe on its own: the number the fallback must carry.
func _probe_gaps() -> int:
	var found := PackNeeds.gaps(PackNeeds.chain_of(Pack.open("%s/%s" % [_probe_dir, PROBE_ID])))
	return PackNeeds.hard(found).size()


# --- a chain that lacks things, in a debug build ------------------------------------------------------------------------

func test_debug_an_incomplete_complete_pack_gets_dev_under_it() -> void:
	_probe()
	Packs.dev_fallback = true
	var expected := _probe_gaps()
	assert_int(expected).is_greater(100)
	assert_bool(Packs.choose(PROBE_ID)).is_false()
	assert_array(Packs.chain_ids()).is_equal([PROBE_ID, Packs.DEV])
	var reason := Packs.fallback_reason()
	assert_int(reason.why).is_equal(Packs.Fallback.Why.MISSING_ASSETS)
	assert_int(reason.missing).is_equal(expected)
	assert_str(reason.pack_id).is_equal(PROBE_ID)
	assert_str(reason.detail).starts_with("%d missing: " % expected)
	assert_bool(reason.refused).is_false()
	assert_bool(Packs.is_refused()).is_false()
	assert_str(reason.text()).contains("'zz_start_probe' is incomplete").contains("%d missing" % expected).contains("dev pack").contains("stands in")
	assert_str(reason.missing_text()).is_equal("%d things are missing." % expected)
	# the lookups were built again with dev in the chain (no `refresh` needed): dev's own durations answer, as when dev is chosen
	var through_probe := Durations.at(DEV_KEY)
	Packs.choose(Packs.DEV)
	assert_int(through_probe).is_equal(Durations.at(DEV_KEY))
	Packs.dev_fallback = false
	Packs.choose(PROBE_ID)
	assert_int(Durations.at(DEV_KEY)).is_not_equal(through_probe)


func test_debug_dev_answers_what_the_chain_lacks() -> void:
	_probe()
	Packs.dev_fallback = true
	Packs.choose(PROBE_ID)
	assert_object(Packs.holder("data/trigger_table.tres")).is_same(Packs.dev())         # the pack holds nothing: dev, under it, answers
	assert_bool(Packs.pack(PROBE_ID).has("data/trigger_table.tres")).is_false()


func test_the_check_builds_the_chain_and_tells_of_it_once() -> void:
	_probe()
	Packs.dev_fallback = true
	var heard := [0]
	var count := func() -> void: heard[0] += 1
	Packs.events.changed.connect(count)
	Packs.choose(PROBE_ID)
	Packs.events.changed.disconnect(count)
	assert_int(heard[0]).is_equal(1)
	heard[0] = 0
	Packs.events.changed.connect(count)
	Packs.dev_fallback = false
	Packs.choose(PROBE_ID)
	Packs.events.changed.disconnect(count)
	assert_int(heard[0]).is_equal(1)


# --- the same chain in a release build -----------------------------------------------------------------------------------

func test_release_an_incomplete_pack_is_refused_and_dev_is_not_added() -> void:
	_probe()
	Packs.dev_fallback = false
	var expected := _probe_gaps()
	assert_bool(Packs.choose(PROBE_ID)).is_false()
	assert_array(Packs.chain_ids()).is_equal([PROBE_ID])
	assert_bool(Packs.is_refused()).is_true()
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.MISSING_ASSETS)
	assert_int(Packs.fallback_reason().missing).is_equal(expected)
	assert_str(Packs.fallback_reason().text()).contains("is incomplete").contains("cannot play").not_contains("dev pack")
	assert_object(Packs.chosen()).is_same(Packs.pack(PROBE_ID))


func test_release_every_reason_is_a_refusal_with_nothing_added() -> void:
	Packs.dev_fallback = false
	_data_pack("top", "middle")
	_data_pack("middle", "ghost")
	_data_pack("one", "two")
	_data_pack("two", "one")
	_data_pack("lonely", "")
	PackFiles.write_text("%s/broken/pack.json" % _scratch, JSON.stringify({"id": "broken", "title": "B", "version": "1", "format": 99}))
	Packs.folders = [_scratch]
	var cases := {
		"nope": [Packs.Fallback.Why.NOT_FOUND, []],
		"top": [Packs.Fallback.Why.MISSING_BASE, [&"top", &"middle"]],
		"one": [Packs.Fallback.Why.CYCLE, [&"one", &"two"]],
		"lonely": [Packs.Fallback.Why.MISSING_ASSETS, [&"lonely"]],
		"broken": [Packs.Fallback.Why.BROKEN, []],
	}
	Packs.folders = [_scratch + "_none"]                      # (an empty place: no pack at all)
	assert_bool(Packs.choose()).is_false()
	assert_array(Packs.chain_ids()).is_empty()
	assert_bool(Packs.is_refused()).is_true()
	assert_object(Packs.chosen()).is_null()
	assert_str(Packs.path("data/zones.tres")).is_not_empty()                                 # (a lookup on a chain with no pack does not fail)
	assert_bool(Packs.has("data/zones.tres")).is_false()
	Packs.folders = [_scratch]
	for id: String in cases:
		assert_bool(Packs.choose(StringName(id))).is_false()
		var why: Packs.Fallback.Why = cases[id][0]
		assert_int(Packs.fallback_reason().why).is_equal(why)
		assert_array(Packs.chain_ids()).override_failure_message("chain for '%s'" % id).is_equal(cases[id][1])
		assert_bool(Packs.is_refused()).is_true()
		assert_str(Packs.fallback_reason().text()).contains("cannot play")


func test_release_an_incomplete_chain_under_a_data_pack_is_refused_whole() -> void:
	_probe()
	_data_pack("layer", String(PROBE_ID))
	Packs.dev_fallback = false
	_folders_with_scratch()
	assert_bool(Packs.choose(&"layer")).is_false()
	assert_array(Packs.chain_ids()).is_equal([&"layer", PROBE_ID])
	assert_int(Packs.fallback_reason().why).is_equal(Packs.Fallback.Why.MISSING_ASSETS)
	assert_str(Packs.fallback_reason().pack_id).is_equal(&"layer")


# --- a chain that holds dev for real is whole -----------------------------------------------------------------------------

func test_dev_chosen_and_a_data_pack_over_dev_are_whole_in_both_modes() -> void:
	_data_pack("whole", "dev")
	Packs.folders = [_scratch]
	for mode in [true, false]:
		Packs.dev_fallback = mode
		assert_bool(Packs.choose(Packs.DEV)).is_true()
		assert_object(Packs.fallback_reason()).is_null()
		assert_array(Packs.chain_ids()).is_equal([Packs.DEV])
		assert_bool(Packs.choose(&"whole")).is_true()
		assert_object(Packs.fallback_reason()).is_null()
		assert_array(Packs.chain_ids()).is_equal([&"whole", Packs.DEV])
		assert_bool(Packs.is_refused()).is_false()


func test_a_chain_with_dev_is_not_asked_what_it_holds() -> void:
	# a campaign that names a sector nobody has is a hard gap of the closure, but a chain that holds dev for real is not checked: the campaign checks of `PackCheck` judge it
	_data_pack("loose", "dev")
	PackFiles.write_text(_scratch + "/loose/campaigns/loose.json", JSON.stringify({"class": "Campaign", "id": "loose", "title": "Loose", "sectors": [200], "finales": [], "default_edu_levels": [0], "log_unlock_order": [], "log_texts": [], "log_voices": [], "supply_texts": [], "supply_voices": []}))
	Packs.folders = [_scratch]
	Packs.dev_fallback = false
	assert_bool(Packs.choose(&"loose")).is_true()
	assert_array(PackNeeds.hard(PackNeeds.gaps(Packs.chain()))).is_not_empty()


func test_only_a_hard_gap_is_a_problem() -> void:
	var soft := PackNeeds.Gap.new()
	soft.soft = true
	var hard := PackNeeds.Gap.new()
	var found: Array[PackNeeds.Gap] = [soft, hard, soft]
	assert_array(PackNeeds.hard(found)).contains_exactly([hard])
	assert_array(PackNeeds.soft(found)).contains_exactly([soft, soft])


# --- the sentences, by situation -----------------------------------------------------------------------------------------

func test_no_pack_at_all_says_to_build_the_content_with_the_importer() -> void:
	Packs.folders = [_scratch]
	for mode in [true, false]:
		Packs.dev_fallback = mode
		Packs.choose()
		var reason := Packs.fallback_reason()
		assert_str(reason.text()).contains("No pack was found")
		assert_str(reason.advice()).contains("your own copy of the original").contains("importer").contains("docs/play/LEGACY.md")
	assert_str(Packs.fallback_reason().text()).contains("cannot play")


func test_a_complete_pack_that_is_incomplete_is_damaged_or_out_of_date() -> void:
	_probe()
	for mode in [true, false]:
		Packs.dev_fallback = mode
		Packs.choose(PROBE_ID)
		var reason := Packs.fallback_reason()
		assert_bool(reason.complete_pack).is_true()
		assert_str(reason.advice()).contains("damaged or out of date").contains("run the importer again").contains("'Troubleshooting' in docs/play/LEGACY.md")


func test_a_pack_laid_over_another_that_is_incomplete_or_missing_is_unfinished_or_needs_a_pack() -> void:
	_probe()
	_data_pack("layer", String(PROBE_ID))
	_data_pack("orphan", "ghost")
	_folders_with_scratch()
	for mode in [true, false]:
		Packs.dev_fallback = mode
		for id in [&"layer", &"orphan"]:
			Packs.choose(id)
			var reason := Packs.fallback_reason()
			assert_bool(reason.complete_pack).override_failure_message(String(id)).is_false()
			assert_str(reason.advice()).contains("unfinished").contains("not installed").contains("docs/create/MAKING_CONTENT.md").contains("docs/create/CONTENT.md")


func test_a_pack_asked_for_that_is_not_there_points_at_the_pack_screen() -> void:
	Packs.folders = [_scratch]
	Packs.choose(&"nowhere")
	assert_str(Packs.fallback_reason().advice()).contains("pack screen").contains("docs/play/LEGACY.md")


func test_each_reason_keeps_its_sentence_in_both_modes() -> void:
	var cases := [
		[Packs.Fallback.Why.BROKEN, "The pack 'a' cannot be used (bad)"],
		[Packs.Fallback.Why.MISSING_BASE, "The pack 'a' is laid over 'bad', which is not there"],
		[Packs.Fallback.Why.CYCLE, "The pack 'a' is laid over itself through its bases"],
	]
	for each in cases:
		var reason := Packs.Fallback.new()
		reason.why = each[0]
		reason.pack_id = &"a"
		reason.detail = "bad"
		assert_str(reason.text()).starts_with(each[1]).ends_with("so the dev pack is under it.")
		reason.refused = true
		assert_str(reason.text()).starts_with(each[1]).ends_with("so the game cannot play it.")
