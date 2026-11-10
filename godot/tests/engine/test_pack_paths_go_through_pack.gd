class_name TestPackPathsGoThroughPack
extends GdUnitTestSuite
## Teaches: a rule kept by a test that reads the source. A pack is a folder or a pack file (`<id>.larissa`, read in place), so the path of a file in it (`Pack.path_of`, `Packs.path`, what `Assets`
## makes of them) is a real path for a folder and a virtual one for a pack file: it names the file for a person and for `Packs.file_at` (which finds the pack by the path's start), and no file system
## can open it. Everything that reads a pack's file asks the pack (`Pack.has`, `read_bytes`, `read_text`, `size_of`, `files_in`, `modified_time`; for a path one was handed `Packs.has_file_at`, `bytes_at`). This
## suite reads every script of `src/` and `addons/` and fails on a line that gives such a path straight to `FileAccess`, `DirAccess`, `ResourceLoader`, `Image.load*` or `OS.shell_open`.
## It sees one line at a time: a path put in a variable first and opened on the next line escapes it, which is why the lookups are also played out on a pack file (`test_pack_file_plays`).

## [script, a fragment of the line, why that line may open a pack's path]. Every entry must still match a line (a fixed line leaves the list).
const ALLOWED := [
	["res://src/core/catalog.gd", "each.trusted and DirAccess", "only a trusted pack is asked: a folder of the project, never a pack file (`Pack.trusted`)"],
	["res://src/core/packs.gd", "else FileAccess.file_exists(path)", "`has_file_at`: the path is in no pack (a pack's is asked of the pack on the same line)"],
	["res://src/core/packs.gd", "else FileAccess.get_file_as_bytes(path)", "`bytes_at`: the path is in no pack (a pack's is asked of the pack on the same line)"],
]
## Not scanned: other people's code; the pack itself, which is the one place that opens its own folder (and reads its pack file through `PackArchive`).
const SKIPPED := ["res://addons/gdUnit4/", "res://addons/godot_ai/", "res://addons/godot_sandbox/", "res://addons/midi/", "res://src/core/pack.gd"]

var _pack_path := RegEx.create_from_string("Packs\\.path\\s*\\(|(?<!SkinChoice)\\.path_of\\s*\\(|Assets\\.\\w*path\\w*\\s*\\(|\\.root\\b")
var _opens := RegEx.create_from_string("\\b(FileAccess|DirAccess|ResourceLoader)\\.|Image\\.load|OS\\.shell_open")


func _scripts() -> Array[String]:
	var found: Array[String] = []
	for folder in ["res://src", "res://addons"]:
		for path in SourceScan.scripts_under(folder):
			if not SKIPPED.any(func(skipped: String) -> bool: return path.begins_with(skipped)):
				found.append(path)
	return found


func _hits() -> Array[Array]:
	var found: Array[Array] = []
	for path in _scripts():
		var number := 0
		for code in SourceScan.code_lines_of(path):
			number += 1
			if _pack_path.search(code) != null and _opens.search(code) != null:
				found.append([path, number, code.strip_edges()])
	return found


func _allowed(hit: Array) -> bool:
	return ALLOWED.any(func(entry: Array) -> bool: return entry[0] == hit[0] and String(hit[2]).contains(entry[1]))


func test_no_line_opens_the_path_of_a_pack_file_with_the_file_system() -> void:
	var stray: Array[String] = []
	for hit in _hits():
		if not _allowed(hit):
			stray.append("%s:%d  %s" % [hit[0], hit[1], hit[2]])
	assert_array(stray).override_failure_message("a pack's path given to the file system (ask the Pack: has, read_bytes, read_text, size_of, files_in, modified_time; or Packs.has_file_at / bytes_at):\n" + "\n".join(stray)).is_empty()


func test_the_list_names_lines_that_exist_and_says_why() -> void:
	var hits := _hits()
	for entry: Array in ALLOWED:
		assert_bool(hits.any(func(hit: Array) -> bool: return hit[0] == entry[0] and String(hit[2]).contains(entry[1]))).override_failure_message("%s: %s" % [entry[0], entry[1]]).is_true()
		assert_str(entry[2]).is_not_empty()
