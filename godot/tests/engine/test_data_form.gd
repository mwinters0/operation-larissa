class_name TestDataForm
extends GdUnitTestSuite
## Teaches: a data form for EVERY kind of resource a pack holds. The strongest test of a serializer is the round trip over real data, so every `.tres` of the dev
## pack's `data/` (zones, trigger table, sprite meta, sprite frames, the tile set, timelines, layouts, text tables, audio catalogs, voice index and cues,
## bubble rules, problem types, sectors with their screens, campaigns) goes to JSON text and back, and the copy equals the original field by field
## (`ResourceCompare`). Then the small facts a hand-written file depends on: a shared sub-resource, a value that keeps its kind inside a dictionary,
## a path that is relative to the pack, a `$ref` that looks down the chain and never up, an engine class that is not on the list.

const SCRIPT_CLASSES := ["ZoneTable", "TriggerTable", "SpriteMetaTable", "CutsceneTimeline", "HudLayout", "CalculatorLayout", "StoryLayout", "ProblemScreenLayout",
		"TextTable", "SfxCatalog", "MusicCatalog", "VoiceIndex", "VoiceCues", "BubbleRules", "ProblemType", "Campaign", "ScreenData"]


func _dev() -> Pack:
	return Packs.dev()


# --- every kind of dev, round trip -------------------------------------------------------------------------------------------

func test_every_resource_of_dev_survives_its_data_form() -> void:
	var dev := _dev()
	var seen: Dictionary = {}
	var count := 0
	for rel in dev.all_files():
		if not rel.begins_with("data/") or rel.get_extension() != "tres":
			continue
		var original := dev.resource(rel)
		assert_object(original).override_failure_message(rel).is_not_null()
		var skip := PackedStringArray([SectorJson.SCRIPT_FIELD]) if original is SectorData else PackedStringArray()
		var writer := ResourceJson.new(dev)
		writer.skip = skip
		var text := ResourceJson.stringify(writer.data_of(original))
		var reader := ResourceJson.new(dev)
		reader.skip = skip
		var back := reader.resource_from(JSON.parse_string(text))
		assert_array(writer.problems).override_failure_message("%s: %s" % [rel, writer.problems]).is_empty()
		assert_array(reader.problems).override_failure_message("%s: %s" % [rel, reader.problems]).is_empty()
		assert_object(back).override_failure_message(rel).is_not_null()
		var differences: Array[String] = []
		ResourceCompare.same(original, back, rel, differences)
		var real := differences.filter(func(line: String) -> bool: return not line.contains("foe_script"))
		assert_array(real).override_failure_message("\n".join(real.slice(0, 8))).is_empty()
		seen[EngineJson.class_of(original) if EngineJson.class_of(original) != "" else original.get_script().get_global_name()] = true
		count += 1
	assert_int(count).is_greater(400)
	for kind in SCRIPT_CLASSES + EngineJson.CLASSES:
		assert_bool(seen.has(kind)).override_failure_message("dev holds no %s to round trip" % kind).is_true()


func test_the_two_engine_classes_are_described_and_built_from_a_whitelist() -> void:
	var dev := _dev()
	var frames_data := ResourceJson.new(dev).data_of(dev.resource("data/sprite_frames/sub_frames.tres"))
	assert_str(frames_data["class"]).is_equal("SpriteFrames")
	assert_str(frames_data["animations"][0]["frames"][0]["texture"]["$ref"]).is_equal("assets/sprites/sub/sub_00.png")
	var tile_data := ResourceJson.new(dev).data_of(dev.resource("data/neptune_tileset.tres"))
	assert_str(tile_data["class"]).is_equal("TileSet")
	assert_array(tile_data["custom_data_layers"]).has_size(2)
	assert_int(tile_data["sources"][0]["tiles"].size()).is_greater(0)
	assert_str(tile_data["sources"][0]["texture"]["$ref"]).starts_with("assets/tiles/")
	# any other engine class is a problem, never an instance
	for other in ["Node", "AudioStreamPlayer", "GDScript", "Environment"]:
		var reader := ResourceJson.new(dev)
		assert_object(reader.resource_from({"class": other})).is_null()
		assert_array(reader.problems).is_not_empty()
	var typo := ResourceJson.new(dev)
	typo.resource_from({"class": "SpriteFrames", "animatons": []})
	assert_str(typo.problems[0]).contains("animatons")


func test_a_hand_written_sprite_frames_and_tile_set_are_built() -> void:
	var shelf := PackShelf.new()
	shelf.add_picture("assets/a.png", Color.RED, Vector2i(16, 16))
	shelf.add_picture("assets/b.png", Color.BLUE, Vector2i(32, 16))
	var pack := shelf.mount()
	var reader := ResourceJson.new(pack)
	var frames := reader.resource_from({"class": "SpriteFrames", "animations": [
			{"name": "walk", "speed": 8, "loop": true, "frames": [{"texture": {"$ref": "assets/a.png"}}, {"texture": {"$ref": "assets/b.png"}, "duration": 2}]}]}) as SpriteFrames
	assert_array(reader.problems).is_empty()
	assert_array(Array(frames.get_animation_names())).is_equal([&"walk"])
	assert_int(frames.get_frame_count(&"walk")).is_equal(2)
	assert_float(frames.get_frame_duration(&"walk", 1)).is_equal(2.0)
	assert_float(frames.get_animation_speed(&"walk")).is_equal(8.0)
	assert_str(Packs.source_of(frames.get_frame_texture(&"walk", 0))).is_equal(shelf.root + "/assets/a.png")
	var tile_set := reader.resource_from({"class": "TileSet", "physics_layers": [{"collision_layer": 2}], "custom_data_layers": [{"name": "push", "type": TYPE_VECTOR2}],
			"sources": [{"id": 3, "name": "b", "texture": {"$ref": "assets/b.png"}, "padding": false, "tiles": [
				{"at": [1, 0], "physics": [[[-8, -8, 8, -8, 8, 8, -8, 8]]], "data": {"0": [1, -1]}}]}]}) as TileSet
	assert_array(reader.problems).is_empty()
	var source := tile_set.get_source(3) as TileSetAtlasSource
	assert_int(tile_set.get_physics_layer_collision_layer(0)).is_equal(2)
	assert_vector(source.get_tile_data(Vector2i(1, 0), 0).get_custom_data_by_layer_id(0)).is_equal(Vector2(1, -1))
	assert_int(source.get_tile_data(Vector2i(1, 0), 0).get_collision_polygons_count(0)).is_equal(1)
	assert_bool(source.has_tile(Vector2i(0, 0))).is_false()
	shelf.remove()


# --- the references ---------------------------------------------------------------------------------------------------------

func test_a_sub_resource_held_twice_is_written_once_and_read_as_one_object() -> void:
	var track := CutsceneTrack.new()
	track.actor = &"crew"
	track.property = &"frame"
	track.times = PackedFloat64Array([0.0, 4.0])
	track.values = [&"a", &"b"]
	var timeline := CutsceneTimeline.new()
	timeline.length = 4.0
	timeline.tracks = [track, track] as Array[CutsceneTrack]
	var writer := ResourceJson.new()
	var data := writer.data_of(timeline)
	assert_str(data["tracks"][0]["$id"]).is_not_empty()
	assert_dict(data["tracks"][1]).is_equal({"$id": data["tracks"][0]["$id"]})
	var reader := ResourceJson.new()
	var back := reader.resource_from(JSON.parse_string(JSON.stringify(data))) as CutsceneTimeline
	assert_array(reader.problems).is_empty()
	assert_object(back.tracks[0]).is_same(back.tracks[1])
	assert_object(back.tracks[0]).is_not_same(track)
	var lonely := ResourceJson.new().data_of(CutsceneTimeline.new())
	assert_bool(JSON.stringify(lonely).contains("$id")).is_false()                         # a sub-resource used once stays plain
	var missing := ResourceJson.new()
	missing.resource_from({"class": "CutsceneTimeline", "tracks": [{"$id": "nobody"}]})
	assert_str(missing.problems[0]).contains("nothing is called 'nobody'")


func test_a_value_keeps_its_kind_inside_a_dictionary_and_an_untyped_list() -> void:
	var timeline := CutsceneTimeline.new()
	timeline.marks = {"whole": 3.0, "count": 3, "name": &"x", "half": 0.5, "point": Vector2(1.5, 2), "cell": Vector2i(1, 2), "box": Rect2i(1, 2, 3, 4),
			"red": Color(1, 0, 0, 1), "line": PackedVector2Array([Vector2(1, 2)]), "words": PackedStringArray(["a"]), "list": [1.0, &"y", 2]}
	var text := JSON.stringify(ResourceJson.new().data_of(timeline))
	var back := ResourceJson.new().resource_from(JSON.parse_string(text)) as CutsceneTimeline
	var marks := back.marks
	assert_int(typeof(marks["whole"])).is_equal(TYPE_FLOAT)
	assert_int(typeof(marks["count"])).is_equal(TYPE_INT)
	assert_int(typeof(marks["name"])).is_equal(TYPE_STRING_NAME)
	assert_int(typeof(marks["half"])).is_equal(TYPE_FLOAT)
	assert_int(typeof(marks["point"])).is_equal(TYPE_VECTOR2)
	assert_int(typeof(marks["cell"])).is_equal(TYPE_VECTOR2I)
	assert_int(typeof(marks["box"])).is_equal(TYPE_RECT2I)
	assert_int(typeof(marks["red"])).is_equal(TYPE_COLOR)
	assert_int(typeof(marks["line"])).is_equal(TYPE_PACKED_VECTOR2_ARRAY)
	assert_int(typeof(marks["words"])).is_equal(TYPE_PACKED_STRING_ARRAY)
	assert_array([typeof(marks["list"][0]), typeof(marks["list"][1]), typeof(marks["list"][2])]).is_equal([TYPE_FLOAT, TYPE_STRING_NAME, TYPE_INT])
	assert_vector(marks["point"]).is_equal(Vector2(1.5, 2))
	assert_bool(marks["box"] == Rect2i(1, 2, 3, 4)).is_true()


func test_a_path_field_is_written_relative_to_its_pack_and_read_in_the_pack_that_holds_it() -> void:
	var dev := _dev()
	var index := VoiceIndex.new()
	index.ids = PackedInt32Array([1, 2])
	index.paths = PackedStringArray([dev.path_of("assets/audio/voice/voice_0.wav"), "res://data/elsewhere.wav"])
	var data := ResourceJson.new(dev).data_of(index)
	assert_dict(data["paths"][0]).is_equal({"$path": "assets/audio/voice/voice_0.wav"})
	assert_str(data["paths"][1]).is_equal("res://data/elsewhere.wav")                      # a path that is not in a pack stays as it is
	var reader := ResourceJson.new(dev)
	var back := reader.resource_from(JSON.parse_string(JSON.stringify(data))) as VoiceIndex
	assert_array(reader.problems).is_empty()
	assert_array(Array(back.paths)).is_equal(Array(index.paths))
	var bad := ResourceJson.new(dev)
	bad.resource_from({"class": "VoiceIndex", "paths": [{"$path": "../../etc/passwd"}]})
	assert_array(bad.problems).is_not_empty()


func test_a_ref_looks_in_its_own_pack_and_then_down_the_chain_never_up() -> void:
	var shelf := PackShelf.new()
	shelf.add_picture("assets/only_up_here.png", Color.GREEN)
	var pack := shelf.mount()
	assert_array(Packs.chain_ids()).is_equal([shelf.id, PackShelf.base_id()])
	# a file of the pack on top, and a file only the pack below has (dev's tile picture)
	var reader := ResourceJson.new(pack)
	var holder := reader.resource_from({"class": "HudLayout", "bezel": {"$ref": "assets/only_up_here.png"}, "tank_full": {"$ref": "assets/tiles/zone0_tiles.png"}}) as HudLayout
	assert_array(reader.problems).is_empty()
	assert_str(Packs.source_of(holder.bezel)).is_equal(shelf.root + "/assets/only_up_here.png")
	assert_str(Packs.source_of(holder.tank_full)).starts_with(_dev().root)
	# the pack below cannot see what the pack above holds
	var below := ResourceJson.new(_dev())
	below.resource_from({"class": "HudLayout", "bezel": {"$ref": "assets/only_up_here.png"}})
	assert_str(below.problems[0]).contains("no pack holds")
	assert_object(Packs.provider_below(_dev(), "assets/only_up_here.png")).is_null()
	assert_object(Packs.provider_below(pack, "assets/only_up_here.png")).is_same(pack)
	# a reference to something that is not a picture, or that leaves the pack
	var wrong := ResourceJson.new(pack)
	wrong.resource_from({"class": "HudLayout", "bezel": {"$ref": "../x.png"}, "tank_empty": {"$ref": "assets/audio/sfx/angler_chomp_2.wav"}})
	assert_int(wrong.problems.size()).is_equal(2)
	shelf.remove()


func test_a_resource_file_of_an_untrusted_pack_is_never_opened_but_its_json_is() -> void:
	var shelf := PackShelf.new()
	shelf.write_text("data/zones.tres", "[gd_resource type=\"Resource\" format=3]\n")
	shelf.write_text("data/bubble_rules.tres", "[gd_resource type=\"Resource\" format=3]\n")
	shelf.write_json("data/bubble_rules.json", {"class": "BubbleRules", "spawn_chance": 7})
	var pack := shelf.mount()
	assert_bool(pack.trusted).is_false()
	assert_bool(pack.provides("data/zones.tres")).is_false()                              # its .tres is not a form it may read
	assert_object(Packs.holder("data/zones.tres")).is_same(_dev())                       # so dev, below, answers
	assert_bool(pack.provides("data/bubble_rules.tres")).is_true()                        # its data form is
	assert_int((Packs.resource("data/bubble_rules.tres") as BubbleRules).spawn_chance).is_equal(7)
	assert_bool(_dev().trusted).is_true()
	shelf.remove()


# --- the comparison itself --------------------------------------------------------------------------------------------------

func test_the_comparison_sees_a_difference_in_every_kind() -> void:
	var dev := _dev()
	var frames := dev.resource("data/sprite_frames/sub_frames.tres") as SpriteFrames
	var other_frames := frames.duplicate() as SpriteFrames
	other_frames.set_animation_speed(&"all", 99.0)
	var differences: Array[String] = []
	ResourceCompare.same(frames, other_frames, "frames", differences)
	assert_array(differences).is_not_empty()
	var tile_set := dev.resource("data/neptune_tileset.tres") as TileSet
	var other_set := tile_set.duplicate(true) as TileSet
	(other_set.get_source(0) as TileSetAtlasSource).get_tile_data(Vector2i(0, 0), 0).set_custom_data_by_layer_id(1, 999)
	differences = []
	ResourceCompare.same(tile_set, other_set, "tiles", differences)
	assert_array(differences).is_not_empty()
	var zones := dev.resource("data/zones.tres") as ZoneTable
	var other_zones := zones.duplicate(true) as ZoneTable
	other_zones.zones[0].title = "another"
	differences = []
	ResourceCompare.same(zones, other_zones, "zones", differences)
	assert_array(differences).is_not_empty()


func test_every_character_a_text_can_hold_survives_a_file() -> void:
	var table := TextTable.new()
	table.texts = {1: "tab\there", 2: "vertical\u000btab", 3: "back\\v is not a tab", 4: "line\nbreak \"quoted\"", 5: "\u000b\\\u000b"}
	var text := ResourceJson.stringify(ResourceJson.new().data_of(table))
	assert_bool(text.contains("\\u000b")).is_true()
	var back := ResourceJson.new().resource_from(JSON.parse_string(text)) as TextTable
	assert_dict(back.texts).is_equal(table.texts)
