"""Dev layouts (HUD, calculator, story) and the dev news cartoon: dev's own rectangles on the 640 x 400 window.

The pictures that play each role are named by their number in the console bundles (the order of the picture files, as in the
importer); where they go and how big they are is dev's own, and `dev_pictures` draws them with the sizes used here.
"""
from __future__ import annotations

import devlib
from devlib import DEV, SCRIPTS, write_text, tres

import common as importer
from asset_names import ui_file
from pictures import problem_art_file

import dev_pictures as dp

BEZEL_FIRST_ID = 1189
CALC_FIRST_ID = 1781


def hud_rel(item: int) -> str:
    return ui_file("hud", BEZEL_FIRST_ID + item).relative_to(importer.LEGACY).as_posix()


def calc_rel(item: int) -> str:
    return problem_art_file("b041", CALC_FIRST_ID + item).relative_to(importer.LEGACY).as_posix()


def vecs(points) -> str:
    return "PackedVector2Array(%s)" % ", ".join("%d, %d" % (x, y) for x, y in points)


def hud_layout_tres() -> str:
    t = tres.Tres("Resource", "HudLayout", SCRIPTS + "hud_layout.gd")
    tx = lambda item: devlib.tex(t, hud_rel(item))
    t.set("playfield", tres.rect2i(16, 32, 608, 288))      # 38 x 18 tiles of 16 px: the engine's playfield
    t.set("bezel", tx(0))
    t.set("bezel_position", tres.vec2i(12, 324))
    t.set("bezel_size", tres.vec2i(*dp.BEZEL))
    t.set("tank_positions", vecs([(100 + 28 * i, 336) for i in range(6)]))
    t.set("tank_rect", tres.rect2i(100, 336, 6 * 28 - 8, 20))                # the slots' icons are 20 x 20 and 28 apart
    t.set("tank_full", tx(15))
    t.set("tank_empty", tx(16))
    t.set("oxygen_positions", vecs([(280 + 24 * i, 338) for i in range(4)]))
    t.set("oxygen_rect", tres.rect2i(280, 338, 4 * 24 - 8, 16))              # 16 x 16, 24 apart
    t.set("oxygen_full", tx(17))
    t.set("oxygen_empty", tx(18))
    t.set("oxygen_low", tx(19))
    t.set("ink_positions", vecs([(100 + 12 * (i % 7), 362 + 10 * (i // 7)) for i in range(21)]))
    t.set("ink_rect", tres.rect2i(100, 362, 7 * 12 - 4, 3 * 10 - 2))         # 8 x 8, in 7 columns 12 apart and 3 rows 10 apart
    t.set("ink_full", tx(4))
    t.set("ink_empty", tx(5))
    t.set("game_position", tres.vec2i(512, 370))
    t.set("game_textures", tres.array("Texture2D", [tx(2), tx(3)]))
    t.set("custom_position", tres.vec2i(408, 370))
    t.set("custom_texture", tx(1))
    t.set("game_size", tres.vec2i(*dp.LABEL))
    t.set("custom_size", tres.vec2i(*dp.LABEL))
    t.set("zone_position", tres.vec2i(512, 350))
    t.set("zone_textures", tres.array("Texture2D", [tx(6 + z) for z in range(5)]))
    t.set("zone_size", tres.vec2i(*dp.LABEL))
    t.set("sector_position", tres.vec2i(512, 330))
    t.set("sector_textures", tres.array("Texture2D", [tx(11 + i) for i in range(3)]))
    t.set("sector_final_texture", tx(14))
    t.set("sector_size", tres.vec2i(*dp.LABEL))
    t.set("ship_position", tres.vec2i(408, 330))
    t.set("ship_textures", tres.array("Texture2D", [tx(21), tx(22)]))
    t.set("ship_size", tres.vec2i(*dp.HUD_SIZES[21]))
    t.set("computer_position", tres.vec2i(408, 350))
    t.set("computer_textures", tres.array("Texture2D", [tx(23), tx(24)]))
    t.set("computer_size", tres.vec2i(*dp.HUD_SIZES[23]))
    rects = [(0, 0, 640, 2), (0, 398, 640, 2), (0, 0, 2, 400), (638, 0, 2, 400), (12, 30, 616, 2), (12, 320, 616, 2)]
    t.set("frame_rects", tres.array("Rect2i", [tres.rect2i(*r) for r in rects]))
    t.set("frame_colors", "PackedColorArray(%s)" % ", ".join("0, 0, 0, 1" if i < 4 else "0.5, 0.5, 0.5, 1" for i in range(len(rects))))
    return t.render()


KEYS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "+", "-", "*", "/", "=", "Enter", "F", "S", "N", "R", "C"]
CALC_AT = (320, 200)
ANSWER_AT = (320, 200)


def key_rects() -> list[tuple[int, int, int, int]]:
    """The 22 keys on a grid of 5 columns x 5 rows of 36 x 20 keys with 4 px gaps, below the display (which ends 36 px down)."""
    x0, y0 = CALC_AT[0] + 8, CALC_AT[1] + 40
    return [(x0 + 40 * (i % 5), y0 + 24 * (i // 5), 36, 20) for i in range(len(KEYS))]


def calculator_layout_tres() -> str:
    t = tres.Tres("Resource", "CalculatorLayout", SCRIPTS + "calculator_layout.gd")
    tx = lambda item: devlib.tex(t, calc_rel(item))
    t.set("picture", tx(0))
    t.set("picture_position", tres.vec2i(*CALC_AT))
    t.set("picture_size", tres.vec2i(*dp.CALCULATOR))
    t.set("answer_panel", tx(21))
    t.set("answer_position", tres.vec2i(*ANSWER_AT))
    t.set("answer_size", tres.vec2i(*dp.ANSWER_PANEL))
    t.set("key_names", tres.packed_strings(KEYS))
    t.set("key_rects", tres.array("Rect2i", [tres.rect2i(*r) for r in key_rects()]))
    t.set("display_origin_calculator", tres.vec2i(CALC_AT[0] + 8, CALC_AT[1] + 8))
    t.set("display_origin_answer", tres.vec2i(ANSWER_AT[0] + 8, ANSWER_AT[1] + 8))
    t.set("display_clear_rect", tres.rect2i(0, 0, 176, 28))             # relative to the origin: the black field
    t.set("digits_right", "160")                                        # the rightmost digit starts here; the cells are 16 apart
    t.set("digit_y", "4")
    t.set("advance", "16")
    t.set("point_offset", tres.vec2i(8, 20))
    t.set("fraction_flag_offset", tres.vec2i(4, 14))
    t.set("operator_position", tres.vec2i(CALC_AT[0] + 200, CALC_AT[1] + 12))
    t.set("memory_position", tres.vec2i(CALC_AT[0] + 220, CALC_AT[1] + 12))
    t.set("digit_textures", tres.array("Texture2D", [tx(1 + d) for d in range(10)]))
    t.set("point_texture", tx(11))
    t.set("slash_texture", tx(13))
    t.set("minus_texture", tx(14))
    t.set("fraction_flag_texture", tx(15))
    t.set("memory_texture", tx(16))
    t.set("digit_sizes", tres.array("Vector2i", [tres.vec2i(14, 20)] * 10))
    t.set("point_size", tres.vec2i(6, 6))
    t.set("slash_size", tres.vec2i(14, 20))
    t.set("minus_size", tres.vec2i(14, 20))
    t.set("operator_textures", tres.dictionary([(tres.s("+"), tx(17)), (tres.s("-"), tx(18)), (tres.s("*"), tx(19)), (tres.s("/"), tx(20))]))
    return t.render()


def story_points() -> list[tuple[int, int]]:
    """The 68 points of the story layout (the indices are the engine's: StoryLayout), laid out by simple rules."""
    pts = [(0, 0)] * 68
    pts[0] = (0, 0)                                                      # MAP
    pts[1], pts[2] = (0, 320), (520, 320)                                # the two consoles
    pts[3:6] = [(100 + 20 * i, 300) for i in range(3)]                   # ALARM_LIGHTS
    pts[6:12] = [(160 + 20 * i, 300) for i in range(6)]                  # STATUS_LIGHTS
    pts[12:20] = [(300 + 20 * i, 320) for i in range(8)]                 # PANEL_LIGHTS
    pts[20] = (150, 200)                                                 # TELETYPE
    pts[21] = (400, 120)                                                 # CRASH_SITE
    pts[22:27] = [(100 + 60 * i, 260) for i in range(5)]                 # CREW
    pts[27:48] = [(20 + 20 * i, 40 + 4 * i) for i in range(21)]          # the capsule's trail
    pts[48:63] = [(-200, 120), (0, 100), (40, 140), (60, 200), (20, 150), (0, 160), (80, 170), (0, 0), (0, 200),
                  (400, 20), (500, 40), (40, 20), (100, 80), (160, 120), (200, 360)]
    for i in range(63, 68):
        pts[i] = (320, 200)
    return pts


def story_layout_tres() -> str:
    t = tres.Tres("Resource", "StoryLayout", SCRIPTS + "story_layout.gd")
    t.set("points", vecs(story_points()))
    return t.render()


# --- the news cartoon ---------------------------------------------------------------------------------------------

def news_cartoon_tres() -> str:
    """A 600 tick cartoon of our own: three bulletins typed out, the capsule's trail of dots, the ring, the crew, an alarm."""
    t = tres.Tres("Resource", "CutsceneTimeline", SCRIPTS + "cutscene_timeline.gd")
    track_script = SCRIPTS + "cutscene_track.gd"
    cue_script = SCRIPTS + "cutscene_cue.gd"
    tracks = []

    def track(actor: str, prop: str, keys: list, smooth: bool = False) -> None:
        times = ", ".join(tres.f(k[0]) if isinstance(k[0], float) else str(k[0]) for k in keys)
        props = [("actor", '&"%s"' % actor), ("property", '&"%s"' % prop), ("times", "PackedFloat64Array(%s)" % times),
                 ("values", "[%s]" % ", ".join(k[1] for k in keys))]
        if smooth:
            props.append(("smooth", "true"))
        tracks.append(t.sub("Resource", props, script=track_script, prefix="Track"))

    name = lambda s: '&"%s"' % s
    track("teletype", "text", [(0, name("")), (50, name("news_bulletin_0")), (250, name("news_bulletin_1")), (450, name("news_bulletin_2"))])
    track("teletype", "reveal", [(0, "0.0"), (50, "0.0"), (200, "1.0"), (250, "0.0"), (400, "1.0"), (450, "0.0"), (590, "1.0")], True)
    for i in range(21):
        track("dot_%02d" % i, "visible", [(0, "false"), (10 * i + 10, "true")])
    track("ring", "visible", [(0, "false"), (300, "true"), (400, "false")])
    for i in range(5):
        track("crew_%d" % i, "picture", [(0, name("crew_walk_0")), (100 + 10 * i, name("crew_walk_1")), (200 + 10 * i, name("crew_walk_2"))])
        track("crew_%d" % i, "mirror", [(0, "false"), (300, "true")])
    for i in range(3):
        track("alarm_%d" % i, "visible", [(0, "false"), (100 * (i + 1), "true"), (100 * (i + 1) + 50, "false")])
    cue = t.sub("Resource", [("tick", "600"), ("kind", '&"event"'), ("cue_name", '&"end"')], script=cue_script, prefix="Cue")
    t.set("length", "600")
    t.set("tracks", tres.array('ExtResource("%s")' % t.ext_id("Script", track_script), tracks))
    t.set("cues", tres.array('ExtResource("%s")' % t.ext_id("Script", cue_script), [cue]))
    t.set("provenance", tres.s("Dev pack: a short news cartoon of our own (tools/dev_pack/dev_ui.py)."))
    return t.render()


def write_all() -> int:
    write_text(DEV / "data" / "ui" / "hud_layout.tres", hud_layout_tres())
    write_text(DEV / "data" / "ui" / "calculator_layout.tres", calculator_layout_tres())
    write_text(DEV / "data" / "ui" / "story_layout.tres", story_layout_tres())
    write_text(DEV / "data" / "story" / "news_cartoon.tres", news_cartoon_tres())
    return 4
