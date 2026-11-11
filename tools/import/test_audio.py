"""Checks on the audio the importer produced: durations, loudness, clipping, loop seams, and the cue tables.

Run with:  uv run --with pytest pytest tools/import/test_audio.py
The OGG checks decode the files with ffmpeg and are skipped when it is not installed.
"""
import array
import json
import math
import shutil
import subprocess
import sys
import wave
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asset_names
import common

MUSIC = common.ASSETS / "audio" / "music"
SONGS = [e for e in common.load_json(common.DOCS_DATA / "music_map.json")["music"]]
OGG_FILES = sorted(MUSIC.glob("*.ogg")) + sorted((MUSIC / "adlib").glob("*.ogg"))

needs_ffmpeg = pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg not installed")


def decode(path: Path) -> array.array:
    """The file as 44.1 kHz mono signed 16-bit samples."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "s16le", "-ac", "1", "-ar", "44100", "-"],
                         check=True, capture_output=True).stdout
    samples = array.array("h")
    samples.frombytes(raw)
    return samples


def rms_db(samples: array.array) -> float:
    if not samples:
        return -120.0
    mean_square = sum(s * s for s in samples) / len(samples)
    return 20 * math.log10(max(math.sqrt(mean_square) / 32768, 1e-6))


@pytest.mark.legacy
def test_both_sets_cover_the_ten_songs():
    assert len(SONGS) == 10
    assert len(OGG_FILES) == 20
    for entry in SONGS:
        stem = entry["file"].rsplit(".", 1)[0][1:].lower()
        assert asset_names.music_file(entry["id"], "e" + stem).exists()
        assert asset_names.music_file(entry["id"], "b" + stem, adlib=True).exists()


def test_the_music_table_is_the_verified_map():
    audio_map = common.load_json(common.DOCS_DATA / "audio_map.json")
    assert [(m["id"], m["file"]) for m in audio_map["music"]] == [(s["id"], s["file"]) for s in SONGS]
    assert all(m["loop_start"] == 0 for m in audio_map["music"])        # every song restarts from its beginning


@needs_ffmpeg
@pytest.mark.parametrize("path", OGG_FILES, ids=lambda p: p.parent.name + "/" + p.name)
def test_song_is_long_loud_enough_unclipped_and_loops_cleanly(path):
    samples = decode(path)
    seconds = len(samples) / 44100
    assert 30 < seconds < 200, "duration %.1f s" % seconds
    peak = max(max(samples), -min(samples)) / 32768
    assert peak < 0.99, "peak %.3f would clip" % peak
    assert peak > 0.1, "peak %.3f is nearly silent" % peak
    assert rms_db(samples) > -30, "average level %.1f dB is too quiet" % rms_db(samples)
    assert rms_db(samples) < -12, "average level %.1f dB is too loud next to the other songs" % rms_db(samples)
    # the song starts at once (no leading silence) ...
    first_sound = next(i for i, s in enumerate(samples) if abs(s) > 33)
    assert first_sound < 0.1 * 44100
    # ... and the jump from its last sample back to its first is small (no click at the loop point)
    assert abs(samples[-1] - samples[0]) / 32768 < 0.02
    # the tail was trimmed: the last 50 ms are quiet
    assert rms_db(samples[-2205:]) < -25


@pytest.mark.legacy
def test_every_cue_group_names_existing_clips():
    cues = common.load_json(common.DOCS_DATA / "audio_map.json")["voice"]
    clips = [c for key, value in cues.items() for c in _flatten(value)]
    assert clips and all(4000 <= c <= 4370 for c in clips)
    for c in set(clips):
        assert asset_names.voice_file(c).exists()
    assert len(cues["supply"]) == 30 and len(cues["logs"]) == 30 and len(cues["closing_pages"]) == 3


@pytest.mark.legacy
def test_log_clips_say_the_entry_number_of_the_log_text():
    cues = common.load_json(common.DOCS_DATA / "audio_map.json")["voice"]
    transcripts_file = common.EXTRACTED / "sounds" / "voice_transcripts.json"
    if not transcripts_file.exists():
        pytest.skip("no voice transcripts: the importer ran with --no-transcripts")
    transcripts = common.load_json(transcripts_file)
    texts = {t["id"]: t["text"] for t in common.load_json(common.EXTRACTED / "data" / "NEP_text.json")}
    for n, clips in enumerate(cues["logs"]):
        header = texts[10648 + n].split(":", 1)[0]                       # "ENTRY 1.01"
        spoken = transcripts["NE1SOUND_%d" % clips[1]].strip()
        assert header.endswith(spoken), (n, header, spoken)


def test_effects_exist_and_every_documented_one_has_a_name():
    """audio_map.json lists the effects the decompilation found (number, when, where); their names are in the registry."""
    audio_map = common.load_json(common.DOCS_DATA / "audio_map.json")
    registry = json.loads((common.GODOT / "names" / "original.json").read_text())["names"]["sound"]
    assert {int(k) for k in audio_map["sfx"]} <= set(registry.values())
    assert all("name" not in v for v in audio_map["sfx"].values())          # one place for names
    assert all(0 <= int(k) < 52 for k in audio_map["sfx"])
    assert all(0 <= int(v) < 52 for v in audio_map["diagram_cues"].values())
    assert set(audio_map["diagram_cues"].values()) <= {int(k) for k in audio_map["sfx"]}


def _flatten(value):
    if isinstance(value, list):
        for item in value:
            yield from _flatten(item)
    else:
        yield value


def wav_rate(path: Path) -> int:
    with wave.open(str(path)) as w:
        return w.getframerate()


@pytest.mark.legacy
def test_wav_rates_are_the_rates_the_original_plays_them_at():
    """Every resource header says 22050 Hz, but the game plays the effects at that rate, the opening-cartoon voices
    (4000-4010) at 8000 Hz and all other speech at 16000 Hz (DESIGN section 7: set_sample_speed (0x4150b1) override)."""
    assert {wav_rate(asset_names.sfx_file(n)) for n in range(52)} == {22050}
    for clip in range(4000, 4371):
        expected = 8000 if clip <= 4010 else 16000
        assert wav_rate(asset_names.voice_file(clip)) == expected, clip


@pytest.mark.legacy
def test_voice_durations_are_the_lengths_of_the_original_clips_in_ticks_of_one_73rd_second():
    """The game waits for a clip this long (godot/data/voice_index.tres `durations`), never for the stream that plays."""
    import re
    text = (common.PACK_DATA / "voice_index.tres").read_text()
    ids_match = re.search(r"ids = PackedInt32Array\((.*?)\)", text)
    assert ids_match is not None
    ids = [int(x) for x in ids_match.group(1).split(",")]
    durations_match = re.search(r"durations = PackedInt32Array\((.*?)\)", text)
    assert durations_match is not None
    durations = [int(x) for x in durations_match.group(1).split(",")]
    assert ids == list(range(4000, 4371)) and len(durations) == 371
    for vid, ticks in zip(ids, durations):
        with wave.open(str(asset_names.voice_file(vid))) as w:
            assert ticks == -(-w.getnframes() * 73 // w.getframerate()), vid          # rounded up, in whole ticks
        assert ticks > 0


# --- when music is rendered again (step_audio.render_set) ----------------------------------------------------------

def _fake_set(tmp_path, monkeypatch):
    """Two MIDI files and a soundfont in tmp_path; render_music only records which songs it was asked for."""
    import step_audio
    midi = tmp_path / "midi"
    midi.mkdir()
    for stem in ("esect1", "esect2"):
        (midi / (stem.upper() + ".MID")).write_bytes(b"MThd" + stem.encode())
    font = tmp_path / "a.sf2"
    font.write_bytes(b"font a")
    calls = []

    def fake_render(src, dest, soundfont):
        calls.append(dest.stem)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"ogg")
    monkeypatch.setattr(step_audio, "render_music", fake_render)
    return step_audio, midi, font, tmp_path / "out", calls


def test_a_set_is_rendered_once_and_again_only_for_what_changed(tmp_path, monkeypatch):
    step_audio, midi, font, out, calls = _fake_set(tmp_path, monkeypatch)
    stems = ["esect1", "esect2"]
    assert step_audio.render_set(stems, out, str(font), midi) == 2
    assert step_audio.render_set(stems, out, str(font), midi) == 0         # nothing changed
    (midi / "ESECT1.MID").touch()                                            # re-extracted: new time, same bytes
    assert step_audio.render_set(stems, out, str(font), midi) == 0
    (midi / "ESECT2.MID").write_bytes(b"MThd changed")                       # one MIDI file changed
    assert step_audio.render_set(stems, out, str(font), midi) == 1 and calls[-1] == "esect2"
    other = tmp_path / "b.sf2"                                               # another soundfont: everything
    other.write_bytes(b"font b")
    assert step_audio.render_set(stems, out, str(other), midi) == 2
    (out / "esect1.ogg").unlink()                                            # a missing OGG
    assert step_audio.render_set(stems, out, str(other), midi) == 1
    stamp = json.loads((out / step_audio.STAMP).read_text())
    assert stamp["soundfont"] == "b.sf2" and set(stamp["songs"]) == set(stems)


@pytest.mark.legacy
def test_the_committed_music_records_what_it_was_rendered_from():
    import step_audio
    for folder, letter in ((MUSIC, "E"), (MUSIC / "adlib", "B")):
        stamp = common.load_json(folder / step_audio.STAMP)
        assert set(stamp["songs"]) == {step_audio.music_stems(e, letter) for e in SONGS}
        assert len(stamp["soundfont_sha256"]) == 64


# --- the music is fixed by the hashes of its MIDI files (docs/port/FIDELITY.md) -----------------------------------------
# A rendered song cannot be hash-checked: FluidSynth does not render the same samples twice. What fixes the music is the
# MIDI file. Two committed files hold its SHA-256: tools/import/source_files.json (every file of the CD, checked against
# YOUR copy before the importer reads anything, so a patched MIDI file is refused) and each music folder's
# rendered_with.json (what the OGGs next to it were rendered from). They must agree, and the catalog must name the files.

def midi_hashes() -> dict[str, str]:
    """'ESECT1.MID' -> SHA-256, from the reference release's table (source_files.json)."""
    import source_files
    files = source_files.load_table()
    return {path.rsplit("/", 1)[1]: entry["sha256"] for path, entry in files.items() if path.upper().endswith(".MID")}


def test_the_reference_release_holds_the_twenty_midi_files_of_the_two_sets():
    hashes = midi_hashes()
    assert sorted(hashes) == sorted(e["file"].replace("B", letter, 1) for e in SONGS for letter in "BE")


@pytest.mark.parametrize("folder, letter", [(MUSIC, "E"), (MUSIC / "adlib", "B")], ids=["general midi", "adlib"])
@pytest.mark.legacy
def test_rendered_with_names_the_midi_files_of_the_reference_release(folder, letter):
    stamp = json.loads((folder / "rendered_with.json").read_text())
    hashes = midi_hashes()
    expected = {(letter + e["file"][1:]).rsplit(".", 1)[0].lower(): hashes[letter + e["file"][1:]] for e in SONGS}
    assert stamp["songs"] == expected
    for e in SONGS:
        assert asset_names.music_file(e["id"], (letter + e["file"][1:]).rsplit(".", 1)[0].lower(), adlib=folder != MUSIC).exists()


@pytest.mark.legacy
def test_the_catalog_names_the_midi_files_the_stamps_hash():
    import re
    text = (common.PACK_DATA / "music_catalog.tres").read_text()
    names_match = re.search(r"midi_names = PackedStringArray\((.*)\)", text)
    assert names_match is not None
    names = names_match.group(1)
    assert re.findall(r'"([^"]+)"', names) == [e["file"] for e in SONGS]


def test_the_extracted_midi_files_are_the_reference_ones():
    hashes = midi_hashes()
    for name, sha in hashes.items():
        path = common.EXTRACTED / "music" / name
        if not path.exists():
            pytest.skip("no extracted MIDI files (run tools/extract/run_all.sh)")
        assert common.sha256_hex(path.read_bytes()) == sha, name
