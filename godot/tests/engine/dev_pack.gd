class_name DevPack
extends RefCounted
## The dev pack as the ENGINE tests know it. A TEST helper, the twin of `LegacyPack` for the dev pack: dev is committed (`res://packs/dev`),
## so an engine test never skips for want of content and never names the original's sectors, numbers or texts. Dev's numbers are its own (docs/engine/HARD_CODED.md);
## a test that needs a place with a stated property asks for a TEST SECTOR made for it by `tools/dev_pack/` (a module per batch, `test_sectors/batch_a.py` ...).
##
## `tools/run_tests.sh engine` runs the suites with `-- --pack=dev`, so `Catalog` and `Packs` answer from dev; `sector` below reads dev's files directly and
## answers the same whatever pack the process chose.
##
## Teaches: one place that says where a body of test content is and which numbers belong to whom, so that parallel authors never choose the same sector.

## The pack's id and its folder (with a trailing slash, as `LegacyPack.ROOT`).
const ID := &"dev"
const ROOT := "res://packs/dev/"
const SECTORS_DIR := ROOT + "data/sectors"
const CAMPAIGNS_DIR := ROOT + "data/campaigns"

## The playable campaign: sectors 0-3 in play order and the finale 4 (`tools/dev_pack/dev_sectors.py` `dev_tour`).
const TOUR := &"dev_tour"
const TOUR_SECTORS: Array[int] = [0, 1, 2, 3]
const TOUR_FINALE := 4
## Creatures in each tour sector (index = sector): one, two, two, three, and three in the finale.
const TOUR_CREATURES: Array[int] = [1, 2, 2, 3, 3]
## The standard sector's layout: twelve screens in a row, the data canister (piece 0) on screen 3, one more piece on screen 8, math triggers on screens 5 and 9.
const SCREENS := 12
const CANISTER_SCREEN := 3

## Test sectors start here and belong to no campaign. Each batch of test sectors owns twenty numbers; a batch never uses another's (tools/dev_pack/README.md).
const FIRST_TEST_SECTOR := 100
const BATCH_A := Vector2i(100, 119)   ## ground: tiles, walls, currents, screens, sector data and its editors/checks
const BATCH_B := Vector2i(120, 139)   ## creatures, combat, the playfield as the skins see it
const BATCH_C := Vector2i(140, 159)   ## problems, triggers, the calculator, the lock, the log, hints
const BATCH_D := Vector2i(160, 179)   ## flow, campaigns, saves, story, sign-in, HUD
const BATCH_E := Vector2i(180, 199)   ## plumbing: audio, names, assets, catalogs, the pack chain
## The campaign ids a batch may need beside `dev_tour`: `test_a` ... `test_e` (see `campaign_id`).
const BATCHES: Array[String] = ["a", "b", "c", "d", "e"]


## The sector `index` as dev's files hold it (compiled, so `foes` and the script are ready), or null when dev has no such sector.
static func sector(index: int) -> SectorData:
	var path := "%s/sector_%02d/sector_%02d.tres" % [SECTORS_DIR, index, index]
	if not ResourceLoader.exists(path):
		return null
	var data := load(path) as SectorData
	if data != null:
		data.ensure_compiled()
	return data


## The path of a file of the pack (`DevPack.path("data/zones.tres")`).
static func path(rel: String) -> String:
	return ROOT + rel


## The inclusive range of sector numbers of a batch (`"a"` ... `"e"`).
static func batch_range(batch: String) -> Vector2i:
	match batch.to_lower():
		"a": return BATCH_A
		"b": return BATCH_B
		"c": return BATCH_C
		"d": return BATCH_D
		"e": return BATCH_E
	assert(false, "no batch '%s'" % batch)
	return Vector2i(-1, -1)


## The sector number `offset` places into a batch's range (`test_sector("c", 2)` is 142).
static func test_sector(batch: String, offset: int) -> int:
	var span := batch_range(batch)
	assert(span.x + offset <= span.y, "batch %s has no sector at offset %d" % [batch, offset])
	return span.x + offset


## The id of a batch's own test campaign (`&"test_a"`), for a batch whose generator module writes one.
static func campaign_id(batch: String) -> StringName:
	return StringName("test_" + batch.to_lower())
