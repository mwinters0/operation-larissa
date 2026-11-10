# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow"]
# ///
"""Register a screenshot of the ORIGINAL game against the port's art.

A hand-cropped screenshot is the 640x400 game view plus an unknown amount of padding (and sometimes
a few missing rows at the top). The Windows captures are NOT pixel exact: the original's dither is
smoothed (thousands of in-between colours), so exact matching fails. This script therefore uses
normalised cross-correlation and blurred comparison. It finds
  * the SCALE (1.0 for a 1:1 capture; others are tried by resampling the console template),
  * the crop OFFSET: the image position of window pixel (0, 0), from the console strip
    (ui_1189, drawn at window (12, 324)); typically good to +-0 px,
  * the SCREEN: the background (assets/backgrounds/bg_sSS_NN.png, drawn at window (16, 32)) that
    agrees best with the blurred playfield. Only water-coloured pixels of the screenshot are judged
    (rock tiles, decos, creatures and the sub are drawn over the background): a true match scores
    ~0.7-0.9 (fraction of those pixels within tolerance). Other sectors reuse similar cave shapes, so
    pass --sector when the runner-up is close; the script prints the candidates so you can judge.

Window coordinates are the original's: playfield = window - (16, 32); image = window + offset.

Usage (repo root):
  uv run tools/analysis/register_screenshot.py IMG
  uv run tools/analysis/register_screenshot.py IMG --json
  uv run tools/analysis/register_screenshot.py IMG --sector 0              # restrict the screen search
  uv run tools/analysis/register_screenshot.py IMG --offset 14 -7          # skip the console search
  uv run tools/analysis/register_screenshot.py IMG --locate <the legacy pack>/assets/sprites/sub/sub_00.png [--flip]
      # window positions where an RGBA sprite (alpha 0 ignored) matches best (masked SSD); the
      # 'rms' column is the colour error (about <20 is a true hit); several --locate are allowed
  uv run tools/analysis/register_screenshot.py IMG --crop out.png
      # write the 640x400 window cut out of the screenshot (padding removed, missing rows black)
"""

# (the PEP 723 deps above are not visible to a bare `uvx pyright`; `uvx --with numpy --with pillow pyright` type-checks fully)
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING

import numpy as np
from PIL import Image, ImageFilter

if TYPE_CHECKING:  # only for annotations (all annotations are lazy: `from __future__ import annotations`)
    from numpy.typing import NDArray

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "import"))
from common import ASSETS      # the legacy pack's assets/ (the importer's output; common.legacy_root says where)
CONSOLE_PNG = ASSETS / "ui" / "hud" / "ui_1189.png"
CONSOLE_POS = (12, 324)  # window pixels
PLAYFIELD_POS = (16, 32)
PLAYFIELD_SIZE = (608, 288)
WINDOW_SIZE = (640, 400)
SCALES = (1.0, 0.75, 2 / 3, 0.5, 1.25, 1.5, 2.0)
BLUR = 2.0
TOLERANCE = 30  # summed |dR|+|dG|+|dB| after blurring that still counts as "equal"



@dataclass
class ScreenScore:
    sector: int
    screen: int
    match: float
    file: str


@dataclass
class Hit:
    window_x: int
    window_y: int
    playfield_x: int
    playfield_y: int
    rms: float


@dataclass
class Registration:
    image: str
    image_size: tuple[int, int]
    scale: float = 1.0
    offset: tuple[int, int] = (0, 0)  # image position of window (0, 0), in 1:1 pixels
    console_ncc: float = 0.0
    screens: list[ScreenScore] = field(default_factory=list)
    locate: dict[str, list[Hit]] = field(default_factory=dict)

    @property
    def screen(self) -> ScreenScore | None:
        if self.screens and self.screens[0].match >= 0.25:
            return self.screens[0]
        return None


def gray(im: Image.Image) -> NDArray[np.float32]:
    return np.asarray(im.convert("L"), dtype=np.float32)


def xcorr(a: NDArray[np.float64], b: NDArray[np.float64]) -> NDArray[np.float64]:
    """Valid-mode cross-correlation of image a with template b (FFT)."""
    h, w = a.shape
    th, tw = b.shape
    fa = np.fft.rfft2(a)
    fb = np.fft.rfft2(b, s=a.shape)
    full = np.fft.irfft2(fa * np.conj(fb), s=a.shape)
    return full[: h - th + 1, : w - tw + 1]


def box_sum(a: NDArray[np.float64], th: int, tw: int) -> NDArray[np.float64]:
    c = np.pad(a, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    return c[th:, tw:] - c[:-th, tw:] - c[th:, :-tw] + c[:-th, :-tw]


def ncc(img: NDArray[np.float32], tpl: NDArray[np.float32]) -> NDArray[np.float64]:
    """Normalised cross-correlation map (same value range as cv2.TM_CCOEFF_NORMED)."""
    a = img.astype(np.float64)
    t = tpl.astype(np.float64)
    th, tw = t.shape
    n = th * tw
    t0 = t - t.mean()
    num = xcorr(a, t0)
    s1 = box_sum(a, th, tw)
    s2 = box_sum(a * a, th, tw)
    var = np.maximum(s2 - s1 * s1 / n, 1e-9)
    return num / np.sqrt(var * float((t0 * t0).sum()) + 1e-9)


def find_offset(img: Image.Image) -> tuple[float, tuple[int, int], float]:
    """Return (scale, offset, ncc) by matching the console strip at several scales."""
    console = Image.open(CONSOLE_PNG).convert("RGBA")
    gi = gray(img)
    best = (1.0, (0, 0), -1.0)
    for scale in SCALES:
        # the screenshot is scaled by `scale` relative to the game, so scale the template instead
        tw, th = round(console.width * scale), round(console.height * scale)
        if tw >= img.width or th >= img.height:
            continue
        tpl = gray(console.resize((tw, th), Image.Resampling.BOX if scale < 1 else Image.Resampling.NEAREST))
        m = ncc(gi, tpl)
        y, x = np.unravel_index(int(np.argmax(m)), m.shape)
        score = float(m[y, x])
        if score > best[2]:
            ox = round((int(x) - CONSOLE_POS[0] * scale) / scale)
            oy = round((int(y) - CONSOLE_POS[1] * scale) / scale)
            best = (scale, (ox, oy), score)
        if score > 0.7 and scale == 1.0:
            break
    return best


def blurred_rgb(im: Image.Image) -> NDArray[np.int32]:
    return np.asarray(im.convert("RGB").filter(ImageFilter.GaussianBlur(BLUR)), dtype=np.int32)


def rank_screens(img: Image.Image, offset: tuple[int, int], sector: int | None, top: int = 5) -> list[ScreenScore]:
    px, py = PLAYFIELD_POS[0] + offset[0], PLAYFIELD_POS[1] + offset[1]
    canvas = Image.new("RGB", PLAYFIELD_SIZE, (0, 0, 0))
    canvas.paste(img.convert("RGB"), (-px, -py))
    shot = blurred_rgb(canvas)
    valid = np.zeros((PLAYFIELD_SIZE[1], PLAYFIELD_SIZE[0]), dtype=bool)
    valid[max(0, -py) : max(0, min(PLAYFIELD_SIZE[1], img.height - py)), max(0, -px) : max(0, min(PLAYFIELD_SIZE[0], img.width - px))] = True
    pat = f"bg_s{sector:02d}_*.png" if sector is not None else "bg_s*_*.png"
    out: list[ScreenScore] = []
    for f in sorted((ASSETS / "backgrounds").glob(pat)):
        d = np.abs(shot - blurred_rgb(Image.open(f))).sum(axis=2)
        # only judge pixels that look like water in the screenshot: rock tiles, decos and creatures
        # are drawn over the background and would otherwise count against the right screen
        water = valid & (shot[..., 2] > shot[..., 0] + 60)
        frac = float(((d <= TOLERANCE) & water).sum()) / max(int(water.sum()), 1)
        s, n = f.stem[4:].split("_")
        out.append(ScreenScore(int(s[1:]), int(n), round(frac, 4), f.name))
    out.sort(key=lambda s: -s.match)
    return out[:top]


def locate(img: Image.Image, offset: tuple[int, int], sprite: Path, flip: bool, count: int = 5) -> list[Hit]:
    """Positions (window coordinates of the sprite's top-left) with the lowest masked colour error."""
    sp = Image.open(sprite).convert("RGBA")
    if flip:
        sp = sp.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    t = np.asarray(sp, dtype=np.float64)
    m = (t[..., 3] > 0).astype(np.float64)
    n = float(m.sum())
    if n == 0:
        return []
    a = np.asarray(img.convert("RGB"), dtype=np.float64)
    ssd: NDArray[np.float64] | None = None
    for c in range(3):
        ic, tc = a[..., c], t[..., c] * m
        term = xcorr(ic * ic, m) - 2 * xcorr(ic, tc) + float((tc * tc).sum())
        ssd = term if ssd is None else ssd + term
    assert ssd is not None
    rms = np.sqrt(np.maximum(ssd, 0) / (3 * n))
    hits: list[Hit] = []
    work = rms.copy()
    th, tw = m.shape
    for _ in range(count):
        y, x = np.unravel_index(int(np.argmin(work)), work.shape)
        hits.append(Hit(int(x) - offset[0], int(y) - offset[1], int(x) - offset[0] - 16, int(y) - offset[1] - 32, round(float(work[y, x]), 1)))
        work[max(0, y - th // 2) : y + th // 2 + 1, max(0, x - tw // 2) : x + tw // 2 + 1] = np.inf
    return hits


def crop_window(img: Image.Image, offset: tuple[int, int], out: Path) -> None:
    canvas = Image.new("RGBA", WINDOW_SIZE, (0, 0, 0, 255))
    canvas.paste(img.convert("RGBA"), (-offset[0], -offset[1]))
    canvas.save(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image", type=Path)
    ap.add_argument("--sector", type=int, default=None, help="only test backgrounds of this sector")
    ap.add_argument("--offset", type=int, nargs=2, metavar=("X", "Y"), default=None, help="known offset; skips the console search")
    ap.add_argument("--json", action="store_true", help="print machine-readable JSON only")
    ap.add_argument("--locate", type=Path, action="append", default=[], help="sprite PNG to find (window coordinates)")
    ap.add_argument("--flip", action="store_true", help="with --locate: search the mirrored sprite")
    ap.add_argument("--crop", type=Path, default=None, help="write the screenshot cropped to the 640x400 window")
    args = ap.parse_args()

    src = Image.open(args.image).convert("RGBA")
    reg = Registration(args.image.name, (src.width, src.height))
    if args.offset is not None:
        reg.offset = (int(args.offset[0]), int(args.offset[1]))
        img = src
    else:
        scale, reg.offset, reg.console_ncc = find_offset(src)
        reg.scale = scale
        img = src if scale == 1.0 else src.resize((round(src.width / scale), round(src.height / scale)), Image.Resampling.BOX)
    reg.screens = rank_screens(img, reg.offset, args.sector)
    for sp in args.locate:
        reg.locate[sp.name] = locate(img, reg.offset, sp, args.flip)
    if args.crop is not None:
        crop_window(img, reg.offset, args.crop)

    if args.json:
        json.dump(asdict(reg), sys.stdout, indent=2)
        print()
        return 0
    ox, oy = reg.offset
    print(f"{reg.image} {reg.image_size[0]}x{reg.image_size[1]}  scale {reg.scale}  console NCC {reg.console_ncc:.3f}")
    print(f"offset (image position of window 0,0): {ox}, {oy}; window in image ({ox}, {oy})-({ox + 640}, {oy + 400});")
    print(f"playfield origin in image ({ox + 16}, {oy + 32})")
    best = reg.screen
    if best is None:
        print("screen: NO background matches (problem screen, map, or wrong scale/offset)")
    else:
        print(f"screen: sector {best.sector} screen {best.screen} ({best.file}) match {best.match}")
    for s in reg.screens:
        print(f"  candidate {s.file}: {s.match}")
    for name, hits in reg.locate.items():
        for h in hits:
            print(f"  locate {name}: window ({h.window_x}, {h.window_y}) playfield ({h.playfield_x}, {h.playfield_y}) rms {h.rms}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
