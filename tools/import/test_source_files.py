"""pytest checks of source_files.py: the committed table of the reference release matches NEPTUNE.ISO (skipped without the image),
a different or patched copy is refused with the names of the files, and the importer checks it before it does anything."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import import_all
import source_files as sf


def need_iso():
    try:
        sf.gamefiles.iso_file()
    except sf.gamefiles.MissingISO as e:
        pytest.skip(str(e))


def _fake_cd(files: dict[str, bytes]):
    return (lambda path: files[path]), (lambda folder: sorted(files))


def _reference_cd() -> dict[str, bytes]:
    """A made-up CD whose files have exactly the sizes and hashes of a made-up table."""
    return {"ONWINCD/A.DLL": b"first file", "ONWINCD/SOUNDS/B.MID": b"second"}


def _table_of(files: dict[str, bytes], tmp_path: Path) -> Path:
    path = tmp_path / "source_files.json"
    path.write_text(sf.build_table(sf.current(*_fake_cd(files))))
    return path


def test_the_committed_table_holds_only_names_sizes_and_hashes():
    parsed = json.loads(sf.TABLE.read_text())
    assert parsed["folder"] == "ONWINCD" and len(parsed["files"]) >= 30
    for path, entry in parsed["files"].items():
        assert path.startswith("ONWINCD/") and set(entry) == {"size", "sha256"} and len(entry["sha256"]) == 64
    for name in ("NEP.DLL", "NEP256.DLL", "NEPBG1.DLL", "NEPBG2.DLL", "NE0SOUND.DLL", "NE1SOUND.DLL", "ONWIN.EXE", "ONWIN32.EXE"):
        assert "ONWINCD/" + name in parsed["files"]
    assert sf.TABLE.read_text() == sf.build_table(sf.load_table())                # the layout --write produces


def test_your_copy_of_the_game_is_the_reference_release():
    need_iso()
    sf.check()


def test_a_copy_that_matches_the_table_passes(tmp_path):
    files = _reference_cd()
    sf.check(_table_of(files, tmp_path), *_fake_cd(files))


def test_a_patched_file_is_refused_and_named(tmp_path):
    table = _table_of(_reference_cd(), tmp_path)
    patched = {**_reference_cd(), "ONWINCD/A.DLL": b"first fime"}
    with pytest.raises(sf.DifferentRelease, match=r"different version or patched.*ONWINCD/A\.DLL differs"):
        sf.check(table, *_fake_cd(patched))


def test_a_missing_and_an_extra_file_are_refused(tmp_path):
    table = _table_of(_reference_cd(), tmp_path)
    with pytest.raises(sf.DifferentRelease, match=r"ONWINCD/SOUNDS/B\.MID is missing"):
        sf.check(table, *_fake_cd({"ONWINCD/A.DLL": b"first file"}))
    with pytest.raises(sf.DifferentRelease, match=r"ONWINCD/C\.DLL is not in the reference release"):
        sf.check(table, *_fake_cd({**_reference_cd(), "ONWINCD/C.DLL": b"x"}))


def test_the_files_nothing_is_made_from_are_not_compared(tmp_path):
    table = _table_of(_reference_cd(), tmp_path)
    played = {**_reference_cd(), "ONWINCD/HALLFAME.DAT": b"scores", "ONWINCD/ONWINCD.INI": b"[ONWINCD]\r\nCDDrive=E:\\\r\n"}
    sf.check(table, *_fake_cd(played))                                          # a hall of fame or a setup file of its own
    assert not sf.IGNORED & set(sf.load_table())


def test_the_importer_checks_the_game_first_and_writes_nothing_when_it_is_refused(monkeypatch, capsys):
    def refuse():
        raise sf.DifferentRelease("your copy of the game is a different version or patched. 1 file does not match")
    monkeypatch.setattr(import_all.source_files, "check", refuse)
    monkeypatch.setattr(sys, "argv", ["import_all.py", "--only", "sectors"])
    monkeypatch.setattr(import_all, "STEPS", {"sectors": lambda: pytest.fail("a step ran after the check refused")})
    assert import_all.main() == 1
    assert "different version or patched" in capsys.readouterr().out


def test_the_importer_says_what_to_do_without_the_image(monkeypatch, capsys, tmp_path):
    monkeypatch.setenv("NEP_ISO", str(tmp_path / "nothing.iso"))
    monkeypatch.setattr(sf.gamefiles, "_cd", None)                  # the image another test opened is not reused
    monkeypatch.setattr(sys, "argv", ["import_all.py", "--only", "sectors"])
    assert import_all.main() == 1
    assert "put your copy of the game at NEPTUNE.ISO" in capsys.readouterr().out
