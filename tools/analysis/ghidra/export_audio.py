"""Export the audio cue tables of the original (music, sound effects, speech) to docs/data/audio_map.json.

Pure Python (no Ghidra needed to run it); every address and rule was read in the Ghidra decompilation of
ONWIN32.EXE, the function names below are the ones in that dump (names_onwin32.json, or FUN_<address>).

How the original plays sound (all found in the decompilation):

* `PlaySoundEffect(i)` 0x431f1f loads the common effect i (logical id 28000 + i = NE0SOUND 8000 + i) and plays it
  through ONE waveOut device: a new sound cuts the old one. Gated by the Sound Effects option (SoundOn (0x44120c)).
* Speech: `LoadSpeechClip(logical id)` (0x411315) loads a clip into the scratch buffer, `PlayWave` (0x4150c4) plays it (gated by the
  Voice option VoiceOn (0x44120e)). Logical ids are mapped to NE1SOUND ids by the u16 table in resource OTHR/15001:
  logical 40..50 = 4000..4010, logical 503..862 = 4011..4370. The callers wait for the clip to end, or for
  Esc / Enter (some also for any key) which cut it off (`KillWave` (0x4151a4)).
* Sample rates: the header of every sound resource says 22050, but `PlayWave` (0x4150c4) opens waveOut at the override set by
  `set_sample_speed(rate)` (0x4150b1) unless that is -1. Effects (PlaySoundEffect) reset it to -1 around the play = 22050; OpeningSequence
  sets 8000 for the cartoon voices (4000-4010) and 16000 afterwards for all other speech. See tools/extract/extract_sounds.py.
* Music: `PlayBackgroundMusic(id)` 0x43206e -> `LoadMidiFile` looks the id up in the table at 0x440dd8 and opens
  SOUNDS\\<B|E><rest>.MID through MCI. The table at 0x440e00 holds the loop start of each song: all ten are 0, so a
  song restarts from its beginning when it ends (`PlayNextMusic` (0x413fba)). `pause_sound/63` (0x414145) pause and resume it (dialogs).
  Gated by the Music option (MusicOn (0x44120d)).
"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))   # gamefiles.py reads the CD image (NEPTUNE.ISO)
import gamefiles
D = gamefiles.read("ONWINCD/ONWIN32.EXE")
pe = struct.unpack_from('<I', D, 0x3c)[0]
nsec = struct.unpack_from('<H', D, pe + 6)[0]
opt = pe + 24
szopt = struct.unpack_from('<H', D, pe + 20)[0]
base = struct.unpack_from('<I', D, opt + 28)[0]
secs = []
for i in range(nsec):
    o = opt + szopt + i * 40
    vs, va, rs, rp = struct.unpack_from('<IIII', D, o + 8)
    secs.append((va, vs, rp, rs))


def off(addr: int) -> int | None:
    r = addr - base
    for va, vs, rp, rs in secs:
        if va <= r < va + max(vs, rs):
            return rp + r - va if r - va < rs else None
    raise KeyError(hex(addr))


def ints(addr: int, n: int) -> list[int]:
    o = off(addr)
    return list(struct.unpack('<%di' % n, D[o:o + 4 * n])) if o is not None else [0] * n


def cstr(addr: int) -> str:
    o = off(addr)
    if o is None:
        raise ValueError("no file data at %s" % hex(addr))
    return D[o:D.index(b'\0', o)].decode('latin1')


def u32(addr: int) -> int:
    o = off(addr)
    if o is None:
        raise ValueError("no file data at %s" % hex(addr))
    return struct.unpack_from('<I', D, o)[0]


# Logical id -> real id table (resource OTHR/15001 of the EXE, 875 u16 values).
RSRC = struct.unpack('<875H', (ROOT / "extracted/data/ONWIN32_resources/OTHR_15001.bin").read_bytes())


def real(logical: int) -> int:
    return logical - 20000 if logical > 20000 else RSRC[logical]


def clips(start: int, end: int) -> list[int]:
    """Logical ids start..end-1 -> NE1SOUND ids."""
    ids = [real(x) for x in range(start, end)]
    assert all(4000 <= i <= 4370 for i in ids), ids
    return ids


# --- music ---------------------------------------------------------------------------------------
music_ids = ints(0x440dd8, 10)
music_loops = ints(0x440e00, 10)
music_files = [cstr(u32(0x440e28 + 4 * i)).upper() for i in range(10)]
music = [{"id": i, "file": f, "loop_start": lp} for i, f, lp in zip(music_ids, music_files, music_loops, strict=True)]

# --- speech --------------------------------------------------------------------------------------
logs_a, logs_b = ints(0x441a74, 30), ints(0x441aec, 30)          # PlayLogEntrySpeech (0x41dfc8): canister log entry n
sup_a, sup_b = ints(0x4430c4, 30), ints(0x44313c, 30)            # PlaySupplyMessageSpeech (0x4326c0): supply message after sector n
clo_a, clo_b = ints(0x44158c, 3), ints(0x441598, 3)              # PlayVoyagerClosingSpeech (0x41c508): Voyager closing, page n

# PlayStoryPageSpeech(page) (0x42a817): the opening story, 9 pages, (clip count, first clip) from its switch statement.
STORY_PAGES = [(2, 0), (3, 2), (2, 5), (1, 7), (2, 8), (2, 10), (3, 12), (1, 15), (3, 16)]

voice = {
    # SignInSpeech (0x42fe4d): sign-in speech. `jingle` (0x2df) is also the lead-in of every supply message and of closing page 0.
    "jingle": real(0x2df),
    "sign_in_first_visit": [real(0x2e1), real(0x2e4)],         # when the sign-in screen first appears
    "sign_in_begin": [real(0x2e7), real(0x2ea)],               # Start for a new player ("Begin mission")
    "sign_in_resume": [real(0x2e7), real(0x2ed)],              # Start for a player with progress ("Resume mission")
    # CartoonSpeech (0x42984d): the opening cartoon, states 1..11 play logical 0x27 + state.
    "opening_cartoon": [real(0x27 + s) for s in range(1, 12)],
    "story_pages": [[real(0x1f7 + first + k) for k in range(n)] for n, first in STORY_PAGES],
    "supply": [clips(a, b) for a, b in zip(sup_a, sup_b, strict=True)],
    "logs": [clips(a, b) for a, b in zip(logs_a, logs_b, strict=True)],
    "closing_pages": [clips(a, b) for a, b in zip(clo_a, clo_b, strict=True)],
}

# --- sound effects -------------------------------------------------------------------------------
# index -> (when it plays, where the decompilation calls it). The NAME of an effect is not kept here: names are ours,
# not the original's, and live in one place, godot/names/original.json (the "sound" kind; docs/create/NAMES.md).
SFX = {
    0x16: ("the first screen of a sector is drawn: DrawScreen(1), only at the start / respawn of a sector (a screen change calls DrawScreen(0): silent)", "DrawScreen (0x433f1c) (param 1; DoAction 0x417ffc at its start)"),
    0x17: ("the supply station door opens (launch and docking)", "ExitSupplyStation, EnterSupplyStation (0x432b96)"),
    0x18: ("an ink pellet is fired", "StartStunGun"),
    0x19: ("a pellet hits the rock and splashes (first splash picture)", "UpdateStunGun"),
    0x1a: ("a creature touches the sub", "ApplyCreatureDamage (0x418d23) (hit handler, twice)"),
    0x1b: ("a capsule piece or the data canister is taken", "DoAction"),
    0x1d: ("the security scanner animation (sign-in) and the canister log screen", "AnimateSecurityScan (0x42fca0), AnimateLogScan (0x41e092)"),
    0x1e: ("fire pressed with no ink left", "StartStunGun"),
    0x1f: ("Backspace in the answer / calculator entry", "GetNumber (key 8, twice)"),
    0x20: ("a right answer (also the right lock number)", "DoMathProblem, LockRunStage"),
    0x21: ("a wrong answer (also a missed lock number)", "DoMathProblem, LockRunStage"),
    0x22: ("a ballast / panel button is toggled; bars of some diagrams step up", "GetBallastAnswer (0x4196e8), Prob02_AnimateBar (0x4321cb), Prob07, Prob20, Prob26/27"),
    0x23: ("a bar of a diagram appears", "Prob04_Diagram, Prob05_Diagram, Prob25_Diagram"),
    0x24: ("a dot of the closed-circuit monitor appears", "AnimateBarnacles (0x4278dc) (Prob14)"),
    0x25: ("the thermometer rises or falls", "AnimateThermometerColumn (0x41f813) (Prob12/13)"),
    0x26: ("a lock wheel moves one step", "LockSpinOperandWheel, LockAdvanceAnswerWheel"),
    0x27: ("the operand wheel stops at its number", "LockSpinOperandWheel"),
    0x28: ("the water tank fills", "Prob21_Diagram"),
    0x29: ("a picture pops into a diagram (pie, search grid, boxes, heading and ballast replays ...)", "Prob17, Prob30, Prob32/33 diagrams, Prob22 / Prob23 success replays"),
    0x2b: ("a scene of the opening cartoon", "TitleSplash (0x42a01f)"),
    0x2c: ("Voyager closing: the object flashes", "VoyagerClosingSequence"),
    0x2d: ("Voyager closing: the sub is carried off", "VoyagerClosingSequence"),
    0x2f: ("a message light (ship or computer) turns on", "DisplayShipMathIcon (0x419e4c)"),
    0x33: ("the end of the opening cartoon (stops the music)", "OpeningMusicCue (0x42b0f9) case 4"),
}

# Problem type -> the effect its diagram plays while it BUILDS (the first sound of each Prob*_Diagram routine; the sequence with
# its ticks is in problem_diagrams.json "intro" and is played by DiagramBase). Types 22, 23, 26, 27 sound only in their
# right-answer replay (ShowSuccessMessage), type 31 and the others not at all, so they are not here.
DIAGRAM_CUES = {2: 0x22, 4: 0x23, 5: 0x23, 7: 0x22, 12: 0x25, 13: 0x25, 14: 0x24, 17: 0x29, 20: 0x22, 21: 0x28,
                25: 0x23, 30: 0x29, 32: 0x29, 33: 0x29}

out = {
    "_doc": "Audio cue tables read from ONWIN32.EXE (music ids and files, speech clip runs, sound effects, diagram "
            "sounds). See the docstring of tools/analysis/ghidra/export_audio.py for how the original plays sound. The effects are "
            "listed by number; their friendly names are in godot/names/original.json.",
    "music": music,
    "music_rules": {
        "sector": "9504 + sector % 6 for sectors 0-29; 9500 for sectors 30 and 31 (SelectSectorMusic 0x43200f)",
        "sign_in": "none: the sign-in screen has no music, only speech (sign_in (0x431420) / SignInSpeech (0x42fe4d))",
        "opening": "9502 at the start of the cartoon, 9503 for the title scene, stopped at its end (OpeningMusicCue (0x42b0f9))",
        "closing": "Voyager: music stopped (VoyagerClosingSequence); Expert: 9501 (ExpertClosingSequence -> PlayExpertClosingMusic (0x4320cc))",
        "screen_change": "NOT restarted at a screen change (the four edge crossings call PlaySectorMusic(0) (0x43204d), which does nothing); PlaySectorMusic(1) restarts the sector song at the start of a sector and after a problem / dock message / supply message (surface ship screen)",
        "problem": "stopped when a math problem opens (StopSectorMusic (0x432064)), restarted when it closes",
        "supply_message_screen": "stopped while the supply message is spoken, restarted for the next sector",
    },
    "voice": voice,
    "sfx": {str(i): {"when": w, "evidence": e} for i, (w, e) in sorted(SFX.items())},
    "diagram_cues": {str(t): s for t, s in sorted(DIAGRAM_CUES.items())},
}
(ROOT / "docs/data/audio_map.json").write_text(json.dumps(out, indent=1) + "\n")
print("wrote docs/data/audio_map.json:", len(music), "songs,", len(SFX), "known effects,",
      sum(len(v) for v in voice["supply"]), "supply clips,", sum(len(v) for v in voice["logs"]), "log clips")
