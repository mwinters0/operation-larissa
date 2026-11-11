# /// script
# requires-python = ">=3.12"
# dependencies = ["fonttools"]
# ///
# pyright: reportMissingImports=false, reportUnknownMemberType=false, reportUnknownVariableType=false, reportUnknownArgumentType=false
"""Makes the tiny TrueType font the tests give a skin pack as its `hud_font` (`godot/tests/mods/skin_data/skin/hud.ttf`).

    uv run tools/make_test_font.py [out.ttf]     # default: the fixture's path

Every printable ASCII character is a plain block (capitals and digits tall, lowercase short, punctuation small), so the font is valid and easy to tell
from the project's own, owns no design of anyone and is a few kilobytes. It is made here, from nothing, and is released as CC0 (the licence is in its name
table): a test font that is committed must be free of the original's content and of anyone's licence. Not part of the importer or the game.

Teaches: what the least TrueType font is (glyf outlines, a cmap, metrics and names) and building one with fontTools' FontBuilder.
"""
import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "godot" / "tests" / "mods" / "skin_data" / "skin" / "hud.ttf"
UNITS = 1000
ASCENT, DESCENT = 800, -200
ADVANCE = 600


def block(top: int, left: int = 80, right: int = 520) -> object:
    pen = TTGlyphPen(None)
    pen.moveTo((left, 0))
    pen.lineTo((left, top))
    pen.lineTo((right, top))
    pen.lineTo((right, 0))
    pen.closePath()
    return pen.glyph()


def height(char: str) -> int:
    if char.isupper() or char.isdigit():
        return 700
    if char.islower():
        return 480
    return 240


def build(out: Path) -> None:
    chars = [chr(c) for c in range(0x21, 0x7F)]
    names = [".notdef", "space"] + ["glyph%02x" % ord(c) for c in chars]
    builder = FontBuilder(UNITS, isTTF=True)
    builder.setupGlyphOrder(names)
    builder.setupCharacterMap({0x20: "space", **{ord(c): "glyph%02x" % ord(c) for c in chars}})
    glyphs = {".notdef": block(700, 60, 540), "space": TTGlyphPen(None).glyph()}
    for char in chars:
        glyphs["glyph%02x" % ord(char)] = block(height(char))
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({name: (ADVANCE, 80 if name not in ("space",) else 0) for name in names})
    builder.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    builder.setupNameTable({
        "familyName": "Larissa Test Block",
        "styleName": "Regular",
        "copyright": "Made by tools/make_test_font.py of Operation Larissa. Public domain (CC0 1.0).",
        "licenseDescription": "CC0 1.0 Universal: no rights reserved.",
    })
    builder.setupOS2(sTypoAscender=ASCENT, sTypoDescender=DESCENT, usWinAscent=ASCENT, usWinDescent=-DESCENT, achVendID="LRSA")
    builder.setupPost()
    builder.setupHead(unitsPerEm=UNITS)
    out.parent.mkdir(parents=True, exist_ok=True)
    builder.save(str(out))


if __name__ == "__main__":
    build(Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT)
