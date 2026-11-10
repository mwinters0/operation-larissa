class_name TestAssetFileNames
extends GdUnitTestSuite
## Teaches: a naming rule checked from the data side. The file of a NAMED entry is `<name>_<number>.<ext>` and the file of an unnamed one
## keeps its made-up name (docs/create/NAMES.md, "Asset file names"; the importer's rule is tools/import/asset_names.py). For every kind that has files
## this suite asks the REGISTRY for the entries and the generated catalogs / SpriteFrames for the paths they hold, and checks that each path
## names the entry, that the file exists, and that no file is left under the old name of a named entry.

const FOE_ZONE_BASE := 35
const COMMON_DECOS := 70
const SFX_OLD := LegacyPack.ROOT + "assets/audio/sfx/sfx_%02d.wav"
const VOICE_OLD := LegacyPack.ROOT + "assets/audio/voice/voice_%d.wav"

var _registry := NameRegistry.original()


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


func test_every_effect_file_is_called_after_its_name_and_number() -> void:
	var catalog := Catalog.sfx_catalog()
	var named := 0
	for n in 52:
		var path := Packs.source_of(catalog.streams[n])
		assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
		if _registry.is_named(&"sound", n):
			assert_str(path.get_file()).is_equal("%s_%d.wav" % [_registry.name_of(&"sound", n), n])
			assert_bool(FileAccess.file_exists(SFX_OLD % n)).override_failure_message("old file " + SFX_OLD % n).is_false()
			named += 1
		else:
			assert_str(path.get_file()).is_equal("sfx_%02d.wav" % n)
	assert_int(named).is_equal(_registry.entries(&"sound").size())


func test_every_speech_file_is_called_after_its_name_and_number() -> void:
	var index := Catalog.voice_index()
	var named := 0
	for i in index.ids.size():
		var id: int = index.ids[i]
		assert_bool(FileAccess.file_exists(index.paths[i])).override_failure_message(index.paths[i]).is_true()
		if _registry.is_named(&"voice", id):
			assert_str(String(index.paths[i]).get_file()).is_equal("%s_%d.wav" % [_registry.name_of(&"voice", id), id])
			assert_bool(FileAccess.file_exists(VOICE_OLD % id)).is_false()
			named += 1
		else:
			assert_str(String(index.paths[i]).get_file()).is_equal("voice_%d.wav" % id)
	assert_int(named).is_equal(_registry.entries(&"voice").size())


func test_every_song_file_is_called_after_its_name_and_number() -> void:
	var catalog := Catalog.music_catalog()
	for i in catalog.ids.size():
		var id: int = catalog.ids[i]
		if _registry.is_named(&"music", id):
			var expected := "%s_%d.ogg" % [_registry.name_of(&"music", id), id]
			assert_str(String(catalog.gm_paths[i]).get_file()).is_equal(expected)
			assert_str(String(catalog.adlib_paths[i]).get_file()).is_equal(expected)


func test_every_named_picture_has_its_file_and_not_the_old_one() -> void:
	for kind: StringName in [&"ui_picture", &"problem_art"]:
		var entries: Dictionary = _registry.entries(kind)
		for picture_name: String in entries:
			var number: int = entries[picture_name]
			var path: String = Assets.ui_picture_path(number) if kind == &"ui_picture" else Assets.problem_art_path(number)
			assert_str(path.get_file()).is_equal("%s_%d.png" % [picture_name, number])
			assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
			assert_bool(FileAccess.file_exists(path.get_base_dir().path_join("%s.png" % _registry.fallback_name(kind, number)))).is_false()


func test_every_named_creature_picture_has_its_file_with_the_zone_in_front_of_a_zones_own_slot() -> void:
	for zone in 7:
		var frames := Catalog.foes_frames(zone)
		for slot in frames.get_frame_count(&"all"):
			var path := Packs.source_of(frames.get_frame_texture(&"all", slot))
			assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
			if _registry.is_named(&"frame", slot, zone):
				var prefix := "foe_z%d_" % zone if slot >= FOE_ZONE_BASE else ""
				assert_str(path.get_file()).is_equal("%s%s_%d.png" % [prefix, _registry.name_of(&"frame", slot, zone), slot])
			else:
				assert_str(path.get_file()).is_equal("foe_z%d_%03d.png" % [zone, slot] if slot >= FOE_ZONE_BASE else "foe_%03d.png" % slot)


func test_every_named_decoration_has_its_file_with_the_art_zone_in_front_of_a_zones_own_slot() -> void:
	for zone in 5:
		var frames := Catalog.decos_frames(zone)
		for slot in frames.get_frame_count(&"all"):
			var path := Packs.source_of(frames.get_frame_texture(&"all", slot))
			assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
			if _registry.is_named(&"deco", slot, zone):
				var prefix := "deco_z%d_" % zone if slot >= COMMON_DECOS else ""
				assert_str(path.get_file()).is_equal("%s%s_%d.png" % [prefix, _registry.name_of(&"deco", slot, zone), slot])
			else:
				assert_str(path.get_file()).is_equal("deco_z%d_%03d.png" % [zone, slot] if slot >= COMMON_DECOS else "deco_%03d.png" % slot)
