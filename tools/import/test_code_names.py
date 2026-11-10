"""The static half of the rename tool: a name in the code that resolves to nothing fails a test, not a run.

code_names.py finds the names that GDScript hands to a registry resolver (`Assets.ui_picture(&"title_sky")`, `Audio.play_sfx(SFX_TICK)`
with a constant, `Catalog.text(StringName("hint_%d" % n))` ...; its docstring says how) and this file checks them against
godot/names/original.json. So a rename that missed a use (the tool is rename_name.py), or a hand edit of the registry that removed or
changed a name, fails here with the file and line, and `tests/engine/test_assets.gd` (every named picture loads, every text gives its string)
still checks the same at run time for what the scan cannot see.

BLIND SPOTS (what this does not check): a name that reaches a resolver through a signal connected to a callable, a call on a value whose
class is not written down (`a.b.f(name)`, an untyped variable, an inner class), a member variable of another object, a container that is
filled in another file, `call()` by name or a data file; a name built any other way than `StringName("..._%d" % n)`; a name in tests/
(they spell wrong names on purpose). For a scoped kind (frame, deco, foe, screen, flag) the name must exist in SOME scope: which scope
the running code asks is not known statically. A literal that no resolver is seen to take is not checked at all; `UNCHECKED_BUT_NAMES`
below lists the ones that are a registry name anyway, so a new one is noticed.
"""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import code_names
import common

REGISTRY = json.loads((common.GODOT / "names" / "original.json").read_text(encoding="utf-8"))
RUNS = json.loads((Path(__file__).resolve().parent / "name_runs.json").read_text(encoding="utf-8"))["runs"]


@pytest.fixture(scope="module")
def scan():
    return code_names.scan_tree(common.GODOT, tests=False)


def _where(lit: code_names.Literal) -> str:
    return "%s:%d: %s%s (%s)" % (lit.path.relative_to(common.ROOT), lit.line, lit.prefix, '"%s"' % lit.value, "/".join(sorted(lit.kinds)))


def test_every_name_handed_to_a_resolver_exists(scan):
    missing = code_names.unresolved(scan, REGISTRY)
    assert not missing, "names the code uses that the registry does not have:\n" + "\n".join(_where(l) for l in missing)


def test_the_runs_the_code_builds_exist(scan):
    problems = code_names.run_problems(scan, REGISTRY, RUNS)
    assert not problems, "\n".join(problems)


def test_the_scan_finds_the_names_of_every_resolver(scan):
    """A scanner that silently found nothing would pass the checks above; these are floors for what it finds today."""
    by_kind: dict[str, int] = {}
    for lit in scan.literals:
        for kind in lit.kinds:
            by_kind[kind] = by_kind.get(kind, 0) + 1
    # (D8 moved the sound and picture names of the cutscenes into data/story/*.tres: the code holds four sound names and about twenty picture names fewer)
    # (F2 moved the log entries, the supply messages and the sector songs into data/campaigns/*.tres and the sector files: the code builds three fewer runs)
    floors = {"sound": 16, "music": 4, "voice": 1, "text": 145, "ui_picture": 40, "problem_art": 1, "frame": 3}
    for kind, floor in floors.items():
        assert by_kind.get(kind, 0) >= floor, "%s: the scan found %d names, there were at least %d" % (kind, by_kind.get(kind, 0), floor)
    assert len(scan.patterns) >= 15


# Name literals of src/ that the scan does not tie to a resolver but that are a name of the registry anyway. The scan cannot tell
# these from other uses of the same word, so they are not checked; each is listed with what it is.
UNCHECKED_BUT_NAMES = {
    ("voyager_closing.gd", "closing"): "the name of an animation of the closing cutscene (the song `closing` is `Audio.SONG_CLOSING`)",
    ("sim_world.gd", "finale"): "a step of `SimWorld.TICK_ORDER` (the finale check), not the song or the sound `finale`",
    ("sub_model.gd", "message_light"): "a field name in `SubModel.SWITCH_FIELDS` (the beacon), not the sound `message_light`",
}


def test_literals_that_are_names_but_no_resolver_takes_them_are_listed(scan):
    known = code_names.known_names(REGISTRY)
    every = set().union(*known.values())
    found = {(lit.path.name, lit.value) for lit in scan.literals if not lit.kinds and lit.value in every}
    assert found == set(UNCHECKED_BUT_NAMES), "name literals that no resolver is seen to take: %s (list them, with why, or bind them)" % sorted(found ^ set(UNCHECKED_BUT_NAMES))


# --- the scan itself, on small scripts ------------------------------------------------------------------------------------

def _scan(source: str, name: str = "probe.gd"):
    return code_names.scan_sources({Path(name): source})


def _kinds(scan, value: str):
    return {frozenset(l.kinds) for l in scan.literals if l.value == value}


def test_a_direct_argument_is_bound_to_the_kind_of_its_resolver():
    s = _scan('func f():\n\tAssets.ui_picture(&"title_sky")\n\tCatalog.text(&"click_to_go_on")\n\tAudio.play_sfx(&"begin")\n\tAudio.play_music(&"title")\n')
    assert _kinds(s, "title_sky") == {frozenset({"ui_picture"})}
    assert _kinds(s, "click_to_go_on") == {frozenset({"text"})}
    assert _kinds(s, "begin") == {frozenset({"sound"})}
    assert _kinds(s, "title") == {frozenset({"music"})}


def test_a_constant_that_flows_into_a_resolver_is_bound():
    s = _scan('const SFX_TICK := &"lock_tick"\nconst NOT_A_NAME := &"pressed"\nconst PICS: Array[StringName] = [&"a_0", &"a_1"]\n'
              'func f():\n\tsfx_requested.emit(SFX_TICK)\n\tfor picture_name: StringName in PICS:\n\t\tAssets.ui_picture(picture_name)\n')
    assert _kinds(s, "lock_tick") == {frozenset({"sound"})}
    assert _kinds(s, "a_0") == {frozenset({"ui_picture"})} and _kinds(s, "a_1") == {frozenset({"ui_picture"})}
    assert _kinds(s, "pressed") == {frozenset()}


def test_a_name_passed_to_a_function_of_the_project_is_followed():
    s = _scan('func _sprite(picture: StringName):\n\treturn Assets.ui_picture(picture)\nfunc f():\n\t_sprite(&"radar_map")\n\tvar x := &"unrelated"\n')
    assert _kinds(s, "radar_map") == {frozenset({"ui_picture"})}
    assert _kinds(s, "unrelated") == {frozenset()}


def _bound(scan, value: str) -> set[str]:
    """The kinds a literal is bound to (empty when it is not bound, or not even recorded because nothing passes it on)."""
    return set().union(*(l.kinds for l in scan.literals if l.value == value))


def test_a_call_reaches_only_the_function_of_its_own_script():
    """Two scripts with a function of the same name: a call is tied to the one it reaches, not to both (cast keys were once texts)."""
    files = {
        Path("sub.gd"): 'class_name Sub\nfunc bind(model):\n\tCatalog.text(model)\nstatic func of(x):\n\treturn x\n',
        Path("cast.gd"): 'class_name Cast\nfunc bind(actor: StringName, node):\n\tpass\n',
        Path("scene.gd"): 'func f(cast: Cast, sub: Sub, other):\n\tcast.bind(&"ship", null)\n\tother.bind(&"untyped", null)\n'
                          '\tSubState.of(&"inner_class")\n\tsub.bind(&"typed_param")\n\tvar s := Sub.new()\n\ts.bind(&"made_here")\n'
                          '\tSub.of(&"static_call")\n\tbind(&"not_here")\n',
        Path("child.gd"): 'extends Sub\nfunc g():\n\tbind(&"inherited")\n\tself.bind(&"via_self")\n',
    }
    s = code_names.scan_sources(files)
    for value in ("ship", "untyped", "inner_class", "not_here"):
        assert _bound(s, value) == set(), value
    for value in ("typed_param", "made_here", "inherited", "via_self"):
        assert _bound(s, value) == {"text"}, value
    assert _bound(s, "static_call") == set()          # of() returns it, but nothing hands the result to a resolver
    s = code_names.scan_sources({**files, Path("user.gd"): 'func h():\n\tCatalog.text(Sub.of(&"returned"))\n\tCatalog.text(Cast.of(&"no_such"))\n'})
    assert _bound(s, "returned") == {"text"} and _bound(s, "no_such") == set()


def test_an_autoload_call_reaches_its_script():
    files = {Path("audio.gd"): 'func jingle(n):\n\tplay_music(n)\n', Path("probe.gd"): 'func f():\n\tAudio.jingle(&"title")\n'}
    assert _bound(code_names.scan_sources(files), "title") == set()
    assert _bound(code_names.scan_sources(files, {"Audio": Path("audio.gd")}), "title") == {"music"}


def test_the_kind_argument_and_other_calls_are_not_names():
    s = _scan('func f():\n\tNameRegistry.original().index_of(&"frame", picture_name, zone)\n\tAudio.play_voice(StringName(reg.name_of(&"voice", 3)))\n'
              '\tCatalog.text(&"a" if x else &"b")\n\tanimations.play(&"wrong")\n')
    assert not any(l.value in ("frame", "voice") and l.kinds for l in s.literals)
    assert _kinds(s, "a") == {frozenset({"text"})} and _kinds(s, "b") == {frozenset({"text"})}
    assert not [l for l in s.literals if l.value == "wrong" and l.kinds]


def test_dictionary_keys_and_comments_are_not_names():
    s = _scan('const D := {&"hints": [&"question_hints_title"]}\nfunc f():\n\tCatalog.text(D[x][0])  # Catalog.text(&"in_a_comment")\n')
    assert _kinds(s, "question_hints_title") == {frozenset({"text"})}
    assert not [l for l in s.literals if l.value in ("hints", "in_a_comment")]


def test_a_name_that_does_not_exist_is_found():
    s = _scan('func f():\n\tAudio.play_sfx(&"lock_tik")\n\tAudio.play_sfx(&"lock_tick")\n\tAudio.play_sfx(&"sfx_28")\n\tCatalog.text(&"ui_1039")\n')
    assert [l.value for l in code_names.unresolved(s, REGISTRY)] == ["lock_tik", "ui_1039"]     # a made-up name resolves in its own kind (sfx_28 is a sound; ui_1039 is not a text)


def test_a_run_that_lost_a_member_is_found():
    s = _scan('func f(n):\n\treturn Catalog.text(StringName("log_entry_%d" % n))\n')
    registry = json.loads(json.dumps(REGISTRY))
    assert code_names.run_problems(s, registry, {"text": {"log_entry_": {"first": 0, "last": 29}}}) == []
    registry["names"]["text"]["captain_log_3"] = registry["names"]["text"].pop("log_entry_3")
    problems = code_names.run_problems(s, registry, {"text": {"log_entry_": {"first": 0, "last": 29}}})
    assert len(problems) == 1 and "'log_entry_3'" in problems[0]
    assert "not declared" in code_names.run_problems(s, REGISTRY, {"text": {}})[0]


def test_the_runs_file_is_in_the_standard_layout():
    path = Path(__file__).resolve().parent / "name_runs.json"
    assert path.read_text(encoding="utf-8") == json.dumps(json.loads(path.read_text(encoding="utf-8")), indent=1, ensure_ascii=False) + "\n"
