"""A sector's header: the original 0x72 bytes <-> the fields of sector_NN.tres, plus the fixtures that guard them.

Teaches: reading a fixed binary layout in Python, undoing the conversions a decoder makes (halved positions, value + 1
neighbours) so that the way back is proven exact, and the "hashes committed, bytes not" fixture form of
docs/port/FIDELITY.md: the committed file keeps provenance and SHA-256 hashes, the original bytes go to a git-ignored place.

The layout is DESIGN 4.1 (the header is the first 0x72 bytes of a sector's data, then 12 screen records, then zeros
up to the resource's 0x3E00 bytes):
    0x00 u16 start x / 2    0x02 u16 start y / 2    0x04 u16 piece count (at most 11)
    0x06 u8[11] piece screen    0x11 u16[11] piece x / 2    0x27 u16[11] piece y / 2
    0x3D u8 unused    0x3E u16 start frame    0x40 u8 unused    0x41 u8 unused
    (the game never reads 0x3D, 0x40 and 0x41; kept for byte fidelity)
    0x42 u8[12] left neighbour, 0x4E right, 0x5A up, 0x66 down      destination screen + 1, 0 = none

Everything is read from the RAW sector resource (the same bytes the screen records come from: screen_record.py), never from
the converted values in docs/data/sectors.json. The Godot side is SectorData.encode() / encode_resource().

What the 32 original headers show (checked here, so a surprise is an error and not silently dropped):
    * the unused piece slots (slot number >= the piece count) are zero except in sector 6 (slot 7) and sector 22 (slot 9):
      stale entries, kept as `stale_pieces`;
    * the bytes after the last screen record, up to 0x3E00, are zero in all 32 resources (checked against NEP.DLL by
      test_sector_header.py; the extracted file ends at its last non-zero byte, so its length shows it too);
    * the game never reads bytes 0x3D, 0x40 and 0x41: 11 / 0x48 / 0 in sectors 0-10 and 12-24, all zero in the others.
"""
from __future__ import annotations

import json

import screen_record
from common import EXTRACTED, GODOT, ORIGINAL_FIXTURES, SCREENS, sha256_hex

HEADER_SIZE = screen_record.HEADER_SIZE
RESOURCE_SIZE = screen_record.SECTOR_SIZE
MAX_PIECES = 11
SIDES = ("left", "right", "up", "down")

# The committed fixture: provenance + hashes. The written-by-the-importer one holds the header bytes.
HASH_FIXTURE = GODOT / "tests" / "fixtures" / "sector_headers.json"
RAW_FIXTURE = ORIGINAL_FIXTURES / "sector_headers.json"


def u16(raw: bytes, offset: int) -> int:
    return int.from_bytes(raw[offset:offset + 2], "little")


def original_resource(sec: dict) -> bytes:
    """The whole 0x3E00-byte original resource of the sector dict from docs/data/sectors.json (only its "source" is
    used: the bytes come from the extracted copy of the game's file).

    NEP.DLL holds every sector resource with its full directory size of 0x3E00 bytes; tools/extract/extract_data.py
    saves it with the trailing zero bytes cut off (`rstrip`), so the extracted file ends at the last non-zero byte and
    is padded back here. A file longer than the 12 records would mean a non-zero byte in the tail. (Checked against
    the DLL itself for all 32 sectors by test_sector_header.py.)"""
    raw = (EXTRACTED / sec["source"]["extracted"]).read_bytes()
    assert sec["source"]["size"] == RESOURCE_SIZE
    assert len(raw) <= HEADER_SIZE + SCREENS * screen_record.RECORD_SIZE, \
        "sector %d: non-zero bytes after the last screen record" % sec["index"]
    return raw.ljust(RESOURCE_SIZE, b"\0")


def decode_header(raw: bytes) -> dict:
    """The header as plain Python data, in the units SectorData uses: positions in pixels, neighbours as destination
    screen or -1, `pieces` as (screen, x, y) of the active pieces, `stale_pieces` as (slot, screen, x, y) of the
    non-zero entries in unused slots, and the unknown fields raw."""
    raw = raw[:HEADER_SIZE]
    assert len(raw) == HEADER_SIZE
    count = u16(raw, 0x04)
    assert count <= MAX_PIECES, "piece count %d" % count

    def piece(slot: int) -> tuple[int, int, int]:
        return raw[0x06 + slot], u16(raw, 0x11 + 2 * slot) * 2, u16(raw, 0x27 + 2 * slot) * 2

    return {
        "start_pos": (u16(raw, 0x00) * 2, u16(raw, 0x02) * 2),
        "start_frame": u16(raw, 0x3E),
        "pieces": [piece(slot) for slot in range(count)],
        "stale_pieces": [(slot,) + piece(slot) for slot in range(count, MAX_PIECES) if any(piece(slot))],
        "header_unused_3d": raw[0x3D],
        "header_unused_40": raw[0x40],
        "header_unused_41": raw[0x41],
        "neighbors": {side: [v - 1 for v in raw[0x42 + 12 * n:0x4E + 12 * n]] for n, side in enumerate(SIDES)},
    }


def encode_header(h: dict) -> bytes:
    """The way back: `decode_header`'s dict -> the 0x72 bytes. Raises ValueError for a value the header cannot hold
    (the refusals of SectorData.header_problems())."""
    out = bytearray(HEADER_SIZE)

    def put16(offset: int, value: int) -> None:
        if not 0 <= value <= 0xFFFF:
            raise ValueError("header value %d at 0x%02x does not fit in two bytes" % (value, offset))
        out[offset:offset + 2] = value.to_bytes(2, "little")

    def put_piece(slot: int, screen: int, x: int, y: int) -> None:
        if not 0 <= slot < MAX_PIECES or not 0 <= screen <= 0xFF or x % 2 or y % 2:
            raise ValueError("piece slot %d: screen %d at (%d, %d)" % (slot, screen, x, y))
        out[0x06 + slot] = screen
        put16(0x11 + 2 * slot, x // 2)
        put16(0x27 + 2 * slot, y // 2)

    x, y = h["start_pos"]
    if x % 2 or y % 2:
        raise ValueError("start (%d, %d) is not on the 2-pixel grid" % (x, y))
    put16(0x00, x // 2)
    put16(0x02, y // 2)
    if len(h["pieces"]) > MAX_PIECES:
        raise ValueError("%d pieces" % len(h["pieces"]))
    put16(0x04, len(h["pieces"]))
    for slot, screen, px, py in h["stale_pieces"]:
        put_piece(slot, screen, px, py)
    for slot, (screen, px, py) in enumerate(h["pieces"]):      # an active piece overwrites a stale slot
        put_piece(slot, screen, px, py)
    for name, offset in (("header_unused_3d", 0x3D), ("header_unused_40", 0x40), ("header_unused_41", 0x41)):
        if not 0 <= h[name] <= 0xFF:
            raise ValueError("%s %d" % (name, h[name]))
        out[offset] = h[name]
    put16(0x3E, h["start_frame"])
    for n, side in enumerate(SIDES):
        table = h["neighbors"][side]
        if len(table) != SCREENS or any(not -1 <= v < SCREENS for v in table):
            raise ValueError("%s neighbours %s" % (side, table))
        out[0x42 + 12 * n:0x4E + 12 * n] = bytes(v + 1 for v in table)
    return bytes(out)


def build_hash_fixture(sectors: list[dict]) -> str:
    """The COMMITTED fixture godot/tests/fixtures/sector_headers.json: per sector its provenance (the raw resource
    it comes from) and two SHA-256 hashes, of the 0x72 header bytes and of the whole 0x3E00-byte resource. No
    original bytes in it."""
    comment = ("Provenance and SHA-256 hashes of every sector's ORIGINAL header, written by tools/import/step_sectors.py "
               "(import_all.py) from the raw sector resource named under \"source\" (saved by tools/extract/extract_data.py "
               "from your copy of the game), never hand-edited. It holds no original bytes: header_sha256 is the hash of "
               "the 0x72 header bytes at \"offset\" 0 (\"size\" bytes), resource_sha256 the hash of the whole resource "
               "exactly as NEP.DLL holds it: the 0x3E00 bytes of source.size, as the resource directory says (header, 12 screen records, zero "
               "tail; the extracted files are shorter only because the extractor cuts trailing zeros, which is padded back). godot/tests/legacy/test_sector_header_fidelity.gd checks that "
               "SectorData.encode() and encode_resource() hash to these. The header bytes themselves are written to the "
               "git-ignored tests/fixtures/original/sector_headers.json by the same importer run, for first-difference "
               "messages. See docs/port/FIDELITY.md, \"Fixtures commit hashes, not bytes\".")
    out = ["{", ' "comment": %s,' % json.dumps(comment), ' "sectors": [']
    rows = []
    for sec in sectors:
        resource = original_resource(sec)
        rows.append('  {"index": %d, "source": %s, "offset": 0, "size": %d,\n   "header_sha256": "%s",\n   "resource_sha256": "%s"}'
                    % (sec["index"], json.dumps(sec["source"]), HEADER_SIZE, sha256_hex(resource[:HEADER_SIZE]), sha256_hex(resource)))
    out.append(",\n".join(rows))
    out += [" ]", "}"]
    text = "\n".join(out) + "\n"
    json.loads(text)                       # must stay valid JSON
    return text


def build_raw_fixture(sectors: list[dict]) -> str:
    """The NOT committed file godot/tests/fixtures/original/sector_headers.json: the original header bytes (hex) of
    every sector, for tests that name the field of a first difference and for reset tools. Rebuilt from YOUR copy."""
    comment = ("ORIGINAL BYTES of every sector header, written by the importer from your copy of the game. Not committed "
               "(.gitignore); the committed hashes are in ../sector_headers.json. See docs/port/FIDELITY.md.")
    out = ["{", ' "comment": %s,' % json.dumps(comment), ' "sectors": [']
    rows = ['  {"index": %d, "offset": 0, "header_hex": "%s"}' % (sec["index"], original_resource(sec)[:HEADER_SIZE].hex())
            for sec in sectors]
    out.append(",\n".join(rows))
    out += [" ]", "}"]
    text = "\n".join(out) + "\n"
    json.loads(text)
    return text
