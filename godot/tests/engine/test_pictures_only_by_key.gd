class_name TestPicturesOnlyByKey
extends GdUnitTestSuite
## Teaches: a rule kept by a test that reads the source. The engine finds a picture ONLY by its key (`ui_picture/title_sky`), through the chain's picture tables (`Pictures`); no file name, folder or number of a pack means
## anything to it. This suite reads every script of `src/` and of our addons and fails on code that would find a picture another way: a picture path made of a number or a folder, a key guessed from a file name, a picture
## loaded from a pack's file outside the table's resolver, or one of the helpers that did those things. A new need is either a key (a row of a pictures.json) or an entry below with the reason it is none of these.

## [script, a fragment of the line, why that line is not a picture found by its file]. Every entry must still match a line (a fixed line leaves the list).
const ALLOWED := [
	["res://src/core/pictures.gd", ".texture(rel)", "the resolver itself: the file a table's row names, in the pack that holds the row"],
	["res://src/packs/pack_check.gd", "live.texture(rel)", "the check decodes the file a row names, to say whether the engine can read it"],
	["res://src/mods/mod_assets.gd", "pack.texture(rel)", "the check of a mod's own `skin/` and `problems/` files: they decode"],
	["res://src/mods/mod_draw.gd", "pack.texture(path)", "a draw list names a file of the mod's OWN pack (`skin/x.png`), never another pack's; a key goes through `Assets.picture_by_key`"],
	["res://src/packs/pack_export.gd", "\"ui_picture/%s.png\"", "the export writes a campaign's picture as a file of the exported pack and a row of its table that names it"],
	["res://src/debug/foe_sandbox.gd", "_save_screenshot(\"%sm4_sandbox", "a screenshot the tool writes, not a picture the game shows"],
]
## Not scanned: other people's code.
const SKIPPED := ["res://addons/gdUnit4/", "res://addons/godot_ai/", "res://addons/godot_sandbox/", "res://addons/midi/", "res://src/core/pack.gd"]

## What made a picture path from a number or guessed a key from a file name, by name: none of these exists.
var _helpers := RegEx.create_from_string("\\b(ui_picture|problem_art|background)_(path|rel)\\b|\\bkey_of_rel\\b|\\bKIND_FOLDERS\\b|\\bPLAIN_FOLDERS\\b|\\btexture_at\\b|\\bfile_stem\\b|\\b\\w+_by_number\\b|\\bkey_files\\b|\\bPathPictures\\b")
## A string that is a folder of a pack's pictures, or a picture file name made from numbers (`%` in front of `.png`).
var _picture_folder := RegEx.create_from_string("assets/(ui|problem_art|sprites|tiles|backgrounds|pictures|authoring_tool)\\b|%[0-9a-z]*\\.png$")
## A picture asked of a pack by a file: a call of `Pack.texture`, or the door's `file_at` taken for a texture.
var _texture_by_file := RegEx.create_from_string("(?<!PromptSender)\\.texture\\(|file_at\\([^)]*\\)\\s+as\\s+(Texture|CompressedTexture|ImageTexture)")
## A key made from a file's name: a name of a file (`get_basename`, `get_file`) on the line of a picture kind.
var _file_name := RegEx.create_from_string("\\.get_basename\\(|\\.get_file\\(")
var _kind_prefix := RegEx.create_from_string("^(ui_picture|problem_art|background|frame|deco|tile)/")


func _scripts() -> Array[String]:
	var found: Array[String] = []
	for folder in ["res://src", "res://addons"]:
		for path in SourceScan.scripts_under(folder):
			if not SKIPPED.any(func(skipped: String) -> bool: return path.begins_with(skipped)):
				found.append(path)
	return found


## Every line of a script that breaks one of the rules, as [path, line number, the line, the rule].
func _hits() -> Array[Array]:
	var found: Array[Array] = []
	for path in _scripts():
		var number := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			number += 1
			found.append_array(_broken_by(path, number, line))
	return found


func _broken_by(path: String, number: int, line: String) -> Array[Array]:
	var parts := SourceScan.parts(line)
	var code: String = parts["code"]
	var strings: Array = parts["strings"]
	var rules: Array[String] = []
	if _helpers.search(code) != null:
		rules.append("a helper that makes a picture path or a key from a number or a file name")
	if _texture_by_file.search(code) != null:
		rules.append("a picture asked of a pack by its file")
	for literal: String in strings:
		if _picture_folder.search(literal) != null:
			rules.append("'%s' is a folder or a file name of pictures" % literal)
	if _file_name.search(code) != null and strings.any(func(literal: String) -> bool: return _kind_prefix.search(literal) != null):
		rules.append("a key made from a file name")
	var found: Array[Array] = []
	for rule in rules:
		found.append([path, number, line.strip_edges(), rule])
	return found


func _allowed(hit: Array) -> bool:
	return ALLOWED.any(func(entry: Array) -> bool: return entry[0] == hit[0] and String(hit[2]).contains(entry[1]))


func test_no_picture_is_found_by_a_number_a_file_or_a_guessed_key() -> void:
	var stray: Array[String] = []
	for hit in _hits():
		if not _allowed(hit):
			stray.append("%s:%d  %s   (%s)" % [hit[0], hit[1], hit[2], hit[3]])
	assert_array(stray).override_failure_message("a picture found other than by its key (hold a key, a row of a pictures.json; `Pictures.resolve`):\n" + "\n".join(stray)).is_empty()


func test_the_list_names_lines_that_exist_and_says_why() -> void:
	var hits := _hits()
	for entry: Array in ALLOWED:
		assert_bool(hits.any(func(hit: Array) -> bool: return hit[0] == entry[0] and String(hit[2]).contains(entry[1]))).override_failure_message("%s: %s" % [entry[0], entry[1]]).is_true()
		assert_str(entry[2]).is_not_empty()


## The scanner sees what it is for, and leaves a sentence alone.
func test_the_scanner_sees_each_way_to_find_a_picture_by_file_name() -> void:
	assert_int(_broken_by("x", 1, "var p := Assets.ui_picture_path(1039)").size()).is_equal(1)
	assert_int(_broken_by("x", 1, "var p := pack.texture(\"art/a.png\")").size()).is_equal(1)
	assert_int(_broken_by("x", 1, "var p := Packs.file_at(path) as Texture2D").size()).is_equal(1)
	assert_int(_broken_by("x", 1, "var p := \"res://packs/legacy/assets/tiles/zone0_tiles.png\"").size()).is_equal(1)
	assert_int(_broken_by("x", 1, "var p := \"bg_s%02d_%02d.png\" % [1, 2]").size()).is_equal(1)
	assert_int(_broken_by("x", 1, "var key := \"frame/\" + rel.get_file().get_basename()").size()).is_equal(1)
	assert_int(_broken_by("x", 1, "var key := \"ui_picture/\" + picture_name").size()).is_equal(0)                  # (a key from a name the code says)
	assert_int(_broken_by("x", 1, "sender_icon.texture = PromptSender.texture(slot)   # texture_at").size()).is_equal(0)
	assert_int(_broken_by("x", 1, "var rel := \"audio/%s.ogg\" % clip").size()).is_equal(0)
