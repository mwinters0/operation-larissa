"""Step 'campaigns': the original's two games as `Campaign` resources (godot/data/campaigns/voyager.tres, expert.tres).

A `Campaign` (godot/src/resources/campaign.gd, docs/engine/ARCHITECTURE.md) is the data that makes one game different from another: its sectors
and finale, its educational levels, its canister log and supply messages. For the two games of the original every number comes from the
program, so the files are written here and nowhere else:

    unlock order of the log   docs/data/databank.json            LogUnlockOrderVoyager 0x4419d5, LogUnlockOrderExpert 0x4419e4
    default levels            docs/data/zone_defaults.json       DS 0x25A8, bytes game * 5 + zone (ds_tables.py; the same bytes as zones.tres)
    names of the strings      godot/names/original.json          the `text` name of each string number (the log entries 10648-10677, the
                                                                 supply messages 10678-10707, the game names 11199 / 11200, the buttons 11258 / 11259)

The structure (sectors 0-14 and 15-29, finales 30 and 31, the log of a finale, the closing scene) is the program's too: `GetGameLevel`
0x42e12c, `IncrementSector` 0x42e0b2, `PrepareCanisterLog` 0x41e787. A campaign of a designer's own is a file next to these that this step
does not touch. The step is among the ones `rename_name.py --import` runs, because the files hold registry names.
"""
from __future__ import annotations

from pathlib import Path

import ds_tables
import step_story
import tres
from common import PACK_DATA, DOCS_DATA, load_json, out_text

SCRIPT = "res://src/resources/campaign.gd"
SECTORS_PER_GAME = 15
LOG_ENTRY_FIRST_TEXT = 10648         # the 30 canister log entries, ENTRY 1.01 .. 2.15 (strings 10648-10677)
SUPPLY_MESSAGE_FIRST_TEXT = 10678    # the 30 mission control messages, one per sector 0-29 (strings 10678-10707)
CAMPAIGNS = (
    # id, the game's name (string 11199 / 11200), its "new game" button (11258 / 11259), first sector, finale sector, how many entries the
    # finale's log lists (the EXE computes `sector % 15 + 1` for every sector, so sector 30 lists 1 and sector 31 lists 2), the closing scene
    {"id": "voyager", "title": 11199, "button": 11258, "first": 0, "finale": 30, "finale_log": 1, "closing": "voyager"},
    {"id": "expert", "title": 11200, "button": 11259, "first": 15, "finale": 31, "finale_log": 2, "closing": "expert"},
)


def _names(numbers: list[int]) -> str:
    return tres.array("StringName", ['&"%s"' % step_story.text_name(n) for n in numbers])


def build_campaign(game: int) -> str:
    """The text of data/campaigns/<id>.tres for game 0 (Voyager) or 1 (Expert)."""
    c = CAMPAIGNS[game]
    unlock = load_json(DOCS_DATA / "databank.json")["unlock_order_voyager" if game == 0 else "unlock_order_expert"]
    edu = ds_tables.default_edu_levels()
    sectors = list(range(c["first"], c["first"] + SECTORS_PER_GAME))
    first_entry = game * SECTORS_PER_GAME
    name = c["id"].capitalize()
    t = tres.Tres("Resource", "Campaign", SCRIPT)
    t.set("provenance", tres.s(
        "ORIGINAL: the %s game of ONWIN32.EXE. Sectors %d-%d and finale %d (GetGameLevel 0x42e12c, IncrementSector 0x42e0b2); "
        "default_edu_levels = bytes %d-%d of the table at DS 0x25A8 (= zones.tres); log_unlock_order = LogUnlockOrder%s 0x%s "
        "(PrepareCanisterLog 0x41e787, docs/data/databank.json); texts: the log entries and supply messages of NEP.DLL by registry name; "
        "song: SelectSectorMusic 0x43200f; closing: Game.show_closing. Written by tools/import/step_campaigns.py."
        % (name, sectors[0], sectors[-1], c["finale"], 5 * game, 5 * game + 4, name, ("4419d5", "4419e4")[game])))
    t.set("id", '&"%s"' % c["id"])
    t.set("title_text", '&"%s"' % step_story.text_name(c["title"]))
    t.set("new_game_text", '&"%s"' % step_story.text_name(c["button"]))
    t.set("banner_index", str(game))
    t.set("sectors", tres.packed_ints(sectors))
    t.set("finales", tres.packed_ints([c["finale"]]))
    t.set("default_edu_levels", tres.packed_ints(edu[5 * game:5 * game + 5]))
    t.set("log_series", str(game + 1))
    t.set("log_unlock_order", tres.packed_ints(unlock))
    t.set("finale_log_counts", tres.packed_ints([c["finale_log"]]))
    t.set("log_texts", _names([LOG_ENTRY_FIRST_TEXT + first_entry + i for i in range(SECTORS_PER_GAME)]))
    t.set("log_voices", tres.array("StringName", ['&"log_%d"' % (first_entry + i) for i in range(SECTORS_PER_GAME)]))
    t.set("supply_texts", _names([SUPPLY_MESSAGE_FIRST_TEXT + n for n in sectors]))
    t.set("supply_voices", tres.array("StringName", ['&"supply_%d"' % n for n in sectors]))
    t.set("fallback_song", '&"sector_song_1"')
    t.set("closing_scene", '&"%s"' % c["closing"])
    return t.render()


def owned_files() -> list[Path]:
    """The campaign files this step generates: the original's two. Nothing else in godot/data/campaigns/ is the importer's (a campaign of
    a designer's own is its own source), so `import_all.py --clean` deletes exactly these."""
    return [PACK_DATA / "campaigns" / (c["id"] + ".tres") for c in CAMPAIGNS]


def run() -> None:
    for game, c in enumerate(CAMPAIGNS):
        out_text(PACK_DATA / "campaigns" / (c["id"] + ".tres"), build_campaign(game))
    print("  campaigns: %s" % ", ".join(c["id"] for c in CAMPAIGNS))
