"""Dev zones and trigger table: dev's own numbers, round and easy to read."""
from __future__ import annotations

import devlib
from devlib import DEV, SCRIPTS, write_text, tres

import common as importer
from asset_names import ui_file

ZONE_TITLES = ["Dev zone 0", "Dev zone 1", "Dev zone 2", "Dev zone 3", "Dev zone 4", "Dev finale A", "Dev finale B"]
EDU_VOYAGER = [0, 1, 1, 2, 2]               # the educational level (0-3) of each zone when the player did not customise the game
EDU_EXPERT = [1, 2, 2, 3, 3]
PROBLEM_TYPES = 34
SLOTS, LEVELS, PICKS = 63, 4, 2


def trigger_type(slot: int, level: int, pick: int) -> int:
    """The problem type a trigger slot asks for at a level: a rule anybody can check by hand."""
    return (slot + 3 * level + 17 * pick) % PROBLEM_TYPES


def zones_tres() -> str:
    t = tres.Tres("Resource", "ZoneTable", SCRIPTS + "zone_table.gd")
    zid = t.ext_id("Script", SCRIPTS + "zone_data.gd")
    zones = []
    for z in range(7):
        art = min(z, 4)
        props = [("index", str(z)), ("title", tres.s(ZONE_TITLES[z])), ("tile_zone", str(art)), ("tile_source_id", str(art)),
                 ("deco_count", str(importer.ZONE_DECO_COUNTS[art])), ("foe_count", str(importer.ZONE_FOE_COUNTS[z]))]
        if z < 5:                                              # the zone banners are the HUD pictures 1195-1199
            banner = ui_file("hud", importer.ZONE_BANNER_IDS[z]).relative_to(importer.LEGACY).as_posix()
            props.append(("banner_texture", devlib.tex(t, banner)))
        props.append(("default_edu_level_voyager", str(EDU_VOYAGER[art])))
        props.append(("default_edu_level_expert", str(EDU_EXPERT[art])))
        zones.append(t.sub("Resource", props, script=SCRIPTS + "zone_data.gd", prefix="Zone"))
    t.set("zones", tres.array('ExtResource("%s")' % zid, zones))
    return t.render()


def trigger_table_tres() -> str:
    t = tres.Tres("Resource", "TriggerTable", SCRIPTS + "trigger_table.gd")
    t.set("table", tres.packed_bytes(trigger_type(s, lv, p) for s in range(SLOTS) for lv in range(LEVELS) for p in range(PICKS)))
    return t.render()


def write_all() -> int:
    write_text(DEV / "data" / "zones.tres", zones_tres())
    write_text(DEV / "data" / "trigger_table.tres", trigger_table_tres())
    return 2
