"""Reset screens of the original sectors back to the ORIGINAL.

    uv run tools/import/reset_screens.py --all          # all 384 screens
    uv run tools/import/reset_screens.py 3 7            # every screen of sectors 3 and 7
    uv run tools/import/reset_screens.py 3:5 12:0       # screen 5 of sector 3 and screen 0 of sector 12

A screen's file the legacy pack's data/sectors/sector_NN/screen_MM.tres is the stored version designers edit (the screen
editor, docs/create/SCREEN_EDITOR.md, or the Inspector). This tool is the way back to the original. It rebuilds
exactly those files from the original records with screen_record.py, the same code that step_sectors.py uses to create
them, and leaves everything else alone: sector_NN.tres is not read or written (it only points at the screen files), and
neither is anything outside the legacy pack's data/sectors/sector_NN/. It needs neither extracted/ nor the rest of the importer.

The original records are the importer's, not the repository's (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"):
`import_all.py` writes them from YOUR copy of the game to the git-ignored godot/tests/fixtures/original/screens.json. Without
that file the tool says to run the importer. Each record must hash to the SHA-256 committed in
godot/tests/fixtures/screens.json, or the tool refuses: your copy is a different version or patched.

Not the same as `import_all.py --only sectors`, which rewrites the WHOLE sector files from extracted/.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import screen_record
from common import ORIGINAL_SECTOR_COUNT, SCREENS, refuse_new_sectors


def load_originals(raw: Path = screen_record.RAW_FIXTURE, hashes: Path = screen_record.HASH_FIXTURE) -> dict[tuple[int, int], bytes]:
    """(sector, screen) -> the original 0x500-byte record, hash-checked (screen_record.load_originals)."""
    return screen_record.load_originals(raw, hashes)


def parse_target(text: str) -> list[tuple[int, int]]:
    """"3" -> every screen of sector 3, "3:5" -> that one screen."""
    sector_text, _, screen_text = text.partition(":")
    try:
        sector = int(sector_text)
        screens = [int(screen_text)] if screen_text else list(range(SCREENS))
    except ValueError:
        raise ValueError("'%s' is not a sector number or sector:screen" % text) from None
    problem = refuse_new_sectors([sector], "original screens")
    if problem:
        raise ValueError(problem)
    for m in screens:
        if not 0 <= m < SCREENS:
            raise ValueError("screen %d does not exist (0-%d)" % (m, SCREENS - 1))
    return [(sector, m) for m in screens]


def reset_screen(path: Path, sector: int, screen: int, record: bytes) -> bool:
    """Writes the original screen_MM.tres at `path`. True if the file changed (or did not exist)."""
    text = screen_record.build_screen_from_record(record, sector, screen).encode("utf-8")
    if path.exists() and path.read_bytes() == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text)
    return True


def run(targets: list[tuple[int, int]], sector_dir: Path | None = None, raw: Path = screen_record.RAW_FIXTURE,
        hashes: Path = screen_record.HASH_FIXTURE) -> None:
    problem = refuse_new_sectors(sorted({sector for sector, _screen in targets}), "original screens")
    if problem:
        raise ValueError(problem)
    records = load_originals(raw, hashes)
    for sector, screen in targets:
        if (sector, screen) not in records:
            raise ValueError("sector %d screen %d is not in %s" % (sector, screen, raw))
        path = screen_record.screen_path(sector, screen)
        if sector_dir is not None:                       # tests write into a temporary folder
            path = sector_dir / path.parent.name / path.name
        changed = reset_screen(path, sector, screen, records[(sector, screen)])
        print("  sector %2d screen %2d: %s" % (sector, screen, "reset to the original" if changed else "already original, unchanged"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Reset screens to the original (see the module docstring).")
    parser.add_argument("targets", nargs="*", help="sector numbers (all 12 screens) or sector:screen")
    parser.add_argument("--all", action="store_true", help="reset every screen of every original sector")
    args = parser.parse_args()
    if args.all == bool(args.targets):
        parser.error("name some sectors or sector:screen pairs, or give --all (not both)")
    try:
        if args.all:
            chosen = [(s, m) for s in range(ORIGINAL_SECTOR_COUNT) for m in range(SCREENS)]
        else:
            chosen = sorted({t for text in args.targets for t in parse_target(text)})
        run(chosen)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
