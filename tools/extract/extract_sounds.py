# /// script
# requires-python = ">=3.10"
# dependencies = ["pycdlib"]
# ///
"""Extract WAV sound effects/voice from NE0SOUND.DLL / NE1SOUND.DLL, copy MIDI music, and
dump the undecoded FM-synth (AdLib) effect definitions from NE0SOUND.DLL (ids 9000+).

Sound resource layout (custom type 32513): u32 format(0), u32 sample_rate (22050), u32 length,
then `length` bytes of unsigned 8-bit mono PCM (silence = 0x80), zero padded to 512 bytes.
(One resource, 8013, has length field = 1 although it holds ~3.8 KB; we trim zero padding.)

The header rate is 22050 in all 423 resources, but the original does NOT play speech at it. Its one waveOut
routine (PlayWave @ 0x4150c4) opens the device at `SampleRateOverride` (0x4411dc) when that is not -1, else at the header rate;
`set_sample_speed(rate)` (0x4150b1) sets `SampleRateOverride` (0x4411dc) (initially -1). Effects go through PlaySoundEffect, which sets -1 around
its play, so they use the header rate (22050). OpeningSequence (OpeningSequence (0x42b16b)) calls set_sample_speed(8000) (0x4150b1) while the
cartoon voices (NE1SOUND 4000-4010, played by CartoonSpeech (0x42984d)) run and set_sample_speed(16000) (0x4150b1) afterwards, never undoing
it: every other speech clip (4011-4370) is played at 16000 Hz. `speech_rates()` reads both values out of the EXE
(the `push imm32` before each `call set_sample_speed (0x4150b1)`) and the WAVs are written with the rate the game plays them at;
the header value is kept in the manifest as `header_rate`.
"""
import json
import struct
import sys
import wave
from pathlib import Path

from ne import NE

FN_SET_RATE = 0x4150B1          # set_sample_speed (0x4150b1): set the waveOut rate override (-1 = use the resource header)
CARTOON_CLIPS = range(4000, 4011)   # NE1SOUND ids played by CartoonSpeech (0x42984d) during the 8000 Hz part of the opening

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / 'tools'))     # gamefiles.py reads the CD image (NEPTUNE.ISO)
import gamefiles
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'extracted'     # usage: extract_sounds.py [OUT_DIR]

def speech_rates(d: bytes) -> tuple[int, int]:
    """(cartoon rate, speech rate): the immediates pushed before the two `call set_sample_speed` (0x4150b1) in ONWIN32.EXE."""
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    nsec, szopt = struct.unpack_from('<H', d, pe + 6)[0], struct.unpack_from('<H', d, pe + 20)[0]
    base = struct.unpack_from('<I', d, pe + 24 + 28)[0]
    found: list[tuple[int, int]] = []
    for i in range(nsec):
        vs, va, rs, rp = struct.unpack_from('<IIII', d, pe + 24 + szopt + i * 40 + 8)
        code = d[rp:rp + min(vs, rs)]
        for at in range(len(code) - 10):
            if code[at] == 0x68 and code[at + 5] == 0xE8:           # push imm32 ; call rel32
                target = base + va + at + 10 + struct.unpack_from('<i', code, at + 6)[0]
                value = struct.unpack_from('<I', code, at + 1)[0]
                if target == FN_SET_RATE and value != 0xFFFFFFFF:
                    found.append((va + at, value))
    rates = [v for _, v in sorted(found)]
    if len(rates) != 2 or not all(1000 < r <= 22050 for r in rates):
        raise SystemExit(f'expected two set_sample_speed(rate) (0x4150b1) calls in ONWIN32.EXE, found {rates}')
    return rates[0], rates[1]


def main():
    cartoon_rate, voice_rate = speech_rates(gamefiles.read('ONWINCD/ONWIN32.EXE'))
    man = {}
    for dll in ['NE0SOUND', 'NE1SOUND']:
        n = NE(gamefiles.read(f'ONWINCD/{dll}.DLL'))
        dwav = OUT / 'sounds' / dll; dwav.mkdir(parents=True, exist_ok=True)
        draw = OUT / 'sounds' / 'fm_patches_undecoded'; draw.mkdir(parents=True, exist_ok=True)
        for r in n.resources:
            if r[1] != 32513: continue
            d = n.get(r)
            fmt, rate, ln = struct.unpack_from('<III', d, 0)
            if rate == 22050 and fmt == 0:
                play = (cartoon_rate if r[2] in CARTOON_CLIPS else voice_rate) if dll == 'NE1SOUND' else rate
                end = 12 + ln if 12 + ln <= len(d) and ln > 1 else len(d.rstrip(b'\0'))
                pcm = d[12:end]
                with wave.open(str(dwav / f'{dll}_{r[2]}.wav'), 'wb') as w:
                    w.setnchannels(1); w.setsampwidth(1); w.setframerate(play); w.writeframes(pcm)
                man[f'{dll}:{r[2]}'] = {'file': f'sounds/{dll}/{dll}_{r[2]}.wav', 'rate': play, 'header_rate': rate, 'bits': 8,
                                        'channels': 1, 'samples': len(pcm), 'seconds': round(len(pcm) / play, 3)}
            else:
                (draw / f'{dll}_{r[2]}.bin').write_bytes(d.rstrip(b'\0') if d.rstrip(b'\0') else d[:16])
                man[f'{dll}:{r[2]}'] = {'file': f'sounds/fm_patches_undecoded/{dll}_{r[2]}.bin', 'kind': 'fm-patch', 'header_u32': fmt}
    with open(OUT / 'sounds' / 'manifest.json', 'w', newline='\n') as f:
        json.dump(man, f, indent=1)
    # MIDI
    dm = OUT / 'music'; dm.mkdir(parents=True, exist_ok=True)
    for f in gamefiles.glob('ONWINCD/SOUNDS/*.MID'):
        (dm / Path(f).name).write_bytes(gamefiles.read(f))
    print('wavs:', sum(1 for v in man.values() if v['file'].endswith('.wav')), 'fm patches:', sum(1 for v in man.values() if v['file'].endswith('.bin')),
          'midi:', len(list(dm.glob('*.MID'))))

if __name__ == '__main__':
    main()
