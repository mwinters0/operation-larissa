class_name TestTuningLegacy
extends GdUnitTestSuite
## Teaches: the original's rule values are the DEFAULTS. The legacy pack (made by the importer from the player's own copy) states no `rules/tuning.json`, so the chain it runs
## on resolves to exactly the project's file, `Tuning.original()`, field by field and table by table; the run that plays the original's sectors holds that tuning, and the
## reachability sweep reads its rectangles and its respawn screen from it. A pack that changed a value would make the fidelity tests prove something else.

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"


func after_test() -> void:
	GameState.reset()


## Every value of an object's script variables as plain data, a `SubTuning` one level down.
func _flat(object: Object) -> Dictionary:
	var flat := {}
	for property in object.get_script().get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = object.get(property["name"])
			flat[property["name"]] = _flat(value) if value is Object else value
	return flat


func test_the_legacy_pack_states_no_rule_values() -> void:
	assert_bool(FileAccess.file_exists(LegacyPack.path(Tuning.PACK_PATH))).is_false()
	assert_array(Packs.chain_ids()).is_equal([LegacyPack.ID])
	assert_array(Tuning.files()).is_equal([Tuning.BASE_PATH])


func test_the_legacy_chain_resolves_to_the_originals_numbers_field_by_field() -> void:
	var resolved := _flat(Tuning.resolve())
	var original := _flat(Tuning.original())
	assert_array(resolved.keys()).is_equal(original.keys())
	for name: String in original:
		assert_that(resolved[name]).override_failure_message("'%s' differs from the original's" % name).is_equal(original[name])
	# the nested SubTuning is compared the same way: every table of it
	var resolved_sub: Dictionary = resolved["sub"]
	var original_sub: Dictionary = original["sub"]
	assert_int(original_sub.size()).is_greater(25)
	assert_array(resolved_sub.keys()).is_equal(original_sub.keys())
	for name: String in original_sub:
		assert_that(resolved_sub[name]).override_failure_message("sub.%s differs from the original's" % name).is_equal(original_sub[name])


func test_a_run_on_the_legacy_chain_holds_the_originals_tuning() -> void:
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.begin_run()
	assert_dict(_flat(run.tuning)).is_equal(_flat(Tuning.original()))
	var sim := SimWorld.new(run)
	assert_object(sim.sub.tuning).is_same(run.tuning.sub)


func test_the_reachability_sweep_takes_its_values_from_the_runs_tuning() -> void:
	var job := ReachSweep.prepare(0)
	assert_that(job["cell_rects"]).is_equal(Tuning.original().sub.frame_rects)
	assert_int(job["midpoint_screen"]).is_equal(Tuning.original().midpoint_screen)
