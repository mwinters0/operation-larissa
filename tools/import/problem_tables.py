"""The 136 stored problem tables of NEP.DLL <-> the flat records of problem_type_NN.tres, plus the fixtures that guard them.

Teaches: a binary table written by a 1990s authoring tool (a count, fixed-size records, a 7-byte number type) and what it takes
to store it LOSSLESSLY: the same "hashes committed, bytes not" fixture form as sprite_meta.py and sector_header.py
(docs/port/FIDELITY.md).

Each problem type (0-33) has four tables, one per educational level 0-3, resources 10512 + 4 * type + level of NEP.DLL:

    u8 N, then N records of the type's record size (problem_layouts32.json), then zeros up to a multiple of 512 bytes
    (a multiple of 512 bytes in all, 512 to 2560; the extractor cuts the trailing zeros and `original_table` pads them back).
    N = 0: the type does not occur at that level (the table is 512 zero bytes).

A record is a run of fields, laid out one after the other (the layouts have no gaps), each
    c  u8        b  signed byte (type 12's f0 and f2)        w  u16        n  CompactNumber, 7 bytes:
        u16 kind = 0 decimal:   u8 exp, i32 raw             value = raw / 10^exp
        u16 kind = 1 fraction:  i8 whole, i8 num, u16 den, 1 byte the program never reads
        any other u16:          5 more bytes the program never reads (authoring leftovers: 45 of 3,450 numbers)

The flat form in `problem_type_NN.tres` (`records`, one PackedInt64Array per record; `ProblemRecord` reads it) keeps one int per
c / b / w field and four per number, and it keeps EVERY byte of the table, the bytes the program never reads included:
    decimal    (0, raw, exp, 0)
    fraction   (1, whole, num, den + 65536 * the unread byte)       the unread byte is 0 in 426 of 459 fractions
    leftover   (2, the u16 that is not 0 or 1, bytes 2-5 as a u32 (little endian), byte 6)       reads as the decimal 0
`encode_table` turns them back into the table; ProblemType.encode_table does the same in GDScript.
"""
from __future__ import annotations

import json
import struct

from common import DOCS_DATA, GODOT, ORIGINAL_FIXTURES, load_json, raw_table, sha256_hex

TYPES, LEVELS = 34, 4
FIRST_ID = 10512                    # type * 4 + level is added
UNIT = 512                          # a table is a multiple of this many bytes
NUMBER_SIZE = 7
SIGNED_BYTE_FIELDS = {12: (0, 2)}   # DESIGN 5.4: "f0 and f2 are SIGNED bytes (e.g. 246 == -10)"
FIELD_SIZE = {"c": 1, "b": 1, "w": 2, "n": NUMBER_SIZE}

# The committed fixture: provenance + hashes. The written-by-the-importer one holds the table bytes.
HASH_FIXTURE = GODOT / "tests" / "fixtures" / "problem_tables.json"
RAW_FIXTURE = ORIGINAL_FIXTURES / "problem_tables.json"


def real_id(t: int, level: int) -> int:
    return FIRST_ID + 4 * t + level


def extracted_name(t: int, level: int) -> str:
    return "data/NEP_raw/NEP_%d.bin" % real_id(t, level)


# ---- layout -----------------------------------------------------------------

def field_kinds(t: int) -> str:
    """One character per field of type `t`, in file order: c, b, w or n (the string `field_kinds` of problem_type_NN.tres)."""
    spec = load_json(DOCS_DATA / "problem_layouts32.json")["types"][str(t)]
    kinds = "".join(f["kind"] for f in spec["fields"])
    signed = SIGNED_BYTE_FIELDS.get(t, ())
    kinds = "".join("b" if i in signed else k for i, k in enumerate(kinds))
    assert record_size(kinds) == spec["record_size"] and all(
        f["file_off"] == sum(FIELD_SIZE[k] for k in kinds[:i]) for i, f in enumerate(spec["fields"])), "type %d: gaps in the layout" % t
    return kinds


def record_size(kinds: str) -> int:
    return sum(FIELD_SIZE[k] for k in kinds)


def flat_size(kinds: str) -> int:
    """Ints in one flat record: one per field, four per number."""
    return sum(4 if k == "n" else 1 for k in kinds)


def table_size(kinds: str, count: int) -> int:
    """Bytes of a whole table with `count` records: 1 + count * record size, up to a multiple of UNIT."""
    used = 1 + count * record_size(kinds)
    return -(-used // UNIT) * UNIT


# ---- the original ---------------------------------------------------------------

def original_table(t: int, level: int) -> bytes:
    """The whole NEP.DLL resource of type `t`, `level` (tools/extract/extract_data.py cut its trailing zeros; they are padded
    back by the size rule above, which test_problem_tables.py checks against the DLL itself)."""
    raw = raw_table(real_id(t, level))
    kinds = field_kinds(t)
    count = raw[0] if raw else 0
    size = table_size(kinds, count)
    assert len(raw) <= size, "table %d/%d is longer than its count says" % (t, level)
    return raw.ljust(size, b"\0")


# ---- bytes -> flat records --------------------------------------------------------

def decode_number(b: bytes) -> list[int]:
    kind = struct.unpack_from("<H", b)[0]
    if kind == 0:
        return [0, struct.unpack_from("<i", b, 3)[0], b[2], 0]
    if kind == 1:
        whole, num, den = struct.unpack_from("<bbH", b, 2)
        return [1, whole, num, den + 65536 * b[6]]
    return [2, kind, struct.unpack_from("<I", b, 2)[0], b[6]]


def decode_table(kinds: str, data: bytes) -> list[list[int]]:
    """The flat records of a whole table. ValueError if the table is shorter than its count says or has bytes after the records."""
    count = data[0]
    size = record_size(kinds)
    if len(data) != table_size(kinds, count) or any(data[1 + count * size:]):
        raise ValueError("a table of %d records should be %d bytes of records and then zeros, up to %d" % (count, 1 + count * size, table_size(kinds, count)))
    records = []
    for i in range(count):
        at = 1 + i * size
        flat: list[int] = []
        for kind in kinds:
            if kind == "n":
                flat += decode_number(data[at:at + NUMBER_SIZE])
            elif kind == "b":
                flat.append(struct.unpack_from("<b", data, at)[0])
            elif kind == "w":
                flat.append(struct.unpack_from("<H", data, at)[0])
            else:
                flat.append(data[at])
            at += FIELD_SIZE[kind]
        records.append(flat)
    return records


# ---- flat records -> bytes ------------------------------------------------------------

def _range(value: int, low: int, high: int, what: str) -> int:
    if not low <= value <= high:
        raise ValueError("%s: %d does not fit (%d to %d)" % (what, value, low, high))
    return value


def encode_number(flat: list[int], what: str = "number") -> bytes:
    kind, a, b, c = flat
    if kind == 0:
        _range(c, 0, 0, what + ", the fourth int of a decimal")
        return struct.pack("<HBi", 0, _range(b, 0, 255, what + " exponent"), _range(a, -2 ** 31, 2 ** 31 - 1, what + " mantissa"))
    if kind == 1:
        _range(c, 0, 256 * 65536 - 1, what + " denominator + 65536 * the unread byte")
        return struct.pack("<HbbHB", 1, _range(a, -128, 127, what + " whole part"), _range(b, -128, 127, what + " numerator"), c & 0xFFFF, c >> 16)
    if kind == 2:
        return struct.pack("<HIB", _range(a, 2, 65535, what + " leftover kind"), _range(b, 0, 2 ** 32 - 1, what + " leftover bytes"), _range(c, 0, 255, what + " last leftover byte"))
    raise ValueError("%s: kind %d does not exist (0 decimal, 1 fraction, 2 leftover bytes)" % (what, kind))


def encode_table(kinds: str, records: list[list[int]]) -> bytes:
    """The whole table (zero padded) of `records`, flat records as decode_table() gives them. ValueError for what does not fit."""
    if len(records) > 255:
        raise ValueError("%d records, but a table holds at most 255 (one count byte)" % len(records))
    out = bytearray([len(records)])
    for i, flat in enumerate(records):
        if len(flat) != flat_size(kinds):
            raise ValueError("record %d: %d ints, but the fields %r take %d" % (i, len(flat), kinds, flat_size(kinds)))
        at = 0
        for k, kind in enumerate(kinds):
            what = "record %d field f%d" % (i, k)
            if kind == "n":
                out += encode_number(flat[at:at + 4], what)
                at += 4
                continue
            v = flat[at]
            at += 1
            out += struct.pack({"c": "<B", "b": "<b", "w": "<H"}[kind], _range(v, {"c": 0, "b": -128, "w": 0}[kind], {"c": 255, "b": 127, "w": 65535}[kind], what))
    return bytes(out).ljust(table_size(kinds, len(records)), b"\0")


# ---- the fixtures -----------------------------------------------------------------

def build_hash_fixture() -> str:
    """The COMMITTED fixture godot/tests/fixtures/problem_tables.json: per table its provenance and the SHA-256 of the whole
    resource. No original bytes in it."""
    comment = ("Provenance and SHA-256 hashes of the ORIGINAL stored problem tables, written by tools/import/step_problems.py "
               "(import_all.py) from the NEP.DLL resources named under \"real_id\" (10512 + 4 * type + level; saved by "
               "tools/extract/extract_data.py from your copy of the game), never hand-edited. It holds no original bytes: per table "
               "\"size\" bytes (a count byte, the records, zeros up to a multiple of 512; the extracted files are shorter only because "
               "the extractor cuts trailing zeros, which is padded back) and \"sha256\", the hash of all of it. godot/tests/"
               "test_problem_table_fidelity.gd checks that ProblemType.encode_table() hashes to these. The table bytes themselves are "
               "written to the git-ignored tests/fixtures/original/problem_tables.json by the same importer run, for first-difference "
               "messages. See docs/port/FIDELITY.md, \"Fixtures commit hashes, not bytes\".")
    rows = []
    for t in range(TYPES):
        for level in range(LEVELS):
            raw = original_table(t, level)
            rows.append('  {"type": %d, "level": %d, "source": {"file": "NEP.DLL", "real_id": %d, "extracted": "%s"}, "offset": 0, "size": %d, "sha256": "%s"}'
                        % (t, level, real_id(t, level), extracted_name(t, level), len(raw), sha256_hex(raw)))
    text = "\n".join(["{", ' "comment": %s,' % json.dumps(comment), ' "tables": [', ",\n".join(rows), " ]", "}"]) + "\n"
    json.loads(text)
    return text


def build_raw_fixture() -> str:
    """The NOT committed file godot/tests/fixtures/original/problem_tables.json: every table (hex), for the first-difference
    messages and the reset tool. Rebuilt from YOUR copy."""
    comment = ("ORIGINAL BYTES of the stored problem tables, written by the importer from your copy of the game. Not committed "
               "(.gitignore); the committed hashes are in ../problem_tables.json. See docs/port/FIDELITY.md.")
    rows = ['  {"type": %d, "level": %d, "hex": "%s"}' % (t, level, original_table(t, level).hex())
            for t in range(TYPES) for level in range(LEVELS)]
    text = "\n".join(["{", ' "comment": %s,' % json.dumps(comment), ' "tables": [', ",\n".join(rows), " ]", "}"]) + "\n"
    json.loads(text)
    return text
