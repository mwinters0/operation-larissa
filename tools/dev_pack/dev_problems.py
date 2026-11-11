"""Dev problems: the 34 problem types with a few made-up records per level, the problem screen layout and the text tables.

STRUCTURE comes from the program, as the importer has it (the layout of a record's fields, which field holds the answer, how an answer
is compared: tools/import/problem_tables.py, step_problems.COMPARE, docs/data/problem_*.json). VALUES are dev's: the titles, the texts (each
says which type and position it is), the records (small numbers by simple rules) and every coordinate of the drawings.
Every type but the three with a screen of their own (0 the combination lock, 28 and 29 the ballast panels) draws the generic
"items" diagram: its panel picture and the first fields of the record as numbers.
"""
from __future__ import annotations

import json
import math

import devlib
from devlib import DEV, SCRIPTS, write_text, tres

import dev_pictures as dp
import problem_tables
import step_problems

import inventory

TYPES = 34
TEXT_POSITIONS = 32                                    # a type's texts are addressed by position; the highest index any rule asks for is 31
RECORDS_PER_LEVEL = 3
PANEL_AT = (20, 60)
LOCK_CENTER = (166, 208)

BALLAST_VALUES = {"0": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "1": [1, 2, 4, 8, 16, 32, 64, 128, 256, 512],
                  "2": [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]}
BALLAST_MODE_BY_LEVEL = [0, 1, 2, 1]
# Types that have no records at some levels, as some of the original's do (a trigger that asks for such a type at that level gets the other type
# of its pair: `ProblemFactory.for_trigger_slot`). Type 3 has none at level 2; `levels_available` says so too.
NO_RECORDS = {3: (2,)}
SONAR_STEP_TICKS = 20                                  # type 3: its three pictures come 20 ticks apart (dev's build-up, 60 ticks in all)


def art_for(t: int, files: list[str]) -> tuple[str, list[str]]:
    """(art_dir, art_files) of type `t` from the pack's own file list: the pictures of its bundle folder in id order (or its single picture)."""
    real = devlib.problem_art()[t]
    if real >= 900:
        folder = "assets/problem_art/single"
        picked = [f for f in files if f.startswith(folder + "/") and f.endswith("_%d.png" % real)]
    else:
        folder = "assets/problem_art/b%03d" % real
        picked = sorted((f for f in files if f.startswith(folder + "/") and f.endswith(".png")), key=_id_of)
    assert picked, "no art for type %d" % t
    return devlib.DEV_RES + folder, [devlib.DEV_RES + f for f in picked]


def _id_of(rel: str) -> int:
    return int(rel.rsplit("_", 1)[1].split(".")[0])


# --- records --------------------------------------------------------------------------------------------------------

def number(value: float) -> list[int]:
    """The flat form of a decimal number with one decimal place: (0, raw, exp, 0)."""
    return [0, round(value * 10), 1, 0]


def generic_record(kinds: str, level: int, v: int) -> list[int]:
    flat = []
    for i, k in enumerate(kinds):
        n = (level + v + i) % 3                          # 0, 1 or 2: valid wherever a field picks one of a few words or units
        if k == "n":
            flat += number(n + 1 + level + v * 0.5)
        elif k == "w":
            flat.append(10 * (v + 1) + level)
        else:                                          # c and b: a small whole number
            flat.append(n)
    return flat


def offset_of(kinds: str, field: int) -> int:
    """Where field `field` starts in the flat record (a number takes four ints, any other field one)."""
    return sum(4 if k == "n" else 1 for k in kinds[:field])


def rounding_record(kinds: str, level: int, v: int) -> list[int]:
    """Type 15 picks its text by field 1 - 1, so that field is 1, 2 or 3."""
    flat = generic_record(kinds, level, v)
    flat[offset_of(kinds, 1)] = 1 + (level + v) % 3
    return flat


def lock_record(kinds: str, level: int, v: int) -> list[int]:
    """Stage 1 and 2 each: operand slot a, '+', operand slot b, '=', the answer slot (the operand wheel's labels are "1".."8", the answer wheel's "2".."9")."""
    a, b = v, v + 1 + (level % 2)
    flat = [0] * offset_of(kinds, len(kinds))                                    # the wheel set 0, zero padding, numbers as the decimal 0, then the two programs
    for first in (1, 12):
        for offset, value in enumerate([a, 1, b, 0, a + b]):              # slot, +, slot, =, answer slot (the answer wheel's label of slot s is s + 2 = (a+1)+(b+1))
            flat[offset_of(kinds, first + offset)] = value
    return flat


def heading_record(kinds: str, level: int, v: int) -> list[int]:
    """Type 22 (a heading turned by whole steps of 45 degrees): f0 the turn, f1 the present heading (a multiple of 45), f2 the direction (not 0:
    clockwise, the heading grows), f3 the answer heading. The answer must be reachable from the heading in 45 degree steps, which a generic record
    is not: a test that walked the steps to the answer once looped for ever on such a record (I6, `diagram_animations`)."""
    turn = 45 * (1 + (level + v) % 3)
    start = 45 * ((3 * level + 2 * v) % 8)
    clockwise = (level + v) % 2
    return [turn, start, clockwise, (start + turn if clockwise else start - turn) % 360]


def range_record(kinds: str, level: int, v: int) -> list[int]:
    return [10 * (v + 1), 15 + v, 10 + v, 20 + v]       # depth, the exact answer at level 0, the bounds


def ballast_record(kinds: str, level: int, v: int) -> list[int]:
    values = BALLAST_VALUES[str(BALLAST_MODE_BY_LEVEL[level])]
    mask = (0b101 << v) & 0x3FF | 1
    return [sum(values[i] for i in range(10) if mask >> i & 1), mask]


def records_for(t: int, kinds: str) -> tuple[list[list[int]], list[int]]:
    make = {0: lock_record, 4: range_record, 15: rounding_record, 22: heading_record, 28: ballast_record, 29: ballast_record}.get(t, generic_record)
    records, levels = [], []
    for level in range(4):
        for v in range(RECORDS_PER_LEVEL):
            if level in NO_RECORDS.get(t, ()):
                continue
            records.append(make(kinds, level, v))
            levels.append(level)
    return records, levels


# --- the diagram of a type ------------------------------------------------------------------------------------------

def items_diagram(kinds: str) -> dict:
    items = [{"pic": 0, "pos": list(PANEL_AT), "opaque": True}]
    for i in range(min(len(kinds), 4)):
        items.append({"text": {"field": i}, "box": [30 + 70 * i, 64], "y": 330})
    return {"family": "items", "items": items}


def wheel_spots(radius: float) -> list[list[list[int]]]:
    """Label centres for the 4 quarter-turn phases and the 8 spots (clockwise from the top) on a circle round the lock's centre."""
    out = []
    for phase in range(4):
        out.append([[round(LOCK_CENTER[0] + radius * math.sin(2 * math.pi * (s + phase / 4) / 8)),
                     round(LOCK_CENTER[1] - radius * math.cos(2 * math.pi * (s + phase / 4) / 8))] for s in range(8)])
    return out


def lock_diagram() -> dict:
    return {"family": "lock", "items": [], "face": {"pic": 11, "pos": list(PANEL_AT)},
            "answer_wheel": {"first_pic": 12, "pos": [LOCK_CENTER[0] - 120, LOCK_CENTER[1] - 120], "size": [240, 240]},
            "operand_wheel": {"first_pic": 6, "pos": [LOCK_CENTER[0] - 70, LOCK_CENTER[1] - 70],
                              "window": {"pic": 10, "pos": [LOCK_CENTER[0] - 70 + 52, LOCK_CENTER[1] - 70 + 3]}},
            "operand_labels": wheel_spots(50), "answer_labels": wheel_spots(100)}


def ballast_diagram() -> dict:
    slot = (96, 28)
    return {"family": "ballast_panel", "items": [{"pic": 0, "pos": list(PANEL_AT), "opaque": True}],
            "weights": {"slot_pic": 4, "selected_pic": 3, "cursor_pic": 2,
                        "pos": [[40 + 130 * col, 80 + 36 * row] for col in range(2) for row in range(5)],
                        "label_offset": [40, 4], "label_color": 0, "slot_size": list(slot)},
            "total": {"idle_pic": 7, "focus_pic": 6, "done_pic": 5, "pos": [40, 280], "hold_ticks": 70, "size": list(slot)},
            "button": {"pic": 1, "pos": [170, 280]}}


def sonar_diagram(kinds: str) -> dict:
    """Type 3 draws its panel, two numbers and three pictures that come one after the other (the generic "items" family with an "intro":
    `sequence` mode, one group of items per step). Dev's own build-up: 3 steps of SONAR_STEP_TICKS ticks, a sound at each."""
    spec = items_diagram(kinds)
    spec["items"] = spec["items"][:3]
    for i, pic in enumerate((2, 3, 4)):
        spec["items"].append({"pic": pic, "pos": [60 + 100 * i, 150], "animate": True})
    spec["intro"] = {"mode": "sequence", "sfx": 41, "interval": SONAR_STEP_TICKS}
    return spec


def diagram_for(t: int, kinds: str) -> dict:
    return {0: lambda: lock_diagram(), 3: lambda: sonar_diagram(kinds), 28: ballast_diagram, 29: ballast_diagram}.get(t, lambda: items_diagram(kinds))()


def extras_for(t: int) -> str:
    if t == 0:
        labels = {str(s): [str(i + 1) for i in range(8)] for s in range(12)}
        answers = {str(s): [str(i + 1) for i in range(1, 9)] for s in range(12)}
        by_set = lambda d: tres.dictionary((tres.s(k), tres.packed_strings(v)) for k, v in sorted(d.items(), key=lambda kv: int(kv[0])))
        return tres.dictionary([(tres.s("operand_labels"), by_set(labels)), (tres.s("answer_labels"), by_set(answers)),
                                (tres.s("operators"), tres.packed_strings(["=", "+", "-", "x", "/"]))])
    if t in (28, 29):
        return tres.dictionary([
            (tres.s("mode_by_level"), tres.packed_ints(BALLAST_MODE_BY_LEVEL)),
            (tres.s("values"), tres.dictionary((tres.s(k), tres.packed_ints(v)) for k, v in sorted(BALLAST_VALUES.items()))),
            (tres.s("labels"), tres.dictionary((tres.s(k), tres.packed_strings(str(x) for x in v)) for k, v in sorted(BALLAST_VALUES.items())))])
    if t == 4:
        return tres.dictionary([(tres.s("range_fields"), tres.packed_ints([2, 3]))])
    return "{}"


def problem_type_tres(t: int, files: list[str], fields_json: dict) -> str:
    kinds = problem_tables.field_kinds(t)
    folder, art = art_for(t, files)
    if t == 0:                                          # the lock also draws the face (single 1803) and the answer wheel (bundle 78)
        art += [devlib.DEV_RES + "assets/problem_art/single/pa_1803.png"] + \
               [devlib.DEV_RES + f for f in sorted((f for f in files if f.startswith("assets/problem_art/b078/") and f.endswith(".png")), key=_id_of)]
    records, levels = records_for(t, kinds)
    mode, tolerances, kind_levels = step_problems.COMPARE.get(t, ("exact", (0, 0, 0, 0), ()))
    title = "Dev problem %02d" % t
    texts = ["Dev problem %02d, text %02d" % (t, p) for p in range(TEXT_POSITIONS)]
    o = tres.Tres("Resource", "ProblemType", SCRIPTS + "problem_type.gd")
    o.set("id", str(t))
    o.set("title", tres.s(title))
    o.set("texts", tres.packed_strings(texts))
    o.set("text_ids", tres.packed_ints([0] * TEXT_POSITIONS))
    o.set("uses_calculator", tres.b(t not in step_problems.NO_CALCULATOR))
    o.set("levels_available", tres.packed_ints([0 if level in NO_RECORDS.get(t, ()) else 1 for level in range(4)]))
    o.set("art_dir", tres.s(folder))
    o.set("art_files", tres.packed_strings(art))
    o.set("field_kinds", tres.s(kinds))
    o.set("records", tres.array("PackedInt64Array", ["PackedInt64Array(%s)" % ", ".join(map(str, r)) for r in records]))
    o.set("record_levels", tres.packed_ints(levels))
    o.set("answer_fields", tres.packed_ints(step_problems.answer_fields(t, fields_json)))
    o.set("compare_mode", tres.s(mode))
    o.set("tolerances", "PackedFloat64Array(%s)" % ", ".join(str(x) for x in tolerances))
    o.set("kind_checked_levels", tres.packed_ints(kind_levels))
    o.set("extras", extras_for(t))
    o.set("diagram", tres.literal(diagram_for(t, kinds)))
    return o.render()


def screen_layout_tres() -> str:
    """The parts of the problem screen all types share, on dev's own problem background (616 x 340 at (12, 30))."""
    t = tres.Tres("Resource", "ProblemScreenLayout", SCRIPTS + "problem_screen_layout.gd")
    t.set("background", devlib.tex(t, "assets/problem_art/single/pa_1780.png"))
    t.set("background_position", tres.vec2i(12, 30))
    t.set("background_size", tres.vec2i(*dp.PROBLEM_BACKGROUND))
    t.set("title_box_x", "20")
    t.set("title_box_width", "600")
    t.set("title_y", "36")
    t.set("message_box", tres.rect2i(320, 62, 296, 120))
    t.set("calculator_position", tres.vec2i(320, 200))
    t.set("font_cell_height", "19")      # the project theme's font (17 px, squeezed to 7): a pack describes it, it cannot change it
    t.set("font_average_width", "7")
    t.set("line_height", "20")
    t.set("line_separation", "0")
    palette = [(0, 0, 0), (0, 0, 128), (0, 128, 0), (0, 128, 128), (128, 0, 0), (128, 0, 128), (128, 128, 0), (192, 192, 192),
               (128, 128, 128), (0, 0, 255), (0, 255, 0), (0, 255, 255), (255, 0, 0), (255, 0, 255), (255, 255, 0), (255, 255, 255)]
    t.set("palette", "PackedColorArray(%s)" % ", ".join("%s, %s, %s, 1" % tuple(tres.f(c / 255) for c in rgb) for rgb in palette))
    return t.render()


# --- text tables --------------------------------------------------------------------------------------------------------

def text_names() -> dict[int, str]:
    """text number -> registry name (godot/names/original.json, kind "text"): the names are ours."""
    store = json.loads((devlib.GODOT / "names" / "original.json").read_text())
    return {n: name for name, n in store["names"]["text"].items()}


def text_table_tres(ids: list[int], names: dict[int, str], overrides: dict[int, str] | None = None) -> str:
    """A text table: each text says its registry name, except those in `overrides` (texts the engine reads as structure: a menu's lines, a heading's words)."""
    overrides = overrides or {}
    t = tres.Tres("Resource", "TextTable", SCRIPTS + "text_table.gd")
    t.set("texts", tres.dictionary((str(i), tres.s(overrides.get(i, names.get(i, "text_%d" % i)))) for i in sorted(ids)))
    return t.render()


def problem_art_index(inv: dict) -> str:
    return json.dumps(inv["problem_art_index"], indent=1, sort_keys=True) + "\n"


def write_all() -> int:
    inv = inventory.load()
    fields_json = json.loads((devlib.ROOT / "docs" / "data" / "problem_fields.json").read_text())
    files = inv["files"]
    for t in range(TYPES):
        write_text(DEV / "data" / "problems" / ("problem_type_%02d.tres" % t), problem_type_tres(t, files, fields_json))
    write_text(DEV / "data" / "problems" / "screen_layout.tres", screen_layout_tres())
    names = text_names()
    from test_sectors import batch_d                  # (batch D keeps the structured texts: the menus' lines, the Hall of Fame's headings, ...)
    for table, ids in inv["text_tables"].items():
        write_text(DEV / "data" / "problems" / (table + ".tres"), text_table_tres(ids, names, batch_d.STRUCTURED_TEXTS.get(table)))
    write_text(DEV / "data" / "problems" / "problem_art_index.json", problem_art_index(inv))
    return TYPES + 2 + len(inv["text_tables"])
