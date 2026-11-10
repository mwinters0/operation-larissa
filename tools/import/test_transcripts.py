"""Tests of the voice transcript fixture and the hand corrections. No model is needed: the engine is not run.

Run with:  uv run --with pytest pytest tools/import/test_transcripts.py
"""
import json
import re
import sys
import tomllib
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import transcripts as t

MACHINE = {"NE1SOUND_4000": "All personnel on hand.", "NE1SOUND_4001": "The tide has turned.",
           "NE0SOUND_8000": "Beep."}


def fixture(machine=MACHINE, compute_type="int8"):
    return t.fixture_document(machine, compute_type)


def test_the_hash_is_the_sha256_of_the_utf8_text():
    assert t.text_hash("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    assert t.text_hash("é") == common.sha256_hex("é".encode())


def test_the_fixture_holds_a_hash_per_clip_and_no_text():
    doc = fixture()
    assert doc["clips"] == {name: t.text_hash(text) for name, text in MACHINE.items()}
    dumped = json.dumps(doc)
    assert not any(text in dumped for text in MACHINE.values())
    assert doc["engine"]["decoding"]["beam_size"] == 1 and doc["engine"]["decoding"]["temperature"] == 0.0
    assert doc["engine"]["compute_type"] == "int8"


def test_identical_transcripts_match_the_fixture():
    assert t.compare_fixture(MACHINE, fixture(), "int8").ok


def test_a_changed_transcript_is_reported_by_clip():
    changed = dict(MACHINE, NE1SOUND_4001="The tide has turned!")
    c = t.compare_fixture(changed, fixture(), "int8")
    assert not c.ok and c.changed == ["NE1SOUND_4001"] and not c.new and not c.gone


def test_new_and_missing_clips_are_reported():
    machine = dict(MACHINE, NE1SOUND_4002="Check systems.")
    del machine["NE0SOUND_8000"]
    c = t.compare_fixture(machine, fixture(), "int8")
    assert c.new == ["NE1SOUND_4002"] and c.gone == ["NE0SOUND_8000"] and not c.ok


def test_another_compute_type_is_noted_next_to_the_comparison():
    c = t.compare_fixture(MACHINE, fixture(), "float32")
    assert c.engine_differs == ["compute_type"]


def correction(name, machine=MACHINE, text="The right words."):
    return {name: {"machine_sha256": t.text_hash(machine[name]), "text": text}}


def test_a_correction_for_the_current_machine_text_is_used():
    c = t.sort_corrections(MACHINE, correction("NE1SOUND_4000"))
    assert c.used == {"NE1SOUND_4000": "The right words."} and not c.stale and not c.unknown
    final = t.final_transcripts(MACHINE, c)
    assert final["NE1SOUND_4000"] == "The right words." and final["NE1SOUND_4001"] == MACHINE["NE1SOUND_4001"]


def test_a_correction_goes_stale_when_the_machine_transcript_changes():
    corrections = correction("NE1SOUND_4000")
    now = dict(MACHINE, NE1SOUND_4000="All personnel on hand!")
    c = t.sort_corrections(now, corrections)
    assert c.stale == ["NE1SOUND_4000"] and not c.used
    assert t.final_transcripts(now, c)["NE1SOUND_4000"] == "All personnel on hand!"           # the machine text, not the old fix


def test_a_correction_for_a_clip_that_does_not_exist_is_unknown():
    c = t.sort_corrections(MACHINE, {"NE1SOUND_9999": {"machine_sha256": "0" * 64, "text": "x"}})
    assert c.unknown == ["NE1SOUND_9999"] and not c.used and not c.stale


def test_correct_writes_an_entry_keyed_to_the_machine_hash(tmp_path):
    path = tmp_path / "area" / "voice_corrections.json"          # the folder does not exist yet
    t.add_correction(path, MACHINE, "NE1SOUND_4001", "The tide has turned.  ")
    t.add_correction(path, MACHINE, "NE1SOUND_4000", "Fixed.")
    entries = t.load_corrections(path)
    assert sorted(entries) == ["NE1SOUND_4000", "NE1SOUND_4001"]
    assert entries["NE1SOUND_4000"] == {"machine_sha256": t.text_hash(MACHINE["NE1SOUND_4000"]), "text": "Fixed."}
    assert t.sort_corrections(MACHINE, entries).used["NE1SOUND_4000"] == "Fixed."
    with pytest.raises(KeyError):
        t.add_correction(path, MACHINE, "NE1SOUND_1", "no such clip")


def test_no_corrections_file_is_no_corrections(tmp_path):
    assert t.load_corrections(tmp_path / "nothing.json") == {}


def test_the_corrections_live_in_the_ignored_legacy_area():
    """The corrections are the game's speech: their folder must be ignored by version control."""
    assert common.VOICE_CORRECTIONS.parent == common.LEGACY_AREA
    assert "/godot/data/legacy/" in (common.ROOT / ".gitignore").read_text().splitlines()    # the default area, $NEP_LEGACY unset


def locked_version(package: str) -> str:
    lock = tomllib.loads((common.ROOT / "uv.lock").read_text())
    return next(p["version"] for p in lock["package"] if p["name"] == package)


def test_the_pins_in_the_code_are_the_locked_versions():
    assert t.FASTER_WHISPER == locked_version("faster-whisper")
    assert t.CTRANSLATE2 == locked_version("ctranslate2")


def test_the_model_is_pinned_by_revision_and_every_file_by_hash():
    assert re.fullmatch(r"[0-9a-f]{40}", t.MODEL_REVISION)
    assert set(t.MODEL_FILES) >= {"model.bin", "config.json", "tokenizer.json", "vocabulary.txt"}
    assert all(re.fullmatch(r"[0-9a-f]{64}", h) for h in t.MODEL_FILES.values())


def test_decoding_is_greedy_without_temperature_fallback():
    assert t.DECODING["beam_size"] == 1 and t.DECODING["best_of"] == 1
    assert isinstance(t.DECODING["temperature"], float) and t.DECODING["temperature"] == 0.0     # a list would allow fallback


def test_the_committed_fixture_is_well_formed_and_holds_no_text():
    path = t.FIXTURE
    if not path.is_file():
        pytest.skip("no fixture yet")
    doc = json.loads(path.read_text())
    assert sorted(doc["clips"]) == sorted(t.clip_names())
    assert all(re.fullmatch(r"[0-9a-f]{64}", h) for h in doc["clips"].values())
    assert doc["engine"] == t.engine_description(doc["engine"]["compute_type"])        # the pins in the code are the fixture's


def test_the_machine_transcripts_of_this_checkout_match_the_fixture():
    """Needs the importer's output: skipped without it. A difference is reported, as the importer does, by clip."""
    if not t.FIXTURE.is_file() or not t.OUT_MACHINE.is_file():
        pytest.skip(common.RUN_THE_IMPORTER)
    doc = json.loads(t.FIXTURE.read_text())
    c = t.compare_fixture(json.loads(t.OUT_MACHINE.read_text(encoding="utf-8")), doc, doc["engine"]["compute_type"])
    assert c.ok, "clips differ from the fixture: %s" % c.changed
