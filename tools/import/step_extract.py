"""The first two steps of the importer: the CD image -> `extracted/` ("extract"), and the tables read from the game's files ->
`docs/data/` ("tables"). Both read NEPTUNE.ISO through tools/gamefiles.py, so a clean checkout plus the user's ISO is enough.

"extract" runs the extractors of tools/extract/ (pictures, sounds and MIDI, text and data resources, contact sheets) into
`extracted/`, which is ignored by version control. It leaves out `extract_previews.py`: that is the promotional content of other
titles, and nothing is made from it.

"tables" runs the four exporters that dump the game's own data tables to the JSON the other steps and tools read: `export_json.py`
(the 32 sectors with their creatures and scripts, the problem tables as raw bytes, the trigger table, the default levels),
`decode_problems.py` (the problems' records, decoded with the layouts of `problem_layouts32.json`), `export_gfx_tbl.py` (which art
bundle a problem type draws) and `map_names.py` (the publics of ONWIN.MAP, which the Ghidra name tables refer to). Their output is the game's content, so it is ignored by version control too (.gitignore); the JSON that
the reverse engineering produced by hand or with Ghidra (layouts, tick tables, struct layouts) stays committed in `docs/data/`.

Each script is run with the interpreter that runs the importer (the project's environment has everything they import), so
`uv run tools/import/import_all.py` is all there is to it. Both steps rewrite their files with the same bytes every time.
"""
from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

from common import DOCS_DATA, EXTRACTED, ROOT

EXTRACTORS = ["extract_images.py", "extract_sounds.py", "extract_data.py", "make_sheets.py"]


def _run(script: Path, *args: str | Path) -> None:
    started = time.time()
    done = subprocess.run([sys.executable, str(script), *map(str, args)], cwd=ROOT, capture_output=True, text=True, check=False)
    if done.returncode != 0:
        sys.stderr.write(done.stdout + done.stderr)
        raise SystemExit("%s failed (exit code %d)" % (script.name, done.returncode))
    print("  %s (%.0f s)" % (script.name, time.time() - started))


def run_extract() -> None:
    for name in EXTRACTORS:
        _run(ROOT / "tools" / "extract" / name, EXTRACTED)


def run_tables() -> None:
    DOCS_DATA.mkdir(parents=True, exist_ok=True)
    _run(ROOT / "tools" / "analysis" / "export_json.py", DOCS_DATA)
    _run(ROOT / "tools" / "analysis" / "decode_problems.py", DOCS_DATA / "problem_records.json")
    _run(ROOT / "tools" / "analysis" / "export_gfx_tbl.py")
    _run(ROOT / "tools" / "analysis" / "ghidra" / "map_names.py", "write", DOCS_DATA / "onwin_map.json")
