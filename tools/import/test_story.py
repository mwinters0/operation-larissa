"""Step 'story': the cutscene timelines the importer writes.

The same facts that godot/tests/legacy/test_cutscene_timing.gd checks on the loaded resources are checked here on what the importer
produces, so a change of the importer that moves a moment or a length fails before Godot is started. Reading the bulletins needs
your copy of the game (extracted/); without it the one test that needs them is skipped.
"""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import foe_names
import step_story

FIXTURE = json.loads((common.GODOT / "tests" / "fixtures" / "cutscene_timing.json").read_text())["cutscenes"]
NEEDS_GAME = pytest.mark.skipif(not (common.EXTRACTED / "data" / "NEP_text.json").is_file(), reason="run the importer on your copy of the game (extracted/ is missing)")


def builders():
    """Every timeline the step writes that does not need the game's texts, by the name the fixture uses."""
    return {
        "news_ambient": step_story.build_news_ambient,
        "title_ship": step_story.build_title_ship,
        "title_reveal": step_story.build_title_reveal,
        "expert_hoist": step_story.build_expert_hoist,
        "expert_deck": step_story.build_expert_deck,
        "expert_wait": step_story.build_expert_wait,
    }


def cues(timeline):
    return [[tick, kind, name] for tick, kind, name in sorted(timeline.cues, key=lambda c: (c[0], c[1] != "sound"))]


def check_against_fixture(timeline, expected):
    assert timeline.length == pytest.approx(expected["length"], abs=1e-3)
    assert timeline.loop == expected["loop"]
    assert timeline.key_times() == pytest.approx(expected["key_ticks"], abs=1e-3)
    assert [[round(t, 3), k, n] for t, k, n in cues(timeline)] == [[round(float(t), 3), k, n] for t, k, n in expected["cues"]]


@pytest.mark.parametrize("name", sorted(builders()))
def test_the_timelines_have_the_lengths_and_moments_they_had_before_d8(name):
    check_against_fixture(builders()[name](), FIXTURE[name])


@NEEDS_GAME
def test_the_news_cartoon_has_the_length_and_moments_it_had_before_d8():
    check_against_fixture(step_story.build_news(step_story.bulletin_texts()), FIXTURE["news_cartoon"])


@pytest.mark.parametrize("name", sorted(builders()))
def test_rendering_twice_gives_the_same_text(name):
    assert builders()[name]().render() == builders()[name]().render()


@pytest.mark.parametrize("name", sorted(builders()))
def test_no_key_lies_after_the_end_and_the_moments_are_in_order(name):
    timeline = builders()[name]()
    for _actor, _prop, keys, _smooth in timeline.tracks:
        assert [k[0] for k in keys] == sorted(k[0] for k in keys)
        assert keys[-1][0] <= timeline.length


def test_the_expert_stages_move_in_whole_steps_of_18_ticks():
    for build in (step_story.build_expert_hoist, step_story.build_expert_deck, step_story.build_expert_wait):
        timeline = build()
        assert timeline.length % step_story.EXPERT_STEP == 0
        assert all(t % step_story.EXPERT_STEP == 0 for t in timeline.key_times())


def test_the_hoist_has_the_originals_number_of_steps():
    assert step_story.turn_steps() == 2
    assert step_story.hoist_steps() == 2 + 20 + 16 + 17
    bottom = step_story.HOOK_START_BOTTOM + step_story.HOOK_STEP * step_story.DESCENT_STEPS
    assert bottom - step_story.ASCENT_STEPS * step_story.HOOK_STEP <= 0x20 < bottom - (step_story.ASCENT_STEPS - 1) * step_story.HOOK_STEP


def test_every_turn_table_ends_where_it_says():
    for table, done in ((step_story.TURN_TABLE, step_story.TURN_DONE_CELL), (step_story.VOYAGER_TURN_TABLE, step_story.VOYAGER_TURN_DONE_CELL)):
        for start in range(9):
            cell, steps = start, 0
            while cell != done:
                cell = table[cell]
                steps += 1
                assert steps < 10


def test_a_crew_member_repeats_and_only_the_left_one_walks():
    members = common.load_json(common.DOCS_DATA / "opening.json")["news_cartoon"]["crew"]["members"]
    def frame(m, call):
        found = step_story.crew_frame(members[m], call)
        assert found is not None
        return found

    assert step_story.crew_frame(members[4], 219) is None
    first = frame(4, 220)
    assert first[0] == 1024 and first[1] == 1 and first[2] == 0
    assert frame(4, 221)[2] == 12
    assert frame(4, 220 + 70 + 27)[2] == 648             # x is not reset when the script restarts
    for m in range(4):
        assert frame(m, 500)[2] == members[m]["x0"]


def test_the_sailors_program_runs_like_the_originals(tmp_path):
    crew = common.load_json(common.DOCS_DATA / "expert_closing.json")
    first = step_story.CrewActor(crew, 0)
    for _ in range(80):                                   # record 0: wait 80 steps, nothing drawn
        first.step()
        assert not first.visible
    first.step()
    assert first.visible and first.picture == 2025 and first.x == 496
    first.step()
    assert first.x == 492
    actors = [step_story.CrewActor(crew, n) for n in range(6)]
    for _ in range(146):
        for actor in actors:
            actor.step()
    assert [a.x for a in actors] == [368, 408, 432, 456, 480, 504]


def test_the_text_names_are_the_registrys():
    assert step_story.text_name(10003) == "news_bulletin_0"
    assert step_story.picture(1027) == "ship_idle"
    assert step_story.sound(43) == "opening_scene"
    assert step_story.sound(51) == "opening_end"
    assert step_story.frame_name(35, 6) == "alien_artifact_0"


def test_a_picture_nobody_named_gets_its_made_up_name():
    unnamed = next(n for n in range(1000, 2500) if not foe_names.original().real_name("ui_picture", n))
    assert step_story.picture(unnamed) == "ui_%d" % unnamed
