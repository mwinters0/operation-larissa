"""pytest checks of new sectors: a sector with a number beyond the original 32 (a "new sector" the designers made, godot/src/core/
catalog.gd `Catalog.is_original_sector`) has no original bytes, so its files are its own source. The importer must never write or
delete them, and the reset and harvest tools must refuse their numbers with a clear message instead of overwriting them. None of these
tests needs the importer-written original bytes."""
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import harvest_foe_annotations as harvest
import import_all
import reset_foe_scripts
import reset_screens
import reset_sector_header
import step_campaigns
import step_sectors


def test_the_original_count_is_32_and_says_which_numbers_are_original():
    assert common.ORIGINAL_SECTOR_COUNT == 32
    assert common.is_original_sector(0) and common.is_original_sector(31)
    assert not common.is_original_sector(32) and not common.is_original_sector(100) and not common.is_original_sector(-1)
    assert common.refuse_new_sectors([0, 31]) == ""
    message = common.refuse_new_sectors([3, 32, 100])
    assert "sectors 32, 100 are not one of the original sectors (0-31)" in message and "own source" in message


def test_the_importer_owns_only_files_of_the_original_sectors():
    """`--clean` deletes exactly `owned_files`, and the importer writes nothing else into godot/data/sectors/."""
    owned = import_all.OWNED_FILES["sectors"]()
    assert owned == step_sectors.owned_files()
    numbers = {int(m.group(1)) for f in owned if (m := re.search(r"sector_(\d+)", f.parent.name if f.name.startswith("screen_") else f.name))}
    assert numbers == set(range(common.ORIGINAL_SECTOR_COUNT))
    assert import_all.OWNED_DIRS["sectors"] == []                  # never the whole folder
    assert common.sector_file(32, "tres") not in owned and common.sector_file(100, "foe") not in owned


def test_the_importer_owns_only_the_original_two_campaign_files():
    """A campaign of a designer's own put in the legacy pack's data/campaigns/ sits next to voyager.tres and expert.tres; `--clean`
    must not take the folder with it."""
    owned = import_all.OWNED_FILES["campaigns"]()
    assert owned == step_campaigns.owned_files()
    assert [f.name for f in owned] == ["voyager.tres", "expert.tres"]
    assert import_all.OWNED_DIRS["campaigns"] == []                # never the whole folder
    assert common.PACK_DATA / "campaigns" / "reef_school.tres" not in owned


def test_folders_of_three_digit_numbers_keep_the_pattern():
    assert common.sector_dir(7).name == "sector_07"
    assert common.sector_dir(100).name == "sector_100"
    assert common.sector_file(100, "foe").name == "sector_100.foe"


def test_the_reset_tools_refuse_a_new_sector_before_they_read_or_write_anything(tmp_path):
    missing = tmp_path / "nothing.json"                       # never read: the refusal comes first
    with pytest.raises(ValueError, match="sector 32 has no original header"):
        reset_sector_header.run([3, 32], sector_dir=tmp_path, raw_fixture=missing)
    with pytest.raises(ValueError, match="not one of the original sectors"):
        reset_screens.run([(3, 1), (40, 0)], sector_dir=tmp_path, raw=missing)
    with pytest.raises(ValueError, match="sector 32 has no original script"):
        reset_foe_scripts.run([32], sector_dir=tmp_path, raw=missing)
    for bad in ("32", "100:3", "-1"):
        with pytest.raises(ValueError, match="not one of the original sectors"):
            reset_screens.parse_target(bad)
    assert list(tmp_path.iterdir()) == []


def test_harvest_refuses_a_new_sector_and_names_it():
    assert "sector 32 has no original script" in reset_foe_scripts.refuse_new_sectors([32])
    assert reset_foe_scripts.original_sectors() == list(range(common.ORIGINAL_SECTOR_COUNT))
    assert harvest.reset.refuse_new_sectors([5, 33]) != ""
