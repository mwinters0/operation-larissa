"""The dev pack's synthesized music and MIDI files: numpy and a few integers, no samples, nothing of the original.

A song is a short loop of a few notes. Its key, mode, tempo and melody come from its position in the song list (`index`
0-9), so every song differs and the same index always gives the same bytes. The General MIDI set sounds like a soft bell
(sine and two overtones); the AdLib set is squarer (a pulse wave), like the cheap FM cards it stands for.
"""
from __future__ import annotations

import struct

import numpy as np

RATE = 44100
MAJOR = (0, 2, 4, 5, 7, 9, 11)
MINOR = (0, 2, 3, 5, 7, 8, 10)
TARGET_SECONDS = 14.0           # a song, with its spoken name, lasts about this long (10-20 s)
MIDI_TICKS = 96                 # per quarter note in the MIDI files


class Song:
    """What makes song `index` (0-9) itself: a root note, a mode, a tempo and a melody of 16 eighth notes."""

    def __init__(self, index: int):
        self.index = index
        self.root = 48 + (index * 7) % 12                 # C3..B3: 7 and 12 share no factor, so ten songs give ten keys
        self.scale = MAJOR if index % 2 == 0 else MINOR
        self.bpm = 72 + 8 * index                         # 72..144, all different
        self.melody = self._melody()                      # 16 entries: a MIDI note number, or None for a rest

    def _melody(self) -> list[int | None]:
        state, degree, notes = (self.index + 1) * 7919, 0, []
        for step in range(16):
            state = (state * 1103515245 + 12345) & 0x7FFFFFFF           # a small LCG: the same walk every run
            move = (state >> 16) % 5 - 2                                 # -2..+2 scale steps
            degree = max(0, min(10, degree + move))
            octave, within = divmod(degree, 7)
            note = self.root + 12 + 12 * octave + self.scale[within]
            notes.append(None if step % 4 == 3 and (state >> 8) % 3 == 0 else note)
        notes[0] = self.root + 12                                         # always starts on the tonic
        return notes

    def bass(self, bar: int) -> int:
        """The bass note of bar `bar`: the root, then the fifth, and so on."""
        return self.root - 12 + (7 if bar % 2 else 0)

    @property
    def beat_seconds(self) -> float:
        return 60.0 / self.bpm


def frequency(note: int) -> float:
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def tone(note: int, seconds: float, adlib: bool, volume: float) -> np.ndarray:
    """One note: a bell (sine plus overtones) or, for the AdLib set, a pulse wave; both with a fast attack and a decay."""
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    phase = 2 * np.pi * frequency(note) * t
    if adlib:
        wave = np.where(np.sin(phase) >= 0.0, 1.0, -1.0) * 0.55
        decay = np.exp(-3.0 * t / seconds)
    else:
        wave = np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.15 * np.sin(3 * phase)
        decay = np.exp(-4.5 * t / seconds)
    attack = np.minimum(1.0, t / 0.005)                                   # 5 ms ramp: no click at the start
    release = np.minimum(1.0, (seconds - t) / 0.01)                       # 10 ms at the end
    return (volume * wave * decay * attack * release).astype(np.float64)


def loop(song: Song, adlib: bool, seconds: float) -> np.ndarray:
    """The song's music (no speech) as float samples: whole bars of 4 beats, as many as fit in `seconds`."""
    bar_seconds = 4 * song.beat_seconds
    bars = max(2, int(seconds / bar_seconds))
    out = np.zeros(int(bars * bar_seconds * RATE) + RATE)
    eighth = song.beat_seconds / 2
    for bar in range(bars):
        start = bar * bar_seconds
        bass = tone(song.bass(bar), 2 * song.beat_seconds, adlib, 0.30)
        for half in range(2):
            at = int((start + half * 2 * song.beat_seconds) * RATE)
            out[at:at + bass.size] += bass
        for step in range(8):
            note = song.melody[(bar % 2) * 8 + step]
            if note is None:
                continue
            at = int((start + step * eighth) * RATE)
            hit = tone(note, eighth * 1.6, adlib, 0.22)
            out[at:at + hit.size] += hit
    return out[:int(bars * bar_seconds * RATE)]


def resample(samples: np.ndarray, from_rate: int, to_rate: int) -> np.ndarray:
    """Linear interpolation: good enough for developer speech."""
    if from_rate == to_rate:
        return samples
    n = round(samples.size * to_rate / from_rate)
    return np.interp(np.arange(n) * from_rate / to_rate, np.arange(samples.size), samples)


def render_song(index: int, adlib: bool, speech: np.ndarray, speech_rate: int) -> np.ndarray:
    """Mono float samples at RATE: the spoken name (`speech`: float -1..1 at `speech_rate`), a short pause, then the loop.
    Whole length is about TARGET_SECONDS. Peak is kept at 0.9 so the encoder cannot clip."""
    song = Song(index)
    voice = resample(speech, speech_rate, RATE)
    voice = voice / max(1e-9, float(np.max(np.abs(voice)))) * 0.8 if voice.size else voice
    pause = np.zeros(int(0.25 * RATE))
    body = loop(song, adlib, max(4 * song.beat_seconds * 2, TARGET_SECONDS - (voice.size + pause.size) / RATE))
    mix = np.concatenate([voice, pause, body])
    peak = float(np.max(np.abs(mix)))
    return mix * (0.9 / peak) if peak > 0.9 else mix


# ---- MIDI files ----------------------------------------------------------------------------------------------------

def vlq(value: int) -> bytes:
    """A MIDI variable-length quantity."""
    out = [value & 0x7F]
    value >>= 7
    while value:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    return bytes(reversed(out))


def midi_bytes(index: int, adlib: bool) -> bytes:
    """A standard MIDI file (format 0, one track) with song `index`'s melody twice: a few notes. The General MIDI set plays
    a piano (program 0), the AdLib set a square lead (program 80)."""
    song = Song(index)
    eighth = MIDI_TICKS // 2
    track = bytearray()
    track += b"\x00\xff\x51\x03" + (60_000_000 // song.bpm).to_bytes(3, "big")        # tempo, microseconds per quarter
    track += b"\x00\xc0" + bytes([80 if adlib else 0])                                # program change on channel 0
    wait = 0
    for note in song.melody * 2:
        if note is None:
            wait += eighth
            continue
        track += vlq(wait) + bytes([0x90, note, 90]) + vlq(eighth) + bytes([0x80, note, 0])
        wait = 0
    track += vlq(wait) + b"\xff\x2f\x00"
    return b"MThd" + struct.pack(">IHHH", 6, 0, 1, MIDI_TICKS) + b"MTrk" + struct.pack(">I", len(track)) + bytes(track)


def parse_midi(data: bytes) -> dict:
    """Just enough of a reader for the tests: the header and the notes (note-on events with a velocity)."""
    assert data[:4] == b"MThd" and data[14:18] == b"MTrk"
    _size, fmt, tracks, division = struct.unpack(">IHHH", data[4:14])
    length = struct.unpack(">I", data[18:22])[0]
    track = data[22:22 + length]
    assert len(data) == 22 + length, "the track length is wrong"
    i, notes, tempo, ended = 0, [], None, False
    while i < len(track):
        while track[i] & 0x80:                                  # skip the delta time
            i += 1
        i += 1
        status = track[i]
        if status == 0xFF:
            kind, size = track[i + 1], track[i + 2]
            if kind == 0x51:
                tempo = int.from_bytes(track[i + 3:i + 6], "big")
            ended = kind == 0x2F
            i += 3 + size
        elif status & 0xF0 == 0x90:
            if track[i + 2] > 0:
                notes.append(track[i + 1])
            i += 3
        elif status & 0xF0 == 0x80:
            i += 3
        elif status & 0xF0 == 0xC0:
            i += 2
        else:
            raise AssertionError("unexpected status %02x" % status)
    return {"format": fmt, "tracks": tracks, "division": division, "tempo": tempo, "notes": notes, "ended": ended}
