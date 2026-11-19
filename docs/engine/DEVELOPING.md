# Developing: tests, checks, screenshots, builds

Commands run from the repository root. Set up the tools first: [`../SETUP.md`](../SETUP.md), "For the engine" (it ends with the
Godot import a fresh checkout needs before anything else).

## Tests

```sh
tools/run_tests.sh                               # both groups: engine (on the dev pack), then legacy (on the legacy pack); each headless, then its windowed files
tools/run_tests.sh engine                        # one group (or legacy); add headless or windowed for one mode
tools/run_tests.sh tests/engine/test_catalog.gd  # one file or folder (relative to godot/); the folder says the group
uv run pytest tools                              # the Python tests; -m "not legacy" is the half that needs no legacy pack
uv run ruff check tools && uv run --group dev-pack pyright      # Python lint and type check
```

The result of a run is what gdUnit4 itself reports (the `Exit code: N` it prints at the end of its run), not the status of the Godot process, which can die after the tests have finished. The script's exit status:

| Status | Meaning |
| --- | --- |
| 0 | every group passed |
| 1 | a test failed (gdUnit4 reported a code other than 0), or a run printed no `Exit code` (Godot ended before the tests had a verdict) |
| 2 | a path that is under neither `tests/engine` nor `tests/legacy` |
| 3 | every test passed and Godot then ended with a non-zero status (the full engine suite aborts at shutdown: [`../ROADMAP.md`](../ROADMAP.md), "Open items"); the script says so on stderr, in the run and at the end |

A failed test beats a crash after a pass: when both happen the status is 1. Reports go to `godot/reports/`. The script is bash and runs on Linux (Windows has no `run_tests.sh`: its `mise` tasks say so; [`../SETUP.md`](../SETUP.md), "On Windows"). There are two gdUnit4 suites, each on the pack it is about;
the script passes the choice after `--`, where `Packs.start()` reads it:

- **`godot/tests/engine/`** (`-- --pack=dev`): the engine, on the dev pack's own numbers, records and test sectors. It needs no legacy
  pack, no ISO and no ISO-derived table of `extracted/tables/`, and never skips for want of content.
- **`godot/tests/legacy/`** (`-- --pack=legacy`): the original game: the fidelity hashes, the original's numbers and texts, whole
  Voyager and Expert runs ([`../port/FIDELITY.md`](../port/FIDELITY.md)). Without `godot/packs/legacy` the script says so
  and the group passes; a file skips itself with "run the importer on your copy of the game" (`before(do_skip := not
  LegacyPack.present(), ...)`) when a half-finished import lacks what it needs. Python tests that need the legacy pack are marked
  `@pytest.mark.legacy` (`tools/conftest.py`).

**Running the legacy suite on the exported pack.** `NEPTUNE_LEGACY_AS_DATA=1 tools/run_tests.sh legacy` makes `LegacyPack.present()` (the first call) export
legacy in the data form (`PackExport.complete`, no reachability search) to `user://legacy_as_data/legacy`, put that folder first in `Packs.folders` and choose again:
the pack called `legacy` that `--pack=legacy` finds is then the export, not trusted, read through the data form only, so the fidelity tests play the pack
that leaves the project (a few seconds for the export; it is replaced by each run that asks). `LegacyPack.plays_the_export()` says so and
`test_legacy_pack.gd` asserts it. So that a legacy test follows the switch it asks the pack that is played, not the folder: `Packs.source_of(texture)` for the file a picture or
sound came from (a decoded one has no `resource_path`), `Packs.relative(path)` to compare a path with `assets/...`, `Packs.file_at(path)` to open a path a catalog holds,
`LegacyPack.played_foe_text(n)` for a script's `.foe` text. A test that names the authoring files (`LegacyPack.ROOT`, `root()`, `SECTORS_DIR`, a `load(ROOT + "data/....tres")`,
an editor given `LegacyPack.SECTORS_DIR`) still reads the project's folder: it checks the importer's output and the editors, not the pack the game plays. `test_pack_export_legacy.gd` proves the export equal to the folder, with or without the switch.

The headless runs use `--headless` (no window, a dummy renderer, a dummy sound card that still advances playback), so working at the
desktop cannot disturb them. The files that need a window are listed with their reasons in `WINDOWED` at the top of
`tools/run_tests.sh` (`tests/legacy/test_snapshots.gd`, `tests/engine/test_skin_creatures_render.gd` and `tests/engine/test_mod_skin_hud_render.gd` read viewport pixels); headless
they are skipped. With the editor open the godot-ai MCP `test_run` works too. gdUnit4's command tool stops a file at its first failing
test, so a broken file hides the rest of itself.

**Rules of an engine test.** It uses dev's numbers, records and test sectors, never legacy's, and never names `LegacyPack` or
`res://packs/legacy`. It reads a rule value from the run (`GameState.tuning`, `Tuning.resolve()`), never assumes the original's number: dev states
every rule value differently ([`tools/dev_pack/README.md`](../../tools/dev_pack/README.md)); `Tuning.original()` is for a test of a part on its own and
of the project's file. A test that checks only the original's data is a legacy test; a file with both kinds is cut in two (`test_x.gd`
for the engine, `test_x_legacy.gd`). A test that borrows the chain puts it back with `Packs.start()` (the command-line choice again), not
`Packs.choose`; a test that starts a second Godot hands the choice on (`PackShelf.pin_args()`). Engine tests that still need something
only the original has are the record of what is hard-coded ([`HARD_CODED.md`](HARD_CODED.md)). **A test never writes the player's own data**: the installed packs
(`Packs.installed_dir`) and the pack remembered for the next start (`PackChoice.memory_path`) belong to whoever runs the tests, so a test that installs, uninstalls or lists packs, presses Use on the pack
screen or runs the pack tool calls `Scratch.isolate_user_data()` in `before_test` and `Scratch.release_user_data()` last in `after_test` (a second Godot it starts is told the folder with
`--packs-dir=`). It names neither place itself, and it passes on a machine that has a pack installed. **A test leaves nothing in `user://`**: every folder or file it makes is a `Scratch` place
(`Scratch.folder(name)` a fresh empty folder, `Scratch.path(name)` a file's path; `PackShelf` and `CampaignShelf` make theirs there) and it deletes what it made in `after_test` (a shelf is
`remove`d, or it stays in `Packs.folders` for the rest of the process; a test that makes the game save a setting or a roster points `Audio.settings_path`, `MachineSettings.settings_path`, `SaveStore.roster_path` at a `Scratch.path` first). `test_tests_leave_user_data_alone.gd` scans `tests/` for both rules: a script that names the two places of the player's data, or
writes a `"user://` path of its own (it lists the few it may: paths that are only asked about and are never made, `user://snapshots/`, where the render tests leave pictures for a human to look at, and the cache of `NEPTUNE_LEGACY_AS_DATA` in `LegacyPack`).

**Helpers** (`godot/tests/`). Engine: `engine/dev_pack.gd` (`DevPack`: dev's root, `sector(n)`, the tour's numbers, the test-sector
ranges, `picture_file` / `picture_rel`: the file dev's table gives a key), `engine/ground.gd` (`Ground`: the ground sectors and `clean_sectors()`), `dev_creatures.gd`, `problem_kit.gd`, `audio_probe`,
`fake_flow_view`, `fake_save_store`, `key_state`, `skin_recorder`, `skin_roster`, `skin_vandal`, `source_scan`, `stub_clock`. Shared: `scratch.gd` (`Scratch`: one root, `user://test_scratch/`, with a folder for each test process; `folder(name)` is a fresh empty scratch folder and `path(name)` a path in it for a file; `isolate_user_data` / `release_user_data` point the installed-packs folder and the remembered pack choice at fresh scratch places and give them back; a process's folder is deleted by the next run once the process is gone, where `/proc` says so, else after a day), `pack_shelf.gd` (scratch packs over the chain; `add_mod_fixture` makes one a mod pack from a folder of `tests/mods/`; `add_scaled_rows` makes one a pack of a higher picture scale with rows for the keys it is given, and `dev_picture_keys` is every key of the dev pack's table: a test builds a covering 4x pack from those, never from what the engine says the chain needs; `without_dev` makes the dev pack absent and `with_dev_again` puts it back; `empty_complete_pack_dir` a pack that is only a manifest and `remove_empty_packs` deletes it), `mod_skin_shelf.gd` (`ModSkinShelf`: the skin mod fixtures, `skin_data` among them (no script), with their pictures, mounted and released), `mod_problem_shelf.gd` (`ModProblemShelf`: the problem-screen mod fixtures with the problem type they draw, mounted and released; `plain` the same type with no mod), `mod_rule_shelf.gd` (`ModRuleShelf`: the rule-hook mod fixtures with their problem type, two sectors and two campaigns, one declaring the mod), `pictures_shelf.gd` (`PicturesShelf`: two scratch packs whose picture files are named at random, with tables of every row form), `picture_use.gd` (`PictureUse`: the keys a pack's data holds and the rows nothing asks for), `picture_painter.gd` (a control that draws a texture, for the render test), `resource_compare.gd` (the deep comparison of two resources, a `PictureRef` by its key, sounds by the file they came from), `campaign_shelf.gd`, `sector_scenario.gd` (one scripted
visit to a sector, driven through the game's own `GameFlow` with a fake view: the launch, a flight, a problem, the canister's problem that
costs the tank, a creature that takes one, the respawns, the dock and the balloon or the closing), `headless_stage.gd` (the playfield of a
`GameFlow` made of a `SimWorld` alone: the creatures tick as in the game, a trip ticks itself out or, asked for inside a tick, after it),
`sim_trace.gd` (every event with its tick and the rules' state after every tick, as text). A harness takes the game's paths
([`ARCHITECTURE.md`](ARCHITECTURE.md), "What keeps the split true"): it never freezes the creatures where the game does not, and seeds
`SimWorld.foe_rng` where it needs the same creatures every time. `SectorWorld.skip_animations` ends the launch and the dock at once,
skips the balloon and settles a lost tank with no dissolve, so no tick runs between `reload_creatures` and the next sector; a test sets
it only where it looks at the flow of a whole run through the real scene, and the scripted visits (`test_plays_identically.gd`) and
`test_game_flow_machine.gd` play the real trips and dissolves; `fixtures/` (probes for the engine, hashes of the original for legacy) and `skins/` (the
tiny and hostile test skins). Legacy: `legacy/legacy_pack.gd` (`LegacyPack`: where legacy is, the witness files). A test
that needs a place with a stated property gets a test sector of the dev pack
([`../../tools/dev_pack/README.md`](../../tools/dev_pack/README.md), "Test sectors").

## The importer and the dev pack

Re-running the importer, its steps and options: [`../play/LEGACY.md`](../play/LEGACY.md). The game's own tables in `extracted/tables/`
(`GENERATED_TABLES` in `tools/import/common.py`; the scripts that make them are `TABLE_SCRIPTS` and `run_tables` in `tools/import/step_extract.py`)
are the importer's `tables` step and are git-ignored (they are in `extracted/`), so a Python test that reads one is marked `@pytest.mark.legacy`. `tools/analysis/data/*.json`
is our own analysis (layouts, field meanings, `console_layout.json` from `tools/analysis/ghidra/export_console.py`) and is committed; the tools and the dev pack read
only those. Regenerating the dev pack:
[`../../tools/dev_pack/README.md`](../../tools/dev_pack/README.md).

## Screenshots

The sector viewer and the problem menu render one picture and quit (port screenshots show the original's art: never commit them):

```sh
tools/godot.sh --path godot res://src/debug/sector_viewer.tscn -- \
    --sector=3 --screen=1 --ticks=6 [--currents] [--collisions] --snapshot=$HOME/shot.png
tools/godot.sh --path godot res://src/debug/problem_menu.tscn -- --type=14 --level=2 [--record=I] \
    --answers=wrong,wrong --snapshot=$HOME/shot.png
```

`skin_compare.tscn`, `sector_overview.tscn` and `foe_sandbox.tscn` take `--snapshot=` as well.

## Exporting builds

`godot/export_presets.cfg` holds three presets. **Linux** (x86_64, embedded pck), **Windows Desktop** (x86_64, embedded pck) and **Web**
(single-threaded, so it needs no special server headers; Compatibility renderer) export the game: they leave out `tests/`, `reports/`, gdUnit4, the
editor plugins, `export/`, every pack (`packs/dev/*`, `packs/legacy/*`; `PackExportFilter` skips any other folder of `godot/packs/` too) and every project skin but the original (`skins/creatures/*`; `PackExportFilter` carries `skins/original/` and no other folder of `godot/skins/`: the game cannot run without the original skin, `SkinChoice.original`, and the others are for developing and showing; `test_pack_export_filter.gd`). The
`godot_ai` addon is not excluded, nor is `addons/godot_sandbox` (the extension that runs mod packs, fetched by `uv run tools/fetch_sandbox.py`: `gdscript.elf` goes into the pck, the library for the platform is written next to the executable of a Linux or Windows export and beside `index.html` of the Web one, and a game without it refuses a mod pack with the reason); the Web preset sets `variant/extensions_support` (the dlink template) so that the extension loads there. A pack reaches an exported game as a pack file made by `pack_tool --export-pack=<id> --archive` (no templates needed): `legacy.larissa` and `dev.larissa`
next to the executable, read where they lie (`Packs.bundled`; [`PACKS.md`](PACKS.md), "Finding and choosing";
[`../play/LEGACY.md`](../play/LEGACY.md), "Playing legacy in an exported game"; [`../create/CONTENT.md`](../create/CONTENT.md), "Shipping", for the player and creator downloads).
A release build without `legacy.larissa` refuses to play; a debug build without `legacy.larissa` but with
`dev.larissa` next to it opens on the pack warning and plays the dev pack's `dev_tour`. The Web preset uses the shell `godot/export/web_shell.html`
(Godot 4.7.2's `full-size.html` plus a step that preloads `dev.larissa` and `legacy.larissa` from next to the page into `/packs/` of the virtual file
system; `PACK_IDS` at its top lists the ids).

1. Install the export templates once: `mise run godot:fetch_templates` ([`../SETUP.md`](../SETUP.md)). `mise run release:build_linux` is the player's
   path once the legacy pack is built (the templates, `legacy.larissa` by `godot:pack`, the Linux release export into
   `build/game/operation-larissa-release.x86_64`; [`../play/LEGACY.md`](../play/LEGACY.md), "Quick start"); `release:build_web` does the same for the
   Web preset into `build/web/index-release.html`, and `release:build` runs both. `debug:build_linux`, `debug:build_web` and `debug:build` export the
   same presets with Godot's debug template (`OS.is_debug_build()` is true: the F3 debug overlay, `Packs.dev_fallback`) into
   `operation-larissa-debug.x86_64` and `index-debug.html` of the same folders, beside the same `legacy.larissa`; `release:play` and `debug:play`
   run the Linux one of their mode. The Web export names its other files after the page (`index-debug.js`, `index-debug.wasm`, ...), so the
   page of a mode is opened by its name. A Linux debug export also writes `operation-larissa-debug.sh`, Godot's launcher that runs it in a terminal.
   The tasks share the hidden tasks `export:linux`, `export:web` and `export:play`, which take the mode.
2. Export from the editor (Project > Export...; the Linux and Windows presets' own `export_path` is outside the repository) or from the
   command line:

```sh
tools/godot.sh --headless --path godot --export-release "Linux"           build/linux/operation-larissa-release.x86_64
tools/godot.sh --headless --path godot --export-debug   "Linux"           build/linux/operation-larissa-debug.x86_64
tools/godot.sh --headless --path godot --export-release "Windows Desktop" build/windows/operation-larissa-release.exe
tools/godot.sh --headless --path godot --export-release "Web"             build/web/index-release.html
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-pack=dev    --archive --out=build/linux --no-reach
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-pack=legacy --archive --out=build/linux --no-reach
```

   An export prints no `ERROR` or `SCRIPT ERROR` line (`tests/engine/test_editor_runs_quietly.gd` exports the game's resources and fails on one).
3. Try it: `godot/build/linux/operation-larissa-release.x86_64` (add `--headless --quit-after 600` for a smoke test), or for the web build
   `uv run python -m http.server -d godot/build/web 8080` and open `http://localhost:8080/index-release.html` (copy `dev.larissa` or `legacy.larissa` into that folder to have the page preload it).
   A headless run reads the `user://packs/` of your account: to see the refusal, set `XDG_DATA_HOME` to an empty folder under your home; to see dev chosen,
   put `dev.larissa` beside the binary and add `-- --pack=dev`. Saves go to `user://` (Project > Open User
   Data Folder in the editor shows it). The Windows export has not been run, and the Web export has not been tried in a browser. A Linux export with a mod pack has been run (`--pack=<id>` of a mod pack logs from its mod).

