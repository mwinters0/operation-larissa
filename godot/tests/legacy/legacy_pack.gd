class_name LegacyPack
extends RefCounted
## Is the original game there? A TEST helper (the engine does not know the original: it is a pack like any other, `Packs`). The legacy pack is what the
## importer writes from the player's own copy of the game (docs/play/LEGACY.md): a real folder of the project (`res://packs/legacy`, git-ignored) with the
## pictures and sounds in `assets/`, the data made of the game's files in `data/` and the MIDI songs in `midi/`. None of it is in the repository, so a fresh
## checkout has the code, the tools and the tests but not the game, and the suites that check the original say so and skip instead of failing.
##
## THE SWITCH. With the environment variable `NEPTUNE_LEGACY_AS_DATA=1` the first `present()` exports the legacy pack in the data form (`PackExport.complete`) to
## `AS_DATA_DIR` and puts that folder first in `Packs.folders`, so the pack called `legacy` that every suite chooses is the exported one: not trusted, read only through the
## data form (no `.tres`, no `ResourceLoader`). The fidelity tests then play the pack that leaves the project. A test that names the authoring files (`ROOT`, `root()`:
## `load(ROOT + "data/...tres")`) still reads the project's folder. `docs/engine/DEVELOPING.md` "Running the legacy suite on the exported pack".
##
## Teaches: asking once, in one place, whether the content a test is built to check exists, and leaving the rest of the code free of the question; and one
## root for a whole body of content (`ROOT`, `path`), so that no test spells where it is. Test suites that need the game skip with `NEED_THE_IMPORTER` when
## `present()` is false.

## The pack's id.
const ID := &"legacy"
## Where the legacy pack is, with a trailing slash (tools/import/common.py `legacy_root`). Every path of the original's pictures,
## sounds, songs and generated data is `ROOT + "assets/..."`, `ROOT + "data/..."`, `ROOT + "midi/..."`.
const ROOT := "res://packs/legacy/"
## The environment variable that makes the legacy suite play the data-form export, and where the export is made (replaced by each run that asks for it).
const AS_DATA_VARIABLE := "NEPTUNE_LEGACY_AS_DATA"
const AS_DATA_DIR := "user://legacy_as_data"
## The folders of sector folders and of campaigns in it (no trailing slash): the sectors 0-31 and the campaigns Voyager and Expert.
const SECTORS_DIR := ROOT + "data/sectors"
const CAMPAIGNS_DIR := ROOT + "data/campaigns"


## The path of `rel` (relative to the pack: `data/zones.tres`, `assets/tiles/zone0_tiles.png`) in the project.
static func path(rel: String) -> String:
	return ROOT + rel


## The folder of the pack without the trailing slash (what `Pack.root` holds).
static func root() -> String:
	return ROOT.trim_suffix("/")


## What the tools say, here and in `tools/import`: the same words everywhere so they can be searched for.
const NEED_THE_IMPORTER := "run the importer on your copy of the game (uv run tools/import/import_all.py), then let Godot import (tools/godot.sh --headless --path godot --import)"

## One output of each importer step; a half-finished import is missing some of them.
const WITNESSES: Array[String] = [
	"res://packs/legacy/data/sectors/sector_00/sector_00.tres",
	"res://packs/legacy/data/sectors/sector_31/sector_31.tres",
	"res://packs/legacy/data/campaigns/voyager.tres",
	"res://packs/legacy/data/campaigns/expert.tres",
	"res://packs/legacy/data/zones.tres",
	"res://packs/legacy/data/trigger_table.tres",
	"res://packs/legacy/data/neptune_tileset.tres",
	"res://packs/legacy/data/sprite_meta/sprite_meta_common.tres",
	"res://packs/legacy/data/sprite_frames/sub_frames.tres",
	"res://packs/legacy/data/problems/problem_type_00.tres",
	"res://packs/legacy/data/ui/hud_layout.tres",
	"res://packs/legacy/data/sfx_catalog.tres",
	"res://packs/legacy/data/music_catalog.tres",
	"res://packs/legacy/data/voice_index.tres",
	"res://packs/legacy/data/story/news_cartoon.tres",
	"res://packs/legacy/assets/tiles/zone0_tiles.png",
	"res://packs/legacy/assets/tiles/invisible_wall.png",
]


## The witnesses that are not there, in the order of `WITNESSES` (`witnesses`: another list, for a test).
static func missing(witnesses: Array[String] = WITNESSES) -> Array[String]:
	var out: Array[String] = []
	for path in witnesses:
		if not FileAccess.file_exists(path):
			out.append(path)
	return out


## True when the legacy pack is there and the importer's optional transcripts step gave its voice clips their texts
## (tools/import/import_all.py `--transcripts`). The suites that compare clips with their words skip without them.
static func has_transcripts() -> bool:
	if not present():
		return false
	var index := load(ROOT + "data/voice_index.tres") as VoiceIndex
	if index == null:
		return false
	for text in index.transcripts:
		if text != "":
			return true
	return false


## True when the importer has written the legacy pack (every witness is there). The first call, with the switch on, makes the suite play the export (`play_the_export`).
static func present() -> bool:
	var here := missing().is_empty()
	if here and as_data_asked() and not _switched:
		play_the_export()
	return here


static var _switched := false
static var _export_error := ""


## Is the switch on (`AS_DATA_VARIABLE` is "1")?
static func as_data_asked() -> bool:
	return OS.get_environment(AS_DATA_VARIABLE) == "1"


## Exports legacy in the data form to `AS_DATA_DIR`, puts that folder first among the pack folders and chooses again (`--pack=legacy` finds the export). Once per process;
## what went wrong stays in `export_error` (empty when the export was made and the chain is the export).
static func play_the_export() -> void:
	if _switched:
		return
	_switched = true
	var options := PackExport.Options.new()
	options.pack_id = ID
	options.reach = false
	var made := PackExport.complete(ID, AS_DATA_DIR, options)
	if not made.ok():
		_export_error = made.text()
		push_error("LegacyPack: the data-form export of legacy failed, so the suite plays the project's folder: " + _export_error)
		return
	Packs.folders.insert(0, AS_DATA_DIR)
	Packs.start()


## The text of sector `index`'s creature script as the pack that is played keeps it: its `.foe` file (the pack's own folder, or the project's for an authoring sector).
static func played_foe_text(index: int) -> String:
	var holder := Packs.sector_owner(index)
	if holder != null:
		return holder.read_text(SectorJson.foe_rel(index))
	return FileAccess.get_file_as_string(Catalog.foe_path(index))


## What kept the export from being made ("" when it was, or the switch is off).
static func export_error() -> String:
	return _export_error


## Does the chain play the exported legacy (the switch is on and worked)?
static func plays_the_export() -> bool:
	var chosen := Packs.chosen()
	return _switched and _export_error.is_empty() and chosen != null and chosen.id == ID and not chosen.trusted


## One sentence for a screen or a log: what is missing and what to do about it ("" when the legacy pack is there).
static func problem(lost: Array[String] = missing()) -> String:
	if lost.is_empty():
		return ""
	return "The legacy pack, the original game, is not here (%d of its files are missing, for example %s): %s." % [lost.size(), lost[0], NEED_THE_IMPORTER]
