"""Fetches Godot's export templates into Godot's own templates folder: what an export of the game (Linux, Windows, Web) is built from.

    uv run tools/fetch_export_templates.py             # download the pinned release's templates, check the hash, extract what our presets use
    uv run tools/fetch_export_templates.py --check     # exit 0 when they are in place, 1 when not; changes nothing
    uv run tools/fetch_export_templates.py --tpz F     # take the templates archive from the file F (still checked against the pinned hash)
    uv run tools/fetch_export_templates.py --force     # fetch again even when they are in place

The archive is pinned by VERSION (the Godot that mise.toml pins; a test keeps the two equal) and its SHA-512 (Godot's SHA512-SUMS.txt of the
release), and downloaded over plain HTTPS from Godot's GitHub release (1.3 GB). It goes to a temporary file beside the templates folder (not /tmp,
which is often in memory), is hashed while it arrives, and is deleted once the templates are out of it. Only the templates of the presets in godot/export_presets.cfg are extracted (Linux and Windows x86_64, the single-threaded Web), with
`version.txt`, into `$XDG_DATA_HOME/godot/export_templates/<version>/` (by default `~/.local/share/...`), where the editor's Manage Export Templates
puts them too: a full install made there by the editor counts as in place. The Flatpak Godot looks elsewhere (docs/SETUP.md, "Godot").

Teaches: pinning a large download by SHA-512 without holding it in memory (streamed to a temporary file, hashed as it arrives), extracting only a
chosen list of members, and an install that is idempotent because it checks for the files it would write.
"""
import argparse
import hashlib
import os
import shutil
import sys
import tempfile
import tomllib
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

VERSION = "4.7.2"
SHA512 = ("ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5"
          "f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079")
URL = "https://github.com/godotengine/godot/releases/download/%s-stable/Godot_v%s-stable_export_templates.tpz" % (VERSION, VERSION)

PREFIX = "templates/"
# The templates the presets of godot/export_presets.cfg are built from: Linux x86_64, Windows x86_64 (with its console wrapper, which an export
# writes beside the .exe when the template is there), and the single-threaded Web with extensions (variant/extensions_support: the dlink one).
TEMPLATES = (
    "version.txt",
    "linux_release.x86_64",
    "linux_debug.x86_64",
    "windows_release_x86_64.exe",
    "windows_debug_x86_64.exe",
    "windows_release_x86_64_console.exe",
    "windows_debug_x86_64_console.exe",
    "web_dlink_nothreads_release.zip",
    "web_dlink_nothreads_debug.zip",
)
EXECUTABLES = ("linux_release.x86_64", "linux_debug.x86_64")


class FetchError(Exception):
    pass


def godot_pin(root: Path = ROOT) -> str:
    """The Godot version mise.toml pins, without its "-stable" ("4.7.2")."""
    return tomllib.loads((root / "mise.toml").read_text())["tools"]["godot"].removesuffix("-stable")


def templates_dir(env=None) -> Path:
    """Godot's templates folder of VERSION on Linux: `$XDG_DATA_HOME/godot/export_templates/<version>.stable/`."""
    env = os.environ if env is None else env
    data = env.get("XDG_DATA_HOME") or str(Path(env.get("HOME", Path.home())) / ".local" / "share")
    return Path(data) / "godot" / "export_templates" / ("%s.stable" % VERSION)


def is_current(dest: Path | None = None) -> bool:
    """Is every template our presets use in `dest`, and does its version.txt name VERSION?"""
    dest = dest or templates_dir()
    try:
        if (dest / "version.txt").read_text().strip() != "%s.stable" % VERSION:
            return False
    except OSError:
        return False
    return all((dest / name).is_file() for name in TEMPLATES)


def download(url: str, into: Path) -> str:
    """Streams `url` into the file `into` and returns its SHA-512 (hex)."""
    if not url.startswith("https://"):
        raise FetchError("refusing a download that is not https: %s" % url)
    print("downloading %s (about 1.3 GB)" % url)
    digest = hashlib.sha512()
    with urllib.request.urlopen(url, timeout=120) as response, into.open("wb") as out:
        total = int(response.headers.get("Content-Length") or 0)
        done, shown = 0, -1
        while chunk := response.read(1 << 20):
            out.write(chunk)
            digest.update(chunk)
            done += len(chunk)
            percent = done * 100 // total if total else -1
            if percent != shown and percent % 10 == 0:
                print("  %d%%" % percent, flush=True)
                shown = percent
    return digest.hexdigest()


def hash_file(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as f:
        while chunk := f.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def extract(tpz: Path, sha512: str, dest: Path | None = None) -> list[str]:
    """Checks `sha512` (the archive's hash) against the pin, then writes the chosen templates under `dest`. Returns the names written."""
    if sha512 != SHA512:
        raise FetchError("the templates archive has SHA-512 %s, expected %s (Godot %s): not extracting it" % (sha512, SHA512, VERSION))
    dest = dest or templates_dir()
    with zipfile.ZipFile(tpz) as z:
        names = set(z.namelist())
        missing = [name for name in TEMPLATES if PREFIX + name not in names]
        if missing:
            raise FetchError("the templates archive lacks %s" % ", ".join(missing))
        dest.mkdir(parents=True, exist_ok=True)
        for name in TEMPLATES:
            with z.open(PREFIX + name) as source, (dest / name).open("wb") as target:
                shutil.copyfileobj(source, target)
            if name in EXECUTABLES:
                (dest / name).chmod(0o755)
    return list(TEMPLATES)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument("--check", action="store_true", help="exit 1 when the templates are not in place; change nothing")
    parser.add_argument("--force", action="store_true", help="fetch again even when the templates are in place")
    parser.add_argument("--tpz", type=Path, help="use this templates archive instead of downloading it")
    args = parser.parse_args(argv)
    dest = templates_dir()
    if args.check:
        current = is_current(dest)
        print("Godot %s export templates are %s" % (
            VERSION, "in place" if current else "not in place: run `uv run tools/fetch_export_templates.py`"))
        return 0 if current else 1
    if is_current(dest) and not args.force:
        print("Godot %s export templates are already in %s" % (VERSION, dest))
        return 0
    try:
        if args.tpz:
            written = extract(args.tpz, hash_file(args.tpz), dest)
        else:
            # Beside the templates folder, not in /tmp: /tmp is often in memory (tmpfs), and the archive is 1.3 GB.
            dest.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(prefix="download-", dir=dest.parent) as scratch:
                tpz = Path(scratch) / "templates.tpz"
                written = extract(tpz, download(URL, tpz), dest)
    except (FetchError, OSError, zipfile.BadZipFile) as error:
        print("fetch_export_templates: %s" % error, file=sys.stderr)
        return 1
    print("Godot %s export templates: %d files in %s" % (VERSION, len(written), dest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
