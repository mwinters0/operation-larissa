"""Finds the registry NAMES that GDScript code writes (docs/create/NAMES.md, "Renaming a name"): the static half of the rename tool.

Code says `Assets.ui_picture(&"title_sky")`, `Audio.play_sfx(SFX_TICK)` with `const SFX_TICK := &"lock_tick"`, or builds a name at run
time (`StringName("log_entry_%d" % n)`). Two tools need to know which literals are such names and of which kind:

  * the static check (test_code_names.py): every name that is handed to a registry resolver exists in godot/names/original.json, so
    a rename that missed a use, or a hand edit of the registry, fails a test instead of a run-time error;
  * the rename tool (rename_name.py): rewrites exactly the literals that are a use of the renamed name.

HOW A LITERAL IS FOUND. A small lexer turns a script into tokens (strings with their `&` prefix, identifiers, operators; comments are
kept apart). A literal counts as the name of a kind in one of three ways, from the most to the least direct:

  1. DIRECT: it is an argument of a call that takes a name of a kind (SINKS below: `Catalog.text`, `Assets.ui_picture`,
     `Assets.problem_art`, `play_sfx`, `play_voice`, `play_voice_sequence`, `play_music`, `<signal>.emit` of the sound / voice / music
     events, `index_of(&"kind", name)`). Wrappers that only pass the value on
     (`StringName(...)`, `String(...)`, parentheses, `[...]` and `{...}` literals, `a if c else b`) are looked through; any other call is
     not (so the kind argument `&"voice"` of `name_of(&"voice", ...)` is never mistaken for a name).
  2. BOUND: it is in the initializer of a constant or variable (`const SFX_TICK := &"lock_tick"`, `const HEADINGS = [&"a", &"b"]`)
     or an argument of a call to a function of the project, and the value flows into such an argument. The flow follows: an identifier
     written inside the argument; an assignment, a `for ... in`, an `.append(...)`; a `return` (a call of a function in an argument
     stands for the function's returned values); the parameters of the project's own functions (`_sprite(&"x")` ... `Assets.ui_picture(picture)`).
     Constants are followed across files (`Audio.SONG_TITLE`), variables only inside their file. A call is followed into the one
     function it reaches: of this script or the one it extends, of `ClassName.` or `Autoload.`, or of a variable's declared class
     (`_Program` says how); a call on anything else is not followed.
  3. A PATTERN: `StringName("log_entry_%d" % n)` builds a run of names at run time. The runs the code may build are declared in
     name_runs.json (kind, prefix, first and last number) and the static check compares them with the registry.

What it cannot see (the blind spots, listed again by test_code_names.py): a name that reaches a resolver through a signal connected to a
callable, a call on a value whose class is not written down (`a.b.f()`, an untyped variable, an inner class), a property or a member
variable of another object, a container filled in another file, a Callable or `call()` by name, or a data file; and a name built by
concatenation that is not `StringName("..._%d" % n)`. A literal that is not bound to a kind is never rewritten by the rename tool, only
reported.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# A node of the flow graph: ("fn", path, function), (path, constant), (path, function, local), ("arg", path, token) or ("?", constant).
Node = tuple[Any, ...]

# ----------------------------------------------------------------------------------------------------------------------
# What takes a name of which kind.

# Calls with a fixed meaning: method name -> (kind, positions of the name arguments, receiver). The receiver is the identifier written
# right before the method (`Catalog.text`); None accepts any (or no) receiver.
SINK_METHODS: dict[str, tuple[str | None, set[int] | None, str | None]] = {
    "text": ("text", {0}, "Catalog"),
    "ui_picture": ("ui_picture", {0}, "Assets"),
    "problem_art": ("problem_art", {0}, "Assets"),
    "play_sfx": ("sound", {0}, None),
    "play_voice": ("voice", {0}, None),
    "play_voice_sequence": ("voice", {0}, None),
    "play_music": ("music", {0}, None),
    "stream_named": (None, {0}, None),            # the kind comes from the receiver (sfx_catalog() / music_catalog() / voice_index())
    "transcript_named": ("voice", {0}, None),
    "ticks_named": ("voice", {0}, None),          # the recorded length of a clip (VoiceIndex.durations)
    "speak": ("voice", {0}, "Audio"),             # await Audio.speak(clips): the clips are voice names
}
# `<signal>.emit(name)`: the events that carry a name.
SIGNAL_KINDS = {"sfx_requested": "sound", "sound_requested": "sound", "sfx_played": "sound", "voice_played": "voice", "voice_started": "voice", "music_changed": "music"}
# Calls whose first argument says the kind and whose second is the name: index_of(&"sound", "begin", scope).
KIND_FIRST = {"index_of": 1, "explain_unknown": 1, "number_of": 1}
# The files that implement the resolvers. A value that is passed into them has reached its sink; following it through their
# internals (tables keyed by every kind) would only mix the kinds up.
RESOLVER_FILES = {"name_registry.gd", "catalog.gd", "assets.gd", "sfx_catalog.gd", "music_catalog.gd", "voice_index.gd", "voice_cues.gd", "foe_names.gd"}
KINDS = ("sound", "frame", "deco", "music", "voice", "ui_picture", "problem_art", "text", "zone", "sector", "foe", "screen", "flag")
# Calls that only hand their argument on.
TRANSPARENT = {"StringName", "String", "str"}

NAME_SHAPE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
PATTERN = re.compile(r"^([a-z][a-z0-9_]*_)%0?[0-9]*d$")
CONSTANT = re.compile(r"^[A-Z][A-Z0-9_]*$")


# ----------------------------------------------------------------------------------------------------------------------
# The lexer.

@dataclass
class Token:
    kind: str                 # "id" "str" "num" "op" "nl" "comment"
    start: int
    end: int
    line: int                 # 1-based
    text: str                 # the source text of the token
    prefix: str = ""          # str only: "&" (StringName), "^", "$", "r" or ""
    value: str = ""           # str only: the characters between the quotes


def lex(source: str) -> list[Token]:
    """Tokens of a GDScript file. A line ends a statement ("nl") only outside brackets."""
    tokens: list[Token] = []
    i, n, line, depth = 0, len(source), 1, 0
    while i < n:
        c = source[i]
        if c == "\n":
            if depth == 0:
                tokens.append(Token("nl", i, i + 1, line, "\n"))
            line += 1
            i += 1
        elif c in " \t\r":
            i += 1
        elif c == "\\" and i + 1 < n and source[i + 1] in "\r\n":
            i += 2 if source[i + 1] == "\n" else 3
            line += 1
        elif c == "#":
            j = source.find("\n", i)
            j = n if j < 0 else j
            tokens.append(Token("comment", i, j, line, source[i:j]))
            i = j
        elif c in "\"'" or (c in "&^$" and i + 1 < n and source[i + 1] in "\"'") or (c == "r" and i + 1 < n and source[i + 1] in "\"'"):
            start = i
            prefix = ""
            if c in "&^$r":
                prefix = c
                i += 1
            quote = source[i]
            triple = source.startswith(quote * 3, i)
            i += 3 if triple else 1
            body = i
            while i < n:
                if source[i] == "\\" and prefix != "r":
                    i += 2
                elif triple and source.startswith(quote * 3, i) or not triple and source[i] == quote:
                    break
                else:
                    i += 1
            value = source[body:i]
            i += 3 if triple else 1
            tokens.append(Token("str", start, min(i, n), line, source[start:i], prefix, value))
            line += source.count("\n", start, i)
        elif c.isalpha() or c == "_":
            j = i + 1
            while j < n and (source[j].isalnum() or source[j] == "_"):
                j += 1
            tokens.append(Token("id", i, j, line, source[i:j]))
            i = j
        elif c.isdigit():
            j = i + 1
            while j < n and (source[j].isalnum() or source[j] in "._"):
                j += 1
            tokens.append(Token("num", i, j, line, source[i:j]))
            i = j
        else:
            two = source[i:i + 2]
            text = two if two in (":=", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "->", "&&", "||", "<<", ">>") else c
            if text in "([{":
                depth += 1
            elif text in ")]}":
                depth = max(0, depth - 1)
            tokens.append(Token("op", i, i + len(text), line, text))
            i += len(text)
    return tokens


# ----------------------------------------------------------------------------------------------------------------------
# What the scan reports.

@dataclass
class Literal:
    """A string literal that is (probably) a name. `kinds` is empty when nothing binds it to a kind."""
    path: Path
    line: int
    start: int                # offset in the file of the whole token (prefix and quotes included)
    end: int
    value: str
    prefix: str
    how: str                  # "direct" | "bound" | "comment" | "other"
    kinds: set[str] = field(default_factory=set)
    via: str = ""             # for "bound": the constant or variable; for "direct": the call


@dataclass
class Pattern:
    """A run of names built at run time: `StringName("log_entry_%d" % n)`."""
    path: Path
    line: int
    start: int
    end: int
    prefix: str               # "log_entry_"
    kinds: set[str]           # from the call it is an argument of; empty if none
    text: str                 # the literal as written


@dataclass
class Scan:
    literals: list[Literal] = field(default_factory=list)
    patterns: list[Pattern] = field(default_factory=list)


def _match_brackets(tokens: list[Token]) -> dict[int, int]:
    """Index of every opening bracket -> the index of its closing one."""
    stack: list[int] = []
    match: dict[int, int] = {}
    for i, t in enumerate(tokens):
        if t.kind != "op":
            continue
        if t.text in "([{":
            stack.append(i)
        elif t.text in ")]}" and stack:
            match[stack.pop()] = i
    return match


def _split_args(tokens: list[Token], open_at: int, close_at: int) -> list[tuple[int, int]]:
    """(first, last+1) token indexes of each argument between the brackets, split on the commas of depth one."""
    args: list[tuple[int, int]] = []
    depth, first = 0, open_at + 1
    for i in range(open_at + 1, close_at):
        t = tokens[i]
        if t.kind == "op" and t.text in "([{":
            depth += 1
        elif t.kind == "op" and t.text in ")]}":
            depth -= 1
        elif t.kind == "op" and t.text == "," and depth == 0:
            args.append((first, i))
            first = i + 1
    if first < close_at:
        args.append((first, close_at))
    return args


LITERAL_WORDS = {"null", "true", "false", "self", "super", "int", "float", "bool", "String", "Array", "Dictionary", "PI", "TAU", "INF", "NAN"}
KEYWORDS = {"if", "else", "elif", "and", "or", "not", "in", "is", "as", "return", "await", "while", "for", "match", "when", "pass", "yield"}


def _walk(tokens: list[Token], match: dict[int, int], first: int, last: int):
    """The tokens of [first, last) that are passed on as they are: yields (index, innermost transparent wrapper or "") for each,
    skipping the inside of every call that is not a wrapper and of every subscript."""
    i = first
    stack: list[str] = []                     # per open transparent group: the wrapper's name ("" for plain brackets)
    closers: list[int] = []
    while i < last:
        t = tokens[i]
        if closers and i == closers[-1]:
            closers.pop()
            stack.pop()
            i += 1
            continue
        if t.kind == "op" and t.text in "([{" and i in match:
            before = tokens[i - 1] if i > 0 else None
            named = before is not None and before.kind == "id" and before.text not in KEYWORDS
            if t.text == "(" and named and before is not None and before.text not in TRANSPARENT:
                i = match[i] + 1                     # an ordinary call: its arguments are its own business
                continue
            if t.text == "[" and (named or (before is not None and before.text in (")", "]"))):
                i = match[i] + 1                     # a subscript
                continue
            stack.append(before.text if (t.text == "(" and named and before is not None) else "")
            closers.append(match[i])
            i += 1
            continue
        yield i, (stack[-1] if stack else "")
        i += 1


def _sink(path: Path, tokens: list[Token], i: int, match: dict[int, int]):
    """If tokens[i] opens a call that takes names: (kinds, positions of the name arguments or None for all, the arguments)."""
    if not (tokens[i].kind == "op" and tokens[i].text == "(" and i in match and i > 0 and tokens[i - 1].kind == "id"):
        return None
    method = tokens[i - 1].text
    receiver = tokens[i - 3].text if i >= 3 and tokens[i - 2].text == "." and tokens[i - 3].kind == "id" else ""
    args = _split_args(tokens, i, match[i])
    if method == "emit" and receiver in SIGNAL_KINDS:
        return {SIGNAL_KINDS[receiver]}, {0}, args
    if method in KIND_FIRST and args:
        first = tokens[args[0][0]:args[0][1]]
        if len(first) == 1 and first[0].kind == "str" and first[0].prefix == "&" and first[0].value in KINDS:
            return {first[0].value}, {KIND_FIRST[method]}, args
        return None
    if method in SINK_METHODS:
        kind, positions, need = SINK_METHODS[method]
        if need is not None and receiver != need:
            return None
        if kind is None:                                   # stream_named: the kind is in the receiver chain before it
            chain = " ".join(x.text for x in tokens[max(0, i - 8):i - 1]).lower()
            kind = "sound" if "sfx" in chain else "music" if "music" in chain else "voice" if "voice" in chain else None
            if kind is None:
                return None
        return {kind}, positions, args
    return None


def _statements(tokens: list[Token]) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    first = 0
    for i, t in enumerate(tokens):
        if t.kind == "nl":
            if i > first:
                out.append((first, i))
            first = i + 1
    if first < len(tokens):
        out.append((first, len(tokens)))
    return out


def _idents(tokens: list[Token], match: dict[int, int], first: int, last: int) -> list[tuple[str, bool, int]]:
    """The identifiers whose value an expression passes on, as (name, is it called, token index): those written in the expression itself,
    not inside the arguments of another call or a subscript, and not members of another value (but `Class.CONSTANT` and called methods)."""
    out: list[tuple[str, bool, int]] = []
    for i, _wrapper in _walk(tokens, match, first, last):
        t = tokens[i]
        if t.kind != "id" or t.text in KEYWORDS or t.text in TRANSPARENT or t.text in LITERAL_WORDS:
            continue
        called = i + 1 < last and tokens[i + 1].text == "("
        if i > first and tokens[i - 1].text == "." and not CONSTANT.match(t.text) and not called:
            continue
        out.append((t.text, called, i))
    return out


def autoloads(godot: Path) -> dict[str, Path]:
    """The autoload singletons of project.godot: name -> script (an `Audio.play_jingle(...)` call goes to src/autoload/audio.gd)."""
    project = godot / "project.godot"
    if not project.is_file():
        return {}
    out: dict[str, Path] = {}
    section = ""
    for line in project.read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            section = line.strip()
        elif section == "[autoload]" and "=" in line:
            name, value = line.split("=", 1)
            script = value.strip().strip('"').lstrip("*")
            if script.startswith("res://") and script.endswith(".gd"):
                out[name.strip()] = godot / script[len("res://"):]
    return out


class _Program:
    """Everything the scan learns about a set of scripts, and the flow graph between its identifiers.

    WHICH FUNCTION A CALL REACHES. A function's parameters and returned values are nodes of the file that defines it
    (`(file, function, parameter)`, `("fn", file, function)`), and a call is tied to the definition it reaches, never to every function
    of the same name: a bare call or `self.f()` to this file (or the script it extends), `ClassName.f()` or `Autoload.f()` to that
    script, `x.f()` to the script named by x's declared type (`var x: ClassName`, `x := ClassName.new()`, a parameter `x: ClassName`).
    A call whose script cannot be told this way (`a.b.f()`, an untyped variable, an inner class, an engine type) is not followed.
    (Matching by name alone tied `cast.bind(&"ship", ...)` in a cutscene, through `bind` of sub.gd and some twenty other same-named
    functions, to `Catalog.text`, so cast keys were checked as texts.)"""

    def __init__(self, files: dict[Path, str], autoload_scripts: dict[str, Path] | None = None) -> None:
        self.result = Scan()
        self.toks: dict[Path, list[Token]] = {}
        self.match: dict[Path, dict[int, int]] = {}
        self.stmts: dict[Path, list[tuple[int, int]]] = {}
        self.consts: dict[Path, set[str]] = {}               # path -> the constants / variables declared at the start of a statement
        self.defs: dict[Path, dict[str, list[str]]] = {}      # path -> function name -> parameter names (the top-level functions)
        self.classes: dict[str, Path] = {}                     # class_name -> its script
        self.parent: dict[Path, str] = {}                      # path -> what it extends (a class_name or a res:// path)
        self.types: dict = {}                                  # node -> the class it is declared as
        self.scripts: dict[str, Path] = {n: p for n, p in (autoload_scripts or {}).items() if p in files}
        self.declared: dict = {}                               # node -> [Literal]
        self.edges: dict = {}                                  # node -> the nodes it is assigned from
        self.demand: dict = {}                                 # node -> the kinds it is handed to a resolver as
        self.made: dict[tuple[Path, int], Literal] = {}
        self.owner: dict[Path, list[str | None]] = {}          # per token: the function it is written in (None at class level)
        for path, source in files.items():
            tokens = self.toks[path] = [t for t in lex(source) if t.kind != "comment"]
            self.match[path] = _match_brackets(tokens)
            self.stmts[path] = _statements(tokens)
            self.consts[path] = set()
            self.defs[path] = {}
            self.owner[path] = [None] * len(tokens)
            current = None
            for first, last in self.stmts[path]:
                head = first
                while head < last and tokens[head].text == "static":
                    head += 1
                indent = tokens[first].start - (source.rfind("\n", 0, tokens[first].start) + 1)
                if indent == 0:
                    current = tokens[head + 1].text if head + 2 < last and tokens[head].text == "func" and tokens[head + 1].kind == "id" else None
                for i in range(first, last):
                    self.owner[path][i] = current
                if indent == 0 and head + 1 < last and tokens[head].text == "class_name" and tokens[head + 1].kind == "id":
                    self.classes[tokens[head + 1].text] = path
                elif indent == 0 and head + 1 < last and tokens[head].text == "extends":
                    self.parent[path] = tokens[head + 1].value if tokens[head + 1].kind == "str" else tokens[head + 1].text
                elif indent == 0 and head + 1 < last and tokens[head].text in ("const", "var") and tokens[head + 1].kind == "id":
                    self.consts[path].add(tokens[head + 1].text)
                elif indent == 0 and current is not None and head + 2 < last and tokens[head + 2].text == "(":
                    args = _split_args(tokens, head + 2, self.match[path].get(head + 2, last))
                    params = [tokens[a].text for a, _b in args if tokens[a].kind == "id"]
                    self.defs[path][current] = params
                    for a, b in args:                            # `x: ClassName` (a default after `=` changes nothing)
                        if b - a >= 3 and tokens[a].kind == "id" and tokens[a + 1].text == ":" and tokens[a + 2].kind == "id":
                            self.types[(path, current, tokens[a].text)] = tokens[a + 2].text
        for path in self.toks:                                   # declared types, once every file's members are known
            tokens = self.toks[path]
            for first, last in self.stmts[path]:
                head = first
                while head < last and tokens[head].text == "static":
                    head += 1
                if head + 3 < last and tokens[head].text in ("var", "for") and tokens[head + 1].kind == "id":
                    if tokens[head + 2].text == ":" and tokens[head + 3].kind == "id":
                        declared = tokens[head + 3].text                       # var x: ClassName / for x: ClassName in
                    elif tokens[head + 2].text == ":=" and head + 5 < last and tokens[head + 4].text == "." and tokens[head + 5].text == "new":
                        declared = tokens[head + 3].text                       # var x := ClassName.new(...)
                    else:
                        continue
                    self.types[self.node(path, tokens[head + 1].text, head + 1)] = declared

    def script_of(self, name: str) -> Path | None:
        """The script a class_name, an autoload or a `res://` path names (None for an engine class or an inner class)."""
        if name in self.classes:
            return self.classes[name]
        if name in self.scripts:
            return self.scripts[name]
        if name.startswith("res://"):
            return next((p for p in self.toks if p.as_posix().endswith("/" + name[len("res://"):])), None)
        return None

    def targets(self, path: Path, at: int) -> list[Path]:
        """The script whose function the call written at token `at` reaches (the method's name), as a list of none or one."""
        tokens, name = self.toks[path], self.toks[path][at].text
        start: Path | None = path
        if at >= 1 and tokens[at - 1].text == ".":
            receiver = tokens[at - 2] if at >= 2 else None
            if receiver is None or receiver.kind != "id" or (at >= 3 and tokens[at - 3].text == "."):
                return []                                         # `f().g()`, `a[0].g()`, `a.b.g()`: whose g is not known
            if receiver.text == "super":
                start = self.script_of(self.parent.get(path, ""))
            elif receiver.text != "self":
                declared = self.types.get(self.node(path, receiver.text, at - 2))
                start = self.script_of(declared if declared is not None else receiver.text)
        seen: set[Path] = set()
        while start is not None and start not in seen:
            if name in self.defs.get(start, {}):
                return [start]
            seen.add(start)
            start = self.script_of(self.parent.get(start, ""))
        return []

    def node(self, path: Path, name: str, at: int) -> Node:
        """The flow node of an identifier written at token `at`: a member / constant of the file, or a local of its function."""
        if name in self.consts[path]:
            return (path, name)
        if CONSTANT.match(name):                              # a constant of another file (`Audio.SONG_TITLE`)
            owners = [p for p, names in self.consts.items() if name in names]
            return (owners[0], name) if len(owners) == 1 else ("?", name)
        return (path, self.owner[path][at], name)

    def name_node(self, path: Path, name: str, called: bool, at: int) -> Node | None:
        """The node of an identifier; a called one is the function's returned values (only for the functions the project defines)."""
        if called:
            found = self.targets(path, at)
            return ("fn", found[0], name) if found else None
        return self.node(path, name, at)

    def literal(self, path: Path, index: int, how: str, kinds: set[str], via: str) -> Literal:
        t = self.toks[path][index]
        found = self.made.get((path, index))
        if found is None:
            found = self.made[(path, index)] = Literal(path, t.line, t.start, t.end, t.value, t.prefix, "other")
            self.result.literals.append(found)
        found.kinds |= kinds
        if how == "direct" or found.how == "other":
            found.how, found.via = how, via
        return found

    def is_kind_argument(self, lit: Literal) -> bool:
        """`&"sound"` as the first argument of a call: it names a kind of the registry, not a name of it."""
        if lit.value not in KINDS:
            return False
        tokens = self.toks[lit.path]
        at = next((i for i, t in enumerate(tokens) if t.start == lit.start), 0)
        return at > 0 and tokens[at - 1].text == "(" and tokens[at + 1].text == ","

    def literals_in(self, path: Path, first: int, last: int) -> list[int]:
        """Indexes of the StringName literals that an expression passes on (not the keys of a dictionary literal)."""
        tokens = self.toks[path]
        return [i for i, _w in _walk(tokens, self.match[path], first, last)
                if tokens[i].kind == "str" and tokens[i].prefix == "&" and NAME_SHAPE.fullmatch(tokens[i].value)
                and not (i + 1 < len(tokens) and tokens[i + 1].text == ":" and tokens[i - 1].text in ("{", ","))]

    def pseudo(self, path: Path, first: int, last: int) -> Node | None:
        """A node for the literals written inside the expression tokens[first:last] (None if it has none)."""
        indexes = self.literals_in(path, first, last)
        if not indexes:
            return None
        node = ("arg", path, first)
        self.declared.setdefault(node, []).extend(self.literal(path, i, "other", set(), "") for i in indexes)
        return node

    def sources(self, path: Path, first: int, last: int) -> set[Node]:
        """The nodes an expression takes its value from: identifiers, functions that are called, and its own literals."""
        out: set[Node] = set()
        for name, called, at in _idents(self.toks[path], self.match[path], first, last):
            found = self.name_node(path, name, called, at)
            if found is not None:
                out.add(found)
        extra = self.pseudo(path, first, last)
        if extra is not None:
            out.add(extra)
        return out

    def run(self) -> Scan:
        for path in self.toks:
            self.sinks(path)
            self.flows(path)
        reached: dict = {}
        todo = list(self.demand.items())
        while todo:
            node, kinds = todo.pop()
            have = reached.setdefault(node, set())
            if kinds <= have:
                continue
            have |= kinds
            todo.extend((source, kinds) for source in self.edges.get(node, ()))
        for node, kinds in reached.items():
            for lit in self.declared.get(node, ()):
                if lit.path.name in RESOLVER_FILES or lit.path.name == "foe_ops.gd" or self.is_kind_argument(lit):
                    continue                                  # a kind (`&"sound"`), not a name of the kind
                lit.kinds |= kinds
                if lit.how != "direct":
                    lit.how, lit.via = "bound", node[1] if len(node) == 2 else "(argument)"
        return self.result

    def sinks(self, path: Path) -> None:
        """Direct sinks: the name arguments of every call that takes names, and the patterns inside them."""
        tokens, match = self.toks[path], self.match[path]
        for i in range(len(tokens)):
            sink = _sink(path, tokens, i, match)
            if sink is None:
                continue
            kinds, positions, args = sink
            for k, (a, b) in enumerate(args):
                if positions is not None and k not in positions:
                    continue
                for name, called, at in _idents(tokens, match, a, b):
                    node = self.name_node(path, name, called, at)
                    if node is not None:
                        self.demand.setdefault(node, set()).update(kinds)
                for index, wrapper in _walk(tokens, match, a, b):
                    t = tokens[index]
                    if t.kind != "str":
                        continue
                    pattern = PATTERN.match(t.value) if t.value.count("%") == 1 else None
                    if pattern and (wrapper == "StringName" or t.prefix == "&"):
                        self.result.patterns.append(Pattern(path, t.line, t.start, t.end, pattern.group(1), set(kinds), t.text))
                    elif NAME_SHAPE.fullmatch(t.value) and (t.prefix == "&" or _bare_string(tokens, a, b, index)):
                        self.literal(path, index, "direct", kinds, tokens[i - 1].text)
        known = {(p.path, p.start) for p in self.result.patterns}
        for i, t in enumerate(tokens):                       # patterns outside a sink: StringName("..._%d" % n)
            if t.kind == "str" and t.value.count("%") == 1 and (path, t.start) not in known:
                pattern = PATTERN.match(t.value)
                if pattern and (t.prefix == "&" or (i >= 2 and tokens[i - 1].text == "(" and tokens[i - 2].text == "StringName")):
                    self.result.patterns.append(Pattern(path, t.line, t.start, t.end, pattern.group(1), set(), t.text))

    def flows(self, path: Path) -> None:
        """Declarations, assignments, loops, returns, `.append` and calls of the project's own functions: where a value goes."""
        tokens, match = self.toks[path], self.match[path]
        for first, last in self.stmts[path]:
            head = first
            while head < last and tokens[head].text == "static":
                head += 1
            if head >= last:
                continue
            word = tokens[head].text
            current = self.owner[path][head]                     # the top-level function (None in an inner class)
            if word == "func":
                pass
            elif word == "return" and current is not None:
                self.edges.setdefault(("fn", path, current), set()).update(self.sources(path, head + 1, last))
            elif word == "for" and head + 1 < last and tokens[head + 1].kind == "id":
                in_at = next((i for i in range(head + 2, last) if tokens[i].text == "in" and _depth0(tokens, match, head, i)), None)
                if in_at is not None:
                    colon = next((i for i in range(in_at, last) if tokens[i].text == ":" and _depth0(tokens, match, in_at, i)), last)
                    self.edges.setdefault(self.node(path, tokens[head + 1].text, head + 1), set()).update(self.sources(path, in_at + 1, colon))
            else:
                self.assignment(path, head, last)
            # `name.append(expr)` and calls of functions the project defines
            for i in range(first, last):
                if not (tokens[i].text == "(" and i in match and i > first and tokens[i - 1].kind == "id"):
                    continue
                method = tokens[i - 1].text
                args = _split_args(tokens, i, match[i])
                if method in ("append", "push_back", "push_front") and i >= first + 3 and tokens[i - 2].text == "." and tokens[i - 3].kind == "id":
                    target = self.node(path, tokens[i - 3].text, i - 3)
                    for a, b in args:
                        self.edges.setdefault(target, set()).update(self.sources(path, a, b))
                for def_path in self.targets(path, i - 1):
                    if def_path.name in RESOLVER_FILES:
                        continue                              # the resolvers are the sinks themselves: a name goes into them and stops
                    params = self.defs[def_path][method]
                    for k, (a, b) in enumerate(args[:len(params)]):
                        self.edges.setdefault((def_path, method, params[k]), set()).update(self.sources(path, a, b))

    def assignment(self, path: Path, head: int, last: int) -> None:
        tokens, match = self.toks[path], self.match[path]
        word = tokens[head].text
        if word in ("const", "var") and head + 1 < last and tokens[head + 1].kind == "id":
            target, rest = tokens[head + 1].text, head + 2
        elif tokens[head].kind == "id" and word not in KEYWORDS:
            target, rest = word, head + 1
        else:
            return
        assign = next((i for i in range(rest, last) if tokens[i].text in ("=", ":=") and _depth0(tokens, match, rest, i)), None)
        if assign is None:
            return
        node = self.node(path, target, head)
        self.edges.setdefault(node, set()).update(self.sources(path, assign + 1, last))
        if word in ("const", "var"):
            self.declared.setdefault(node, []).extend(self.literal(path, i, "other", set(), "") for i in self.literals_in(path, assign + 1, last))


def scan_sources(files: dict[Path, str], autoload_scripts: dict[str, Path] | None = None) -> Scan:
    """Scan several scripts together (constants are followed across files). `files` maps a path to its source; `autoload_scripts`
    (see autoloads()) lets `Audio.f(...)` reach the autoload's script."""
    return _Program(files, autoload_scripts).run()


def _bare_string(tokens: list[Token], a: int, b: int, index: int) -> bool:
    """Is the argument tokens[a:b] only the string at `index` (maybe wrapped in StringName(...))?"""
    inner = [t for t in tokens[a:b] if t.text not in ("(", ")") and t.text not in TRANSPARENT]
    return len(inner) == 1 and tokens[index] is inner[0]


def _depth0(tokens: list[Token], match: dict[int, int], first: int, at: int) -> bool:
    """Is tokens[at] outside every bracket that opens at or after `first`?"""
    for i in range(first, at):
        if tokens[i].kind == "op" and tokens[i].text in "([{" and i in match and match[i] > at:
            return False
    return True


# ----------------------------------------------------------------------------------------------------------------------
# Comments, and the files to scan.

COMMENT_NAME = re.compile(r"&\"([a-z][a-z0-9_]*)\"")


def comment_literals(files: dict[Path, str]) -> list[Literal]:
    """`&"name"` written inside a comment (a doc comment that shows how to call a resolver)."""
    out: list[Literal] = []
    for path, source in files.items():
        for t in lex(source):
            if t.kind != "comment":
                continue
            for m in COMMENT_NAME.finditer(t.text):
                out.append(Literal(path, t.line, t.start + m.start(), t.start + m.end(), m.group(1), "&", "comment"))
    return out


# The addons of the project itself (the other folders of godot/addons are third party).
OWN_ADDONS = ("foe_script_editor", "screen_editor")


def code_files(godot: Path, tests: bool = True) -> list[Path]:
    """The scripts the registry's names may be written in: src/, the project's own addons, and (optionally) tests/."""
    roots = [godot / "src"] + [godot / "addons" / a for a in OWN_ADDONS] + ([godot / "tests"] if tests else [])
    return sorted(p for root in roots if root.is_dir() for p in root.rglob("*.gd"))


def scan_tree(godot: Path, tests: bool = False) -> Scan:
    files = {p: p.read_text(encoding="utf-8") for p in code_files(godot, tests)}
    return scan_sources(files, autoloads(godot))


# ----------------------------------------------------------------------------------------------------------------------
# The check itself (test_code_names.py), here so that the rename tool and a test of the check can use it too.

def known_names(registry: dict) -> dict[str, set[str]]:
    """kind -> every real name of the kind, in any scope (a scoped name is looked up in a scope that only the running code knows)."""
    found: dict[str, set[str]] = {}
    for kind, node in registry["names"].items():
        tables = node.values() if kind in ("frame", "deco", "foe", "screen", "flag") else [node]
        found[kind] = {name for table in tables for name in table}
    return found


def made_up(kind: str, name: str) -> bool:
    """Is `name` the made-up name of a number of the kind (`sfx_22`, `ui_1039`)? Those always resolve."""
    import rename_name
    return rename_name.fallback_index(kind, name) >= 0


def unresolved(scan: Scan, registry: dict) -> list[Literal]:
    """The literals the scan binds to a kind that resolves to nothing in the registry (in none of the kinds it is bound to)."""
    known = known_names(registry)
    return [lit for lit in scan.literals
            if lit.kinds and not any(lit.value in known.get(kind, ()) or made_up(kind, lit.value) for kind in lit.kinds)]


def run_problems(scan: Scan, registry: dict, runs: dict) -> list[str]:
    """What is wrong between the runs the code builds (name_runs.json, the patterns in the scan) and the registry."""
    known = known_names(registry)
    problems: list[str] = []
    declared = {prefix: kind for kind, table in runs.items() for prefix in table}
    for kind, table in runs.items():
        for prefix, run in table.items():
            missing = set(run.get("missing", []))
            wanted = [prefix + str(n) for n in range(run["first"], run["last"] + 1) if n not in missing]
            for name in wanted:
                if name not in known.get(kind, ()):
                    problems.append("%s: '%s' of the run '%s%%d' (%d to %d) is not a name" % (kind, name, prefix, run["first"], run["last"]))
            extra = sorted(n for n in known.get(kind, ()) if n.startswith(prefix) and n[len(prefix):].isdigit() and n not in wanted)
            if extra:
                problems.append("%s: %s start with '%s' but are outside the run %d to %d of name_runs.json" % (kind, ", ".join(extra), prefix, run["first"], run["last"]))
            if not any(p.prefix == prefix for p in scan.patterns):
                problems.append("%s: the run '%s%%d' of name_runs.json is not built anywhere in the code" % (kind, prefix))
    for p in scan.patterns:
        if p.prefix in declared:
            if p.kinds and declared[p.prefix] not in p.kinds:
                problems.append("%s:%d: the run '%s%%d' is declared as %s but handed to a %s resolver" % (p.path.name, p.line, p.prefix, declared[p.prefix], "/".join(sorted(p.kinds))))
        elif p.kinds or any(n.startswith(p.prefix) and n[len(p.prefix):].isdigit() for names in known.values() for n in names):
            problems.append("%s:%d: '%s%%d' builds registry names at run time but is not declared in name_runs.json" % (p.path.name, p.line, p.prefix))
    return problems
