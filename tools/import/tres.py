"""A tiny writer for Godot 4 text resources (.tres).

A .tres file has: a header, [ext_resource] lines (other files we use),
[sub_resource] blocks (resources embedded in this file), and one final
[resource] block holding the properties of the file's own resource.

Ids are assigned by counters, so output is deterministic.
"""
from __future__ import annotations

import re
from collections.abc import Iterable, Mapping
from pathlib import Path

import import_uids


# ---- value formatting -----------------------------------------------------

def s(text: str) -> str:
    """GDScript string literal. Control characters become \\uXXXX escapes."""
    out = []
    for ch in text:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif o < 32 or o == 127:
            out.append("\\u%04x" % o)
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def multiline(text: str) -> str:
    """GDScript string literal that keeps real line breaks, the way Godot itself saves an @export_multiline text.

    Only backslash and double quote are escaped, so the .tres shows the text as it reads and a diff is readable.
    """
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def f(x: float) -> str:
    """Float with a fixed, short format."""
    t = ("%.6f" % x).rstrip("0").rstrip(".")
    return t if "." in t else t + ".0"


def b(x: bool) -> str:
    return "true" if x else "false"


def vec2i(x: int, y: int) -> str:
    return "Vector2i(%d, %d)" % (x, y)


def vec2(x: float, y: float) -> str:
    return "Vector2(%s, %s)" % (f(x), f(y))


def rect2i(x: int, y: int, w: int, h: int) -> str:
    return "Rect2i(%d, %d, %d, %d)" % (x, y, w, h)


def packed_bytes(data: Iterable[int]) -> str:
    items = ", ".join(str(int(v)) for v in data)
    return "PackedByteArray(%s)" % items


def packed_ints(data: Iterable[int]) -> str:
    return "PackedInt32Array(%s)" % ", ".join(str(int(v)) for v in data)


def packed_strings(data: Iterable[str]) -> str:
    return "PackedStringArray(%s)" % ", ".join(s(v) for v in data)


def array(elem_type: str, items: Iterable[str]) -> str:
    """Typed array. elem_type is e.g. 'int', 'Rect2i' or 'ExtResource("2_x")'."""
    return "Array[%s]([%s])" % (elem_type, ", ".join(items))


def literal(value) -> str:
    """Any JSON value (nested dicts / lists / numbers / strings / bools) as a GDScript literal.

    Used for the free-form per-type `diagram` dictionaries; the Godot side reads them with plain
    dictionary and array access.
    """
    if isinstance(value, bool):
        return b(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return f(value)
    if isinstance(value, str):
        return s(value)
    if value is None:
        return "null"
    if isinstance(value, list):
        return "[%s]" % ", ".join(literal(v) for v in value)
    if isinstance(value, dict):
        return dictionary((s(k), literal(v)) for k, v in value.items())
    raise TypeError("cannot write %r as a GDScript literal" % (value,))


def dictionary(pairs: Iterable[tuple[str, str]]) -> str:
    """Dictionary from already formatted (key, value) pairs."""
    body = ", ".join("%s: %s" % kv for kv in pairs)
    return "{%s}" % body if body else "{}"


# ---- the writer -----------------------------------------------------------

class Tres:
    """Builds one .tres file.

    Tres("Resource", script_class="SectorData", script="res://src/...gd")
    Tres("SpriteFrames")                      # engine resource, no script
    """

    def __init__(self, resource_type: str, script_class: str | None = None, script: str | None = None,
                 uid: str | None = None):
        self.resource_type = resource_type
        self.script_class = script_class
        self.uid = uid                                  # "uid://..." for the header, or None (most files have none)
        self._ext_uid: dict[str, str] = {}              # path -> uid written on its [ext_resource] line
        self.ext: list[tuple[str, str, str]] = []      # (id, type, path)
        self._ext_by_path: dict[str, str] = {}
        self.subs: list[str] = []                       # rendered blocks
        self.props: list[tuple[str, str]] = []
        self._counter = 0
        self._script_ref = self.ext_ref("Script", script) if script else None
        if self._script_ref:
            self.props.append(("script", self._script_ref))

    def ext_ref(self, res_type: str, path: str, uid: str | None = None) -> str:
        """Returns 'ExtResource("id")', registering the file the first time. `uid`: the "uid://..." Godot gave the file."""
        if uid:
            self._ext_uid[path] = uid
        if path not in self._ext_by_path:
            rid = "%d_%s" % (len(self.ext) + 1, _slug(path))
            self._ext_by_path[path] = rid
            self.ext.append((rid, res_type, path))
        return 'ExtResource("%s")' % self._ext_by_path[path]

    def ext_id(self, res_type: str, path: str) -> str:
        """Same as ext_ref but returns only the id string (for Array[ExtResource("id")])."""
        self.ext_ref(res_type, path)
        return self._ext_by_path[path]

    def sub(self, res_type: str, props: list[tuple[str, str]], script: str | None = None, prefix: str | None = None) -> str:
        """Adds a [sub_resource] and returns 'SubResource("id")'."""
        self._counter += 1
        rid = "%s_%d" % (prefix or res_type, self._counter)
        lines = ['[sub_resource type="%s" id="%s"]' % (res_type, rid)]
        if script:
            lines.append("script = " + self.ext_ref("Script", script))
        for k, v in props:
            lines.append("%s = %s" % (k, v))
        self.subs.append("\n".join(lines))
        return 'SubResource("%s")' % rid

    def set(self, key: str, value: str) -> None:
        self.props.append((key, value))

    def render(self) -> str:
        head = '[gd_resource type="%s"' % self.resource_type
        if self.script_class:
            head += ' script_class="%s"' % self.script_class
        head += " format=3" + (' uid="%s"' % self.uid if self.uid else "") + "]"
        blocks = [head]
        if self.ext:
            blocks.append("\n".join(
                '[ext_resource type="%s"%s path="%s" id="%s"]' % (t, ' uid="%s"' % self._ext_uid[p] if p in self._ext_uid else "", p, i)
                for i, t, p in self.ext))
        blocks.extend(self.subs)
        body = ["[resource]"] + ["%s = %s" % kv for kv in self.props]
        blocks.append("\n".join(body))
        return "\n\n".join(blocks) + "\n"


def import_uid(png: Path) -> str:
    """The `uid://...` Godot keeps in `<png>.import`, or the one the importer gives the file (import_uids.py, which is also what
    the sidecar will hold: the legacy pack is not committed, so a clean checkout gets the same uids again)."""
    return import_uids.uid_in(png)


def _slug(path: str) -> str:
    base = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    return "".join(c if c.isalnum() else "_" for c in base)[:24]


# ---- reading and patching an existing file --------------------------------
# The reset tools change single lines of a .tres that designers (or Godot itself) have saved, so they work on its
# blocks: the header line, the [ext_resource] lines, each [sub_resource] and the final [resource] are separated by
# blank lines, in files from the importer and in files Godot saved.

def split_blocks(text: str) -> list[str]:
    """The blocks of a .tres text, each without its trailing newline."""
    if not text.endswith("\n"):
        raise ValueError("a .tres file ends with a newline")
    return text[:-1].split("\n\n")


def join_blocks(blocks: list[str]) -> str:
    return "\n\n".join(blocks) + "\n"


def sub_resource_id(block: str) -> str | None:
    """The id of a `[sub_resource ... id="X"]` block, None for any other block."""
    first = block.split("\n", 1)[0]
    if not first.startswith("[sub_resource "):
        return None
    start = first.index(' id="') + 5
    return first[start:first.index('"', start)]


def property_line(lines: list[str], key: str) -> int | None:
    """Index of the line `key = ...` in a block's lines, None if the block has none."""
    for k, line in enumerate(lines):
        if line.startswith(key + " = "):
            return k
    return None


def ints_in(value: str) -> list[int]:
    """The numbers inside the brackets of `Vector2i(1, 2)` / `PackedInt32Array(1, 2)` (not the 2 and 32 of the type name)."""
    return [int(v) for v in re.findall(r"-?\d+", value[value.find("(") + 1:])]


def property_values(lines: list[str]) -> dict[str, str]:
    """`key = value` lines of a block as a dict (the value still as text)."""
    return {line.split(" = ", 1)[0]: line.split(" = ", 1)[1] for line in lines if " = " in line}


def set_properties(block: str, values: dict[str, str], after: Mapping[str, str | list[str]] | None = None) -> str:
    """A block's text with `key = value` set for each entry of `values` (already formatted), in that order. A line the block has
    is replaced in place; a key it lacks (Godot leaves properties at their default out when it saves) is put after the line
    `after[key]` names (where the importer writes it: a property, or a list of them of which the first present counts; "*" is
    the end of the block), else after the entry of `values` before it, else after the `script` line. Other lines are kept
    as they are."""
    lines = block.split("\n")
    previous = None
    for key, value in values.items():
        at = property_line(lines, key)
        if at is None:
            anchors = (after or {}).get(key, [])
            anchor = next((a for a in ([anchors] if isinstance(anchors, str) else anchors) if a == "*" or property_line(lines, a) is not None), None)
            if anchor == "*":
                position = len(lines)
            elif anchor is not None:
                anchor_at = property_line(lines, anchor)
                assert anchor_at is not None
                position = anchor_at + 1
            elif previous is not None:
                position = previous + 1
            else:
                script = property_line(lines, "script")
                position = (script if script is not None else 0) + 1
            lines.insert(position, "")
            at = position
        lines[at] = "%s = %s" % (key, value)
        previous = at
    return "\n".join(lines)
