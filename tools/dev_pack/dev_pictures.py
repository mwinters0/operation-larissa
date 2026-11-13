"""Dev pictures: flat shapes in the dev palette with a 1 px outline and the picture's own key name written on them.

One colour per kind (sprite, deco, tile, UI, background, problem art). The sizes are dev's own: arbitrary, even, easy to read; a
few are the size the ENGINE assumes (the sub, a piece, the playfield, the prompt's sender icon), listed in `ENGINE_SIZES`.
Each lies in `assets/pictures/<kind>/<name>.png` for its key `<kind>/<name>` (`rel_of`), and `pictures.json` says so. Nothing here reads a picture of the legacy pack.
"""
from __future__ import annotations

import io
import re
from functools import cache

from PIL import Image, ImageDraw, ImageFont

import devlib

# the dev palette: (fill, outline, text) per kind
PALETTE = {
    "sprite": ((46, 160, 160), (14, 70, 70), (255, 255, 255)),
    "deco": ((80, 170, 70), (30, 80, 30), (255, 255, 255)),
    "tile": ((150, 110, 70), (70, 50, 30), (255, 255, 255)),
    "ui": ((140, 90, 190), (60, 30, 90), (255, 255, 255)),
    "background": ((30, 50, 110), (10, 20, 50), (200, 220, 255)),
    "problem": ((230, 140, 40), (110, 60, 10), (20, 20, 20)),
    "current": ((60, 120, 220), (20, 50, 110), (255, 255, 255)),
    "empty": ((0, 0, 0, 0), (255, 255, 255, 255), (255, 255, 255)),
}

# Sizes (width, height) the engine itself assumes, by (folder, id or stem): see piece_model.gd, prompt_sender.gd, title_scene.gd.
PIECE = (24, 20)
SUB = (96, 58)
SENDER = (55, 20)
MINI_SUB = (72, 44)
BEZEL = (616, 72)
PROBLEM_BACKGROUND = (616, 340)
CALCULATOR = (296, 160)
ANSWER_PANEL = (296, 40)
LABEL = (96, 16)
LOG_ROW = (115, 16)

# Roles of the HUD pictures (index = id - 1189), the order of the console bundle. Sizes are dev's own.
HUD_SIZES = {0: BEZEL, 4: (8, 8), 5: (8, 8), 15: (20, 20), 16: (20, 20), 17: (16, 16), 18: (16, 16), 19: (16, 16),
             21: (20, 20), 22: (20, 20), 23: (20, 20), 24: (20, 20)}
# The calculator bundle (b041): item = id - 1781. 0 the calculator, 21 the "Ans:" panel, 1-10 digits, 11 point, 13 slash, 14 minus,
# 15 fraction flag, 16 memory, 17-20 operator markers.
CALC_SIZES = {0: CALCULATOR, 21: ANSWER_PANEL, **{i: (14, 20) for i in range(1, 11)}, 11: (6, 6), 12: (6, 6), 13: (14, 20),
              14: (14, 20), 15: (12, 12), 16: (12, 12), **{i: (12, 12) for i in range(17, 21)}}


PANEL = (292, 296)                                  # the diagram panel: the first picture of each problem type's bundle


@cache
def _numbers() -> dict[str, int | None]:
    """key -> the number the picture has in the inventory (a picture id, a creature or deco slot), None for a key of a plain set."""
    import inventory
    return inventory.load()["pictures"]


@cache
def _bundle_first_ids() -> dict[str, int]:
    """problem art folder -> the smallest picture id in it that has a picture of its own (its picture 0)."""
    import inventory
    import pictures
    return {folder: min(i for i in ids if pictures.home(i) is None) for folder, ids in inventory.load()["problem_art_index"].items()
            if any(pictures.home(i) is None for i in ids)}


@cache
def _folder_of_art(pid: int) -> str:
    import inventory
    return next(folder for folder, ids in inventory.load()["problem_art_index"].items() if pid in ids)


@cache
def _panel_folders() -> set[str]:
    return {"b%03d" % r for r in devlib.problem_art() if r < 900}


def _problem_art_size(folder: str, n: int) -> tuple[int, int]:
    index = n - _bundle_first_ids().get(folder, n)
    if folder == "b078":
        return 240, 240                               # the lock's answer wheel (no problem type has the folder as its own art)
    if folder in _panel_folders():
        if index == 0:
            return PANEL
        if folder == "b077" and 6 <= index <= 9:
            return 140, 140                           # the lock's operand wheel, four turns
        if folder == "b103":                          # the ballast panel: 1 button, 2 3 4 weight slots, 5 6 7 the total
            return (96, 24) if index == 1 else (96, 28)
    return 64, 48


def _match(pattern: str, text: str) -> re.Match[str]:
    """The match of `pattern` in `text`; a picture name the rules do not know is an error."""
    m = re.search(pattern, text)
    if m is None:
        raise ValueError(f"{text!r} does not match {pattern!r}")
    return m


def _required(n: int | None, name: str) -> int:
    """The number of a picture whose rule is computed from it."""
    if n is None:
        raise ValueError(f"{name!r} has no picture number")
    return n


def _slot_size(slot: int, wide: int, high: int) -> tuple[int, int]:
    """A deterministic even size that varies a little with the slot, so that a mix-up of pictures shows."""
    return wide + 8 * (slot % 4), high + 8 * (slot % 3)


def _ui_folder(pid: int) -> str:
    """Which role a picture of the interface has (the importer's folders of assets/ui/, pictures.UI_FOLDERS): it decides the size."""
    import pictures
    return next(folder for folder, ids in pictures.UI_FOLDERS.items() if pid in ids)


def name_of(key: str) -> str:
    return key.split("/", 1)[1]


def rel_of(key: str) -> str:
    """Where dev keeps the picture of `key`: `assets/pictures/<kind>/<name>.png`, so the file is named by its key and by nothing else."""
    return "assets/pictures/%s.png" % key


def spec(key: str) -> tuple[str, int, int]:
    """(kind, width, height) of the picture of `key`."""
    kind, name = key.split("/", 1)
    n = _numbers().get(key)
    if kind == "background":
        return "background", 640, 400
    if kind == "tile":
        return ("tile", 16, 16) if name == "invisible_wall" else ("tile", 128, 128)      # 8 x 8 cells of 16 x 16
    if kind == "frame":
        if name.startswith("sub_"):
            index = int(name[len("sub_"):])
            if index <= 7:
                return "sprite", *SUB
            if index == 8:
                return "sprite", 16, 8
            return "sprite", 12, 12
        if name.startswith("piece_"):
            return "sprite", *PIECE
        if name.startswith("station_"):
            return "sprite", 64, 64
        if name.startswith("fx_"):
            side = 8 + 2 * int(_match(r"(\d+)$", name).group(1))
            return "sprite", side, side
        slot = _required(n, key)
        if slot < 28:
            return "sprite", *_slot_size(slot, 32, 24)
        if slot < 35:
            side = 16 + 8 * (slot - 28)                       # the ink burst grows
            return "sprite", side, side
        return "sprite", *_slot_size(slot, 40, 32)
    if kind == "deco":
        return "deco", *_slot_size(_required(n, key), 24, 32)
    if kind == "ui_picture":
        pid = _required(n, key)
        folder = _ui_folder(pid)
        if folder == "hud":
            return "ui", *HUD_SIZES.get(pid - 1189, LABEL)
        if folder == "prompt":
            return "ui", *SENDER
        if folder == "map":
            return "ui", 640, 400
        if folder == "title":
            if "sky" in name or name == "ui_1039":
                return "ui", 640, 200
            if "sea" in name:
                return "ui", 640, 120
            if "waves" in name:
                return "ui", 640, 40
            if "frame" in name:
                return "ui", 320, 200
            if "scanner" in name:
                return "ui", 100, 22
            return "ui", 160, 32
        big = ("background", "sky", "sea", "frame_", "americas", "cloud_swirl", "galaxy", "earth")
        if any(b in name for b in big):
            return "ui", 320, 200
        if "ship_mini_sub" in name:
            return "ui", *MINI_SUB
        if "ship_" in name or "heli_body" in name or "deck_ship" in name:
            return "ui", 160, 64
        if "caption" in name or "heading" in name:
            return "ui", 240, 24
        if "button" in name:
            return "ui", 96, 24
        if "console" in name:
            return "ui", 120, 80
        if "light" in name:
            return "ui", 16, 16
        return "ui", 48, 48
    if kind == "problem_art":
        pid = _required(n, key)
        folder = _folder_of_art(pid)
        if folder == "single":
            return "problem", *{1780: PROBLEM_BACKGROUND, 1803: PANEL, 1864: PANEL, 1979: (640, 400)}.get(pid, (64, 32))
        if folder == "b041":
            return "problem", *CALC_SIZES.get(pid - 1781, (14, 20))
        if "log_scan" in name:
            return "problem", *LOG_ROW
        return "problem", *_problem_art_size(folder, pid)
    raise ValueError("no picture rule for " + key)


@cache
def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(devlib.FONT), size)


def _fit(draw: ImageDraw.ImageDraw, label: str, width: int, height: int) -> tuple[ImageFont.FreeTypeFont, list[str]]:
    """The biggest font (at most 22 px) in which `label`, broken at underscores, fits the box; the smallest as a last resort."""
    words = label.replace("_", " _").split(" ")
    for size in range(min(40 if height >= 200 else 22, max(height - 2, 6)), 5, -1):
        font = _font(size)
        lines, line = [], ""
        for w in words:
            trial = line + w
            if draw.textlength(trial, font=font) <= width - 4 or not line:
                line = trial
            else:
                lines.append(line)
                line = w
        lines.append(line)
        if len(lines) * (size + 1) <= height - 2 and all(draw.textlength(s, font=font) <= width - 2 for s in lines):
            return font, lines
    return _font(6), [label]


def draw_picture(key: str) -> bytes:
    kind, w, h = spec(key)
    stem = name_of(key)
    fill, outline, ink = PALETTE[kind]
    if kind == "tile":
        return _tile_png(stem, w, h)
    img = Image.new("RGBA", (w, h), fill + (255,))
    d = ImageDraw.Draw(img)
    if kind == "sprite" and stem.startswith(("piece_", "fx_")) or kind == "sprite" and "bubble" in stem:
        d.rectangle([0, 0, w - 1, h - 1], fill=(0, 0, 0, 0))
        d.ellipse([0, 0, w - 1, h - 1], fill=fill + (255,), outline=outline + (255,))
    else:
        d.rectangle([0, 0, w - 1, h - 1], outline=outline + (255,))
    if w >= 16 and h >= 12:
        font, lines = _fit(d, stem, w, h)
        total = len(lines) * (font.size + 1)
        y = (h - total) // 2
        for line in lines:
            d.text(((w - d.textlength(line, font=font)) // 2, y), line, font=font, fill=ink + (255,))
            y += font.size + 1
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=False)
    return buf.getvalue()


# --- the tile atlases ---------------------------------------------------------------------------------------------

DIRECTIONS = ["NW", "N", "NE", "W", "E", "SW", "S", "SE"]               # the order of the currents atlas columns
ZONE_WALLS = [(150, 110, 70), (120, 120, 150), (170, 150, 110), (90, 140, 90), (140, 90, 90)]


def _tile_png(name: str, w: int, h: int) -> bytes:
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = _font(9)
    if name == "invisible_wall":
        d.rectangle([0, 0, 15, 15], fill=(255, 40, 160, 90), outline=(255, 40, 160, 255))
        d.text((5, 1), "I", font=font, fill=(255, 255, 255, 255))
    elif name == "currents":
        for strength in range(8):
            for direction, text in enumerate(DIRECTIONS):
                x0, y0 = direction * 16, strength * 16
                shade = 80 + strength * 20
                d.rectangle([x0, y0, x0 + 15, y0 + 15], fill=(40, 90, shade, 255), outline=(255, 255, 255, 255))
                d.text((x0 + 2, y0 + 1), text, font=font, fill=(255, 255, 255, 255))
    else:
        zone = int(_match(r"zone(\d)", name).group(1))
        base = ZONE_WALLS[zone]
        for k in range(1, 64):                                          # cell 0 is "nothing": it stays empty
            x0, y0 = (k % 8) * 16, (k // 8) * 16
            shade = tuple(min(255, c + 12 * (k % 3)) for c in base)
            d.rectangle([x0, y0, x0 + 15, y0 + 15], fill=shade + (255,), outline=(60, 40, 20, 255))
            d.text((x0 + 4, y0 + 1), "W", font=font, fill=(255, 255, 255, 255))
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=False)
    return buf.getvalue()


def write_all(keys: list[str]) -> int:
    """The picture of every key, at `rel_of(key)`, each with its `.import` stub."""
    for key in keys:
        path = devlib.DEV / rel_of(key)
        devlib.write_bytes(path, draw_picture(key))
        devlib.write_sidecar(path)
    return len(keys)
