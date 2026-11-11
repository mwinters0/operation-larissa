"""tools/fetch_soundfont.py: a .deb is checked against the pinned hash before anything is read from it; only the soundfont and its copyright
file come out, into the destination folder. The package here is a small one built by the test, in the real .deb layout (an ar archive with
debian-binary, control.tar.xz and data.tar.xz), and the pin is switched to its hash; nothing is downloaded."""
import hashlib
import io
import tarfile

import pytest

import fetch_soundfont


def ar_entry(name: str, body: bytes) -> bytes:
    header = b"%-16s%-12s%-6s%-6s%-8s%-10d`\n" % (name.encode() + b"/", b"0", b"0", b"0", b"100644", len(body))
    return header + body + (b"\n" if len(body) & 1 else b"")


def tar_xz(files: dict[str, bytes]) -> bytes:
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w:xz") as tar:
        for name, body in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(body)
            tar.addfile(info, io.BytesIO(body))
    return out.getvalue()


def make_deb(files: dict[str, bytes]) -> bytes:
    return (b"!<arch>\n" + ar_entry("debian-binary", b"2.0\n") + ar_entry("control.tar.xz", tar_xz({"./control": b"Package: x\n"}))
            + ar_entry("data.tar.xz", tar_xz(files)))


@pytest.fixture
def deb(monkeypatch):
    data = make_deb({"./" + fetch_soundfont.MEMBER: b"sfbk" * 3, "./" + fetch_soundfont.COPYRIGHT_MEMBER: b"MIT\n",
                     "./usr/share/doc/fluid-soundfont-gm/changelog.gz": b"x"})
    monkeypatch.setattr(fetch_soundfont, "SHA256", hashlib.sha256(data).hexdigest())
    return data


def test_the_soundfont_and_its_copyright_come_out_and_nothing_else(deb, tmp_path):
    written = fetch_soundfont.extract(deb, tmp_path)
    assert written == tmp_path / "FluidR3_GM.sf2"
    assert written.read_bytes() == b"sfbk" * 3
    assert sorted(p.name for p in tmp_path.iterdir()) == ["FluidR3_GM.copyright", "FluidR3_GM.sf2"]
    assert fetch_soundfont.is_current(tmp_path)


def test_a_package_with_another_hash_is_refused_before_it_is_read(deb, tmp_path):
    with pytest.raises(fetch_soundfont.FetchError, match="SHA-256"):
        fetch_soundfont.extract(deb + b"x", tmp_path)
    assert not any(tmp_path.iterdir())


def test_a_package_without_the_soundfont_is_refused(monkeypatch, tmp_path):
    data = make_deb({"./usr/share/doc/fluid-soundfont-gm/copyright": b"MIT\n"})
    monkeypatch.setattr(fetch_soundfont, "SHA256", hashlib.sha256(data).hexdigest())
    with pytest.raises(fetch_soundfont.FetchError, match="FluidR3_GM.sf2"):
        fetch_soundfont.extract(data, tmp_path)


def test_only_https_is_downloaded():
    with pytest.raises(fetch_soundfont.FetchError, match="https"):
        fetch_soundfont.download("http://example.org/x.deb")
