"""The test-sector hooks of the I7 batches (tools/dev_pack/test_sectors/): ranges that never overlap, and nothing in the pack outside them.

    uv run pytest tools/dev_pack/test_batches.py -q
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import dev_sectors
import devlib
import test_sectors

DEV_PACK_GD = devlib.GODOT / "tests" / "engine" / "dev_pack.gd"


def test_the_ranges_are_twenty_sectors_each_and_do_not_overlap():
    seen: set[int] = set()
    for batch, numbers in test_sectors.RANGES.items():
        assert len(numbers) == 20, batch
        assert not seen & set(numbers), batch
        seen |= set(numbers)
    assert min(seen) == 100 and max(seen) == 199


def test_the_ranges_are_the_ones_the_engine_test_helper_names():
    text = DEV_PACK_GD.read_text()
    for batch, numbers in test_sectors.RANGES.items():
        found = re.search(r"const BATCH_%s := Vector2i\((\d+), (\d+)\)" % batch.upper(), text)
        assert found and (int(found.group(1)), int(found.group(2))) == (numbers[0], numbers[-1]), batch


def test_a_batch_cannot_write_a_sector_or_a_campaign_of_another(tmp_path):
    spec = dev_sectors.standard_sector(121, zone=0, creatures=0)
    with pytest.raises(ValueError):
        test_sectors.write_sector("a", spec, tmp_path)
    with pytest.raises(ValueError):
        test_sectors.write_campaign("a", "Wrong", [100, 121], [101], [0], "End.", tmp_path)
    assert not list(tmp_path.rglob("*"))


def test_a_batch_writes_its_own_sector_and_campaign(tmp_path):
    assert test_sectors.write_sector("b", dev_sectors.standard_sector(121, zone=0, creatures=0), tmp_path) == 2 + dev_sectors.SCREENS
    assert test_sectors.write_campaign("b", "B", [121], [122], [0, 0], "End.", tmp_path) == 1
    assert (tmp_path / "data" / "sectors" / "sector_121" / "sector_121.tres").is_file()
    assert 'id = &"test_b"' in (tmp_path / "data" / "campaigns" / "test_b.tres").read_text()
    test_sectors.WRITTEN_SECTORS["b"].remove(121)                 # (only a scratch run: keep the registry as the real run left it)
    test_sectors.WRITTEN_CAMPAIGNS["b"].remove("test_b")


def test_the_pack_holds_no_test_sector_or_campaign_that_no_batch_writes():
    test_sectors.write_all(devlib.DEV)
    written = {n for numbers in test_sectors.WRITTEN_SECTORS.values() for n in numbers}
    on_disk = {int(p.name.removeprefix("sector_")) for p in (devlib.DEV / "data" / "sectors").glob("sector_*") if int(p.name.removeprefix("sector_")) >= 100}
    assert on_disk == written, "sectors on disk and written: %s" % sorted(on_disk ^ written)
    campaigns = {p.stem for p in (devlib.DEV / "data" / "campaigns").glob("test_*.tres")}
    assert campaigns == {c for cs in test_sectors.WRITTEN_CAMPAIGNS.values() for c in cs}
