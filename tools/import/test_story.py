"""Step 'story': the cutscene timelines the importer writes.

The same facts that godot/tests/legacy/test_cutscene_timing.gd checks on the loaded resources are checked here on what the importer
produces (the hash of each timeline's timing record, `step_story.timing_record`, against godot/tests/fixtures/cutscene_timing.json),
so a change of the importer that moves a moment or a length fails before Godot is started. Godot writes that fixture from the legacy
pack, so these tests also tell that the Python and the GDScript record agree. Reading the bulletins needs your copy of the game
(extracted/); without it the one test that needs them is skipped.
"""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common
import foe_names
import step_story

FIXTURE = {name: entry["sha256"] for name, entry in json.loads((common.GODOT / "tests" / "fixtures" / "cutscene_timing.json").read_text())["cutscenes"].items()}
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


def check_against_fixture(timeline, name):
    assert step_story.timeline_digest(timeline) == FIXTURE[name], "%s: its timing record is not the fixture's" % name


@pytest.mark.parametrize("name", sorted(builders()))
@pytest.mark.legacy
def test_the_timelines_have_the_recorded_lengths_and_moments(name):
    check_against_fixture(builders()[name](), name)


@NEEDS_GAME
@pytest.mark.legacy
def test_the_news_cartoon_has_the_recorded_length_and_moments():
    check_against_fixture(step_story.build_news(step_story.bulletin_texts()), "news_cartoon")


def test_the_record_is_in_thousandths_sorted_and_counts_each_moment_once():
    record = step_story.timing_record(591.3, True, [3.0, 0.0, 3.0, 0.0004, 1.5], [(584, "event", "e"), (292, "sound", "b"), (584, "sound", "a")])
    assert record == "length=591300;loop=1;moments=0,1500,3000;cues=292000:sound:b,584000:sound:a,584000:event:e"


@pytest.mark.parametrize("name", sorted(builders()))
@pytest.mark.legacy
def test_rendering_twice_gives_the_same_text(name):
    assert builders()[name]().render() == builders()[name]().render()


@pytest.mark.parametrize("name", sorted(builders()))
@pytest.mark.legacy
def test_no_key_lies_after_the_end_and_the_moments_are_in_order(name):
    timeline = builders()[name]()
    for _actor, _prop, keys, _smooth in timeline.tracks:
        assert [k[0] for k in keys] == sorted(k[0] for k in keys)
        assert keys[-1][0] <= timeline.length


@pytest.mark.legacy
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


@pytest.mark.legacy
def test_a_crew_member_repeats_and_only_the_left_one_walks():
    members = common.load_json(common.TABLES / "opening.json")["news_cartoon"]["crew"]["members"]
    walker = members[-1]
    later = [m for m in members if m["first_call"] > 1]
    assert later == [walker]                              # only the man on the left comes in late
    cycle = walker["pictures"]
    cycle_total = sum(entry[2] for entry in cycle)
    assert cycle_total != 0 and all(sum(entry[2] for entry in m["pictures"]) == 0 for m in members[:-1])
    def frame(member, call):
        found = step_story.crew_frame(member, call)
        assert found is not None
        return found

    first = walker["first_call"]
    assert step_story.crew_frame(walker, first - 1) is None
    picture, mirror, x = frame(walker, first)
    assert (picture, mirror) == tuple(cycle[0][:2]) and x == walker["x0"] + cycle[0][2]
    assert frame(walker, first + 1)[2] == x + cycle[1][2]
    assert frame(walker, first + len(cycle))[2] == x + cycle_total          # x is not reset when the script restarts
    for m in members[:-1]:
        assert frame(m, m["first_call"] + 7 * len(m["pictures"]) + 1)[2] == frame(m, m["first_call"] + 1)[2]


@pytest.mark.legacy
def test_the_sailors_program_runs_like_the_originals():
    crew = common.load_json(common.TABLES / "expert_closing.json")
    for n in range(6):
        program = crew["scripts"][n]
        actor = step_story.CrewActor(crew, n)
        lead = program[0]
        if lead[0] == actor.WAIT:                          # a leading wait draws nothing for as many steps as it says
            for _ in range(lead[3]):
                actor.step()
                assert not actor.visible
        items = {crew["first_picture"] + record[1] for record in program}
        drawn = 0
        for _ in range(300):
            before = (actor.x, actor.y)
            actor.step()
            dx, dy = actor.x - before[0], actor.y - before[1]
            assert dx in (-actor.STEP_X, 0, actor.STEP_X) and dy in (-actor.STEP_Y, 0, actor.STEP_Y) and not (dx and dy)
            if actor.visible:
                drawn += 1
                assert actor.picture in items
            else:
                assert (actor.x, actor.y) == before
        assert drawn > 0


def test_the_text_names_are_the_registrys():
    assert step_story.text_name(10003) == "news_bulletin_0"
    assert step_story.picture(1027) == "ship_idle"
    assert step_story.sound(43) == "opening_scene"
    assert step_story.sound(51) == "opening_end"
    assert step_story.frame_name(35, 6) == "alien_artifact_0"


def test_a_picture_nobody_named_gets_its_made_up_name():
    unnamed = next(n for n in range(1000, 2500) if not foe_names.original().real_name("ui_picture", n))
    assert step_story.picture(unnamed) == "ui_%d" % unnamed


@pytest.mark.legacy
def test_the_stages_put_every_actor_at_its_point_of_the_position_table_in_draw_order():
    data = common.load_json(common.TABLES / "opening.json")
    pts, names = data["points"], data["point_names"]
    news = {a["name"]: a for a in step_story.build_news_stage().actors}
    assert list(news)[:2] == ["map", "dot_00"] and list(news)[-1] == "teletype"
    assert [news["dot_%02d" % i]["at"] for i in range(21)] == [pts[i] for i in range(names["capsule_trail"][0], names["capsule_trail"][1] + 1)]
    assert news["ring"]["at"] == pts[names["crash_site"]] and news["console_right"]["mirror"] and not news["console_left"]["mirror"]
    assert [news["status_%02d" % i]["mirror"] for i in range(6)] == [False] * 3 + [True] * 3
    assert [news["panel_%02d" % i]["mirror"] for i in range(8)] == [False] * 4 + [True] * 4
    assert [news["crew_%d" % i]["visible"] for i in range(5)] == [True] * 4 + [False]          # the man on the left walks in later
    assert news["teletype"]["kind"] == "text" and news["teletype"]["at"] == pts[names["teletype"]]
    title = {a["name"]: a for a in step_story.build_title_stage().actors}
    order = list(title)
    assert order.index("ship") < order.index("hull") < order.index("radar") < order.index("hook") < order.index("mini_sub") < order.index("waves_front") < order.index("spray")
    assert [title[n]["parent"] for n in ("hull", "radar", "hook")] == ["ship"] * 3 and title["ship"]["kind"] == "group" and title["ship"]["at"] == pts[names["ship_hull"]]
    assert title["splash_right"]["at"][0] - title["splash_left"]["at"][0] == 76 and title["splash_right"]["mirror"]
    assert title["mini_sub"]["clip"] == (0, 0, 72, 44)
    assert not any(title[n]["visible"] for n in ("presents", "operation", "neptune", "copyright", "splash_left", "splash_right"))


@pytest.mark.legacy
def test_every_actor_a_legacy_timeline_names_is_on_its_stage():
    actors = {"news_cartoon_stage": step_story.build_news_stage(), "title_stage": step_story.build_title_stage()}
    played_on = {"news_cartoon_stage": ("news_cartoon", "news_ambient"), "title_stage": ("title_ship", "title_reveal")}
    for stage_name, timeline_names in played_on.items():
        held = {a["name"] for a in actors[stage_name].actors}
        for name in timeline_names:
            if name == "news_cartoon":
                continue                                        # (its builder reads the game's texts; the stage test above covers its actors)
            named = {actor for actor, *_ in step_story.timelines()[name].tracks}
            assert named <= held, (name, named - held)
