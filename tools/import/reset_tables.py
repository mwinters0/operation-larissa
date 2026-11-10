"""Reset the small original tables of the editable data back to the ORIGINAL: sprite sizes and hit rectangles, the trigger
table, the zones' default educational levels, and the stored problems.

    uv run tools/import/reset_tables.py sprite_meta --all          # the 9 sets (<the legacy pack>/data/sprite_meta/)
    uv run tools/import/reset_tables.py sprite_meta common zone3   # named sets
    uv run tools/import/reset_tables.py trigger_table              # <the legacy pack>/data/trigger_table.tres
    uv run tools/import/reset_tables.py zone_levels                # the 10 default levels in <the legacy pack>/data/zones.tres
    uv run tools/import/reset_tables.py problems --all             # the 34 problem types (<the legacy pack>/data/problems/problem_type_NN.tres)
    uv run tools/import/reset_tables.py problems 5 12              # problem types 5 and 12

These tables are stored data that designers edit (the Inspector): `sizes` / `hit_rects` / `hit_rects_flipped` of a
sprite_meta_<set>.tres, `table` of trigger_table.tres, `default_edu_level_voyager` / `default_edu_level_expert` of the zones 0-4 in
zones.tres, `field_kinds` / `records` / `record_levels` / `levels_available` of a problem_type_NN.tres. This tool is the way back
to the original, one tool for all four kinds because they work the same way (reset_sector_header.py, reset_screens.py and
reset_foe_scripts.py are the ones for the sectors). It reads the original table bytes that the importer wrote from YOUR copy of the
game (godot/tests/fixtures/original/<kind>.json, git-ignored), decodes them with the code the importer uses
(sprite_meta.py, ds_tables.py, problem_tables.py) and patches exactly those properties into the existing .tres, in the
importer's format. Everything else in the file stays as it is: the zones' titles, picture counts and banners, a problem type's texts,
art, answer rules and diagram, the uids. The zones' two finale entries are not part of the original's table (the game uses the
last zone's level) and are not touched.

Two checks make sure the result is the original and not just something that looks like it:
  * the original bytes must hash to the SHA-256 committed in godot/tests/fixtures/<kind>.json (a different release of the game,
    or a patched copy, is refused: the hashes do not come from your copy);
  * the file just written is read back, its fields are encoded to the table bytes again, and those must hash to the same
    committed SHA-256 as well.

If the original bytes are missing, the tool stops with "run the importer on your copy of the game". (the legacy pack is not in version control, so
there is no restoring these files from it: this tool, or the importer's steps, is the way back to the original.)

Not the same as `import_all.py --only sprites / sectors / problems`, which rewrite WHOLE files (and more than these tables).
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import ClassVar

import ds_tables
import problem_tables
import sprite_meta
import tres
from common import PACK_DATA, DIFFERENT_VERSION, RUN_THE_IMPORTER, sha256_hex

ORIGINAL_ZONES = 5          # zones 0-4 have a row in the original's table; the two finales do not


def _missing(raw_fixture: Path) -> ValueError:
    return ValueError("%s is missing. It holds the original table bytes and is written by the importer from your copy of the game: %s."
                      % (raw_fixture, RUN_THE_IMPORTER))


def _load_json(path: Path, committed: bool) -> dict:
    if not path.exists():
        raise ValueError("%s is missing (it is committed): restore it with git." % path) if committed else _missing(path)
    return json.loads(path.read_text())


def _checked(raw: bytes, expected: str, what: str, raw_fixture: Path, hash_fixture: Path) -> None:
    if sha256_hex(raw) != expected:
        raise ValueError("%s: the bytes in %s do not match the SHA-256 committed in %s. %s, or the file was edited: %s."
                         % (what, raw_fixture.name, hash_fixture.name, DIFFERENT_VERSION.capitalize(), RUN_THE_IMPORTER))


def _ints(text: str) -> list[int]:
    return [int(v) for v in re.findall(r"-?\d+", text)]


def _property(block: str, key: str) -> str:
    """The value text of `key = ...` in a block, "" if the block has no such line (a default Godot leaves out)."""
    lines = block.split("\n")
    at = tres.property_line(lines, key)
    return lines[at][len(key) + 3:] if at is not None else ""


def _resource_block(text: str) -> str:
    blocks = tres.split_blocks(text)
    if not blocks[-1].startswith("[resource]"):
        raise ValueError("the last block is not [resource]")
    return blocks[-1]


def _replace_resource_block(text: str, values: dict[str, str], after: dict[str, str] | None = None) -> str:
    blocks = tres.split_blocks(text)
    blocks[-1] = tres.set_properties(_resource_block(text), values, after)
    return tres.join_blocks(blocks)


# ============================================================================ kinds
# Each kind gives: `items` (what can be named on the command line), `path(item, base)`, `load(...)` -> {item: (original,
# expected hashes)} with the raw bytes checked, `hashes(text, item)` (what the fields in the file encode to) and `patch(text,
# item, original)`. "hashes" is a tuple of SHA-256 hex strings, one per table of the item.

class SpriteMeta:
    name = "sprite_meta"
    items: ClassVar[list[str]] = [name for name, _ids, _count in sprite_meta.SETS]
    base = PACK_DATA / "sprite_meta"
    raw_fixture, hash_fixture = sprite_meta.RAW_FIXTURE, sprite_meta.HASH_FIXTURE

    @staticmethod
    def path(item: str, base: Path) -> Path:
        return base / ("sprite_meta_%s.tres" % item)

    @classmethod
    def load(cls, raw_fixture: Path, hash_fixture: Path) -> dict:
        raw = _load_json(raw_fixture, False)
        hashes = {e["name"]: e["tables"] for e in _load_json(hash_fixture, True)["sets"]}
        out = {}
        for entry in raw["sets"]:
            tables = tuple(bytes.fromhex(entry[kind + "_hex"]) for kind in sprite_meta.KINDS)
            expected = tuple(hashes[entry["name"]][kind]["sha256"] for kind in sprite_meta.KINDS)
            for kind, table, want in zip(sprite_meta.KINDS, tables, expected):
                _checked(table, want, "%s %s" % (entry["name"], kind), raw_fixture, hash_fixture)
            out[entry["name"]] = (tables, expected)
        return out

    @staticmethod
    def fields(text: str) -> dict:
        block = _resource_block(text)
        pairs = lambda key: [tuple(_ints(v)) for v in re.findall(r"(?:Vector2i|Rect2i)\(([^)]*)\)", _property(block, key))]
        return {"sizes": pairs("sizes"), "hit_rects": pairs("hit_rects"), "hit_rects_flipped": pairs("hit_rects_flipped")}

    @classmethod
    def hashes(cls, text: str, item: str) -> tuple:
        return tuple(sha256_hex(t) for t in sprite_meta.encode_set(cls.fields(text)))

    @classmethod
    def patch(cls, text: str, item: str, original: tuple) -> str:
        count = {name: c for name, _ids, c in sprite_meta.SETS}[item]
        meta = sprite_meta.decode_set(original, count)
        return _replace_resource_block(text, {
            "sizes": tres.array("Vector2i", [tres.vec2i(*v) for v in meta["sizes"]]),
            "hit_rects": tres.array("Rect2i", [tres.rect2i(*v) for v in meta["hit_rects"]]),
            "hit_rects_flipped": tres.array("Rect2i", [tres.rect2i(*v) for v in meta["hit_rects_flipped"]])})


class TriggerTable:
    name = "trigger_table"
    items: ClassVar[list[str]] = ["table"]
    base = PACK_DATA
    raw_fixture, hash_fixture = ds_tables.TRIGGER_RAW_FIXTURE, ds_tables.TRIGGER_HASH_FIXTURE

    @staticmethod
    def path(item: str, base: Path) -> Path:
        return base / "trigger_table.tres"

    @classmethod
    def load(cls, raw_fixture: Path, hash_fixture: Path) -> dict:
        raw = bytes.fromhex(_load_json(raw_fixture, False)["hex"])
        expected = _load_json(hash_fixture, True)["sha256"]
        _checked(raw, expected, "the trigger table", raw_fixture, hash_fixture)
        return {"table": (raw, (expected,))}

    @classmethod
    def hashes(cls, text: str, item: str) -> tuple:
        value = _property(_resource_block(text), "table")
        return (sha256_hex(ds_tables.encode_trigger_table(_ints(value[value.find("(") + 1:]))),)

    @classmethod
    def patch(cls, text: str, item: str, original: bytes) -> str:
        return _replace_resource_block(text, {"table": tres.packed_bytes(original)})


class ZoneLevels:
    name = "zone_levels"
    items: ClassVar[list[str]] = ["levels"]
    base = PACK_DATA
    raw_fixture, hash_fixture = ds_tables.ZONES_RAW_FIXTURE, ds_tables.ZONES_HASH_FIXTURE

    @staticmethod
    def path(item: str, base: Path) -> Path:
        return base / "zones.tres"

    @classmethod
    def load(cls, raw_fixture: Path, hash_fixture: Path) -> dict:
        raw = bytes.fromhex(_load_json(raw_fixture, False)["hex"])
        expected = _load_json(hash_fixture, True)["sha256"]
        _checked(raw, expected, "the default educational levels", raw_fixture, hash_fixture)
        return {"levels": (raw, (expected,))}

    @staticmethod
    def zone_blocks(text: str) -> dict[int, int]:
        """zone index -> position of its [sub_resource] block (the zone's own `index` property)."""
        return {int(_property(b, "index")): k for k, b in enumerate(tres.split_blocks(text)) if tres.sub_resource_id(b) and _property(b, "index") != ""}

    @classmethod
    def hashes(cls, text: str, item: str) -> tuple:
        blocks = tres.split_blocks(text)
        at = cls.zone_blocks(text)
        if any(z not in at for z in range(ORIGINAL_ZONES)):
            raise ValueError("zones.tres has no zones 0 to %d" % (ORIGINAL_ZONES - 1))
        voyager = [int(_property(blocks[at[z]], "default_edu_level_voyager") or 0) for z in range(ORIGINAL_ZONES)]
        expert = [int(_property(blocks[at[z]], "default_edu_level_expert") or 0) for z in range(ORIGINAL_ZONES)]
        return (sha256_hex(ds_tables.encode_default_edu_levels(voyager, expert)),)

    @classmethod
    def patch(cls, text: str, item: str, original: bytes) -> str:
        blocks = tres.split_blocks(text)
        at = cls.zone_blocks(text)
        if any(z not in at for z in range(ORIGINAL_ZONES)):
            raise ValueError("zones.tres has no zones 0 to %d" % (ORIGINAL_ZONES - 1))
        for z in range(ORIGINAL_ZONES):
            blocks[at[z]] = tres.set_properties(blocks[at[z]], {"default_edu_level_voyager": str(original[z]),
                                                                "default_edu_level_expert": str(original[ORIGINAL_ZONES + z])},
                                             {"default_edu_level_voyager": ["banner_texture", "foe_count", "*"], "default_edu_level_expert": ["default_edu_level_voyager", "*"]})
        return tres.join_blocks(blocks)


class Problems:
    name = "problems"
    items: ClassVar[list[str]] = [str(t) for t in range(problem_tables.TYPES)]
    base = PACK_DATA / "problems"
    raw_fixture, hash_fixture = problem_tables.RAW_FIXTURE, problem_tables.HASH_FIXTURE

    @staticmethod
    def path(item: str, base: Path) -> Path:
        return base / ("problem_type_%02d.tres" % int(item))

    @classmethod
    def load(cls, raw_fixture: Path, hash_fixture: Path) -> dict:
        raw = {(e["type"], e["level"]): bytes.fromhex(e["hex"]) for e in _load_json(raw_fixture, False)["tables"]}
        hashes = {(e["type"], e["level"]): e["sha256"] for e in _load_json(hash_fixture, True)["tables"]}
        out = {}
        for t in range(problem_tables.TYPES):
            levels = range(problem_tables.LEVELS)
            for level in levels:
                if (t, level) not in raw:
                    raise ValueError("type %d level %d is missing in %s: %s" % (t, level, raw_fixture.name, RUN_THE_IMPORTER))
                _checked(raw[t, level], hashes[t, level], "type %d level %d" % (t, level), raw_fixture, hash_fixture)
            out[str(t)] = (tuple(raw[t, level] for level in levels), tuple(hashes[t, level] for level in levels))
        return out

    @staticmethod
    def fields(text: str) -> tuple[str, list[list[int]], list[int]]:
        block = _resource_block(text)
        kinds = re.search(r'"([^"]*)"', _property(block, "field_kinds"))
        value = _property(block, "records")
        records = [_ints(v) for v in re.findall(r"PackedInt64Array\(([^)]*)\)", value)]
        levels_text = _property(block, "record_levels")
        levels = _ints(levels_text[levels_text.find("(") + 1:])
        if len(levels) != len(records):
            raise ValueError("%d records but %d record levels" % (len(records), len(levels)))
        return (kinds.group(1) if kinds else ""), records, levels

    @classmethod
    def hashes(cls, text: str, item: str) -> tuple:
        kinds, records, levels = cls.fields(text)
        return tuple(sha256_hex(problem_tables.encode_table(kinds, [r for r, lv in zip(records, levels) if lv == level]))
                     for level in range(problem_tables.LEVELS))

    @classmethod
    def patch(cls, text: str, item: str, original: tuple) -> str:
        t = int(item)
        kinds = problem_tables.field_kinds(t)
        records, levels = [], []
        for level, table in enumerate(original):
            recs = problem_tables.decode_table(kinds, table)
            records += recs
            levels += [level] * len(recs)
        return _replace_resource_block(text, {
            "levels_available": tres.packed_ints(1 if any(lv == level for lv in levels) else 0 for level in range(problem_tables.LEVELS)),
            "field_kinds": tres.s(kinds),
            "records": tres.array("PackedInt64Array", ["PackedInt64Array(%s)" % ", ".join(map(str, r)) for r in records]),
            "record_levels": tres.packed_ints(levels)},
            {"levels_available": "uses_calculator", "field_kinds": "art_files", "records": "field_kinds", "record_levels": "records"})


KINDS = {kind.name: kind for kind in (SpriteMeta, TriggerTable, ZoneLevels, Problems)}


# ============================================================================ the reset

def reset_item(kind, item: str, path: Path, original, expected: tuple) -> bool:
    """Reset one file in place. True if the file changed. The text is checked against `expected` before it is written and the
    file is read back and checked again after."""
    old = path.read_text()
    new = kind.patch(old, item, original)
    if kind.hashes(new, item) != expected:
        raise ValueError("%s: the patched fields do not encode to the committed hash; nothing written" % path)
    if new == old:
        return False
    path.write_text(new)
    if kind.hashes(path.read_text(), item) != expected:
        raise ValueError("%s: the file written does not encode to the committed hash" % path)
    return True


def run(kind_name: str, items: list[str], base: Path | None = None, raw_fixture: Path | None = None,
        hash_fixture: Path | None = None) -> None:
    """Reset `items` of one kind (all of them when empty). `base`: the folder with the .tres files (a copy in a test)."""
    kind = KINDS[kind_name]
    originals = kind.load(raw_fixture or kind.raw_fixture, hash_fixture or kind.hash_fixture)
    unknown = [i for i in items if i not in kind.items]
    if unknown:
        raise ValueError("no original %s %s: %s. A new one's .tres is its own source, so there is nothing to reset"
                         % (kind_name, ", ".join(unknown), "the names are " + ", ".join(kind.items)))
    for item in items or kind.items:
        original, expected = originals[item]
        changed = reset_item(kind, item, kind.path(item, base or kind.base), original, expected)
        print("  %s %s: %s" % (kind_name, item, "reset to the original (hash checked)" if changed else "already original, unchanged"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Reset original tables to the original (see the module docstring).")
    parser.add_argument("kind", choices=sorted(KINDS))
    parser.add_argument("items", nargs="*", help="sprite_meta: set names (%s); problems: type numbers 0-33; the other kinds have one table"
                        % ", ".join(SpriteMeta.items))
    parser.add_argument("--all", action="store_true", help="reset every set / type")
    args = parser.parse_args()
    multiple = args.kind in ("sprite_meta", "problems")
    if multiple and args.all == bool(args.items):
        parser.error("name some %s, or give --all (not both)" % ("sets" if args.kind == "sprite_meta" else "types"))
    if not multiple and (args.items or args.all):
        parser.error("%s is one table: no names, no --all" % args.kind)
    try:
        run(args.kind, [] if args.all or not multiple else args.items)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
