"""Fetches the General MIDI soundfont FluidR3_GM.sf2 into soundfonts/ (git-ignored), for the importer's music on a machine with no package for it.

    uv run tools/fetch_soundfont.py              # download the pinned Debian package, check its hash, extract FluidR3_GM.sf2
    uv run tools/fetch_soundfont.py --check      # exit 0 when soundfonts/FluidR3_GM.sf2 is in place, 1 when it is not; changes nothing
    uv run tools/fetch_soundfont.py --deb F      # take the package from the file F (still checked against the pinned hash)
    uv run tools/fetch_soundfont.py --force      # fetch again even when the soundfont is in place

On Linux the soundfont comes from the distribution's fluid-soundfont-gm package (docs/SETUP.md). Windows has no such package, so this takes the same
file out of Debian's `fluid-soundfont-gm` package, version VERSION, pinned by its SHA-256 and downloaded over HTTPS from deb.debian.org (about
115 MB). A .deb is an `ar` archive holding a compressed tar, `data.tar.*`; FluidR3_GM.sf2 is its member MEMBER. Only that member is extracted, to
soundfonts/FluidR3_GM.sf2, where the importer looks for it on Windows (tools/import/step_audio.py DEFAULT_SOUNDFONT). The Fluid R3 soundfont is
under the MIT licence (the package's `copyright` file, extracted beside it as FluidR3_GM.copyright).

Teaches: reading a Debian package with the standard library alone (`ar` is a fixed 60-byte header per member; the tar inside is opened by
`tarfile`, which reads xz, gzip and bzip2), and the same pinning as tools/fetch_sandbox.py: the hash is checked before a byte is trusted.
"""
import argparse
import hashlib
import io
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "soundfonts"
SOUNDFONT = "FluidR3_GM.sf2"
COPYRIGHT = "FluidR3_GM.copyright"

VERSION = "3.1-5.3"
SHA256 = "6f531493ac4e4d9772fd96b2488ea1790af81c196135fbdd25997da0781fc60e"
URL = "https://deb.debian.org/debian/pool/main/f/fluid-soundfont/fluid-soundfont-gm_%s_all.deb" % VERSION
MEMBER = "usr/share/sounds/sf2/FluidR3_GM.sf2"
COPYRIGHT_MEMBER = "usr/share/doc/fluid-soundfont-gm/copyright"


class FetchError(Exception):
    pass


def verify(data: bytes, expected: str | None = None) -> None:
    """Raises FetchError unless the SHA-256 of `data` is `expected` (the pinned one by default)."""
    expected = expected or SHA256
    got = hashlib.sha256(data).hexdigest()
    if got != expected:
        raise FetchError("the fluid-soundfont-gm package has SHA-256 %s, expected %s (the pinned version %s): not extracting it"
                         % (got, expected, VERSION))


def ar_members(data: bytes) -> dict[str, bytes]:
    """The members of an `ar` archive (a .deb) by name."""
    if not data.startswith(b"!<arch>\n"):
        raise FetchError("not a Debian package (no ar header)")
    out, at = {}, 8
    while at + 60 <= len(data):
        header = data[at:at + 60]
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58].decode("ascii").strip())
        out[name] = data[at + 60:at + 60 + size]
        at += 60 + size + (size & 1)
    return out


def data_tar(deb: bytes) -> tarfile.TarFile:
    """The package's data archive, opened (data.tar.xz, .gz or .bz2)."""
    for name, body in ar_members(deb).items():
        if name.startswith("data.tar"):
            if name.endswith(".zst"):
                raise FetchError("the package's data is zstd-compressed, which the standard library cannot read")
            return tarfile.open(fileobj=io.BytesIO(body), mode="r:*")
    raise FetchError("the package has no data.tar member")


def read_member(tar: tarfile.TarFile, wanted: str) -> bytes:
    for info in tar.getmembers():
        if info.isfile() and info.name.removeprefix("./") == wanted:
            stream = tar.extractfile(info)
            if stream is not None:
                return stream.read()
    raise FetchError("the package has no %s" % wanted)


def extract(deb: bytes, dest: Path | None = None) -> Path:
    """Checks `deb` against the pin and writes the soundfont (and its copyright file) into `dest`. Returns the soundfont's path."""
    dest = dest or DEST
    verify(deb)
    tar = data_tar(deb)
    soundfont, copyright_text = read_member(tar, MEMBER), read_member(tar, COPYRIGHT_MEMBER)
    dest.mkdir(parents=True, exist_ok=True)
    (dest / COPYRIGHT).write_bytes(copyright_text)
    part = dest / (SOUNDFONT + ".part")
    part.write_bytes(soundfont)
    part.replace(dest / SOUNDFONT)
    return dest / SOUNDFONT


def is_current(dest: Path | None = None) -> bool:
    return ((dest or DEST) / SOUNDFONT).is_file()


def download(url: str = URL) -> bytes:
    if not url.startswith("https://"):
        raise FetchError("refusing a download that is not https: %s" % url)
    print("downloading %s (about 115 MB)" % url)
    with urllib.request.urlopen(url, timeout=600) as response:
        return response.read()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument("--check", action="store_true", help="exit 1 when soundfonts/%s is not in place; change nothing" % SOUNDFONT)
    parser.add_argument("--force", action="store_true", help="fetch again even when the soundfont is in place")
    parser.add_argument("--deb", type=Path, help="use this fluid-soundfont-gm .deb instead of downloading it")
    args = parser.parse_args(argv)
    shown = (DEST / SOUNDFONT).relative_to(ROOT)
    if args.check:
        current = is_current()
        print("%s is %s" % (shown, "in place" if current else "not in place: run `uv run tools/fetch_soundfont.py`"))
        return 0 if current else 1
    if is_current() and not args.force:
        print("%s is already in place" % shown)
        return 0
    try:
        written = extract(args.deb.read_bytes() if args.deb else download())
    except (FetchError, OSError, tarfile.TarError) as error:
        print("fetch_soundfont: %s" % error, file=sys.stderr)
        return 1
    print("%s: %d MB, from Debian's fluid-soundfont-gm %s" % (written.relative_to(ROOT), written.stat().st_size // 1_000_000, VERSION))
    return 0


if __name__ == "__main__":
    sys.exit(main())
