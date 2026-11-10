"""Reset the creature scripts of some sectors back to the ORIGINAL.

    uv run tools/import/reset_foe_scripts.py 3 7        # sectors 3 and 7
    uv run tools/import/reset_foe_scripts.py --all      # all 32 sectors
    uv run tools/import/reset_foe_scripts.py 3 --plain  # sector 3 as generated, without the stored names and comments
    uv run tools/import/reset_foe_scripts.py 3 --records  # also the creatures' 34-byte record fields (see below)

The script text in the legacy pack's data/sectors/sector_NN/sector_NN.foe, plus the start_label / hit_label / ink_label of every FoeData in
sector_NN.tres, are the stored version of the creature scripts; designers edit them in Godot (script editor / Inspector)
or any text editor. This tool is the way back to the original. It rebuilds exactly those from the original bytes
with foe_text.py: it rewrites the .foe file and patches ONLY the label lines into the existing .tres. Every other byte of
the .tres stays as it is, so the rest of the sector, the uids and the ordering are untouched. It needs neither extracted/
nor the rest of the importer.

The original script bytes are the importer's, not the repository's (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"):
`import_all.py` writes them from YOUR copy of the game to the git-ignored godot/tests/fixtures/original/foe_scripts.json
(foe_script.py). Without that file the tool says to run the importer. Each script must hash to the SHA-256 committed in
godot/tests/fixtures/foe_scripts.json, or the tool refuses: your copy is a different version or patched.

The designers' label names and comments (godot/data/sectors/foe_annotations.json, foe_annotations.py) are part of
the reset: the text is written WITH them, and the labels in the .tres follow the renamed labels. What goes back to
the original is the instructions, i.e. the code. `--plain` ignores the store and writes the fully generated text
(foe0_hit, loc_529, no comments); the store file itself is not touched.
Manual: docs/create/FOE_SCRIPTING.md ("Resetting a script to the original").

`--records` also puts back the fields of every creature's 34-byte record: dormant, hidden, screen, pos, frame, flip,
frame_min, frame_max, damage and runtime_state. They sit in the same FoeData sub-resources as the labels, and the three
entry points of a record ARE those labels (offsets into the script), so this is the one tool that knows a creature as a
whole. The original records come from godot/tests/fixtures/original/foe_records.json, which the importer writes from YOUR copy
of the game (git-ignored): without it the tool says "run the importer on your copy of the game". Each original must hash to
the SHA-256 committed in godot/tests/fixtures/foe_records.json, and the file written is read back: the record fields
it holds, with the entry points of the script fixture, must encode to bytes with the committed hash. (The entry points are not
re-assembled here: that is the GDScript test's job, tests/legacy/test_foe_record_fidelity.gd.) It refuses a sector that has a
different number of creatures than the original: adding or removing a creature is not a reset of its record.
The sector header (start, neighbours, pieces) has its own tool, reset_sector_header.py.

Not the same as `import_all.py --only sectors`, which rewrites the WHOLE sector files from extracted/.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import foe_annotations
import foe_names
import foe_record
import foe_text
import tres
import foe_script
from common import PACK_DATA, RUN_THE_IMPORTER, sector_file, sha256_hex

SECTOR_DIR = PACK_DATA / "sectors"

LABEL_FIELDS = ("start_label", "hit_label", "ink_label")
# The record fields kept in the FoeData sub-resource, in the importer's order (labels follow, runtime_state is last).
RECORD_FIELDS = ("dormant", "hidden", "screen", "pos", "frame", "flip", "frame_min", "frame_max", "damage")
RUNTIME_STATE = "runtime_state"
HOW_TO_FIX = RUN_THE_IMPORTER


def load_originals(raw: Path = foe_script.RAW_FIXTURE, hashes: Path = foe_script.HASH_FIXTURE) -> list[dict]:
    """Per original sector its script bytes (hex), base and creature offsets, hash-checked (foe_script.load_originals)."""
    return foe_script.load_originals(raw, hashes)


def original_sectors(hashes: Path = foe_script.HASH_FIXTURE) -> list[int]:
    """The sector numbers that have an ORIGINAL script (an entry in the committed hash fixture). A sector the designers made
    themselves (sector_32 and up) has none: its .foe is its only source, and the tools here never touch it."""
    return foe_script.original_sectors(hashes)


def refuse_new_sectors(sectors: list[int], hashes: Path = foe_script.HASH_FIXTURE) -> str:
    """"" when every sector has an original, else the message that says which have not."""
    new = [n for n in sectors if n not in original_sectors(hashes)]
    if not new:
        return ""
    return ("sector%s %s ha%s no original script: a new sector's .foe file is its own source, so there is nothing "
            "to reset or harvest" % ("s" if len(new) > 1 else "", ", ".join(map(str, new)), "ve" if len(new) > 1 else "s"))


def original_fields(entry: dict, annotations: dict | None = None) -> tuple[str, list[tuple[str, str, str]]]:
    """(script text, per creature (start, hit, ink) labels) of one fixture entry, with one sector's `annotations`
    (names and comments of foe_annotations.py; None for the plain generated text). The operands are written with the
    names of godot/names/original.json for this sector (foe_names.py)."""
    offsets = [(f["pc"], f["script_hit"], f["script_ink"]) for f in entry["foes"]]
    text = foe_text.disassemble(bytes.fromhex(entry["script_hex"]), entry["base"], foe_text.entry_names(offsets),
                                annotations, foe_names.Names.for_original_sector(entry["index"]))
    return text, foe_text.entry_labels(offsets, (annotations or {}).get("labels"))


def patch_text(tres_text: str, entry: dict, annotations: dict | None = None) -> str:
    """The .tres text with the label fields replaced by the original (or renamed) ones; all else kept."""
    _source, labels = original_fields(entry, annotations)
    for k, field in enumerate(LABEL_FIELDS):
        pattern = re.compile(r'^%s = ".*"$' % field, re.MULTILINE)
        if len(pattern.findall(tres_text)) != len(labels):
            raise ValueError("expected %d %s lines (one per creature)" % (len(labels), field))
        values = iter(label[k] for label in labels)
        tres_text = pattern.sub(lambda _m, f=field, v=values: "%s = %s" % (f, tres.s(next(v))), tres_text)
    return tres_text


def load_original_records(raw_fixture: Path = foe_record.RAW_FIXTURE,
                          hash_fixture: Path = foe_record.HASH_FIXTURE) -> dict[int, list[tuple[bytes, str]]]:
    """sector -> per creature (the original 34 bytes, their committed SHA-256). Refuses with the importer hint when the bytes
    are missing, and when one does not hash to the committed value (a different release or a patched copy)."""
    if not raw_fixture.exists():
        raise ValueError("%s is missing. It holds the original creature records and is written by the importer from your "
                         "copy of the game: %s." % (raw_fixture, HOW_TO_FIX))
    if not hash_fixture.exists():
        raise ValueError("%s is missing (it is committed): restore it with git." % hash_fixture)
    hashes = {e["index"]: [f["sha256"] for f in e["foes"]] for e in json.loads(hash_fixture.read_text())["sectors"]}
    out = {}
    for entry in json.loads(raw_fixture.read_text())["sectors"]:
        records = [bytes.fromhex(h) for h in entry["records_hex"]]
        expected = hashes.get(entry["index"], [])
        if [sha256_hex(r) for r in records] != expected:
            raise ValueError("sector %d: the creature records in %s do not match the SHA-256 committed in %s. Your copy of the "
                             "game is a different version or patched, or the file was edited: %s."
                             % (entry["index"], raw_fixture.name, hash_fixture.name, HOW_TO_FIX))
        out[entry["index"]] = list(zip(records, expected))
    return out


def _foe_ids(blocks: list[str]) -> list[str]:
    lines = blocks[-1].split("\n")
    at = tres.property_line(lines, "foes")
    return re.findall(r'SubResource\("([^"]+)"\)', lines[at]) if at is not None else []


def patch_records_text(tres_text: str, records: list[bytes]) -> str:
    """The .tres text with the record fields of every FoeData replaced by the original `records`; the labels and all else
    are kept (patch_text handles the labels)."""
    blocks = tres.split_blocks(tres_text)
    ids = _foe_ids(blocks)
    if len(ids) != len(records):
        raise ValueError("the sector has %d creatures, the original %d: adding or removing a creature is not undone by a "
                         "record reset" % (len(ids), len(records)))
    index = {tres.sub_resource_id(b): k for k, b in enumerate(blocks) if tres.sub_resource_id(b)}
    for sub_id, raw in zip(ids, records):
        r = foe_record.decode_record(raw)
        lines = blocks[index[sub_id]].split("\n")
        owned = set(RECORD_FIELDS) | {RUNTIME_STATE}
        script = [l for l in lines[1:] if l.startswith("script = ")]
        rest = [l for l in lines[1:] if not l.startswith("script = ") and l.split(" = ", 1)[0] not in owned]
        fields = [("dormant", tres.b(r["dormant"])), ("hidden", tres.b(r["hidden"])), ("screen", str(r["screen"])),
                  ("pos", tres.vec2i(*r["pos"])), ("frame", str(r["frame"])), ("flip", tres.b(r["flip"])),
                  ("frame_min", str(r["frame_min"])), ("frame_max", str(r["frame_max"])), ("damage", str(r["damage"]))]
        state = [(RUNTIME_STATE, tres.packed_bytes(r["runtime_state"]))] if any(r["runtime_state"]) else []
        blocks[index[sub_id]] = "\n".join([lines[0]] + script + ["%s = %s" % kv for kv in fields] + rest
                                          + ["%s = %s" % kv for kv in state])
    return tres.join_blocks(blocks)


def record_hashes(tres_text: str, entry: dict) -> list[str]:
    """SHA-256 of the 34 bytes each creature of the .tres text encodes to: its record fields as stored, with the entry points
    (labels in the file) taken from the script fixture `entry`."""
    blocks = tres.split_blocks(tres_text)
    index = {tres.sub_resource_id(b): b for b in blocks if tres.sub_resource_id(b)}
    out = []
    for sub_id, foe in zip(_foe_ids(blocks), entry["foes"]):
        v = tres.property_values(index[sub_id].split("\n"))
        state = bytes(tres.ints_in(v[RUNTIME_STATE])) if RUNTIME_STATE in v else bytes(foe_record.RUNTIME_STATE_SIZE)
        record = {"dormant": v.get("dormant") == "true", "hidden": v.get("hidden") == "true",
                  "screen": int(v.get("screen", "0")), "pos": tuple(tres.ints_in(v.get("pos", "Vector2i(0, 0)"))),
                  "frame": int(v.get("frame", "0")), "flip": v.get("flip") == "true",
                  "frame_min": int(v.get("frame_min", "0")), "frame_max": int(v.get("frame_max", "0")),
                  "damage": int(v.get("damage", "0")), "script_hit": foe["script_hit"], "script_ink": foe["script_ink"],
                  "pc": foe["pc"], "runtime_state": state}
        out.append(sha256_hex(foe_record.encode_record(record)))
    return out


def reset_sector(path: Path, entry: dict, annotations: dict | None = None,
                 records: list[tuple[bytes, str]] | None = None) -> bool:
    """Reset one sector in place: `path` is its .tres, the script is the .foe beside it. True if anything changed.
    `records`: the original (bytes, SHA-256) of every creature, to reset the record fields too."""
    source, _labels = original_fields(entry, annotations)
    foe_path = path.with_suffix(".foe")
    foe_bytes = source.encode("utf-8")
    changed = not foe_path.exists() or foe_path.read_bytes() != foe_bytes
    if changed:
        foe_path.write_bytes(foe_bytes)
    old = path.read_text()
    new = patch_text(old, entry, annotations)
    if records is not None:
        new = patch_records_text(new, [raw for raw, _hash in records])
        if record_hashes(new, entry) != [h for _raw, h in records]:
            raise ValueError("%s: the patched records do not encode to the committed hashes; nothing written" % path)
    if new != old:
        path.write_text(new)
        changed = True
        if records is not None and record_hashes(path.read_text(), entry) != [h for _raw, h in records]:
            raise ValueError("%s: the file written does not encode to the committed record hashes" % path)
    return changed


def run(sectors: list[int], sector_dir: Path = SECTOR_DIR, raw: Path = foe_script.RAW_FIXTURE,
        hashes: Path = foe_script.HASH_FIXTURE, store_path: Path = foe_annotations.STORE, plain: bool = False, records: bool = False,
        record_raw: Path = foe_record.RAW_FIXTURE, record_hash_fixture: Path = foe_record.HASH_FIXTURE) -> None:
    problem = refuse_new_sectors(sectors, hashes)
    if problem:
        raise ValueError(problem)
    entries = {e["index"]: e for e in load_originals(raw, hashes)}
    store = {} if plain else foe_annotations.load(store_path)
    originals = load_original_records(record_raw, record_hash_fixture) if records else {}
    for n in sectors:
        path = sector_file(n, "tres", sector_dir)
        annotations = foe_annotations.for_sector(store, n)
        changed = reset_sector(path, entries[n], annotations, originals[n] if records else None)
        kept = "" if foe_annotations.is_empty(annotations) else " (with the stored names and comments)"
        kept += " and the records (hash checked)" if records else ""
        print("  sector %2d: %s%s" % (n, "reset to the original" if changed else "already original, unchanged", kept))


def main() -> None:
    parser = argparse.ArgumentParser(description="Reset creature scripts to the original (see the module docstring).")
    parser.add_argument("sectors", nargs="*", type=int, help="sector numbers (of the original sectors)")
    parser.add_argument("--all", action="store_true", help="reset every sector")
    parser.add_argument("--plain", action="store_true",
                        help="ignore the stored label names and comments (foe_annotations.json): fully generated text")
    parser.add_argument("--records", action="store_true",
                        help="also reset the creatures' record fields (position, frame, damage ...); needs the original "
                             "bytes written by the importer")
    args = parser.parse_args()
    if args.all == bool(args.sectors):
        parser.error("name some sectors, or give --all (not both)")
    chosen = original_sectors() if args.all else sorted(set(args.sectors))
    problem = refuse_new_sectors(chosen)
    if problem:
        parser.error(problem)
    try:
        run(chosen, plain=args.plain, records=args.records)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
