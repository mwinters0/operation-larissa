"""tools/fetch_export_templates.py: its pin follows mise.toml's Godot, it checks the hash first, takes only our presets' templates, is idempotent.
No network: a small archive stands in for the release."""
import hashlib
import zipfile

import pytest

import fetch_export_templates as ft


def make_tpz(path, names=ft.TEMPLATES, extra=("android_release.apk", "macos.zip")):
    with zipfile.ZipFile(path, "w") as z:
        for name in (*names, *extra):
            z.writestr(ft.PREFIX + name, "%s.stable\n" % ft.VERSION if name == "version.txt" else "payload of " + name)
    return path


@pytest.fixture
def pinned(monkeypatch, tmp_path):
    """A stand-in archive whose hash is the pinned one."""
    tpz = make_tpz(tmp_path / "templates.tpz")
    monkeypatch.setattr(ft, "SHA512", hashlib.sha512(tpz.read_bytes()).hexdigest())
    return tpz


def test_the_pin_is_the_godot_that_mise_pins():
    assert ft.VERSION == ft.godot_pin()
    assert ft.VERSION in ft.URL and ft.URL.startswith("https://")


def test_the_templates_are_those_of_our_presets():
    presets = (ft.ROOT / "godot" / "export_presets.cfg").read_text()
    assert {'platform="Linux"', 'platform="Windows Desktop"', 'platform="Web"'} <= {line for line in presets.splitlines()}
    assert "variant/extensions_support=true" in presets and "variant/thread_support=false" in presets   # the dlink, nothreads Web
    assert not any(word in name for name in ft.TEMPLATES for word in ("android", "macos", "ios", "arm", "x86_32"))


def test_the_folder_follows_xdg_data_home():
    assert ft.templates_dir({"XDG_DATA_HOME": "/data", "HOME": "/home/u"}).as_posix() == "/data/godot/export_templates/%s.stable" % ft.VERSION
    assert ft.templates_dir({"HOME": "/home/u"}).as_posix() == "/home/u/.local/share/godot/export_templates/%s.stable" % ft.VERSION


def test_an_archive_with_another_hash_is_refused_before_anything_is_written(tmp_path):
    tpz = make_tpz(tmp_path / "templates.tpz")
    with pytest.raises(ft.FetchError, match="SHA-512"):
        ft.extract(tpz, ft.hash_file(tpz), tmp_path / "out")
    assert not (tmp_path / "out").exists()


def test_extract_writes_only_our_templates(pinned, tmp_path):
    out = tmp_path / "out"
    assert not ft.is_current(out)
    ft.extract(pinned, ft.hash_file(pinned), out)
    assert sorted(p.name for p in out.iterdir()) == sorted(ft.TEMPLATES)
    assert (out / "linux_release.x86_64").stat().st_mode & 0o111
    assert ft.is_current(out)
    (out / "web_dlink_nothreads_release.zip").unlink()
    assert not ft.is_current(out)


def test_another_version_is_not_in_place(pinned, tmp_path):
    out = tmp_path / "out"
    ft.extract(pinned, ft.hash_file(pinned), out)
    (out / "version.txt").write_text("4.6.stable\n")
    assert not ft.is_current(out)


def test_an_archive_missing_a_template_is_refused(monkeypatch, tmp_path):
    tpz = make_tpz(tmp_path / "templates.tpz", names=("version.txt",))
    monkeypatch.setattr(ft, "SHA512", ft.hash_file(tpz))
    with pytest.raises(ft.FetchError, match="lacks"):
        ft.extract(tpz, ft.hash_file(tpz), tmp_path / "out")


def test_main_with_an_archive_then_again_does_nothing(pinned, tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    assert ft.main(["--check"]) == 1
    assert ft.main(["--tpz", str(pinned)]) == 0
    assert ft.main(["--check"]) == 0
    capsys.readouterr()
    assert ft.main(["--tpz", str(tmp_path / "missing.tpz")]) == 0          # (in place: the archive is never opened)
    assert "already" in capsys.readouterr().out
    assert ft.main(["--force", "--tpz", str(tmp_path / "missing.tpz")]) == 1


def test_a_download_that_is_not_https_is_refused(tmp_path):
    with pytest.raises(ft.FetchError, match="https"):
        ft.download("http://example.com/templates.tpz", tmp_path / "t.tpz")
