class_name SkinRoster
extends RefCounted
## Test helper: the skins that the "skins don't change the game" tests are run with. `all()` is every skin that ships
## (`SkinChoice.available()`: whatever is in `res://skins/`, so a new skin is in the tests the moment its folder is there), the tiny test
## skin, and a HOSTILE one that does everything a skin could try in order to change the game.
##
## Teaches: a test that covers what does not exist yet. Nothing here names the proof skins: the list is asked for, so a skin added next
## month is compared with the original without a line of test code being written.

const TINY := "res://tests/skins/tiny/skin.tres"
const VANDAL_SCENE := "res://tests/skins/hostile/vandal_presenter.tscn"


## The skin mods that are mounted (`mount_mod_skins`): a data skin (no script), a good scripted one and a faulty one. Held here so that the suites that go through the roster mount them in `before` and release them in `after`.
static var _mounted: Array[PackShelf] = []


## Mounts the skin mods of `tests/mods/` (`skin_data`, `skinny`, `skin_faulty`) as packs over the suite's, so `all()` has them. The data skin needs no Sandbox, the other two are left out when the godot-sandbox
## extension is not loaded. Does nothing when they are mounted.
static func mount_mod_skins() -> void:
	if _mounted.is_empty():
		var names: Array[String] = ["skin_data"]
		if ModLoader.sandbox_available():
			names.append_array(["skinny", "skin_faulty"] as Array[String])
		_mounted = ModSkinShelf.mount(names)


## Takes them away again (and chooses the suite's own pack).
static func release_mod_skins() -> void:
	ModSkinShelf.release(_mounted)


## The skin mods that run (mounted by `mount_mod_skins`).
static func mod_skins() -> Array[GameSkin]:
	var found: Array[GameSkin] = []
	for shelf in _mounted:
		Mods.loader().resume(String(shelf.id))                           # (the faulty one is quarantined by the test before: it is offered again)
		var skin := SkinChoice.load_skin(shelf.id)
		assert(skin is ModSkin, "the mod skin %s is not running" % shelf.id)
		found.append(skin)
	return found


## Every skin that ships, the original first (not the skin mods that run, `mod_skins`).
static func shipped() -> Array[GameSkin]:
	var found: Array[GameSkin] = []
	for id in SkinChoice.available():
		var skin := SkinChoice.load_skin(id)
		if not skin is ModSkin:
			found.append(skin)
	return found


## The shipped skins, the tiny test skin, the hostile one and the skin mods that are mounted.
static func all() -> Array[GameSkin]:
	var found := shipped()
	found.append(load(TINY) as GameSkin)
	found.append(hostile())
	found.append_array(mod_skins())
	return found


## A skin that tries it all: its presenter scribbles over everything the skin API gives it (`SkinVandal`), it maps `resources` for rules and
## content (a tuning with a huge wall box, empty tables of zones and triggers, no hit rectangles, a problem without records, sectors
## with nothing in them, no texts, no bubble rules), and it has pictures, another filter and no pixel snapping. `GameSkin.refused_resources`
## lists those keys: none of them may take effect.
static func hostile() -> GameSkin:
	var skin := GameSkin.new()
	skin.id = &"hostile"
	skin.display_name = "Hostile test skin: tries to change the rules"
	skin.presenter_scene = load(VANDAL_SCENE) as PackedScene
	var render := RenderSettings.new()
	render.texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	render.snap_transforms = false
	render.snap_vertices = false
	skin.render = render
	var marker := load("res://tests/skins/tiny/marker.png") as Texture2D
	skin.pictures = {"background/bg_s00_00": marker, "frame/dolphin_swim_0": marker}
	var doctored: Dictionary[String, Resource] = {}
	doctored["zones"] = ZoneTable.new()
	doctored["trigger_table"] = TriggerTable.new()
	doctored["bubble_rules"] = BubbleRules.new()
	for part in ["common", "ink", "zone0", "zone1", "zone2", "zone3", "zone4", "zone5", "zone6"]:
		doctored["sprite_meta/sprite_meta_%s" % part] = SpriteMetaTable.new()
	var problem := Catalog.problem_type(0).duplicate() as ProblemType
	problem.records = []
	doctored["problems/problem_type_00"] = problem
	doctored["problems/ui_strings"] = TextTable.new()
	for index in Catalog.sector_ids():
		doctored[data_key(Catalog.sector_path(index))] = SectorData.new()
	skin.resources = doctored
	return skin


## "res://packs/dev/data/zones.tres" -> "zones": the key a skin's `resources` has for a data file of any pack of the chain (also for a file of the project's own `res://data/`).
static func data_key(path: String) -> String:
	return path.substr(path.find("/data/") + "/data/".length()).get_basename()
