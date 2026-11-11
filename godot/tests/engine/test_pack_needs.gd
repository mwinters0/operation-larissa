class_name TestPackNeeds
extends GdUnitTestSuite
## Teaches: "is this chain playable?" is one closure (`PackNeeds`), computed from what the code asks for, and testable against the pack that is complete by
## definition. The dev pack misses nothing; a pack that lacks files is reported as exactly those; a pack over dev misses nothing and a chain with no
## dev under it is asked about as it is. Scratch packs are `PackShelf` folders in `user://` and, for a pack the engine trusts (a pack that holds `.tres` files), a folder under `res://packs/`
## that is taken away again.

const PROBE_ID := &"zz_needs_probe"
const PROBE_ROOT := "res://packs/zz_needs_probe"
## What the ISO-free closure may cost at every start; the measured time on dev is a tenth of this.
const TIME_BOUND_MS := 2000.0

var _shelves: Array[PackShelf] = []
var _real_chain: Dictionary


func before_test() -> void:
	_real_chain = Packs.snapshot()


func after_test() -> void:
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	PackFiles.remove_tree(PROBE_ROOT)
	Packs.restore(_real_chain)


func _shelf(base: StringName = &"") -> PackShelf:
	var shelf := PackShelf.new(&"", base)
	_shelves.append(shelf)
	shelf.pack = Pack.open(shelf.root)
	return shelf


func _dev_chain() -> Array[Pack]:
	var chain: Array[Pack] = [Packs.dev()]
	return chain


func _chain_of(pack: Pack) -> Array[Pack]:
	var chain: Array[Pack] = [pack]
	return chain


func _text(gaps: Array[PackNeeds.Gap]) -> String:
	return "\n".join(gaps.map(func(gap: PackNeeds.Gap) -> String: return "%s: %s" % [gap.group, gap.text()]))


# --- the dev pack is complete -----------------------------------------------------------------------------------------------------

func test_the_dev_pack_misses_nothing() -> void:
	var started := Time.get_ticks_usec()
	var gaps := PackNeeds.gaps(_dev_chain())
	var took := (Time.get_ticks_usec() - started) / 1000.0
	print("PackNeeds on dev: %d gaps, %.1f ms, %d things required" % [gaps.size(), took, PackNeeds.required(_dev_chain()).size()])
	assert_array(gaps).override_failure_message(_text(gaps)).is_empty()
	assert_array(PackNeeds.missing(_dev_chain())).is_empty()
	assert_bool(PackNeeds.is_complete(_dev_chain())).is_true()
	assert_float(took).is_less(TIME_BOUND_MS)


func test_the_chain_in_use_misses_nothing_and_asking_leaves_it_as_it_was() -> void:
	var before := Packs.chain_ids()
	assert_array(PackNeeds.gaps(Packs.chain())).is_empty()
	assert_array(PackNeeds.gaps(_dev_chain())).is_empty()                   # (a chain that is not the one in use is lent for the question)
	assert_array(Packs.chain_ids()).is_equal(before)


func test_what_is_required_is_files_the_chain_holds() -> void:
	var required := PackNeeds.required(_dev_chain())
	assert_array(required).contains(["data/zones.tres", "data/problems/problem_type_33.tres", "data/sprite_frames/foes_zone6.tres", "data/sprite_frames/decos_zone4.tres"])
	assert_array(required).contains(["assets/ui/title/title_sky_1039.png"])
	for item in required:
		if item.begins_with("data/") or item.begins_with("assets/"):
			assert_bool(Packs.dev().has(item)).override_failure_message("required but dev has no " + item).is_true()
		elif item.begins_with("res://"):
			assert_bool(ResourceLoader.exists(item) or FileAccess.file_exists(item)).override_failure_message("required but not there: " + item).is_true()


## The declared list is what dev provides under `data/`, bar the sectors, campaigns and problem types (which the content decides).
func test_the_declared_files_are_what_dev_holds_under_data() -> void:
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
	for rel in Packs.dev().all_files():
		if not rel.begins_with("data/") or rel.begins_with("data/sectors/") or rel.begins_with("data/campaigns/") or rel.begins_with("data/problems/problem_type_"):
			continue
		if rel.get_extension() == "import" or rel.get_extension() == "uid":
			continue
		held.append(rel)
	held.sort()
	assert_array(declared).is_equal(held)
	assert_array(declared).has_size(PackNeeds.FILES.size() + Catalog.TEXT_TABLES.size() + Catalog.ZONE_COUNT * PackNeeds.PER_ZONE.size() + ZoneTable.ORIGINAL_ZONES)


func test_every_problem_type_dev_holds_is_required_and_no_more() -> void:
	var held := 0
	for rel in Packs.dev().all_files():
		if rel.begins_with("data/problems/problem_type_") and rel.get_extension() == "tres":
			held += 1
	assert_int(held).is_equal(Catalog.PROBLEM_TYPE_COUNT)


# --- a chain that lacks files ------------------------------------------------------------------------------------------------------

## A pack on its own in the data form serves no resource, so it lacks every `.tres`; what it does hold is not reported.
func test_a_pack_that_lacks_files_is_reported_as_exactly_those() -> void:
	var shelf := _shelf()
	shelf.write_text("data/problems/problem_art_index.json", FileAccess.get_file_as_string(Packs.dev().path_of("data/problems/problem_art_index.json")))
	for type_id in 3:
		shelf.write_json("data/problems/problem_type_%02d.json" % type_id, ResourceJson.new().data_of(Catalog.problem_type(type_id)))
	shelf.add_picture("pictures/ui_picture/title_sky.png", Color.BLUE)
	var chain := _chain_of(shelf.pack)
	var asked := PackNeeds.required(chain)
	var missing := PackNeeds.missing(chain)
	var held: Array[String] = []
	for item in asked:
		if not missing.has(item) and not item.begins_with("res://"):                   # (the whole paths are what the problem types and catalogs name)
			held.append(item)
	held.sort()
	assert_array(held).is_equal([
		"assets/ui/title/title_sky_1039.png", "data/problems/problem_art_index.json",
		"data/problems/problem_type_00.tres", "data/problems/problem_type_01.tres", "data/problems/problem_type_02.tres"])
	assert_array(missing).contains(["data/zones.tres", "data/problems/problem_type_03.tres", "data/problems/problem_type_33.tres", "data/story/news_cartoon.tres",
			"data/story/title_ship.tres", "data/story/story_script.tres", "data/story/voyager_closing_script.tres", "data/story/closing_crew.tres"])
	assert_array(missing).not_contains(["data/problems/problem_art_index.json", "data/problems/problem_type_02.tres", "assets/ui/title/title_sky_1039.png"])
	var groups := PackNeeds.by_group(PackNeeds.gaps(chain))
	assert_array(groups.keys()).contains([PackNeeds.GROUP_FILES, PackNeeds.GROUP_PROBLEMS, PackNeeds.GROUP_PICTURES])
	assert_int(groups[PackNeeds.GROUP_PROBLEMS].size()).is_equal(Catalog.PROBLEM_TYPE_COUNT - 3)


func test_a_summary_gives_the_count_and_a_few_names() -> void:
	assert_str(PackNeeds.summary(PackNeeds.gaps(_dev_chain()))).is_empty()
	var gaps := PackNeeds.gaps(_chain_of(_shelf().pack))
	var summary := PackNeeds.summary(gaps, 3)
	assert_str(summary).starts_with("%d missing: " % gaps.size()).contains(" and %d more" % (gaps.size() - 3))
	assert_int(summary.count(",")).is_equal(2)


## No chain at all lacks the files and the problem types, and nothing else is looked at.
func test_an_empty_chain_misses_the_declared_files() -> void:
	var none: Array[Pack] = []
	var gaps := PackNeeds.gaps(none)
	assert_array(gaps).is_not_empty()
	assert_array(PackNeeds.missing(none)).contains(["data/zones.tres", "data/problems/problem_type_00.tres"])
	assert_array(PackNeeds.by_group(gaps).keys()).contains_exactly([PackNeeds.GROUP_FILES, PackNeeds.GROUP_PROBLEMS])


# --- a pack over a complete one ------------------------------------------------------------------------------------------------

func _mini_campaign(shelf: PackShelf, sectors: Array, extra: Dictionary = {}) -> void:
	var data := {
		"class": "Campaign", "id": "mini", "title": "Mini", "sectors": sectors, "finales": [],
		"default_edu_levels": [0, 1], "log_unlock_order": [1], "log_texts": ["One."], "log_voices": [""],
		"supply_texts": ["Well."], "supply_voices": [""],
	}
	data.merge(extra, true)
	shelf.write_json("campaigns/mini.json", data)


func test_a_data_pack_over_dev_misses_nothing() -> void:
	var shelf := _shelf(Packs.DEV)
	shelf.add_sector_copy(0, 40)
	_mini_campaign(shelf, [40, 0])
	var chain: Array[Pack] = [shelf.pack, Packs.dev()]
	var gaps := PackNeeds.gaps(chain)
	assert_array(gaps).override_failure_message(_text(gaps)).is_empty()


func test_the_campaigns_of_a_chain_bring_their_sectors_a_finale_picture_and_speech() -> void:
	var shelf := _shelf(Packs.DEV)
	_mini_campaign(shelf, [77], {"finale_picture": "no_such_picture", "log_voices": ["no_such_group"]})
	var chain: Array[Pack] = [shelf.pack, Packs.dev()]
	var gaps := PackNeeds.gaps(chain)
	var by_path := {}
	for gap in gaps:
		by_path[gap.path] = gap
	assert_array(by_path.keys()).contains_exactly(["sector 77", "finale_picture no_such_picture", "voice group no_such_group"])
	assert_str(by_path["sector 77"].group).is_equal("campaign mini")
	assert_bool(by_path["sector 77"].soft).is_false()                                     # the game cannot start the campaign
	assert_bool(by_path["finale_picture no_such_picture"].soft).is_true()                 # it plays on without a picture, and without a spoken line
	assert_bool(by_path["voice group no_such_group"].soft).is_true()


func test_a_sector_of_a_data_pack_needs_its_script() -> void:
	var shelf := _shelf(Packs.DEV)
	shelf.add_sector_copy(0, 41)
	_mini_campaign(shelf, [41])
	DirAccess.remove_absolute("%s/%s" % [shelf.root, SectorJson.foe_rel(41)])
	var chain: Array[Pack] = [shelf.pack, Packs.dev()]
	assert_array(PackNeeds.missing(chain)).contains_exactly([SectorJson.foe_rel(41)])


# --- chains without dev ------------------------------------------------------------------------------------------------------------

func test_a_chain_is_made_without_dev_under_it() -> void:
	var shelf := _shelf(&"no_such_base")
	var with_dev := Packs.resolve(shelf.pack)
	assert_array(with_dev.packs.map(func(each: Pack) -> StringName: return each.id)).is_equal([shelf.id, Packs.DEV])
	assert_int(with_dev.fallback.why).is_equal(Packs.Fallback.Why.MISSING_BASE)
	var without := PackNeeds.chain_of(shelf.pack)
	assert_array(without.map(func(each: Pack) -> StringName: return each.id)).is_equal([shelf.id])
	assert_array(PackNeeds.missing(without)).contains(["data/zones.tres"])
	assert_array(PackNeeds.gaps(PackNeeds.chain_of(Packs.dev()))).is_empty()


func test_a_chain_that_ends_in_dev_by_its_base_is_whole() -> void:
	var shelf := _shelf(Packs.DEV)
	var chain := PackNeeds.chain_of(shelf.pack)
	assert_array(chain.map(func(each: Pack) -> StringName: return each.id)).is_equal([shelf.id, Packs.DEV])
	assert_array(PackNeeds.gaps(chain)).is_empty()


# --- skins and pictures of a pack ----------------------------------------------------------------------------------------------------

func test_a_skin_that_maps_a_picture_covers_it_and_no_skin_does_not() -> void:
	var chain := _chain_of(_shelf().pack)
	var rel := "assets/ui/title/title_sky_1039.png"
	assert_array(PackNeeds.missing(chain)).contains([rel])
	var skin := GameSkin.new()
	skin.id = &"needs_probe"
	skin.pictures = {"ui_picture/title_sky": ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))}
	assert_array(PackNeeds.missing(chain, skin)).not_contains([rel])
	assert_array(PackNeeds.missing(chain, skin)).contains(["assets/ui/title/title_cloud_0_1042.png"])        # (it covers what it maps)


func test_a_picture_of_a_pack_covers_the_file_it_replaces() -> void:
	var shelf := _shelf()
	var rel := "assets/ui/title/title_sky_1039.png"
	assert_array(PackNeeds.missing(_chain_of(shelf.pack))).contains([rel])
	shelf.add_picture("pictures/ui_picture/title_sky.png", Color.RED)
	assert_array(PackNeeds.missing(_chain_of(Pack.open(shelf.root)))).not_contains([rel])


# --- what a resource names ---------------------------------------------------------------------------------------------------------

func test_a_resource_that_names_a_file_nobody_has_is_reported() -> void:
	PackFiles.write_text(PROBE_ROOT + "/data/zones.tres", "[gd_resource type=\"Resource\" format=3]\n\n[ext_resource type=\"Texture2D\" path=\"%s/assets/gone.png\" id=\"1\"]\n\n[resource]\n" % PROBE_ROOT)
	assert_array(PackNeeds.named_files(PROBE_ROOT + "/data/zones.tres")).is_equal([PROBE_ROOT + "/assets/gone.png"])
	assert_array(PackNeeds.absent_files(PROBE_ROOT + "/data/zones.tres")).is_equal([PROBE_ROOT + "/assets/gone.png"])
	assert_array(PackNeeds.absent_files(Packs.dev().path_of("data/zones.tres"))).is_empty()


# --- PackCheck uses it --------------------------------------------------------------------------------------------------------------

func test_pack_check_passes_dev_and_a_data_pack_over_it() -> void:
	var options := PackCheck.Options.new()
	options.reach = false
	options.sectors = false
	var report := PackCheck.run(Packs.dev(), options)
	assert_bool(_has_needs_error(report)).override_failure_message(report.text()).is_false()
	var shelf := _shelf(Packs.DEV)
	report = PackCheck.run(Pack.open(shelf.root), options)
	assert_bool(_has_needs_error(report)).override_failure_message(report.text()).is_false()


func test_pack_check_names_what_a_complete_pack_lacks() -> void:
	PackFiles.write_text(PROBE_ROOT + "/pack.json", JSON.stringify({"id": String(PROBE_ID), "title": "Needs probe", "version": "1"}))
	PackFiles.write_text(PROBE_ROOT + "/data/zones.tres", "[gd_resource type=\"Resource\" format=3]\n\n[resource]\n")
	var options := PackCheck.Options.new()
	options.reach = false
	options.sectors = false
	var report := PackCheck.run(Pack.open(PROBE_ROOT), options)
	assert_bool(report.passes()).is_false()
	var text := report.text()
	assert_str(text).contains("needs:").contains("files the game needs").contains("data/trigger_table.tres").contains("problem types the game needs").contains("pictures the game needs")
	assert_str(text).not_contains("data/zones.tres")                                # (it holds that one)
	assert_int(report.errors().filter(func(f: PackReport.Finding) -> bool: return f.area == "needs").size()).is_equal(3)


func _has_needs_error(report: PackReport) -> bool:
	return report.errors().any(func(f: PackReport.Finding) -> bool: return f.area == "needs")
