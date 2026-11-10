# Working on this repository (agents)

*Operation Larissa*: a Godot 4.7.2 engine that plays *Operation Neptune* (1998) faithfully, with an importer that builds the original
game's content from the user's own ISO. **Start with [`docs/CODEMAP.md`](docs/CODEMAP.md)**: where every system lives (code, data,
tests, doc), so you do not have to search for it. The human-oriented tour of the same ground is [`docs/OVERVIEW.md`](docs/OVERVIEW.md);
read it only when you need the why.

## Standing rules for documentation

- **Document only what is, never what was.** No "was", "no longer", "used to", "replaces X", "gone", "before the change", "now",
  migrations, removed features or commit references. History is in git. When the code changes, rewrite the sentence that describes it;
  do not annotate it.
- **No work-item or phase ids outside `docs/ROADMAP.md`** (no "G2a", "phase D", "M8", "(ROADMAP F4)" in docs or code comments). Name the
  thing itself and point at the doc that describes it.
- **`docs/ROADMAP.md` is future work only.** When an item is done, delete it from the roadmap and describe the result in the permanent doc
  for its audience, and add or update its line in `docs/CODEMAP.md`.
- **One home per fact.** Before writing, find the doc that owns the topic (CODEMAP lists them) and link to it instead of repeating it.
- **Docs live by audience:** `docs/play/` (build the legacy pack and play), `docs/create/` (content creators: sectors, scripts, campaigns,
  packs, skins), `docs/engine/` (how the Godot code works, developing and testing it), `docs/port/` (the original game, reverse
  engineering, fidelity). A README next to a tool documents only that tool.
- Keep `docs/CODEMAP.md` terse: pointers, not prose. A new system, folder, tool or test helper gets one line there.

## Rules of the code

- **Fidelity.** The port follows the original as read from the asm. `docs/port/DESIGN.md` names functions by name and address
  (`tools/analysis/ghidra/names_onwin32.json`), never as bare `FUN_xxxx`. A found difference goes in `docs/port/PORT_GAPS.md`; when it is
  fixed, a gdUnit4 test pins the fix and the entry is removed. A quirk of the original that hurts play is fixed as a **Deliberate
  deviation**, marked by that phrase in the code comment, a test and `docs/port/DESIGN.md`.
- **Record what Ghidra teaches.** Any Ghidra exploration adds every function name and global or data label it establishes to
  `tools/analysis/ghidra/names_onwin32.json` / `labels_onwin32.json`, in the same commit (subagent briefs included). Look a name up
  with `uv run tools/analysis/ghidra/map_names.py find <name|address>`; a name taken from ONWIN.MAP is written as its `"map"` reference
  (`export_names.py` does it).
- **Keep the port map true.** A change to the Godot architecture (a function, class or file that implements an original routine is
  added, renamed, moved or removed) updates that routine's `where` in `tools/analysis/ghidra/port_map_onwin32.json` (and the
  call-site audit's `audit_rows.py`) in the same commit. `tools/analysis/ghidra/check_port_map.py` (run by `uv run pytest tools`)
  fails on a name the code no longer defines.
- **The three layers.** Rules never change (a pack changes their values through `rules/tuning.json`, and a campaign that declares a sandboxed mod pack gets its rule hooks, `docs/engine/ARCHITECTURE.md` "Rule hooks"); content is data; presentation (skins)
  never changes a rule or a timing. `tests/engine/test_rules_are_plain_objects.gd` and `test_plays_identically.gd` enforce it.
- **No original content in git.** Nothing derived from the ISO (pictures, sounds, texts, levels, scripts, tables) is committed: the legacy
  pack (`godot/packs/legacy`), `extracted/`, the seven ISO tables in `docs/data/` (one is ONWIN.MAP's names: the Ghidra name tables commit a reference to a MAP name, never
  the name, `tools/analysis/ghidra/map_names.py`), `godot/tests/fixtures/original/`. Fixtures commit SHA-256
  hashes of whole records, never bytes. Screenshots of the port (they show the original's art) are never committed.
- **Engine tests run on the dev pack** (`godot/tests/engine/`, never name `LegacyPack` or `res://packs/legacy`); tests of the original's data
  are in `godot/tests/legacy/`.
- **Every field has a lifetime.** Each member variable of a stateful rules or run object (`GameState`, `SimWorld`, `SubModel`) is in one
  of its `*_FIELDS` lists (or `KEPT_FIELDS` with a reason), and the reset that clears a lifetime cites the original routine it mirrors
  (name and address) and what that routine zeroes. `tests/engine/test_state_lifetimes.gd` enforces it; `docs/engine/ARCHITECTURE.md`
  ("Lifetimes of state") lists the lifetimes.
- **Derive, don't patch.** State has one owner (the rules, the run, the pack chain). A copy of it (a creature context, a view's nodes,
  a cache) is made by one builder that reads every field from the owner's live state, and every path (first load, reload, respawn, a
  presenter bound mid-sector, a skin or pack change, a debug key, a test harness) calls that builder or the game's own entry point,
  never a subset of its steps. `docs/engine/ARCHITECTURE.md` ("Derived state is built from its owner") states the parts and the tests.
- **Code is teaching material.** A script starts with a header comment saying what it is and, for most files, a `## Teaches:` line
  (`docs/engine/TEACHING.md` indexes them); give a new file one.

## Tools

- **Every tool fact lives in `docs/SETUP.md`**: what to install, for the engine and for the importer, and the policy. mise is the
  default and supported source of every tool it has (`mise.toml` pins uv, Godot and a JDK), and users may opt out with their
  own installs; others come from the system's packages, documented for Fedora. Only Linux is tested.
- **Scripts call plain names** (`uv`, `godot`, `ffmpeg`), never `mise exec`, so other installs still run. Godot goes through
  `tools/godot.sh`; a Python tool asks `tools/godot.py` (`command()`), which is that wrapper on Linux and finds Godot itself on Windows.
- **Windows runs the importer and the game** (`docs/SETUP.md`, "On Windows"). A Python entry point calls `utf8_mode.ensure()` first; a
  text file a tool writes is written as bytes or with `newline="\n"`; a mise task that calls a bash script has a `run_windows`.
- **A new external program** a tool calls gets a check in `tools/import/tool_check.py` (when the importer calls it), a pin in
  `mise.toml` when mise has it, and its row in `docs/SETUP.md`.

## Git

We work on `main`: commit there directly; do not create a branch unless asked.

## Commands

```sh
tools/godot.sh --headless --path godot --import          # once in a fresh checkout, and after the importer or new assets
tools/run_tests.sh [engine|legacy] [headless|windowed]   # gdUnit4; or a path: tools/run_tests.sh tests/engine/test_catalog.gd
uv run pytest tools -m "not legacy"                      # Python tests that need no legacy pack (drop -m for all)
uv run ruff check tools && uv run --group dev-pack pyright              # Python lint and types
tools/godot.sh --path godot [res://scene.tscn] -- --pack=dev|legacy --skin=<id> ...
```

Which Godot `tools/godot.sh` runs: `docs/SETUP.md`. gdUnit4 stops a file at its first failing test. Reports go to `godot/reports/`.
