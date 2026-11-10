"""A creature's 34-byte record: the original bytes <-> the fields of FoeData, plus the fixtures that guard them.

Teaches: the same "hashes committed, bytes not" fixture form as sector_header.py (docs/port/FIDELITY.md, "Fixtures commit
hashes, not bytes"), one hash per WHOLE record, and a decoder whose way back is proven exact.

A sector's foe buffer (DESIGN 3.5) is `u8 count`, then `count` records of 34 bytes, then the script bytecode. The record:
    0x00 u8 dormant    0x01 u8 hidden    0x02 u8 screen    0x03 u16 x / 2    0x05 u16 y / 2
    0x07 u8 frame    0x08 u8 flip    0x09 u8 frame min    0x0A u8 frame max
    0x0B u16 hit script    0x0D u16 ink script    0x0F i8 damage    0x10 u16 start pc
    0x12..0x21 the creature's run-time state while it is interrupted (saved pc, loop counters, saved x / y / frame /
               flip): the game writes it, the data starts out all zero (16 bytes, kept as `runtime_state`)
Everything is read from the RAW foe buffer (the extracted NEP.DLL resource named in sectors.json under foes.source),
never from the converted values in docs/data/sectors.json. The Godot side is FoeData.encode().

What the 640 original records show (checked here, so a surprise is an error and not silently dropped):
    * dormant, hidden and flip are 0 or 1 in every record (FoeData keeps them as booleans);
    * the 16 run-time state bytes are zero in every record;
    * the three script entry points are the bytes the script text assembles to (godot/tests/fixtures/
      original/foe_scripts.json, hashed in foe_scripts.json): FoeData keeps them as LABELS, and SectorData.compile() turns them back into numbers.
"""
from __future__ import annotations

import json

from common import EXTRACTED, GODOT, ORIGINAL_FIXTURES, sha256_hex

RECORD_SIZE = 34
RUNTIME_STATE_AT = 0x12
RUNTIME_STATE_SIZE = RECORD_SIZE - RUNTIME_STATE_AT      # 16

# The committed fixture: provenance + hashes. The written-by-the-importer one holds the record bytes.
HASH_FIXTURE = GODOT / "tests" / "fixtures" / "foe_records.json"
RAW_FIXTURE = ORIGINAL_FIXTURES / "foe_records.json"


def u16(raw: bytes, offset: int) -> int:
    return int.from_bytes(raw[offset:offset + 2], "little")


def record_offset(k: int) -> int:
    """Offset of record k in the foe buffer."""
    return 1 + RECORD_SIZE * k


def original_buffer(sec: dict) -> bytes:
    """The foe buffer of the sector dict from docs/data/sectors.json (only its foes.source is used: the bytes come from the
    extracted copy of the game's file; the extractor cuts trailing zero bytes, which never reach into the records, since
    the script bytecode follows them)."""
    raw = (EXTRACTED / sec["foes"]["source"]["extracted"]).read_bytes()
    assert len(raw) >= record_offset(raw[0]), "sector %d: foe buffer shorter than its records" % sec["index"]
    return raw


def original_records(sec: dict) -> list[bytes]:
    """The 34 original bytes of every creature of the sector, in order."""
    raw = original_buffer(sec)
    return [raw[record_offset(k):record_offset(k) + RECORD_SIZE] for k in range(raw[0])]


def decode_record(raw: bytes) -> dict:
    """One record as plain Python data, in the units FoeData uses: positions in pixels, flags as booleans, damage signed,
    the entry points as buffer offsets, and the run-time state raw."""
    assert len(raw) == RECORD_SIZE
    for offset in (0, 1, 8):
        assert raw[offset] in (0, 1), "flag byte 0x%02x is %d, not 0 or 1" % (offset, raw[offset])
    return {
        "dormant": bool(raw[0]), "hidden": bool(raw[1]), "screen": raw[2],
        "pos": (u16(raw, 3) * 2, u16(raw, 5) * 2),
        "frame": raw[7], "flip": bool(raw[8]), "frame_min": raw[9], "frame_max": raw[10],
        "script_hit": u16(raw, 0x0B), "script_ink": u16(raw, 0x0D),
        "damage": raw[0x0F] - 256 if raw[0x0F] >= 128 else raw[0x0F],
        "pc": u16(raw, 0x10),
        "runtime_state": raw[RUNTIME_STATE_AT:],
    }


def decode_records(sec: dict) -> list[dict]:
    return [decode_record(raw) for raw in original_records(sec)]


def encode_record(r: dict) -> bytes:
    """The way back: `decode_record`'s dict -> the 34 bytes. Raises ValueError for a value the record cannot hold (the
    refusals of FoeData.problems())."""
    out = bytearray(RECORD_SIZE)

    def put(offset: int, value: int, size: int = 1) -> None:
        if not 0 <= value < 256 ** size:
            raise ValueError("record value %d at 0x%02x does not fit in %d byte(s)" % (value, offset, size))
        out[offset:offset + size] = value.to_bytes(size, "little")

    def put_pos(offset: int, value: int) -> None:
        if value % 2:
            raise ValueError("position %d is not on the 2-pixel grid" % value)
        put(offset, value // 2, 2)

    put(0, int(r["dormant"]))
    put(1, int(r["hidden"]))
    put(2, r["screen"])
    put_pos(3, r["pos"][0])
    put_pos(5, r["pos"][1])
    put(7, r["frame"])
    put(8, int(r["flip"]))
    put(9, r["frame_min"])
    put(10, r["frame_max"])
    put(0x0B, r["script_hit"], 2)
    put(0x0D, r["script_ink"], 2)
    if not -128 <= r["damage"] <= 127:
        raise ValueError("damage %d" % r["damage"])
    put(0x0F, r["damage"] & 0xFF)
    put(0x10, r["pc"], 2)
    state = bytes(r["runtime_state"])
    if len(state) != RUNTIME_STATE_SIZE:
        raise ValueError("%d run-time state bytes" % len(state))
    out[RUNTIME_STATE_AT:] = state
    return bytes(out)


def build_hash_fixture(sectors: list[dict]) -> str:
    """The COMMITTED fixture godot/tests/fixtures/foe_records.json: per sector the provenance of its foe buffer and, per
    creature, the offset of its record and the SHA-256 of the whole 34 bytes. No original bytes in it."""
    comment = ("Provenance and SHA-256 hashes of every creature's ORIGINAL 34-byte record, written by "
               "tools/import/step_sectors.py (import_all.py) from the raw foe buffer named under \"source\" (NEP.DLL, saved by "
               "tools/extract/extract_data.py from your copy of the game; docs/data/sectors.json, from "
               "tools/analysis/export_json.py, carries where it comes from), never hand-edited. It holds no original bytes: "
               "creature k of a sector is the \"size\" bytes at \"offset\" of its buffer (1 + 34 * k: the buffer starts "
               "with the count byte), \"sha256\" the hash of the whole record. godot/tests/legacy/test_foe_record_fidelity.gd "
               "checks that SectorData.encode_foe_records() hashes to these. The record bytes themselves are written to the "
               "git-ignored tests/fixtures/original/foe_records.json by the same importer run, for first-difference "
               "messages. See docs/port/FIDELITY.md, \"Fixtures commit hashes, not bytes\".")
    out = ["{", ' "comment": %s,' % json.dumps(comment), ' "size": %d,' % RECORD_SIZE, ' "sectors": [']
    rows = []
    for sec in sectors:
        records = original_records(sec)
        foes = ",\n".join('    {"offset": %d, "sha256": "%s"}' % (record_offset(k), sha256_hex(raw))
                          for k, raw in enumerate(records))
        rows.append('  {"index": %d, "source": %s, "foes": [\n%s\n  ]}' % (sec["index"], json.dumps(sec["foes"]["source"]), foes))
    out.append(",\n".join(rows))
    out += [" ]", "}"]
    text = "\n".join(out) + "\n"
    json.loads(text)                       # must stay valid JSON
    return text


def build_raw_fixture(sectors: list[dict]) -> str:
    """The NOT committed file godot/tests/fixtures/original/foe_records.json: the original record bytes (hex) of every
    creature, for tests that name the field of a first difference. Rebuilt from YOUR copy."""
    comment = ("ORIGINAL BYTES of every creature record, written by the importer from your copy of the game. Not committed "
               "(.gitignore); the committed hashes are in ../foe_records.json. See docs/port/FIDELITY.md.")
    out = ["{", ' "comment": %s,' % json.dumps(comment), ' "sectors": [']
    rows = ['  {"index": %d, "records_hex": [%s]}' % (sec["index"], ", ".join('"%s"' % raw.hex() for raw in original_records(sec)))
            for sec in sectors]
    out.append(",\n".join(rows))
    out += [" ]", "}"]
    text = "\n".join(out) + "\n"
    json.loads(text)
    return text
