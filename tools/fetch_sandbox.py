"""Fetches the godot-sandbox extension into godot/addons/godot_sandbox/ (git-ignored): the engine that runs a mod pack's SafeGDScript.

    uv run tools/fetch_sandbox.py            # download the pinned release, check its hash, extract what the game needs
    uv run tools/fetch_sandbox.py --check    # exit 0 when the pinned version is in place, 1 when it is not; changes nothing
    uv run tools/fetch_sandbox.py --zip F    # take the release zip from the file F (still checked against the pinned hash)
    uv run tools/fetch_sandbox.py --force    # fetch again even when the pinned version is in place

The release is pinned by VERSION and SHA256 below and downloaded over plain HTTPS from its GitHub release page (`gh` is not needed). The extension is
never committed (docs/SETUP.md, "godot-sandbox"). Only what the game runs and exports is extracted: the Linux x86_64, Windows x86_64 and Web wasm32
single-precision libraries, the SafeGDScript compiler (`gdscript.elf`), the licence files, and a `godot-riscv.gdextension` cut down to those libraries
(the upstream one names libraries for platforms we do not ship, which would make an export of ours complain about a missing file).

Teaches: pinning a download by version and SHA-256 (the hash is checked before a byte of the zip is trusted), extracting only a chosen list of members
(never a path from the archive), and a marker file that makes a fetch idempotent.
"""
import argparse
import hashlib
import io
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "godot" / "addons" / "godot_sandbox"

VERSION = "v0.60"
SHA256 = "6b7f4c6a74d283352036c2cf6baf4672059ab17d4eaf00386a0357eda73ce865"
URL = "https://github.com/libriscv/godot-sandbox/releases/download/%s/godot-sandbox.zip" % VERSION

PREFIX = "addons/godot_sandbox/"
# The libraries of the platforms the game exports to (Linux, Windows, Web), single precision (Godot's default build).
LIBRARIES = (
    "bin/libgodot_riscv.linux.template_release.x86_64.so",
    "bin/libgodot_riscv.windows.template_release.x86_64.dll",
    "bin/libgodot_riscv.web.template_release.wasm32.wasm",
)
GDEXTENSION = "bin/godot-riscv.gdextension"
# Everything else extracted as it is: the SafeGDScript compiler the extension loads from its own folder, and the licences.
OTHER_FILES = ("gdscript.elf", "LICENSE", "THIRDPARTY.txt")
MARKER = ".fetched"


class FetchError(Exception):
    pass


def members() -> list[str]:
    """The zip members that are extracted unchanged (the .gdextension is rewritten, so it is not among them)."""
    return [PREFIX + name for name in (*LIBRARIES, *OTHER_FILES)]


def verify(data: bytes, expected: str | None = None) -> None:
    """Raises FetchError unless the SHA-256 of `data` is `expected` (the pinned one by default)."""
    expected = expected or SHA256
    got = hashlib.sha256(data).hexdigest()
    if got != expected:
        raise FetchError("the godot-sandbox zip has SHA-256 %s, expected %s (the pinned release %s): not extracting it" % (got, expected, VERSION))


def cut_gdextension(text: str, libraries=LIBRARIES) -> str:
    """The upstream .gdextension with only the lines of `libraries` (and no [icons], whose pictures are not shipped)."""
    kept = {Path(name).name for name in libraries}
    out = []
    section = ""
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            section = stripped
        if section == "[icons]":
            continue
        if section == "[libraries]" and "=" in stripped:
            target = stripped.split("=", 1)[1].strip().strip('"').removeprefix("./")
            if target not in kept:
                continue
        out.append(line)
    # blank lines left behind collapse to one
    text = "\n".join(out)
    while "\n\n\n" in text:
        text = text.replace("\n\n\n", "\n\n")
    return text.rstrip() + "\n"


def marker_text() -> str:
    return "%s %s\n" % (VERSION, SHA256)


def is_current(dest: Path | None = None) -> bool:
    """Is the pinned release in `dest`: the marker says so and every file it holds is there?"""
    dest = dest or DEST
    try:
        if (dest / MARKER).read_text() != marker_text():
            return False
    except OSError:
        return False
    return all((dest / name).is_file() for name in (*LIBRARIES, *OTHER_FILES, GDEXTENSION))


def extract(zip_bytes: bytes, dest: Path | None = None) -> list[str]:
    """Checks the hash, then writes the chosen members (and the cut .gdextension) under `dest`. Returns the paths written, relative to `dest`."""
    verify(zip_bytes)
    dest = dest or DEST
    written = []
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as z:
        wanted = [*members(), PREFIX + GDEXTENSION]
        missing = [name for name in wanted if name not in z.namelist()]
        if missing:
            raise FetchError("the godot-sandbox zip lacks %s" % ", ".join(missing))
        if dest.exists():
            for old in sorted(dest.rglob("*"), reverse=True):
                old.unlink() if old.is_file() or old.is_symlink() else old.rmdir()
        for name in members():
            target = dest / name.removeprefix(PREFIX)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(z.read(name))
            written.append(name.removeprefix(PREFIX))
        gdext = dest / GDEXTENSION
        gdext.parent.mkdir(parents=True, exist_ok=True)
        gdext.write_text(cut_gdextension(z.read(PREFIX + GDEXTENSION).decode("utf-8")))
        written.append(GDEXTENSION)
    (dest / MARKER).write_text(marker_text())
    return written


def download(url: str = URL) -> bytes:
    if not url.startswith("https://"):
        raise FetchError("refusing a download that is not https: %s" % url)
    print("downloading %s" % url)
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument("--check", action="store_true", help="exit 1 when the pinned version is not in place; change nothing")
    parser.add_argument("--force", action="store_true", help="fetch again even when the pinned version is in place")
    parser.add_argument("--zip", type=Path, help="use this release zip instead of downloading it")
    args = parser.parse_args(argv)
    if args.check:
        current = is_current()
        print("godot-sandbox %s is %s" % (VERSION, "in place" if current else "not in place: run `uv run tools/fetch_sandbox.py`"))
        return 0 if current else 1
    if is_current() and not args.force:
        print("godot-sandbox %s is already in %s" % (VERSION, DEST.relative_to(ROOT)))
        return 0
    try:
        data = args.zip.read_bytes() if args.zip else download()
        written = extract(data)
    except (FetchError, OSError) as error:
        print("fetch_sandbox: %s" % error, file=sys.stderr)
        return 1
    print("godot-sandbox %s: %d files in %s" % (VERSION, len(written), DEST.relative_to(ROOT)))
    print("Godot learns of the extension when it imports the project: tools/godot.sh --headless --path godot --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
