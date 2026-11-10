"""Dev sectors and campaigns, and how to add one.

A sector is a `SectorSpec`: a header (zone, start, neighbours, pieces), twelve `ScreenSpec`s (tiles, decorations, math triggers), its
creatures and their script text. `write_sector(spec)` writes `data/sectors/sector_NN/` of the dev pack (sector_NN.tres, sector_NN.foe and
screen_00..11.tres) in the format the importer and the screen editor use. `standard_sector(index, zone)` makes a small playable one;
a test sector (100 and up, made for one engine test) starts from it and changes what its test needs: see tools/dev_pack/README.md.

Positions are WINDOW pixels (the playfield is the 608 x 288 rectangle at (16, 32); a tile is 16 x 16). Tile bytes: 0 empty, 0x40 | picture
a wall, 0x80 | strength << 3 | direction a current (direction 0-7: NW N NE W E SW S SE, as in the currents atlas).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import devlib
from devlib import DEV, SCRIPTS, write_text, tres

COLUMNS, ROWS, SCREENS = 38, 18, 12
PLAYFIELD = (16, 32)
FLOOR = 0x71                                 # wall picture 0x31
LEDGE = 0x72
NW, N, NE, W, E, SW, S, SE = range(8)


def wall(picture: int = 0x31) -> int:
    return 0x40 | picture


def current(direction: int, strength: int) -> int:
    return 0x80 | strength << 3 | direction


@dataclass
class Deco:
    x: int
    y: int
    slot: int
    mirrored: bool = False


@dataclass
class Trigger:
    x: int
    y: int
    slot: int
    nibble: int = 15
    armed: bool = True
    rearm: bool = False


@dataclass
class ScreenSpec:
    tiles: bytearray = field(default_factory=lambda: bytearray(COLUMNS * ROWS))
    bg: list[Deco] = field(default_factory=list)
    mid: list[Deco] = field(default_factory=list)
    fg: list[Deco] = field(default_factory=list)
    triggers: list[Trigger] = field(default_factory=list)

    def fill(self, col0: int, row0: int, col1: int, row1: int, tile: int) -> None:
        """Tile `tile` in the columns col0..col1 and rows row0..row1 (inclusive)."""
        for row in range(row0, row1 + 1):
            for col in range(col0, col1 + 1):
                self.tiles[row * COLUMNS + col] = tile

    def floor(self, rows: int = 2) -> None:
        self.fill(0, ROWS - rows, COLUMNS - 1, ROWS - 1, FLOOR)


@dataclass
class Foe:
    screen: int
    pos: tuple[int, int]
    frame: int
    frame_min: int
    frame_max: int
    damage: int = 1
    start: str = "patrol_start"
    hit: str = "patrol_hit"
    ink: str = "patrol_ink"
    flip: bool = False


@dataclass
class SectorSpec:
    index: int
    zone: int
    screens: list[ScreenSpec]
    pieces: list[tuple[int, int, int]]                    # (screen, x, y); piece 0 is the data canister
    foes: list[Foe] = field(default_factory=list)
    script: str = ""
    game: int = 0
    start_pos: tuple[int, int] = (96, 160)
    start_frame: int = 6
    left: list[int] = field(default_factory=lambda: [m - 1 for m in range(SCREENS)])                       # the destination screen or -1
    right: list[int] = field(default_factory=lambda: [m + 1 if m < SCREENS - 1 else -1 for m in range(SCREENS)])
    up: list[int] = field(default_factory=lambda: [-1] * SCREENS)
    down: list[int] = field(default_factory=lambda: [-1] * SCREENS)
    music: str = ""
    finale_screen: int = -1


def sector_dir(index: int) -> str:
    return "data/sectors/sector_%02d" % index


def screen_tres(spec: ScreenSpec) -> str:
    t = tres.Tres("Resource", "ScreenData", SCRIPTS + "screen_data.gd")
    ids = {n: t.ext_id("Script", SCRIPTS + n + ".gd") for n in ("deco_placement", "anim_deco_data", "math_trigger_data")}

    def decos(items: list[Deco]) -> str:
        subs = [t.sub("Resource", [("pos", tres.vec2i(d.x, d.y)), ("slot", str(d.slot)), ("flag", tres.b(d.mirrored))],
                      script=SCRIPTS + "deco_placement.gd", prefix="Deco") for d in items]
        return tres.array('ExtResource("%s")' % ids["deco_placement"], subs)

    lists = {name: decos(getattr(spec, name)) for name in ("bg", "mid", "fg")}
    triggers = [t.sub("Resource", [("pos", tres.vec2i(g.x, g.y)), ("slot", str(g.slot)), ("armed", tres.b(g.armed)),
                                   ("rearm_on_enter", tres.b(g.rearm)), ("test_nibble", str(g.nibble))],
                      script=SCRIPTS + "math_trigger_data.gd", prefix="Trigger") for g in spec.triggers]
    t.set("original_sector", "-1")                          # (the screen editor's own writer always names the provenance fields; -1: no original)
    t.set("original_screen", "-1")
    t.set("tiles", tres.packed_bytes(spec.tiles))
    t.set("bg_decos", lists["bg"])
    t.set("mid_decos", lists["mid"])
    t.set("fg_decos", lists["fg"])
    t.set("anim_decos", tres.array('ExtResource("%s")' % ids["anim_deco_data"], []))
    t.set("triggers", tres.array('ExtResource("%s")' % ids["math_trigger_data"], triggers))
    return t.render()


def sector_tres(spec: SectorSpec) -> str:
    folder = devlib.DEV_RES + sector_dir(spec.index)
    t = tres.Tres("Resource", "SectorData", SCRIPTS + "sector_data.gd")
    ids = {n: t.ext_id("Script", SCRIPTS + n + ".gd") for n in ("piece_data", "foe_data", "screen_data")}
    screen_refs = [t.ext_ref("Resource", "%s/screen_%02d.tres" % (folder, m)) for m in range(SCREENS)]
    pieces = [t.sub("Resource", [("screen", str(sc)), ("pos", tres.vec2i(x, y)), ("is_canister", tres.b(k == 0))],
                    script=SCRIPTS + "piece_data.gd", prefix="Piece") for k, (sc, x, y) in enumerate(spec.pieces)]
    foes = [t.sub("Resource", [("dormant", "false"), ("hidden", "false"), ("screen", str(f.screen)), ("pos", tres.vec2i(*f.pos)),
                               ("frame", str(f.frame)), ("flip", tres.b(f.flip)), ("frame_min", str(f.frame_min)),
                               ("frame_max", str(f.frame_max)), ("damage", str(f.damage)), ("start_label", tres.s(f.start)),
                               ("hit_label", tres.s(f.hit)), ("ink_label", tres.s(f.ink))],
                   script=SCRIPTS + "foe_data.gd", prefix="Foe") for f in spec.foes]
    t.set("index", str(spec.index))
    t.set("game", str(spec.game))
    t.set("zone", str(spec.zone))
    if spec.finale_screen >= 0:
        t.set("finale_screen", str(spec.finale_screen))
    t.set("start_pos", tres.vec2i(*spec.start_pos))
    t.set("start_frame", str(spec.start_frame))
    for side in ("left", "right", "up", "down"):
        t.set("neighbors_" + side, tres.packed_ints(getattr(spec, side)))
    t.set("pieces", tres.array('ExtResource("%s")' % ids["piece_data"], pieces))
    t.set("screens", tres.array('ExtResource("%s")' % ids["screen_data"], screen_refs))
    t.set("foes", tres.array('ExtResource("%s")' % ids["foe_data"], foes))
    t.set("foe_script", t.ext_ref("Resource", "%s/sector_%02d.foe" % (folder, spec.index)))
    t.set("foe_script_base", str(1 + 34 * len(spec.foes)))
    t.set("music_name", tres.s(spec.music))
    t.set("header_unused_3d", "0")
    t.set("header_unused_40", "0")
    t.set("header_unused_41", "0")
    return t.render()


def write_sector(spec: SectorSpec, root: Path | None = None) -> int:
    """Writes the sector's files below `root` (the pack's folder, default the dev pack); the number of files."""
    assert len(spec.screens) == SCREENS
    base = (DEV if root is None else root) / sector_dir(spec.index)
    write_text(base / ("sector_%02d.tres" % spec.index), sector_tres(spec))
    write_text(base / ("sector_%02d.foe" % spec.index), spec.script)
    for m, screen in enumerate(spec.screens):
        write_text(base / ("screen_%02d.tres" % m), screen_tres(screen))
    return 2 + SCREENS


# --- the dev creatures' script -------------------------------------------------------------------------------------------------

def patrol_script(index: int, first_frame: int, last_frame: int, comment: str = "") -> str:
    """The pacing creature of docs/create/FOE_SCRIPTING.md section 4: right and left, a sound when touched, frozen by ink."""
    return """; Dev pack - sector %02d. %s
; A creature that paces right and left; when the sub touches it a sound plays; an ink pellet freezes it for a moment.
; foe records name the three entry points: start_label patrol_start, hit_label patrol_hit, ink_label patrol_ink.

patrol_start:
    Set_Frame_Range %d %d
walk_right:
    Move_Foe_Relative_XY 2 0 1
    Loop_Counter0_Back_To walk_right 9
walk_left:
    Move_Foe_Relative_XY -2 0 1 mirrored
    Loop_Counter0_Back_To walk_left 9
    Jump_To patrol_start

patrol_hit:
    Play_Sound 3
    Return

patrol_ink:
    Set_Frame %d
ink_wait:
    Wait_Next_Tick
    Loop_Counter1_Back_To ink_wait 30
    Return
""" % (index, comment, first_frame, last_frame, first_frame)


NO_SCRIPT = ("; Dev pack - sector %02d has no creatures.\n; Every creature names three labels of this file (start, hit, ink): see docs/create/FOE_SCRIPTING.md.\n")


# --- a small playable sector ------------------------------------------------------------------------------------------------------

def standard_sector(index: int, zone: int, creatures: int = 1, finale: bool = False, comment: str = "") -> SectorSpec:
    """Twelve screens chained left to right, a floor of rock, the data canister (piece 0) on screen 3 and another piece on screen 8,
    decorations, a ledge, a current, two math triggers and `creatures` pacing creatures. The supply station (screen 0) and the end
    station (screen 11) are drawn by the game. Change what you need after calling it."""
    screens = [ScreenSpec() for _ in range(SCREENS)]
    for m, screen in enumerate(screens):
        screen.floor()
        screen.bg.append(Deco(96 + 16 * m, 256, 0))
        screen.bg.append(Deco(400, 248, 1, mirrored=bool(m % 2)))
    for m in (2, 5, 9):
        screens[m].fill(10, 11, 20, 11, LEDGE)                 # a ledge at y = 208 .. 223
    screens[6].fill(5, 7, 15, 8, current(E, 2))               # a current pushing right
    screens[5].triggers.append(Trigger(400, 240, 10))
    screens[9].triggers.append(Trigger(400, 240, 11))
    pieces = [(3, 320, 180), (8, 160, 230)]
    first = 35                                              # the zone's own creature pictures start at slot 35
    homes = [(4, (300, 250)), (7, (200, 250)), (10, (420, 250))]
    foes = [Foe(s, pos, first, first, first + 1) for s, pos in homes[:creatures]]
    spec = SectorSpec(index, zone, screens, pieces, foes, patrol_script(index, first, first + 1, comment) if foes else NO_SCRIPT % index,
                      music="esect%d" % (index % 6 + 1))
    return spec


def finale_sector(index: int, zone: int) -> SectorSpec:
    """The last sector of a campaign: the same, with three creatures and a trigger on every third screen."""
    spec = standard_sector(index, zone, creatures=3, finale=True, comment="The finale.")
    for m in (2, 8):
        spec.screens[m].triggers.append(Trigger(300, 240, 12 + m % 3))
    return spec


# --- campaigns ----------------------------------------------------------------------------------------------------------------

def campaign_tres(id: str, title: str, sectors: list[int], finales: list[int], edu: list[int], finale_text: str,
                  provenance: str = "Dev pack: a campaign of our own (tools/dev_pack/dev_sectors.py).", voiced: bool = False) -> str:
    """`voiced`: the log entries and supply messages are spoken, by the pack's voice groups `log_<k>` and `supply_<k>` (k from 0, in the campaign's order)."""
    entries = len(sectors)
    t = tres.Tres("Resource", "Campaign", SCRIPTS + "campaign.gd")
    names = lambda items: tres.array("StringName", ['&%s' % tres.s(x) for x in items])
    t.set("provenance", tres.s(provenance))
    t.set("id", '&"%s"' % id)
    t.set("title", tres.s(title))
    t.set("new_game_text", '&%s' % tres.s(title))
    t.set("banner_index", "0")
    t.set("sectors", tres.packed_ints(sectors))
    t.set("finales", tres.packed_ints(finales))
    t.set("default_edu_levels", tres.packed_ints(edu))
    t.set("log_series", "1")
    t.set("log_unlock_order", tres.packed_ints(list(range(1, entries + 1))))
    t.set("finale_log_counts", tres.packed_ints([entries] * len(finales)))
    t.set("log_texts", names("Dev log entry %d: the canister of sector %d." % (i + 1, s) for i, s in enumerate(sectors)))
    t.set("log_voices", names(("log_%d" % i if voiced else "") for i in range(len(sectors))))
    t.set("supply_texts", names("Dev mission control: sector %d is done." % s for s in sectors))
    t.set("supply_voices", names(("supply_%d" % i if voiced else "") for i in range(len(sectors))))
    t.set("fallback_song", '&"sector_song_1"')
    t.set("closing_scene", '&""')
    t.set("finale_text", tres.s(finale_text))
    t.set("finale_picture", tres.s("title_sky"))
    return t.render()


def dev_tour() -> tuple[list[SectorSpec], str]:
    sectors = [standard_sector(0, 0, comment="Zone 0, one creature."), standard_sector(1, 1, creatures=2, comment="Zone 1, two creatures."),
               standard_sector(2, 2, creatures=2, comment="Zone 2, two creatures."), standard_sector(3, 3, creatures=3, comment="Zone 3, three creatures."),
               finale_sector(4, 4)]
    text = campaign_tres("dev_tour", "Dev tour", [0, 1, 2, 3], [4], [0, 1, 1, 2, 2], "The dev tour is done. Nothing of the original is in this game.",
                         voiced=True)
    return sectors, text


def write_all() -> int:
    sectors, campaign = dev_tour()
    n = sum(write_sector(s) for s in sectors)
    write_text(DEV / "data" / "campaigns" / "dev_tour.tres", campaign)
    return n + 1
