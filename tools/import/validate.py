"""Cross-checks on the generated tree (no Godot needed). `run()` returns a list of problems."""
from __future__ import annotations

import re

from PIL import Image

from asset_names import foe_file, problem_art_folder_file, ui_file
from common import (ASSETS, COMMON_CREATURES, COMMON_DECOS, ANALYSIS_DATA, TABLES, FOE_ZONE_BASE, INK_FRAMES,
                    ORIGINAL_SECTOR_COUNT, PACK_DATA, PROJECT_DATA, ZONE_DECO_COUNTS, ZONE_FOE_COUNTS, file_of_res, load_json, raw_table, sector_file)
from step_sectors import sector_zone
from sprite_meta import ZONE_META_IDS


def run() -> list[str]:
    bad: list[str] = []

    # 376 backgrounds
    n = len(list((ASSETS / "backgrounds").glob("bg_s*_*.png")))
    if n != 376:
        bad.append("expected 376 backgrounds, found %d" % n)

    sectors = load_json(TABLES / "sectors.json")
    for sec in sectors:
        i = sec["index"]
        z = sector_zone(i)
        art = min(z, 4)
        max_deco = COMMON_DECOS + ZONE_DECO_COUNTS[art]
        max_frame = FOE_ZONE_BASE + ZONE_FOE_COUNTS[z]
        for k, sc in enumerate(sec["screens"]):
            if len(sc["tiles"]) != 684:
                bad.append("sector %d screen %d: %d tiles" % (i, k, len(sc["tiles"])))
            for v in sc["tiles"]:
                if v & 0x40 and v & 0x80:
                    bad.append("sector %d screen %d: tile byte with both 0x40 and 0x80" % (i, k))
                    break
            for lst in ("bg_decos", "mid_decos", "fg_decos"):
                for x, y, ident in sc[lst]:
                    if (ident & 0x7F) >= max_deco:
                        bad.append("sector %d screen %d: deco %d >= %d" % (i, k, ident & 0x7F, max_deco))
        for r in sec["foes"]["records"]:
            if r["frame"] >= max_frame:
                bad.append("sector %d: foe frame %d >= %d" % (i, r["frame"], max_frame))
        for side, lst in sec["nbr"].items():
            if len(lst) != 12 or any(not 0 <= v <= 12 for v in lst):
                bad.append("sector %d: bad %s neighbours" % (i, side))

    # sub sprite-cell tables of the project's tuning file: 9 cells, targets in range, pictures within bundle 15's 8 sub pictures
    sub = load_json(PROJECT_DATA / "rules" / "tuning.json")["sub"]
    for name in ("left", "right", "down", "up", "level"):
        table = sub["cell_after_" + name]
        if len(table) != 9 or any(not 0 <= v <= 8 for v in table):
            bad.append("sub cell table '%s' must have 9 entries in 0..8" % name)
    if len(sub["cell_pictures"]) != 18 or any(not 0 <= v <= 7 for v in sub["cell_pictures"]):
        bad.append("sub cell_pictures must have 18 entries in 0..7")

    # SpriteFrames / tileset / problem files only reference files that exist
    for tres_file in [*PROJECT_DATA.rglob("*.tres"), *PACK_DATA.rglob("*.tres")]:
        for path in re.findall(r'path="(res://[^"]+)"', tres_file.read_text()):
            if not file_of_res(path).exists():
                bad.append("%s references missing %s" % (tres_file.name, path))

    # sprite meta sizes equal PNG sizes
    # Known quirk: the height table says 32 px for the three 80x16 pictures 1175-1177
    # (common slots 14-16); the picture itself is 16 px high. Listed in
    # docs/port/ASSET_FORMATS.md ("Known quirks of the data"), not treated as an error.
    known = {("common", 14), ("common", 15), ("common", 16)}

    def check_sizes(width_id, height_id, count, files, label):
        w, h = raw_table(width_id), raw_table(height_id)
        for k in range(count):
            size = Image.open(files[k]).size
            if size != (w[k] * 2, h[k] * 2) and (label, k) not in known:
                bad.append("%s slot %d: table %s vs png %s" % (label, k, (w[k] * 2, h[k] * 2), size))

    check_sizes(10018, 10019, COMMON_CREATURES, [foe_file(0, k) for k in range(COMMON_CREATURES)], "common")
    check_sizes(10015, 10016, INK_FRAMES, [foe_file(0, 28 + k) for k in range(INK_FRAMES)], "ink")
    for zone, (wid, hid, _) in enumerate(ZONE_META_IDS):
        cnt = ZONE_FOE_COUNTS[zone]
        check_sizes(wid, hid, cnt, [foe_file(zone, FOE_ZONE_BASE + k) for k in range(cnt)],
                    "zone%d" % zone)

    # tile pictures 1..61 are non-empty in every zone atlas
    for z in range(5):
        atlas = Image.open(ASSETS / "tiles" / ("zone%d_tiles.png" % z)).convert("RGBA")
        for k in range(1, 62):
            cell = atlas.crop(((k % 8) * 16, (k // 8) * 16, (k % 8) * 16 + 16, (k // 8) * 16 + 16))
            if cell.getbbox() is None:
                bad.append("zone %d tile %d is empty" % (z, k))

    # problem types: >= 1 prompt, 34 files
    for t in range(34):
        f = PACK_DATA / "problems" / ("problem_type_%02d.tres" % t)
        if not f.exists():
            bad.append("missing " + f.name)
        elif not re.search(r'^texts = PackedStringArray\("', f.read_text(), re.MULTILINE):
            bad.append("%s has no texts" % f.name)

    # counts of generated files
    # (the ORIGINAL sectors' files: a sector the designers made lives in the same folder and is not counted)
    missing = [i for i in range(ORIGINAL_SECTOR_COUNT) if not sector_file(i, "tres").exists()]
    if missing:
        bad.append("missing the sector files of the original sectors %s" % ", ".join(map(str, missing)))
    expect = {"music": (ASSETS / "audio" / "music", "*.ogg", 10),
              "adlib music": (ASSETS / "audio" / "music" / "adlib", "*.ogg", 10),
              "sfx": (ASSETS / "audio" / "sfx", "*.wav", 52), "voice": (ASSETS / "audio" / "voice", "*.wav", 371)}
    for label, (folder, pattern, count) in expect.items():
        found = len(list(folder.glob(pattern)))
        if found != count:
            bad.append("expected %d %s files, found %d" % (count, label, found))
    # sub console and calculator layouts (step 'console'): every key and icon lies inside its picture
    console = load_json(ANALYSIS_DATA / "console_layout.json")
    calc = console["calculator"]
    cx, cy = calc["picture"]["xy"]
    cw, ch = Image.open(problem_art_folder_file("b041", 1781)).size
    for k in calc["keys"]:
        x, y, w, h = k["rect"]
        if not (cx <= x and cy <= y and x + w <= cx + cw and y + h <= cy + ch):
            bad.append("calculator key %s lies outside the calculator picture" % k["key"])
    gauges = load_json(TABLES / "hud_gauges.json")
    bx, by = gauges["bezel_background"]["xy"]
    bw, bh = Image.open(ui_file("hud", 1189)).size
    points = [(x, gauges["tanks"]["y"]) for x in gauges["tanks"]["x"]] + [tuple(p) for p in gauges["ink_pellets"]["xy"]]
    for x, y in points:
        if not (bx <= x and by <= y and x < bx + bw and y < by + bh):
            bad.append("HUD icon at (%d, %d) lies outside the bezel picture" % (x, y))

    return bad
