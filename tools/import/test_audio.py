"""Checks on the audio the importer produced: durations, loudness, clipping, loop seams, and the cue tables.

Run with:  uv run --with pytest pytest tools/import/test_audio.py
The OGG checks decode the files with ffmpeg and are skipped when it is not installed.
"""
import array
import functools
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


@functools.cache
def songs() -> list[dict]:
    """The ten songs of extracted/tables/music_map.json (written by the importer's tables step: read lazily, so collecting this file needs no table)."""
    return common.load_json(common.TABLES / "music_map.json")["music"]


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
    assert len(songs()) == 10
    assert len(OGG_FILES) == 20
    for entry in songs():
        stem = entry["file"].rsplit(".", 1)[0][1:].lower()
        assert asset_names.music_file(entry["id"], "e" + stem).exists()
        assert asset_names.music_file(entry["id"], "b" + stem, adlib=True).exists()


@pytest.mark.legacy
def test_the_music_table_is_the_verified_map():
    audio_map = common.load_json(common.TABLES / "audio_map.json")
    assert [(m["id"], m["file"]) for m in audio_map["music"]] == [(s["id"], s["file"]) for s in songs()]
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
    cues = common.load_json(common.TABLES / "audio_map.json")["voice"]
    clips = [c for key, value in cues.items() for c in _flatten(value)]
    assert clips and all(4000 <= c <= 4370 for c in clips)
    for c in set(clips):
        assert asset_names.voice_file(c).exists()
    assert len(cues["supply"]) == 30 and len(cues["logs"]) == 30 and len(cues["closing_pages"]) == 3


@pytest.mark.legacy
def test_log_clips_say_the_entry_number_of_the_log_text():
    cues = common.load_json(common.TABLES / "audio_map.json")["voice"]
    transcripts_file = common.EXTRACTED / "sounds" / "voice_transcripts.json"
    if not transcripts_file.exists():
        pytest.skip("no voice transcripts: the importer ran with --no-transcripts")
    transcripts = common.load_json(transcripts_file)
    texts = {t["id"]: t["text"] for t in common.load_json(common.EXTRACTED / "data" / "NEP_text.json")}
    for n, clips in enumerate(cues["logs"]):
        header = texts[10648 + n].split(":", 1)[0]                       # "ENTRY 1.01"
        spoken = transcripts["NE1SOUND_%d" % clips[1]].strip()
        assert header.endswith(spoken), (n, header, spoken)


@pytest.mark.legacy
def test_effects_exist_and_every_documented_one_has_a_name():
    """audio_map.json lists the effects the decompilation found (number, when, where); their names are in the registry."""
    audio_map = common.load_json(common.TABLES / "audio_map.json")
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

def _fake_set(tmp_path, monkeypatch, prefix="e"):
    """Two MIDI files and a soundfont in tmp_path; render_music only records which songs it was asked for, and with what bytes."""
    import step_audio
    midi = tmp_path / "midi"
    midi.mkdir()
    for stem in (prefix + "sect1", prefix + "sect2"):
        (midi / (stem.upper() + ".MID")).write_bytes(smf(b"\x00\x90\x3c\x40"))
    font = tmp_path / "a.sf2"
    font.write_bytes(b"font a")
    calls = []

    def fake_render(midi_bytes, dest, soundfont):
        calls.append((dest.stem, midi_bytes))
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
    (midi / "ESECT2.MID").write_bytes(smf(b"\x00\x90\x3e\x40"))             # one MIDI file changed
    assert step_audio.render_set(stems, out, str(font), midi) == 1 and calls[-1][0] == "esect2"
    other = tmp_path / "b.sf2"                                               # another soundfont: everything
    other.write_bytes(b"font b")
    assert step_audio.render_set(stems, out, str(other), midi) == 2
    (out / "esect1.ogg").unlink()                                            # a missing OGG
    assert step_audio.render_set(stems, out, str(other), midi) == 1
    stamp = json.loads((out / step_audio.STAMP).read_text())
    assert stamp["soundfont"] == "b.sf2" and set(stamp["songs"]) == set(stems)
    assert "recipe" not in stamp                                             # the General MIDI set is rendered from the file as it is


def test_the_general_midi_set_is_rendered_from_the_original_bytes(tmp_path, monkeypatch):
    step_audio, midi, font, out, calls = _fake_set(tmp_path, monkeypatch)
    step_audio.render_set(["esect1"], out, str(font), midi)
    assert calls[0][1] == (midi / "ESECT1.MID").read_bytes()


def test_the_adlib_set_is_rendered_from_the_file_with_its_percussion_on_channel_10(tmp_path, monkeypatch):
    step_audio, midi, font, out, calls = _fake_set(tmp_path, monkeypatch, "b")
    (midi / "BSECT1.MID").write_bytes(smf(b"\x00\x9f\x24\x64" b"\x10\x8f\x24\x00"))
    stems = ["bsect1", "bsect2"]
    assert step_audio.render_set(stems, out, str(font), midi, adlib=True) == 2
    assert dict(calls)["bsect1"] == smf(b"\x00\x99\x24\x64" b"\x10\x89\x24\x00")
    assert dict(calls)["bsect2"] == (midi / "BSECT2.MID").read_bytes()       # no channel 16: nothing to move
    stamp = json.loads((out / step_audio.STAMP).read_text())
    assert stamp["recipe"] == step_audio.ADLIB_RECIPE
    assert stamp["songs"]["bsect1"] == common.sha256_hex((midi / "BSECT1.MID").read_bytes())    # the hash is the CD file's
    assert step_audio.render_set(stems, out, str(font), midi, adlib=True) == 0


def test_a_set_rendered_before_the_recipe_is_rendered_again_once(tmp_path, monkeypatch):
    step_audio, midi, font, out, _calls = _fake_set(tmp_path, monkeypatch, "b")
    stems = ["bsect1", "bsect2"]
    step_audio.render_set(stems, out, str(font), midi, adlib=True)
    stamp_path = out / step_audio.STAMP
    stamp = json.loads(stamp_path.read_text())
    del stamp["recipe"]                                                      # a stamp written before the percussion was moved
    stamp_path.write_text(json.dumps(stamp))
    assert step_audio.render_set(stems, out, str(font), midi, adlib=True) == 2
    assert step_audio.render_set(stems, out, str(font), midi, adlib=True) == 0
    assert step_audio.render_set(stems, out, str(font), midi) == 2           # the same folder asked for without the recipe: again


def test_an_adlib_song_with_a_channel_10_is_rendered_as_it_is_and_says_so(tmp_path, monkeypatch, capsys):
    step_audio, midi, font, out, calls = _fake_set(tmp_path, monkeypatch, "b")
    both = smf(b"\x00\x99\x24\x64" b"\x00\x9f\x24\x64")
    (midi / "BSECT1.MID").write_bytes(both)
    step_audio.render_set(["bsect1"], out, str(font), midi, adlib=True)
    assert dict(calls)["bsect1"] == both
    assert "BSECT1.MID" in capsys.readouterr().out


# --- the AdLib percussion channel (step_audio.percussion_to_channel_10) -----------------------------------------------

def smf(events: bytes, tracks: int = 1) -> bytes:
    """A format-0 (or format-1, more tracks) MIDI file with the given event bytes (delta times included) in each track."""
    track = b"MTrk" + len(events + b"\x00\xff\x2f\x00").to_bytes(4, "big") + events + b"\x00\xff\x2f\x00"
    return b"MThd\x00\x00\x00\x06\x00" + (b"\x00" if tracks == 1 else b"\x01") + tracks.to_bytes(2, "big") + b"\x01\xe0" + track * tracks


def test_every_event_on_channel_16_moves_to_channel_10_and_nothing_else_changes():
    import step_audio
    program = b"\x00\xcd\x0b"                       # a program change on channel 14
    pitch = b"\x00\xef\x00\x40"                     # a pitch bend on channel 16
    note_on, note_off, touch = b"\x00\x9f\x24\x64", b"\x83\x60\x8f\x24\x00", b"\x00\xdf\x30"
    meta = b"\x00\xff\x51\x03\x07\xa1\x20" b"\x00\xff\x03\x04" b"Name"
    sysex = b"\x00\xf0\x05\x7e\x7f\x09\x01\xf7"
    source = smf(program + meta + pitch + note_on + sysex + note_off + touch)
    moved = step_audio.percussion_to_channel_10(source)
    assert moved == smf(program + meta + b"\x00\xe9\x00\x40" + b"\x00\x99\x24\x64" + sysex + b"\x83\x60\x89\x24\x00" + b"\x00\xd9\x30")
    assert len(moved) == len(source)


def test_running_status_follows_the_status_byte_that_is_changed():
    import step_audio
    # note on ch16, then two more notes on running status, then a channel 14 note with its own status byte, then running status on it
    source = smf(b"\x00\x9f\x24\x64" b"\x01\x26\x64" b"\x01\x28\x64" b"\x01\x9d\x3c\x40" b"\x01\x3e\x40")
    assert step_audio.percussion_to_channel_10(source) == smf(
        b"\x00\x99\x24\x64" b"\x01\x26\x64" b"\x01\x28\x64" b"\x01\x9d\x3c\x40" b"\x01\x3e\x40")


def test_a_data_byte_that_looks_like_a_status_of_channel_16_is_not_touched():
    import step_audio
    # a meta event's text and a system exclusive's bytes hold 0x9F and 0x8F, and a delta time is a variable-length number
    source = smf(b"\x00\xff\x01\x02\x9f\x8f" b"\x00\xf0\x03\x7d\x7f\xf7" b"\x8f\x7f\x9d\x3c\x40")
    assert step_audio.percussion_to_channel_10(source) == source


def test_every_track_of_a_file_is_moved_and_a_file_without_channel_16_comes_back_as_it_is():
    import step_audio
    assert step_audio.percussion_to_channel_10(smf(b"\x00\x9f\x24\x64", tracks=2)) == smf(b"\x00\x99\x24\x64", tracks=2)
    melodic = smf(b"\x00\x9d\x3c\x40")
    assert step_audio.percussion_to_channel_10(melodic) is melodic
    assert step_audio.percussion_to_channel_10(smf(b"\x00\x99\x24\x64")) == smf(b"\x00\x99\x24\x64")      # General MIDI: as it is


def test_a_file_that_already_has_channel_10_is_refused():
    import step_audio
    with pytest.raises(step_audio.MidiChannelRefused, match="channel 10"):
        step_audio.percussion_to_channel_10(smf(b"\x00\x99\x24\x64" b"\x00\x9f\x24\x64"))


@pytest.mark.parametrize("data", [b"", b"RIFF" + bytes(20), smf(b"\x00\x9f\x24")[:-5], smf(b"\x00\x9f\x24\x64")[:20],
                                  smf(b"\x00\x26\x64"), smf(b"\x00\xf5\x01")],
                         ids=["empty", "not midi", "track cut short", "track cut short again", "no running status yet", "undefined status"])
def test_a_file_that_does_not_parse_is_refused(data):
    import step_audio
    with pytest.raises(step_audio.MidiChannelRefused):
        step_audio.percussion_to_channel_10(data)


@pytest.mark.legacy
def test_the_ten_adlib_songs_move_their_percussion_without_losing_an_event():
    import step_audio
    for entry in songs():
        data = (common.EXTRACTED / "music" / entry["file"]).read_bytes()
        moved = step_audio.percussion_to_channel_10(data)
        before = [status & 0x0F for _, status in step_audio._channel_events(data)]
        after = [status & 0x0F for _, status in step_audio._channel_events(moved)]
        assert 15 in before and 9 not in before, entry["file"]                  # the MPC layout: 13-16, percussion on 16
        assert after == [9 if channel == 15 else channel for channel in before], entry["file"]
        assert len(moved) == len(data)
        assert [i for i in range(len(data)) if data[i] != moved[i]] and 15 not in after


@pytest.mark.legacy
def test_the_committed_music_records_what_it_was_rendered_from():
    import step_audio
    for folder, letter in ((MUSIC, "E"), (MUSIC / "adlib", "B")):
        stamp = common.load_json(folder / step_audio.STAMP)
        assert set(stamp["songs"]) == {step_audio.music_stems(e, letter) for e in songs()}
        assert len(stamp["soundfont_sha256"]) == 64
        assert stamp.get("recipe", "") == (step_audio.ADLIB_RECIPE if letter == "B" else "")


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


@pytest.mark.legacy
def test_the_reference_release_holds_the_twenty_midi_files_of_the_two_sets():
    hashes = midi_hashes()
    assert sorted(hashes) == sorted(e["file"].replace("B", letter, 1) for e in songs() for letter in "BE")


@pytest.mark.parametrize("folder, letter", [(MUSIC, "E"), (MUSIC / "adlib", "B")], ids=["general midi", "adlib"])
@pytest.mark.legacy
def test_rendered_with_names_the_midi_files_of_the_reference_release(folder, letter):
    stamp = json.loads((folder / "rendered_with.json").read_text())
    hashes = midi_hashes()
    expected = {(letter + e["file"][1:]).rsplit(".", 1)[0].lower(): hashes[letter + e["file"][1:]] for e in songs()}
    assert stamp["songs"] == expected
    for e in songs():
        assert asset_names.music_file(e["id"], (letter + e["file"][1:]).rsplit(".", 1)[0].lower(), adlib=folder != MUSIC).exists()


@pytest.mark.legacy
def test_the_catalog_names_the_midi_files_the_stamps_hash():
    import re
    text = (common.PACK_DATA / "music_catalog.tres").read_text()
    names_match = re.search(r"midi_names = PackedStringArray\((.*)\)", text)
    assert names_match is not None
    names = names_match.group(1)
    assert re.findall(r'"([^"]+)"', names) == [e["file"] for e in songs()]


def test_the_extracted_midi_files_are_the_reference_ones():
    hashes = midi_hashes()
    for name, sha in hashes.items():
        path = common.EXTRACTED / "music" / name
        if not path.exists():
            pytest.skip("no extracted MIDI files (run tools/extract/run_all.sh)")
        assert common.sha256_hex(path.read_bytes()) == sha, name
