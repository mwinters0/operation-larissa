"""The picture table of a complete pack: `pictures.json`, from the key of every picture to its file (or to another key).

The engine finds a picture ONLY by its key (`<kind>/<name>`: `ui_picture/title_sky`, `frame/eel_swim_0`, `tile/zone0_tiles`,
`background/bg_s03_07`; godot/src/core/picture_table.gd, `PictureTable`). What a file is called means nothing to it. This module writes the table the
importer's pack and the dev pack hold, and it is the one place that turns a picture FILE of the importer's naming (asset_names.py) into its key:

    ui/<folder>/<name>_<id>.png            ui_picture/<name>         unnamed  ui_<id>.png        ui_picture/ui_<id>
    problem_art/<folder>/<name>_<id>.png   problem_art/<name>                 pa_<id>.png        problem_art/pa_<id>
    sprites/foes/<name>_<slot>.png         frame/<name>                      foe_<slot>.png     frame/foe_<slot>      (a zone's own: foe_z<zone>_...)
    sprites/decos/<name>_<slot>.png        deco/<name>                       deco_<slot>.png    deco/deco_<slot>      (deco_z<zone>_...)
    sprites/{sub,pieces,station,fx}/<s>.png   frame/<s>      tiles/<s>.png   tile/<s>      backgrounds/<s>.png   background/<s>

A picture another role owns (pictures.py: the story art, the finale creatures) is kept once; every other key of the same picture (the problem art ids it
also has, `problem_art/pa_1826`) is an alias of the owner's key, so one file serves both names.

    rows(files, index)    -> {key: "assets/..png" | {"alias": key}}   from the list of files below a pack and the problem art index
    render(rows)          -> the text of pictures.json
    write(root, rows)     -> writes <root>/pictures.json
"""
from __future__ import annotations

import json
import re
from collections.abc import Iterable
from pathlib import Path

import asset_names
import pictures
from common import LEGACY

FILE = "pictures.json"
FORMAT = 1

# The names the importer gives a picture nobody named: they hold the number already, so the key is the file's stem as it is.
_UNNAMED = re.compile(r"^(ui|pa|foe|deco)_(z[0-9]+_)?[0-9]+$")
_TRAILING_NUMBER = re.compile(r"^(.+)_[0-9]+$")
# folder below assets/ (or the first two) -> (kind, is the file name followed by the registry number?)
_FOLDERS = {
    "ui": ("ui_picture", True),
    "problem_art": ("problem_art", True),
    "sprites/foes": ("frame", True),
    "sprites/decos": ("deco", True),
    "sprites/sub": ("frame", False),
    "sprites/pieces": ("frame", False),
    "sprites/station": ("frame", False),
    "sprites/fx": ("frame", False),
    "tiles": ("tile", False),
    "backgrounds": ("background", False),
}


def key_of_rel(rel: str) -> str:
    """The key of the picture file `rel` (`assets/ui/title/title_sky_1039.png`), "" for a file that is no picture of the game (the authoring tool's art, a README)."""
    parts = rel.split("/")
    if len(parts) < 3 or parts[0] != "assets" or not rel.endswith(".png"):
        return ""
    folder = "/".join(parts[1:3]) if "/".join(parts[1:3]) in _FOLDERS else parts[1]
    if folder not in _FOLDERS:
        return ""
    kind, numbered = _FOLDERS[folder]
    stem = parts[-1][:-len(".png")]
    if numbered and not _UNNAMED.match(stem):
        found = _TRAILING_NUMBER.match(stem)
        assert found is not None, "%s: a named picture file ends with its number" % rel
        stem = found.group(1)
    return "%s/%s" % (kind, stem)


def key_of_file(path: Path) -> str:
    """The key of the picture file `path` below the legacy pack (what a step wrote)."""
    return key_of_rel(path.relative_to(LEGACY).as_posix())


def rows(files: Iterable[str], index: dict[str, list[int]]) -> dict[str, str | dict[str, str]]:
    """The table of a pack that holds `files` (paths below its root) and whose problem art is `index` (folder -> picture ids, the importer's
    `step_images.problem_art_index`): a row for every picture file, and for every problem art id that another role keeps the file of, an alias of that file's key."""
    table: dict[str, str | dict[str, str]] = {}
    for rel in sorted(files):
        key = key_of_rel(rel)
        if key:
            assert key not in table, "%s is the key of %s and of %s" % (key, table[key], rel)
            table[key] = rel
    held = pictures.homes()
    for ids in index.values():
        for pid in ids:
            key = asset_names.problem_art_key(pid)
            if pid in held and key not in table:
                owner = key_of_rel(held[pid].relative_to(LEGACY).as_posix())
                assert owner in table, "%s: the owner %s of picture %d has no file" % (key, owner, pid)
                table[key] = {"alias": owner}
    return table


def render(table: dict[str, str | dict[str, str]]) -> str:
    """The text of `pictures.json` (a row to a line, sorted, so a diff reads)."""
    lines = ",\n".join("  %s: %s" % (json.dumps(k), json.dumps(table[k], separators=(", ", ": "))) for k in sorted(table))
    return '{\n "format": %d,\n "pictures": {\n%s\n }\n}\n' % (FORMAT, lines)


def write(root: Path, table: dict[str, str | dict[str, str]]) -> None:
    (root / FILE).write_text(render(table), encoding="utf-8", newline="\n")
