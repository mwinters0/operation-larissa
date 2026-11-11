"""The dev pack's cutscenes: choreography of its own, short and plain, played by the same scenes as the original's.

The scenes (`src/story/`) ask the pack chain for `data/story/<name>.tres` (`Catalog.story_timeline`, `story_script`, `voyager_closing_script`,
`closing_crew`) and tell a `CutsceneCast` which node plays which actor. These timelines use the same actor names and the same property
words as the original's, so every scene finds its nodes, but a few keys each: a ship that sails in and stops, a sub that sinks, a title
that appears in three holds, a hook that comes down and hoists, six sailors that step to and fro, four story pages. Every number is
dev's own (a step of 12 ticks, a hold of 100), none is read from the legacy pack; the pictures and sounds are named by the registry,
as the importer names them (godot/names/original.json), which the dev pack has a picture or sound for.

Teaches: that a cutscene is data a pack can replace whole, and that the timing lives in the data (the tests of the mechanism read the dev
timelines' own lengths and marks; the original's numbers are pinned by tests/legacy/).
"""
from __future__ import annotations

from devlib import DEV, SCRIPTS, write_text, tres

import step_story as st

STEP = 12                                   # ticks of the expert closing's and the ship scene's step: ours
SHIP_FRAMES = 36
SHIP_STOPS_AT_FRAME = 15
SHIP_STOPS_AT_X = 40
REVEAL_HOLD = 100                           # ticks of one hold of the title
CREW_FIRST_PICTURE = 2012                   # the sailors' items count from this picture of the registry


def timeline(length: float, why: str, loop: bool = False) -> st.Timeline:
    return st.Timeline(length, "Dev pack: %s (tools/dev_pack/dev_story.py)." % why, loop)


def names(pattern: str, count: int) -> list[str]:
    return [pattern % i for i in range(count)]


def seq(step_ticks: float, values: list[str]) -> list[tuple[float, str]]:
    """Keys one step apart, one value each."""
    return [(i * step_ticks, v) for i, v in enumerate(values)]


def pictures(step_ticks: float, picture_names: list[str]) -> list[tuple[float, str]]:
    return seq(step_ticks, [st.sn(n) for n in picture_names])


def flags(step_ticks: float, values: list[bool]) -> list[tuple[float, str]]:
    return seq(step_ticks, [st.boolean(v) for v in values])


# --- the opening -------------------------------------------------------------------------------------------------

def news_ambient() -> st.Timeline:
    """The alarm lights and the ring: a loop of 16 redraws of 10 ticks."""
    steps = 16
    t = timeline(steps * 10, "the alarm lights and the pulsing ring, a loop of 16 redraws of 10 ticks", loop=True)
    for light in range(3):
        t.track("alarm_%d" % light, "picture", pictures(10, ["alarm_light_%d" % ((s + light) % 3) for s in range(steps)]))
        t.track("alarm_%d" % light, "mirror", flags(10, [(s // 4) % 2 == 1 for s in range(steps)]))
    t.track("ring", "picture", pictures(10, ["crash_ring_%d" % (s % 4) for s in range(steps)]))
    return t


def title_ship() -> st.Timeline:
    """The ship sails in and stops, the sub is let go and falls past the waterline (row 312) with a splash, the ship sails on."""
    t = timeline(SHIP_FRAMES * STEP, "the ship scene: %d frames of %d ticks" % (SHIP_FRAMES, STEP))
    frames = range(SHIP_FRAMES)

    def ship_x(f: int) -> int:
        if f <= SHIP_STOPS_AT_FRAME:
            return -200 + 16 * f                                    # 40 when it stops
        return SHIP_STOPS_AT_X if f <= SHIP_STOPS_AT_FRAME + 6 else SHIP_STOPS_AT_X + 8 * (f - SHIP_STOPS_AT_FRAME - 6)

    def sub_y(f: int) -> int:
        return 236 if f < SHIP_STOPS_AT_FRAME + 1 else 236 + 6 * (f - SHIP_STOPS_AT_FRAME - 1)

    def sub_rows(f: int) -> int:
        return max(0, min(44, 312 - sub_y(f)))                      # the water line cuts it off from below

    dropped_at = SHIP_STOPS_AT_FRAME + 1
    touches = next(f for f in frames if sub_rows(f) < 44)
    t.track("ship", "position", seq(STEP, [st.v2(ship_x(f), 120) for f in frames]))
    t.track("radar", "picture", pictures(STEP, ["ship_radar_%d" % (0, 1, 2, 1)[f % 4] for f in frames]))
    t.track("radar", "mirror", flags(STEP, [(f // 4) % 2 == 1 for f in frames]))
    t.track("hook", "picture", pictures(STEP, ["ship_hook_0"] * SHIP_FRAMES))
    t.track("mini_sub", "position", seq(STEP, [st.v2(ship_x(min(f, dropped_at)) + 80, sub_y(f)) for f in frames]))   # it moves with the ship until it is let go
    t.track("mini_sub", "clip", seq(STEP, [st.rect(0, 0, 72, sub_rows(f)) for f in frames]))
    t.track("mini_sub", "visible", flags(STEP, [sub_rows(f) > 0 for f in frames]))
    t.track("spray", "position", seq(STEP, [st.v2(ship_x(f) + 24, 252) for f in frames]))
    t.track("spray", "visible", flags(STEP, [f < SHIP_FRAMES - 2 for f in frames]))
    t.track("spray", "picture", pictures(STEP, ["spray_%d" % (1 + f % 2) for f in frames]))
    splashing = [touches + 2 <= f < touches + 7 for f in frames]       # five pictures, from two frames after the sound
    for side in ("left", "right"):
        t.track("splash_" + side, "picture", pictures(STEP, ["spray_%d" % (f - touches - 2 if splashing[f] else 0) for f in frames]))
        t.track("splash_" + side, "visible", flags(STEP, splashing))
    t.cue(STEP * touches, "sound", "opening_scene")
    return t


def title_reveal() -> st.Timeline:
    """Three holds of 100 ticks: "Presents", then "OPERATION", then "NEPTUNE" with the copyright and the prompt."""
    t = timeline(2 * REVEAL_HOLD + 7.3, "the title in three holds of %d ticks" % REVEAL_HOLD)
    t.track("presents", "visible", [(0, "true"), (REVEAL_HOLD, "false")])
    t.track("operation", "visible", [(0, "false"), (REVEAL_HOLD, "true")])
    t.track("neptune", "visible", [(0, "false"), (2 * REVEAL_HOLD, "true")])
    t.track("copyright", "visible", [(0, "false"), (2 * REVEAL_HOLD, "true")])
    for tick in (0, REVEAL_HOLD, 2 * REVEAL_HOLD):
        t.cue(tick, "sound", "opening_end")
    t.cue(2 * REVEAL_HOLD, "event", "prompt")
    t.marks = {"presents": 0.0, "operation": float(REVEAL_HOLD), "neptune": float(2 * REVEAL_HOLD)}
    return t


# --- the Expert closing ------------------------------------------------------------------------------------------

ARTIFACT = ("alien_artifact_0", "alien_artifact_1")
POD = ("deck_pod_0", "deck_pod_1", "deck_pod_2", "deck_pod_1")


def expert_hoist() -> st.Timeline:
    """The hook comes down, takes the sub and the artifact and hoists them: 4 steps idle, 6 down, 8 up, of 12 ticks."""
    idle, down, up = 4, 6, 8
    steps = idle + down + up
    t = timeline(steps * STEP + STEP, "the hook comes down for the sub and hoists it: %d steps of %d ticks" % (steps, STEP))
    t.track("cable", "visible", [(0, "false"), (idle * STEP, "true")])
    extent = [36 + 12 * min(i, down) - 12 * max(0, i - down) for i in range(down + up + 1)]
    t.track("cable", "extent", [(0, "36")] + [((idle + i) * STEP, str(e)) for i, e in enumerate(extent)])
    t.track("cable", "frame", [((idle + 2) * STEP, "0"), ((idle + down) * STEP, "1"), ((idle + down + 1) * STEP, "2")])
    t.track("sub", "position", [(0, st.v2(184, 212))] + [((idle + down + i) * STEP, st.v2(184, 212 - 12 * i)) for i in range(up)])
    t.track("sub", "pose", seq(STEP, [st.v2i(6, s % 2) for s in range(steps)]))
    t.track("artifact", "position", [(0, st.v2(200, 232))] + [((idle + down + i) * STEP, st.v2(200, 232 - 12 * i)) for i in range(up)])
    t.track("artifact", "frame", seq(STEP, [st.sn(ARTIFACT[s % 2]) for s in range(steps)]))
    return t


def expert_deck() -> st.Timeline:
    """The sub rises into the ship (5 steps), six sailors step to and fro, the box blinks: 20 more steps of 12 ticks."""
    rise, show = 5, 20
    steps = rise + show
    t = timeline(steps * STEP, "the deck shot: %d steps of %d ticks" % (steps, STEP))
    t.track("deck_cable", "frame", [(0, "2")])
    t.track("deck_sub", "position", seq(STEP, [st.v2(184, 279 - 12 * i) for i in range(rise)]))
    t.track("deck_sub", "pose", seq(STEP, [st.v2i(6, i % 2) for i in range(rise)]))
    t.track("deck_artifact", "position", seq(STEP, [st.v2(200, 299 - 12 * i) for i in range(rise)]))
    t.track("deck_artifact", "frame", seq(STEP, [st.sn(ARTIFACT[1 - i % 2]) for i in range(rise)]))
    t.track("deck_cable", "extent", seq(STEP, [str(295 - 12 * i) for i in range(rise)]))
    for member in range(6):
        begin = (rise + member) * STEP
        walking = list(range(steps - rise - member))
        t.track("crew_%d" % member, "visible", [(0, "false"), (begin, "true")])
        t.track("crew_%d" % member, "position",
                [(begin + i * STEP, st.v2(332 + 20 * member + 4 * (i % 6), 214)) for i in walking])
        t.track("crew_%d" % member, "picture", [(begin + i * STEP, st.sn(st.picture(CREW_FIRST_PICTURE + (i % 3)))) for i in walking])
        t.track("crew_%d" % member, "mirror", [(begin, "false"), (begin + 6 * STEP, "true")])
    t.track("pod", "picture", pictures(STEP, [POD[i % 4] for i in range(steps)]))
    t.track("pod", "mirror", flags(STEP, [i % 4 == 3 for i in range(steps)]))
    return t


def expert_wait() -> st.Timeline:
    """The box blinks until a key: a loop of four steps."""
    t = timeline(4 * STEP, "the box blinks until a key, a loop of 4 steps of %d ticks" % STEP, loop=True)
    t.track("pod", "picture", pictures(STEP, [POD[(i + 2) % 4] for i in range(4)]))
    t.track("pod", "mirror", flags(STEP, [i == 1 for i in range(4)]))
    return t


# --- the crew, the story and the Voyager's flight (the news cartoon is dev_ui.py's) ---------------------------------------------------------

WAIT, DOWN, UP, LEFT, RIGHT, END, DRAW = -8, -7, -6, -5, -4, -3, -2        # the ops of `ClosingCrewActor.Op`


def closing_crew() -> str:
    """Six sailors, each a few records of [op, item, mirror, delay]: wait a little, step right and back, bob up and down, stand."""
    scripts = []
    for member in range(6):
        records = [(WAIT, 0, 0, 2 + member), (DRAW, 1, 0, 2), (RIGHT, 2, 0, 1), (RIGHT, 3, 0, 1), (UP, 1, 0, 1), (DOWN, 1, 0, 1),
                   (LEFT, 2, 1, 1), (LEFT, 3, 1, 1), (WAIT, 0, 0, 3), (END, 0, 0, 0)]
        scripts.append([v for record in records for v in record])
    t = tres.Tres("Resource", "ClosingCrewScripts", SCRIPTS + "closing_crew_scripts.gd")
    t.set("first_picture", str(CREW_FIRST_PICTURE))
    t.set("start_x", tres.packed_ints([300 + 40 * m for m in range(6)]))
    t.set("start_y", tres.packed_ints([214] * 6))
    t.set("scripts", tres.array("PackedInt32Array", [tres.packed_ints(s) for s in scripts]))
    return t.render()


def story_script() -> str:
    """Four pages: the stars, the sea, the sub, and the last one that waits for a key. A page holds 120 ticks."""
    pages = [
        ("story_heading_capsule", "story_frame_stars", "story_caption_0", [("story_galaxy_capsule", 100, 80)], False, False),
        ("story_heading_toxins", "story_frame_pacific", "story_caption_1", [], True, False),
        ("story_heading_submarine", "story_frame_submarine", "story_caption_2", [], False, False),
        ("story_heading_oceans", "story_frame_stars", "story_caption_3", [("story_earth_globe", 200, 70)], False, True),
    ]
    t = tres.Tres("Resource", "StoryScript", SCRIPTS + "story_script.gd")
    page_id = t.ext_id("Script", SCRIPTS + "story_page.gd")
    refs = []
    for heading, frame, caption, extras, ring, last in pages:
        props = [("heading", st.sn(heading)), ("frame", st.sn(frame)), ("caption", st.sn(caption))]
        if extras:
            props.append(("extra_pictures", tres.array("StringName", (st.sn(e[0]) for e in extras))))
            props.append(("extra_positions", "PackedVector2Array(%s)" % ", ".join("%d, %d" % (e[1], e[2]) for e in extras)))
        if ring:
            props.append(("ring", "true"))
        if last:
            props.append(("last", "true"))
        refs.append(t.sub("Resource", props, script=SCRIPTS + "story_page.gd", prefix="Page"))
    t.set("pages", tres.array('ExtResource("%s")' % page_id, refs))
    t.set("background", st.sn("story_background"))
    t.set("heading_position", st.v2(120, 10))
    t.set("frame_position", st.v2(0, 50))
    t.set("caption_position", st.v2(40, 300))
    t.set("ring_pictures", tres.array("StringName", (st.sn("story_ring_%d" % i) for i in range(4))))
    t.set("ring_position", st.v2(240, 220))
    t.set("ring_picture_ticks", "10")
    t.set("minimum_page_ticks", "120")
    t.set("last_page_ticks", "300")
    t.set("caption_delay_ticks", "10")
    t.set("provenance", tres.s("Dev pack: four story pages of our own, each held at least 120 ticks, the last 300 (tools/dev_pack/dev_story.py)."))
    return t.render()


def voyager_closing_script() -> str:
    """The sub rises 6 steps, turns (every cell goes down to 2), changes into a helicopter, surges and flies off to the left."""
    t = tres.Tres("Resource", "VoyagerClosingScript", SCRIPTS + "voyager_closing_script.gd")
    t.set("step_ticks", "4")
    t.set("rise_steps", "6")
    t.set("rise_pixels", "6")
    t.set("turn_table", tres.packed_ints([1, 2, 2, 2, 3, 4, 5, 6, 7]))
    t.set("turn_done_cell", "2")
    t.set("change_pictures", tres.array("StringName", (st.sn(n) for n in ("heli_change_0", "heli_change_1", "heli_change_2"))))
    t.set("change_picture_steps", "3")
    t.set("flash_sound", st.sn("closing_flash"))
    t.set("surge_sound", st.sn("closing_surge"))
    t.set("surge_steps", "5")
    t.set("surge_pixels", "10")
    t.set("fly_pixels", "20")
    t.set("fly_until_x", "-100")
    t.set("body_picture", st.sn("heli_body"))
    t.set("rotor_pictures", tres.array("StringName", (st.sn(n) for n in ("heli_rotor_0", "heli_rotor_1"))))
    t.set("margin_ticks", "8")
    t.set("provenance", tres.s("Dev pack: a short flight of our own, steps of 4 ticks (tools/dev_pack/dev_story.py)."))
    return t.render()


def write_all() -> int:
    story = DEV / "data" / "story"
    for name, build in (("news_ambient", news_ambient), ("title_ship", title_ship), ("title_reveal", title_reveal),
                        ("expert_hoist", expert_hoist), ("expert_deck", expert_deck), ("expert_wait", expert_wait)):
        write_text(story / (name + ".tres"), build().render())
    write_text(story / "closing_crew.tres", closing_crew())
    write_text(story / "story_script.tres", story_script())
    write_text(story / "voyager_closing_script.tres", voyager_closing_script())
    return 9
