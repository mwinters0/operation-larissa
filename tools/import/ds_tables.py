"""Two small tables from the program's data segment: the trigger table and the default educational levels, plus the
fixtures that guard them.

Teaches: tables that are not resources of a DLL but bytes inside ONWIN.EXE (the 16-bit program's DGROUP, which starts
at file offset 0x3C200: "DS" offsets in DESIGN and in the decompilation count from there), and the same "hashes
committed, bytes not" fixture form as sector_header.py (docs/port/FIDELITY.md).

    trigger table   DS 0x22BE, 63 x 4 x 2 = 504 bytes   trigger_table[slot][educational level][pick] = problem type (0-33);
                    a screen's math trigger names the slot, the game picks one of the two candidates at random
    default levels  DS 0x25A8, 10 bytes                 the educational level (0-3) when the player did not customise the
                    game, indexed game * 5 + zone (game 0 = Voyager, 1 = Expert; zone 0-4)

The bytes come from docs/data/trigger_table.json and docs/data/zone_defaults.json (tools/analysis/export_json.py reads them
from the program); test_ds_tables.py checks both against ONWIN.EXE on the CD image when there is one. What the neighbours
of the tables are is not known: the two bytes 0x20 0x21 follow the trigger table directly (DS 0x24B6), which is slot 63 if the table
were one entry longer; the game's code reads 63 slots, so they are left out. The Godot side is TriggerTable.encode() and
ZoneTable.encode_default_edu_levels().
"""
from __future__ import annotations

import json

from common import DOCS_DATA, GODOT, ORIGINAL_FIXTURES, load_json, sha256_hex

DS_FILE_OFFSET = 0x3C200               # where the data segment starts in ONWIN.EXE
SLOTS, LEVELS, PICKS = 63, 4, 2
TRIGGER_TABLE = {"ds_offset": 0x22BE, "size": SLOTS * LEVELS * PICKS}
DEFAULT_EDU = {"ds_offset": 0x25A8, "size": 10}

TRIGGER_HASH_FIXTURE = GODOT / "tests" / "fixtures" / "trigger_table.json"
TRIGGER_RAW_FIXTURE = ORIGINAL_FIXTURES / "trigger_table.json"
ZONES_HASH_FIXTURE = GODOT / "tests" / "fixtures" / "zones.json"
ZONES_RAW_FIXTURE = ORIGINAL_FIXTURES / "zones.json"


def source_of(table: dict) -> dict:
    return {"file": "ONWIN.EXE", "ds_offset": table["ds_offset"], "file_offset": DS_FILE_OFFSET + table["ds_offset"],
            "size": table["size"]}


def trigger_table() -> bytes:
    """The 504 bytes, laid out [slot][level][pick]."""
    rows = load_json(DOCS_DATA / "trigger_table.json")["trigger_to_type"]
    flat = bytes(v for slot in rows for level in slot for v in level)
    assert len(rows) == SLOTS and all(len(slot) == LEVELS for slot in rows) and len(flat) == TRIGGER_TABLE["size"]
    return flat


def default_edu_levels() -> bytes:
    """The 10 bytes, indexed game * 5 + zone."""
    data = load_json(DOCS_DATA / "zone_defaults.json")
    assert data["source"] == source_of(DEFAULT_EDU), "zone_defaults.json is not the table at DS 0x25A8"
    raw = bytes(data["default_edu_level"])
    assert len(raw) == DEFAULT_EDU["size"] and max(raw) <= 3, "an educational level is 0 to 3"
    return raw


def encode_trigger_table(values: list[int]) -> bytes:
    """The 504 bytes from the stored `table` of trigger_table.tres (one problem type, 0-33, per entry)."""
    if len(values) != TRIGGER_TABLE["size"] or not all(0 <= v <= 255 for v in values):
        raise ValueError("the trigger table is %d bytes of 0 to 255" % TRIGGER_TABLE["size"])
    return bytes(values)


def encode_default_edu_levels(voyager: list[int], expert: list[int]) -> bytes:
    """The 10 bytes from the levels of zones 0-4 stored in zones.tres: Voyager zones 0-4, then Expert zones 0-4."""
    raw = bytes(list(voyager) + list(expert))
    if len(voyager) != 5 or len(expert) != 5 or max(raw) > 3:
        raise ValueError("an educational level is 0 to 3, one per zone 0-4 and game")
    return raw


def _hash_fixture(what: str, table: dict, raw: bytes, test: str, encoder: str, raw_name: str) -> str:
    comment = ("Provenance and the SHA-256 hash of the ORIGINAL %s, written by tools/import/step_sectors.py "
               "(import_all.py) from the program's data segment (docs/data/, from tools/analysis/export_json.py), never hand-edited. "
               "It holds no original bytes: \"sha256\" is the hash of the whole table, the \"size\" bytes at \"file_offset\" of ONWIN.EXE "
               "(DS offset \"ds_offset\"). godot/tests/%s checks that %s hashes to it. The table bytes themselves are written "
               "to the git-ignored tests/fixtures/original/%s by the same importer run, for first-difference messages. "
               "See docs/port/FIDELITY.md, \"Fixtures commit hashes, not bytes\"." % (what, test, encoder, raw_name))
    text = '{\n "comment": %s,\n "source": %s,\n "sha256": "%s"\n}\n' % (json.dumps(comment), json.dumps(source_of(table)), sha256_hex(raw))
    json.loads(text)
    return text


def _raw_fixture(what: str, name: str, raw: bytes) -> str:
    comment = ("ORIGINAL BYTES of the %s, written by the importer from your copy of the game. Not committed (.gitignore); "
               "the committed hash is in ../%s. See docs/port/FIDELITY.md." % (what, name))
    text = '{\n "comment": %s,\n "hex": "%s"\n}\n' % (json.dumps(comment), raw.hex())
    json.loads(text)
    return text


def build_trigger_hash_fixture() -> str:
    return _hash_fixture("trigger table (problem type per slot, educational level and pick)", TRIGGER_TABLE, trigger_table(),
                         "test_trigger_table_fidelity.gd", "TriggerTable.encode()", "trigger_table.json")


def build_trigger_raw_fixture() -> str:
    return _raw_fixture("trigger table", "trigger_table.json", trigger_table())


def build_zones_hash_fixture() -> str:
    return _hash_fixture("default educational levels of the zones", DEFAULT_EDU, default_edu_levels(),
                         "test_zone_fidelity.gd", "ZoneTable.encode_default_edu_levels()", "zones.json")


def build_zones_raw_fixture() -> str:
    return _raw_fixture("default educational levels of the zones", "zones.json", default_edu_levels())
