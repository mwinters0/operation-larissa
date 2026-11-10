"""pytest checks of step_campaigns.py: the committed godot/data/campaigns/*.tres are exactly what the importer writes, and they say what
the program's tables say (the log's unlock order, the default levels, the registry names of the strings)."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import ds_tables
import step_campaigns as sc


@pytest.mark.parametrize("game", [0, 1])
@pytest.mark.legacy
def test_the_committed_campaign_is_what_the_importer_writes(game):
    path = common.PACK_DATA / "campaigns" / (sc.CAMPAIGNS[game]["id"] + ".tres")
    assert path.read_text(encoding="utf-8") == sc.build_campaign(game)


@pytest.mark.legacy
def test_the_two_campaigns_hold_the_tables_of_the_program():
    databank = common.load_json(common.DOCS_DATA / "databank.json")
    text = {g: sc.build_campaign(g) for g in (0, 1)}
    assert "log_unlock_order = PackedInt32Array(%s)" % ", ".join(map(str, databank["unlock_order_voyager"])) in text[0]
    assert "log_unlock_order = PackedInt32Array(%s)" % ", ".join(map(str, databank["unlock_order_expert"])) in text[1]
    edu = ds_tables.default_edu_levels()
    assert "default_edu_levels = PackedInt32Array(%s)" % ", ".join(map(str, edu[:5])) in text[0]
    assert "default_edu_levels = PackedInt32Array(%s)" % ", ".join(map(str, edu[5:])) in text[1]


@pytest.mark.legacy
def test_every_name_in_a_campaign_is_a_text_name_of_the_registry():
    texts = json.loads((common.GODOT / "names" / "original.json").read_text(encoding="utf-8"))["names"]["text"]
    for game in (0, 1):
        body = sc.build_campaign(game)
        for line in body.splitlines():
            if line.startswith(("title_text", "new_game_text", "log_texts", "supply_texts")):
                for name in line.split('&"')[1:]:
                    assert name.split('"')[0] in texts, (game, line[:40], name)
