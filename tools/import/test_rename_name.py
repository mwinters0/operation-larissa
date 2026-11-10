"""pytest checks of the rename tool (rename_name.py). Every test works on a COPY of the parts of the repository the tool
reads and writes (the registry, the stored creature scripts, godot/src, tests and the project's addons, the documents), never on the real
tree. The end-to-end proof on the real tree (the importer moving the asset files) is described in docs/create/NAMES.md and was done by hand.
"""
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import code_names
import common
import foe_names
import foe_text
import rename_name
from rename_name import Refused, plan_rename

# The copy it works on holds the legacy pack's sectors (`_copy_tree`): without the legacy pack the whole file is skipped (I7: point the copy at dev's sectors).
pytestmark = pytest.mark.legacy

REGISTRY_FILE = Path("godot/names/original.json")


def _copy_tree(root: Path) -> Path:
    keep = shutil.ignore_patterns("*.uid", "*.import")
    (root / "godot" / "names").mkdir(parents=True)
    shutil.copy(common.GODOT / "names" / "original.json", root / REGISTRY_FILE)
    shutil.copytree(common.PACK_DATA / "sectors", root / "godot" / "packs" / "legacy" / "data" / "sectors", ignore=shutil.ignore_patterns("*.uid", "screen_*.tres", "foe_annotations*"))
    for sub in ("src", "tests"):
        shutil.copytree(common.GODOT / sub, root / "godot" / sub, ignore=shutil.ignore_patterns("*.uid", "fixtures", "snapshots"))
    for addon in code_names.OWN_ADDONS:
        shutil.copytree(common.GODOT / "addons" / addon, root / "godot" / "addons" / addon, ignore=keep)
    shutil.copytree(common.ROOT / "docs", root / "docs", ignore=shutil.ignore_patterns("data", "*.png", "*.json", "*.jsonl"))
    shutil.copy(common.ROOT / "README.md", root / "README.md")
    shutil.copy(common.GODOT / "README.md", root / "godot" / "README.md")
    (root / "tools" / "import").mkdir(parents=True)
    shutil.copy(Path(__file__).resolve().parent / "name_runs.json", root / "tools" / "import" / "name_runs.json")
    return root


@pytest.fixture()
def tree(tmp_path):
    """A copy of what the tool touches, as a repository root; every test may change it."""
    return _copy_tree(tmp_path / "repo")


@pytest.fixture(scope="module")
def frozen(tmp_path_factory):
    """The same copy for tests that must leave it exactly as it is (refusals, dry runs): they check that."""
    return _copy_tree(tmp_path_factory.mktemp("frozen") / "repo")


def snapshot(root: Path) -> dict[str, str]:
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob("*")) if p.is_file()}


def changed_files(before: dict[str, str], after: dict[str, str]) -> set[str]:
    return {k for k in before.keys() | after.keys() if before.get(k) != after.get(k)}


def run(root: Path, kind: str, old: str, new: str, scope: str | None = None, run_: bool = False) -> rename_name.Plan:
    plan = plan_rename(root, kind, old, new, scope, run_)
    rename_name.apply(plan)
    return plan


def registry(root: Path) -> dict:
    return json.loads((root / REGISTRY_FILE).read_text(encoding="utf-8"))


def operand_values(root: Path, data: dict) -> dict[str, list]:
    """The operand values of every instruction line of every stored creature script, read with the registry `data`: what the assembler
    would turn into bytes (a Python twin of FoeAsm.parse_operands; the GDScript tests check the bytes against the original)."""
    reg = foe_names.Registry(data["names"])
    out: dict[str, list] = {}
    mnemonics = {m.lower(): i for i, m in enumerate(foe_text.MNEMONIC)}
    for index, zone, script in rename_name._sector_dirs(root):
        names = foe_names.Names(reg, index, zone)
        values = []
        for line in script.read_text(encoding="utf-8").splitlines():
            words = line.split(";", 1)[0].split()
            if words and words[0].lower() in mnemonics:
                values.append(foe_text.parse_operands(mnemonics[words[0].lower()], words[1:], names))
        out[script.parent.name] = values
    return out


def lines_with(root: Path, relative: str, word: str) -> list[str]:
    return [l.strip() for l in (root / relative).read_text(encoding="utf-8").splitlines() if re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % word, l)]


# --- a global kind: a sound ------------------------------------------------------------------------------------------------

@pytest.mark.legacy
def test_a_sound_is_renamed_in_the_registry_the_scripts_the_code_and_the_docs(tree):
    before = snapshot(tree)
    values_before = operand_values(tree, registry(tree))
    plan = run(tree, "sound", "ray_sting", "sting_ray_hit")
    data = registry(tree)

    # the registry: the number and the position stay, the layout is the standard one
    assert (tree / REGISTRY_FILE).read_text(encoding="utf-8") == json.dumps(data, indent=1, ensure_ascii=False) + "\n"
    old = json.loads((common.GODOT / "names" / "original.json").read_text(encoding="utf-8"))
    names, old_names = list(data["names"]["sound"].items()), list(old["names"]["sound"].items())
    assert [n for n, _ in names].index("sting_ray_hit") == [n for n, _ in old_names].index("ray_sting")
    assert [v for _, v in names] == [v for _, v in old_names] and "ray_sting" not in data["names"]["sound"]
    assert {k: v for k, v in data.items() if k != "names"} == {k: v for k, v in old.items() if k != "names"}

    # the scripts: only `Play_Sound ray_sting` changed, `ray_sting_alt` did not, and every script still means the same operands
    assert plan.applied
    for line in (tree / "godot/packs/legacy/data/sectors/sector_16/sector_16.foe").read_text(encoding="utf-8").splitlines():
        assert not re.fullmatch(r"\s*Play_Sound ray_sting", line)
    assert any("Play_Sound ray_sting_alt" in line for p in tree.glob("godot/packs/legacy/data/sectors/*/*.foe") for line in p.read_text(encoding="utf-8").splitlines())
    assert operand_values(tree, data) == values_before
    after = snapshot(tree)
    assert all(f.endswith((".foe", "original.json", ".md", ".gd")) for f in changed_files(before, after))
    assert any(f.endswith(".foe") for f in changed_files(before, after))


def test_a_sound_used_by_the_code_is_renamed_in_every_literal_that_a_resolver_takes(tree):
    run(tree, "sound", "lock_tick", "click_tick")
    assert 'const SFX_TICK := &"click_tick"' in lines_with(tree, "godot/src/problems/combination_lock.gd", "click_tick")
    assert lines_with(tree, "godot/src/problems/combination_lock.gd", "lock_tick") == []          # the comment that names it in backticks moved too
    assert "stream_named(&\"click_tick\")" in (tree / "godot/tests/engine/test_assets.gd").read_text(encoding="utf-8")
    assert "sfx_requested.emit(&\"click_tick\")" in (tree / "godot/tests/engine/test_sfx_events.gd").read_text(encoding="utf-8")
    # the asset file name in the documents moves with it
    assert "click_tick_38.wav" in (tree / "docs/create/NAMES.md").read_text(encoding="utf-8")
    # and the static check agrees that nothing is left behind
    scan = code_names.scan_tree(tree / "godot", tests=False)
    assert code_names.unresolved(scan, registry(tree)) == []


def test_what_it_is_not_sure_of_is_reported_and_left_alone(tree):
    plan = run(tree, "sound", "wrong", "buzzer")
    flow = (tree / "godot/src/problems/problem_flow.gd").read_text(encoding="utf-8")
    # `reacted.emit(&"wrong")` names an animation of the problem screen, not the sound
    assert 'reacted.emit(&"wrong")' in flow
    assert 'const SFX_WRONG := &"buzzer"' in flow
    assert any("problem_flow.gd" in c.path and 'reacted.emit(&"wrong")' in c.before for c in plan.reported)


def test_a_round_trip_leaves_the_files_as_they_were(tree):
    before = snapshot(tree)
    run(tree, "sound", "lock_tick", "click_tick")
    assert snapshot(tree) != before
    run(tree, "sound", "click_tick", "lock_tick")
    assert snapshot(tree) == before


@pytest.mark.legacy
def test_dry_run_changes_nothing_and_lists_everything(frozen, capsys):
    tree = frozen
    before = snapshot(tree)
    assert rename_name.main(["sound", "ray_sting", "sting_ray_hit", "--dry-run", "--root", str(tree)]) == 0
    assert snapshot(tree) == before
    shown = capsys.readouterr().out
    assert "godot/names/original.json" in shown and re.search(r"sector_\d\d\.foe:\d+", shown) and "would change" in shown
    plan = plan_rename(tree, "sound", "ray_sting", "sting_ray_hit")
    assert shown.count("\n  + ") == len(plan.applied)


# --- a zone-scoped kind: a creature picture ------------------------------------------------------------------------------

@pytest.mark.legacy
def test_a_zone_scoped_frame_changes_only_in_the_sectors_of_its_zone(tree):
    data = registry(tree)
    zone4 = data["names"]["frame"]["4"]
    zone4["crab_hold_ball"] = 100                    # the same spelling, another drawing: zone 4's slot 100
    (tree / REGISTRY_FILE).write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    other = tree / "godot/packs/legacy/data/sectors/sector_12/sector_12.foe"
    other.write_text(other.read_text(encoding="utf-8") + "\n    Set_Frame crab_hold_ball\n", encoding="utf-8")      # a zone 4 sector
    home = tree / "godot/packs/legacy/data/sectors/sector_09/sector_09.foe"
    home.write_text(home.read_text(encoding="utf-8") + "\ncrab_hold_ball:\n    Jump_To crab_hold_ball   ; crab_hold_ball is also a label here\n", encoding="utf-8")
    before_values = operand_values(tree, registry(tree))
    before = {p.name: p.read_text(encoding="utf-8") for p in tree.glob("godot/packs/legacy/data/sectors/*/*.foe")}

    with pytest.raises(Refused, match="2 scopes|in 2 scopes"):
        plan_rename(tree, "frame", "crab_hold_ball", "crab_hold", None)
    run(tree, "frame", "crab_hold_ball", "crab_hold_the_ball", scope="3")
    after = {p.name: p.read_text(encoding="utf-8") for p in tree.glob("godot/packs/legacy/data/sectors/*/*.foe")}
    changed = {n for n in before if before[n] != after[n]}
    assert changed == {"sector_%02d.foe" % i for i in (9, 10, 11, 24, 25, 26)}
    assert "Set_Frame crab_hold_ball" in after["sector_12.foe"]
    assert "crab_hold_the_ball:" not in after["sector_09.foe"] and "crab_hold_ball:\n    Jump_To crab_hold_ball   ; crab_hold_ball is also a label here" in after["sector_09.foe"]
    assert "Set_Frame crab_hold_the_ball" in after["sector_09.foe"]
    frames = registry(tree)["names"]["frame"]
    assert frames["4"]["crab_hold_ball"] == 100 and "crab_hold_ball" not in frames["3"]
    assert frames["3"]["crab_hold_the_ball"] == json.loads((common.GODOT / "names" / "original.json").read_text(encoding="utf-8"))["names"]["frame"]["3"]["crab_hold_ball"]
    # the values of every line are unchanged under the new registry
    assert operand_values(tree, registry(tree)) == before_values


@pytest.mark.legacy
def test_a_common_frame_changes_in_every_sector(tree):
    run(tree, "frame", "ink_burst_4", "ink_spurt_4", scope="common")
    for script in tree.glob("godot/packs/legacy/data/sectors/*/*.foe"):
        assert "Set_Frame ink_burst_4" not in script.read_text(encoding="utf-8")
    assert "Set_Frame ink_spurt_4" in (tree / "godot/packs/legacy/data/sectors/sector_07/sector_07.foe").read_text(encoding="utf-8")


# --- a sector-scoped kind: a creature --------------------------------------------------------------------------------------

@pytest.mark.legacy
def test_a_sector_scoped_foe_changes_only_in_its_sector(tree):
    scripts = {p.name: p.read_text(encoding="utf-8") for p in tree.glob("godot/packs/legacy/data/sectors/*/*.foe")}
    assert "Put_Foe_To_Sleep oxygen_tank" in scripts["sector_02.foe"] and "Put_Foe_To_Sleep oxygen_tank" in scripts["sector_03.foe"]
    before_values = operand_values(tree, registry(tree))
    run(tree, "foe", "oxygen_tank", "air_tank", scope="2")
    now = {p.name: p.read_text(encoding="utf-8") for p in tree.glob("godot/packs/legacy/data/sectors/*/*.foe")}
    assert {n for n in now if now[n] != scripts[n]} == {"sector_02.foe"}
    assert "Put_Foe_To_Sleep oxygen_tank" not in now["sector_02.foe"] and "Put_Foe_To_Sleep air_tank" in now["sector_02.foe"]
    assert operand_values(tree, registry(tree)) == before_values


@pytest.mark.legacy
def test_a_flag_is_not_confused_with_a_label_or_a_picture_of_the_same_spelling(tree):
    script = tree / "godot/packs/legacy/data/sectors/sector_30/sector_30.foe"
    script.write_text(script.read_text(encoding="utf-8") + "\nfinale:\n    Jump_To finale\n    Set_Frame finale\n", encoding="utf-8")
    run_text = script.read_text(encoding="utf-8")
    plan = plan_rename(tree, "flag", "finale", "end_of_game", "common")
    rename_name.apply(plan)
    now = script.read_text(encoding="utf-8")
    assert "Set_Flag end_of_game" in now and "Clear_Flag end_of_game" in now
    assert "\nfinale:\n    Jump_To finale\n    Set_Frame finale\n" in now          # the label, its jump and the (unknown) picture word stay
    assert now.count("end_of_game") == run_text.count("Set_Flag finale") + run_text.count("Clear_Flag finale") + run_text.count("If_Flag finale")


# --- what it refuses ---------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("request_, message", [
    (("sound", "begin", "Begin"), "not a valid name"),
    (("sound", "begin", "1st"), "not a valid name"),
    (("sound", "begin", "x" * 41), "longer than 40"),
    (("sound", "begin", ""), "is empty"),
    (("sound", "begin", "self"), "reserved"),
    (("sound", "begin", "mirrored"), "reserved"),
    (("sound", "begin", "jump_to"), "instruction"),
    (("sound", "begin", "padding"), "instruction"),
    (("sound", "begin", "sfx_30"), "looks like the made-up name"),
    (("sound", "begin", "correct"), "already a sound name"),
    (("sound", "begin", "begin"), "is the old name"),
    (("sound", "sfx_22", "anything"), "made-up name of sound 22"),
    (("sound", "no_such_sound", "anything"), "no sound named"),
    (("sound", "bgin", "anything"), "did you mean 'begin'"),
    (("nonsense", "begin", "x"), "unknown kind"),
    (("frame", "ink_burst_0", "ink_burst_1"), "already a frame name in the common names"),
    (("frame", "ink_burst_0", "eel_swim_0"), "already a frame name in scope 1"),         # a common name must be free in every zone
    (("frame", "eel_swim_0", "ink_burst_0"), "already a frame name in the common names"),   # a zone's name must be free in common
    (("frame", "eel_swim_0", "eel_swim_1", "2"), "no frame named 'eel_swim_0' in scope 2"),
    (("foe", "clam", "x"), "scopes"),
    (("sound", "begin", "x", "3"), "global"),
    (("text", "news_bulletin_3", "diary_3"), "run"),
    (("text", "hint_6", "x"), "run"),
    (("ui_picture", "status_light_1", "x"), "run"),
])
def test_it_refuses_and_changes_nothing(frozen, request_, message):
    tree = frozen
    kind, old, new = request_[:3]
    scope = request_[3] if len(request_) > 3 else None
    before = snapshot(tree)
    if kind == "frame" and old == "ink_burst_0" and new == "eel_swim_0":
        scope = "common"
    with pytest.raises(Refused, match=message):
        plan_rename(tree, kind, old, new, scope)
    assert snapshot(tree) == before


def test_the_refusal_of_a_run_member_says_what_to_do(frozen):
    tree = frozen
    with pytest.raises(Refused) as why:
        plan_rename(tree, "text", "news_bulletin_3", "x")
    assert "--run" in str(why.value) and "news_bulletin_" in str(why.value)


def test_the_command_line_refuses_with_an_exit_code_and_a_message(frozen, capsys):
    tree = frozen
    before = snapshot(tree)
    assert rename_name.main(["sound", "begin", "Begin", "--root", str(tree)]) == 1
    assert "REFUSED, nothing was changed" in capsys.readouterr().err
    assert snapshot(tree) == before


# --- runs --------------------------------------------------------------------------------------------------------------

def test_a_whole_run_is_renamed_with_its_pattern_and_the_checks_still_pass(tree):
    plan = run(tree, "text", "news_bulletin_", "headline_", run_=True)
    data = registry(tree)
    assert not [n for n in data["names"]["text"] if re.fullmatch(r"news_bulletin_[0-9]+", n)]
    assert [data["names"]["text"]["headline_%d" % i] for i in range(6)] == list(range(10003, 10009))
    assert 'StringName("headline_%d" % index)' in (tree / "godot/src/story/news_cartoon.gd").read_text(encoding="utf-8")
    runs = json.loads((tree / "tools/import/name_runs.json").read_text(encoding="utf-8"))["runs"]
    assert "headline_" in runs["text"] and "news_bulletin_" not in runs["text"]
    scan = code_names.scan_tree(tree / "godot", tests=False)
    assert code_names.unresolved(scan, data) == [] and code_names.run_problems(scan, data, runs) == []
    assert plan.applied


def test_a_run_needs_a_run(frozen):
    tree = frozen
    with pytest.raises(Refused, match="not a run"):
        plan_rename(tree, "text", "exit_", "leave_", run=True)
    with pytest.raises(Refused, match="not a valid|already"):
        plan_rename(tree, "text", "news_bulletin_", "Captain_", run=True)


# --- the check catches a rename that missed a use ----------------------------------------------------------------------

def test_a_registry_edit_that_leaves_the_code_behind_fails_the_static_check(tree):
    plan = plan_rename(tree, "sound", "lock_tick", "click_tick")
    registry_path = tree / REGISTRY_FILE
    registry_path.write_text(plan.edits[registry_path], encoding="utf-8")           # only the registry: what a hand edit does
    scan = code_names.scan_tree(tree / "godot", tests=False)
    assert [l.value for l in code_names.unresolved(scan, registry(tree))] == ["lock_tick"]


# --- parity with the GDScript reader -----------------------------------------------------------------------------------

def test_the_rules_are_the_ones_of_name_registry_gd():
    source = (common.GODOT / "src" / "core" / "name_registry.gd").read_text(encoding="utf-8")
    assert "const MAX_NAME_LENGTH := %d" % rename_name.MAX_NAME_LENGTH in source
    assert 'const RESERVED: Array[String] = [%s]' % ", ".join('"%s"' % w for w in rename_name.RESERVED) in source
    assert 'RegEx.create_from_string("^[a-z][a-z0-9_]*$")' in source
    for kind in rename_name.KINDS:
        m = re.search(r'&"%s": \{[^\n]*?"first": (\d+), "last": (\d+), "fallback": "([^"]+)"' % kind, source)
        assert m, kind
        assert (int(m.group(1)), int(m.group(2)), m.group(3)) == (*rename_name.FIRST_LAST[kind], rename_name.FALLBACKS[kind]), kind


def test_every_name_of_the_registry_passes_the_rules_of_the_tool():
    for kind, node in registry_names().items():
        for name in node:
            assert rename_name.name_problem(name) == "", (kind, name)
            assert rename_name.fallback_index(kind, name) < 0, (kind, name)


def registry_names() -> dict[str, set[str]]:
    return code_names.known_names(json.loads((common.GODOT / "names" / "original.json").read_text(encoding="utf-8")))
