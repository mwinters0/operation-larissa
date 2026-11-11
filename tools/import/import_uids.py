"""Stable uids for the imported assets.

Godot keeps a `uid://...` for every picture and sound in the file's `.import` sidecar, and a scene or resource that points at
the file by uid (the tileset does; a scene you drag a picture into does) finds it again after the file moves. The legacy pack is made
anew from the user's ISO and its `.import` files are not committed (they name nothing but the assets, but they belong to them),
so a clean checkout would hand every asset a random new uid and break each reference by uid. Instead the importer writes the
sidecar itself, as a stub that holds only what Godot cannot guess: the importer, the type and a uid worked out from the file's
path. `godot --import` fills in the rest (the settings are the defaults, as before) and keeps the uid. A sidecar that exists is
never touched: Godot's own, or one carried over to a renamed asset by asset_manifest.prune.

The uid is a hash of the path, written the way Godot writes one (ResourceUID::id_to_text: a 63 bit number in base 34, digits
a-y then 0-8), so it is the same on every machine and in every checkout. The cost is that a renamed asset gets a new uid,
unless its sidecar is carried over (prune does, for an asset whose bytes did not change).
"""
from __future__ import annotations

import hashlib
from pathlib import Path

from common import res_path

ALPHABET = "abcdefghijklmnopqrstuvwxy012345678"       # Godot's uuid_characters: base 34, 'z' and '9' are never used
# extension -> (importer, type) of the resource Godot makes of it, as it writes them in `[remap]`
IMPORTERS = {
    ".png": ("texture", "CompressedTexture2D"),
    ".wav": ("wav", "AudioStreamWAV"),
    ".ogg": ("oggvorbisstr", "AudioStreamOggVorbis"),
}


def uid_of(res_url: str) -> str:
    """The uid for the file `res_url` ("res://packs/legacy/assets/ui/...png"): the same text Godot would print for that 63 bit number."""
    number = int.from_bytes(hashlib.sha256(res_url.encode()).digest()[:8], "big") & 0x7FFFFFFFFFFFFFFF
    digits = ""
    while True:
        digits = ALPHABET[number % len(ALPHABET)] + digits
        number //= len(ALPHABET)
        if not number:
            return "uid://" + digits


def sidecar(path: Path) -> Path:
    return path.with_name(path.name + ".import")


def stub_text(path: Path) -> str:
    importer, kind = IMPORTERS[path.suffix]
    return '[remap]\n\nimporter="%s"\ntype="%s"\nuid="%s"\n' % (importer, kind, uid_of(res_path(path)))


def uid_in(path: Path) -> str:
    """The uid of `path` (an asset under godot/): the one in its sidecar if it has one, else the one the stub will get."""
    file = sidecar(path)
    if file.exists():
        for line in file.read_text().splitlines():
            if line.startswith('uid="'):
                return line[5:-1]
    return uid_of(res_path(path))


def ensure_sidecar(path: Path) -> bool:
    """Writes the stub next to `path` unless it has a sidecar already. True if one was written."""
    if path.suffix not in IMPORTERS or sidecar(path).exists():
        return False
    sidecar(path).write_text(stub_text(path))
    return True


def ensure_sidecars(folders: list[Path]) -> int:
    """`ensure_sidecar` for every picture and sound below `folders`; returns how many stubs were written."""
    return sum(ensure_sidecar(p) for d in folders if d.exists() for p in sorted(d.rglob("*")) if p.is_file())

