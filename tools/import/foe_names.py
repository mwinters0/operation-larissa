"""The registry as the importer reads it (the names of a creature script's operands, and the names of the asset files): the twin of godot/src/core/foe_names.gd (FoeNames)
and of the lookups of godot/src/core/name_registry.gd (NameRegistry).

The disassembler in foe_text.py writes the stored scripts (godot/data/sectors/sector_NN/sector_NN.foe), and the GDScript
disassembler must write the same text, so the importer has to answer the same question as the game: "which REAL name does
number 22 have as a sound, number 41 as a creature picture in zone 2, number 3 as a creature of sector 7?". Real means a
name somebody gave it in godot/names/original.json; a number nobody named has only a made-up name (`sfx_22`), which the
disassembler never prints (the number says more). This module only reads that direction (number -> real name) plus the
reverse lookups the harvest needs; whether the file is sound is the job of the GDScript tests and of test_names.py.

Scopes (docs/create/NAMES.md): `frame` names belong to the sector's zone, `foe`, `screen` and `flag` names to the sector; a lookup in a
scope sees the scope's own names and the `common` ones. Everything else is global.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from common import GODOT

STORE = GODOT / "names" / "original.json"
COMMON = "common"
NO_SCOPE = -1

# kind -> (scope, scopes, first, last, fallback). Keep equal to NameRegistry.KINDS (test_foe_names.py checks it).
GLOBAL, ZONE, SECTOR = "global", "zone", "sector"
KINDS = {
    "sound": (GLOBAL, 0, 0, 51, "sfx_%02d"),
    "frame": (ZONE, 7, 0, 127, "frame_%03d"),
    "deco": (ZONE, 5, 0, 255, "deco_%03d"),
    "music": (GLOBAL, 0, 9500, 9999, "music_%d"),
    "voice": (GLOBAL, 0, 4000, 4999, "voice_%d"),
    "ui_picture": (GLOBAL, 0, 1000, 2999, "ui_%d"),
    "problem_art": (GLOBAL, 0, 1000, 2999, "pa_%d"),
    "foe": (SECTOR, 256, 0, 127, "foe_%d"),
    "screen": (SECTOR, 256, 0, 11, "screen_%02d"),
    "flag": (SECTOR, 256, 0, 15, "flag_%02d"),
}
# The first five are the operands of a creature script; the asset kinds (deco ... problem_art) are here for asset_names.py, which
# names the asset files. `text`, `zone` and `sector` are never needed by the importer.

MIRROR_WORD = "mirrored"


def sector_zone(i: int) -> int:
    """SectorData.zone of an original sector: 0-4 the normal zones, 5 and 6 the Voyager and the Expert finale."""
    return 5 + (i - 30) if i >= 30 else (i % 15) // 3


class Registry:
    """kind -> scope key (COMMON, or a scope number as text, or None for a global kind) -> {number: name}."""

    def __init__(self, names: dict | None = None) -> None:
        self._by_index: dict[str, dict[str | None, dict[int, str]]] = {}
        self._by_name: dict[str, dict[str | None, dict[str, int]]] = {}
        for kind, node in (names or {}).items():
            if kind not in KINDS:
                continue
            tables = {None: node} if KINDS[kind][0] == GLOBAL else node
            self._by_index[kind] = {key: {int(n): name for name, n in table.items()} for key, table in tables.items()}
            self._by_name[kind] = {key: {name: int(n) for name, n in table.items()} for key, table in tables.items()}

    @classmethod
    def load(cls, path: Path = STORE) -> Registry:
        return cls(json.loads(path.read_text())["names"])

    def _visible(self, kind: str, scope: int) -> list[str | None]:
        scoped, count = KINDS[kind][0], KINDS[kind][1]
        if scoped == GLOBAL:
            return [None]
        if 0 <= scope < count:
            return [str(scope), COMMON]
        return [COMMON]                                  # NO_SCOPE, or a scope the kind does not have: only the common names

    def real_name(self, kind: str, index: int, scope: int = NO_SCOPE) -> str:
        """The name somebody gave number `index` (NameRegistry.name_of when NameRegistry.is_named), else ""."""
        for key in self._visible(kind, scope):
            name = self._by_index.get(kind, {}).get(key, {}).get(index)
            if name is not None:
                return name
        return ""

    def index_of(self, kind: str, name: str, scope: int = NO_SCOPE) -> int:
        """NameRegistry.index_of: a real name of the scope (or common), else a made-up name; -1 when it is neither."""
        for key in self._visible(kind, scope):
            found = self._by_name.get(kind, {}).get(key, {}).get(name)
            if found is not None:
                return found
        return fallback_index(kind, name)

    def entries(self, kind: str, scope: int = NO_SCOPE) -> dict[str, int]:
        """The real names usable in the scope, in the order of their numbers (NameRegistry.entries)."""
        merged: dict[int, str] = {}
        for key in self._visible(kind, scope):
            for number, name in self._by_index.get(kind, {}).get(key, {}).items():
                merged.setdefault(number, name)
        return {merged[n]: n for n in sorted(merged)}


def fallback_name(kind: str, index: int) -> str:
    """NameRegistry.fallback_name: "" outside the kind."""
    _scope, _count, first, last, pattern = KINDS[kind]
    return pattern % index if first <= index <= last else ""


def fallback_index(kind: str, name: str) -> int:
    """NameRegistry.fallback_index: only the exact spelling fallback_name writes counts."""
    pattern = KINDS[kind][4]
    prefix = pattern[:pattern.index("%")]
    digits = name[len(prefix):] if name.startswith(prefix) else ""
    if not re.fullmatch(r"-?[0-9]+", digits):
        return -1
    index = int(digits)
    return index if fallback_name(kind, index) == name else -1


class Names:
    """The names of one script's place: a registry, the sector and the zone (FoeNames)."""

    def __init__(self, registry: Registry | None = None, sector: int = NO_SCOPE, zone: int = NO_SCOPE) -> None:
        self.registry = registry if registry is not None else _original()
        self.sector = sector
        self.zone = zone

    @classmethod
    def for_original_sector(cls, index: int, registry: Registry | None = None) -> Names:
        return cls(registry, index, sector_zone(index))

    def scope_of(self, kind: str) -> int:
        scoped, count = KINDS[kind][0], KINDS[kind][1]
        if scoped == GLOBAL:
            return NO_SCOPE
        wanted = self.zone if kind == "frame" else self.sector
        return wanted if 0 <= wanted < count else NO_SCOPE

    def name_for(self, kind: str, value: int) -> str:
        """The real name of `value`, or "" (then the disassembler writes the number)."""
        return self.registry.real_name(kind, value, self.scope_of(kind))

    def index_for(self, kind: str, word: str) -> int:
        return self.registry.index_of(kind, word, self.scope_of(kind))


_loaded: Registry | None = None


def _original() -> Registry:
    global _loaded
    if _loaded is None:
        _loaded = Registry.load()
    return _loaded


def original() -> Registry:
    """godot/names/original.json, read once (NameRegistry.original())."""
    return _original()
