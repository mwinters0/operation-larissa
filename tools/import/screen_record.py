"""One screen of a sector: the original 0x500-byte record <-> the screen_MM.tres text.

Teaches: reading a binary record layout in Python (counts, then fixed-size entries), and keeping one function
as the only place that turns a record into a Godot resource, so the importer (step_sectors.py) and the reset
tool (reset_screens.py) cannot disagree.

The record layout is DESIGN 4.1 (the screen starts at 0x72 + k * 0x500 of a sector's data):
    tiles      38 x 18 bytes
    5 lists    each: u8 count, then count entries
               bg decos / mid decos / fg decos   3 bytes: x/4, y/2, slot | 0x80 (mirrored)
               anim decos                        22 bytes: x/4, y/2, w/4, h/2, start cursor, frames + 1 ... 0, then 1s
               math triggers                     4 bytes: x/4, y/2, trigger slot, flags
    the rest, up to 0x500, is not used by the game.

What the 384 original records show (checked here, so a surprise is an error and not silently dropped):
    * the unused rest is zero except in 7 records, which keep stale bytes of an earlier, longer version of the
      lists (DESIGN 4.1). They are kept as `stale_offset` / `stale_bytes` so the record can be rebuilt exactly.
    * an anim deco's frame list is followed by a 0 and then 1s up to the 22 bytes, in all 355 records.
    * a trigger's flags only use bits 7 (armed), 5 (re-arm on enter) and the low nibble. Bits 6 and 4 are never set
      in the original, but nobody knows what they would mean, so they are stored (`other_bits`) when set.

Where a record comes from (provenance, kept machine-readable): sector S is NEP.DLL logical resource
SECTOR_TBL[S], saved by tools/extract/extract_data.py as extracted/data/NEP_raw/NEP_<real id>.bin; screen k is
the 0x500 bytes at offset HEADER_SIZE + k * RECORD_SIZE of it. docs/data/sectors.json carries both ("source",
"record_offset") and the record itself ("record_hex"), exported from the game's files by tools/analysis/export_json.py.

The fixtures that guard the records (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"): the committed
godot/tests/fixtures/screens.json holds provenance and one SHA-256 per whole record, the original bytes go to the git-ignored
godot/tests/fixtures/original/screens.json. godot/tests/legacy/test_screen_fidelity.gd compares the hashes; reset_screens.py and the
screen editor read the bytes.
"""
from __future__ import annotations

import json

import tres
from common import (DIFFERENT_VERSION, EXTRACTED, GODOT, ORIGINAL_FIXTURES, RUN_THE_IMPORTER, res_path, sector_dir,
                    sha256_hex)

SCRIPTS = "res://src/resources/"
RECORD_SIZE = 0x500
HEADER_SIZE = 0x72                     # a sector's data: this header, then 12 screen records
SECTOR_SIZE = 0x3E00                   # size of the resource (15872); the 12 records end at 0x3C72, the rest is zero
TILE_COUNT = 38 * 18
ANIM_SIZE = 22
ANIM_FRAME_BYTES = ANIM_SIZE - 5       # 17: the list, its 0 terminator and the 1s after it
# (list name in the record, entry size)
LISTS = (("bg_decos", 3), ("mid_decos", 3), ("fg_decos", 3), ("anim_decos", ANIM_SIZE), ("math_triggers", 4))
UNUSED_FILLER = 1                      # what follows an anim deco's 0 terminator in the original


# The committed fixture: provenance + hashes. The written-by-the-importer one holds the record bytes.
HASH_FIXTURE = GODOT / "tests" / "fixtures" / "screens.json"
RAW_FIXTURE = ORIGINAL_FIXTURES / "screens.json"


def screen_path(sector: int, screen: int):
    """the legacy pack's data/sectors/sector_NN/screen_MM.tres"""
    return sector_dir(sector) / ("screen_%02d.tres" % screen)


def screen_res_path(sector: int, screen: int) -> str:
    return res_path(screen_path(sector, screen))


def record_offset(screen: int) -> int:
    """Offset of screen `screen`'s record inside its sector's data (DESIGN 4.1)."""
    return HEADER_SIZE + screen * RECORD_SIZE


def original_record(sec: dict, screen: int) -> bytes:
    """The 0x500 original bytes of screen `screen` of the sector dict from docs/data/sectors.json.

    Read from the extracted copy of the game's resource (sec["source"]["extracted"], the raw bytes) when it is
    there, else from "record_hex" in sectors.json; if both are there they must agree, so the decoded export can
    never drift from the original file. (The extracted file may lack the trailing zero bytes of the resource.)
    """
    sc = sec["screens"][screen]
    from_json = record_from_hex(sc["record_hex"])
    assert sc["record_offset"] == record_offset(screen)
    raw_file = EXTRACTED / sec["source"]["extracted"]
    if raw_file.exists():
        data = raw_file.read_bytes().ljust(SECTOR_SIZE, b"\0")
        from_file = data[record_offset(screen):record_offset(screen) + RECORD_SIZE]
        assert from_file == from_json, "sector %d screen %d: sectors.json and %s disagree" % (sec["index"], screen, raw_file)
        return from_file
    return from_json


def record_from_hex(record_hex: str) -> bytes:
    """The fixture / sectors.json keep the record without its trailing zeros; this pads it back to 0x500."""
    raw = bytes.fromhex(record_hex)
    assert len(raw) <= RECORD_SIZE
    return raw.ljust(RECORD_SIZE, b"\0")


def decode_record(raw: bytes) -> dict:
    """The record as plain Python data: tiles, the five lists (decos as (x, y, id), anim decos as the 22 bytes,
    triggers as (x, y, slot, flags)), `used` (end of the lists) and the stale bytes after it."""
    assert len(raw) == RECORD_SIZE
    out: dict = {"tiles": list(raw[:TILE_COUNT])}
    p = TILE_COUNT
    for name, size in LISTS:
        n = raw[p]
        entries = [bytes(raw[p + 1 + size * j:p + 1 + size * (j + 1)]) for j in range(n)]
        out[name] = entries if name == "anim_decos" else [tuple(e) for e in entries]
        p += 1 + n * size
    assert p <= RECORD_SIZE, "lists run past the end of the record"
    out["used"] = p
    nonzero = [j for j in range(p, RECORD_SIZE) if raw[j]]
    out["stale_offset"] = nonzero[0] if nonzero else 0
    out["stale_bytes"] = bytes(raw[nonzero[0]:nonzero[-1] + 1]) if nonzero else b""
    return out


def _decos(t: tres.Tres, ids: dict, lst) -> str:
    subs = []
    for x, y, ident in lst:
        subs.append(t.sub("Resource", [("pos", tres.vec2i(x * 4, y * 2)), ("slot", str(ident & 0x7F)),
                                       ("flag", tres.b(bool(ident & 0x80)))],
                          script=SCRIPTS + "deco_placement.gd", prefix="Deco"))
    return tres.array('ExtResource("%s")' % ids["deco_placement"], subs)


def _anim(t: tres.Tres, raw: bytes) -> str:
    # [0]=x/4  [1]=y/2  [2]=width/4  [3]=height/2 (largest frame)  [4]=start cursor
    # [5..]=frame list ended by a 0, then 1s. The list stores slot+1 (0 is the terminator, so slots are 1-based
    # here), unlike the static deco lists which store the plain slot (DESIGN 4.1).
    frames = []
    pos = 5
    while raw[pos] != 0:
        assert raw[pos] < 0x80, "anim deco frame with bit 7 set: not in the original data"
        frames.append(raw[pos] - 1)
        pos += 1
    assert all(v == UNUSED_FILLER for v in raw[pos + 1:]), "anim deco filler is not 1s: not in the original data"
    return t.sub("Resource", [("pos", tres.vec2i(raw[0] * 4, raw[1] * 2)),
                              ("frames", tres.packed_ints(frames)),
                              ("size", tres.vec2i(raw[2] * 4, raw[3] * 2)),
                              ("start_cursor", str(raw[4]))],
                 script=SCRIPTS + "anim_deco_data.gd", prefix="Anim")


def _trigger(t: tres.Tres, x: int, y: int, slot: int, flags: int) -> str:
    props = [("pos", tres.vec2i(x * 4, y * 2)), ("slot", str(slot)),
             ("armed", tres.b(bool(flags & 0x80))),
             ("rearm_on_enter", tres.b(bool(flags & 0x20))),
             ("test_nibble", str(flags & 0x0F))]
    if flags & 0x50:                               # never in the original; kept if a game copy has them
        props.append(("other_bits", str(flags & 0x50)))
    return t.sub("Resource", props, script=SCRIPTS + "math_trigger_data.gd", prefix="Trigger")


def build_screen(screen: dict, sector: int, index: int) -> str:
    """Text of screen `index` of sector `sector` (screen_MM.tres) from `decode_record`'s dict."""
    t = tres.Tres("Resource", "ScreenData", SCRIPTS + "screen_data.gd")
    ids = {n: t.ext_id("Script", SCRIPTS + n + ".gd") for n in ("deco_placement", "anim_deco_data", "math_trigger_data")}
    lists = {
        "bg_decos": _decos(t, ids, screen["bg_decos"]),
        "mid_decos": _decos(t, ids, screen["mid_decos"]),
        "fg_decos": _decos(t, ids, screen["fg_decos"]),
    }
    anims = [_anim(t, raw) for raw in screen["anim_decos"]]
    trigs = [_trigger(t, *e) for e in screen["math_triggers"]]
    t.set("original_sector", str(sector))          # provenance: which original record this screen was made from
    t.set("original_screen", str(index))
    t.set("tiles", tres.packed_bytes(screen["tiles"]))
    for name in ("bg_decos", "mid_decos", "fg_decos"):
        t.set(name, lists[name])
    t.set("anim_decos", tres.array('ExtResource("%s")' % ids["anim_deco_data"], anims))
    t.set("triggers", tres.array('ExtResource("%s")' % ids["math_trigger_data"], trigs))
    if screen["stale_bytes"]:                      # only the 7 records that have them
        t.set("stale_offset", str(screen["stale_offset"]))
        t.set("stale_bytes", tres.packed_bytes(screen["stale_bytes"]))
    return t.render()


def build_screen_from_hex(record_hex: str, sector: int, index: int) -> str:
    return build_screen(decode_record(record_from_hex(record_hex)), sector, index)


def build_screen_from_record(record: bytes, sector: int, index: int) -> str:
    return build_screen(decode_record(record), sector, index)


def build_hash_fixture(sectors: list[dict]) -> str:
    """The COMMITTED fixture godot/tests/fixtures/screens.json: per sector its provenance (the raw resource it comes from) and,
    per screen, the offset of its record and the SHA-256 of the whole 0x500 bytes. No original bytes in it."""
    comment = ("Provenance and SHA-256 hashes of the ORIGINAL 0x500-byte record of every screen, written by "
               "tools/import/step_sectors.py (import_all.py) from the raw sector resource named under \"source\" (NEP.DLL, saved by "
               "tools/extract/extract_data.py from your copy of the game), never hand-edited. It holds no original bytes: screen k "
               "is the \"size\" bytes at \"offset\" = 0x72 + k * 0x500 of the sector's resource, \"sha256\" the hash of the whole "
               "record (the resource padded with zeros to its 0x3E00 bytes, as sector_header.py does). "
               "godot/tests/legacy/test_screen_fidelity.gd checks that ScreenData.encode() hashes to these. The record bytes themselves "
               "are written to the git-ignored tests/fixtures/original/screens.json by the same importer run, for first-difference "
               "messages, tools/import/reset_screens.py and the screen editor. See docs/port/FIDELITY.md, \"Fixtures commit hashes, not bytes\".")
    out = ["{", ' "comment": %s,' % json.dumps(comment), ' "size": %d,' % RECORD_SIZE, ' "sectors": [']
    rows = []
    for sec in sectors:
        screens = ",\n".join('   {"screen": %d, "offset": %d, "sha256": "%s"}'
                             % (k, record_offset(k), sha256_hex(original_record(sec, k))) for k in range(len(sec["screens"])))
        rows.append('  {"index": %d, "source": %s, "screens": [\n%s\n  ]}' % (sec["index"], json.dumps(sec["source"]), screens))
    out.append(",\n".join(rows))
    out += [" ]", "}"]
    text = "\n".join(out) + "\n"
    json.loads(text)                       # must stay valid JSON
    return text


def build_raw_fixture(sectors: list[dict]) -> str:
    """The NOT committed file godot/tests/fixtures/original/screens.json: the original record of every screen as hex (without
    its trailing zero bytes), for first-difference messages, reset_screens.py and the screen editor. Rebuilt from YOUR copy."""
    comment = ("ORIGINAL BYTES of every screen record (hex, cut after the last non-zero byte; the rest of the 0x500 bytes is zero), "
               "written by the importer from your copy of the game. Not committed (.gitignore); the committed hashes are in "
               "../screens.json. See docs/port/FIDELITY.md.")
    out = ["{", ' "comment": %s,' % json.dumps(comment), ' "sectors": [']
    rows = []
    for sec in sectors:
        screens = ",\n".join('   {"screen": %d, "offset": %d, "record_hex": "%s"}'
                             % (k, record_offset(k), original_record(sec, k).rstrip(b"\0").hex()) for k in range(len(sec["screens"])))
        rows.append('  {"index": %d, "screens": [\n%s\n  ]}' % (sec["index"], screens))
    out.append(",\n".join(rows))
    out += [" ]", "}"]
    text = "\n".join(out) + "\n"
    json.loads(text)
    return text


def load_originals(raw_fixture=RAW_FIXTURE, hash_fixture=HASH_FIXTURE) -> dict[tuple[int, int], bytes]:
    """(sector, screen) -> the original 0x500 bytes, read from the importer's raw file and checked against the committed hashes.
    Raises ValueError with the importer hint when the raw file is missing, and when a record does not hash to the committed
    value (a different release or a patched copy, or an edited file)."""
    if not raw_fixture.exists():
        raise ValueError("%s is missing. It holds the original screens and is written by the importer from your copy of the "
                         "game: %s." % (raw_fixture, RUN_THE_IMPORTER))
    if not hash_fixture.exists():
        raise ValueError("%s is missing (it is committed): restore it with git." % hash_fixture)
    hashes = {(e["index"], s["screen"]): s["sha256"] for e in json.loads(hash_fixture.read_text())["sectors"] for s in e["screens"]}
    out = {}
    for entry in json.loads(raw_fixture.read_text())["sectors"]:
        for row in entry["screens"]:
            key = (entry["index"], row["screen"])
            record = record_from_hex(row["record_hex"])
            if hashes.get(key) != sha256_hex(record):
                raise ValueError("sector %d screen %d: the record in %s does not match the SHA-256 committed in %s. %s, or the "
                                 "file was edited: %s." % (key + (raw_fixture.name, hash_fixture.name, DIFFERENT_VERSION.capitalize(),
                                                                RUN_THE_IMPORTER)))
            out[key] = record
    if set(out) != set(hashes):
        raise ValueError("%s does not hold the same screens as %s: %s." % (raw_fixture.name, hash_fixture.name, RUN_THE_IMPORTER))
    return out
