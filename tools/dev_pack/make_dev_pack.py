"""Makes the dev pack, godot/packs/dev: the developers' own pack: a data file for every data file of the legacy pack and a picture for every picture key of its table, with values of its own.

    uv run tools/dev_pack/make_dev_pack.py                      # everything (pictures, data, and audio when audio.py is there)
    uv run tools/dev_pack/make_dev_pack.py --only pictures,data
    uv run tools/dev_pack/make_dev_pack.py --refresh-inventory  # rebuild inventory.json from the legacy pack's file names (needs legacy)

Then let Godot import the pictures: `tools/godot.sh --headless --path godot --import`. See tools/dev_pack/README.md.
"""
from __future__ import annotations

import argparse
import importlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import devlib
import picture_table as picture_table_module
from devlib import DEV, write_text

import dev_pictures
import inventory

STAGES = ("pictures", "data", "audio")

PACK_JSON = {"id": "dev", "title": "Dev pack", "version": "1", "format": 1,
             "description": "The developers' own pack: coloured shapes with their asset name written on them, speech that says its own "
                            "name, sounds that say \"bang\". Complete, and not meant for play. Copy it to start a game of your own."}


def picture_table() -> dict:
    """dev's `pictures.json`: a row to the file of each key of the inventory (`assets/pictures/<kind>/<name>.png`) and an alias row for each alias."""
    inv = inventory.load()
    rows: dict = {key: dev_pictures.rel_of(key) for key in inv["pictures"]}
    rows.update({key: {"alias": target} for key, target in inv["picture_aliases"].items()})
    return rows


def pictures() -> None:
    inv = inventory.load()
    n = dev_pictures.write_all(list(inv["pictures"]))
    wanted = {dev_pictures.rel_of(key) for key in inv["pictures"]}
    for stale in sorted(p for p in (DEV / "assets" / "pictures").rglob("*") if p.is_file()):          # (a key that is not in the inventory any more)
        rel = stale.relative_to(DEV).as_posix()
        if rel.removesuffix(".import") not in wanted:
            stale.unlink()
    write_text(DEV / picture_table_module.FILE, picture_table_module.render(picture_table()))
    print("  pictures: %d, aliases: %d" % (n, len(inv["picture_aliases"])))


def data() -> None:
    import dev_problems
    import dev_rules
    import dev_sectors
    import dev_sprites
    import dev_story
    import dev_tables
    import dev_tiles
    import dev_ui
    import test_sectors
    write_text(DEV / "pack.json", json.dumps(PACK_JSON, indent=2) + "\n")
    counts = {"sprites": dev_sprites.write_all(), "tiles": dev_tiles.write_all(), "tables": dev_tables.write_all(), "ui": dev_ui.write_all(), "story": dev_story.write_all(),
              "problems": dev_problems.write_all(), "rules": dev_rules.write_all(), "sectors and campaign": dev_sectors.write_all(), "test sectors": test_sectors.write_all(DEV)}
    print("  data: " + ", ".join("%s %d" % kv for kv in counts.items()))


def audio() -> None:
    if not (devlib.HERE / "audio.py").exists():
        print("  audio: tools/dev_pack/audio.py is not there (it is made by the audio work item): skipped")
        return
    module = importlib.import_module("audio")
    module.build(DEV)


def missing_files() -> list[str]:
    """Files of the inventory that the pack does not have (the audio ones only when the audio builder has run): its data files, its pictures, its table."""
    inv = inventory.load()
    wanted = list(inv["files"]) + [dev_pictures.rel_of(key) for key in inv["pictures"]] + [picture_table_module.FILE]
    return [f for f in wanted if not (DEV / f).exists()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="comma-separated stages to run: " + ", ".join(STAGES))
    parser.add_argument("--refresh-inventory", action="store_true", help="rebuild inventory.json from the legacy pack's file names and exit")
    args = parser.parse_args(argv)
    if args.refresh_inventory:
        if not devlib.LEGACY.exists():
            print("the legacy pack is not there (%s): nothing to read the file names from" % devlib.LEGACY)
            return 1
        inv = inventory.refresh()
        print("inventory.json: %d files, %d audio files" % (len(inv["files"]), len(inv["audio"])))
        return 0
    chosen = args.only.split(",") if args.only else list(STAGES)
    unknown = [s for s in chosen if s not in STAGES]
    if unknown:
        print("unknown stage %s (stages: %s)" % (", ".join(unknown), ", ".join(STAGES)))
        return 2
    for stage in STAGES:
        if stage in chosen:
            print("stage %s" % stage)
            globals()[stage]()
    lost = missing_files()
    print("files written: %d, unchanged: %d" % (devlib.Stats.written, devlib.Stats.unchanged))
    if lost:
        print("MISSING from the inventory: %d, for example %s" % (len(lost), lost[0]))
        return 1
    print("every file of the inventory is there")
    return 0


if __name__ == "__main__":
    sys.exit(main())
