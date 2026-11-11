"""Step 'audio': sound effects, voice (WAV copies) and music (MIDI -> OGG)."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

from asset_manifest import copy_sound, put_port, put_song
from asset_names import music_file, sfx_file, voice_file
from common import ASSETS, MIDI, PACK_DATA, DOCS_DATA, EXTRACTED, ROOT, load_json, out_text, res_path, sha256_hex
import tres

SCRIPTS = "res://src/resources/"
# The General MIDI soundfont: where Fedora's fluid-soundfont-gm puts it; on Windows, which has no such package, in the git-ignored
# soundfonts/ folder of the repository, where tools/fetch_soundfont.py puts it (docs/SETUP.md, "On Windows").
DEFAULT_SOUNDFONT = str(ROOT / "soundfonts" / "FluidR3_GM.sf2") if os.name == "nt" else "/usr/share/soundfonts/FluidR3_GM.sf2"
ADLIB_SOUNDFONT = str(ROOT / "soundfonts" / "opl.sf2")   # optional; not in the repository (135 MB)
# The friendly names of the effects are not written here: `SfxCatalog` asks the name registry (godot/names/original.json).


# FluidSynth renders some songs much louder than others, and two of them exceed full scale (peak > 1.0), which
# clips on the speakers. A song whose average level is above TARGET_MEAN_DB + 3 is turned down to the target, and
# every song is kept PEAK_LIMIT_DB below full scale. Songs inside both limits are not touched.
TARGET_MEAN_DB = -22.0
PEAK_LIMIT_DB = -1.5


def music_gain_db(wav: Path) -> float:
    """The gain (<= 0 dB) that brings a rendered song inside the two limits above (ffmpeg's volumedetect)."""
    out = subprocess.run(["ffmpeg", "-nostats", "-i", str(wav), "-af", "volumedetect", "-f", "null", "-"],
                         check=True, capture_output=True, text=True).stderr
    mean_found = re.search(r"mean_volume: (-?[\d.]+) dB", out)
    peak_found = re.search(r"max_volume: (-?[\d.]+) dB", out)
    if mean_found is None or peak_found is None:
        raise RuntimeError("ffmpeg volumedetect printed no levels for %s" % wav)
    mean, peak = float(mean_found.group(1)), float(peak_found.group(1))
    gain = TARGET_MEAN_DB - mean if mean > TARGET_MEAN_DB + 3 else 0.0
    return round(min(0.0, gain, PEAK_LIMIT_DB - peak), 1)


TICKS_PER_SECOND = 73       # the original's timer (1 tick = 1/73 s): the unit every waiting step of the game counts in


def wav_ticks(path: Path) -> int:
    """How long a WAV plays, in whole ticks of 1/73 s (rounded up): frames * 73 / rate with integer arithmetic, so the number
    is the same on every machine. The file's header rate is the rate the original plays the clip at (see test_audio.py)."""
    with wave.open(str(path)) as w:
        return -(-w.getnframes() * TICKS_PER_SECOND // w.getframerate())


def music_stems(entry: dict, letter: str) -> str:
    """'BSECT1.MID' -> 'esect1' (letter E, the General MIDI set) or 'bsect1' (letter B, the AdLib set)."""
    return (letter + entry["file"][1:].rsplit(".", 1)[0]).lower()


# Each rendered set records what it was rendered from, next to its OGGs: the soundfont (file name and SHA-256) and the
# SHA-256 of each song's MIDI file. A song is rendered again only when its OGG is missing or one of those changed,
# so `--soundfont other.sf2` re-renders the whole set, while re-extracting the same MIDI files (new modification
# times, same bytes) re-renders nothing. That matters because FluidSynth does not render every song to the same
# samples twice: a needless re-render would change committed files.
STAMP = "rendered_with.json"


def file_sha256(path: Path) -> str:
    """SHA-256 of a file, read in pieces (soundfonts are over 100 MB)."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 22):
            h.update(chunk)
    return h.hexdigest()


def adopt_song(dest: Path, midi_stem: str, song_id: int) -> bool:
    """Moves the OGG of a song to `dest` when it exists under another name: the MIDI stem (`esect1.ogg`, the name before the
    songs had names of their own) or an earlier `<name>_<id>.ogg`. A rendered song is never rendered again just because its
    file got a new name (FluidSynth does not render the same samples twice, and not every machine can render at all)."""
    if dest.exists():
        return False
    found = sorted({dest.with_name(midi_stem + ".ogg"), *dest.parent.glob("*_%d.ogg" % song_id)} - {dest})
    found = [p for p in found if p.exists()]
    if len(found) != 1:
        return False
    for sidecar in (".import",):                       # Godot's import file moves with its asset (see asset_manifest.prune)
        old = Path(str(found[0]) + sidecar)
        if old.exists():
            Path(str(dest) + sidecar).write_text(old.read_text().replace(found[0].name, dest.name), newline="\n")
            old.unlink()
    found[0].rename(dest)
    return True


def render_set(stems: list[str], dest_dir: Path, soundfont: str, midi_dir: Path = EXTRACTED / "music",
               files: dict[str, Path] | None = None) -> int:
    """Renders the songs of one set into `dest_dir` (see STAMP above); returns how many were rendered.
    `files`: stem -> the OGG to write, for songs that are not called `<stem>.ogg` (named songs, `asset_names.music_file`)."""
    stamp_path = dest_dir / STAMP
    old = json.loads(stamp_path.read_text()) if stamp_path.exists() else {}   # not load_json: it caches
    font_hash = file_sha256(Path(soundfont))
    same_font = old.get("soundfont_sha256") == font_hash
    songs, rendered = {}, 0
    for stem in stems:
        src = midi_dir / (stem.upper() + ".MID")
        midi_hash = sha256_hex(src.read_bytes())
        dest = (files or {}).get(stem, dest_dir / (stem + ".ogg"))
        if not (dest.exists() and same_font and old.get("songs", {}).get(stem) == midi_hash):
            render_music(src, dest, soundfont)
            rendered += 1
        songs[stem] = midi_hash
    stamp = {"comment": "What the OGGs in this folder were rendered from, written by tools/import/step_audio.py: a "
                        "song is rendered again only when its MIDI file or the soundfont changes. Choose another "
                        "soundfont with import_all.py --only audio --soundfont / --adlib-soundfont.",
             "soundfont": Path(soundfont).name, "soundfont_sha256": font_hash, "songs": songs}
    out_text(stamp_path, json.dumps(stamp, indent=1) + "\n")
    return rendered


def render_music(src: Path, dest: Path, soundfont: str) -> None:
    """MIDI -> WAV with fluidsynth, WAV -> OGG with ffmpeg (trailing silence trimmed)."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "x.wav"
        subprocess.run(["fluidsynth", "-ni", "-g", "0.8", "-r", "44100", "-F", str(wav), soundfont, str(src)],
                       check=True, capture_output=True)
        # areverse + silenceremove + areverse trims silence at the END; bitexact = no encoder version or date in
        # the file (FluidSynth itself is not deterministic, see STAMP).
        gain = music_gain_db(wav)
        trim = "areverse,silenceremove=start_periods=1:start_threshold=-60dB,areverse"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
                        "-af", trim + (",volume=%sdB" % gain if gain < 0 else ""),
                        "-c:a", "libvorbis", "-q:a", "4", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        "-map_metadata", "-1", str(dest)], check=True, capture_output=True)


def copy_midi(songs: list[dict]) -> int:
    """Copies the original MIDI files (both sets) to the legacy pack's `midi/`, where `MidiMusic` finds them: the game can play them through
    any SoundFont at runtime (docs/engine/AUDIO.md) instead of the OGGs rendered above. Original bytes, so they are in the legacy pack (git-ignored); the
    files are the ones `source_files.json` hashes (the importer checks them first). Returns how many were written."""
    dest = MIDI
    dest.mkdir(parents=True, exist_ok=True)
    written = 0
    for e in songs:
        for letter in ("E", "B"):
            name = letter + e["file"][1:]
            src = EXTRACTED / "music" / name
            if src.exists() and (not (dest / name).exists() or (dest / name).read_bytes() != src.read_bytes()):
                shutil.copyfile(src, dest / name)
                written += 1
    return written


def run(soundfont: str = DEFAULT_SOUNDFONT, adlib_soundfont: str = ADLIB_SOUNDFONT) -> None:
    amap = load_json(DOCS_DATA / "audio_map.json")

    # --- sound effects: 52 WAVs (their names are the "sound" names of the registry, which SfxCatalog reads itself) ---
    sfx_paths = []
    for n in range(52):
        dest = sfx_file(n)
        copy_sound("NE0SOUND", 8000 + n, dest)
        sfx_paths.append(res_path(dest))
    t = tres.Tres("Resource", "SfxCatalog", SCRIPTS + "sfx_catalog.gd")
    t.set("streams", tres.array("AudioStream", (t.ext_ref("AudioStreamWAV", p) for p in sfx_paths)))
    t.set("diagram_cues", tres.dictionary((k, str(v)) for k, v in sorted(amap["diagram_cues"].items(), key=lambda kv: int(kv[0]))))
    out_text(PACK_DATA / "sfx_catalog.tres", t.render())

    # --- speech: 371 WAVs with their transcripts, and the cue lists (which clips are spoken when) -----------
    transcripts = load_json(EXTRACTED / "sounds" / "voice_transcripts.json")
    ids, paths, texts, durations = [], [], [], []
    for vid in range(4000, 4371):
        dest = voice_file(vid)
        copy_sound("NE1SOUND", vid, dest)
        ids.append(vid)
        paths.append(res_path(dest))
        texts.append(transcripts.get("NE1SOUND_%d" % vid, "").strip())
        durations.append(wav_ticks(dest))              # (D5: what the clip lasts in the ORIGINAL; flows wait this long, not for the stream)
    v = tres.Tres("Resource", "VoiceIndex", SCRIPTS + "voice_index.gd")
    v.set("ids", tres.packed_ints(ids))
    v.set("paths", tres.packed_strings(paths))
    v.set("transcripts", tres.packed_strings(texts))
    v.set("durations", tres.packed_ints(durations))
    out_text(PACK_DATA / "voice_index.tres", v.render())

    voice = amap["voice"]
    groups: dict[str, list[int]] = {"jingle": [voice["jingle"]], "sign_in_first_visit": voice["sign_in_first_visit"],
                                    "sign_in_begin": voice["sign_in_begin"], "sign_in_resume": voice["sign_in_resume"],
                                    "opening_cartoon": voice["opening_cartoon"]}
    for kind, key in (("story_page", "story_pages"), ("supply", "supply"), ("log", "logs"), ("closing_page", "closing_pages")):
        for i, clip_list in enumerate(voice[key]):
            groups["%s_%d" % (kind, i)] = clip_list
    c = tres.Tres("Resource", "VoiceCues", SCRIPTS + "voice_cues.gd")
    c.set("groups", tres.dictionary((tres.s(k), tres.packed_ints(g)) for k, g in groups.items()))
    out_text(PACK_DATA / "voice_cues.tres", c.render())

    # --- music: MIDI rendered to OGG, once per sound set ---------------------------------------------------------
    songs = load_json(DOCS_DATA / "music_map.json")["music"]       # the verified id -> MIDI file map
    have_gm = shutil.which("fluidsynth") and shutil.which("ffmpeg") and Path(soundfont).exists()
    # The AdLib set (B*.MID) wants an OPL imitation (soundfonts/opl.sf2, not in the repository). A checkout that has none still gets a
    # complete the legacy pack: the set is rendered with the General MIDI soundfont then (it sounds like General MIDI), and says so below.
    adlib_font = adlib_soundfont if Path(adlib_soundfont).exists() else soundfont
    have_adlib = shutil.which("fluidsynth") and shutil.which("ffmpeg") and Path(adlib_font).exists()
    music_dir = ASSETS / "audio" / "music"
    # The catalog is written even if rendering is skipped: it names the same files whatever this machine can render.
    m = tres.Tres("Resource", "MusicCatalog", SCRIPTS + "music_catalog.gd")
    m.set("ids", tres.packed_ints(e["id"] for e in songs))
    gm_files = {music_stems(e, "E"): music_file(e["id"], music_stems(e, "E")) for e in songs}
    adlib_files = {music_stems(e, "B"): music_file(e["id"], music_stems(e, "B"), adlib=True) for e in songs}
    for e in songs:                                  # a song that was rendered under its old name is moved, not rendered again
        adopt_song(gm_files[music_stems(e, "E")], music_stems(e, "E"), e["id"])
        adopt_song(adlib_files[music_stems(e, "B")], music_stems(e, "B"), e["id"])
    m.set("gm_paths", tres.packed_strings(res_path(gm_files[music_stems(e, "E")]) for e in songs))
    m.set("adlib_paths", tres.packed_strings(res_path(adlib_files[music_stems(e, "B")]) for e in songs))
    m.set("midi_names", tres.packed_strings(e["file"] for e in songs))
    out_text(PACK_DATA / "music_catalog.tres", m.render())
    # The manifest names the songs and their stamps even where this machine cannot render.
    for letter, folder, files in (("E", music_dir, gm_files), ("B", music_dir / "adlib", adlib_files)):
        for e in songs:
            stem = music_stems(e, letter)
            put_song(files[stem], stem)
        put_port(folder / STAMP, "tools/import/step_audio.py", "stamp")

    if not have_gm:
        print("  WARNING: fluidsynth/ffmpeg/General MIDI soundfont missing - music not rendered (the songs already in the legacy pack's assets/audio/music are kept)")
    else:
        n = render_set([music_stems(e, "E") for e in songs], music_dir, soundfont, files=gm_files)
        print("  music (General MIDI, %s): %d of %d songs rendered" % (Path(soundfont).name, n, len(songs)))
    if not have_adlib:
        print("  note: no soundfont for the AdLib music set (%s, nor the General MIDI one) - it is not (re)rendered" % adlib_soundfont)
    else:
        if adlib_font != adlib_soundfont:
            print("  note: %s not found - the AdLib set is rendered with %s (give --adlib-soundfont an OPL soundfont for the real sound)"
                  % (adlib_soundfont, Path(adlib_font).name))
        n = render_set([music_stems(e, "B") for e in songs], music_dir / "adlib", adlib_font, files=adlib_files)
        print("  music (AdLib, %s): %d of %d songs rendered" % (Path(adlib_font).name, n, len(songs)))
    print("  midi: %d files copied to the legacy pack's midi/ (for music from MIDI at runtime)" % copy_midi(songs))
    print("  audio: 52 sfx, 371 voice clips, %d songs x 2 sets" % len(songs))
