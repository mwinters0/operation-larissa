"""The list of files a dev pack must have: one per file of the legacy pack (shape-complete), made from legacy's PATHS only.

`inventory.json` is committed, so a checkout without the legacy pack knows the expected shape. `refresh()` rebuilds it from the
legacy pack's folder when that is there: it lists file names and, for the text tables, the ids of their entries (identifiers,
like the registry's numbers). It never reads a picture, a size, a coordinate or a string of the original.

    files        every file below assets/ and data/ except audio, the sector and campaign folders (dev has its own sectors and
                 campaign: dev_tour) and the sound catalogs (audio.py makes those), plus pack.json
    audio        the audio files, midi files and sound catalogs, for audio.py: the shape it has to fill
    text_tables  data/problems/<table>.tres -> the ids of its entries
    problem_art_index  data/problems/problem_art_index.json: the picture ids of each problem-art folder (ids only)
"""
from __future__ import annotations

import json
from pathlib import Path

from devlib import AUDIO_DATA, INVENTORY, LEGACY

FORMAT = 1
SKIP_SUFFIXES = (".import", ".uid")
TEXT_TABLES = ("calc_notices", "closing", "help", "hints", "log_entries", "story", "supply_messages", "ui_strings")


def _tree(root: Path, folder: str) -> list[str]:
    base = root / folder
    return sorted(p.relative_to(root).as_posix() for p in base.rglob("*") if p.is_file() and p.suffix not in SKIP_SUFFIXES)


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


def refresh(legacy: Path = LEGACY) -> dict:
    """Rebuild inventory.json from the legacy pack's file list (and the ids of its text tables)."""
    everything = ["pack.json"] + _tree(legacy, "assets") + _tree(legacy, "data") + _tree(legacy, "midi")
    files = [f for f in everything if not is_audio(f) and not f.startswith(("data/sectors/", "data/campaigns/"))]
    audio = [f for f in everything if is_audio(f)]
    tables = {name: table_ids((legacy / "data" / "problems" / (name + ".tres")).read_text()) for name in TEXT_TABLES}
    index = json.loads((legacy / "data" / "problems" / "problem_art_index.json").read_text())
    inv = {"format": FORMAT,
           "comment": "Written by make_dev_pack.py --refresh-inventory from the legacy pack's file NAMES (and the ids of its text tables). "
                      "No content of the original is in it. See tools/dev_pack/inventory.py.",
           "files": sorted(files), "audio": sorted(audio), "text_tables": tables,
           "problem_art_index": index}
    INVENTORY.write_text(json.dumps(inv, indent=1) + "\n")
    return inv


def load() -> dict:
    return json.loads(INVENTORY.read_text())
