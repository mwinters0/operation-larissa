"""The dev tile set over the dev atlases (the same TileSet layout as the importer's: sources 0-4 the zone atlases, 5 the currents, 6 the
invisible wall; custom data 0 "current", 1 "tile_byte"). The layout is the engine's (tile_codec.gd); the pictures are dev's."""
from __future__ import annotations

import devlib
from devlib import DEV, write_text, tres

GRID = 8
SQUARE = "PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)"
DIRS = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]     # NW N NE W E SW S SE
ZONE_NAMES = ["Dev zone 0", "Dev zone 1", "Dev zone 2", "Dev zone 3", "Dev zone 4 (also the finales)"]


def tileset_tres() -> str:
    t = tres.Tres("TileSet", uid=devlib.uid_of("data/neptune_tileset.tres"))
    for z in range(5):
        lines = ["texture = " + devlib.tex(t, "assets/tiles/zone%d_tiles.png" % z), "use_texture_padding = false"]
        for k in range(GRID * GRID):
            c = "%d:%d/0" % (k % GRID, k // GRID)
            lines += ["%s = 0" % c, "%s/physics_layer_0/polygon_0/points = %s" % (c, SQUARE), "%s/custom_data_1 = %d" % (c, 0x40 | k)]
        t.sub("TileSetAtlasSource", [("resource_name", tres.s(ZONE_NAMES[z]))], prefix="Zone%d" % z)
        t.subs[-1] += "\n" + "\n".join(lines)
    lines = ["texture = " + devlib.tex(t, "assets/tiles/currents.png"), "use_texture_padding = false"]
    for strength in range(8):
        for direction, (dx, dy) in enumerate(DIRS):
            m = strength * 2 + 2
            c = "%d:%d/0" % (direction, strength)
            lines += ["%s = 0" % c, "%s/custom_data_0 = Vector2(%d, %d)" % (c, dx * m, dy * m),
                      "%s/custom_data_1 = %d" % (c, 0x80 | strength << 3 | direction)]
    t.sub("TileSetAtlasSource", [("resource_name", tres.s("Currents (letters, not drawn in the game)"))], prefix="Currents")
    t.subs[-1] += "\n" + "\n".join(lines)
    lines = ["texture = " + devlib.tex(t, "assets/tiles/invisible_wall.png"), "use_texture_padding = false",
             "0:0/0 = 0", "0:0/0/physics_layer_0/polygon_0/points = " + SQUARE, "0:0/0/custom_data_1 = %d" % 0x40]
    t.sub("TileSetAtlasSource", [("resource_name", tres.s("Invisible wall (editor only)"))], prefix="InvisibleWall")
    t.subs[-1] += "\n" + "\n".join(lines)
    ids = [s.split('id="')[1].split('"')[0] for s in t.subs]
    t.set("physics_layer_0/collision_layer", "1")
    t.set("custom_data_layer_0/name", '"current"')
    t.set("custom_data_layer_0/type", "5")
    t.set("custom_data_layer_1/name", '"tile_byte"')
    t.set("custom_data_layer_1/type", "2")
    for i, rid in enumerate(ids):
        t.set("sources/%d" % i, 'SubResource("%s")' % rid)
    return t.render()


def write_all() -> int:
    write_text(DEV / "data" / "neptune_tileset.tres", tileset_tres())
    return 1
