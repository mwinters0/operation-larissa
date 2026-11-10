"""Checks that the port map (port_map_onwin32.json) and the call-site audit (audit_rows.py) name port code that exists.

Every `where` of the port map and every `port` text of the audit says which code of the Godot port implements a routine of the
original. This finds the names in those texts and reports each one the code does not define:

  file.gd:function   (also .py, .tscn; a bare file name is looked up under godot/ and tools/)
  file.gd:a / b_c    (more names of the same file after " / " or ", :"; only words with an underscore, since "a / message path"
                     is prose: a further name without one goes unchecked)
  Class.member       (a `class_name` under godot/src or godot/addons, or an autoload of project.godot)
  file.gd:123        (a line number: reported as such, since it goes stale without notice; name the function instead)

Words of the original's code (Win32 constants, routine names) are not checked: only port code is.

  uv run python tools/analysis/ghidra/check_port_map.py        # prints the stale references, exit status 1 when there are any

Teaches: a test over hand-written cross-references, so a rename in the code cannot leave the map pointing at nothing
(tools/analysis/ghidra/test_check_port_map.py runs it).
"""
from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PORT_MAP = HERE / "port_map_onwin32.json"

SKIP_DIRS = {".godot", ".git", "reports", ".venv", "node_modules", "__pycache__", "ghidra-project"}
FILE_REF = re.compile(r"((?:[\w.\-]+/)*[\w\-]+\.(?:gd|py|tscn))(?![\w.])(?::(\w+))?")
MORE_NAMES = re.compile(r"(?:\s+/\s+|,\s*:)(_?[a-z][a-z0-9]*_[a-z0-9_]*|_[a-z][a-z0-9_]*)\b(?!\.)")
CLASS_REF = re.compile(r"\b([A-Z][A-Za-z0-9]+)\.(_?[A-Za-z]\w*)")


@dataclass(frozen=True)
class Stale:
    where: str       # which entry: "0x004174ec RunModalDialog" or "audit row DoAction (S)"
    reference: str   # as written
    problem: str


class Code:
    """The repo's source files, their classes and what each defines."""

    def __init__(self, repo: Path):
        self.repo = repo
        self._texts: dict[str, str] = {}
        self.files: dict[str, Path] = {}
        for top in ("godot", "tools"):
            for folder, dirs, names in os.walk(repo / top):
                dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not (top == "godot" and d == "packs")]
                for name in names:
                    path = Path(folder) / name
                    self.files[path.relative_to(repo).as_posix()] = path
        self.by_name: dict[str, list[str]] = {}
        for rel, path in self.files.items():
            self.by_name.setdefault(path.name, []).append(rel)
        self.classes: dict[str, list[str]] = {}
        for rel in self.files:
            if rel.endswith(".gd") and rel.startswith(("godot/src/", "godot/addons/")):
                found = re.search(r"^class_name\s+(\w+)", self.text(rel), re.MULTILINE)
                if found:
                    self.classes.setdefault(found.group(1), []).append(rel)
        project = repo / "godot" / "project.godot"
        if project.exists():
            for found in re.finditer(r'^(\w+)="\*?res://([^"]+)"', project.read_text(), re.MULTILINE):
                self.classes.setdefault(found.group(1), []).append("godot/" + found.group(2))

    def text(self, rel: str) -> str:
        if rel not in self._texts:
            self._texts[rel] = self.files[rel].read_text(errors="ignore")
        return self._texts[rel]

    def resolve(self, written: str) -> list[str]:
        """The files a written path may mean: exact, under godot/ or godot/src/, else by its file name."""
        for prefix in ("", "godot/", "godot/src/", "godot/addons/"):
            if prefix + written in self.files:
                return [prefix + written]
        same_name = self.by_name.get(os.path.basename(written), [])
        if "/" in written:
            return [rel for rel in same_name if rel.endswith("/" + written)]
        return same_name

    def defines(self, rel: str, name: str) -> bool:
        text, word = self.text(rel), re.escape(name)
        if rel.endswith(".gd"):
            if re.search(rf"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(?:func|var|const|signal|enum|class|class_name)\s+{word}\b", text, re.MULTILINE):
                return True
            return any(re.search(rf"\b{word}\b", body) for body in re.findall(r"enum\s*\w*\s*\{([^}]*)\}", text))
        if rel.endswith(".py"):
            return bool(re.search(rf"^\s*(?:async\s+)?(?:def|class)\s+{word}\b|^\s*{word}\s*(?::[^=\n]+)?=", text, re.MULTILINE))
        return bool(re.search(rf"\b{word}\b", text))                # a scene: a node or a property of that name


def check_text(code: Code, label: str, text: str) -> list[Stale]:
    """The stale references in one hand-written text."""
    stale: list[Stale] = []
    for found in FILE_REF.finditer(text):
        written, name = found.group(1), found.group(2)
        files = code.resolve(written)
        if not files:
            stale.append(Stale(label, written, "no such file"))
            continue
        if name is None:
            continue
        if name.isdigit():
            stale.append(Stale(label, "%s:%s" % (written, name), "a line number: name the function or constant instead"))
            continue
        names = [name]
        chain = re.match(r"(?:(?:\s+/\s+|,\s*:)(?:_?[a-z][a-z0-9]*_[a-z0-9_]*|_[a-z][a-z0-9_]*)\b(?!\.))+", text[found.end():])
        if chain:
            names += MORE_NAMES.findall(chain.group(0))
        for each in names:
            if not any(code.defines(rel, each) for rel in files):
                stale.append(Stale(label, "%s:%s" % (written, each), "not defined in " + ", ".join(files)))
    for found in CLASS_REF.finditer(text):
        cls, member = found.groups()
        if cls in code.classes and not any(code.defines(rel, member) for rel in code.classes[cls]):
            stale.append(Stale(label, "%s.%s" % (cls, member), "not defined in " + ", ".join(code.classes[cls])))
    return stale


def audit_texts() -> list[tuple[str, str]]:
    """(label, port text) of every row of audit_rows.py."""
    sys.path.insert(0, str(HERE))
    import audit_rows
    return [("audit row %s (%s)" % (row["caller"], row["table"]), row["port"] or "") for row in audit_rows.ROWS]


def check(repo: Path = REPO, port_map: Path = PORT_MAP, audit: list[tuple[str, str]] | None = None) -> list[Stale]:
    code = Code(repo)
    stale: list[Stale] = []
    for address, entry in json.loads(port_map.read_text()).items():
        stale += check_text(code, " ".join(filter(None, (address, entry.get("name")))), entry.get("where", ""))
    for label, text in audit_texts() if audit is None else audit:
        stale += check_text(code, label, text)
    return stale


def main() -> int:
    stale = check()
    for each in stale:
        print("%s: %s (%s)" % (each.where, each.reference, each.problem))
    print("%d stale reference(s)" % len(stale))
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
