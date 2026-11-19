"""The list of files a dev pack must have: one per file of the legacy pack (shape-complete), made from legacy's PATHS only.

`inventory.json` is committed, so a checkout without the legacy pack knows the expected shape. `refresh()` rebuilds it from the
legacy pack's folder when that is there: it lists file names and, for the text tables, the ids of their entries (identifiers,
like the registry's numbers). It never reads a picture, a size, a coordinate or a string of the original.

    files        every file below data/ except audio, the sector and campaign folders (dev has its own sectors and
                 campaign: dev_tour), the scene the legacy campaigns end with and what it names (`is_a_closing_scene`: dev_tour ends with
                 a scene of its own, `dev_closing`) and the sound catalogs (audio.py makes those), plus pack.json. No picture: those are `pictures`.
    pictures     key -> the number the legacy pack's file of that key ends with (a picture id, a creature or deco slot) or null: a row of dev's
                 `pictures.json` with a file of its own (the importer's asset manifest says which keys there are and the number of their files, never what is in them)
    picture_aliases  key -> the key it is an alias of (a problem art id whose picture another role keeps once)
    audio        the audio files, midi files and sound catalogs, for audio.py: the shape it has to fill
    text_tables  data/problems/<table>.tres -> the ids of its entries
    problem_art_index  the picture ids of each problem-art bundle of the legacy pack (ids only: which picture is the n-th of a problem type's art)
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from devlib import AUDIO_DATA, INVENTORY, LEGACY

import asset_manifest
import picture_table

FORMAT = 2
SKIP_SUFFIXES = (".import", ".uid")
## The files of the Expert campaign's closing scene (a campaign names its closing scene, so a pack needs none of them): the scene, its stage and its three timelines.
CLOSING_SCENE_FILES = tuple("data/story/%s.tres" % name for name in ("expert_closing", "expert_closing_stage", "expert_hoist", "expert_deck", "expert_wait"))
TEXT_TABLES = ("calc_notices", "closing", "help", "hints", "log_entries", "story", "supply_messages", "ui_strings")


def _tree(root: Path, folder: str, only: str = "") -> list[str]:
    base = root / folder
    return sorted(p.relative_to(root).as_posix() for p in base.rglob("*")
                  if p.is_file() and p.suffix not in SKIP_SUFFIXES and (not only or p.suffix == only))


def is_a_closing_scene(rel: str) -> bool:
    """Is `rel` a file of a legacy campaign's closing scene, which dev does not hold (its campaign has a closing scene of its own)?"""
    return rel in CLOSING_SCENE_FILES


def is_audio(rel: str) -> bool:
    return rel.startswith(("assets/audio/", "midi/")) or rel in ["data/" + n for n in AUDIO_DATA]


def table_ids(text: str) -> list[int]:
    """The ids (keys) of the `texts = {id: "...", ...}` line of a TextTable .tres, read without looking at the strings."""
    start = text.index("texts = {") + len("texts = {")
    ids, i, n = [], start, len(text)
    while i < n:
        while text[i] in " ,\n":
            i += 1
        if text[i] == "}":
            break
        j = i
        while text[j].isdigit():
            j += 1
        ids.append(int(text[i:j]))
        i = j + 2                                                   # ": "
        assert text[i] == '"'
        i += 1
        while text[i] != '"':
            i += 2 if text[i] == "\\" else 1
        i += 1
    return ids


def _number_of(key: str, rel: str) -> int | None:
    """The number the file `rel` of the picture `key` ends with (`title_sky_1039.png`, `foe_z1_eel_swim_0_35.png`): its picture id, or its slot; None for a file of a plain folder."""
    numbered = key.startswith(("ui_picture/", "problem_art/")) or rel.startswith(("assets/sprites/foes/", "assets/sprites/decos/"))
    found = re.search(r"_([0-9]+)\.png$", rel)
    return int(found.group(1)) if numbered and found else None


def pictures_of(manifest: dict[str, dict], index: dict[str, list[int]]) -> tuple[dict[str, int | None], dict[str, str]]:
    """(pictures, picture_aliases) of the pack whose asset manifest is `manifest` (the importer's, `asset_manifest.load`) and whose problem art is `index`: the rows of its table."""
    pictures: dict[str, int | None] = {}
    aliases: dict[str, str] = {}
    for key, row in picture_table.rows(manifest, index).items():
        if isinstance(row, str):
            pictures[key] = _number_of(key, row)
        else:
            aliases[key] = row["alias"]
    return dict(sorted(pictures.items())), dict(sorted(aliases.items()))


def refresh(legacy: Path = LEGACY) -> dict:
    """Rebuild inventory.json from the legacy pack's file list (and the ids of its text tables). The pack's pictures are the file rows of the table the importer's asset manifest makes
    (picture_table.rows); its problem-art ids are the ones the inventory has (the bundles do not change)."""
    everything = ["pack.json"] + _tree(legacy, "assets") + _tree(legacy, "data") + _tree(legacy, "midi")
    files = [f for f in everything if not is_audio(f) and not is_a_closing_scene(f) and not f.startswith(("assets/", "data/sectors/", "data/campaigns/")) and f != "data/problems/problem_art_index.json"]
    audio = [f for f in everything if is_audio(f)]
    tables = {name: table_ids((legacy / "data" / "problems" / (name + ".tres")).read_text()) for name in TEXT_TABLES}
    index = load()["problem_art_index"] if INVENTORY.exists() else json.loads((legacy / "data" / "problems" / "problem_art_index.json").read_text())
    pictures, aliases = pictures_of(asset_manifest.load(), index)
    inv = {"format": FORMAT,
           "comment": "Written by make_dev_pack.py --refresh-inventory from the legacy pack's file NAMES (and the ids of its text tables). "
                      "No content of the original is in it. See tools/dev_pack/inventory.py.",
           "files": sorted(files), "pictures": pictures, "picture_aliases": aliases, "audio": sorted(audio), "text_tables": tables,
           "problem_art_index": index}
    INVENTORY.write_text(json.dumps(inv, indent=1) + "\n")
    return inv


def load() -> dict:
    return json.loads(INVENTORY.read_text())
