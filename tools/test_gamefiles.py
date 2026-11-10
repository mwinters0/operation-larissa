"""gamefiles reads the CD image; the check against a folder unpacked with 7z skips without the ISO or iso/."""
import hashlib
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gamefiles

UNPACKED = gamefiles.ROOT / "iso"      # what `mise -E proton run unpack-cd` makes (7z x NEPTUNE.ISO); only Wine needs it now


def need_iso():
    try:
        gamefiles.iso_file()
    except gamefiles.MissingISO as e:
        pytest.skip(str(e))


def test_missing_iso_says_what_to_do(monkeypatch, tmp_path):
    monkeypatch.setenv("NEP_ISO", str(tmp_path / "nothing.iso"))
    with pytest.raises(gamefiles.MissingISO, match="put your copy of the game at NEPTUNE.ISO or set NEP_ISO"):
        gamefiles.iso_file()


def test_every_unpacked_file_reads_back_identical():
    need_iso()
    if not UNPACKED.is_dir():
        pytest.skip("no iso/ to compare with (mise -E proton run unpack-cd)")
    seen = set()
    for f in sorted(p for p in UNPACKED.rglob("*") if p.is_file()):
        cd_path = f.relative_to(UNPACKED).as_posix()
        if cd_path.endswith(".orig"):               # `mise -E proton run patch` keeps the pristine DATA1.CAB beside the patched one
            continue
        # patch edits INSTALL/DATA1.CAB in place; the pristine copy is its .orig
        want = (f.with_name(f.name + ".orig") if cd_path == "INSTALL/DATA1.CAB" and f.with_name(f.name + ".orig").exists()
                else f).read_bytes()
        assert gamefiles.read(cd_path) == want, cd_path
        seen.add(cd_path.upper())
    # and the image holds nothing that 7z did not unpack
    assert {p.upper() for p in gamefiles.walk()} == seen


def test_names_are_case_insensitive():
    need_iso()
    assert gamefiles.read("onwincd/nep.dll") == gamefiles.read("ONWINCD/NEP.DLL")
    assert gamefiles.read("ONWINCD\\NEP.DLL")[:2] == b"MZ"
    assert gamefiles.exists("Assets") and not gamefiles.exists("ASSETS/NOPE.GRP")
    with pytest.raises(FileNotFoundError):
        gamefiles.read("ONWINCD/NOPE.DLL")


def test_listdir_and_glob():
    need_iso()
    assert "ONWINCD" in gamefiles.listdir() and "ASSETS" in gamefiles.listdir("")
    assert "NEP.DLL" in gamefiles.listdir("onwincd")
    grp = gamefiles.glob("ASSETS/*.GRP")
    assert grp == sorted(grp) and "ASSETS/WSCOMMON.GRP" in grp and len(grp) == 6
    assert gamefiles.glob("assets/ws109?.grp") == ["ASSETS/WS109P.GRP"]
    assert len(gamefiles.walk()) == 154 and gamefiles.walk("onwincd/sounds")[0] == "ONWINCD/SOUNDS/BEND.MID"
    assert "ONWINCD/SOUNDS" not in gamefiles.glob("ONWINCD/*")          # folders are not files


def test_materialize_writes_a_real_file_once(monkeypatch, tmp_path):
    need_iso()
    monkeypatch.setattr(gamefiles, "CACHE", tmp_path)
    p = gamefiles.materialize("onwincd/onwin32.exe")
    assert p.is_file() and p.is_relative_to(tmp_path) and p.name == "ONWIN32.EXE"
    assert p.read_bytes() == gamefiles.read("ONWINCD/ONWIN32.EXE")
    p.write_bytes(b"marker")
    assert gamefiles.materialize("ONWINCD/ONWIN32.EXE").read_bytes() == b"marker"      # not extracted again


def test_sha256_of_the_image():
    need_iso()
    h = hashlib.sha256(gamefiles.iso_file().read_bytes()).hexdigest()
    assert gamefiles.sha256() == h
