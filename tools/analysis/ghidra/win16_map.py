"""Reader for the Win16 build's link map (ONWIN.MAP): the module address ranges and the publics. Standard library only.

The map is the game's content: names stay in memory and in git-ignored files, never in a tracked file. What the Win16 tools
keep of it are ids (`SSSS:OOOO`, the NE segment number and the offset, 4 upper-case hex digits each) and, for a module, its
address range and whether it is the game's own code or a library's.

  parse(text) -> {"mods": [...], "publics": [...]}
    mods     one per row of "Detailed map of segments": seg (NE number), off, len, cls, segname, mod
    publics  one per row of "Publics by Value": seg, off, name
  code_modules(mods) -> the code modules that hold bytes, in address order, each {seg, off, len, kind}, kind "game" or "rtl"

Teaches: the NE segment model the Win16 tools share: NE segment N is Ghidra segment 0x1000 + (N-1)*8 (`ghidra_segment`).
"""
import re

N_CODE_SEGMENTS = 26          # NE segments 1..26 are code; the rest are data

_DETAIL = re.compile(r"\s*([0-9A-F]{4}):([0-9A-F]{4}) ([0-9A-F]{4}) C=(\S+)\s+S=(\S+)\s+G=\S+\s+M=(\S+)")
_PUBLIC = re.compile(r"\s*([0-9A-F]{4}):([0-9A-F]{4})(?: idle)?\s+(.*\S)")


def ghidra_segment(n):
    """The Ghidra segment value of NE segment number n (1-based), in x86:LE:16:Protected Mode."""
    return 0x1000 + (n - 1) * 8


def win16_id(seg, off):
    return "%04X:%04X" % (seg, off)


def parse(text):
    mods, publics = [], []
    state = None
    for line in text.splitlines():
        if line.startswith("Detailed map of segments"):
            state = "detail"
        elif "Publics by Name" in line:
            state = "by-name"
        elif "Publics by Value" in line:
            state = "by-value"
        elif line.startswith("Line numbers for"):
            state = "lines"
        elif state == "detail":
            m = _DETAIL.match(line)
            if m:
                mods.append(dict(seg=int(m[1], 16), off=int(m[2], 16), len=int(m[3], 16), cls=m[4], segname=m[5], mod=m[6]))
        elif state == "by-value":
            m = _PUBLIC.match(line)
            if m:
                publics.append(dict(seg=int(m[1], 16), off=int(m[2], 16), name=m[3]))
    return dict(mods=mods, publics=publics)


def code_modules(mods):
    """A module named by a source path (a drive letter or a backslash) is the game's ("game"); a library object is "rtl"."""
    out = []
    for x in mods:
        if x["cls"] == "CODE" and x["len"] > 0:
            kind = "game" if ("\\" in x["mod"] or ":" in x["mod"]) else "rtl"
            out.append(dict(seg=x["seg"], off=x["off"], len=x["len"], kind=kind))
    out.sort(key=lambda x: (x["seg"], x["off"]))
    return out
