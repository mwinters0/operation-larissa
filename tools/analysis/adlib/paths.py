"""Where the research scripts of this folder find their inputs and put their outputs.

Teaches: nothing the game contains is written into the scripts; they read it at run time. `extracted/` is the importer's first
readable form of the ISO (`docs/play/LEGACY.md`).

Environment variables:
  LARISSA_EXTRACTED  the importer's `extracted/` folder           (default: `extracted/` of this repository)
  ADLIB_OUT          where the scripts write their results        (default: `build/adlib/` of this repository, git-ignored)
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EXTRACTED = Path(os.environ.get("LARISSA_EXTRACTED", ROOT / "extracted"))
MUSIC = EXTRACTED / "music"                       # B*.MID and E*.MID
FM_PATCHES = EXTRACTED / "sounds" / "fm_patches_undecoded"   # NE0SOUND_9000.bin ... NE0SOUND_9190.bin
OUT = Path(os.environ.get("ADLIB_OUT", ROOT / "build" / "adlib"))


def ensure_utf8() -> None:
    """Python's UTF-8 mode on Windows (`tools/utf8_mode.py`); every script calls it first."""
    tools = str(ROOT / "tools")
    if tools not in sys.path:
        sys.path.append(tools)
    import utf8_mode
    utf8_mode.ensure()


def out_dir() -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    return OUT
