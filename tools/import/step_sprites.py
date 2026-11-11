"""Step 'sprites': sprite PNG copies, SpriteFrames, sprite metadata, bubble rules."""
from __future__ import annotations

import animation_map as amap
from asset_manifest import copy_picture
from common import (ASSETS, PACK_DATA, TABLES, TICK_HZ, bundle_ids, deco_slots, foe_slots,
                    load_json, out_text, res_path)
import sprite_meta
import tres
from asset_names import deco_file, foe_file
from pictures import home

SPRITE_FRAMES_DIR = PACK_DATA / "sprite_frames"
META_DIR = PACK_DATA / "sprite_meta"
SCRIPTS = "res://src/resources/"


# ---- SpriteFrames ---------------------------------------------------------

def sprite_frames_tres(all_paths: list[str], extra: list[tuple[str, list[str], bool]] | None = None) -> str:
    """SpriteFrames with the indexed animation "all" (frame i = slot i) plus named animations.

    `extra` entries are (name, [res:// paths], loop). Named animations play at
    the original game tick rate; "all" has speed 0 so it never advances by itself.
    """
    t = tres.Tres("SpriteFrames")

    def anim(name: str, paths: list[str], speed: float, loop: bool) -> str:
        frames = ", ".join('{"duration": 1.0, "texture": %s}' % t.ext_ref("Texture2D", p) for p in paths)
        return '{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}' % (
            frames, tres.b(loop), name, tres.f(speed))

    anims = [anim("all", all_paths, 0.0, False)]
    for name, paths, loop in extra or []:
        anims.append(anim(name, paths, TICK_HZ, loop))
    t.set("animations", "[%s]" % ", ".join(anims))
    return t.render()


def pick(paths: list[str], indices: list[int]) -> list[str]:
    return [paths[i] for i in indices]


# ---- copying sprites ------------------------------------------------------

def copy_ids(ids: list[int], file) -> list[str]:
    """Copy NEP256 sprites to the file `file(i, id)` (a Path; `sprite_in` makes one for the sets without registry names); returns res:// paths.

    A picture is stored once (pictures.py): an id that another role owns (the story art, the finale creatures) is not
    copied again, the returned path is that role's file."""
    out = []
    for i, pid in enumerate(ids):
        dest = file(i, pid)
        owner = home(pid)
        if owner is None or owner == dest:
            copy_picture(pid, dest)
        else:
            dest = owner
        out.append(res_path(dest))
    return out


def sprite_in(folder: str, pattern: str):
    """The file rule of a set that has no names: assets/sprites/<folder>/<pattern % index>.png (`pattern` may use the id as %(id)d)."""
    return lambda i, pid: ASSETS / "sprites" / folder / ((pattern % {"i": i, "id": pid}) + ".png")


def deco_paths(zone: int) -> list[str]:
    """The files of deco slots 0-69 (common) and the zone's own, from the slot table tools/analysis/data/sprite_slots.json."""
    return copy_ids(deco_slots(zone), lambda slot, pid: deco_file(zone, slot))


def foe_paths(zone: int) -> list[str]:
    """The files of creature slots 0-27 (common), 28-34 (ink) and 35+ (the zone's own), from tools/analysis/data/sprite_slots.json."""
    return copy_ids(foe_slots(zone), lambda slot, pid: foe_file(zone, slot))


# ---- metadata ---------------------------------------------------------------

def meta_tres(name: str, ids: tuple[int, int, int], count: int) -> str:
    """sprite_meta_<name>.tres, from the original tables read by sprite_meta.py (the same bytes the fixture hashes)."""
    meta = sprite_meta.decode_set(sprite_meta.original_tables(ids), count)
    t = tres.Tres("Resource", "SpriteMetaTable", SCRIPTS + "sprite_meta_table.gd")
    t.set("sizes", tres.array("Vector2i", [tres.vec2i(*v) for v in meta["sizes"]]))
    t.set("hit_rects", tres.array("Rect2i", [tres.rect2i(*v) for v in meta["hit_rects"]]))
    t.set("hit_rects_flipped", tres.array("Rect2i", [tres.rect2i(*v) for v in meta["hit_rects_flipped"]]))
    return t.render()


def write_meta() -> None:
    for name, ids, count in sprite_meta.SETS:
        out_text(META_DIR / ("sprite_meta_%s.tres" % name), meta_tres(name, ids, count))
    out_text(sprite_meta.HASH_FIXTURE, sprite_meta.build_hash_fixture())
    out_text(sprite_meta.RAW_FIXTURE, sprite_meta.build_raw_fixture())


def write_bubble_rules() -> None:
    """The ambient bubbles' spawn rule, motion and picture order (BUBBLES.C), from extracted/tables/bubbles.json. The sizes of the eight
    pictures (the original's own table) go into the rules too: its spawn range (x) and its despawn test (picture height) read them,
    and a rule must not depend on which picture is on disk."""
    amb = load_json(TABLES / "bubbles.json")["ambient"]
    t = tres.Tres("Resource", "BubbleRules", SCRIPTS + "bubble_rules.gd")
    t.set("spawn_chance", str(amb["spawn_chance"]))
    t.set("spawn_y", str(amb["spawn_y"]))
    t.set("top_y", str(amb["top_y"]))
    t.set("x_base", str(amb["x_base"]))
    t.set("x_span", str(amb["x_span"]))
    slots = amb["slots"]
    t.set("slot_first_picture", tres.packed_ints([sl["first_picture"] for sl in slots]))
    t.set("slot_rise_per_tick", tres.packed_ints([sl["rise_per_tick"] for sl in slots]))
    t.set("slot_loop", tres.array("PackedInt32Array", [tres.packed_ints(sl["loop"]) for sl in slots]))
    t.set("picture_sizes", tres.array("Vector2i", [tres.vec2i(*size) for size in amb["picture_sizes"]]))
    t.set("no_bubble_screens", tres.array("Vector2i", [tres.vec2i(sec, scr) for sec, scr in amb["no_bubble_screens"]]))
    t.set("finale_sector", str(amb["finale_no_bubble_sector"]))
    t.set("finale_screens", tres.packed_ints(amb["finale_no_bubble_screens"]))
    out_text(PACK_DATA / "bubble_rules.tres", t.render())


# ---- run ------------------------------------------------------------------------

def run() -> None:
    for z in range(5):
        out_text(SPRITE_FRAMES_DIR / ("decos_zone%d.tres" % z), sprite_frames_tres(deco_paths(z)))
    for z in range(7):
        paths = foe_paths(z)
        extra = [(n, pick(paths, idx), loop) for n, idx, loop in amap.FOE_COMMON]
        out_text(SPRITE_FRAMES_DIR / ("foes_zone%d.tres" % z), sprite_frames_tres(paths, extra))

    sub = copy_ids(bundle_ids(15), sprite_in("sub", "sub_%(i)02d"))
    out_text(SPRITE_FRAMES_DIR / "sub_frames.tres",
             sprite_frames_tres(sub, [(n, pick(sub, idx), loop) for n, idx, loop in amap.SUB]))

    pieces = copy_ids(bundle_ids(17), sprite_in("pieces", "piece_%(i)02d"))
    # The pieces animate (DrawProbePieces 0x42dc3b, extracted/tables/piece_animation.json): the canister flashes between pictures
    # 3 and 4, every other piece is a rock that sparkles on 3 of 16 game frames. One entry per game tick.
    anim = load_json(TABLES / "piece_animation.json")
    out_text(SPRITE_FRAMES_DIR / "pieces_frames.tres",
             sprite_frames_tres(pieces, [("canister", pick(pieces, anim["canister_pictures"]), True),
                                         ("rock", pick(pieces, anim["rock_pictures"]), True)]))

    station = copy_ids(bundle_ids(18), sprite_in("station", "station_%(i)02d"))
    out_text(SPRITE_FRAMES_DIR / "station_frames.tres",
             sprite_frames_tres(station, [(n, pick(station, idx), loop) for n, idx, loop in amap.STATION]))

    # fx_frames: "all" = bubble columns (bundle 22); named sets from loose ids
    bubbles = copy_ids(bundle_ids(amap.FX_BUBBLE_BUNDLE), sprite_in("fx", "fx_bubbles_%(i)02d"))
    extra = [("bubble_columns", bubbles, True)]
    for name, (ids, loop) in amap.FX_SETS.items():
        extra.append((name, copy_ids(ids, sprite_in("fx", "fx_%s_%%(id)d" % name)), loop))
    out_text(SPRITE_FRAMES_DIR / "fx_frames.tres", sprite_frames_tres(bubbles, extra))

    write_meta()
    write_bubble_rules()
    print("  sprites: decos x5, foes x7, sub, pieces, station, fx, metadata, bubble rules")
