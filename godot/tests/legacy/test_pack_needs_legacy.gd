class_name TestPackNeedsLegacy
extends GdUnitTestSuite
## The original game as a chain that needs nothing under it. `PackNeeds` is defined by the code and checked against the dev pack (tests/engine/test_pack_needs.gd);
## this checks that the same closure holds for the pack the importer writes, which is what a release plays without `dev`.
## Teaches: one definition of "complete" tested against two independent packs, so that a file the engine asks for and one of them lacks cannot slip by.


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := LegacyPack.NEED_THE_IMPORTER) -> void:
	pass


func _legacy_chain() -> Array[Pack]:
	return PackNeeds.chain_of(Pack.open(LegacyPack.root()))


func test_legacy_alone_misses_nothing() -> void:
	var chain := _legacy_chain()
	assert_array(chain.map(func(each: Pack) -> StringName: return each.id)).is_equal([LegacyPack.ID])
	var started := Time.get_ticks_usec()
	var gaps := PackNeeds.gaps(chain)
	print("PackNeeds on legacy: %d gaps, %.1f ms, %d things required" % [gaps.size(), (Time.get_ticks_usec() - started) / 1000.0, PackNeeds.required(chain).size()])
	assert_array(gaps).override_failure_message("\n".join(gaps.map(func(gap: PackNeeds.Gap) -> String: return gap.text()))).is_empty()
	assert_float((Time.get_ticks_usec() - started) / 1000.0).is_less(2000.0)


func test_the_chain_in_use_misses_nothing() -> void:
	assert_array(PackNeeds.gaps(Packs.chain())).is_empty()


## The start-up check (`Packs.choose`) finds legacy whole: no fallback and no `dev`, in a debug build and in a release build.
func test_legacy_starts_with_no_fallback_in_either_mode() -> void:
	var real_mode := Packs.dev_fallback
	for mode in [true, false]:
		Packs.dev_fallback = mode
		assert_bool(Packs.choose(LegacyPack.ID)).is_true()
		assert_object(Packs.fallback_reason()).is_null()
		assert_array(Packs.chain_ids()).is_equal([LegacyPack.ID])
	Packs.dev_fallback = real_mode
	Packs.start()


func test_both_original_campaigns_are_in_what_legacy_requires() -> void:
	var required := PackNeeds.required(_legacy_chain())
	assert_array(required).contains(["sector 0", "sector 31", "data/zones.tres", "data/problems/problem_type_33.tres"])


## The declared files are what the importer writes under `data/` besides sectors, campaigns and problem types.
func test_the_declared_files_are_what_legacy_holds_under_data() -> void:
	var declared: Array[String] = Array(PackNeeds.FILES.keys(), TYPE_STRING, "", null)
	for table_name in Catalog.TEXT_TABLES:
		declared.append(PackNeeds.TEXT_TABLE_REL % table_name)
	for zone in Catalog.ZONE_COUNT:
		for pattern in PackNeeds.PER_ZONE:
			declared.append(pattern % zone)
	for zone in ZoneTable.ORIGINAL_ZONES:
		for pattern in PackNeeds.PER_TILE_ZONE:
			declared.append(pattern % zone)
	declared.sort()
	var held: Array[String] = []
	for rel in Pack.open(LegacyPack.root()).all_files():
		if not rel.begins_with("data/") or rel.begins_with("data/sectors/") or rel.begins_with("data/campaigns/") or rel.begins_with("data/problems/problem_type_"):
			continue
		if rel.get_extension() == "import" or rel.get_extension() == "uid":
			continue
		held.append(rel)
	held.sort()
	assert_array(declared).is_equal(held)
