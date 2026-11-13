"""The picture table of a complete pack: `pictures.json`, from the key of every picture to its file (or to another key).

The engine finds a picture ONLY by its key (`<kind>/<name>`: `ui_picture/title_sky`, `frame/eel_swim_0`, `tile/zone0_tiles`,
`background/bg_s03_07`; godot/src/core/picture_table.gd, `PictureTable`). What a file is called means nothing to it. This module writes the table the
importer's pack and the dev pack hold.

The key of a picture is made once, by the forward rules of asset_names.py (`ui_key`, `problem_art_key`, `foe_key`, `deco_key`, `plain`), in the step that writes the
file; the step records it with the file (`asset_manifest`: `copy_picture`, `put_atlas`, `put_port`, the entry's `picture_key`), and the table is built from those
records, so no file name is ever read back into a key.

A picture another role owns (pictures.py: the story art, the finale creatures) is kept once; every other key of the same picture (the problem art ids it
also has, `problem_art/pa_1826`) is an alias of the owner's key (`pictures.home_key`), so one file serves both names.

    rows(manifest, index) -> {key: "assets/..png" | {"alias": key}}   from the asset manifest's entries and the problem art index
    render(rows)          -> the text of pictures.json
    write(root, rows)     -> writes <root>/pictures.json
"""
from __future__ import annotations

import json
from pathlib import Path

import asset_names
import pictures

FILE = "pictures.json"
FORMAT = 1


def rows(manifest: dict[str, dict], index: dict[str, list[int]]) -> dict[str, str | dict[str, str]]:
    """The table of a pack whose asset files are `manifest` (path below its root -> the manifest entry; every PNG has its `picture_key`) and whose problem art is `index`
    (folder -> picture ids, the importer's `step_images.problem_art_index`): a row for every picture file, and for every problem art id that another role keeps the
    file of, an alias of that role's key."""
    table: dict[str, str | dict[str, str]] = {}
    for rel in sorted(manifest):
        if not rel.endswith(".png"):
            continue
        key = manifest[rel].get("picture_key", "")
        assert key, "%s has no picture key in the manifest: run the importer steps that write pictures (images, tiles, sprites)" % rel
        assert key not in table, "%s is the key of %s and of %s" % (key, table[key], rel)
        table[key] = rel
    for ids in index.values():
        for pid in ids:
            owner = pictures.home_key(pid)
            if owner is not None:
                assert owner in table, "%s: the owner %s of picture %d has no file" % (asset_names.problem_art_key(pid), owner, pid)
                table[asset_names.problem_art_key(pid)] = {"alias": owner}
    return table


def render(table: dict[str, str | dict[str, str]]) -> str:
    """The text of `pictures.json` (a row to a line, sorted, so a diff reads)."""
    lines = ",\n".join("  %s: %s" % (json.dumps(k), json.dumps(table[k], separators=(", ", ": "))) for k in sorted(table))
    return '{\n "format": %d,\n "pictures": {\n%s\n }\n}\n' % (FORMAT, lines)


def write(root: Path, table: dict[str, str | dict[str, str]]) -> None:
    (root / FILE).write_text(render(table), encoding="utf-8", newline="\n")
