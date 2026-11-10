"""Step 'tiles': zone floor atlases, the currents atlas and neptune_tileset.tres."""
from __future__ import annotations

import io
import math
from pathlib import Path

from PIL import Image, ImageDraw

from asset_manifest import put_atlas, put_port
from common import ASSETS, PACK_DATA, ZONE_TITLES, bundle_ids, out_text, res_path, sprite_file, Stats, write_bytes
import tres

TILE = 16
GRID = 8                       # 8 x 8 cells per atlas
# Direction table of the original (jump-table order): NW N NE W E SW S SE.
DIRS = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
SQUARE = "PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)"
# Source ids inside the tileset. 0-4 = zone atlases, 5 = currents, 6 = the editor-only invisible wall.
CURRENTS_SOURCE = 5
INVISIBLE_WALL_SOURCE = 6
# Custom data layers: 0 "current" (Vector2, read by the sub), 1 "tile_byte" (int, the byte the original stores).
TYPE_VECTOR2 = 5
TYPE_INT = 2


def save_png(img: Image.Image, dest) -> None:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=False)
    Stats.record(write_bytes(dest, buf.getvalue()))


def build_zone_atlas(zone: int) -> None:
    """Cell k of the 8x8 grid holds tile picture k (k = low 6 bits of a tile byte)."""
    atlas = Image.new("RGBA", (TILE * GRID, TILE * GRID), (0, 0, 0, 0))
    for k, pid in enumerate(bundle_ids(23 + 3 * zone)):
        if k == 0:
            continue                      # index 0 = "nothing" (an invisible wall)
        tile = Image.open(sprite_file(pid)).convert("RGBA")
        assert tile.size == (TILE, TILE), (zone, k, tile.size)
        atlas.paste(tile, ((k % GRID) * TILE, (k // GRID) * TILE))
    dest = ASSETS / "tiles" / ("zone%d_tiles.png" % zone)
    save_png(atlas, dest)
    put_atlas(dest, 23 + 3 * zone, bundle_ids(23 + 3 * zone))


def build_currents_atlas() -> None:
    """Debug picture: column = direction (0-7), row = strength (0-7)."""
    img = Image.new("RGBA", (TILE * GRID, TILE * GRID), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for strength in range(8):
        for direction, (dx, dy) in enumerate(DIRS):
            cx, cy = direction * TILE + 8, strength * TILE + 8
            d.rectangle([direction * TILE, strength * TILE, direction * TILE + 15, strength * TILE + 15],
                        fill=(40, 120, 255, 40))
            n = math.hypot(dx, dy)
            ux, uy = dx / n, dy / n
            length = 3 + strength * 0.8           # longer arrow = stronger current
            tip = (cx + ux * length, cy + uy * length)
            tail = (cx - ux * length, cy - uy * length)
            d.line([tail, tip], fill=(255, 255, 255, 200), width=1)
            px, py = -uy, ux
            head = [tip, (tip[0] - ux * 3 + px * 2, tip[1] - uy * 3 + py * 2),
                    (tip[0] - ux * 3 - px * 2, tip[1] - uy * 3 - py * 2)]
            d.polygon(head, fill=(255, 255, 255, 230))
    save_png(img, ASSETS / "tiles" / "currents.png")
    put_port(ASSETS / "tiles" / "currents.png", "tools/import/step_tiles.py", "drawn")


def build_invisible_wall() -> None:
    """Editor picture for tile byte 0x40 (a wall without art): diagonal pink hatching on a faint pink tint.

    Pink is not used anywhere in the zone art, and the stripes are opaque, so the tile shows on dark and on light
    backgrounds. The game never draws it (it draws picture 0 of the zone atlas, which is transparent).
    """
    pink = (255, 40, 160)
    img = Image.new("RGBA", (TILE, TILE), pink + (50,))
    px = img.load()
    assert px is not None
    for y in range(TILE):
        for x in range(TILE):
            if (x + y) % 5 == 0:
                px[x, y] = pink + (255,)
            if x in (0, TILE - 1) or y in (0, TILE - 1):
                px[x, y] = pink + (255,)
    save_png(img, ASSETS / "tiles" / "invisible_wall.png")
    put_port(ASSETS / "tiles" / "invisible_wall.png", "tools/import/step_tiles.py", "drawn")


def zone_source_name(zone: int) -> str:
    """Name shown in the TileSet panel. Zone 4's atlas also serves the two finale sectors (zones 5 and 6)."""
    name = "Zone %d: %s" % (zone, ZONE_TITLES[zone])
    return name + " (also the finales)" if zone == 4 else name


# The tileset is written in the text Godot itself writes (see the note on build_tileset), so a Ctrl+S in the editor, which saves
# every resource it thinks was edited, leaves the committed file as it is. This is the uid Godot gave it the first time.
TILESET_UID = "uid://c7w78wbxveog0"


def godot_vec2(x: int, y: int) -> str:
    """Vector2 the way Godot prints a whole-number one: Vector2(-2, 0), not Vector2(-2.0, 0.0)."""
    return "Vector2(%d, %d)" % (x, y)


def tile_texture(t: tres.Tres, png: Path) -> str:
    """ExtResource of an atlas picture, with the uid Godot keeps for it in the .import file."""
    return t.ext_ref("Texture2D", res_path(png), tres.import_uid(png))


def build_tileset() -> None:
    """neptune_tileset.tres, in GODOT'S OWN text format: a uid in the header and on every picture, and none of the properties
    that have their default value (texture_region_size and tile_size are 16 x 16, which is what the editor leaves out). The editor
    loads this file for the screen editor's tile painting and would rewrite it on Ctrl+S; with this text that save is a no-op
    (checked by saving it in a headless editor: the result is byte for byte this file)."""
    t = tres.Tres("TileSet", uid=TILESET_UID)
    for z in range(5):
        tex = tile_texture(t, ASSETS / "tiles" / ("zone%d_tiles.png" % z))
        lines = ["texture = " + tex, "use_texture_padding = false"]
        for k in range(GRID * GRID):
            c = "%d:%d/0" % (k % GRID, k // GRID)
            lines.append("%s = 0" % c)
            lines.append("%s/physics_layer_0/polygon_0/points = %s" % (c, SQUARE))
            lines.append("%s/custom_data_1 = %d" % (c, 0x40 | k))
        t.sub("TileSetAtlasSource", [("resource_name", tres.s(zone_source_name(z)))], prefix="Zone%d" % z)
        t.subs[-1] += "\n" + "\n".join(lines)
    # currents atlas: no collision, custom data "current" = acceleration in source units
    tex = tile_texture(t, ASSETS / "tiles" / "currents.png")
    lines = ["texture = " + tex, "use_texture_padding = false"]
    for strength in range(8):
        for direction, (dx, dy) in enumerate(DIRS):
            m = strength * 2 + 2                       # ((v & 0x38) >> 2) + 2
            c = "%d:%d/0" % (direction, strength)
            lines.append("%s = 0" % c)
            lines.append("%s/custom_data_0 = %s" % (c, godot_vec2(dx * m, dy * m)))
            lines.append("%s/custom_data_1 = %d" % (c, 0x80 | strength << 3 | direction))
    t.sub("TileSetAtlasSource", [("resource_name", tres.s("Currents (debug arrows, not drawn in the game)"))], prefix="Currents")
    t.subs[-1] += "\n" + "\n".join(lines)
    # invisible wall (editor only): one hatched tile with the wall collision square and tile byte 0x40
    tex = tile_texture(t, ASSETS / "tiles" / "invisible_wall.png")
    lines = ["texture = " + tex, "use_texture_padding = false",
             "0:0/0 = 0", "0:0/0/physics_layer_0/polygon_0/points = " + SQUARE, "0:0/0/custom_data_1 = %d" % 0x40]
    t.sub("TileSetAtlasSource", [("resource_name", tres.s("Invisible wall (editor only)"))], prefix="InvisibleWall")
    t.subs[-1] += "\n" + "\n".join(lines)
    ids = [s.split('id="')[1].split('"')[0] for s in t.subs]
    assert len(ids) == INVISIBLE_WALL_SOURCE + 1 and ids[CURRENTS_SOURCE].startswith("Currents")
    t.set("physics_layer_0/collision_layer", "1")
    t.set("custom_data_layer_0/name", '"current"')
    t.set("custom_data_layer_0/type", str(TYPE_VECTOR2))
    t.set("custom_data_layer_1/name", '"tile_byte"')
    t.set("custom_data_layer_1/type", str(TYPE_INT))
    for i, rid in enumerate(ids):
        t.set("sources/%d" % i, 'SubResource("%s")' % rid)
    out_text(PACK_DATA / "neptune_tileset.tres", t.render())


def run() -> None:
    for z in range(5):
        build_zone_atlas(z)
    build_currents_atlas()
    build_invisible_wall()
    build_tileset()
    print("  tiles: 5 zone atlases, currents atlas, invisible wall, tileset")
