"""Store the label names and comments of some sectors' .foe files, so a later import or reset brings them back.

    uv run tools/import/harvest_foe_annotations.py 3 7      # sectors 3 and 7
    uv run tools/import/harvest_foe_annotations.py --all    # all 32 sectors

The creature scripts in the legacy pack's data/sectors/sector_NN/sector_NN.foe are generated from the original bytes, and a designer then
renames labels and writes comments in them by hand. Those additions are kept in godot/data/sectors/foe_annotations.json
(foe_annotations.py explains the format), keyed by sector and ORIGINAL byte offset. This tool reads each named .foe,
works out the offset of every label and instruction line, and writes what differs from the generated text into that
file, replacing the sector's earlier entry. It also
  - rewrites the .foe in the standard layout if the layout differs (the text must equal what the disassembler
    writes from the store, which is what godot/tests/engine/test_foe_asm.gd checks), and
  - patches the start_label / hit_label / ink_label of sector_NN.tres to follow renamed entry labels.
Only ORIGINAL sectors (those in godot/tests/fixtures/foe_scripts.json) can be harvested, and the original script bytes the importer
wrote (godot/tests/fixtures/original/foe_scripts.json, hash-checked: "run the importer on your copy" without them) are what
the text is compared with; the .foe of a
sector the designers made (sector_32 and up) is its own source, nothing regenerates it, and naming one is an error.
A sector whose instructions are not the original's (a deliberate change, see DELIBERATE_SCRIPT_CHANGES in
test_foe_asm.gd), that has two labels at one place or lost a creature's entry label, is REFUSED with the reason and
left alone; the exit status is then 1. The Foe Script screen has the same command as a button ("Store names &
comments"). Manual: docs/create/FOE_SCRIPTING.md ("Names and comments").
"""
from __future__ import annotations

import argparse
from pathlib import Path

import common
import foe_annotations
import foe_names
import foe_text
import reset_foe_scripts as reset


def harvest_sector(n: int, entry: dict, store: dict[int, dict], sector_dir: Path = reset.SECTOR_DIR) -> str:
    """Harvests sector `n` into `store` (changed in place), fixes the .foe layout and the .tres labels.
    Returns "" or the reason it was refused (then nothing was changed)."""
    foe_path = common.sector_file(n, "foe", sector_dir)
    offsets = [(f["pc"], f["script_hit"], f["script_ink"]) for f in entry["foes"]]
    result = foe_annotations.harvest(foe_path.read_text(encoding="utf-8"), bytes.fromhex(entry["script_hex"]),
                                     entry["base"], foe_text.entry_names(offsets), foe_names.Names.for_original_sector(n))
    if not result.ok:
        return result.problem
    annotations = result.annotations()
    if foe_annotations.is_empty(annotations):
        store.pop(n, None)
    else:
        store[n] = annotations
    if foe_path.read_text(encoding="utf-8") != result.text:
        foe_path.write_bytes(result.text.encode("utf-8"))
    tres_path = foe_path.with_suffix(".tres")
    old = tres_path.read_text()
    new = reset.patch_text(old, entry, annotations)
    if new != old:
        tres_path.write_text(new)
    return ""


def run(sectors: list[int], sector_dir: Path = reset.SECTOR_DIR, raw: Path = reset.foe_script.RAW_FIXTURE,
        hashes: Path = reset.foe_script.HASH_FIXTURE, store_path: Path = foe_annotations.STORE) -> bool:
    """Harvests the sectors and saves the store. True when none was refused."""
    entries = {e["index"]: e for e in reset.load_originals(raw, hashes)}
    store = foe_annotations.load(store_path)
    all_ok = True
    for n in sectors:
        if n not in entries:
            all_ok = False
            print("  sector %2d: REFUSED, nothing changed: %s" % (n, reset.refuse_new_sectors([n], hashes)))
            continue
        before = store.get(n)
        problem = harvest_sector(n, entries[n], store, sector_dir)
        if problem:
            all_ok = False
            print("  sector %2d: REFUSED, nothing changed: %s" % (n, problem))
        else:
            labels = len(store.get(n, {}).get("labels", {}))
            comments = len(store.get(n, {}).get("comments", {}))
            print("  sector %2d: %d label names, %d commented places%s" % (
                n, labels, comments, "" if store.get(n) != before else " (unchanged)"))
    foe_annotations.save(store, store_path)
    return all_ok


def main() -> None:
    parser = argparse.ArgumentParser(description="Store the label names and comments of .foe files (see the module docstring).")
    parser.add_argument("sectors", nargs="*", type=int, help="sector numbers (of the original sectors)")
    parser.add_argument("--all", action="store_true", help="harvest every sector")
    args = parser.parse_args()
    if args.all == bool(args.sectors):
        parser.error("name some sectors, or give --all (not both)")
    chosen = reset.original_sectors() if args.all else sorted(set(args.sectors))
    problem = reset.refuse_new_sectors(chosen)
    if problem:
        parser.error(problem)
    try:
        ok = run(chosen)
    except ValueError as error:
        parser.error(str(error))
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
