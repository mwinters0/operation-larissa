"""I7 batch E: test sectors 180-199 (and the campaign `test_e`, if a test needs one): plumbing: audio, names, assets, catalogs, the pack chain.

This module is the batch's alone (tools/dev_pack/README.md): no other batch edits it and it edits no other batch's. `write_all` is called by
`make_dev_pack.py` (stage "data") after the dev tour. Make a sector with `dev_sectors.standard_sector` or `finale_sector`, change what the test
needs, and write it with `test_sectors.write_sector("e", spec)`, which refuses a number outside the range:

    spec = dev_sectors.standard_sector(180, zone=2, creatures=0)
    spec.screens[4].fill(10, 6, 20, 6, dev_sectors.wall())
    count += test_sectors.write_sector("e", spec, dev_root)

A campaign (`test_sectors.write_campaign("e", ...)`) shows in `Catalog.campaigns()` of every suite, so add one only when the test needs it.
"""
from __future__ import annotations

import math
import struct
from pathlib import Path

import dev_sectors
import test_sectors
from dev_sectors import Foe

BATCH = "e"

# The sectors (the tests name them in `godot/tests/engine/dev_pack.gd`: `DevPack.test_sector("e", offset)`).
FINALE_SECTOR = 180        # offset 0: a finale for the scratch packs' campaigns: the treasure on the finale screen (10)

TREASURE_SCRIPT = """; Dev pack - sector %02d. %s
; The treasure: a creature that does no damage; when the sub touches it, it sets flag 15, which the game reads: with the sub on the
; sector's finale screen (header field finale_screen) the closing sequence starts. docs/create/FOE_SCRIPTING.md, "The finale: bit 15".

treasure_start:
    Set_Frame 35
treasure_idle:
    Wait_Next_Tick
    Jump_To treasure_idle

treasure_hit:
    Set_Flag 15
    Play_Sound 3
treasure_stuck:
    Wait_Next_Tick
    Jump_To treasure_stuck

treasure_ink:
    Return
"""


def finale_with_treasure(index: int) -> dev_sectors.SectorSpec:
    """A finale sector for a scratch pack's campaign to copy: the standard one with a treasure on the finale screen (10), which starts the closing."""
    comment = "The treasure is on the finale screen, 10."
    spec = dev_sectors.standard_sector(index, 4, creatures=0, finale=True, comment=comment)
    spec.foes = [Foe(10, (300, 250), 35, 35, 36, damage=0, start="treasure_start", hit="treasure_hit", ink="treasure_ink")]
    spec.script = TREASURE_SCRIPT % (index, comment)
    spec.finale_screen = 10
    return spec

# The tiny SoundFont the music tests play the dev MIDI files through (godot/tests/fixtures/tiny_soundfont.sf2): one sine wave, looped, for every
# General MIDI program of bank 0. It is not part of the pack, so `write_all` does not write it; run this module to make it again:
#     uv run python -c "import sys; sys.path.insert(0, 'tools/dev_pack'); from test_sectors import batch_e; print(batch_e.write_soundfont())"
SOUNDFONT = Path(__file__).resolve().parents[3] / "godot" / "tests" / "fixtures" / "tiny_soundfont.sf2"
SF_CYCLE = 64                      # sample frames in one sine period
SF_RATE = 16744                    # 64 frames at 16744 Hz: middle C (261.6 Hz) at original pitch 60
SF_PROGRAMS = 128


def _riff(tag: bytes, body: bytes) -> bytes:
    return tag + struct.pack("<I", len(body)) + body + (b"\0" if len(body) % 2 else b"")


def _name(text: str) -> bytes:
    return text.encode("ascii").ljust(20, b"\0")


def soundfont_bytes() -> bytes:
    """A SoundFont 2 file of a few KB: preset p (bank 0, programs 0-127) plays instrument 0, one looped sine wave."""
    sine = [round(20000 * math.sin(2 * math.pi * i / SF_CYCLE)) for i in range(SF_CYCLE)]
    smpl = struct.pack("<%dh" % (SF_CYCLE + 46), *sine, *([0] * 46))               # (the format wants 46 silent frames after a sample)
    info = _riff(b"ifil", struct.pack("<HH", 2, 1)) + _riff(b"isng", b"EMU8000\0") + _riff(b"INAM", b"Neptune tiny test font\0\0")
    phdr = b"".join(_name("Sine %d" % p) + struct.pack("<HHHIII", p, 0, p, 0, 0, 0) for p in range(SF_PROGRAMS))
    phdr += _name("EOP") + struct.pack("<HHHIII", 0, 0, SF_PROGRAMS, 0, 0, 0)
    pbag = b"".join(struct.pack("<HH", p, 0) for p in range(SF_PROGRAMS + 1))
    pgen = b"".join(struct.pack("<HH", 41, 0) for _ in range(SF_PROGRAMS)) + struct.pack("<HH", 0, 0)       # generator 41: instrument 0
    inst = _name("Tiny sine") + struct.pack("<H", 0) + _name("EOI") + struct.pack("<H", 1)
    ibag = struct.pack("<HH", 0, 0) + struct.pack("<HH", 2, 0)
    igen = struct.pack("<HH", 54, 1) + struct.pack("<HH", 53, 0) + struct.pack("<HH", 0, 0)                 # sampleModes 1 (loop), sampleID 0
    shdr = _name("Sine") + struct.pack("<IIIIIBbHH", 0, SF_CYCLE, 0, SF_CYCLE, SF_RATE, 60, 0, 0, 1)
    shdr += _name("EOS") + struct.pack("<IIIIIBbHH", 0, 0, 0, 0, 0, 0, 0, 0, 0)
    mod = b"\0" * 10
    pdta = (_riff(b"phdr", phdr) + _riff(b"pbag", pbag) + _riff(b"pmod", mod) + _riff(b"pgen", pgen) + _riff(b"inst", inst)
            + _riff(b"ibag", ibag) + _riff(b"imod", mod) + _riff(b"igen", igen) + _riff(b"shdr", shdr))
    body = b"sfbk" + _riff(b"LIST", b"INFO" + info) + _riff(b"LIST", b"sdta" + _riff(b"smpl", smpl)) + _riff(b"LIST", b"pdta" + pdta)
    return _riff(b"RIFF", body)


def write_soundfont(path: Path = SOUNDFONT) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(soundfont_bytes())
    return path


def write_all(dev_root: Path) -> int:
    """Writes this batch's sectors (and campaign) below `dev_root`; returns how many files were written or checked."""
    count = test_sectors.write_sector(BATCH, finale_with_treasure(FINALE_SECTOR), dev_root)
    return count
