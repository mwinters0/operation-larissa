"""One-off exporter: problem type -> panel-art bundle (GFX_TBL at DS 0x227A in ONWIN.EXE).

The import pipeline (tools/import) does not read the game's files itself, so this tiny analysis
script reads the table (from ONWINCD/ONWIN.EXE on the CD, NEPTUNE.ISO) and stores it in extracted/tables/problem_gfx_bundles.json, which is not
committed (it is the game's table): the importer's "tables" step (tools/import/step_extract.py) runs it, after the "extract" step.

Run:  uv run tools/analysis/export_gfx_tbl.py
"""
import json, struct, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.append(str(ROOT / "tools" / "import"))   # common.py: where extracted/ and its tables/ are
import gamefiles
from common import EXTRACTED, TABLES
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else TABLES   # the importer passes common.TABLES
exe = gamefiles.read("ONWINCD/ONWIN.EXE")
DS = 0x3C200
logical = list(struct.unpack_from("<34H", exe, DS + 0x227A))
rm = (EXTRACTED / "data/ONWIN_exe_resources/OTHR_15001.bin").read_bytes()
n = len(rm) // 2
rmap = struct.unpack("<%dH" % n, rm[: 2 * n])
real = [rmap[x] if x < n else x - 20000 for x in logical]
out = {
    "note": "Per problem type 0-33: logical id from GFX_TBL and the real id. "
            "real < 900 is a bundle (BNDL) id, real >= 1000 is a single bitmap id.",
    "gfx_logical": logical,
    "gfx_real": real,
}
OUT.mkdir(parents=True, exist_ok=True)
dest = OUT / "problem_gfx_bundles.json"
dest.write_text(json.dumps(out, indent=1) + "\n", newline="\n")
print("wrote", dest, real)
