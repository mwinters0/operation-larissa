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

Exit code 0 means everything passed; reports go to `godot/reports/`. There are two gdUnit4 suites, each on the pack it is about;
the script passes the choice after `--`, where `Packs.start()` reads it:

- **`godot/tests/engine/`** (`-- --pack=dev`): the engine, on the dev pack's own numbers, records and test sectors. It needs no legacy
  pack, no ISO and no ISO-derived `docs/data/` table, and never skips for want of content.
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
`tools/run_tests.sh` (`tests/legacy/test_snapshots.gd` and `tests/engine/test_skin_creatures_render.gd` read viewport pixels); headless
they are skipped. With the editor open the godot-ai MCP `test_run` works too. gdUnit4's command tool stops a file at its first failing
test, so a broken file hides the rest of itself.

**Rules of an engine test.** It uses dev's numbers, records and test sectors, never legacy's, and never names `LegacyPack` or
`res://packs/legacy`. It reads a rule value from the run (`GameState.tuning`, `Tuning.resolve()`), never assumes the original's number: dev states
every rule value differently ([`tools/dev_pack/README.md`](../../tools/dev_pack/README.md)); `Tuning.original()` is for a test of a part on its own and
of the project's file. A test that checks only the original's data is a legacy test; a file with both kinds is cut in two (`test_x.gd`
for the engine, `test_x_legacy.gd`). A test that borrows the chain puts it back with `Packs.start()` (the command-line choice again), not
`Packs.choose`; a test that starts a second Godot hands the choice on (`PackShelf.pin_args()`). Engine tests that still need something
only the original has are the record of what is hard-coded ([`HARD_CODED.md`](HARD_CODED.md)).

**Helpers** (`godot/tests/`). Engine: `engine/dev_pack.gd` (`DevPack`: dev's root, `sector(n)`, the tour's numbers, the test-sector
ranges), `engine/ground.gd` (`Ground`: the ground sectors and `clean_sectors()`), `dev_creatures.gd`, `problem_kit.gd`, `audio_probe`,
`fake_flow_view`, `fake_save_store`, `key_state`, `skin_recorder`, `skin_roster`, `skin_vandal`, `source_scan`, `stub_clock`. Shared: `pack_shelf.gd` (scratch packs over the chain; `add_mod_fixture` makes one a mod pack from a folder of `tests/mods/`; `without_dev` makes the dev pack absent and `with_dev_again` puts it back; `empty_complete_pack_dir` a pack that is only a manifest), `mod_skin_shelf.gd` (`ModSkinShelf`: the skin mod fixtures with their pictures, mounted and released), `mod_problem_shelf.gd` (`ModProblemShelf`: the problem-screen mod fixtures with the problem type they draw, mounted and released; `plain` the same type with no mod), `mod_rule_shelf.gd` (`ModRuleShelf`: the rule-hook mod fixtures with their problem type, two sectors and two campaigns, one declaring the mod), `resource_compare.gd` (the deep comparison of two resources, pictures and sounds by the file they came from), `campaign_shelf.gd`, `sector_scenario.gd` (one scripted
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

Re-running the importer, its steps and options: [`../play/LEGACY.md`](../play/LEGACY.md). The game's own tables in `docs/data/`
(`sectors.json`, `problem_tables_raw.json`, `trigger_table.json`, `zone_defaults.json` from `tools/analysis/export_json.py`;
`problem_records.json` from `decode_problems.py`; `problem_gfx_bundles.json` from `export_gfx_tbl.py`) are the importer's `tables` step
and are git-ignored. The rest of `docs/data/*.json` was read from the decompiled program (`tools/analysis/ghidra/export_*.py`, and the
pure-Python `export_console.py`) and is committed; rerun those only when the analysis changes. Regenerating the dev pack:
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
editor plugins, `export/` and every pack (`packs/dev/*`, `packs/legacy/*`; `PackExportFilter` skips any other folder of `godot/packs/` too). The
`godot_ai` addon is not excluded, nor is `addons/godot_sandbox` (the extension that runs mod packs, fetched by `uv run tools/fetch_sandbox.py`: `gdscript.elf` goes into the pck, the library for the platform is written next to the executable of a Linux or Windows export and beside `index.html` of the Web one, and a game without it refuses a mod pack with the reason); the Web preset sets `variant/extensions_support` (the dlink template) so that the extension loads there. A pack reaches an exported game as a pack file made by `pack_tool --export-pack=<id> --archive` (no templates needed): `legacy.larissa` and `dev.larissa`
next to the executable, read where they lie (`Packs.bundled`; [`PACKS.md`](PACKS.md), "Finding and choosing";
[`../play/LEGACY.md`](../play/LEGACY.md), "Playing legacy in an exported game"; [`../create/CONTENT.md`](../create/CONTENT.md), "Shipping", for the player and creator downloads).
A release build without `legacy.larissa` refuses to play; a debug build without `legacy.larissa` but with
`dev.larissa` next to it opens on the pack warning and plays the dev pack's `dev_tour`. The Web preset uses the shell `godot/export/web_shell.html`
(Godot 4.7.2's `full-size.html` plus a step that preloads `dev.larissa` and `legacy.larissa` from next to `index.html` into `/packs/` of the virtual file
system; `PACK_IDS` at its top lists the ids).

1. Install the export templates once: `mise run godot:fetch_templates` ([`../SETUP.md`](../SETUP.md)). `mise run release:build_linux` is the player's
   path once the legacy pack is built (the templates, `legacy.larissa` by `godot:pack`, the Linux release export into `build/game/`;
   [`../play/LEGACY.md`](../play/LEGACY.md), "Quick start"); `release:build_web` does the same for the Web preset into `build/web/`, and
   `release:build` runs both.
2. Export from the editor (Project > Export...; the Linux and Windows presets' own `export_path` is outside the repository) or from the
   command line:

```sh
tools/godot.sh --headless --path godot --export-release "Linux"           build/linux/operation-larissa.x86_64
tools/godot.sh --headless --path godot --export-release "Windows Desktop" build/windows/operation-larissa.exe
tools/godot.sh --headless --path godot --export-release "Web"             build/web/index.html
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-pack=dev    --archive --out=build/linux --no-reach
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --export-pack=legacy --archive --out=build/linux --no-reach
```

   An export prints no `ERROR` or `SCRIPT ERROR` line (`tests/engine/test_editor_runs_quietly.gd` exports the game's resources and fails on one).
3. Try it: `godot/build/linux/operation-larissa.x86_64` (add `--headless --quit-after 600` for a smoke test), or for the web build
   `uv run python -m http.server -d godot/build/web 8080` and open `http://localhost:8080` (copy `dev.larissa` or `legacy.larissa` into that folder to have the page preload it).
   A headless run reads the `user://packs/` of your account: to see the refusal, set `XDG_DATA_HOME` to an empty folder under your home; to see dev chosen,
   put `dev.larissa` beside the binary and add `-- --pack=dev`. Saves go to `user://` (Project > Open User
   Data Folder in the editor shows it). The Windows export has not been run, and the Web export has not been tried in a browser. A Linux export with a mod pack has been run (`--pack=<id>` of a mod pack logs from its mod).

