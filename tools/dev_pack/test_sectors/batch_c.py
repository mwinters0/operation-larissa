"""I7 batch C: test sectors 140-159 and the campaign `test_c`: problems, triggers, the calculator, the lock, the log, hints.

This module is the batch's alone (tools/dev_pack/README.md): no other batch edits it and it edits no other batch's. `write_all` is called by
`make_dev_pack.py` (stage "data") after the dev tour.

What is here, and which engine tests use it (godot/tests/engine/):

* The campaign `test_c`, nine sectors 140-148, for the canister log (`test_canister_log`, `test_log_screen`). Its log has nine entries, unlocked in
  the deliberately uneven order LOG_UNLOCK_ORDER, so that "the newest entry" is neither the sector's number nor the largest in the list; the
  sector at position i lists the first i + 1 numbers of the order, sorted. The entries are the campaign's own words (not names of the
  string tables), spoken by the dev voice groups log_0 ... log_8, and its series digit is 3 ("ENTRY 3.07").
* Sector 150, the trigger sector, in no campaign (`test_trigger`, `test_trigger_table_rule`), with these math triggers (window pixels, as
  `dev_sectors.Trigger`):

      screen 5  (200,  90) slot 20, nibble 1, armed, re-armed on entering the screen        the "fires in most cells, wants the row in cell 0 and 8" trigger
      screen 6  (300, 120) slot 21, nibble 4, armed, NOT re-armed                           the "x is tested in the cells 5-8" trigger
      screen 7  (248, 100) slot 22, nibble 15 and (400, 200) slot 23, nibble 15, both armed  two triggers on one screen with different slots
      screen 9  (400, 240) slot 11 (the standard sector's own)

  A creature is never there (`creatures=0`); the standard sector's other triggers are replaced.
"""
from __future__ import annotations

from pathlib import Path

import devlib
from devlib import tres

import dev_sectors
import test_sectors

BATCH = "c"
CAMPAIGN_ID = "test_c"
CAMPAIGN_SECTORS = list(range(140, 149))
LOG_UNLOCK_ORDER = [3, 1, 4, 9, 2, 6, 5, 8, 7]       # entry numbers in the order the sectors unlock them
LOG_SERIES = 3
TRIGGER_SECTOR = 150


def campaign_text() -> str:
    """`test_c`: nine sectors, no finale, a log with its own words and voices."""
    entries = len(LOG_UNLOCK_ORDER)
    t = tres.Tres("Resource", "Campaign", devlib.SCRIPTS + "campaign.gd")
    names = lambda items: tres.array("StringName", ["&%s" % tres.s(x) for x in items])
    t.set("provenance", tres.s("Dev pack: the test campaign of I7 batch C (tools/dev_pack/test_sectors/batch_c.py)."))
    t.set("id", '&"%s"' % CAMPAIGN_ID)
    t.set("title", tres.s("Test C"))
    t.set("new_game_text", "&%s" % tres.s("Test C"))
    t.set("banner_index", "0")
    t.set("sectors", tres.packed_ints(CAMPAIGN_SECTORS))
    t.set("finales", tres.packed_ints([]))
    t.set("default_edu_levels", tres.packed_ints([0, 1, 1, 2, 2]))
    t.set("log_series", str(LOG_SERIES))
    t.set("log_unlock_order", tres.packed_ints(LOG_UNLOCK_ORDER))
    t.set("finale_log_counts", tres.packed_ints([]))
    t.set("log_texts", names("Test log entry %d: a note of the canister." % (n) for n in range(1, entries + 1)))
    t.set("log_voices", names("log_%d" % (n - 1) for n in range(1, entries + 1)))
    t.set("supply_texts", names("Test mission control: sector %d is done." % s for s in CAMPAIGN_SECTORS))
    t.set("supply_voices", names("" for _ in CAMPAIGN_SECTORS))
    t.set("fallback_song", '&"sector_song_1"')
    t.set("closing_scene", '&""')
    t.set("finale_text", tres.s("Test C is done."))
    t.set("finale_picture", tres.s("title_sky"))
    return t.render()


def trigger_sector() -> dev_sectors.SectorSpec:
    spec = dev_sectors.standard_sector(TRIGGER_SECTOR, zone=1, creatures=0, comment="Batch C: the trigger sector (see tools/dev_pack/test_sectors/batch_c.py).")
    T = dev_sectors.Trigger
    spec.screens[5].triggers = [T(200, 90, 20, nibble=1, armed=True, rearm=True)]
    spec.screens[6].triggers = [T(300, 120, 21, nibble=4, armed=True, rearm=False)]
    spec.screens[7].triggers = [T(248, 100, 22, nibble=15, armed=True, rearm=False), T(400, 200, 23, nibble=15, armed=True, rearm=False)]
    return spec


def write_all(dev_root: Path) -> int:
    """Writes this batch's sectors (and campaign) below `dev_root`; returns how many files were written or checked."""
    count = 0
    for i, index in enumerate(CAMPAIGN_SECTORS):
        count += test_sectors.write_sector(BATCH, dev_sectors.standard_sector(index, zone=i % 5, creatures=0,
                                           comment="Batch C: sector %d of the campaign test_c (its log)." % index), dev_root)
    count += test_sectors.write_sector(BATCH, trigger_sector(), dev_root)
    devlib.write_text(dev_root / "data" / "campaigns" / (CAMPAIGN_ID + ".tres"), campaign_text())
    if CAMPAIGN_ID not in test_sectors.WRITTEN_CAMPAIGNS[BATCH]:
        test_sectors.WRITTEN_CAMPAIGNS[BATCH].append(CAMPAIGN_ID)
    return count + 1
