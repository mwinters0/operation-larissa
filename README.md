# Operation Larissa

A game engine in Godot 4, capable of playing The Learning Company's *Operation Neptune* 1998
Windows release.  Larissa was a lover of Neptune.

Operation Larissa has several goals (which often compete with each other!):
- [X] A reimplementation of Operation Neptune's engine, capable of running the (extracted) original
  data with full fidelity.
- [X] A learning platform for programming and game dev students -- all code is written to be
  read, and we have extensive docs.
- [ ] Facilitate user-made content:
    - [X] Basic content editing tools (level editors, foe scripting grammar, etc)
    - [X] "Data packs": packaged art, sounds, levels, scripts, game rules.  These can exist as
      "overrides" to another pack (for example, keeping the original levels but replacing the art), or as
      fully-standalone "base" packs.  They contain no code.
        - [ ] A fully original base content pack should be included!
    - [ ] Mods -- fully custom problem types, shaders, etc.
- [ ] Maybe someday
    - [ ] Support other games of that era which use similar engines.

**This repository contains none of the original game's content.**  To play it, an importer generates
the *"legacy pack"* from your copy of the game. Without the legacy pack, the game runs on the *dev
pack*, which is placeholder content not intended for gameplay -- it mainly exists to give our tests
something to test.

## Documentation by audience

| You want to ... | Read |
| --- | --- |
| **set up your machine**: the tools, for the engine and for the importer | [`docs/SETUP.md`](docs/SETUP.md) |
| **play the original game**: build it from your CD image, run it, put it in an exported build | [`docs/play/LEGACY.md`](docs/play/LEGACY.md) |
| **make content**: understand how content works | [`docs/create/CONTENT.md`](docs/create/CONTENT.md) |
| ... make sectors, creatures, a campaign, a pack or a skin (tutorial and reference) | [`docs/create/MAKING_CONTENT.md`](docs/create/MAKING_CONTENT.md) |
| ... use one tool in depth | [`SCREEN_EDITOR`](docs/create/SCREEN_EDITOR.md), [`SECTOR_INSPECTOR`](docs/create/SECTOR_INSPECTOR.md), [`FOE_SCRIPTING`](docs/create/FOE_SCRIPTING.md), [`NAMES`](docs/create/NAMES.md), [`SKIN_API`](docs/create/SKIN_API.md) |
| **understand the engine**: what is built and why, in one tour | [`docs/OVERVIEW.md`](docs/OVERVIEW.md) |
| ... how the Godot project works | [`ARCHITECTURE`](docs/engine/ARCHITECTURE.md), [`PACKS`](docs/engine/PACKS.md), [`SKINS`](docs/engine/SKINS.md), [`AUDIO`](docs/engine/AUDIO.md), [`EDITORS`](docs/engine/EDITORS.md), [`HARD_CODED`](docs/engine/HARD_CODED.md) |
| ... run the tests, export builds | [`docs/engine/DEVELOPING.md`](docs/engine/DEVELOPING.md) |
| ... teach with it: which Godot concept each file shows | [`docs/engine/TEACHING.md`](docs/engine/TEACHING.md) |
| **study the port**: how the original behaves | [`docs/port/DESIGN.md`](docs/port/DESIGN.md) |
| ... how fidelity and provenance are kept | [`docs/port/FIDELITY.md`](docs/port/FIDELITY.md) |
| ... known differences, the call-site audit, file formats, Ghidra | [`PORT_GAPS`](docs/port/PORT_GAPS.md), [`AUDIT_CALLSITES`](docs/port/AUDIT_CALLSITES.md), [`ASSET_FORMATS`](docs/port/ASSET_FORMATS.md), [`GHIDRA_GUI`](docs/port/GHIDRA_GUI.md) |
| see what comes next | [`docs/ROADMAP.md`](docs/ROADMAP.md) |

Agents: [`AGENTS.md`](AGENTS.md) and [`docs/CODEMAP.md`](docs/CODEMAP.md).

## Repository layout

| Path | What it holds |
| --- | --- |
| `godot/` | the Godot project: `src/` (code), `addons/` (editor tools), `skins/`, `data/` (project-level data), `names/` (the name registry), `packs/dev/` (the dev pack, committed), `packs/legacy/` (the legacy pack, made by the importer, git-ignored), `tests/` (gdUnit4: `engine/` on dev, `legacy/` on legacy) |
| `examples/` | example packs to copy (`packs/modern/`: a skin pack with no script) |
| `tools/` | `import/` (the importer and reset tools), `extract/` (extractors), `analysis/` (parsers and Ghidra scripts), `dev_pack/` (the dev pack's generator), `gamefiles.py` (reads the ISO), `godot.sh`, `run_tests.sh` |
| `docs/` | the documentation above; `data/` (facts read from the program's code, committed, and the game's tables dumped from your ISO, not committed) |
| `mise.toml` | the pinned tools (`mise install`) and the shortcut tasks (`mise tasks`; [`docs/SETUP.md`](docs/SETUP.md)) |
| `mise.proton.toml` | opt-in tasks for running the original game under Proton (`mise -E proton run play`, [`docs/SETUP.md`](docs/SETUP.md)) |

Never committed (`.gitignore`): `NEPTUNE.ISO`, `extracted/`, the legacy pack, `soundfonts/`, `iso/`, `build/`, `prefix/`, the original
bytes behind the test fixtures, and every screenshot. What is committed and why: [`docs/create/CONTENT.md`](docs/create/CONTENT.md),
section 6.
