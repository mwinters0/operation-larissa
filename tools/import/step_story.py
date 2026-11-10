"""Step 'story': the cutscenes' choreography as data (godot/data/story/*.tres).

The choreography of every cutscene of the opening and the closings is data, not `Animation` tracks built in code with
node paths and textures. Each timeline becomes a `CutsceneTimeline` Resource: a length, tracks (an ACTOR NAME, a property word,
moments in ticks of the original's 73 Hz timer, values with picture and sound NAMES of the registry) and cues (sounds,
events). A view plays it by building an `AnimationPlayer` animation at run time (`src/story/cutscene.gd`), so the numbers
belong to the original and the nodes belong to the view.

    news_cartoon        the capsule's trail, the bulletins typed, the crew, the alarm lights, the end   (docs/data/opening.json)
    news_ambient        the alarm lights' four states and the pulsing ring, a loop of 64 redraws          (the same)
    title_ship          the ship scene, 163 frames of 12 ticks                                           (title_scene.frames)
    title_reveal        "Presents" / "OPERATION" / "NEPTUNE" with their sounds and the prompt            (reveal_and_prompt)
    expert_hoist        the Expert closing: the sub turns, the hook comes down, the cable hoists         (CLOSING.C, constants below)
    expert_deck         the deck shot: the sub rises into the ship, six sailors act, the box blinks      (+ expert_closing.json)
    expert_wait         the box blinks until a key
    story_script        the nine pages of the opening story and how long each one holds                  (OPENING.C, constants below)
    voyager_closing_script  the Voyager closing's loop counts; the timeline is run for the sub's place at the finale

Provenance (ground rule "Provenance is never lost"): every number is the original's, from docs/data/*.json or from the
constants below, which were read from the decompiled loops and carry their function and address. The few numbers that are
OURS (a margin after the last step, one millisecond that keeps a ramp from sliding back) are named `*_TICKS` constants
with a comment saying so, and each file's `provenance` text lists them. Hand-made timelines (the fade of a story page, the
flicker of the console lights) are not here: they are made in code by the views, because they have no original behind them.

Names: pictures and sounds are written as the registry's names (godot/names/original.json), found from the original's
numbers here, so `rename_name.py --import` rewrites them when a name changes.
"""
from __future__ import annotations

import itertools
import json
import math
from collections.abc import Sequence
from functools import cache
from pathlib import Path

import foe_names
import step_problems
import tres
from common import PACK_DATA, PROJECT_DATA, DOCS_DATA, EXTRACTED, load_json, out_text

SCRIPTS = "res://src/resources/"
STORY = PROJECT_DATA / "story"                  # the cutscenes' timelines: committed, no picture or text of the game in them
LEGACY_STORY = PACK_DATA / "story"               # the news cartoon's: it holds the game's own bulletin texts, so it is the legacy pack's
LEGACY_TIMELINES = {"news_cartoon"}
TIMELINE_NAMES = {"news_cartoon", "news_ambient", "title_ship", "title_reveal", "expert_hoist", "expert_deck", "expert_wait"}      # `timelines()`
TICKS_PER_SECOND = 73

# --- our own numbers -----------------------------------------------------------------------------------------------
# (nothing in the original: they exist only to make the animation player behave)
## The ramp of the typing holds its last value until this long before the next text starts (one millisecond), so that the
## player does not slide back from "all typed" to "nothing" over the whole reading time.
HOLD_EPSILON_TICKS = 0.073
## The reveal animation runs this long (0.1 s) past its last picture; nothing happens at its end.
REVEAL_TAIL_TICKS = 7.3
## The Voyager flight animation runs this long (0.2 s) past its last step.
VOYAGER_MARGIN_TICKS = 14.6


# --- names -------------------------------------------------------------------------------------------------------------

def picture(number: int) -> str:
    """The `ui_picture` name of the picture with the original's number `number` (the made-up name when nobody named it)."""
    return foe_names.original().real_name("ui_picture", number) or foe_names.fallback_name("ui_picture", number)


def sound(number: int) -> str:
    return foe_names.original().real_name("sound", number) or foe_names.fallback_name("sound", number)


@cache
def _text_names() -> dict[int, str]:
    """String id -> name (the `text` kind is not one the importer's Registry reads: it only ever needed the picture and sound kinds)."""
    return {number: name for name, number in json.loads(foe_names.STORE.read_text())["names"]["text"].items()}


def text_name(number: int) -> str:
    return _text_names().get(number, "text_%d" % number)


def frame_name(slot: int, zone: int) -> str:
    """The name of creature picture `slot` of `zone`."""
    return foe_names.original().real_name("frame", slot, zone) or foe_names.fallback_name("frame", slot)


# --- writing -------------------------------------------------------------------------------------------------------------

def num(x: float) -> str:
    return str(int(x)) if float(x).is_integer() else tres.f(x)


def sn(name: str) -> str:
    """A StringName literal."""
    return "&" + tres.s(name)


def v2(x: float, y: float) -> str:
    return "Vector2(%s, %s)" % (num(x), num(y))


def v2i(x: int, y: int) -> str:
    return "Vector2i(%d, %d)" % (x, y)


def rect(x: float, y: float, w: float, h: float) -> str:
    return "Rect2(%s, %s, %s, %s)" % (num(x), num(y), num(w), num(h))


def boolean(b: bool) -> str:
    return "true" if b else "false"


def floats(values) -> str:
    return "PackedFloat64Array(%s)" % ", ".join(num(v) for v in values)


class Timeline:
    """A CutsceneTimeline being collected: tracks of (actor, property, [(tick, literal)], smooth), cues, marks."""

    def __init__(self, length: float, provenance: str, loop: bool = False):
        self.length = length
        self.loop = loop
        self.provenance = provenance
        self.tracks: list[tuple[str, str, Sequence[tuple[float, str]], bool]] = []
        self.cues: list[tuple[float, str, str]] = []
        self.marks: dict[str, float] = {}

    def track(self, actor: str, prop: str, keys: Sequence[tuple[float, str]], smooth: bool = False) -> None:
        assert keys and all(a[0] <= b[0] for a, b in itertools.pairwise(keys)), (actor, prop)
        assert keys[-1][0] <= self.length + 1e-9, (actor, prop, keys[-1][0], self.length)
        self.tracks.append((actor, prop, keys, smooth))

    def cue(self, tick: float, kind: str, name: str) -> None:
        assert tick <= self.length + 1e-9
        self.cues.append((tick, kind, name))

    def key_times(self) -> list[float]:
        found = {t for _a, _p, keys, _s in self.tracks for t, _v in keys} | {c[0] for c in self.cues}
        return sorted(found)

    def render(self) -> str:
        t = tres.Tres("Resource", "CutsceneTimeline", SCRIPTS + "cutscene_timeline.gd")
        track_id = t.ext_id("Script", SCRIPTS + "cutscene_track.gd")
        cue_id = t.ext_id("Script", SCRIPTS + "cutscene_cue.gd")
        t.set("length", num(self.length))
        if self.loop:
            t.set("loop", "true")
        refs = []
        for actor, prop, keys, smooth in self.tracks:
            props = [("actor", sn(actor)), ("property", sn(prop)), ("times", floats(k[0] for k in keys)),
                     ("values", "[%s]" % ", ".join(k[1] for k in keys))]
            if smooth:
                props.append(("smooth", "true"))
            refs.append(t.sub("Resource", props, script=SCRIPTS + "cutscene_track.gd", prefix="Track"))
        t.set("tracks", tres.array('ExtResource("%s")' % track_id, refs))
        if self.cues:
            cue_refs = [t.sub("Resource", [("tick", num(tick)), ("kind", sn(kind)), ("cue_name", sn(name))],
                              script=SCRIPTS + "cutscene_cue.gd", prefix="Cue") for tick, kind, name in self.cues]
            t.set("cues", tres.array('ExtResource("%s")' % cue_id, cue_refs))
        if self.marks:
            t.set("marks", tres.dictionary((sn(k), tres.f(v)) for k, v in self.marks.items()))
        t.set("provenance", tres.s(self.provenance))
        return t.render()


def points() -> list[tuple[int, int]]:
    return [tuple(p) for p in load_json(DOCS_DATA / "opening.json")["points"]]


# --- the news cartoon -------------------------------------------------------------------------------------------------------

def godot_text_length(text: str) -> int:
    """How many characters the teletype types: the text as `NewsCartoon.bulletin()` shows it (`strip_edges`, `\\r` -> `\\n`)."""
    return len(text.strip().replace("\r", "\n"))


def bulletin_texts() -> dict[int, str]:
    """String id -> the original's text (read from YOUR copy of the game, like the problem texts)."""
    entries = load_json(EXTRACTED / "data" / "NEP_text.json")
    return {e["id"]: step_problems.clean(e["text"]) for e in entries if e.get("kind") == "text"}


def crew_frame(member: dict, call: int) -> tuple[int, int, int] | None:
    """(picture number, mirror, x) of one crew member in redraw `call` (1-based), None while he is not drawn yet.
    The script repeats; a walking member also moves on by the sum of `dx` of a whole cycle each time round."""
    index = call - member["first_call"]
    if index < 0:
        return None
    cycle = member["pictures"]
    cycle_total = sum(entry[2] for entry in cycle)
    x = member["x0"] + (index // len(cycle)) * cycle_total
    for k in range(index % len(cycle) + 1):
        x += cycle[k][2]
    picture_number, mirror, _dx = cycle[index % len(cycle)]
    return picture_number, mirror, x


def build_news(texts: dict[int, str]) -> Timeline:
    """The one-time part of the cartoon: the capsule's trail, the ring, the six bulletins, the crew, the alarm gates, the end."""
    data = load_json(DOCS_DATA / "opening.json")
    news = data["news_cartoon"]
    step = news["redraw_ticks"]
    pts = data["points"]
    reading = 25 * step                                  # "7 passes of 25 redraws": the box is empty for one pass, each bulletin is read for one
    per_character = news["typing"]["ticks_per_character"]

    # the bulletins: the box is empty for a pass, then each one is typed and read
    text_keys = [(0, sn(""))]
    reveal_keys = [(0, "0.0")]
    at = reading
    for bulletin in news["bulletins"]:
        typing = godot_text_length(texts[bulletin["id"]]) * per_character
        assert abs(typing - bulletin["typing_ticks"]) <= per_character, (bulletin, typing)     # the JSON counts the blank at the edge too
        text_keys.append((at, sn(text_name(bulletin["id"]))))
        reveal_keys.append((at, "0.0"))
        reveal_keys.append((at + typing, "1.0"))
        at += typing + reading
        reveal_keys.append((at - HOLD_EPSILON_TICKS, "1.0"))
    trail = news["trail_and_ring"]
    ring_at = (trail["ring_first_call"] - 1) * step
    assert ring_at == trail["ring_first_tick"]
    length = max(at, ring_at + step)
    tl = Timeline(length, PROVENANCE_NEWS)

    tl.track("teletype", "text", text_keys)
    tl.track("teletype", "reveal", reveal_keys, smooth=True)
    # the capsule's trail: one dot per 11 redraws, then the ring
    for i, dot in enumerate(trail["dots"]):
        assert dot["point"] == data["point_names"]["capsule_trail"][0] + i
        tl.track("dot_%02d" % i, "visible", [(0, "false"), ((dot["call"] - 1) * step, "true")])
    tl.track("ring", "visible", [(0, "false"), (ring_at, "true")])
    # the crew: in every redraw each member shows the picture his script says
    calls = math.ceil(length / step)
    for m, member in enumerate(news["crew"]["members"]):
        assert pts[data["point_names"]["crew"][m]][1] == member["y"]
        pictures, mirrors, positions, visibles = [], [], [], []
        for call in range(member["first_call"], calls + 1):
            t = (call - 1) * step
            frame = crew_frame(member, call)
            assert frame is not None
            pictures.append((t, sn(picture(frame[0]))))
            mirrors.append((t, boolean(frame[1] == 1)))
            positions.append((t, v2(frame[2], member["y"])))
            visibles.append((t, boolean(frame[2] < 640)))
        tl.track("crew_%d" % m, "picture", pictures)
        tl.track("crew_%d" % m, "mirror", mirrors)
        if member["dx_per_cycle"] != 0:                  # only the man on the left walks, and he is not there for the first 30 s
            tl.track("crew_%d" % m, "position", positions)
            tl.track("crew_%d" % m, "visible", [(0, "false")] + visibles)
    # the alarm lights are dark until their call: the centre one from call 37, the outer two from call 234
    gate = news["alarm_lights"]["gate_call"]
    for i, call in enumerate((gate["outer"], gate["centre"], gate["outer"])):
        tl.track("alarm_%d" % i, "visible", [(0, "false"), ((call - 1) * step, "true")])
    tl.cue(length, "event", "end")
    return tl


def build_news_ambient() -> Timeline:
    """What repeats: the alarm lights run through four states, each light one redraw ahead of the last, and the ring at the
    crash site shows one picture per redraw. (The flicker of the other lights is random in the original; it is made in code.)"""
    data = load_json(DOCS_DATA / "opening.json")
    news = data["news_cartoon"]
    step = news["redraw_ticks"]
    steps = 64                                           # a multiple of 4, the alarm lights' cycle: long enough not to look like a loop
    tl = Timeline(steps * step, PROVENANCE_AMBIENT, loop=True)
    alarms = news["alarm_lights"]
    states = alarms["state_to_picture"]
    for i, side in enumerate(("left", "centre", "right")):
        start = alarms["start_state"][side]
        order = [(start + s) % 4 for s in range(steps)]
        tl.track("alarm_%d" % i, "picture", [(s * step, sn(picture(states[str(order[s])]["picture"]))) for s in range(steps)])
        tl.track("alarm_%d" % i, "mirror", [(s * step, boolean(states[str(order[s])]["mirror"] == 1)) for s in range(steps)])
    ring = news["trail_and_ring"]["ring_pictures"]
    assert news["trail_and_ring"]["ring_ticks_per_picture"] == step
    tl.track("ring", "picture", [(s * step, sn(picture(ring[s % len(ring)]))) for s in range(steps)])
    return tl


PROVENANCE_NEWS = (
    "Original: OpeningSequence 0x42b16b, the news cartoon (docs/data/opening.json, news_cartoon): redraw every 10 ticks; "
    "the trail's dots and the ring at their calls; the bulletins typed at 3 ticks a character, each read for 25 redraws; "
    "the crew's five scripts; the alarm lights' gates. The typing length counts the characters the teletype shows (the "
    "text stripped at its edges). Ours: the 0.073 tick hold that keeps the typing ramp at 1 while the bulletin is read.")
PROVENANCE_AMBIENT = (
    "Original: the alarm lights' four states and the pulsing ring, one step per 10 tick redraw (docs/data/opening.json). "
    "Ours: the loop length of 64 redraws.")


# --- the title scene ---------------------------------------------------------------------------------------------------------

SPRAY_IDLE_PICTURE = 1035              # shown (hidden) by the bow spray in frames without spray: `spray_1`
SPLASH_IDLE_PICTURE = 1034             # the same for the splash halves: `spray_0`, the first of the five


def build_title_ship() -> Timeline:
    data = load_json(DOCS_DATA / "opening.json")
    title = data["title_scene"]
    pts = data["points"]
    names = data["point_names"]
    step = title["redraw_ticks"]
    frames = title["frames"]
    assert len(frames) == 163 and [f["redraw"] for f in frames] == list(range(163))
    hull_at = pts[names["ship_hull"]]
    sub_dx = pts[names["ship_sub"]][0] - hull_at[0]
    spray_offset = (pts[names["ship_bow_spray"]][0] - hull_at[0], pts[names["ship_bow_spray"]][1] - hull_at[1])
    size_x = title["sub"]["size"][0]
    tl = Timeline(len(frames) * step, PROVENANCE_TITLE_SHIP)
    keys: dict[str, list[tuple[float, str]]] = {}

    def put(name: str, t: float, value: str) -> None:
        keys.setdefault(name, []).append((t, value))

    for f in frames:
        t = f["redraw"] * step
        hull = f["hull"]
        put("ship position", t, v2(hull["x"], hull["y"]))
        put("radar picture", t, sn(picture(f["radar"]["picture"])))
        put("radar mirror", t, boolean(f["radar"]["mirror"] == 1))
        put("hook picture", t, sn(picture(f["hook"]["picture"])))
        sub = f["sub"]
        assert sub["x"] == hull["x"] + sub_dx
        put("mini_sub position", t, v2(sub["x"], sub["y"]))
        put("mini_sub clip", t, rect(0, 0, size_x, sub["visible_rows"]))
        put("mini_sub visible", t, boolean(sub["visible_rows"] > 0))
        spray = f["spray"]
        spray_xy = (hull["x"] + spray_offset[0], hull["y"] + spray_offset[1])
        if spray:
            assert (spray["x"], spray["y"]) == spray_xy
        put("spray position", t, v2(*spray_xy))
        put("spray visible", t, boolean(spray is not None))
        put("spray picture", t, sn(picture(spray["picture"] if spray else SPRAY_IDLE_PICTURE)))
        splash = f["splash"]
        for side in ("splash_left", "splash_right"):
            put(side + " picture", t, sn(picture(splash["picture"] if splash else SPLASH_IDLE_PICTURE)))
            put(side + " visible", t, boolean(splash is not None))
    for name, track_keys in keys.items():
        actor, prop = name.split(" ")
        tl.track(actor, prop, track_keys)
    splash = title["splash"]
    tl.cue(splash["sound_redraw"] * step, "sound", sound(splash["sound"]))
    return tl


PROVENANCE_TITLE_SHIP = (
    "Original: the ship scene of OpeningSequence 0x42b16b (docs/data/opening.json, title_scene.frames): frame r is drawn at "
    "r x 12 ticks and every part is where the original drew it in that frame; the splash sound plays in frame 73. "
    "Hidden parts keep a picture and a place (the spray and splash show their first picture, the spray follows the hull).")


def build_title_reveal() -> Timeline:
    data = load_json(DOCS_DATA / "opening.json")["reveal_and_prompt"]
    hold = data["hold_ticks"]
    steps = data["steps"]
    assert [s["t_ticks"] for s in steps] == [0, hold, hold, 2 * hold] and [s.get("sfx") for s in steps] == [51, None, 51, 51]
    wipe = sound(data["steps"][0]["sfx"])
    tl = Timeline(2 * hold + REVEAL_TAIL_TICKS, PROVENANCE_REVEAL)
    tl.track("presents", "visible", [(0, "true"), (hold, "false")])
    tl.track("operation", "visible", [(0, "false"), (hold, "true")])
    tl.track("neptune", "visible", [(0, "false"), (2 * hold, "true")])
    tl.track("copyright", "visible", [(0, "false"), (2 * hold, "true")])
    for t in (0, hold, 2 * hold):
        tl.cue(t, "sound", wipe)
    tl.cue(2 * hold, "event", "prompt")
    tl.marks = {"presents": 0, "operation": hold, "neptune": 2 * hold}
    return tl


PROVENANCE_REVEAL = (
    "Original: the three title pictures of OpeningSequence (docs/data/opening.json, reveal_and_prompt): each appears at once "
    "with a sound and stays 292 ticks; at the third one the prompt (Start / Intro) begins. Ours: the 7.3 tick tail.")


# --- the Expert closing ------------------------------------------------------------------------------------------------------------
# Numbers read from ExpertClosingSequence 0x41c650 (CLOSING.C); one step is 18 ticks, every step draws the sub and the artifact.

EXPERT_STEP = 18
SUB_AT = (184, 212)                          # SubX / SubY of the sub
START_CELL = 4                               # the sub faces the viewer when the closing starts
TURN_TABLE = [3, 3, 3, 4, 5, 6, 6, 6, 6]     # ExpertClosingTurnTable (0x441582): the next cell while the sub turns
TURN_DONE_CELL = 6                           # facing right
IDLE_STEPS = 20
HOOK_START_BOTTOM = 0x24                     # ExpertClosingCableBottom at the start
HOOK_STEP = 12
DESCENT_STEPS = 16
HOOK_OPEN_STEPS = 10                         # hook picture 0 for the first 10 steps of the descent, 1 for the next 5, 2 from then on
HOOK_CLOSING_STEPS = 5
ASCENT_STEPS = 17                            # 12 px per step until the cable's bottom is at or above 0x20
ARTIFACT_X = 200
ARTIFACT_START_Y = 0xE8                      # ExpertClosingArtifactY
ARTIFACT_ZONE = 6                            # ExpertClosingDrawArtifact draws items 0 / 1 of the Expert finale's creature bundle
ARTIFACT_SLOTS = (35, 36)                    # ... which are slots 35 and 36 of that zone's creature set
DECK_SUB_Y = 0x123                           # the deck shot: SubY (SubX stays 184)
DECK_ARTIFACT_Y = 0x137
DECK_CABLE_BOTTOM = 0x133
DECK_RISE_STEPS = 6                          # the sub, the artifact and the cable rise 12 px per step ...
DECK_CREW_STEPS = 140                        # ... then the sailors act for 140 steps
CREW_COUNT = 6
POD_PICTURES = (2015, 2016, 2017, 2016)      # ExpertClosingDrawPod (0x41cdba): items 3, 4, 5, 4 of bundle 0x1d1; the last one mirrored
HOOK_PICTURE_INDEX = (0, 1, 2)               # open, closing, closed (the cable's `hook_frame`)


class Steps:
    """Keys per (actor, property) collected step by step, writing a key only when the value changes (the player holds a value
    until the next key, so the step loops can say "at this step the value is X" for every step)."""

    def __init__(self) -> None:
        self.keys: dict[tuple[str, str], list[tuple[float, str]]] = {}

    def put(self, actor: str, prop: str, t: float, value: str) -> None:
        keys = self.keys.setdefault((actor, prop), [])
        if not keys or keys[-1][1] != value:
            keys.append((t, value))

    def timeline(self, length: float, provenance: str, loop: bool = False) -> Timeline:
        tl = Timeline(length, provenance, loop)
        for (actor, prop), keys in self.keys.items():
            tl.track(actor, prop, keys)
        return tl


def hook_frame_at_descent(d: int) -> int:
    """Hook picture during descent step `d` (1-based): open, closing, then closed."""
    if d <= HOOK_OPEN_STEPS:
        return 0
    return 1 if d <= HOOK_OPEN_STEPS + HOOK_CLOSING_STEPS else 2


def turn_steps() -> int:
    cell, steps = START_CELL, 0
    while cell != TURN_DONE_CELL:
        cell = TURN_TABLE[cell]
        steps += 1
    return steps


def hoist_steps() -> int:
    return turn_steps() + IDLE_STEPS + DESCENT_STEPS + ASCENT_STEPS


def artifact(toggle: int) -> str:
    return sn(frame_name(ARTIFACT_SLOTS[toggle], ARTIFACT_ZONE))


def build_expert_hoist() -> Timeline:
    """The sub turns to face right and idles, the hook comes down and closes on it, the cable pulls it up with the artifact."""
    steps = Steps()
    turn = turn_steps()
    cell = START_CELL
    sub_y, artifact_y, bottom = SUB_AT[1], ARTIFACT_START_Y, HOOK_START_BOTTOM
    steps.put("cable", "visible", 0, "false")
    for i in range(hoist_steps()):
        t = i * EXPERT_STEP
        toggle = i & 1
        if i < turn:
            cell = TURN_TABLE[cell]
        d = i - turn - IDLE_STEPS + 1                    # 1 .. 16 while the hook comes down
        a = d - DESCENT_STEPS                            # 1 .. 17 while it goes up
        if 1 <= d <= DESCENT_STEPS:
            bottom = HOOK_START_BOTTOM + HOOK_STEP * d
            steps.put("cable", "visible", t, "true")
            steps.put("cable", "frame", t, str(hook_frame_at_descent(d)))
        elif a >= 1:
            bottom -= HOOK_STEP
            sub_y -= HOOK_STEP
            artifact_y -= HOOK_STEP
        steps.put("cable", "extent", t, str(bottom))
        steps.put("sub", "position", t, v2(SUB_AT[0], sub_y))
        steps.put("sub", "pose", t, v2i(cell, toggle))
        steps.put("artifact", "position", t, v2(ARTIFACT_X, artifact_y))
        steps.put("artifact", "frame", t, artifact(toggle))
    return steps.timeline(hoist_steps() * EXPERT_STEP, PROVENANCE_HOIST)


class CrewActor:
    """One sailor's program (the Python twin of ClosingCrewActor, src/story/closing_crew_actor.gd; ExpertClosingCrewStep 0x41ceb7).
    tests/test_expert_timelines.gd checks that this and the GDScript give the same drawing in every step."""

    WAIT, DOWN, UP, LEFT, RIGHT, END, DRAW = -8, -7, -6, -5, -4, -3, -2
    STEP_X, STEP_Y = 4, 10

    def __init__(self, data: dict, index: int):
        self.program = data["scripts"][index]            # records [op, item, mirror, delay]
        self.first_picture = data["first_picture"]
        self.x, self.y = data["start_positions"][index]
        self.visible = False
        self.picture = 0
        self.mirrored = False
        self.record = -1
        self.delay = 0

    def step(self) -> None:
        previous = max(self.record, 0)
        if self.delay < 1:
            self.record += 1
        op, item, mirror, delay = self.program[self.record]
        self.visible = False
        if op == self.WAIT:
            if self.delay == 0:
                self.delay = delay
        elif op in (self.LEFT, self.RIGHT, self.UP, self.DOWN, self.DRAW):
            self.x += {self.LEFT: -self.STEP_X, self.RIGHT: self.STEP_X}.get(op, 0)
            self.y += {self.UP: -self.STEP_Y, self.DOWN: self.STEP_Y}.get(op, 0)
            self._draw(op, item, mirror)
            if self.delay == 0:
                self.delay = delay
        elif op == self.END:
            _op, item, mirror, _delay = self.program[previous]
            self._draw(op, item, mirror)
            self.record = -1
            self.delay = 0
        if self.delay > 0:
            self.delay -= 1

    def _draw(self, _op: int, item: int, mirror: int) -> None:
        self.visible = True
        self.picture = self.first_picture + item
        self.mirrored = mirror != 0


def pod(steps: Steps, t: float, step: int) -> None:
    """The control box at the right edge shows phase `step % 4` of its pictures; the fourth is mirrored."""
    phase = step % len(POD_PICTURES)
    steps.put("pod", "picture", t, sn(picture(POD_PICTURES[phase])))
    steps.put("pod", "mirror", t, boolean(phase == len(POD_PICTURES) - 1))


def build_expert_deck() -> Timeline:
    """The ship, the sea and the sub on the cable rising into the picture while the sailors act (6 + 140 steps). The sub's and
    the artifact's pictures go on toggling where the hoist left them (it drew `hoist_steps()` times)."""
    crew_data = load_json(DOCS_DATA / "expert_closing.json")
    actors = [CrewActor(crew_data, i) for i in range(CREW_COUNT)]
    steps = Steps()
    sub_y, artifact_y, bottom = DECK_SUB_Y, DECK_ARTIFACT_Y, DECK_CABLE_BOTTOM
    total = DECK_RISE_STEPS + DECK_CREW_STEPS
    steps.put("deck_cable", "frame", 0, "2")
    for i in range(total):
        t = i * EXPERT_STEP
        if i < DECK_RISE_STEPS:                          # the sub, the artifact and the cable rise
            toggle = (hoist_steps() + i) & 1
            sub_y -= HOOK_STEP
            artifact_y -= HOOK_STEP
            bottom -= HOOK_STEP
            steps.put("deck_sub", "position", t, v2(SUB_AT[0], sub_y))
            steps.put("deck_sub", "pose", t, v2i(TURN_DONE_CELL, toggle))
            steps.put("deck_artifact", "position", t, v2(ARTIFACT_X, artifact_y))
            steps.put("deck_artifact", "frame", t, artifact(toggle))
            steps.put("deck_cable", "extent", t, str(bottom))
        for n, actor in enumerate(actors):
            actor.step()
            name = "crew_%d" % n
            steps.put(name, "visible", t, boolean(actor.visible))
            if actor.visible:
                steps.put(name, "position", t, v2(actor.x, actor.y))
                steps.put(name, "picture", t, sn(picture(actor.picture)))
                steps.put(name, "mirror", t, boolean(actor.mirrored))
        pod(steps, t, i)
    return steps.timeline(total * EXPERT_STEP, PROVENANCE_DECK)


def build_expert_wait() -> Timeline:
    """The last stage: only the box blinks, over and over, until a key is pressed. The phases go on after the deck's last step."""
    steps = Steps()
    for i in range(len(POD_PICTURES)):
        pod(steps, i * EXPERT_STEP, DECK_RISE_STEPS + DECK_CREW_STEPS + i)
    return steps.timeline(len(POD_PICTURES) * EXPERT_STEP, PROVENANCE_WAIT, loop=True)


PROVENANCE_HOIST = (
    "Original: ExpertClosingSequence 0x41c650 (CLOSING.C), the first stage: the sub turns (ExpertClosingTurnTable), idles 20 "
    "steps, the hook comes down 16 steps of 12 px and closes, then the cable pulls the sub and the artifact up 17 steps. One "
    "step is 18 ticks; the pictures of the sub (cell, propeller phase) and the artifact toggle every step. Constants are in "
    "tools/import/step_story.py with the function they were read from.")
PROVENANCE_DECK = (
    "Original: the deck shot of ExpertClosingSequence: the sub rises into the ship for 6 steps, then six sailors walk and wave for "
    "140 steps (ExpertClosingCrewStep 0x41ceb7 run on docs/data/expert_closing.json) while the control box at the right edge "
    "blinks (ExpertClosingDrawPod 0x41cdba). Nothing of it is ours.")
PROVENANCE_WAIT = (
    "Original: the last stage of ExpertClosingSequence: only the control box blinks, one phase per 18 tick step, until a key or "
    "a click. The phases go on from where the deck shot left them.")


# --- the opening story -------------------------------------------------------------------------------------------------------------
# OpeningStoryPages 0x42a9f1 (OPENING.C): per page the heading, the frame, extra pictures [picture, x, y], whether the radar ring blinks.

STORY_BACKGROUND = 2065
HEADING_AT = (168, 6)
FRAME_AT = (0, 38)
CAPTION_AT = (52, 316)
# GALAXY SPACE CAPSULE, WORLD'S OCEANS, DANGEROUS TOXINS, NEPTUNE SUBMARINE
HEADINGS = (2072, 2073, 2074, 2075)
RING_PICTURES = (2076, 2077, 2078, 2079)
RING_AT = (184, 234)
RING_PICTURE_TICKS = 7
FRAME_STARS, FRAME_PACIFIC, FRAME_SUBMARINE = 2070, 2069, 2071
CAPTION_FIRST = 2056                                 # the nine pages' words are the bitmaps 2056-2064
PAGES = (
    {"heading": 0, "frame": FRAME_STARS, "extras": [(2066, 132, 92)]},
    {"heading": 0, "frame": FRAME_STARS, "extras": [(2066, 132, 92)]},
    {"heading": 0, "frame": FRAME_STARS, "extras": [(2066, 132, 92)]},
    {"heading": 2, "frame": FRAME_PACIFIC, "extras": []},
    {"heading": 2, "frame": FRAME_PACIFIC, "extras": [], "ring": True},
    {"heading": 3, "frame": FRAME_SUBMARINE, "extras": []},
    {"heading": 3, "frame": FRAME_SUBMARINE, "extras": []},
    {"heading": 3, "frame": FRAME_SUBMARINE, "extras": []},
    {"heading": 1, "frame": FRAME_STARS, "extras": [(2067, 208, 60), (2068, 228, 60), (2055, 224, 60)], "last": True},
)
MIN_PAGE_TICKS = 365                                 # a page lasts as long as its speech and at least 5 s
LAST_PAGE_TICKS = 3285                               # the last page waits up to 45 s for a key or a click
CAPTION_DELAY_TICKS = 15                             # the caption is drawn 15 ticks after the page


def build_story_script() -> str:
    t = tres.Tres("Resource", "StoryScript", SCRIPTS + "story_script.gd")
    page_id = t.ext_id("Script", SCRIPTS + "story_page.gd")
    refs = []
    for index, page in enumerate(PAGES):
        props = [("heading", sn(picture(HEADINGS[page["heading"]]))), ("frame", sn(picture(page["frame"]))),
                 ("caption", sn(picture(CAPTION_FIRST + index)))]
        if page["extras"]:
            props.append(("extra_pictures", tres.array("StringName", (sn(picture(e[0])) for e in page["extras"]))))
            props.append(("extra_positions", "PackedVector2Array(%s)" % ", ".join("%d, %d" % (e[1], e[2]) for e in page["extras"])))
        if page.get("ring"):
            props.append(("ring", "true"))
        if page.get("last"):
            props.append(("last", "true"))
        refs.append(t.sub("Resource", props, script=SCRIPTS + "story_page.gd", prefix="Page"))
    t.set("pages", tres.array('ExtResource("%s")' % page_id, refs))
    t.set("background", sn(picture(STORY_BACKGROUND)))
    t.set("heading_position", v2(*HEADING_AT))
    t.set("frame_position", v2(*FRAME_AT))
    t.set("caption_position", v2(*CAPTION_AT))
    t.set("ring_pictures", tres.array("StringName", (sn(picture(p)) for p in RING_PICTURES)))
    t.set("ring_position", v2(*RING_AT))
    t.set("ring_picture_ticks", num(RING_PICTURE_TICKS))
    t.set("minimum_page_ticks", num(MIN_PAGE_TICKS))
    t.set("last_page_ticks", num(LAST_PAGE_TICKS))
    t.set("caption_delay_ticks", num(CAPTION_DELAY_TICKS))
    t.set("provenance", tres.s(
        "Original: OpeningStoryPages 0x42a9f1 (OPENING.C) and the page player PlayStoryPageSpeech 0x42a817: nine pages of "
        "pictures, a page lasts as long as its speech and at least 365 ticks, the last waits up to 3285 ticks; the words are "
        "the bitmaps 2056-2064. Constants are in tools/import/step_story.py."))
    return t.render()


# --- the Voyager closing -------------------------------------------------------------------------------------------------------------
# VoyagerClosingSequence (CLOSING.C, called from DoAction in sector 30): in 6 tick steps the sub rises, turns, changes into a
# helicopter (the change pictures 1995-1997, then the body 1998 and the rotor 1999 / 2000), surges up, flies off to the left.

VOYAGER_STEP = 6
VOYAGER_RISE_STEPS = 18
VOYAGER_RISE_PIXELS = 4
VOYAGER_TURN_TABLE = [2, 2, 2, 2, 3, 4, 5, 5, 5]     # VoyagerClosingTurnTable (0x441579)
VOYAGER_TURN_DONE_CELL = 2
VOYAGER_CHANGE_PICTURES = (1995, 1996, 1997)
VOYAGER_CHANGE_PICTURE_STEPS = 2                     # 12 ticks each
VOYAGER_FLASH_SOUND = 44                             # 0x2c
VOYAGER_SURGE_SOUND = 45                             # 0x2d
VOYAGER_SURGE_STEPS = 15
VOYAGER_SURGE_PIXELS = 8
VOYAGER_FLY_PIXELS = 8
VOYAGER_FLY_UNTIL_X = -136
VOYAGER_BODY_PICTURE = 1998
VOYAGER_ROTOR_PICTURES = (1999, 2000)


def build_voyager_script() -> str:
    t = tres.Tres("Resource", "VoyagerClosingScript", SCRIPTS + "voyager_closing_script.gd")
    t.set("step_ticks", num(VOYAGER_STEP))
    t.set("rise_steps", str(VOYAGER_RISE_STEPS))
    t.set("rise_pixels", str(VOYAGER_RISE_PIXELS))
    t.set("turn_table", tres.packed_ints(VOYAGER_TURN_TABLE))
    t.set("turn_done_cell", str(VOYAGER_TURN_DONE_CELL))
    t.set("change_pictures", tres.array("StringName", (sn(picture(p)) for p in VOYAGER_CHANGE_PICTURES)))
    t.set("change_picture_steps", str(VOYAGER_CHANGE_PICTURE_STEPS))
    t.set("flash_sound", sn(sound(VOYAGER_FLASH_SOUND)))
    t.set("surge_sound", sn(sound(VOYAGER_SURGE_SOUND)))
    t.set("surge_steps", str(VOYAGER_SURGE_STEPS))
    t.set("surge_pixels", str(VOYAGER_SURGE_PIXELS))
    t.set("fly_pixels", str(VOYAGER_FLY_PIXELS))
    t.set("fly_until_x", str(VOYAGER_FLY_UNTIL_X))
    t.set("body_picture", sn(picture(VOYAGER_BODY_PICTURE)))
    t.set("rotor_pictures", tres.array("StringName", (sn(picture(p)) for p in VOYAGER_ROTOR_PICTURES)))
    t.set("margin_ticks", num(VOYAGER_MARGIN_TICKS))
    t.set("provenance", tres.s(
        "Original: VoyagerClosingSequence (CLOSING.C), the loops: 18 steps of 4 px up, the turn table, three change pictures of "
        "12 ticks, 15 steps of 8 px up, then 8 px left a step until x <= -136; a step is 6 ticks. Constants are in "
        "tools/import/step_story.py. Ours: the 14.6 tick margin after the last step."))
    return t.render()


# --- run --------------------------------------------------------------------------------------------------------------------------------

def timelines() -> dict[str, Timeline]:
    return {
        "news_cartoon": build_news(bulletin_texts()),
        "news_ambient": build_news_ambient(),
        "title_ship": build_title_ship(),
        "title_reveal": build_title_reveal(),
        "expert_hoist": build_expert_hoist(),
        "expert_deck": build_expert_deck(),
        "expert_wait": build_expert_wait(),
    }


def owned_files() -> list[Path]:
    """The files this step writes into the project (the committed timelines and scripts; the news cartoon is the legacy pack's). `import_all.py --clean`
    deletes them."""
    return [STORY / (name + ".tres") for name in sorted(TIMELINE_NAMES - LEGACY_TIMELINES)] + [STORY / "story_script.tres", STORY / "voyager_closing_script.tres"]


def run() -> None:
    written = []
    for name, timeline in timelines().items():
        out_text((LEGACY_STORY if name in LEGACY_TIMELINES else STORY) / (name + ".tres"), timeline.render())
        written.append(name)
    out_text(STORY / "story_script.tres", build_story_script())
    out_text(STORY / "voyager_closing_script.tres", build_voyager_script())
    print("  story: %s, story_script, voyager_closing_script" % ", ".join(written))
