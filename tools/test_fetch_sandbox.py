"""tools/fetch_sandbox.py: which files it takes, how it cuts the .gdextension, that it checks the hash first and is idempotent. No network: a small zip stands in for the release."""
import hashlib
import io
import zipfile

import pytest

import fetch_sandbox as fs

UPSTREAM_GDEXTENSION = """[configuration]

entry_symbol = "riscv_library_init"
compatibility_minimum = "4.4"

[libraries]

macos.debug.double = "./libgodot_riscv.macos.template_release.double.universal.framework"
windows.debug.double.x86_64 = "./libgodot_riscv.windows.template_release.double.x86_64.dll"
linux.debug.double.x86_64 = "./libgodot_riscv.linux.template_release.double.x86_64.so"
android.debug.x86_64 = "./libgodot_riscv.android.template_release.x86_64.so"

windows.debug.x86_64 = "./libgodot_riscv.windows.template_release.x86_64.dll"
windows.release.x86_64 = "./libgodot_riscv.windows.template_release.x86_64.dll"
linux.debug.x86_64 = "./libgodot_riscv.linux.template_release.x86_64.so"
linux.release.x86_64 = "./libgodot_riscv.linux.template_release.x86_64.so"
windows.debug.arm64 = "./libgodot_riscv.windows.template_release.arm64.dll"
web.release.wasm32 = "./libgodot_riscv.web.template_release.wasm32.wasm"
web.release.double.wasm32 = "./libgodot_riscv.web.template_release.double.wasm32.wasm"

[icons]

Sandbox = "./Sandbox.svg"
"""


def release_zip(extra=()):
    """A zip with the members the fetch step wants (and some it does not), laid out as the release is."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as z:
        for name in fs.members():
            z.writestr(name, b"payload of " + name.encode())
        z.writestr(fs.PREFIX + fs.GDEXTENSION, UPSTREAM_GDEXTENSION)
        z.writestr(fs.PREFIX + "bin/libgodot_riscv.android.template_release.x86_64.so", b"not wanted")
        z.writestr(fs.PREFIX + "plugin.gd", b"not wanted")
        for name in extra:
            z.writestr(name, b"extra")
    return buffer.getvalue()


@pytest.fixture
def pinned(monkeypatch):
    """The pinned hash is the hash of the stand-in release."""
    data = release_zip()
    monkeypatch.setattr(fs, "SHA256", hashlib.sha256(data).hexdigest())
    return data


def test_the_members_are_the_three_platform_libraries_the_compiler_and_the_licences():
    wanted = fs.members()
    assert fs.PREFIX + "bin/libgodot_riscv.linux.template_release.x86_64.so" in wanted
    assert fs.PREFIX + "bin/libgodot_riscv.windows.template_release.x86_64.dll" in wanted
    assert fs.PREFIX + "bin/libgodot_riscv.web.template_release.wasm32.wasm" in wanted
    assert fs.PREFIX + "gdscript.elf" in wanted
    assert fs.PREFIX + "LICENSE" in wanted and fs.PREFIX + "THIRDPARTY.txt" in wanted
    assert not any("double" in name or "android" in name or "macos" in name or "ios" in name for name in wanted)


def test_the_gdextension_keeps_only_the_libraries_that_are_shipped_and_no_icons():
    cut = fs.cut_gdextension(UPSTREAM_GDEXTENSION)
    assert 'entry_symbol = "riscv_library_init"' in cut
    assert 'linux.release.x86_64 = "./libgodot_riscv.linux.template_release.x86_64.so"' in cut
    assert 'web.release.wasm32 = "./libgodot_riscv.web.template_release.wasm32.wasm"' in cut
    for gone in ("double", "android", "macos", "arm64", "[icons]", "Sandbox.svg"):
        assert gone not in cut
    assert "\n\n\n" not in cut and cut.endswith("\n")
    listed = [line.split("=", 1)[1].strip().strip('"').removeprefix("./") for line in cut.splitlines() if " = " in line and "." in line.split("=")[0]]
    assert {name for name in listed if name.startswith("libgodot")} == {name.removeprefix("bin/") for name in fs.LIBRARIES}


def test_a_zip_with_another_hash_is_refused_before_anything_is_written(tmp_path):
    with pytest.raises(fs.FetchError, match="SHA-256"):
        fs.extract(release_zip(), tmp_path / "out")
    assert not (tmp_path / "out").exists()


def test_extract_writes_what_is_wanted_and_marks_the_version(pinned, tmp_path):
    out = tmp_path / "godot_sandbox"
    written = fs.extract(pinned, out)
    assert "bin/godot-riscv.gdextension" in written and "gdscript.elf" in written
    assert (out / "bin" / "libgodot_riscv.linux.template_release.x86_64.so").read_bytes().startswith(b"payload of")
    assert not (out / "plugin.gd").exists()
    assert not list(out.rglob("*android*"))
    assert fs.is_current(out)


def test_is_current_needs_the_marker_and_every_file(pinned, tmp_path):
    out = tmp_path / "godot_sandbox"
    assert not fs.is_current(out)
    fs.extract(pinned, out)
    assert fs.is_current(out)
    (out / "gdscript.elf").unlink()
    assert not fs.is_current(out)
    fs.extract(pinned, out)
    (out / fs.MARKER).write_text("v0.1 abc\n")
    assert not fs.is_current(out)


def test_extract_replaces_what_was_there(pinned, tmp_path):
    out = tmp_path / "godot_sandbox"
    (out / "bin").mkdir(parents=True)
    (out / "bin" / "old.so").write_bytes(b"old")
    fs.extract(pinned, out)
    assert not (out / "bin" / "old.so").exists()


def test_a_zip_missing_a_member_is_refused(monkeypatch, tmp_path):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as z:
        z.writestr(fs.PREFIX + "LICENSE", b"x")
    monkeypatch.setattr(fs, "SHA256", hashlib.sha256(buffer.getvalue()).hexdigest())
    with pytest.raises(fs.FetchError, match="lacks"):
        fs.extract(buffer.getvalue(), tmp_path / "out")


def test_main_with_a_zip_file_then_again_does_nothing(pinned, tmp_path, monkeypatch, capsys):
    out = tmp_path / "godot" / "addons" / "godot_sandbox"
    monkeypatch.setattr(fs, "DEST", out)
    monkeypatch.setattr(fs, "ROOT", tmp_path)
    archive = tmp_path / "release.zip"
    archive.write_bytes(pinned)
    assert fs.main(["--check"]) == 1
    assert fs.main(["--zip", str(archive)]) == 0
    assert fs.main(["--check"]) == 0
    capsys.readouterr()
    assert fs.main(["--zip", str(tmp_path / "missing.zip")]) == 0          # (in place: the zip is never opened)
    assert "already" in capsys.readouterr().out
    assert fs.main(["--force", "--zip", str(tmp_path / "missing.zip")]) == 1


def test_a_download_that_is_not_https_is_refused():
    with pytest.raises(fs.FetchError, match="https"):
        fs.download("http://example.com/godot-sandbox.zip")
