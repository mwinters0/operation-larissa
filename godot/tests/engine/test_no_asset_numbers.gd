class_name TestNoAssetNumbers
extends GdUnitTestSuite
## Teaches: a test that reads the PROJECT'S OWN SOURCE as data to keep a rule true. The rule (docs/create/NAMES.md, B4): code says
## `Assets.ui_picture(&"title_sky")` and `Audio.play_sfx(&"begin")`, never picture 1039 or sound 0x16; the number of
## a thing lives in the registry (names/original.json) and in the resolvers that read it, and nowhere else. A new
## `1039` in a scene script would make a later renaming of the assets silently wrong, so this fails instead.
##
## What counts: a whole number from 1000 to 12999 written in code, or a two-digit hexadecimal number on a line about sounds
## (comments and the inside of strings do not count), a string that names a numbered picture file (`ui_1039`, `pa_2046`, `sfx_28`), and a path into the
## asset folders that the resolvers own. The allow-list below says why each exception is not an asset id.

const SOURCE := "res://src"
## Files that ARE the registry or the resolver: asset numbers and asset paths are their job.
const OWNERS := {
	"res://src/core/name_registry.gd": "the registry: the first and last number of each kind",
	"res://src/core/assets.gd": "the resolver of the picture kinds: which folder a picture number lives in",
}
## Numbers that are not asset ids. Each is exact: a second one in the same file is a failure again.
const NOT_ASSET_IDS := {
	"res://src/debug/reach_sweep.gd": {1200: "ticks the sweep simulates"},
	"res://src/debug/sound_test.gd": {2000: "characters the log keeps"},
	"res://src/mods/mod_spec.gd": {8000: "the most guest heap allocations a mod may be granted (a ceiling)"},
	"res://src/mods/mod_draw.gd": {4000: "the most commands of a skin mod's draw list"},
	"res://src/mods/mod_shader.gd": {8192: "the most bytes of a skin mod's shader"},
	"res://src/problems/diagrams/diagram_base.gd": {1200: "twelve hours on a clock face (hhmm)"},
	"res://src/resources/hall_entry.gd": {9999: "the most tries the hall of fame holds"},
	"res://src/resources/player_profile.gd": {9999: "the most tries a record holds"},
	"res://src/resources/screen_data.gd": {1020: "the biggest x of a screen record (x / 4 in one byte)"},
}
## Where a path into the asset folders of a pack (`res://packs/<id>/assets/ui` ...) may be written: only in the resolver.
const ASSET_FOLDERS: Array[String] = ["assets/ui", "assets/problem_art", "assets/audio"]
const PACKS_ROOT := "res://packs/"

var _number := RegEx.create_from_string("(?<![\\w.%])(0[xX][0-9a-fA-F]{2}|[1-9][0-9]{3,4})(?![\\w.])")
var _sound_words := RegEx.create_from_string("(?i)sfx|sound")
var _numbered_file := RegEx.create_from_string("\\b(ui|pa|sfx)_[0-9]+")
## A file name that ends in the original's number: `lock_tick_38.wav`, `title_sky_1039.png` (docs/create/NAMES.md, "Asset file names").
var _numbered_asset_name := RegEx.create_from_string("_[0-9]+\\.(png|wav|ogg)\\b")


func test_no_asset_number_is_written_in_the_source() -> void:
	var found: Array[String] = []
	for path in _scripts(SOURCE):
		if OWNERS.has(path):
			continue
		var allowed: Dictionary = NOT_ASSET_IDS.get(path, {})
		var line_number := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			line_number += 1
			var parts := _parts(line)
			for value in _asset_numbers(parts["code"]):
				if not allowed.has(value):
					found.append("%s:%d  %d  (%s)" % [path, line_number, value, line.strip_edges()])
			for literal: String in parts["strings"]:
				if (_numbered_file.search(literal) != null or _numbered_asset_name.search(literal) != null) and not literal.contains("%"):
					found.append("%s:%d  the string '%s' names a numbered asset" % [path, line_number, literal])
				if _is_asset_path(literal):
					found.append("%s:%d  the path '%s' belongs to the resolver (Assets)" % [path, line_number, literal])
	assert_array(found).override_failure_message("asset numbers or paths outside the registry and the resolver:\n" + "\n".join(found)).is_empty()


## The allow-list stays honest: every entry is still in its file.
func test_every_exception_is_still_needed() -> void:
	for path: String in NOT_ASSET_IDS:
		var source := FileAccess.get_file_as_string(path)
		for value: int in NOT_ASSET_IDS[path]:
			assert_bool(source.contains(str(value))).override_failure_message("%s no longer has %d: remove the exception" % [path, value]).is_true()


## The file-name patterns: a name with its number (`title_sky_1039.png`) is as much a number in code as `ui_1039`.
func test_the_file_name_patterns_see_numbered_asset_names() -> void:
	assert_bool(_numbered_asset_name.search("lock_tick_38.wav") != null).is_true()
	assert_bool(_numbered_asset_name.search(DevPack.ROOT + "assets/ui/title/title_sky_1039.png") != null).is_true()
	assert_bool(_numbered_asset_name.search("bg_s%02d_%02d.png") != null).is_false()
	assert_bool(_numbered_asset_name.search("sector_world.png") != null).is_false()
	assert_bool(_numbered_file.search("ui_1039") != null).is_true()


## A path into the asset folders of any pack is the resolver's business, whatever the pack is called.
func test_a_path_into_the_asset_folders_of_any_pack_is_seen() -> void:
	assert_bool(_is_asset_path(DevPack.ROOT + "assets/ui/title/title_sky_1039.png")).is_true()
	assert_bool(_is_asset_path("res://packs/another/assets/audio/sfx/x.wav")).is_true()
	assert_bool(_is_asset_path("res://packs/another/data/zones.tres")).is_false()
	assert_bool(_is_asset_path("res://src/ui/hud.tscn")).is_false()


func _is_asset_path(literal: String) -> bool:
	if not literal.begins_with(PACKS_ROOT):
		return false
	var inside := literal.trim_prefix(PACKS_ROOT).get_slice("/", 0)
	for folder in ASSET_FOLDERS:
		if literal.begins_with(PACKS_ROOT + inside + "/" + folder):
			return true
	return false


## The scanner itself, on a few lines.
func test_the_scanner_ignores_comments_and_strings_and_sees_code() -> void:
	assert_str(_parts("var a := 1039   # picture 1039")["code"]).contains("1039").not_contains("picture")
	assert_str(_parts("var a := \"1039\"")["code"]).not_contains("1039")
	assert_array(_parts("var a := \"x # y\" + b # c")["strings"]).is_equal(["x # y"])
	assert_array(_asset_numbers("var a := 1039")).is_equal([1039])
	assert_array(_asset_numbers("Audio.play_sfx(0x1F, 12, 1200.0, 3 + 20000)")).is_equal([31])
	assert_array(_asset_numbers("var y := 0xe8 + 42")).is_empty()           # a hexadecimal number about something else


## The numbers of one line of code (see `_parts`) that look like an asset id.
func _asset_numbers(code: String) -> Array[int]:
	var found: Array[int] = []
	var about_sounds := _sound_words.search(code) != null
	for hit in _number.search_all(code):
		var text := hit.get_string()
		if text.begins_with("0"):
			if about_sounds:
				found.append(text.hex_to_int())
		elif int(text) >= 1000 and int(text) <= 12999:
			found.append(int(text))
	return found


func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	found.sort()
	return found


## Splits one line of GDScript: `code` is the line without its comment and with the inside of its strings emptied,
## `strings` the text inside each string.
func _parts(line: String) -> Dictionary:
	var code := ""
	var strings: Array[String] = []
	var quote := ""
	var current := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote.is_empty():
			if c == "#":
				break
			if c == "\"" or c == "'":
				quote = c
				current = ""
			code += c
		elif c == "\\" and i + 1 < line.length():
			current += line.substr(i, 2)
			i += 1
		elif c == quote:
			strings.append(current)
			quote = ""
			code += c
		else:
			current += c
		i += 1
	return {"code": code, "strings": strings}
