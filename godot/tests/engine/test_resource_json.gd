class_name TestResourceJson
extends GdUnitTestSuite
## Teaches: a data format that is a DESCRIPTION of the resource. `ResourceJson` writes any Resource of the game as JSON and reads it
## back without `ResourceLoader`, and `SectorJson` does the same for a sector with its `.foe` text beside it. The strongest test of a serializer is
## the round trip over REAL data: every campaign, every sector (of the chain, screens, decorations, triggers, creatures) and every problem type goes
## to JSON text and back, and the copy equals the original field by field. Then the small facts a hand-written file depends on: defaults are left out,
## a typo is a problem, a value of the wrong kind is a problem, and a picture field names a file of the pack.

const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"


## `resource` written as JSON text and read back (nothing but the text passes between).
func _round_trip(resource: Resource, skip: PackedStringArray = PackedStringArray()) -> Dictionary:
	var writer := ResourceJson.new()
	writer.skip = skip
	var text := ResourceJson.stringify(writer.data_of(resource))
	var reader := ResourceJson.new()
	reader.skip = skip
	return {"resource": reader.resource_from(JSON.parse_string(text)), "problems": reader.problems, "text": text}


# --- real data, round trip --------------------------------------------------------------------------------------------------

func test_every_campaign_survives_json() -> void:
	var seen := 0
	for campaign in Catalog.campaigns():
		var back := _round_trip(campaign)
		assert_array(back["problems"]).override_failure_message("%s: %s" % [campaign.id, back["problems"]]).is_empty()
		var differences: Array[String] = []
		ResourceCompare.same(campaign, back["resource"], String(campaign.id), differences)
		assert_array(differences).override_failure_message("\n".join(differences)).is_empty()
		seen += 1
	assert_int(seen).is_greater_equal(1)                                      # the dev tour at least


func test_every_sector_survives_json_screens_creatures_and_all() -> void:
	var skip := PackedStringArray([SectorJson.SCRIPT_FIELD])
	var count := 0
	for index in Catalog.sector_ids():
		var sector := Catalog.sector(index)
		var back := _round_trip(sector, skip)
		assert_array(back["problems"]).override_failure_message("sector %d: %s" % [index, back["problems"]]).is_empty()
		var read: SectorData = back["resource"]
		var differences: Array[String] = []
		ResourceCompare.same(sector, read, "sector %d" % index, differences)
		# (the script is not in the JSON: compare the rest, then the bytes the sector encodes to)
		var real_differences := differences.filter(func(line: String) -> bool: return not line.contains("foe_script"))
		assert_array(real_differences).override_failure_message("\n".join(real_differences)).is_empty()
		assert_array(Array(read.encode())).is_equal(Array(sector.encode()))             # the 0x72-byte header, to the byte
		for m in SectorData.SCREEN_COUNT:
			assert_array(Array(read.screens[m].encode())).override_failure_message("sector %d screen %d" % [index, m]).is_equal(Array(sector.screens[m].encode()))
		count += 1
	assert_int(count).is_equal(Catalog.sector_ids().size())
	assert_int(count).is_greater_equal(Ground.clean_sectors().size())


func test_every_problem_type_survives_json() -> void:
	for index in Catalog.PROBLEM_TYPE_COUNT:
		var type := load(DevPack.path("data/problems/problem_type_%02d.tres" % index)) as ProblemType
		var back := _round_trip(type)
		assert_array(back["problems"]).override_failure_message("problem type %d: %s" % [index, back["problems"]]).is_empty()
		var differences: Array[String] = []
		ResourceCompare.same(type, back["resource"], "problem type %d" % index, differences)
		assert_array(differences).override_failure_message("\n".join(differences)).is_empty()


# --- the shape of the file --------------------------------------------------------------------------------------------------

func test_the_file_names_its_class_and_only_what_differs_from_the_default() -> void:
	var campaign := CampaignShelf.orchard()
	var data := ResourceJson.new().data_of(campaign)
	assert_str(data["class"]).is_equal("Campaign")
	assert_str(data["id"]).is_equal("orchard")
	assert_array(data["sectors"]).is_equal([0, 1])
	assert_bool(data.has("log_series")).is_false()                               # 1 is the default
	assert_bool(data.has("banner_index")).is_false()
	assert_bool(data.has("fallback_song")).is_false()
	assert_bool(data.has("closing_scene")).is_false()
	assert_bool(data.has("banner")).is_false()                                    # a picture is a file of the pack, never written


func test_a_hand_written_campaign_names_only_what_it_changes() -> void:
	var reader := ResourceJson.new()
	var read := reader.resource_from({"class": "Campaign", "id": "mine", "title": "Mine", "sectors": [40, 41], "log_texts": ["a", "b"]}) as Campaign
	assert_array(reader.problems).is_empty()
	assert_str(read.id).is_equal(&"mine")
	assert_array(Array(read.sectors)).is_equal([40, 41])
	assert_array(read.log_texts).is_equal([&"a", &"b"])
	assert_bool(read.log_texts.is_typed()).is_true()                              # the typed array of the class, not a plain list
	assert_int(read.log_series).is_equal(1)
	assert_str(read.fallback_song).is_equal(Campaign.DEFAULT_SONG)


func test_a_typo_a_wrong_kind_and_a_missing_class_are_problems_not_silence() -> void:
	var reader := ResourceJson.new()
	reader.resource_from({"class": "Campaign", "id": "x", "titel": "Typo", "sectors": "not a list", "log_series": "one"})
	assert_array(reader.problems).has_size(3)
	assert_str(reader.problems[0]).contains("no field 'titel'")
	assert_str(reader.problems[1]).contains("Campaign.sectors")
	assert_str(reader.problems[2]).contains("Campaign.log_series")
	var nameless := ResourceJson.new()
	assert_object(nameless.resource_from({"id": "x"})).is_null()
	assert_str(nameless.problems[0]).contains("no class")
	var unknown := ResourceJson.new()
	assert_object(unknown.resource_from({"class": "NoSuchThing"})).is_null()


func test_a_nested_object_is_read_with_its_own_fields_and_numbers_become_ints() -> void:
	var reader := ResourceJson.new()
	var sector := reader.resource_from({"class": "SectorData", "index": 40, "start_pos": [10, 20],
			"pieces": [{"screen": 3, "pos": [100, 200], "is_canister": true}, {"screen": 4}]}) as SectorData
	assert_array(reader.problems).is_empty()
	assert_object(sector.start_pos).is_equal(Vector2i(10, 20))
	assert_int(sector.pieces.size()).is_equal(2)
	assert_bool(sector.pieces[0].is_canister).is_true()
	assert_object(sector.pieces[0].pos).is_equal(Vector2i(100, 200))
	assert_object(sector.pieces[1].pos).is_equal(Vector2i.ZERO)
	var odd := ResourceJson.new()
	odd.resource_from({"class": "SectorData", "pieces": [{"screen": 3, "colour": 1}]})
	assert_str(odd.problems[0]).contains("PieceData has no field 'colour'")


func test_a_dictionary_field_turns_whole_numbers_and_numeric_keys_into_ints() -> void:
	var reader := ResourceJson.new()
	var catalog := reader.resource_from({"class": "SfxCatalog", "diagram_cues": {"7": 35, "8": 2.0}}) as SfxCatalog
	assert_array(reader.problems).is_empty()
	assert_int(catalog.diagram_cue(7)).is_equal(35)
	assert_int(catalog.diagram_cue(8)).is_equal(2)


func test_a_picture_field_names_a_png_of_the_pack() -> void:
	var shelf := PackShelf.new()
	shelf.add_picture("pictures/mine.png", Color.RED, Vector2i(3, 2))
	var pack := Pack.open(shelf.root)
	var reader := ResourceJson.new(pack)
	var campaign := reader.resource_from({"class": "Campaign", "id": "x", "banner": "pictures/mine.png"}) as Campaign
	assert_array(reader.problems).is_empty()
	assert_object(campaign.banner).is_not_null()
	assert_vector(campaign.banner.get_size()).is_equal(Vector2(3, 2))
	var missing := ResourceJson.new(pack)
	missing.resource_from({"class": "Campaign", "id": "x", "banner": "pictures/none.png"})
	assert_str(missing.problems[0]).contains("no picture")
	var escaping := ResourceJson.new(pack)
	escaping.resource_from({"class": "Campaign", "id": "x", "banner": "../outside.png"})
	assert_str(escaping.problems[0]).contains("no picture")                        # a path that leaves the pack is not a picture of it
	shelf.remove()


# --- a sector in two files --------------------------------------------------------------------------------------------------

func test_a_sector_is_a_json_file_and_a_foe_text_and_comes_back_equal() -> void:
	var shelf := PackShelf.new()
	var copy := shelf.add_sector_copy(Ground.EDIT, 40)
	assert_bool(FileAccess.file_exists(shelf.root + "/sectors/sector_40/sector_40.json")).is_true()
	assert_bool(FileAccess.file_exists(shelf.root + "/sectors/sector_40/sector_40.foe")).is_true()
	assert_str(FileAccess.get_file_as_string(shelf.root + "/sectors/sector_40/sector_40.foe")).starts_with("; Sector 40 - a copy of sector %d" % Ground.EDIT)
	var pack := Pack.open(shelf.root)
	var read := SectorJson.read(pack, 40)
	assert_object(read).is_not_null()
	assert_int(read.index).is_equal(40)
	var differences: Array[String] = []
	ResourceCompare.same(copy, read, "sector 40", differences)
	assert_array(differences).override_failure_message("\n".join(differences)).is_empty()
	read.ensure_compiled()
	assert_array(read.compile_errors).is_empty()
	assert_array(Array(read.foe_bytecode)).is_equal(Array(Catalog.sector(Ground.EDIT).foe_bytecode))   # the copy's script is the source's bytes
	shelf.remove()
