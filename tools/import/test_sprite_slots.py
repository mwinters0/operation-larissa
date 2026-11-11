"""pytest checks of tools/analysis/data/sprite_slots.json, the slot -> picture table of the creature and deco sets."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common


def table() -> dict:
    return json.loads(common.SPRITE_SLOTS_FILE.read_text())


def test_slots_follow_each_other_without_gaps():
    c, d = table()["creatures"], table()["decos"]
    assert (c["common"]["slot"], c["ink"]["slot"], c["zones"][0]["slot"]) == (0, 28, 35)
    assert c["ink"]["slot"] == len(c["common"]["pictures"]) and c["zones"][0]["slot"] == c["ink"]["slot"] + len(c["ink"]["pictures"])
    assert {z["slot"] for z in c["zones"]} == {35} and len(c["zones"]) == 7
    assert d["common"]["slot"] == 0 and {z["slot"] for z in d["zones"]} == {70} and len(d["zones"]) == 5
    assert len(d["common"]["pictures"]) == 70
    for zone in range(7):
        assert len(common.foe_slots(zone)) == 35 + common.ZONE_FOE_COUNTS[zone]
    for zone in range(5):
        assert len(common.deco_slots(zone)) == 70 + common.ZONE_DECO_COUNTS[zone]


def test_each_segment_is_the_start_of_its_bundle():
    """`bundle` is where the pictures come from: NEP.DLL's bundle lists, as the extractor saved them (needs extracted/)."""
    if not (common.EXTRACTED / "images" / "sprite_bundles.json").exists():
        pytest.skip("run tools/extract/run_all.sh first")
    t = table()
    segments = [t["creatures"]["common"], t["creatures"]["ink"], *t["creatures"]["zones"], t["decos"]["common"], *t["decos"]["zones"]]
    for s in segments:
        assert s["pictures"] == common.bundle_ids(s["bundle"])[: len(s["pictures"])], s["bundle"]
    # the zone sets of the five art zones are bundles 25 + 3z (creatures) and 24 + 3z (decos); the finales use 110 / 112
    assert [z["bundle"] for z in t["creatures"]["zones"]] == [25, 28, 31, 34, 37, 110, 112]
    assert [z["bundle"] for z in t["decos"]["zones"]] == [24, 27, 30, 33, 36]
