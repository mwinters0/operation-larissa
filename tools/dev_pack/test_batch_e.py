"""Batch E's generated fixture: the tiny SoundFont the music tests play the dev MIDI files through (godot/tests/fixtures/tiny_soundfont.sf2).

    uv run pytest tools/dev_pack/test_batch_e.py -q
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_sectors import batch_e


def chunks(data: bytes) -> list[tuple[bytes, bytes]]:
    out, at = [], 0
    while at < len(data):
        tag, size = data[at:at + 4], struct.unpack("<I", data[at + 4:at + 8])[0]
        out.append((tag, data[at + 8:at + 8 + size]))
        at += 8 + size + (size & 1)
    return out


def test_the_soundfont_is_a_riff_sfbk_with_the_three_lists():
    data = batch_e.soundfont_bytes()
    riff = chunks(data)
    assert len(riff) == 1 and riff[0][0] == b"RIFF" and riff[0][1][:4] == b"sfbk"
    lists = chunks(riff[0][1][4:])
    assert [(tag, body[:4]) for tag, body in lists] == [(b"LIST", b"INFO"), (b"LIST", b"sdta"), (b"LIST", b"pdta")]
    assert len(data) < 16 * 1024                              # a few KB, not a sound library


def test_the_soundfont_has_a_preset_for_every_program_and_one_looped_sample():
    pdta = dict(chunks(chunks(chunks(batch_e.soundfont_bytes())[0][1][4:])[2][1][4:]))
    assert len(pdta[b"phdr"]) == 38 * (batch_e.SF_PROGRAMS + 1)           # (and the terminal record)
    assert len(pdta[b"shdr"]) == 46 * 2
    programs = [struct.unpack("<H", pdta[b"phdr"][38 * i + 20:38 * i + 22])[0] for i in range(batch_e.SF_PROGRAMS)]
    assert programs == list(range(batch_e.SF_PROGRAMS))
    start, end, loop_start, loop_end, rate, key = struct.unpack("<IIIIIB", pdta[b"shdr"][20:41])
    assert (start, end, loop_start, loop_end, rate, key) == (0, batch_e.SF_CYCLE, 0, batch_e.SF_CYCLE, batch_e.SF_RATE, 60)
    assert struct.unpack("<HHHH", pdta[b"igen"][:8]) == (54, 1, 53, 0)     # loops continuously, then the sample


def test_the_committed_fixture_is_what_the_generator_makes():
    assert batch_e.SOUNDFONT.read_bytes() == batch_e.soundfont_bytes()
