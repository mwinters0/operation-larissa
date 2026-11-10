"""pytest checks of the label tables step_problems.py builds for the combination lock and the ballast panel: the strings
`DoCombinationLock` (0x421780) and `LoadBallastLabels` (0x419d96) load replace the EXE's static decimal labels. The strings here are
made up by the test (a label's number with the padding the loaded text does not have); no legacy pack is needed."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import step_problems as sp


def strings_like_the_game() -> dict:
    """string id -> text for the ids the loaders use: the number of the static label at that place, written "0.5" for " .5"."""
    lock = common.load_json(common.DOCS_DATA / "lock_wheel.json")
    out = {}

    def write(ids, static):
        for i, label in zip(ids, static):
            out[str(i)] = label.strip().replace(".", "0.", 1) if label.strip().startswith(".") else label.strip()

    write(range(11219, 11227), lock["operand_labels_by_wheel_set"]["7"])
    write(range(11228, 11236), lock["operand_labels_by_wheel_set"]["11"])
    write([*range(11220, 11227), 11227], lock["answer_labels_by_wheel_set"]["6"])
    write(range(11237, 11245), lock["answer_labels_by_wheel_set"]["8"])
    write(range(11215, 11219), [".01", ".05", ".10", ".25"])
    return out


def test_the_lock_shows_the_loaded_decimal_labels_and_keeps_the_others():
    lock = common.load_json(common.DOCS_DATA / "lock_wheel.json")
    operand, answer = sp.lock_labels(lock, strings_like_the_game())
    assert operand[7] == operand[8] == ["0.1", "0.2", "0.3", "0.4", "0.5", "0.6", "0.7", "0.8"]
    assert operand[11] == ["0.10", "0.20", "0.30", "0.40", "0.50", "0.60", "0.70", "0.80"]
    assert answer[6] == ["0.2", "0.3", "0.4", "0.5", "0.6", "0.7", "0.8", "0.9"]
    assert answer[8] == ["1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "1.8"]
    for wheel_set in (0, 1, 2, 3, 4, 5, 6, 9, 10):
        assert operand[wheel_set] == lock["operand_labels_by_wheel_set"][str(wheel_set)]
    for wheel_set in (0, 1, 2, 3, 4, 5, 7, 9, 10, 11):
        assert answer[wheel_set] == lock["answer_labels_by_wheel_set"][str(wheel_set)]


def test_the_ballast_panel_shows_the_loaded_labels_in_mode_1_only():
    modes = common.load_json(common.DOCS_DATA / "ballast.json")["modes"]
    labels = sp.ballast_labels(modes, strings_like_the_game())
    assert labels["1"] == ["0.01"] * 4 + ["0.05"] * 2 + ["0.10"] + ["0.25"] * 3
    assert labels["0"] == modes["0"]["labels"]
    assert labels["2"] == modes["2"]["labels"]


def test_a_loaded_string_that_says_another_number_is_refused():
    strings = strings_like_the_game()
    strings["11223"] = "0.9"                      # the fifth tenth: " .5" in the table
    lock = common.load_json(common.DOCS_DATA / "lock_wheel.json")
    with pytest.raises(AssertionError):
        sp.lock_labels(lock, strings)
