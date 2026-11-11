class_name ModProblemShelf
extends RefCounted
## Problem-screen mods for tests: scratch mod packs made of the fixtures of `tests/mods/` (`tides`, `tides_faulty`, `tides_hostile`, `tides_spinner`) with what a problem type of a pack is (the data of type 40, "fish in rows", made here
## in code and written in the data form: its words, its records, how an answer is judged, the diagram family `mod`) and the pictures and shader the screens draw (`problems/*`), laid over the pack the suite runs on and running
## (`Mods.sync`). `plain` is the same type in a pack with no mod at all, the baseline a mod's problem is compared with. `release` takes the packs away and chooses the suite's own pack again. They need the godot-sandbox
## extension (`uv run tools/fetch_sandbox.py`).
##
## Teaches: a test double for a pack that adds content AND carries code, built the way a creator would: the data is a file of the pack, the script a fixture, and nothing of either is known to the game but through the chain.

const FIXTURES := "res://tests/mods"
## The problem type the fixtures draw, and the original types (of the suite's own pack) they opt in to draw by number: 3 has a build-up, 5 has not, and every other original type keeps its own diagram.
const TYPE := 40
const ORIGINALS: Array[int] = [3, 5]
## The original type the plays use, and one of the original types no fixture draws.
const ORIGINAL := 3
const NOT_DRAWN := 4
## The pictures every problem-screen fixture gets: file -> [colour, size].
const PICTURES := {
	"problems/fish.png": [Color.ORANGE, Vector2i(8, 8)],
	"problems/dot.png": [Color.RED, Vector2i(4, 4)],
}
const GLOW := "problems/glow.gdshader"
const WORDS := ["How many fish are in {0} rows of {1}?", "Count one row, then count the rows.", "{0} rows of {1} make {2}.", "Well fished!"]


## Scratch packs of the fixtures `names`, each laid over the one before (the first over the suite's pack), chosen and synced: the last one is the pack in use.
static func mount(names: Array[String]) -> Array[PackShelf]:
	var shelves: Array[PackShelf] = []
	var base: StringName = &""
	for fixture in names:
		var shelf := PackShelf.new(&"", base)
		shelf.add_mod_fixture("%s/%s" % [FIXTURES, fixture])
		add_files(shelf)
		shelf.mount()
		base = shelf.id
		shelves.append(shelf)
	Mods.sync()
	return shelves


## The original type with a replay after a right answer that the packs of a test have: type 6 as the suite's pack holds it, with the replay of two pictures (the diagram spec's "pictures" mode: the second and the third of its art, 88 ticks).
const REPLAY := 6
const REPLAY_TICKS := 88


## One scratch pack of the fixture `name` (`mod` overrides keys of its manifest's mod entry), laid over the suite's pack, chosen and synced; with `replay`, the pack also holds type 6 with a replay (`replay_type`) and the manifest lists it among the types the mod draws.
static func mount_one(name: String, mod: Dictionary = {}, replay := false) -> PackShelf:
	var shelf := PackShelf.new()
	var overrides := mod.duplicate(true)
	if replay:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/pack.json" % [FIXTURES, name]))
		var problems: Dictionary = (overrides.get("problems", fixture["mod"]["problems"]) as Dictionary).duplicate(true)
		problems["types"] = (problems["types"] as Array) + [REPLAY]
		overrides["problems"] = problems
	shelf.add_mod_fixture("%s/%s" % [FIXTURES, name], overrides)
	add_files(shelf)
	if replay:
		shelf.write_json("data/problems/problem_type_%02d.json" % REPLAY, ResourceJson.new().data_of(replay_type()))
	shelf.mount()
	Mods.sync()
	return shelf


## Type 6 of the suite's pack with the replay of two pictures after a right answer.
static func replay_type() -> ProblemType:
	var type: ProblemType = Catalog.problem_type_unskinned(REPLAY).duplicate(true)
	type.diagram["success"] = {"mode": "pictures", "pos": [100, 100], "flip_field": 0, "sfx": 41, "end": REPLAY_TICKS, "frames": [{"tick": 22, "pic": 1}, {"tick": 44, "pic": 2}]}
	return type


## A pack with the type and no mod: what a problem of the type is without anybody drawing it.
static func plain() -> PackShelf:
	var shelf := PackShelf.new()
	shelf.write_json("data/problems/problem_type_%02d.json" % TYPE, ResourceJson.new().data_of(problem_type()))
	shelf.mount()
	Mods.sync()
	return shelf


## A pack with type 6 and its replay and no mod: what the replay is without anybody drawing it.
static func plain_replay() -> PackShelf:
	var shelf := PackShelf.new()
	shelf.write_json("data/problems/problem_type_%02d.json" % REPLAY, ResourceJson.new().data_of(replay_type()))
	shelf.mount()
	Mods.sync()
	return shelf


## Takes the packs of `shelves` away, the last first, and syncs the mods with the chain that is left.
static func release(shelves: Array[PackShelf]) -> void:
	for i in range(shelves.size() - 1, -1, -1):
		shelves[i].remove()
	shelves.clear()
	Mods.sync()


## The type, its pictures and its shader, written into `shelf`.
static func add_files(shelf: PackShelf, type: ProblemType = null) -> void:
	shelf.write_json("data/problems/problem_type_%02d.json" % TYPE, ResourceJson.new().data_of(type if type != null else problem_type()))
	for file: String in PICTURES:
		shelf.add_picture(file, PICTURES[file][0], PICTURES[file][1])
	if not FileAccess.file_exists("%s/%s" % [shelf.root, GLOW]):
		shelf.write_text(GLOW, FileAccess.get_file_as_string("%s/tides/%s" % [FIXTURES, GLOW]))


## Problem type 40: "how many fish in `a` rows of `b`", the answer `a * b` (field 2), three records, the calculator, the diagram family `mod` with a plain picture (the number of rows) for when nobody draws it.
static func problem_type(family: String = "mod") -> ProblemType:
	var type := ProblemKit.type_of("exact", "ccn", 2, [
		ProblemKit.flat([3, 4, ProblemKit.decimal(12.0, 0)]),
		ProblemKit.flat([2, 5, ProblemKit.decimal(10.0, 0)]),
		ProblemKit.flat([6, 2, ProblemKit.decimal(12.0, 0)]),
	], 0.0, false, [0, 0, 1])
	type.id = TYPE
	type.title = "Fish in rows"
	type.texts = PackedStringArray(WORDS)
	type.text_ids = PackedInt32Array([0, 0, 0, 0])
	type.diagram = {"family": family, "items": [{"text": {"field": 0}, "box": [100, 100], "y": 100}]}
	return type
