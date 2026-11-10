class_name TestResourceJsonLegacy
extends GdUnitTestSuite
## The round trip through JSON over the legacy pack's real data: its campaigns (Voyager and Expert), its 32 original sectors (and the designers'
## ones beside them) and its 34 problem types. The serializer's rules are in `tests/engine/test_resource_json.gd`, on dev's data; this file only runs the same
## comparison (`ResourceCompare.same`) over the original's.


func _round_trip(resource: Resource, skip: PackedStringArray = PackedStringArray()) -> Dictionary:
	var writer := ResourceJson.new()
	writer.skip = skip
	var text := ResourceJson.stringify(writer.data_of(resource))
	var reader := ResourceJson.new()
	reader.skip = skip
	return {"resource": reader.resource_from(JSON.parse_string(text)), "problems": reader.problems}


func test_every_original_campaign_survives_json() -> void:
	var ids: Array[StringName] = []
	for campaign in Catalog.campaigns():
		ids.append(campaign.id)
		var back := _round_trip(campaign)
		assert_array(back["problems"]).override_failure_message("%s: %s" % [campaign.id, back["problems"]]).is_empty()
		var differences: Array[String] = []
		ResourceCompare.same(campaign, back["resource"], String(campaign.id), differences)
		assert_array(differences).override_failure_message("\n".join(differences)).is_empty()
	assert_array(ids).contains([&"voyager", &"expert"])


func test_every_original_sector_survives_json_screens_creatures_and_all() -> void:
	var skip := PackedStringArray([SectorJson.SCRIPT_FIELD])
	var count := 0
	for index in Catalog.sector_ids():
		var sector := Catalog.sector(index)
		var back := _round_trip(sector, skip)
		assert_array(back["problems"]).override_failure_message("sector %d: %s" % [index, back["problems"]]).is_empty()
		var read: SectorData = back["resource"]
		var differences: Array[String] = []
		ResourceCompare.same(sector, read, "sector %d" % index, differences)
		var real_differences := differences.filter(func(line: String) -> bool: return not line.contains("foe_script"))
		assert_array(real_differences).override_failure_message("\n".join(real_differences)).is_empty()
		assert_array(Array(read.encode())).is_equal(Array(sector.encode()))             # the 0x72-byte header, to the byte
		for m in SectorData.SCREEN_COUNT:
			assert_array(Array(read.screens[m].encode())).override_failure_message("sector %d screen %d" % [index, m]).is_equal(Array(sector.screens[m].encode()))
		count += 1
	assert_int(count).is_greater_equal(Catalog.ORIGINAL_SECTOR_COUNT)


func test_every_original_problem_type_survives_json() -> void:
	for index in Catalog.PROBLEM_TYPE_COUNT:
		var type := load(LegacyPack.ROOT + "data/problems/problem_type_%02d.tres" % index) as ProblemType
		var back := _round_trip(type)
		assert_array(back["problems"]).override_failure_message("problem type %d: %s" % [index, back["problems"]]).is_empty()
		var differences: Array[String] = []
		ResourceCompare.same(type, back["resource"], "problem type %d" % index, differences)
		assert_array(differences).override_failure_message("\n".join(differences)).is_empty()
