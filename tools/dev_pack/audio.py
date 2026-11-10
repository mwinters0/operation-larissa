"""The dev pack's audio: speech, sound effects, music, MIDI files and the four catalogs that name them.

    uv run --group dev-pack tools/dev_pack/audio.py            writes godot/packs/dev/{assets/audio,midi,data/*_catalog...}

`build(dev_root)` is what tools/dev_pack/make_dev_pack.py calls. The dev pack has one file for every audio file of the legacy pack
(same path, same kind of file), made from the list of those files and the name registry (godot/names/original.json) and from
nothing of their content:

    speech  371 WAV   Piper says the clip's registry name (underscores as spaces): `log_12_3.wav` says "log 12 3"
    sounds   52 WAV   Piper says a short onomatopoeia that fits the effect's name (ONOMATOPOEIA below), else its name
    music    20 OGG   both sets (music/, music/adlib/): a synthesized loop in a key and tempo of its own, starting with the
                      song's name spoken; mono, Vorbis through ffmpeg
    midi     20 MID   a few notes each, written here

The catalogs (`sfx_catalog`, `music_catalog`, `voice_index`, `voice_cues`) are the same classes legacy's are, over dev's files. The
transcripts of `voice_index` are the spoken words and its durations are measured from dev's own files, the way the importer measures
(whole ticks of 1/73 s, rounded up). The Piper version and the voice are recorded in tools/dev_pack/audio_manifest.json.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "import"))         # the importer's modules: names, tres writer, uids

import asset_names
import audio_speech
import audio_synth
import common
import foe_names
import import_uids
import tres

DEV_ROOT = common.PACKS / "dev"
RES_PREFIX = "res://packs/dev/"
SCRIPTS = "res://src/resources/"
MANIFEST = HERE / "audio_manifest.json"
TICKS_PER_SECOND = 73                   # the original's timer (1 tick = 1/73 s), the unit `voice_index` counts in
SFX_RATE = 22050
VOICE_RATE = 16000
SFX_COUNT, VOICE_FIRST, VOICE_LAST = 52, 4000, 4370

# What each sound effect says: an onomatopoeia that fits its name. A name that is not here says itself (the unnamed `sfx_28`).
ONOMATOPOEIA = {
    "eel_lash": "zap", "worm_snap": "snap", "angler_chomp": "chomp", "octopus_spit": "spit", "squid_fire": "pew",
    "squid_dart_pop": "pop", "fire_launch": "whoosh", "fire_burst": "boom", "crab_lob": "bloop", "ball_land": "thud",
    "ray_sting": "zing", "ray_sting_alt": "zing zing", "ray_sting_third": "zing zing zing", "isopod_skitter": "skitter",
    "clam_chomp": "chomp chomp", "hammerhead_bite": "crunch", "oxygen_refill": "hiss", "oxygen_refill_alt": "psst",
    "crab_lob_alt": "bloop bloop", "hammerhead_bite_alt": "crunch crunch", "fire_burst_deep": "boom boom",
    "fire_launch_alt": "whoosh whoosh", "begin": "ding", "station_door": "swish", "ink_fired": "squirt", "ink_splash": "splat",
    "creature_hit": "bonk", "piece_pickup": "ping", "scanner": "beep", "no_pellets": "nope", "calc_backspace": "tick",
    "correct": "ding dong", "wrong": "buzz", "click": "click", "diagram_bar": "boop", "diagram_dot": "dot",
    "thermometer": "blip", "lock_tick": "tick tick", "lock_settle": "clunk", "tank_fill": "glug", "diagram_pop": "pop pop",
    "opening_scene": "swoosh", "closing_flash": "flash", "closing_surge": "surge", "message_light": "beep beep",
    "opening_end": "ta da",
}

# `diagram_cues` of the sfx catalog: problem type -> the sound its diagram plays while it is built. The types are the ones whose
# diagrams are not silent; the sounds are dev's own pick (the three diagram effects in turn), as the numbers of `sound` names.
DIAGRAM_TYPES = (2, 4, 5, 7, 12, 13, 14, 17, 20, 21, 25, 30, 32, 33)
DIAGRAM_SOUNDS = ("diagram_bar", "diagram_dot", "diagram_pop")

# The groups of `voice_cues`: name -> how many there are. Their clips are the voice clips called `<group>` or `<group>_<k>`.
SINGLE_GROUPS = ("jingle", "sign_in_first_visit", "sign_in_begin", "sign_in_resume", "opening_cartoon")
NUMBERED_GROUPS = (("story_page", 9), ("supply", 30), ("log", 30), ("closing_page", 3))


# ---- names and paths --------------------------------------------------------------------------------------------------

def registry() -> foe_names.Registry:
    return foe_names.original()


def name_of(kind: str, number: int) -> str:
    """The registry name of `number`, or the made-up name (`sfx_28`, `voice_4244`) while nobody has named it."""
    return registry().real_name(kind, number) or foe_names.fallback_name(kind, number)


def spoken(name: str) -> str:
    return name.replace("_", " ")


def rel(path: Path) -> str:
    """A path the importer's naming code made (below the legacy pack's folder) as the path below any pack's root."""
    return path.relative_to(common.LEGACY).as_posix()


def sfx_paths() -> list[str]:
    return [rel(asset_names.sfx_file(n)) for n in range(SFX_COUNT)]


def voice_ids() -> list[int]:
    return list(range(VOICE_FIRST, VOICE_LAST + 1))


def voice_paths() -> list[str]:
    return [rel(asset_names.voice_file(v)) for v in voice_ids()]


def songs() -> list[dict]:
    """The ten songs: [{"id": 9500, "file": "BEND.MID"}, ...] (docs/data/music_map.json: an id and the name of a file, nothing else is used)."""
    return [{"id": e["id"], "file": e["file"]} for e in common.load_json(common.DOCS_DATA / "music_map.json")["music"]]


def midi_name(song: dict, letter: str) -> str:
    """'BSECT1.MID' -> 'ESECT1.MID' (letter E, the General MIDI set) or 'BSECT1.MID' (letter B, the AdLib set)."""
    return letter + song["file"][1:]


def music_stem(song: dict, letter: str) -> str:
    return (letter + song["file"][1:].rsplit(".", 1)[0]).lower()


def music_paths(adlib: bool) -> list[str]:
    letter = "B" if adlib else "E"
    return [rel(asset_names.music_file(s["id"], music_stem(s, letter), adlib=adlib)) for s in songs()]


def midi_paths() -> list[str]:
    return ["midi/" + midi_name(s, letter) for s in songs() for letter in ("E", "B")]


def inventory() -> list[str]:
    """Every file of the dev pack that belongs to audio (paths below the pack's root, sorted), `.import` files included."""
    audio = (sfx_paths() + voice_paths() + music_paths(False) + music_paths(True)
             + ["assets/audio/music/rendered_with.json", "assets/audio/music/adlib/rendered_with.json"] + midi_paths())
    return sorted(audio + [p + ".import" for p in audio if Path(p).suffix in import_uids.IMPORTERS])


def sfx_words(name: str) -> str:
    """What effect `name` says."""
    return ONOMATOPOEIA.get(name, spoken(name))


# ---- voice groups -----------------------------------------------------------------------------------------------------

def voice_groups() -> dict[str, list[int]]:
    """group name -> the clip numbers, in order. The clips of a group are the ones the registry names `<group>` or `<group>_<k>`
    (`log_3_0`, `log_3_1`, ...; `story_page_3` has just the one), so the names carry the structure and dev does not repeat it."""
    names = registry().entries("voice")

    def members(group: str) -> list[int]:
        found = []
        for name, number in names.items():
            if name == group:
                found.append((0, number))
            elif (m := re.fullmatch(re.escape(group) + r"_(\d+)", name)):
                found.append((int(m.group(1)), number))
        return [number for _k, number in sorted(found)]

    groups = {g: members(g) for g in SINGLE_GROUPS}
    for kind, count in NUMBERED_GROUPS:
        for i in range(count):
            groups["%s_%d" % (kind, i)] = members("%s_%d" % (kind, i))
    return groups


# ---- the catalogs -----------------------------------------------------------------------------------------------------

def sfx_catalog_text(res_prefix: str = RES_PREFIX) -> str:
    t = tres.Tres("Resource", "SfxCatalog", SCRIPTS + "sfx_catalog.gd")
    t.set("streams", tres.array("AudioStream", (t.ext_ref("AudioStreamWAV", res_prefix + p) for p in sfx_paths())))
    sounds = registry().entries("sound")
    cues = [(str(t_id), str(sounds[DIAGRAM_SOUNDS[i % len(DIAGRAM_SOUNDS)]])) for i, t_id in enumerate(DIAGRAM_TYPES)]
    t.set("diagram_cues", tres.dictionary(cues))
    return t.render()


def music_catalog_text(res_prefix: str = RES_PREFIX) -> str:
    m = tres.Tres("Resource", "MusicCatalog", SCRIPTS + "music_catalog.gd")
    m.set("ids", tres.packed_ints(s["id"] for s in songs()))
    m.set("gm_paths", tres.packed_strings(res_prefix + p for p in music_paths(False)))
    m.set("adlib_paths", tres.packed_strings(res_prefix + p for p in music_paths(True)))
    m.set("midi_names", tres.packed_strings(s["file"] for s in songs()))
    return m.render()


def voice_index_text(durations: list[int], res_prefix: str = RES_PREFIX) -> str:
    v = tres.Tres("Resource", "VoiceIndex", SCRIPTS + "voice_index.gd")
    v.set("ids", tres.packed_ints(voice_ids()))
    v.set("paths", tres.packed_strings(res_prefix + p for p in voice_paths()))
    v.set("transcripts", tres.packed_strings(spoken(name_of("voice", i)) for i in voice_ids()))
    v.set("durations", tres.packed_ints(durations))
    return v.render()


def voice_cues_text() -> str:
    c = tres.Tres("Resource", "VoiceCues", SCRIPTS + "voice_cues.gd")
    c.set("groups", tres.dictionary((tres.s(k), tres.packed_ints(g)) for k, g in voice_groups().items()))
    return c.render()


# ---- writing audio ----------------------------------------------------------------------------------------------------

def wav_ticks(path: Path) -> int:
    """How long a WAV plays in whole ticks of 1/73 s, rounded up (integer arithmetic: the same number on every machine)."""
    with wave.open(str(path)) as w:
        return -(-w.getnframes() * TICKS_PER_SECOND // w.getframerate())


def wav_bytes(samples: np.ndarray, rate: int) -> bytes:
    """Float samples (-1..1) as a mono 16-bit WAV file."""
    import io
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((np.clip(samples, -1.0, 1.0) * 32767.0).round().astype("<i2").tobytes())
    return buffer.getvalue()


def speech_wav(speaker: audio_speech.Speaker, text: str, rate: int) -> bytes:
    """`text` said at `rate`, at a fixed comfortable level, with a little silence at the end."""
    voice = speaker.say(text)
    peak = float(np.max(np.abs(voice))) if voice.size else 0.0
    if peak > 0:
        voice = voice / peak * 0.8
    voice = audio_synth.resample(voice, audio_speech.SPEECH_RATE, rate)
    return wav_bytes(np.concatenate([voice, np.zeros(int(0.05 * rate))]), rate)


def encode_ogg(samples: np.ndarray) -> bytes:
    """Mono float samples at audio_synth.RATE -> OGG Vorbis through ffmpeg (bitexact: no encoder version or date in the file)."""
    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).round().astype("<i2").tobytes()
    run = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(audio_synth.RATE), "-ac", "1", "-i", "-",
                          "-c:a", "libvorbis", "-q:a", "3", "-fflags", "+bitexact", "-flags:a", "+bitexact", "-map_metadata", "-1",
                          "-f", "ogg", "-"], input=pcm, check=True, capture_output=True)
    return run.stdout


def put(path: Path, data: bytes | str) -> bool:
    if isinstance(data, str):
        data = data.encode("utf-8")
    return common.write_bytes(path, data)


def put_sidecar(path: Path, res_prefix: str, root: Path) -> None:
    """The `.import` stub of a WAV or OGG: importer, type and a uid worked out from the file's res:// path (import_uids.py). A sidecar
    that exists is never touched (Godot's own, filled in by an import)."""
    side = import_uids.sidecar(path)
    if side.exists():
        return
    importer, kind = import_uids.IMPORTERS[path.suffix]
    url = res_prefix + path.relative_to(root).as_posix()
    side.write_text('[remap]\n\nimporter="%s"\ntype="%s"\nuid="%s"\n' % (importer, kind, import_uids.uid_of(url)))


def res_prefix_of(dev_root: Path) -> str:
    """res://packs/dev/ for the real dev pack (and for a folder outside the project, such as a test's)."""
    try:
        return "res://" + dev_root.resolve().relative_to(common.GODOT.resolve()).as_posix() + "/"
    except ValueError:
        return RES_PREFIX


def build(dev_root: Path = DEV_ROOT, speaker: audio_speech.Speaker | None = None) -> None:
    """Writes the dev pack's audio, MIDI files, the four catalogs and the `.import` stubs below `dev_root`."""
    dev_root = Path(dev_root)
    prefix = res_prefix_of(dev_root)
    speaker = speaker or audio_speech.Speaker()
    audio_files: list[Path] = []

    def write_audio(relative: str, data: bytes) -> None:
        path = dev_root / relative
        put(path, data)
        audio_files.append(path)

    for n, relative in enumerate(sfx_paths()):                       # sound effects
        write_audio(relative, speech_wav(speaker, sfx_words(name_of("sound", n)), SFX_RATE))
    for vid, relative in zip(voice_ids(), voice_paths()):             # speech
        write_audio(relative, speech_wav(speaker, spoken(name_of("voice", vid)), VOICE_RATE))
    for adlib in (False, True):                                      # music
        for index, (song, relative) in enumerate(zip(songs(), music_paths(adlib))):
            words = spoken(name_of("music", song["id"]))
            samples = audio_synth.render_song(index, adlib, speaker.say(words), audio_speech.SPEECH_RATE)
            write_audio(relative, encode_ogg(samples))
    stamp = {"comment": "What the OGGs in this folder are, written by tools/dev_pack/audio.py: a synthesized loop (numpy) in a key and "
                        "tempo per song, after the song's name spoken by Piper.",
             }
    for adlib, folder in ((False, "assets/audio/music"), (True, "assets/audio/music/adlib")):
        put(dev_root / folder / "rendered_with.json",
            json.dumps({**stamp, "set": "AdLib (pulse wave)" if adlib else "General MIDI (bell)", "piper": audio_speech.piper_version(),
                        "voice": audio_speech.VOICE_ID}, indent=1) + "\n")

    for index, song in enumerate(songs()):                           # MIDI files
        for letter in ("E", "B"):
            put(dev_root / "midi" / midi_name(song, letter), audio_synth.midi_bytes(index, letter == "B"))

    durations = [wav_ticks(dev_root / p) for p in voice_paths()]       # catalogs
    data = dev_root / "data"
    put(data / "sfx_catalog.tres", sfx_catalog_text(prefix))
    put(data / "music_catalog.tres", music_catalog_text(prefix))
    put(data / "voice_index.tres", voice_index_text(durations, prefix))
    put(data / "voice_cues.tres", voice_cues_text())

    for path in audio_files:
        put_sidecar(path, prefix, dev_root)
    write_manifest(dev_root, audio_files)
    size = sum(p.stat().st_size for p in audio_files) + sum((dev_root / p).stat().st_size for p in midi_paths())
    print("  dev audio: %d sounds, %d speech clips, %d songs x 2 sets, %d MIDI files, %.1f MB" % (
        SFX_COUNT, len(voice_ids()), len(songs()), len(midi_paths()), size / 1e6))


def write_manifest(dev_root: Path, audio_files: list[Path]) -> None:
    """tools/dev_pack/audio_manifest.json: the voice and Piper version the speech was made with, and what was made."""
    files = {"sfx": SFX_COUNT, "voice": len(voice_ids()), "music": 2 * len(songs()), "midi": len(midi_paths())}
    manifest = {
        "comment": "Written by tools/dev_pack/audio.py. The dev pack's speech is Piper text-to-speech (noise settings 0, so the same words "
                   "give the same samples); the model is downloaded to ~/.cache/neptune-dev-pack/ and checked against these SHA-256s.",
        "piper_tts": audio_speech.piper_version(),
        "voice": audio_speech.VOICE_ID,
        "voice_files": {n: {"url": u, "sha256": d} for n, (u, d) in audio_speech.VOICE_FILES.items()},
        "formats": {"sfx": "WAV 16-bit mono %d Hz" % SFX_RATE, "voice": "WAV 16-bit mono %d Hz" % VOICE_RATE,
                    "music": "OGG Vorbis mono %d Hz (ffmpeg libvorbis -q:a 3)" % audio_synth.RATE, "midi": "SMF format 0"},
        "files": files,
        "megabytes": round(sum(p.stat().st_size for p in audio_files) / 1e6, 1),
    }
    put(MANIFEST, json.dumps(manifest, indent=1) + "\n")


if __name__ == "__main__":
    build(Path(sys.argv[1]) if len(sys.argv) > 1 else DEV_ROOT)
