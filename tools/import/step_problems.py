"""Step 'problems': problem_type_NN.tres and the text tables (logs, hints, UI strings)."""
from __future__ import annotations

import copy

from common import ASSETS, PACK_DATA, ANALYSIS_DATA, TABLES, EXTRACTED, bundle_ids, load_json, out_text, png_size, raw_table, res_path
from pictures import problem_art_file
import problem_tables
import tres

SCRIPTS = "res://src/resources/"
# The height of one line of the project font (Liberation Sans Bold at the original's 17 px em, themes/neptune_theme.tres), as
# Godot measures it: ascent plus descent. The original's lines are `line_height` (20, `GetFontLineHeight`) apart, so the extra space between lines
# is the difference, and it is DATA (`ProblemScreenLayout.line_separation`) so no screen has to ask the font. A skin with another
# font changes this number with its font. test_layout_from_data.gd checks it against the theme's font.
STOCK_FONT_LINE_HEIGHT = 20
NO_CALCULATOR = {0, 28, 29}     # combination lock and the two ballast panels (DESIGN 5.2)


def clean(text: str) -> str:
    """Drop the NUL / Ctrl-Z padding some resources carry at the end."""
    return text.split("\x00")[0].rstrip("\x1a")


def art_files(real_id: int) -> tuple[str, list[str]]:
    """(folder, files) of the panel art for a problem type. A picture another part of the port owns (pictures.py)
    is listed with the path of that file, so `files` is the truth and `folder` only the bundle's own folder."""
    if real_id < 900:                                            # a bundle of pictures
        folder = ASSETS / "problem_art" / ("b%03d" % real_id)
        return res_path(folder), [res_path(problem_art_file("b%03d" % real_id, i)) for i in bundle_ids(real_id)]
    folder = ASSETS / "problem_art" / "single"                   # one loose picture
    return res_path(folder), [res_path(problem_art_file("single", real_id))]


def extra_art(t_id: int) -> list[str]:
    """Pictures a type's drawing uses that are not in its own bundle (appended to `art_files`).
    The combination lock draws its face (loose picture 1803) and its answer wheel (bundle 78)."""
    if t_id != 0:
        return []
    return [res_path(problem_art_file("single", 1803))] + [res_path(problem_art_file("b078", i)) for i in bundle_ids(78)]


# How a typed answer is compared, per type (DESIGN 5.2 item 7 / tools/analysis/data/problem_fields.json):
#   (mode, tolerance per educational level 0-3, levels whose answer KIND (fraction vs decimal) must match)
#   exact: |a-b| < 1e-10        near: |a-b| <= |expected| * tol        close: |a-b| <= tol
#   range: strictly between two stored bounds   sum: ballast, a set of denominations   wheel: lock
ALL = (0, 1, 2, 3)
COMPARE: dict[int, tuple[str, tuple, tuple]] = {
    0: ("wheel", (0, 0, 0, 0), ()),
    1: ("near", (0, 0.03, 0, 0), ()),
    2: ("close", (0.01,) * 4, ()),
    4: ("range", (0, 0, 0, 0), ()),
    9: ("close", (0, 0.5, 0.2, 0), ()),
    11: ("close", (0, 0.3, 0.3, 0), ()),
    13: ("close", (0.01,) * 4, ()),
    14: ("exact", (0, 0, 0, 0), (1,)),
    17: ("close", (0, 0, 0.7, 0), ALL),
    26: ("near", (0, 0.03, 0, 0.03), ()),
    27: ("near", (0, 0.03, 0, 0.03), ()),
    28: ("sum", (0, 0, 0, 0), ()),
    29: ("sum", (0, 0, 0, 0), ()),
    32: ("exact", (0, 0, 0, 0), ALL),
    33: ("exact", (0, 0, 0, 0), ALL),
}


def answer_fields(t_id: int, fields_json: dict) -> list[int]:
    """Flat field index holding the expected answer for each level (-1: none)."""
    ans = fields_json["types"][str(t_id)]["answer"]
    if isinstance(ans, int):
        return [ans] * 4
    return {
        0: [-1] * 4,                      # lock: answer is derived from the program (LockProgram)
        3: [2, 3, 3, 3],                  # "fL==0: 2 else 3"
        4: [1, -1, -1, -1],               # L0 exact f1; L>0 uses the two bounds (extras.range_fields)
        28: [-1] * 4, 29: [-1] * 4,       # ballast: sum of selected denominations == f0
    }[t_id]


def stored_records(t_id: int) -> tuple[str, list[list[int]], list[int]]:
    """(field kinds, flat records, level of each record) of a type, read from its four original tables (problem_tables.py).
    The flat form keeps every byte of the tables, so ProblemType.encode_table() gives them back."""
    kinds = problem_tables.field_kinds(t_id)
    records, levels = [], []
    for level in range(problem_tables.LEVELS):
        recs = problem_tables.decode_table(kinds, problem_tables.original_table(t_id, level))
        records += recs
        levels += [level] * len(recs)
    return kinds, records, levels


def fix_glyphs(text: str) -> str:
    """The original font has private glyphs: 0x12 before F/C and 0xA1 after a number are degree
    signs; the pairs 0x11 0x12 and 0x17 0x18 are the picture of the Space bar and of the Enter key."""
    return (text.replace("\x12F", "°F").replace("\x12C", "°C").replace("¡", "°")
            .replace("\x11\x12", "Space").replace("\x17\x18", "Enter"))


def positional_texts(t_id: int, bundle_ids_by_type: dict, texts_by_bundle: dict) -> tuple[list[str], list[int]]:
    """Texts of the type's bundle by POSITION (the original addresses them as bundle index).

    A few positions have no text in NEP.DLL (levels where the type does not occur, or a missing
    worked solution); they stay as empty strings so that every index rule of DESIGN 5.4 still
    points at the right entry.
    """
    ids = bundle_ids_by_type[str(43 + t_id)]
    by_id = {e["id"]: clean(e["text"]) for e in texts_by_bundle[str(43 + t_id)]}
    texts = [fix_glyphs(by_id.get(i, "")) for i in ids]
    return texts, [i if i in by_id else 0 for i in ids]


def with_picture_sizes(spec: dict, files: list[str]) -> dict:
    """The type's `diagram` spec plus the sizes of the pictures that hit areas and centring are measured from:
    the ballast panel's weight button and Done button (`weights.slot_size`, `total.size`: the clickable rectangles and the width
    the labels are centred in) and the lock's answer wheel (`answer_wheel.size`: its centre and radius for clicks). `files` is
    the type's `art_files`; the size is read from the PNG the importer wrote, so it is the original's size."""
    spec = copy.deepcopy(spec)
    if spec.get("family") == "ballast_panel":
        spec["weights"]["slot_size"] = list(png_size(files[spec["weights"]["slot_pic"]]))
        spec["total"]["size"] = list(png_size(files[spec["total"]["idle_pic"]]))
    elif spec.get("family") == "lock":
        spec["answer_wheel"]["size"] = list(png_size(files[spec["answer_wheel"]["first_pic"]]))
    return spec


# The labels the EXE holds statically for the lock's decimal wheel sets (" .1", " .10") and the ballast panel's level-3 weights
# (".01") are only defaults: `DoCombinationLock` (0x421780) and `LoadBallastLabels` (0x419d96) load strings over the buffers the
# label tables point at, and those are what the wheels, the worked solution and the panel show. wheel set -> the string ids loaded
# into its 8 labels (operand tables at 0x441e9c: sets 7 and 8 are LockTenthLabelPtrs / LockTenthLabelPtrsCopy, set 11
# LockHundredthLabelPtrs; answer tables at 0x44201c: set 6 is LockTenthFromSecondPtrs, "0.2" .. "0.8" and, in its entry 7,
# LockLabelSlotNineTenths; set 8 LockWholeTenthLabelPtrs).
LOCK_LOADED_OPERAND_LABELS = {7: range(11219, 11227), 8: range(11219, 11227), 11: range(11228, 11236)}
LOCK_LOADED_ANSWER_LABELS = {6: [*range(11220, 11227), 11227], 8: range(11237, 11245)}
# BallastLabels mode 1 (level 3): the string id loaded into each of the 10 weights' labels.
BALLAST_LOADED_LABELS = {1: [11215] * 4 + [11216] * 2 + [11217] + [11218] * 3}


def loaded_labels(static: list[str], ids, strings: dict) -> list[str]:
    """The labels a wheel set or ballast mode shows: the loaded strings `ids`. A loaded string says the same number as the static
    label with only its padding changed (" .5" -> "0.5", ".25" -> "0.25"), which this checks, so a wrong id or table fails loudly."""
    labels = [strings[str(i)] for i in ids]
    assert len(labels) == len(static), (static, labels)
    for old, new in zip(static, labels):
        assert float(old) == float(new), (old, new)
    return labels


def lock_labels(lock: dict, strings: dict) -> tuple[dict, dict]:
    """(operand labels, answer labels) by wheel set as the lock shows them: the static tables of lock_wheel.json with the sets
    `DoCombinationLock` loads strings into replaced by those strings."""
    operand = {int(k): v for k, v in lock["operand_labels_by_wheel_set"].items()}
    answer = {int(k): v for k, v in lock["answer_labels_by_wheel_set"].items()}
    for wheel_set, ids in LOCK_LOADED_OPERAND_LABELS.items():
        operand[wheel_set] = loaded_labels(operand[wheel_set], ids, strings)
    for wheel_set, ids in LOCK_LOADED_ANSWER_LABELS.items():
        answer[wheel_set] = loaded_labels(answer[wheel_set], ids, strings)
    return operand, answer


def ballast_labels(modes: dict, strings: dict) -> dict:
    """The weights' labels by ballast display mode: ballast.json's static ones with mode 1 replaced by `LoadBallastLabels`' strings."""
    labels = {k: list(v["labels"]) for k, v in modes.items()}
    for mode, ids in BALLAST_LOADED_LABELS.items():
        labels[str(mode)] = loaded_labels(labels[str(mode)], ids, strings)
    return labels


def extras_for(t_id: int) -> str:
    """Small side tables some types need, as a Dictionary literal (or {})."""
    if t_id == 0:
        lock = load_json(TABLES / "lock_wheel.json")
        operand, answer = lock_labels(lock, load_json(EXTRACTED / "data" / "ONWIN16_strings.json"))
        by_set = lambda labels: tres.dictionary((tres.s(str(k)), tres.packed_strings(v)) for k, v in sorted(labels.items()))
        return tres.dictionary([
            (tres.s("operand_labels"), by_set(operand)),
            (tres.s("answer_labels"), by_set(answer)),
            (tres.s("operators"), tres.packed_strings(lock["operator_strings"])),
        ])
    if t_id in (28, 29):
        ballast = load_json(TABLES / "ballast.json")["modes"]
        labels = ballast_labels(ballast, load_json(EXTRACTED / "data" / "ONWIN16_strings.json"))
        by_level = [0, 2, 1, 2]       # BallastMode (0x448694): level 0 -> mode 0 (cents), 1 -> 2 (powers of two), 2 -> 1 (dollars), 3 -> 2
        return tres.dictionary([
            (tres.s("mode_by_level"), tres.packed_ints(by_level)),
            (tres.s("values"), tres.dictionary((tres.s(k), tres.packed_ints(v["values"])) for k, v in sorted(ballast.items()))),
            (tres.s("labels"), tres.dictionary((tres.s(k), tres.packed_strings(v)) for k, v in sorted(labels.items()))),
        ])
    if t_id == 4:
        return tres.dictionary([(tres.s("range_fields"), tres.packed_ints([2, 3]))])
    return "{}"


def build_problem_type(t_id: int, ctx: dict) -> str:
    texts, text_ids = positional_texts(t_id, ctx["bundles"], ctx["texts_by_bundle"])
    levels = [1 if raw_table(10512 + 4 * t_id + lv)[:1] not in (b"", b"\x00") else 0 for lv in range(4)]
    folder, files = art_files(ctx["gfx_real"][t_id])
    files = files + extra_art(t_id)
    kinds, records, record_levels = stored_records(t_id)
    assert [record_levels.count(lv) > 0 for lv in range(4)] == [bool(v) for v in levels], t_id
    mode, tolerances, kind_levels = COMPARE.get(t_id, ("exact", (0, 0, 0, 0), ()))
    # Transcription check against the Ghidra notes. Type 17's "exact + kind rule + tolerance_L2 0.7" is
    # written here as mode "close" (tolerance only at level 2) with the kind rule on every level.
    assert t_id == 17 or mode == ctx["fields"]["types"][str(t_id)]["compare"]["mode"], (t_id, mode)
    t = tres.Tres("Resource", "ProblemType", SCRIPTS + "problem_type.gd")
    t.set("id", str(t_id))
    t.set("title", tres.s(ctx["titles"][str(11074 + t_id)]))
    t.set("texts", tres.packed_strings(texts))
    t.set("text_ids", tres.packed_ints(text_ids))
    t.set("uses_calculator", tres.b(t_id not in NO_CALCULATOR))
    t.set("levels_available", tres.packed_ints(levels))
    t.set("art_dir", tres.s(folder))
    t.set("art_files", tres.packed_strings(files))
    t.set("field_kinds", tres.s(kinds))
    t.set("records", tres.array("PackedInt64Array", ["PackedInt64Array(%s)" % ", ".join(map(str, r)) for r in records]))
    t.set("record_levels", tres.packed_ints(record_levels))
    t.set("answer_fields", tres.packed_ints(answer_fields(t_id, ctx["fields"])))
    t.set("compare_mode", tres.s(mode))
    t.set("tolerances", "PackedFloat64Array(%s)" % ", ".join(str(x) for x in tolerances))
    t.set("kind_checked_levels", tres.packed_ints(kind_levels))
    t.set("extras", extras_for(t_id))
    t.set("diagram", tres.literal(with_picture_sizes(ctx["diagrams"]["types"][str(t_id)], files)))
    return t.render()


def build_screen_layout(diagrams: dict) -> str:
    """The parts of the problem screen that are the same for all types (DESIGN 5.5)."""
    screen = diagrams["screen"]
    t = tres.Tres("Resource", "ProblemScreenLayout", SCRIPTS + "problem_screen_layout.gd")
    bg = screen["background"]
    background = res_path(problem_art_file("single", bg["single_pic_id"]))
    t.set("background", t.ext_ref("Texture2D", background))
    t.set("background_position", tres.vec2i(*bg["pos"]))
    t.set("background_size", tres.vec2i(*png_size(background)))
    t.set("title_box_x", str(screen["title"]["box"][0]))
    t.set("title_box_width", str(screen["title"]["box"][1]))
    t.set("title_y", str(screen["title"]["y"]))
    t.set("message_box", tres.rect2i(*screen["message_box"]))
    t.set("calculator_position", tres.vec2i(*screen["calculator_pos"]))
    font = screen["font"]
    t.set("font_cell_height", str(font["cell_height"]))
    t.set("font_average_width", str(font["average_width"]))
    t.set("line_height", str(font["line_height"]))
    t.set("line_separation", str(font["line_height"] - STOCK_FONT_LINE_HEIGHT))
    t.set("palette", "PackedColorArray(%s)" % ", ".join(
        "%s, %s, %s, 1" % tuple(tres.f(c / 255) for c in rgb) for rgb in diagrams["colors"]))
    return t.render()


def text_table(pairs: list[tuple[int, str]]) -> str:
    t = tres.Tres("Resource", "TextTable", SCRIPTS + "text_table.gd")
    t.set("texts", tres.dictionary((str(k), tres.s(v)) for k, v in sorted(pairs)))
    return t.render()


def run() -> None:
    ctx = {
        "texts_by_bundle": load_json(EXTRACTED / "data" / "NEP_text_by_bundle.json"),
        "bundles": load_json(EXTRACTED / "data" / "NEP_bundles.json"),
        "titles": load_json(EXTRACTED / "data" / "ONWIN16_strings.json"),
        "gfx_real": load_json(TABLES / "problem_gfx_bundles.json")["gfx_real"],
        "fields": load_json(ANALYSIS_DATA / "problem_fields.json"),      # meaning of every field (DESIGN 5.4)
        "diagrams": load_json(TABLES / "problem_diagrams.json"),  # how the original draws each type (DESIGN 5.5)
    }
    for i in range(34):
        out_text(PACK_DATA / "problems" / ("problem_type_%02d.tres" % i), build_problem_type(i, ctx))
    out_text(PACK_DATA / "problems" / "screen_layout.tres", build_screen_layout(ctx["diagrams"]))

    nep = {e["id"]: clean(e["text"]) for e in load_json(EXTRACTED / "data" / "NEP_text.json") if e.get("kind") == "text"}
    # Each table is a list of (first id, last id) ranges. "help" holds the Help menu's pages: the
    # short pop-up pages 10152-10166 and the long ones 12000-12020 (DESIGN 2 item 5).
    ranges = {"log_entries": [(10648, 10677)], "supply_messages": [(10678, 10707)],
              "hints": [(10167, 10173)], "story": [(10003, 10011)], "closing": [(10715, 10717)],
              "help": [(10152, 10166), (12000, 12020)],
              # the three "Calculator Error" messages: 0 divide by zero, 1 too large, 2 operator inside a fraction
              # (item 0-2 of bundle 0xf5, `ShowCalcNoticeDialog` (0x420d8f), DESIGN 5.2)
              "calc_notices": [(10174, 10176)]}
    for name, spans in ranges.items():
        pairs = [(i, nep[i]) for lo, hi in spans for i in range(lo, hi + 1) if i in nep]   # a few ids hold no text
        out_text(PACK_DATA / "problems" / (name + ".tres"), text_table(pairs))
    ui = load_json(EXTRACTED / "data" / "ONWIN32_strings.json")
    out_text(PACK_DATA / "problems" / "ui_strings.tres", text_table([(int(k), v) for k, v in ui.items()]))
    out_text(problem_tables.HASH_FIXTURE, problem_tables.build_hash_fixture())
    out_text(problem_tables.RAW_FIXTURE, problem_tables.build_raw_fixture())
    print("  problems: 34 types, 8 text tables, screen layout")
