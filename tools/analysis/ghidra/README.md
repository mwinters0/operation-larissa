# Headless Ghidra workflow for Operation Neptune

Goal: decompile `ONWINCD/ONWIN32.EXE` from the CD (`NEPTUNE.ISO`; 32-bit PE; decompiles much better than the 16-bit NE `ONWIN.EXE`),
give functions the names from `ONWIN.MAP` (read from your CD, not committed: "Names from ONWIN.MAP" below), and answer questions about the game logic. Uses Ghidra 12.2 headless
through PyGhidra (no GUI). Do **not** analyse the patched copy under `prefix/` (its bytes differ at 0x413c74).

## Requirements
* Ghidra 12.2 and a JDK: [`docs/SETUP.md`](../../../docs/SETUP.md) (`GHIDRA_INSTALL_DIR` overrides where Ghidra is)
* the pure-Python scripts (see the table and "Reproducing the data files") run in the repository's environment: `uv run <script>`
* the game's CD image at `NEPTUNE.ISO` in the repository root (or `NEP_ISO`): the headless scripts take ONWIN32.EXE from it (`tools/gamefiles.py`)
* `docs/data/onwin_map.json`, ONWIN.MAP's names, which the importer's `tables` step writes from the ISO (or `uv run tools/analysis/ghidra/map_names.py write`): every script that reads or writes the name tables needs it
* `run.sh` builds its own `tools/analysis/ghidra/.venv` from the PyGhidra wheels shipped inside Ghidra (separate from the repository's `.venv`; only the scripts that import `ghidra.*` run there, via `./run.sh`), and adds `pycdlib` from PyPI to it so that `tools/gamefiles.py` can read the CD image

To browse the program in the Ghidra GUI with these names applied, run the apply scripts from the GUI, or send GUI renames back to the JSON, see [`docs/port/GHIDRA_GUI.md`](../../../docs/port/GHIDRA_GUI.md).

## Quick start
```zsh
cd tools/analysis/ghidra
export NEP_GHIDRA_PROJECT=/tmp/neptune-ghidra        # where the Ghidra project lives (any scratch dir)
./run.sh apply_problem_types.py                      # 1st run imports + auto-analyses ONWIN32.EXE (~20 s), adds Prob00..33 structs
./run.sh apply_names.py                              # function names + global labels
./run.sh dump_c.py /tmp/all.c                        # decompile everything (852 functions, ~1 min)
./run.sh dump_c.py /tmp/some.c DoMathProblem CheckAnswer 0x425772   # selected functions by name or address
```
Then read `/tmp/all.c` with an editor / `grep`. For example `CheckAnswer` is the whole answer rule table,
`ReadProblemRecord` the record readers, `DoCombinationLock` / `LockRunStage` the lock wheel, `DoAction` the game loop.

## Files
| file | purpose |
|---|---|
| `nepghidra.py` | helpers (open project, decompile, name file loading, idempotent `set_label`, GUI-vs-headless `run`) |
| `run.sh` | creates `.venv` with PyGhidra, runs a script inside it |
| `dump_c.py` | export decompiled C |
| `apply_problem_types.py` | creates struct types for the 34 problem records from `docs/data/problem_layouts32.json` and retypes the globals so the decompiler prints `g_prob03->f2_n`. Runs headless or from the GUI Script Manager; safe to repeat |
| `apply_names.py` | applies `names_onwin32.json` (address -> name + evidence) and `labels_onwin32.json` (globals). Runs headless or from the GUI Script Manager (`pyghidraRun`); safe to repeat |
| `export_names.py` | the reverse: writes user-defined function names / global labels from the program (e.g. renamed in the GUI) that are new or differ into the two JSON files, with an empty `evidence` to fill in. `--dry-run` prints the diff, `--check` also exits 1 when there is something to export; `--dir DIR` redirects the files. Headless or GUI. See [`docs/port/GHIDRA_GUI.md`](../../../docs/port/GHIDRA_GUI.md) |
| `apply_annotations.py`, `export_annotations.py` | the same round trip for everything else you add in the GUI (comments, types, signatures, variables, labels inside functions, equates, Note bookmarks) through `annotations_onwin32.json`; the export tells your work from Ghidra's by a cached fresh import (`--baseline`) and merges three ways. Headless or GUI. See [`docs/port/GHIDRA_GUI.md`](../../../docs/port/GHIDRA_GUI.md) section 8 |
| `annotations.py`, `program_annotations.py` | the annotation file's format and three-way merge (pure Python, `test_annotations.py`), and its Ghidra side (read, write, baseline, record of the last apply) |
| `check_annotations.py` | round trip of the annotation tools on two throw-away projects (every kind of annotation; about 90 s, needs the ISO): run it after changing the two modules above |
| `open_gui.py` | opens the Ghidra GUI (through PyGhidra, so the Script Manager runs our scripts) on the project the scripts above build; `mise run ghidra:gui` runs the two exports with `--check`, the three apply scripts and then this. See [`docs/port/GHIDRA_GUI.md`](../../../docs/port/GHIDRA_GUI.md) |
| `derive_problem_layouts.py` | rebuilds `docs/data/problem_layouts32.json` from a decompilation of `ReadProblemRecord`. Run it on a dump taken **before** `apply_problem_types.py` (it parses the untyped `DAT_` form); the committed JSON is its output |
| `dump_asm.py` | export the disassembly of selected functions (the decompiler drops x87 floating point instructions: read the asm wherever a decompiled function does arithmetic on doubles) |
| `export_diagrams.py` | pure Python: the geometry of every problem diagram (transcribed from `Prob*_Diagram`, tables read from the EXE) -> `docs/data/problem_diagrams.json`, see DESIGN 5.5 |
| `export_opening.py` | pure Python: the opening's crew scripts, light rules, the title scene's ship / sub drop / splash as a per-redraw table (transcribed from OPENING.C, run as state machines) -> `docs/data/opening.json`, see DESIGN 2.1 |
| `export_console.py` | pure Python: the sub console labels / message lights / frame rectangles and the calculator's key hotspots and LCD display geometry (transcribed from `DisplayBezel`, `AddHotspot`, `GetAnswer`, `DrawCalcDisplay`) -> `docs/data/console_layout.json` |
| `export_bubbles.py` | pure Python: the ambient bubbles (BUBBLES.C: spawn rule, speeds, picture order derived by running the state machines, blocked screens) and the DrawSub overlays (hit bubbles, message light tables) -> `docs/data/bubbles.json`, see DESIGN 9 |
| `export_constants.py` | pure Python: dumps music / ink / HUD / lock / ballast / piece / dissolve tables straight from the EXE to `docs/data/*.json` |
| `export_audio.py` | pure Python: the audio cue tables (music ids and files, sound effects and their callers, speech clips per cue, sample rates) -> `docs/data/audio_map.json`, see DESIGN 7 |
| `export_databank.py` | pure Python: the canister log screen's tables (unlock order per game, row positions, speech clips per entry, row caption) -> `docs/data/databank.json`, see DESIGN 7.1 |
| `audit_callsites.py` | every call site of the sound / timing / text / bundle primitives and their wrappers (Ghidra references + resolved switch handlers + a raw `E8`/`E9` scan), with the constant arguments -> JSON |
| `audit_rows.py`, `audit_report.py`, `audit_intro.md` | the hand annotations and the generator for [`docs/port/AUDIT_CALLSITES.md`](../../../docs/port/AUDIT_CALLSITES.md) (fails when a call site has no row) |
| `names_onwin32.json`, `labels_onwin32.json` | the naming work product (each name has an `evidence` note; a name of ONWIN.MAP is a `map` reference) |
| `map_names.py` | ONWIN.MAP's publics: `write` makes `docs/data/onwin_map.json` from the ISO (the importer runs it), `resolve` / `with_name` turn references into names and back for the other scripts, `find TEXT` prints the entries whose name, address or reference contains TEXT, with evidence and port status. `test_map_names.py` checks the format, and (legacy) that no committed name is a MAP name |
| `annotations_onwin32.json` | the annotation work product (written by `export_annotations.py`) |
| `port_map_onwin32.json` | original function -> Godot port status (all 847 named functions; the `name` only where it is ours) |
| `check_port_map.py` | reports every port-code name in the port map's `where` texts and the audit's `port` texts that the code does not define (and every line-number reference); `test_check_port_map.py` runs it in `uv run pytest tools` |

## How the names were matched
`ONWIN.MAP` (16-bit link map) lists every public function per source module (ACCESS.C, ACTION.C, BEZEL.C, MATHPROB.C,
NUMBERS.C ...). The 32-bit build links the same modules in the same order, so a 32-bit function is identified by (1) the
module order, (2) sizes, (3) call structure and constants (e.g. `NumbersClose` is the last of the three small `fabs`
comparators after `NumberCmp`; `DoMathProblem` is the only caller of the 34-way record reader) and (4) strings
(`LoadString` ids, sound ids, `.MID` file names). Static helpers that are not in the MAP got descriptive names
(`ShowProblemHint`, `Prob07_SolutionSubst`). All 852 functions are named (847 in `names_onwin32.json`, 5 Borland
dialog procs keep their imported mangled names; 408 global labels in `labels_onwin32.json`). The statically linked Borland C++ runtime starts at
0x434250 (`strcpy`, `rand`, `sprintf` ...); its exception-handling / RTTI internals are marked `[guess]`. Evidence
containing `[guess]` is a position-only match. Three MAP functions have no Ghidra function yet (code Ghidra did not
disassemble): `get_font` 0x414dbe, `init_anim` 0x4153f9, `do_help` ~0x415b7c.

`port_map_onwin32.json` records, for every named function, whether the Godot port implements it (`ported` + where, `not-ported` + the difference, or `n/a` for platform plumbing / dead code).

## Names from ONWIN.MAP
The MAP is the game's, so its names are not committed. Where a function or global is a MAP public, its entry holds `"map": "SSSS:OOOO"`,
the public's 16-bit address in the MAP's "Publics by Value", instead of `"name"`: the match of the 32-bit address to the 16-bit public is
our work and is committed, the name is read back from your CD. The name is the C name without its one leading underscore
(`_DoMathProblem` -> `DoMathProblem`); names that differ from the MAP's (`Alarms` for `_alarms`, the runtime's `__scanner`, Windows
API names in our case) are ours and committed as `"name"`. The port map leaves out a MAP name (`names_onwin32.json` owns it), the
annotation file writes none. `nepghidra.load_names` / `load_labels` resolve the references for every script; `export_names.py` writes
a GUI name that is a MAP public as its reference. The docs and code comments name routines by name, as a citation.

## Reading the decompiler output
* Win32 build, 4-byte `int`; the Win16 original used 2-byte `int`, so record offsets differ (a CompactNumber is 9 bytes in
  memory, 7 in the file).
* `CompactNumber` arguments are passed by value (3 dwords), so the decompiler shows `CompactNumberToString(kind, a, b, buf)`.
* Timer units are 73 ticks/second (`timeGetTime()*73/1000`); `set_alarm(0, n)` / `alarm_expired(0)` are used everywhere.
* Sound ids are indexes into the common effect bundle (`PlaySoundEffect(0x20)` = right answer).
* The decompiler drops x87 floating-point instructions: wherever a function does arithmetic on doubles, read the assembly
  (`dump_asm.py`, or the Listing in the GUI).
* To resolve a data address to bytes without Ghidra, see `export_constants.py` (small PE reader).

## Reproducing the data files
Run `mise run setup` once at the repository root, then:
```zsh
uv run tools/analysis/decode_problems.py          # docs/data/problem_records.json
uv run tools/analysis/make_problem_fields.py      # docs/data/problem_fields.json
uv run tools/analysis/ghidra/export_constants.py  # music_map / ink_tables / hud_gauges / lock_wheel / ballast / piece_animation / dissolve_tables
uv run tools/analysis/ghidra/export_opening.py    # opening.json (crew, lights, ship, sub drop, splash)
```
