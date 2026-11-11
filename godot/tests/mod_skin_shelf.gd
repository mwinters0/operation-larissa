class_name ModSkinShelf
extends RefCounted
## Skin mods for tests: scratch mod packs made of the fixtures of `tests/mods/` (`skinny`, `skin_layers`, `skin_faulty`, `skin_layers_faulty`, `skin_hostile`, and the data skin `skin_data`, which has no script) with the pictures a skin draws (`skin/*.png`, flat colours of the
## sizes a skin draws them at) and the shader text the manifests list, or of a whole pack folder (`EXAMPLE_MODERN`: the example pack, which holds its own pictures and shaders), laid over the pack the suite runs on and running (`Mods.sync`). `mount` makes them, `release` takes them away and chooses the
## suite's own pack again, so the next test starts with the game as it ships. The scripted ones need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`); the data skin does not.
##
## Teaches: a test double for a pack that carries code: a real folder in `user://`, written from a fixture and deleted afterwards, so the code under test reads the disk as it does in the game.

const FIXTURES := "res://tests/mods"
## The pictures every skin fixture gets: file -> [colour, size].
const PICTURES := {
	"skin/sub.png": [Color.ORANGE, Vector2i(96, 54)],
	"skin/creature.png": [Color.WHITE, Vector2i(24, 24)],
	"skin/ink.png": [Color.BLACK, Vector2i(16, 16)],
	"skin/piece.png": [Color.YELLOW, Vector2i(24, 20)],
	"skin/dot.png": [Color.RED, Vector2i(4, 4)],
	"skin/sky.png": [Color.CYAN, Vector2i(32, 18)],
}
const GLOW := "skin/glow.gdshader"
## The example packs `examples/packs/<name>/` are folders outside the project, which `Pack.open` reads like any folder. `mount` is given `EXAMPLE_MODERN` for the whole pack folder of the modern one: copied as it is, under the id its manifest says and `_test` (so a copy installed on the developer's machine is not the one in the test).
const EXAMPLE_MODERN := "example:modern"
const EXAMPLES := "../examples/packs"


## Scratch packs of the fixtures `names` (or `"example:<name>"`, an example pack), each laid over the one before (the first over the suite's pack), chosen and synced: the last one is the pack in use.
static func mount(names: Array[String]) -> Array[PackShelf]:
	var shelves: Array[PackShelf] = []
	var base: StringName = &""
	for fixture in names:
		var shelf: PackShelf
		if fixture.begins_with("example:"):
			var folder := example_folder(fixture.trim_prefix("example:"))
			shelf = PackShelf.new(StringName("%s_test" % JSON.parse_string(FileAccess.get_file_as_string(folder + "/pack.json"))["id"]), base)
			shelf.add_mod_fixture(folder)
		else:
			shelf = PackShelf.new(&"", base)
			shelf.add_mod_fixture("%s/%s" % [FIXTURES, fixture])
			add_files(shelf)
		shelf.mount()
		base = shelf.id
		shelves.append(shelf)
	Mods.sync()
	return shelves


## The folder of the example pack `name` (`examples/packs/<name>/`), a path on the file system. A name given to `mount` as `"example:<name>"` is that pack.
static func example_folder(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(EXAMPLES).path_join(name).simplify_path()


## Takes the packs of `shelves` away, the last first, and syncs the mods with the chain that is left.
static func release(shelves: Array[PackShelf]) -> void:
	for i in range(shelves.size() - 1, -1, -1):
		shelves[i].remove()
	shelves.clear()
	Mods.sync()


## The pictures and the shader every skin fixture is given.
static func add_files(shelf: PackShelf) -> void:
	for file: String in PICTURES:
		shelf.add_picture(file, PICTURES[file][0], PICTURES[file][1])
	if not shelf.pack_json("pack.json")["mod"]["skin"].get("shaders", []).is_empty() and not FileAccess.file_exists("%s/%s" % [shelf.root, GLOW]):
		shelf.write_text(GLOW, FileAccess.get_file_as_string("%s/skinny/%s" % [FIXTURES, GLOW]))
