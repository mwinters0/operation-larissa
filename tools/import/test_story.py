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
    check_against_fixture(step_story.build_news(step_story.bulletin_texts()), "news_report")


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
    assert not any(title[n]["visible"] for n in ("presents", "operation", "neptune", "copyright", "splash_left", "splash_right", "start_button", "intro_button"))
    buttons = {n: title[n] for n in ("start_button", "intro_button")}
    assert order[-2:] == ["start_button", "intro_button"] and all(b["kind"] == "button" for b in buttons.values())
    assert [(b["at"], b["choice"], b["hotkey"]) for b in buttons.values()] == [((228, 322), "start", "S"), ((330, 322), "intro", "I")]
    assert all(b["picture"] and b["pressed_picture"] and b["picture"] != b["pressed_picture"] for b in buttons.values())


@pytest.mark.legacy
def test_every_actor_a_legacy_timeline_names_is_on_its_stage():
    actors = {"news_cartoon_stage": step_story.build_news_stage(), "title_stage": step_story.build_title_stage(), "expert_closing_stage": step_story.build_expert_closing_stage()}
    played_on = {scene.stage: scene.loops + scene.timelines for scene in step_story.scenes().values()}
    for stage_name, timeline_names in played_on.items():
        held = {a["name"] for a in actors[stage_name].actors}
        for name in timeline_names:
            if name == "news_report":
                continue                                        # (its builder reads the game's texts; the stage test above covers its actors)
            named = {actor for actor, *_ in step_story.timelines()[name].tracks}
            assert named <= held, (name, named - held)


def _closing_stage(crew_starts=((496, 214), (332, 214), (368, 224), (436, 214), (496, 214), (496, 214))):
    return {a["name"]: a for a in step_story.expert_closing_stage("test", list(crew_starts)).actors}


def test_the_expert_closing_stage_lists_the_playfield_then_the_hidden_deck_in_the_originals_draw_order():
    actors = _closing_stage()
    order = list(actors)
    assert order[:3] == ["playfield", "artifact", "sub"] and order.index("cable") == 3
    deck = order.index("deck")
    assert [n for n in order[deck:] if "_piece_" not in n] == ["deck", "water", "cloud", "ship"] + ["crew_%d" % i for i in range(6)] + ["deck_artifact", "deck_sub", "deck_cable", "pod", "sea"]
    assert actors["deck"]["visible"] is False and actors["playfield"]["visible"] is True
    assert (actors["playfield"]["at"], actors["playfield"]["size"]) == ((16, 32), (608, 288)) and (actors["deck"]["at"], actors["deck"]["size"]) == ((16, 32), (608, 288))
    assert [(actors[n]["kind"], actors[n]["frames"]) for n in ("artifact", "sub", "deck_artifact", "deck_sub")] == [("frames", "zone_creatures"), ("frames", "sub")] * 2
    assert (actors["artifact"]["at"], actors["sub"]["at"]) == ((200, 232), (184, 212)) and actors["pod"]["at"] == (568, 104)
    assert all(actors["crew_%d" % i]["parent"] == "deck" and not actors["crew_%d" % i]["visible"] and not actors["crew_%d" % i]["picture"] for i in range(6))
    assert actors["crew_2"]["at"] == (368, 224)


def test_the_cable_is_a_hook_three_links_a_ball_and_links_stacked_by_their_heights_and_cut_at_the_arm():
    actors = _closing_stage()
    for name, top in (("cable", 32), ("deck_cable", 154)):
        cable = actors[name]
        assert cable["kind"] == "chain" and len(cable["pictures"]) == 3 and cable["at"] == (16, top) and cable["size"] == (608, 32 + 288 - top)
        pieces = [a for n, a in actors.items() if n.startswith(name + "_piece_")]
        assert [p["picture"] for p in pieces[:6]] == ["", "crane_link", "crane_link", "crane_link", "crane_ball", "crane_link"]
        assert [p["at"] for p in pieces[:6]] == [(220, -25), (236, -37), (236, -49), (236, -61), (228, -83), (236, -95)]        # a piece's top row rests on the one below: the heights 26, 12, 12, 12, 22
        assert all(p["parent"] == name for p in pieces)
        assert -pieces[-1]["at"][1] >= step_story.CABLE_REACH - step_story.LINK_HEIGHT       # built as far up as the reach


@pytest.mark.legacy
def test_every_actor_a_legacy_closing_timeline_names_is_on_its_stage():
    held = {a["name"] for a in step_story.build_expert_closing_stage().actors}
    for name in ("expert_hoist", "expert_deck", "expert_wait"):
        named = {actor for actor, *_ in step_story.timelines()[name].tracks}
        assert named <= held, (name, named - held)
    voyager = {a["name"]: a for a in step_story.build_voyager_closing_stage().actors}
    assert list(voyager) == ["playfield", "sub", "helicopter", "rotor"] and voyager["sub"]["frames"] == "sub" and not voyager["helicopter"]["visible"] and not voyager["rotor"]["visible"]
    assert set(step_story.stages()) >= {"expert_closing_stage", "voyager_closing_stage"}


def test_the_expert_closing_scene_is_laid_over_the_sector_deaf_until_its_last_timeline_says_listen():
    scene = step_story.build_expert_closing_scene()
    assert (scene.stage, scene.loops, scene.timelines, scene.song) == ("expert_closing_stage", [], ["expert_hoist", "expert_deck", "expert_wait"], "closing")
    assert scene.backdrop is False and scene.deaf_until_listen is True and scene.stage in step_story.stages()
    text = scene.render()
    assert 'script_class="StoryScene"' in text and "backdrop = false" in text and "deaf_until_listen = true" in text and 'song = &"closing"' in text
    assert "backdrop" not in step_story.build_news_scene().render() and "deaf_until_listen" not in step_story.build_title_scene().render()
    assert step_story.scenes()[step_story.EXPERT_CLOSING_SCENE].render() == text


def test_the_deck_cuts_to_the_deck_at_its_first_moment_and_the_wait_listens_from_its_first():
    deck = {(actor, prop): keys for actor, prop, keys, _smooth in step_story.build_expert_deck().tracks}
    assert deck["playfield", "visible"] == [(0, "false")] and deck["deck", "visible"] == [(0, "true")]
    wait = step_story.build_expert_wait()
    assert wait.loop and wait.cues == [(0, "event", "listen")]


def test_the_news_cartoon_scene_names_its_stage_timelines_song_and_five_speech_steps_in_order():
    scene = step_story.build_news_scene()
    assert (scene.stage, scene.loops, scene.timelines, scene.song) == ("news_cartoon_stage", ["news_ambient"], ["news_report"], "opening")
    assert [group for _pause, group in scene.speech] == ["news_speech_%d" % i for i in range(len(common.NEWS_SPEECH_GROUPS))]
    assert [pause for pause, _group in scene.speech] == [219, 248, 248, 248, 0]
    assert set(scene.loops + scene.timelines) <= step_story.TIMELINE_NAMES and scene.stage in step_story.stages()
    text = scene.render()
    assert 'script_class="StoryScene"' in text and text.count('script = ExtResource("2_speech_step")') == 5
    assert 'group = &"news_speech_4"' in text and "pause_ticks = 219" in text
    assert scene.render() == step_story.build_news_scene().render()


def test_the_title_scene_plays_the_ship_then_the_reveal_stops_its_song_there_and_starts_the_story_song_after_the_prompt():
    scene = step_story.build_title_scene()
    assert (scene.stage, scene.loops, scene.timelines, scene.song, scene.speech) == ("title_stage", [], ["title_ship", "title_reveal"], "title", [])
    assert (scene.song_stops_at, scene.prompt_song) == ("title_reveal", "opening") and scene.stage in step_story.stages()
    text = scene.render()
    assert 'script_class="StoryScene"' in text and 'song_stops_at = &"title_reveal"' in text and 'prompt_song = &"opening"' in text
    assert set(step_story.scenes()) == {"news_cartoon", "title", "expert_closing"}


def test_the_opening_lists_the_cartoon_the_title_that_leads_on_with_intro_and_the_story_and_starts_over():
    opening = step_story.build_opening()
    assert opening.parts == [("scene", "news_cartoon", ""), ("scene", "title", "intro"), ("story", "story_script", "")] and opening.starts_over
    for kind, name, _leads_on in opening.parts:
        assert name in step_story.scenes() if kind == "scene" else name == "story_script"
    text = opening.render()
    assert 'script_class="OpeningList"' in text and text.count('script = ExtResource("2_opening_part")') == 3
    assert 'leads_on = &"intro"' in text and "starts_over = true" in text and text.count("leads_on") == 1
    assert opening.render() == step_story.build_opening().render()


# --- the console's flicker: ours, baked into news_ambient --------------------------------------------------------------------------

def flicker_digest(length: float, status_lights: int, panel_lights: int) -> str:
    """The digest of the tracks `console_flicker` adds: actor, property, then `tick:value` of every key."""
    timeline = step_story.Timeline(length, "test", loop=True)
    step_story.console_flicker(timeline, 10, status_lights, panel_lights, "status_light", "panel_light")
    text = "\n".join("%s %s %s" % (actor, prop, ",".join("%g:%s" % key for key in keys)) for actor, prop, keys, _smooth in timeline.tracks)
    return step_story.sha256_hex(text.encode("utf-8"))


def test_the_generator_is_godots_with_the_seed_of_the_flicker():
    """`rng.seed = 73` then `rng.randi() % 299` in GDScript gave these numbers (the engine drew them while it played; the baked files were compared with
    what it drew, key by key, for the legacy pack's 64 redraws and the dev pack's 16)."""
    rng = step_story.Pcg32(step_story.FLICKER_SEED)
    assert [rng.randi() % step_story.FLICKER_MODULUS for _ in range(12)] == [4, 40, 72, 169, 88, 263, 4, 87, 236, 76, 66, 140]


def test_the_flicker_is_the_one_the_engine_drew_for_the_legacy_and_the_dev_pack():
    assert flicker_digest(640, 6, 8) == "820c62b16b378125775b0da5b47df57506975f1d648f8fb6b1b8e7f0f1bd8d3a"
    assert flicker_digest(160, 6, 8) == "146faff6c7245e82c39a8c46908bf4d0d5abda0aa861dd1458df4eac426b93bd"


def test_the_flicker_has_a_key_per_redraw_for_each_light_and_lights_a_status_light_below_100():
    timeline = step_story.Timeline(640, "test", loop=True)
    step_story.console_flicker(timeline, 10, 2, 1, "status_light", "panel_light")
    tracks = {(actor, prop): keys for actor, prop, keys, _smooth in timeline.tracks}
    assert sorted(tracks) == [("panel_00", "picture"), ("status_00", "picture"), ("status_00", "visible"), ("status_01", "picture"), ("status_01", "visible")]
    assert all(len(keys) == 64 and keys[1][0] == 10 for keys in tracks.values())
    rng = step_story.Pcg32(step_story.FLICKER_SEED)
    first = rng.randi() % 299
    assert tracks[("status_00", "visible")][0][1] == ("true" if first < 100 else "false")
    assert tracks[("status_00", "picture")][0][1] == '&"status_light_%d"' % (first % 3)


@pytest.mark.legacy
def test_the_legacy_news_ambient_holds_the_flicker_of_every_light_of_its_stage():
    timeline = step_story.build_news_ambient()
    named = {(actor, prop) for actor, prop, _keys, _smooth in timeline.tracks}
    stage = {a["name"] for a in step_story.build_news_stage().actors}
    assert {f"status_{i:02d}" for i in range(6)} | {f"panel_{i:02d}" for i in range(8)} <= stage
    assert all((f"status_{i:02d}", prop) in named for i in range(6) for prop in ("visible", "picture"))
    assert all((f"panel_{i:02d}", "picture") in named for i in range(8))
    assert "console's lights flicker" in timeline.provenance


def test_the_news_cartoons_eleven_clips_are_five_voice_groups_in_order():
    groups = common.news_speech_groups(list(range(4000, 4011)))
    assert groups == {"news_speech_0": [4000, 4001], "news_speech_1": [4002, 4003, 4004], "news_speech_2": [4005], "news_speech_3": [4006],
                      "news_speech_4": [4007, 4008, 4009, 4010]}
