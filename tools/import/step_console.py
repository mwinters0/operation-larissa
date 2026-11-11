"""Step 'console': the HUD layout and the calculator layout (godot/data/ui/*.tres).

Reads extracted/tables/hud_gauges.json (gauges, from export_constants.py) and console_layout.json (labels, lights, frame,
calculator keys, from tools/analysis/ghidra/export_console.py) and writes two settings Resources, so that no
position is typed into a GDScript file. The pictures are the ones step 'images' already copied.
"""
from __future__ import annotations

from pathlib import Path

from common import PACK_DATA, PROJECT_DATA, ANALYSIS_DATA, TABLES, load_json, out_text, png_size, raw_table, res_path
from pictures import problem_art_file, ui_file
import tres

SCRIPTS = "res://src/resources/"
# Where the menu bar's titles start, in pixels right of the bar's own left edge: the sum of the widths of the titles in front of
# it, each with the button margins and the gap between titles. The WINDOWS menu bar did this for the original; the Godot
# `MenuBar` lays its titles out from the theme font (Liberation Sans Bold, 13 px menu size: `File`, `Options`, `Help`) and has no call
# for where a title is, so the numbers are fixed here (measured once with that font; test_layout_from_data.gd checks them).
# A skin with another menu font brings its own `menu_layout.tres`.
MENU_TITLE_X = [0, 36, 96]
BEZEL_FIRST_ID = 1189          # bezel bundle (21) picture i = id 1189 + i
CALC_FIRST_ID = 1781           # calculator bundle (41) picture i = id 1781 + i


def _hud_tex(t: tres.Tres, item: int) -> str:
    return t.ext_ref("Texture2D", res_path(ui_file("hud", BEZEL_FIRST_ID + item)))


def _label_size(items) -> tuple[int, int]:
    """The size of the pictures `items` (bezel items: a lettering, the console, a light): they must all be the same size."""
    sizes = {png_size(res_path(ui_file("hud", BEZEL_FIRST_ID + item))) for item in items}
    assert len(sizes) == 1, f"the pictures of one HUD label differ in size: {sorted(sizes)}"
    return sizes.pop()


def _calc_tex(t: tres.Tres, item: int) -> str:
    return t.ext_ref("Texture2D", res_path(problem_art_file("b041", CALC_FIRST_ID + item)))


def _calc_size(item: int) -> tuple[int, int]:
    return png_size(res_path(problem_art_file("b041", CALC_FIRST_ID + item)))


def _slots(points) -> str:
    return "PackedVector2Array(%s)" % ", ".join("%d, %d" % (x, y) for x, y in points)


def build_hud_layout(gauges: dict, console: dict, colors: list) -> str:
    t = tres.Tres("Resource", "HudLayout", SCRIPTS + "hud_layout.gd")
    px, py = console["playfield"]["xy"]
    pw, ph = console["playfield"]["size"]
    t.set("playfield", tres.rect2i(px, py, pw, ph))
    t.set("bezel", _hud_tex(t, gauges["bezel_background"]["pic"]))
    t.set("bezel_position", tres.vec2i(*gauges["bezel_background"]["xy"]))
    t.set("bezel_size", tres.vec2i(*_label_size([gauges["bezel_background"]["pic"]])))

    tanks = gauges["tanks"]
    t.set("tank_positions", _slots([(x, tanks["y"]) for x in tanks["x"]]))
    t.set("tank_rect", tres.rect2i(*tanks["dirty_rect"]))             # the area the original redraws when a gauge changes: the rectangle a script may draw a gauge in
    t.set("tank_full", _hud_tex(t, tanks["pic_full"]))
    t.set("tank_empty", _hud_tex(t, tanks["pic_empty"]))

    ox = gauges["oxygen"]
    t.set("oxygen_positions", _slots([(ox["x0"] + ox["step_x"] * i, ox["y"]) for i in range(ox["slots"])]))
    t.set("oxygen_rect", tres.rect2i(*ox["dirty_rect"]))
    t.set("oxygen_full", _hud_tex(t, ox["pic_full"]))
    t.set("oxygen_empty", _hud_tex(t, ox["pic_empty"]))
    t.set("oxygen_low", _hud_tex(t, ox["pic_low_warning"]))

    ink = gauges["ink_pellets"]
    t.set("ink_positions", _slots(ink["xy"]))
    t.set("ink_rect", tres.rect2i(*ink["dirty_rect"]))
    t.set("ink_full", _hud_tex(t, ink["pic_full"]))
    t.set("ink_empty", _hud_tex(t, ink["pic_empty"]))

    labels = console["labels"]
    game = labels["game"]
    t.set("game_position", tres.vec2i(*game["xy"]))
    t.set("game_textures", tres.array("Texture2D", [_hud_tex(t, game["first_pic"] + g) for g in range(2)]))
    t.set("custom_position", tres.vec2i(*game["custom_xy"]))
    t.set("custom_texture", _hud_tex(t, game["custom_pic"]))
    # the box of each lettering: all the pictures of one label are the same size, so one size per label (a skin that draws the words as
    # text puts them in this box; the layout is data, not whatever picture is loaded)
    t.set("game_size", tres.vec2i(*_label_size(game["first_pic"] + g for g in range(2))))
    t.set("custom_size", tres.vec2i(*_label_size([game["custom_pic"]])))
    zone = labels["zone"]
    t.set("zone_position", tres.vec2i(*zone["xy"]))
    t.set("zone_textures", tres.array("Texture2D", [_hud_tex(t, zone["first_pic"] + z) for z in range(zone["last_zone"] + 1)]))
    t.set("zone_size", tres.vec2i(*_label_size(zone["first_pic"] + z for z in range(zone["last_zone"] + 1))))
    sector = labels["sector"]
    t.set("sector_position", tres.vec2i(*sector["xy"]))
    t.set("sector_textures", tres.array("Texture2D", [_hud_tex(t, sector["first_pic"] + i) for i in range(3)]))
    t.set("sector_final_texture", _hud_tex(t, sector["final_pic"]))
    t.set("sector_size", tres.vec2i(*_label_size([sector["first_pic"] + i for i in range(3)] + [sector["final_pic"]])))

    lights = console["message_lights"]
    for name in ("ship", "computer"):
        light = lights[name]
        t.set(name + "_position", tres.vec2i(*light["xy"]))
        t.set(name + "_textures", tres.array("Texture2D", [_hud_tex(t, light["pic_off"]), _hud_tex(t, light["pic_on"])]))
        t.set(name + "_size", tres.vec2i(*_label_size([light["pic_off"], light["pic_on"]])))

    rects = [e for e in console["frame"] if e[0] == "rect"]
    t.set("frame_rects", tres.array("Rect2i", [tres.rect2i(*e[2:6]) for e in rects]))
    t.set("frame_colors", "PackedColorArray(%s)" % ", ".join(
        "%s, %s, %s, 1" % tuple(tres.f(c / 255) for c in colors[e[1]]) for e in rects))
    return t.render()


def build_calculator_layout(console: dict) -> str:
    calc = console["calculator"]
    disp = calc["display"]
    t = tres.Tres("Resource", "CalculatorLayout", SCRIPTS + "calculator_layout.gd")
    t.set("picture", _calc_tex(t, calc["picture"]["item"]))
    t.set("picture_position", tres.vec2i(*calc["picture"]["xy"]))
    t.set("picture_size", tres.vec2i(*_calc_size(calc["picture"]["item"])))
    t.set("answer_panel", _calc_tex(t, calc["answer_panel"]["item"]))
    t.set("answer_position", tres.vec2i(*calc["answer_panel"]["xy"]))
    t.set("answer_size", tres.vec2i(*_calc_size(calc["answer_panel"]["item"])))
    t.set("key_names", tres.packed_strings([k["key"] for k in calc["keys"]]))
    t.set("key_rects", tres.array("Rect2i", [tres.rect2i(*k["rect"]) for k in calc["keys"]]))
    t.set("display_origin_calculator", tres.vec2i(disp["x0_calculator"], disp["y0"]))
    t.set("display_origin_answer", tres.vec2i(disp["x0_answer"], disp["y0"]))
    t.set("display_clear_rect", tres.rect2i(*disp["clear_rect"]))
    t.set("digits_right", str(disp["digits_right"]))
    t.set("digit_y", str(disp["digit_y"]))
    t.set("advance", str(disp["advance"]))
    t.set("point_offset", tres.vec2i(*disp["point_xy"]))
    t.set("fraction_flag_offset", tres.vec2i(*disp["fraction_flag_xy"]))
    t.set("operator_position", tres.vec2i(*disp["operator_xy"]))
    t.set("memory_position", tres.vec2i(*disp["memory_xy"]))
    g = disp["glyph_items"]
    t.set("digit_textures", tres.array("Texture2D", [_calc_tex(t, g["digit0"] + d) for d in range(10)]))
    t.set("point_texture", _calc_tex(t, g["point"]))
    t.set("slash_texture", _calc_tex(t, g["slash"]))
    t.set("minus_texture", _calc_tex(t, g["minus"]))
    t.set("fraction_flag_texture", _calc_tex(t, g["fraction_flag"]))
    t.set("memory_texture", _calc_tex(t, g["memory"]))
    # the sizes of the glyph pictures: where the digits go is the layout's business, not the pictures'
    t.set("digit_sizes", tres.array("Vector2i", [tres.vec2i(*_calc_size(g["digit0"] + d)) for d in range(10)]))
    t.set("point_size", tres.vec2i(*_calc_size(g["point"])))
    t.set("slash_size", tres.vec2i(*_calc_size(g["slash"])))
    t.set("minus_size", tres.vec2i(*_calc_size(g["minus"])))
    t.set("operator_textures", tres.dictionary([
        (tres.s("+"), _calc_tex(t, g["plus"])), (tres.s("-"), _calc_tex(t, g["subtract"])),
        (tres.s("*"), _calc_tex(t, g["multiply"])), (tres.s("/"), _calc_tex(t, g["divide"]))]))
    return t.render()


def build_menu_layout() -> str:
    """Where the menu bar's popups open (see MENU_TITLE_X): one number per menu title."""
    t = tres.Tres("Resource", "MenuBarLayout", SCRIPTS + "menu_bar_layout.gd")
    t.set("title_x", tres.packed_ints(MENU_TITLE_X))
    return t.render()


def build_story_layout() -> str:
    """The opening cartoon's position table: NEP.DLL resource 10012, 68 (x, y) pairs of 16 bit numbers that the
    original's `OpeningSequence` doubles at load time. The meaning of each index is documented in
    `src/resources/story_layout.gd` (found in the decompilation of OPENING.C, see docs/port/DESIGN.md section 2)."""
    raw = raw_table(10012)
    raw += b"\0" * (-len(raw) % 4)                      # the resource length is rounded down by one byte
    values = [int.from_bytes(raw[i:i + 2], "little", signed=True) * 2 for i in range(0, len(raw), 2)]
    points = list(zip(values[0::2], values[1::2]))
    t = tres.Tres("Resource", "StoryLayout", SCRIPTS + "story_layout.gd")
    t.set("points", _slots(points))
    return t.render()


def owned_files() -> list[Path]:
    """The files this step writes into the project (not the legacy pack): the menu layout, which commits. `import_all.py --clean` deletes them."""
    return [PROJECT_DATA / "ui" / "menu_layout.tres"]


def run() -> None:
    gauges = load_json(TABLES / "hud_gauges.json")
    console = load_json(ANALYSIS_DATA / "console_layout.json")
    colors = load_json(TABLES / "problem_diagrams.json")["colors"]
    out_text(PACK_DATA / "ui" / "hud_layout.tres", build_hud_layout(gauges, console, colors))
    out_text(PACK_DATA / "ui" / "calculator_layout.tres", build_calculator_layout(console))
    out_text(PROJECT_DATA / "ui" / "menu_layout.tres", build_menu_layout())
    out_text(PACK_DATA / "ui" / "story_layout.tres", build_story_layout())
    print("  console: hud_layout.tres, calculator_layout.tres, menu_layout.tres, story_layout.tres")
