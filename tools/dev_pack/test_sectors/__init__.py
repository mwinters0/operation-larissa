"""The test sectors of the dev pack, one module per I7 batch (tools/dev_pack/README.md, "Test sectors").

Engine tests that need a place with a stated property (a ledge with a piece behind a wall, a creature of a stated box, a record of known values)
get a sector of the dev pack made for them, numbered from 100 up and in no campaign. So that five agents can add sectors at the same time, each batch
has its own module (`batch_a.py` ... `batch_e.py`), its own range of sector numbers and, if it must have one, its own campaign `test_a` ... `test_e`.
`write_all` here only calls each module's `write_all(dev_root)`; `write_sector` and `write_campaign` refuse a number or an id that is not the batch's.
"""
from __future__ import annotations

import importlib
from pathlib import Path

import dev_sectors
import devlib

# batch letter -> its sector numbers (the same ranges as godot/tests/engine/dev_pack.gd BATCH_A ... BATCH_E).
RANGES = {"a": range(100, 120), "b": range(120, 140), "c": range(140, 160), "d": range(160, 180), "e": range(180, 200)}

# batch letter -> the sector numbers and campaign ids written in this run (the test checks the pack holds no others).
WRITTEN_SECTORS: dict[str, list[int]] = {b: [] for b in RANGES}
WRITTEN_CAMPAIGNS: dict[str, list[str]] = {b: [] for b in RANGES}


def campaign_id(batch: str) -> str:
    return "test_" + batch


def write_sector(batch: str, spec: dev_sectors.SectorSpec, dev_root: Path | None = None) -> int:
    """Writes the sector below `dev_root`; `spec.index` must be in the batch's range. The number of files."""
    if spec.index not in RANGES[batch]:
        raise ValueError("batch %s owns sectors %d-%d, not %d" % (batch, RANGES[batch][0], RANGES[batch][-1], spec.index))
    if spec.index not in WRITTEN_SECTORS[batch]:
        WRITTEN_SECTORS[batch].append(spec.index)
    return dev_sectors.write_sector(spec, dev_root)


def write_campaign(batch: str, title: str, sectors: list[int], finales: list[int], edu: list[int], finale_text: str,
                   dev_root: Path | None = None) -> int:
    """Writes the batch's campaign `test_<batch>` (its sectors must be the batch's own). 1 file."""
    for index in sectors + finales:
        if index not in RANGES[batch]:
            raise ValueError("batch %s owns sectors %d-%d, not %d" % (batch, RANGES[batch][0], RANGES[batch][-1], index))
    cid = campaign_id(batch)
    text = dev_sectors.campaign_tres(cid, title, sectors, finales, edu, finale_text,
                                     provenance="Dev pack: a test campaign of I7 batch %s (tools/dev_pack/test_sectors/batch_%s.py)." % (batch.upper(), batch))
    if cid not in WRITTEN_CAMPAIGNS[batch]:
        WRITTEN_CAMPAIGNS[batch].append(cid)
    devlib.write_text((devlib.DEV if dev_root is None else dev_root) / "data" / "campaigns" / (cid + ".tres"), text)
    return 1


def write_all(dev_root: Path | None = None) -> int:
    """Calls each batch module's `write_all(dev_root)`; the number of files they wrote or checked."""
    total = 0
    for batch in RANGES:
        total += importlib.import_module("test_sectors.batch_" + batch).write_all(devlib.DEV if dev_root is None else dev_root)
    return total
