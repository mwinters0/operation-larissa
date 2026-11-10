"""The names of the asset files: THE rule (docs/create/NAMES.md, "Asset file names"), written once for every kind.

A file of a NAMED entry of the registry (godot/names/original.json) is `<name>_<number>.<ext>`: the name says what it is and the
original's number, in decimal and without padding, says which resource of the game it is (`lock_tick_38.wav` is sound 38). An
entry nobody has named keeps the file name it always had, which already holds the number (`sfx_38.wav`, `ui_1039.png`, `esect1.ogg`).
When a name is given or changed (rename_name.py) the file moves: run the importer again (`import_all.py` prunes the old file, see
`asset_manifest.prune`).

    sound        audio/sfx/<name>_<n>.wav                         unnamed  sfx_%02d.wav
    voice        audio/voice/<name>_<id>.wav                               voice_<id>.wav
    music        audio/music/<name>_<id>.ogg, .../adlib/...                <midi stem>.ogg (esect1, bsect1)
    ui_picture   ui/<folder>/<name>_<id>.png                               ui_<id>.png
    problem_art  problem_art/<folder>/<name>_<id>.png                      pa_<id>.png
    frame        sprites/foes/<name>_<slot>.png                            foe_%03d.png                    (slots 0-34, common)
                 sprites/foes/foe_z<zone>_<name>_<slot>.png                foe_z<zone>_%03d.png            (slots 35+, the zone's own)
    deco         sprites/decos/<name>_<slot>.png                           deco_%03d.png                   (slots 0-69, common)
                 sprites/decos/deco_z<zone>_<name>_<slot>.png              deco_z<zone>_%03d.png           (slots 70+, the art zone's own)

The zone stays in the file name as a `foe_z<zone>_` / `deco_z<zone>_` prefix because a name belongs to a zone (slot 40 is a different
drawing in every zone) and the files of all zones share one folder. godot/src/core/assets.gd (`Assets.ui_picture_path`,
`problem_art_path`) is the GDScript twin for the two picture kinds that code resolves by path; the other kinds are reached through
the generated catalogs and SpriteFrames, which hold the paths this module makes.
"""
from __future__ import annotations

from pathlib import Path

from common import ASSETS, COMMON_DECOS, FOE_ZONE_BASE
from foe_names import NO_SCOPE, original

AUDIO = ASSETS / "audio"


def stem(kind: str, number: int, unnamed: str, scope: int = NO_SCOPE, prefix: str = "") -> str:
    """`<prefix><name>_<number>` when somebody named `number` (as a `kind`, in `scope`), else `unnamed`."""
    name = original().real_name(kind, number, scope)
    return "%s%s_%d" % (prefix, name, number) if name else unnamed


def named(kind: str, number: int, scope: int = NO_SCOPE) -> bool:
    return original().real_name(kind, number, scope) != ""


def sfx_file(n: int) -> Path:
    return AUDIO / "sfx" / (stem("sound", n, "sfx_%02d" % n) + ".wav")


def voice_file(vid: int) -> Path:
    return AUDIO / "voice" / (stem("voice", vid, "voice_%d" % vid) + ".wav")


def music_file(song_id: int, midi_stem: str, adlib: bool = False) -> Path:
    """The OGG of a song in the General MIDI set (`midi_stem` "esect1") or the AdLib set ("bsect1")."""
    return AUDIO / "music" / ("adlib" if adlib else "") / (stem("music", song_id, midi_stem) + ".ogg")


def ui_file(folder: str, pid: int) -> Path:
    return ASSETS / "ui" / folder / (stem("ui_picture", pid, "ui_%d" % pid) + ".png")


def problem_art_folder_file(folder: str, pid: int) -> Path:
    return ASSETS / "problem_art" / folder / (stem("problem_art", pid, "pa_%d" % pid) + ".png")


def foe_file(zone: int, slot: int) -> Path:
    """The picture of creature slot `slot` of `zone` (35 and up are the zone's own, 0-34 are shared by all zones)."""
    if slot < FOE_ZONE_BASE:
        return ASSETS / "sprites" / "foes" / (stem("frame", slot, "foe_%03d" % slot) + ".png")
    return ASSETS / "sprites" / "foes" / (stem("frame", slot, "foe_z%d_%03d" % (zone, slot), zone, "foe_z%d_" % zone) + ".png")


def deco_file(zone: int, slot: int) -> Path:
    """The picture of deco slot `slot` of art zone `zone` (70 and up are the zone's own, 0-69 are shared by all zones)."""
    if slot < COMMON_DECOS:
        return ASSETS / "sprites" / "decos" / (stem("deco", slot, "deco_%03d" % slot) + ".png")
    return ASSETS / "sprites" / "decos" / (stem("deco", slot, "deco_z%d_%03d" % (zone, slot), zone, "deco_z%d_" % zone) + ".png")
