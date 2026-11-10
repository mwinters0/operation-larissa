"""Dev sprite frames, sprite metadata (box hit rectangles that match the dev pictures) and bubble rules.

The file NAMES come from the importer's own naming code (asset_names, pictures.home) and the slot tables of docs/data/sprite_slots.json;
the sizes come from dev_pictures. Nothing is read from the legacy pack.
"""
from __future__ import annotations

import json
from pathlib import Path

import devlib                                    # first: it puts tools/import on the path
from devlib import DEV, SCRIPTS, write_text, tres

import animation_map as amap
import common as importer
from asset_names import deco_file, foe_file
from pictures import home

import dev_pictures

SPEED = importer.TICK_HZ


def _rel(path: Path) -> str:
    return path.relative_to(importer.LEGACY).as_posix()


def _slot_paths(ids: list[int], file) -> list[str]:
    out = []
    for i, pid in enumerate(ids):
        dest = file(i, pid)
        owner = home(pid)
        out.append(_rel(dest if owner is None or owner == dest else owner))
    return out


def deco_paths(zone: int) -> list[str]:
    return _slot_paths(importer.deco_slots(zone), lambda slot, pid: deco_file(zone, slot))


def foe_paths(zone: int) -> list[str]:
    return _slot_paths(importer.foe_slots(zone), lambda slot, pid: foe_file(zone, slot))


def numbered(folder: str, stem: str, count: int) -> list[str]:
    return ["assets/sprites/%s/%s_%02d.png" % (folder, stem, i) for i in range(count)]


def frames_tres(paths: list[str], extra: list[tuple[str, list[str], bool]] | None = None) -> str:
    """SpriteFrames with the indexed animation "all" (frame i = slot i, speed 0) plus named animations at the game tick rate."""
    t = tres.Tres("SpriteFrames")

    def anim(name: str, items: list[str], speed: float, loop: bool) -> str:
        frames = ", ".join('{"duration": 1.0, "texture": %s}' % devlib.tex(t, p) for p in items)
        return '{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}' % (frames, tres.b(loop), name, tres.f(speed))

    anims = [anim("all", paths, 0.0, False)]
    for name, items, loop in extra or []:
        anims.append(anim(name, items, SPEED, loop))
    t.set("animations", "[%s]" % ", ".join(anims))
    return t.render()


def pick(paths: list[str], indices: list[int]) -> list[str]:
    return [paths[i] for i in indices]


def frame_sets() -> dict[str, tuple[list[str], list]]:
    """data/sprite_frames/<name>.tres -> (the pictures by slot, the named animations)."""
    sets: dict[str, tuple[list[str], list]] = {}
    for z in range(5):
        sets["decos_zone%d" % z] = (deco_paths(z), [])
    for z in range(7):
        paths = foe_paths(z)
        sets["foes_zone%d" % z] = (paths, [(n, pick(paths, idx), loop) for n, idx, loop in amap.FOE_COMMON])
    sub = numbered("sub", "sub", 13)
    sets["sub_frames"] = (sub, [(n, pick(sub, idx), loop) for n, idx, loop in amap.SUB])
    pieces = numbered("pieces", "piece", 5)
    anim = json.loads((devlib.ROOT / "docs" / "data" / "piece_animation.json").read_text())
    sets["pieces_frames"] = (pieces, [("canister", pick(pieces, anim["canister_pictures"]), True),
                                      ("rock", pick(pieces, anim["rock_pictures"]), True)])
    station = numbered("station", "station", 7)
    sets["station_frames"] = (station, [(n, pick(station, idx), loop) for n, idx, loop in amap.STATION])
    bubbles = numbered("fx", "fx_bubbles", 8)
    extra = [("bubble_columns", bubbles, True)]
    for name, (ids, loop) in amap.FX_SETS.items():
        extra.append((name, _slot_paths(ids, lambda i, pid: Path("/nowhere")), loop))
    sets["fx_frames"] = (bubbles, extra)
    return sets


def meta_sets() -> dict[str, list[str]]:
    """sprite_meta_<name> -> the picture of each of its sprites: the common creatures, the ink bursts, the creatures of each zone."""
    common_foes = foe_paths(0)
    first, ink = importer.COMMON_CREATURES, importer.INK_FRAMES
    sets = {"common": common_foes[:first], "ink": common_foes[first:first + ink]}
    for z in range(7):
        sets["zone%d" % z] = foe_paths(z)[importer.FOE_ZONE_BASE:]
    return sets


def meta_tres(pictures: list[str]) -> str:
    t = tres.Tres("Resource", "SpriteMetaTable", SCRIPTS + "sprite_meta_table.gd")
    sizes, rects = [], []
    for rel in pictures:
        _kind, w, h = dev_pictures.spec(rel)
        sizes.append((w, h))
        rects.append((2, 2, w - 4, h - 4))                            # the box: the picture inset by 2 px on every side
    t.set("sizes", tres.array("Vector2i", [tres.vec2i(*v) for v in sizes]))
    t.set("hit_rects", tres.array("Rect2i", [tres.rect2i(*v) for v in rects]))
    t.set("hit_rects_flipped", tres.array("Rect2i", [tres.rect2i(*v) for v in rects]))
    return t.render()


def bubble_rules_tres() -> str:
    """Four bubble kinds over the eight pictures fx_bubbles_00..07 (kind k starts at picture 2k and then loops picture 2k + 1)."""
    t = tres.Tres("Resource", "BubbleRules", SCRIPTS + "bubble_rules.gd")
    t.set("spawn_chance", "40")
    t.set("spawn_y", "304")
    t.set("top_y", "40")
    t.set("x_base", "32")
    t.set("x_span", "560")
    t.set("slot_first_picture", tres.packed_ints([0, 2, 4, 6]))
    t.set("slot_rise_per_tick", tres.packed_ints([2, 2, 4, 4]))
    t.set("slot_loop", tres.array("PackedInt32Array", [tres.packed_ints([1]), tres.packed_ints([3]), tres.packed_ints([5]), tres.packed_ints([7])]))
    t.set("picture_sizes", tres.array("Vector2i", [tres.vec2i(8 + 2 * i, 8 + 2 * i) for i in range(8)]))
    t.set("no_bubble_screens", tres.array("Vector2i", []))
    t.set("finale_sector", "4")
    t.set("finale_screens", tres.packed_ints([]))
    return t.render()


def write_all() -> int:
    n = 0
    for name, (paths, extra) in frame_sets().items():
        write_text(DEV / "data" / "sprite_frames" / (name + ".tres"), frames_tres(paths, extra))
        n += 1
    for name, pictures in meta_sets().items():
        write_text(DEV / "data" / "sprite_meta" / ("sprite_meta_%s.tres" % name), meta_tres(pictures))
        n += 1
    write_text(DEV / "data" / "bubble_rules.tres", bubble_rules_tres())
    return n + 1
