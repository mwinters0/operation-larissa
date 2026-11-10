"""A sector's creature script: the original bytecode and where the creatures enter it, plus the fixtures that guard them.

Teaches: the "hashes committed, bytes not" fixture form of sector_header.py and foe_record.py (docs/port/FIDELITY.md, "Fixtures
commit hashes, not bytes"), for the script of one sector as one record: the committed godot/tests/fixtures/foe_scripts.json
keeps provenance and one SHA-256 of the whole script, never of an instruction or an operand; the original bytecode and the
creatures' entry points go to the git-ignored godot/tests/fixtures/original/foe_scripts.json. godot/tests/engine/test_foe_asm.gd
checks that the stored script text assembles to bytes with the committed hash; the tests that disassemble the original,
tools/import/reset_foe_scripts.py and the Foe Script screen's "Store names & comments" read the bytes.

A sector's foe buffer (DESIGN 3.5) is `u8 count`, then `count` 34-byte records (foe_record.py), then the script bytecode;
the script starts at buffer offset `base` = 1 + 34 * count. Everything is read from the RAW foe buffer (the extracted NEP.DLL
resource named in sectors.json under foes.source), the same bytes the records come from.
"""
from __future__ import annotations

import json

import foe_record
from common import DIFFERENT_VERSION, GODOT, ORIGINAL_FIXTURES, RUN_THE_IMPORTER, sha256_hex

# The committed fixture: provenance + hashes. The written-by-the-importer one holds the script bytes.
HASH_FIXTURE = GODOT / "tests" / "fixtures" / "foe_scripts.json"
RAW_FIXTURE = ORIGINAL_FIXTURES / "foe_scripts.json"


def script_of(sec: dict) -> tuple[int, bytes]:
    """(base, bytes): the script is the bytecode behind the records, up to the end of the extracted buffer (the extractor cuts
    trailing zero bytes, which are padding of the resource)."""
    base = sec["foes"]["script_base"]
    buffer = foe_record.original_buffer(sec)
    assert base == foe_record.record_offset(buffer[0]), "sector %d: the script does not follow the records" % sec["index"]
    return base, buffer[base:]


def offsets_of(sec: dict) -> list[tuple[int, int, int]]:
    """Per creature (pc, script_hit, script_ink): buffer offsets, exactly as in the original record (read from the raw
    foe buffer, foe_record.py)."""
    return [(r["pc"], r["script_hit"], r["script_ink"]) for r in foe_record.decode_records(sec)]


def build_hash_fixture(sectors: list[dict]) -> str:
    """The COMMITTED fixture godot/tests/fixtures/foe_scripts.json: per sector the provenance of its foe buffer, the offset and size
    of its script in it and the SHA-256 of the whole script. No original bytes in it."""
    comment = ("Provenance and SHA-256 hashes of every sector's ORIGINAL creature script, written by tools/import/step_sectors.py "
               "(import_all.py) from the raw foe buffer named under \"source\" (NEP.DLL, saved by tools/extract/extract_data.py from "
               "your copy of the game), never hand-edited. It holds no original bytes: the script of a sector is the \"size\" bytes "
               "at \"offset\" of its buffer (behind the count byte and the 34-byte creature records; the extractor cuts the trailing "
               "zeros), \"sha256\" the hash of the whole script. godot/tests/engine/test_foe_asm.gd checks that the stored script text "
               "assembles to bytes with this hash. The bytes themselves, with the creatures' entry points, are written to the "
               "git-ignored tests/fixtures/original/foe_scripts.json by the same importer run, for the tests that disassemble the "
               "original and for tools/import/reset_foe_scripts.py. See docs/port/FIDELITY.md, \"Fixtures commit hashes, not bytes\".")
    out = ["{", ' "comment": %s,' % json.dumps(comment), ' "sectors": [']
    rows = []
    for sec in sectors:
        base, script = script_of(sec)
        rows.append('  {"index": %d, "source": %s, "offset": %d, "size": %d,\n   "sha256": "%s"}'
                    % (sec["index"], json.dumps(sec["foes"]["source"]), base, len(script), sha256_hex(script)))
    out.append(",\n".join(rows))
    out += [" ]", "}"]
    text = "\n".join(out) + "\n"
    json.loads(text)                       # must stay valid JSON
    return text


def build_raw_fixture(sectors: list[dict]) -> str:
    """The NOT committed file godot/tests/fixtures/original/foe_scripts.json: per sector the original script bytes (hex), their
    base and every creature's offsets. Rebuilt from YOUR copy."""
    comment = ("ORIGINAL BYTES of every creature script, written by the importer from your copy of the game. Not committed "
               "(.gitignore); the committed hashes are in ../foe_scripts.json. godot/tests/engine/test_foe_asm.gd and "
               "tools/import/reset_foe_scripts.py read it. See docs/port/FIDELITY.md.")
    out = ["{", ' "comment": %s,' % json.dumps(comment), ' "sectors": [']
    for n, sec in enumerate(sectors):
        base, script = script_of(sec)
        out.append('  {"index": %d, "base": %d,' % (sec["index"], base))
        out.append('   "script_hex": "%s",' % script.hex())
        out.append('   "foes": [')
        out.append(",\n".join('    {"pc": %d, "script_hit": %d, "script_ink": %d}' % offs for offs in offsets_of(sec)))
        out.append("   ]}" + ("," if n < len(sectors) - 1 else ""))
    out += [" ]", "}"]
    text = "\n".join(out) + "\n"
    json.loads(text)
    return text


def load_originals(raw_fixture=RAW_FIXTURE, hash_fixture=HASH_FIXTURE) -> list[dict]:
    """Per sector {"index", "base", "script_hex", "foes": [{"pc", "script_hit", "script_ink"}]}, read from the importer's raw file
    and checked against the committed hashes. Raises ValueError with the importer hint when the raw file is missing, and when a
    script does not hash to the committed value (a different release or a patched copy, or an edited file)."""
    if not raw_fixture.exists():
        raise ValueError("%s is missing. It holds the original creature scripts and is written by the importer from your copy of "
                         "the game: %s." % (raw_fixture, RUN_THE_IMPORTER))
    if not hash_fixture.exists():
        raise ValueError("%s is missing (it is committed): restore it with git." % hash_fixture)
    committed = {e["index"]: e for e in json.loads(hash_fixture.read_text())["sectors"]}
    entries = json.loads(raw_fixture.read_text())["sectors"]
    for entry in entries:
        want = committed.get(entry["index"])
        script = bytes.fromhex(entry["script_hex"])
        if want is None or sha256_hex(script) != want["sha256"] or entry["base"] != want["offset"] or len(script) != want["size"]:
            raise ValueError("sector %d: the script in %s does not match the SHA-256 committed in %s. %s, or the file was "
                             "edited: %s." % (entry["index"], raw_fixture.name, hash_fixture.name, DIFFERENT_VERSION.capitalize(),
                                              RUN_THE_IMPORTER))
    if {e["index"] for e in entries} != set(committed):
        raise ValueError("%s does not hold the same sectors as %s: %s." % (raw_fixture.name, hash_fixture.name, RUN_THE_IMPORTER))
    return entries


def original_sectors(hash_fixture=HASH_FIXTURE) -> list[int]:
    """The sector numbers that have an ORIGINAL script (an entry in the committed fixture; no raw bytes needed). A sector the
    designers made themselves (sector_32 and up) has none: its .foe is its only source."""
    return sorted(e["index"] for e in json.loads(hash_fixture.read_text())["sectors"])
