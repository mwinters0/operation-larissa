"""check_port_map.py: the port map and the call-site audit name only port code that exists (AGENTS.md, "Keep the port map true")."""
import json

from check_port_map import check


def _repo(tmp_path):
    (tmp_path / "godot" / "src" / "ui").mkdir(parents=True)
    (tmp_path / "godot" / "src" / "ui" / "box.gd").write_text(
        "class_name Box\nextends Control\n\nconst LIMIT := 3\nvar shown: bool\nsignal closed\n\n"
        "func open() -> void:\n\tpass\n\nstatic func _build() -> void:\n\tpass\n")
    (tmp_path / "godot" / "src" / "clock.gd").write_text("extends Node\n\nfunc hold() -> void:\n\tpass\n")
    (tmp_path / "godot" / "project.godot").write_text('[autoload]\n\nGameClock="*res://src/clock.gd"\n')
    (tmp_path / "tools").mkdir()
    (tmp_path / "tools" / "tool.py").write_text("def run():\n    pass\n\nTABLE = {}\n")
    return tmp_path


def _stale(tmp_path, *texts):
    port_map = tmp_path / "map.json"
    port_map.write_text(json.dumps({"0x1": {"name": "Routine", "status": "ported", "where": texts[0]}}))
    audit = [("row %d" % i, text) for i, text in enumerate(texts[1:])]
    return sorted(each.reference for each in check(_repo(tmp_path), port_map, audit))


def test_names_that_exist_pass(tmp_path):
    assert _stale(tmp_path,
                  "godot/src/ui/box.gd:open / _build / closed, Box.LIMIT, Box.shown (the message path / rules), GameClock.hold",
                  "ui/box.gd:LIMIT and box.gd:open; tools/tool.py:run, tool.py:TABLE; Control.FOCUS_NONE is Godot's") == []


def test_a_missing_function_file_or_member_is_reported(tmp_path):
    assert _stale(tmp_path,
                  "box.gd:gone / _also_gone, Box.missing, GameClock.release",
                  "nowhere.gd:open", "tool.py:walk") == [
        "Box.missing", "GameClock.release", "box.gd:_also_gone", "box.gd:gone", "nowhere.gd", "tool.py:walk"]


def test_a_line_number_is_reported(tmp_path):
    assert _stale(tmp_path, "box.gd:12 (the open)") == ["box.gd:12"]


def test_the_port_map_and_the_audit_name_code_that_exists():
    stale = check()
    assert stale == [], "\n".join("%s: %s (%s)" % (each.where, each.reference, each.problem) for each in stale)
