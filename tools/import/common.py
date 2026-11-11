"""Shared helpers for the import pipeline.

Rules of the pipeline (see docs/port/FIDELITY.md, "The importer's rules"):
  * input  = extracted/ (its tables/ too) and tools/analysis/data/ only (never the game's files; but import_all.py first checks with
    source_files.py that the CD image they were extracted from is the reference release, and its first two steps,
    step_extract.py, make extracted/ and the game's tables in extracted/tables/ from that image),
  * output = the legacy pack, loose files in the project's own folder godot/packs/legacy (`legacy_root`: pack.json, assets/, data/,
    midi/; git-ignored; deterministic, so a second run changes nothing),
  * files are only rewritten when their content changes, so Godot does not
    needlessly re-import unchanged assets.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
from functools import cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXTRACTED = ROOT / "extracted"
TABLES = EXTRACTED / "tables"                       # the game's own data tables, written by the importer's "tables" step (GENERATED_TABLES)
ANALYSIS_DATA = ROOT / "tools" / "analysis" / "data"  # our own analysis (layouts, field meanings), committed
GODOT = ROOT / "godot"
PROJECT_DATA = GODOT / "data"        # the COMMITTED data of the project (not the legacy pack's: PACK_DATA)
PACKS = GODOT / "packs"
LEGACY_ID = "legacy"
LEGACY = PACKS / LEGACY_ID           # the legacy pack: a real folder of the project (res://packs/legacy), git-ignored
LEGACY_RES = "res://packs/%s/" % LEGACY_ID


def legacy_root() -> Path:
    """Where the legacy pack is on disk: godot/packs/legacy, `res://packs/legacy` of the game. The ONE place that knows it."""
    return LEGACY


ASSETS = LEGACY / "assets"           # everything that was godot/assets/
PACK_DATA = LEGACY / "data"          # the generated files that were in godot/data/
MIDI = LEGACY / "midi"               # what was godot/midi/
PACK_JSON = LEGACY / "pack.json"
LEGACY_MANIFEST = {"id": LEGACY_ID, "title": "Operation Neptune (your copy)", "version": "1", "format": 1}


@cache
def load_json(path: Path):
    return json.loads(Path(path).read_text())


# Original game logic rate: 73 timer ticks per second, 6 ticks per game frame.
TICK_HZ = 73 / 6

# Art zones: floor-tile bundle = 23+3z, deco bundle = 24+3z, foe bundle = 25+3z.
ZONE_TITLES = ["Dragon Reef", "Fossil Trench", "Limestone Ridge", "Sea Forest", "Hammerhead"]
ZONE_BANNER_IDS = [1195, 1196, 1197, 1198, 1199]
# (The default educational level per zone is read from the program: ds_tables.py.)

# Which picture is in which creature / deco slot is data: tools/analysis/data/sprite_slots.json. Creature sets 5 and 6
# are the Voyager and Expert finales.
SPRITE_SLOTS_FILE = ANALYSIS_DATA / "sprite_slots.json"


def foe_slots(zone: int) -> list[int]:
    """Picture ids of the creature slots of `zone` (0-6): slots 0-27 common, 28-34 the ink pellet, 35+ the zone's own."""
    s = load_json(SPRITE_SLOTS_FILE)["creatures"]
    assert len(s["common"]["pictures"]) == s["ink"]["slot"]
    assert s["ink"]["slot"] + len(s["ink"]["pictures"]) == s["zones"][zone]["slot"]
    return s["common"]["pictures"] + s["ink"]["pictures"] + s["zones"][zone]["pictures"]


def deco_slots(zone: int) -> list[int]:
    """Picture ids of the deco slots of `zone` (0-4): slots 0-69 common, 70+ the zone's own."""
    s = load_json(SPRITE_SLOTS_FILE)["decos"]
    assert len(s["common"]["pictures"]) == s["zones"][zone]["slot"]
    return s["common"]["pictures"] + s["zones"][zone]["pictures"]


ZONE_DECO_COUNTS = [len(z["pictures"]) for z in load_json(SPRITE_SLOTS_FILE)["decos"]["zones"]]
ZONE_FOE_COUNTS = [len(z["pictures"]) for z in load_json(SPRITE_SLOTS_FILE)["creatures"]["zones"]]
COMMON_DECOS = len(load_json(SPRITE_SLOTS_FILE)["decos"]["common"]["pictures"])      # deco slots 0-69
COMMON_CREATURES = len(load_json(SPRITE_SLOTS_FILE)["creatures"]["common"]["pictures"])   # foe frames 0-27
INK_FRAMES = len(load_json(SPRITE_SLOTS_FILE)["creatures"]["ink"]["pictures"])       # foe frames 28-34
FOE_ZONE_BASE = load_json(SPRITE_SLOTS_FILE)["creatures"]["zones"][0]["slot"]        # foe frames 35+: the zone's own

# Sectors 0..ORIGINAL_SECTOR_COUNT-1 come from the game's files (original bytes, fixtures, reset tools). A sector with a higher
# number is one the designers made (godot/src/core/catalog.gd: Catalog.is_original_sector): its files are its only source, so the
# importer never writes or deletes them and the reset and harvest tools refuse them (`is_original_sector`, `refuse_new_sectors`).
ORIGINAL_SECTOR_COUNT = 32
SCREENS = 12

# Fixtures that hold ORIGINAL BYTES go here: written by the importer from the user's copy of the game, never committed
# (.gitignore, docs/port/FIDELITY.md "Fixtures commit hashes, not bytes"). The committed fixture next to them keeps only
# provenance and SHA-256 hashes.
ORIGINAL_FIXTURES = GODOT / "tests" / "fixtures" / "original"
# THE LEGACY PACK (docs/play/LEGACY.md) is the original game as the importer writes it from the user's ISO: a pack in the folder
# godot/packs/legacy (`legacy_root`, res://packs/legacy/, godot/tests/legacy/legacy_pack.gd), git-ignored, never committed. What the user adds to
# it by hand, because it holds the game's content, goes in this folder of the project, which is ignored: today the hand corrections of the
# machine voice transcripts (transcripts.py). $NEP_LEGACY puts it elsewhere.
LEGACY_AREA = Path(os.environ.get("NEP_LEGACY") or PROJECT_DATA / "legacy")
VOICE_CORRECTIONS = LEGACY_AREA / "voice_corrections.json"
# One output of each importer step, relative to the legacy pack's root (godot/tests/legacy/legacy_pack.gd WITNESSES is the same list; test_import.py checks that they agree): the game is
# "there" when all of them are. `legacy_missing` also asks for the tables of extracted/tables/ (GENERATED_TABLES). (The voice transcripts may
# be left out, `--no-transcripts`: a test that reads them skips without them.)
LEGACY_WITNESSES = [
    "data/sectors/sector_00/sector_00.tres", "data/sectors/sector_31/sector_31.tres", "data/campaigns/voyager.tres",
    "data/campaigns/expert.tres", "data/zones.tres", "data/trigger_table.tres", "data/neptune_tileset.tres",
    "data/sprite_meta/sprite_meta_common.tres", "data/sprite_frames/sub_frames.tres", "data/problems/problem_type_00.tres",
    "data/ui/hud_layout.tres", "data/sfx_catalog.tres", "data/music_catalog.tres", "data/voice_index.tres",
    "data/story/news_cartoon.tres", "assets/tiles/zone0_tiles.png", "assets/tiles/invisible_wall.png",
]
# The tables the importer's "tables" step (step_extract.py) writes from the CD into extracted/tables/ (TABLES): the game's own data, git-ignored with
# extracted/. Our own analysis (layouts, field meanings, console and sprite-slot tables) is committed in tools/analysis/data/ (ANALYSIS_DATA).
GENERATED_TABLES = ["sectors.json", "problem_records.json", "problem_tables_raw.json", "problem_gfx_bundles.json",
                    "trigger_table.json", "zone_defaults.json", "onwin_map.json",
                    "music_map.json", "ink_tables.json", "hud_gauges.json", "lock_wheel.json", "ballast.json", "piece_animation.json",
                    "dissolve_tables.json", "expert_closing.json", "opening.json", "audio_map.json", "bubbles.json", "databank.json",
                    "problem_diagrams.json"]


def legacy_missing() -> list[str]:
    """The files of the legacy pack (and the importer's other outputs the tests read) that are not there; empty after a full import."""
    wanted = [LEGACY / name for name in LEGACY_WITNESSES] + [TABLES / name for name in GENERATED_TABLES]
    return [str(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path) for path in wanted if not path.exists()]


# What the tools say when the importer's raw files are missing, and when they do not match the committed hashes.
RUN_THE_IMPORTER = "run the importer on your copy of the game (uv run tools/import/import_all.py)"
DIFFERENT_VERSION = "your copy of the game is a different version or patched"


def sha256_hex(data: bytes) -> str:
    """Lower-case hex SHA-256 of `data`. godot/src/core/fixture_hash.gd does the same in GDScript; the two must agree.
    Hash a whole record (one sector header, one screen, one script), never a single field: a hash of a one- or
    two-byte field can be reversed by trying every value."""
    return hashlib.sha256(data).hexdigest()


def is_original_sector(index: int) -> bool:
    """True for the sectors 0..ORIGINAL_SECTOR_COUNT-1, the ones that have original bytes."""
    return 0 <= index < ORIGINAL_SECTOR_COUNT


def refuse_new_sectors(sectors: list[int], what: str = "original bytes") -> str:
    """"" when every sector is an original one, else the message that says which are not (a sector the designers made is its
    own source, so a tool that rebuilds from the original refuses it instead of overwriting it)."""
    new = [n for n in sectors if not is_original_sector(n)]
    if not new:
        return ""
    return ("sector%s %s %s not one of the original sectors (0-%d) and so ha%s no %s: a new sector's files are its own "
            "source, nothing here rewrites them" % ("s" if len(new) > 1 else "", ", ".join(map(str, new)),
                                                      "are" if len(new) > 1 else "is", ORIGINAL_SECTOR_COUNT - 1,
                                                      "ve" if len(new) > 1 else "s", what))


def sector_dir(index: int, base: Path | None = None) -> Path:
    """The folder of one sector, sector_NN/ -- in the legacy pack's data/sectors/ for the original sectors 0-31, else in the project's
    godot/data/sectors/, where the sectors the designers made live and commit (`base`: the sectors folder, a copy of it in a test)."""
    if base is None:
        base = (PACK_DATA if is_original_sector(index) else PROJECT_DATA) / "sectors"
    return base / ("sector_%02d" % index)


def sector_file(index: int, ext: str, base: Path | None = None) -> Path:
    """sector_NN/sector_NN.<ext> in `sector_dir` (ext: "tres" or "foe")."""
    return sector_dir(index, base) / ("sector_%02d.%s" % (index, ext))


def res_path(path: Path) -> str:
    """Absolute path of a file of the legacy pack or of the project -> res:// URL (res://packs/legacy/... for the legacy pack)."""
    if path.is_relative_to(LEGACY):
        return LEGACY_RES + path.relative_to(LEGACY).as_posix()
    return "res://" + path.relative_to(GODOT).as_posix()


def file_of_res(res_url: str) -> Path:
    """The file a res:// URL names (the inverse of `res_path`; the legacy pack's URLs lead into its folder)."""
    rest = res_url.removeprefix("res://")
    if rest.startswith("packs/%s/" % LEGACY_ID):
        return LEGACY / rest.removeprefix("packs/%s/" % LEGACY_ID)
    return GODOT / rest


def png_size(res_url: str) -> tuple[int, int]:
    """(width, height) in pixels of the PNG that `res_url` (a res://packs/legacy/assets/ path) names.

    Layout in the Godot port comes from data, never from a texture read at run time, so the importer
    writes the sizes that hit areas and positions need. The size is the 8 bytes after the PNG signature and the
    IHDR chunk header, so no image library is needed and the result is the same on every machine."""
    with open(file_of_res(res_url), "rb") as file:
        header = file.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR", res_url
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


def manifest() -> dict:
    return load_json(EXTRACTED / "images" / "manifest.json")


def sprite_file(image_id: int) -> Path:
    """Extracted PNG of a NEP256 sprite id."""
    return EXTRACTED / manifest()["NEP256:%d" % image_id]["file"]


def bundles() -> dict:
    return load_json(EXTRACTED / "images" / "sprite_bundles.json")


def bundle_ids(bundle: int) -> list[int]:
    """Picture ids of a sprite bundle, in frame order."""
    return list(bundles()[str(bundle)]["frame_ids"])


def raw_table(real_id: int) -> bytes:
    """Raw NEP.DLL data resource (an OTHR table)."""
    return (EXTRACTED / "data" / "NEP_raw" / ("NEP_%d.bin" % real_id)).read_bytes()


def write_bytes(path: Path, data: bytes) -> bool:
    """Write only if the content differs. Returns True if the file changed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() == data:
        return False
    path.write_bytes(data)
    return True


def write_text(path: Path, text: str) -> bool:
    return write_bytes(path, text.encode("utf-8"))


def copy_file(src: Path, dest: Path) -> bool:
    """Copy only if content differs (keeps mtimes stable on re-runs)."""
    return write_bytes(dest, Path(src).read_bytes())


class Stats:
    """Counts files written/unchanged so the CLI can report them."""
    written = 0
    unchanged = 0

    @classmethod
    def record(cls, changed: bool) -> None:
        if changed:
            cls.written += 1
        else:
            cls.unchanged += 1


def out_copy(src: Path, dest: Path) -> Path:
    Stats.record(copy_file(src, dest))
    return dest


def out_text(dest: Path, text: str) -> Path:
    Stats.record(write_text(dest, text))
    return dest


def clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)


# --- the legacy pack on disk: its folder and pack.json --------------------------------------------------------------------------

def prepare_legacy(root: Path | None = None) -> list[str]:
    """What the importer does before any step: the legacy pack's folder and its pack.json (godot/src/core/pack_manifest.gd).
    Returns what it changed, as lines to print."""
    root = LEGACY if root is None else root
    changed = []
    root.mkdir(parents=True, exist_ok=True)
    manifest_text = json.dumps(LEGACY_MANIFEST, indent=2) + "\n"
    if write_text(root / "pack.json", manifest_text):
        changed.append("pack.json written in %s" % root)
    return changed
