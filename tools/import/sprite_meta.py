"""Sprite sizes and hit rectangles: the original tables <-> the fields of SpriteMetaTable, plus the fixtures that guard them.

Teaches: the "hashes committed, bytes not" fixture form of docs/port/FIDELITY.md for tables that are whole NEP.DLL resources,
and the extractor's habit of cutting trailing zeros, which the fixture undoes by padding back to the resource's real size.

Each creature set (the 28 common creatures, the 7 ink bursts, the creatures of each of the 7 zones) has three resources in
NEP.DLL, 512 bytes each (checked against the DLL by test_sprite_meta.py):
    widths    u8 per sprite    the sprite's width / 2
    heights   u8 per sprite    the sprite's height / 2
    hit rects 8 bytes per sprite   x1 y1 x2 y2 of the hit rectangle (each / 2), then x1 y1 x2 y2 of the rectangle of the
                                   horizontally flipped sprite
Only the first `count` entries are used (count = the number of pictures of the set, a constant of this importer in
common.py: the DLL does not say); everything after them is zero in all 27 resources. SpriteMetaTable keeps the used
entries in pixels (doubled) as sizes / hit_rects (position + size) / hit_rects_flipped, and `SpriteMetaTable.encode_*()`
rebuilds the 512 bytes, zero tail included. The Godot side is godot/src/resources/sprite_meta_table.gd.
"""
from __future__ import annotations

import json

from common import (COMMON_CREATURES, GODOT, INK_FRAMES, ORIGINAL_FIXTURES, ZONE_FOE_COUNTS, raw_table, sha256_hex)

RESOURCE_SIZE = 512
KINDS = ("widths", "heights", "hit_rects")

# (name, (width table, height table, hit rectangle table) = real NEP.DLL resource ids, number of sprites). The name is
# the file godot/data/sprite_meta/sprite_meta_<name>.tres.
ZONE_META_IDS = [(10033, 10034, 10035), (10048, 10049, 10050), (10063, 10064, 10065),
                 (10078, 10079, 10080), (10093, 10094, 10095), (10712, 10713, 10714), (10718, 10719, 10720)]
SETS = [("common", (10018, 10019, 10020), COMMON_CREATURES), ("ink", (10015, 10016, 10017), INK_FRAMES)] + \
       [("zone%d" % z, ids, ZONE_FOE_COUNTS[z]) for z, ids in enumerate(ZONE_META_IDS)]

# The committed fixture: provenance + hashes. The written-by-the-importer one holds the table bytes.
HASH_FIXTURE = GODOT / "tests" / "fixtures" / "sprite_meta.json"
RAW_FIXTURE = ORIGINAL_FIXTURES / "sprite_meta.json"


def extracted_name(real_id: int) -> str:
    return "data/NEP_raw/NEP_%d.bin" % real_id


def original_resource(real_id: int) -> bytes:
    """The whole 512-byte NEP.DLL resource `real_id`. tools/extract/extract_data.py saves it with the trailing zero bytes
    cut off, so the extracted file is padded back here (test_sprite_meta.py checks it against the DLL itself)."""
    raw = raw_table(real_id)
    assert len(raw) <= RESOURCE_SIZE, "resource %d is longer than %d bytes" % (real_id, RESOURCE_SIZE)
    return raw.ljust(RESOURCE_SIZE, b"\0")


def original_tables(ids: tuple[int, int, int]) -> tuple[bytes, bytes, bytes]:
    first, second, third = ids
    return original_resource(first), original_resource(second), original_resource(third)


def decode_set(tables: tuple[bytes, bytes, bytes], count: int) -> dict:
    """The first `count` sprites as plain data in pixels: sizes (w, h), hit_rects and hit_rects_flipped as (x, y, w, h).
    Asserts that nothing but zeros follows them."""
    widths, heights, rects = tables
    assert not any(widths[count:]) and not any(heights[count:]) and not any(rects[8 * count:]), "non-zero bytes after the sprites"
    out = {"sizes": [], "hit_rects": [], "hit_rects_flipped": []}
    for i in range(count):
        out["sizes"].append((widths[i] * 2, heights[i] * 2))
        for offset, key in ((0, "hit_rects"), (4, "hit_rects_flipped")):
            x1, y1, x2, y2 = (v * 2 for v in rects[8 * i + offset:8 * i + offset + 4])
            out[key].append((x1, y1, x2 - x1, y2 - y1))
    return out


def encode_set(meta: dict) -> tuple[bytes, bytes, bytes]:
    """The way back: `decode_set`'s dict -> the three 512-byte resources. Raises ValueError for a value they cannot hold
    (the refusals of SpriteMetaTable.problems())."""
    count = len(meta["sizes"])
    if len(meta["hit_rects"]) != count or len(meta["hit_rects_flipped"]) != count or 8 * count > RESOURCE_SIZE:
        raise ValueError("%d sizes, %d hit rectangles" % (count, len(meta["hit_rects"])))
    widths, heights, rects = bytearray(RESOURCE_SIZE), bytearray(RESOURCE_SIZE), bytearray(RESOURCE_SIZE)

    def half(value: int) -> int:
        if value % 2 or not 0 <= value <= 2 * 255:
            raise ValueError("%d is not an even number from 0 to 510" % value)
        return value // 2

    for i in range(count):
        widths[i], heights[i] = (half(v) for v in meta["sizes"][i])
        for offset, key in ((0, "hit_rects"), (4, "hit_rects_flipped")):
            x, y, w, h = meta[key][i]
            rects[8 * i + offset:8 * i + offset + 4] = bytes(half(v) for v in (x, y, x + w, y + h))
    return bytes(widths), bytes(heights), bytes(rects)


def build_hash_fixture() -> str:
    """The COMMITTED fixture godot/tests/fixtures/sprite_meta.json: per sprite set the provenance and the SHA-256 of each of
    its three whole 512-byte resources. No original bytes in it."""
    comment = ("Provenance and SHA-256 hashes of the ORIGINAL sprite size and hit rectangle tables, written by "
               "tools/import/step_sprites.py (import_all.py) from the NEP.DLL resources named under \"real_id\" (saved by "
               "tools/extract/extract_data.py from your copy of the game), never hand-edited. It holds no original bytes: "
               "per set (godot/data/sprite_meta/sprite_meta_<name>.tres) the three tables widths (1 byte per sprite), heights (1 byte per "
               "sprite) and hit_rects (8 bytes per sprite), each the whole resource exactly as NEP.DLL holds it, \"size\" bytes "
               "(the used entries, then zeros; the extracted files are shorter only because the extractor cuts trailing zeros, which is "
               "padded back), \"sha256\" the hash of all of it. godot/tests/legacy/test_sprite_meta_fidelity.gd checks that "
               "SpriteMetaTable.encode_widths() / encode_heights() / encode_hit_rects() hash to these. The table bytes themselves are "
               "written to the git-ignored tests/fixtures/original/sprite_meta.json by the same importer run, for first-difference "
               "messages. See docs/port/FIDELITY.md, \"Fixtures commit hashes, not bytes\".")
    rows = []
    for name, ids, _count in SETS:
        tables = ",\n".join(
            '    "%s": {"source": {"file": "NEP.DLL", "real_id": %d, "extracted": "%s"}, "offset": 0, "size": %d, "sha256": "%s"}'
            % (kind, real_id, extracted_name(real_id), RESOURCE_SIZE, sha256_hex(original_resource(real_id)))
            for kind, real_id in zip(KINDS, ids))
        rows.append('  {"name": "%s", "tables": {\n%s\n  }}' % (name, tables))
    text = "\n".join(["{", ' "comment": %s,' % json.dumps(comment), ' "sets": [', ",\n".join(rows), " ]", "}"]) + "\n"
    json.loads(text)                       # must stay valid JSON
    return text


def build_raw_fixture() -> str:
    """The NOT committed file godot/tests/fixtures/original/sprite_meta.json: the three tables (hex) of every set, for tests
    that name the field of a first difference. Rebuilt from YOUR copy."""
    comment = ("ORIGINAL BYTES of the sprite size and hit rectangle tables, written by the importer from your copy of the game. "
               "Not committed (.gitignore); the committed hashes are in ../sprite_meta.json. See docs/port/FIDELITY.md.")
    rows = []
    for name, ids, _count in SETS:
        hexes = ", ".join('"%s_hex": "%s"' % (kind, original_resource(i).hex()) for kind, i in zip(KINDS, ids))
        rows.append('  {"name": "%s", %s}' % (name, hexes))
    text = "\n".join(["{", ' "comment": %s,' % json.dumps(comment), ' "sets": [', ",\n".join(rows), " ]", "}"]) + "\n"
    json.loads(text)
    return text
