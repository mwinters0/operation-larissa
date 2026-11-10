"""Tests of the dev pack's audio generator (tools/dev_pack/audio.py) for the parts that need no Piper: the synth, the MIDI bytes, the
onomatopoeia table, the catalogs and the inventory. The last tests read the generated dev pack (and legacy's file list when it is there).

Run with:  uv run pytest tools/dev_pack/test_audio.py -q
"""
import re
import shutil
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import audio
import audio_synth
import common

DEV = audio.DEV_ROOT
needs_dev_audio = pytest.mark.skipif(not (DEV / "assets" / "audio" / "voice").exists(), reason="the dev pack's audio is not generated yet")


# ---- inventory and names ----------------------------------------------------------------------------------------------

def test_counts():
    assert len(audio.sfx_paths()) == 52
    assert len(audio.voice_paths()) == 371
    assert len(audio.songs()) == 10
    assert len(audio.music_paths(False)) == len(audio.music_paths(True)) == 10
    assert len(audio.midi_paths()) == 20
    assert len(set(audio.inventory())) == len(audio.inventory())


def test_onomatopoeia_covers_every_sound_name():
    sounds = audio.registry().entries("sound")
    assert set(audio.ONOMATOPOEIA) <= set(sounds), "a table entry for a name the registry does not have"
    missing = sorted(set(sounds) - set(audio.ONOMATOPOEIA))
    assert not missing, "named effects with no onomatopoeia: %s" % missing
    assert all(re.fullmatch(r"[a-z ]+", w) for w in audio.ONOMATOPOEIA.values())


def test_unnamed_effects_and_clips_say_their_made_up_name():
    assert audio.sfx_words("sfx_28") == "sfx 28"
    assert audio.sfx_words("click") == "click"
    assert audio.spoken(audio.name_of("voice", 4244)) == "voice 4244"


def test_file_names_follow_the_naming_rule():
    assert "assets/audio/sfx/click_34.wav" in audio.sfx_paths()
    assert "assets/audio/voice/jingle_4243.wav" in audio.voice_paths()
    assert "assets/audio/music/title_9503.ogg" in audio.music_paths(False)
    assert "assets/audio/music/adlib/title_9503.ogg" in audio.music_paths(True)
    assert "midi/BSECT1.MID" in audio.midi_paths() and "midi/ESECT1.MID" in audio.midi_paths()


@pytest.mark.legacy
def test_inventory_matches_legacy_audio_paths():
    legacy = {p.relative_to(common.LEGACY).as_posix() for sub in ("assets/audio", "midi")
              for p in (common.LEGACY / sub).rglob("*") if p.is_file()}
    assert set(audio.inventory()) == legacy


# ---- voice groups -----------------------------------------------------------------------------------------------------

def test_voice_groups_have_the_names_of_the_importers_groups():
    groups = audio.voice_groups()
    assert len(groups) == 5 + 9 + 30 + 30 + 3
    for name in ("jingle", "sign_in_resume", "story_page_3", "supply_29", "log_0", "closing_page_2"):
        assert groups[name], name
    assert all(groups.values()), [g for g, c in groups.items() if not c]
    ids = [i for clips in groups.values() for i in clips]
    assert len(ids) == len(set(ids)), "a clip in two groups"
    assert all(audio.VOICE_FIRST <= i <= audio.VOICE_LAST for i in ids)


def test_log_1_does_not_swallow_log_10():
    groups = audio.voice_groups()
    names = audio.registry().entries("voice")
    assert [n for n, i in names.items() if i in groups["log_1"]] == ["log_1_%d" % k for k in range(len(groups["log_1"]))]


# ---- catalogs ---------------------------------------------------------------------------------------------------------

def test_sfx_catalog():
    text = audio.sfx_catalog_text()
    assert 'script_class="SfxCatalog"' in text
    assert text.count('type="AudioStreamWAV"') == 52
    assert all("res://packs/dev/assets/audio/sfx/" in line for line in text.splitlines() if "AudioStreamWAV" in line)
    cues_match = re.search(r"diagram_cues = \{(.*)\}", text)
    assert cues_match is not None
    cues = cues_match.group(1)
    sounds = audio.registry().entries("sound")
    assert {int(v) for v in re.findall(r": (\d+)", cues)} <= {sounds[n] for n in audio.DIAGRAM_SOUNDS}


def test_music_catalog():
    text = audio.music_catalog_text()
    assert "ids = PackedInt32Array(9500, 9501, 9502, 9503, 9504, 9505, 9506, 9507, 9508, 9509)" in text
    assert text.count("res://packs/dev/assets/audio/music/adlib/") == 10
    assert text.count("res://packs/dev/assets/audio/music/") == 20
    assert '"BSECT1.MID"' in text


def test_voice_index_holds_dev_text_and_the_given_durations():
    text = audio.voice_index_text([73] * 371)
    assert "ids = PackedInt32Array(4000, 4001" in text
    assert '"opening cartoon 0"' in text and '"voice 4244"' in text
    transcripts_match = re.search(r"transcripts = PackedStringArray\((.*)\)", text)
    assert transcripts_match is not None
    assert "_" not in transcripts_match.group(1)
    assert re.search(r"durations = PackedInt32Array\(73, 73", text)


def test_voice_cues_text():
    text = audio.voice_cues_text()
    assert '"jingle": PackedInt32Array(4243)' in text
    assert '"closing_page_2": PackedInt32Array(4367, 4368, 4369, 4370)' in text


def test_resource_prefix(tmp_path):
    assert audio.res_prefix_of(tmp_path) == "res://packs/dev/"
    assert audio.res_prefix_of(common.GODOT / "packs" / "dev") == "res://packs/dev/"


# ---- sidecars and ticks -----------------------------------------------------------------------------------------------

def test_sidecar_stub_has_a_path_derived_uid(tmp_path):
    wav = tmp_path / "assets" / "audio" / "sfx" / "click_34.wav"
    wav.parent.mkdir(parents=True)
    wav.write_bytes(b"")
    audio.put_sidecar(wav, "res://packs/dev/", tmp_path)
    text = (wav.parent / "click_34.wav.import").read_text()
    assert 'importer="wav"' in text and 'type="AudioStreamWAV"' in text
    assert 'uid="%s"' % audio.import_uids.uid_of("res://packs/dev/assets/audio/sfx/click_34.wav") in text
    (wav.parent / "click_34.wav.import").write_text("Godot's own")
    audio.put_sidecar(wav, "res://packs/dev/", tmp_path)
    assert (wav.parent / "click_34.wav.import").read_text() == "Godot's own"


def test_wav_ticks_round_up(tmp_path):
    path = tmp_path / "x.wav"
    path.write_bytes(audio.wav_bytes(np.zeros(16000), 16000))          # exactly 1 s = 73 ticks
    assert audio.wav_ticks(path) == 73
    path.write_bytes(audio.wav_bytes(np.zeros(16001), 16000))
    assert audio.wav_ticks(path) == 74


def test_wav_ticks_agrees_with_the_importers(tmp_path):
    import step_audio
    for frames, rate in ((1, 16000), (777, 16000), (16000, 16000), (22051, 22050)):
        path = tmp_path / "x.wav"
        path.write_bytes(audio.wav_bytes(np.zeros(frames), rate))
        assert audio.wav_ticks(path) == step_audio.wav_ticks(path)


# ---- synth and MIDI ---------------------------------------------------------------------------------------------------

def test_songs_differ_in_key_and_tempo():
    songs = [audio_synth.Song(i) for i in range(10)]
    assert len({s.root for s in songs}) == 10
    assert len({s.bpm for s in songs}) == 10
    assert len({tuple(s.melody) for s in songs}) == 10
    assert all(s.melody[0] == s.root + 12 for s in songs)


def test_song_render_is_deterministic_and_the_right_length():
    speech = np.sin(np.arange(22050) * 0.1) * 0.5                       # a stand-in for the spoken name
    a = audio_synth.render_song(3, False, speech, 22050)
    b = audio_synth.render_song(3, False, speech, 22050)
    assert np.array_equal(a, b)
    assert 10.0 <= a.size / audio_synth.RATE <= 20.0
    assert float(np.max(np.abs(a))) <= 0.9 + 1e-9
    assert not np.array_equal(a, audio_synth.render_song(4, False, speech, 22050))


def test_adlib_set_is_squarer():
    gm = audio_synth.tone(60, 0.5, False, 0.5)
    ad = audio_synth.tone(60, 0.5, True, 0.5)

    def flatness(x):                          # a square wave spends its time at the extremes: more samples near the peak
        top = np.abs(x[2000:12000])
        return float(np.mean(top > 0.8 * top.max()))

    assert flatness(ad) > flatness(gm) * 2


def test_midi_files_are_valid_and_small():
    for i in range(10):
        for adlib in (False, True):
            data = audio_synth.midi_bytes(i, adlib)
            info = audio_synth.parse_midi(data)
            song = audio_synth.Song(i)
            assert info["format"] == 0 and info["tracks"] == 1 and info["ended"]
            assert info["tempo"] == 60_000_000 // song.bpm
            assert info["notes"] == [n for n in song.melody * 2 if n is not None]
            assert len(data) < 600
    assert audio_synth.midi_bytes(2, False) != audio_synth.midi_bytes(2, True)
    assert audio_synth.vlq(0) == b"\x00" and audio_synth.vlq(128) == b"\x81\x00"


@pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg not installed")
def test_encode_ogg_is_mono_vorbis(tmp_path):
    ogg = audio.encode_ogg(np.sin(np.arange(audio_synth.RATE) * 0.05) * 0.5)
    path = tmp_path / "x.ogg"
    path.write_bytes(ogg)
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,channels,sample_rate", "-of", "csv=p=0", str(path)],
                         check=True, capture_output=True, text=True).stdout.strip()
    assert out == "vorbis,44100,1"
    assert audio.encode_ogg(np.sin(np.arange(audio_synth.RATE) * 0.05) * 0.5) == ogg      # bitexact: the same bytes twice


# ---- the generated pack -----------------------------------------------------------------------------------------------

@needs_dev_audio
def test_generated_files_match_the_inventory():
    for relative in audio.inventory():
        assert (DEV / relative).is_file(), relative
    on_disk = {p.relative_to(DEV).as_posix() for sub in ("assets/audio", "midi") for p in (DEV / sub).rglob("*") if p.is_file()}
    assert on_disk == set(audio.inventory())


@needs_dev_audio
def test_generated_catalog_files_are_what_the_code_writes():
    ticks = [audio.wav_ticks(DEV / p) for p in audio.voice_paths()]
    assert (DEV / "data" / "sfx_catalog.tres").read_text() == audio.sfx_catalog_text()
    assert (DEV / "data" / "music_catalog.tres").read_text() == audio.music_catalog_text()
    assert (DEV / "data" / "voice_index.tres").read_text() == audio.voice_index_text(ticks)
    assert (DEV / "data" / "voice_cues.tres").read_text() == audio.voice_cues_text()


@needs_dev_audio
def test_generated_audio_formats_and_sizes():
    for relative in audio.sfx_paths() + audio.voice_paths():
        with wave.open(str(DEV / relative)) as w:
            assert w.getnchannels() == 1 and w.getsampwidth() == 2
            assert 0.1 <= w.getnframes() / w.getframerate() <= 10, relative
    total = sum(p.stat().st_size for p in (DEV / "assets" / "audio").rglob("*") if p.is_file())
    assert total < 40_000_000
