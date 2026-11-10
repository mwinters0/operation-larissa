# Where the engine still assumes the original's content

The places where the engine or the project assumes the original game's content, so that every pack, dev included, inherits it. Packs are
described in [`../create/CONTENT.md`](../create/CONTENT.md) (section 4) and [`PACKS.md`](PACKS.md), the dev pack in
[`../../tools/dev_pack/README.md`](../../tools/dev_pack/README.md), the test suites in [`DEVELOPING.md`](DEVELOPING.md).

## Not built: high-resolution pictures in packs

Only a skin can supply high-resolution pictures (`GameSkin.art_folder`/`art_scale`); a pack's pictures are drawn at file size.
Candidates: `pictures/<kind>/<name>@4x.png` in a pack's own layout, high-res in complete packs' sprite frames and tile
set, an engine test with a test-only hi-res skin.

## Hard-coded assumptions

Places where the engine or the project assumes the original's content (each is a candidate for separation; none stops dev from
running). Paths are under `godot/`. A pack on the chain inherits whatever is project-level.

**Project-level data files with the original's numbers** (`res://data/`; the biggest remaining leak: every pack inherits them, dev included).
- `data/rules/durations.json` (read by `Durations`): the base layer holds the original's ticks (73 Hz timer). Dev's `rules/durations.json`
  overrides only launch, dock, sign_in, news and fade; dissolve (21), log scan (5 x 6), problem message and silent speech (146), key flash (12),
  surface-ship wait (1460) and the balloon come from the base, and some engine tests (of creatures, problems and the log, and audio) assert those numbers. Fix: a neutral
  base (or every pack gives every key) and the original's numbers in legacy's own file.
- `data/story/*.tres` (`title_ship`, `title_reveal`, `news_ambient`, `story_script`, `expert_deck`, `expert_hoist`, `expert_wait`,
  `voyager_closing_script`) and `data/closing_crew.tres`: the original's cutscene timelines and crew, project-level, not pack data.
  `Progression.VOYAGER_*` / `EXPERT_*` constants exist (unused by the dev flow).
- `data/ui/menu_layout.tres`: the original's popup x positions.
- `data/rules/tuning.json` (read by `Tuning`): the original's rule values, the sub's wall box, frame rectangles, light and hit-bubble tables among them, the oxygen, ink
  and midpoint limits, the trigger countdown and the lock wheel's waits. A pack's `rules/tuning.json` goes over it key by key; a pack that states none plays as the original.
- `data/sectors`, `data/campaigns` (`Catalog.SECTORS_DIR`, `CAMPAIGNS_DIR`) are the lowest layer under the chain; the editors make new sectors there.
- The project theme (`theme_builder.gd`) has the original's font size; dev's `screen_layout` matches it (`font_cell_height` 19,
  `font_average_width` 7; `tests/engine/test_theme.gd`). Fix: the theme as pack data.
- `tests/fixtures/` is one folder for both test suites: `src/checks/original_bytes.gd`, `src/core/fixture_hash.gd`, `src/core/foe_annotations.gd`,
  the screen editor and `addons/screen_editor/screen_file.gd` read `res://tests/fixtures/...`, and the importer writes there.

**Packs and catalog**
- `src/core/catalog.gd:26` `ORIGINAL_SECTOR_COUNT := 32`: `is_original_sector`, `next_free_sector` (a new sector gets 32 or more, also in dev),
  `src/checks/sector_changes.gd:198`, `addons/sector_editor/new_sector_dialog.gd:39,72`, `addons/sector_editor/sector_factory.gd:60-63` (the
  editors refuse sectors 0-31), `addons/screen_editor/screen_editor.gd:1010`; in the engine suite `tests/engine/test_new_sector.gd` keeps one
  `>= ORIGINAL_SECTOR_COUNT` assertion and `tests/engine/test_pack_campaign.gd:73` uses `is_original_sector`.
- `src/core/catalog.gd:46` `ORIGINAL_CAMPAIGNS = [voyager, expert]`: campaign list order, the saved `game` number to a campaign;
  `src/resources/player_profile.gd` (`Game` enum; hints off for `expert`, new and loaded players); `addons/pack_tools/pack_tool_dialog.gd:141`
  (the campaigns offered for export leave out the original's two).
- `src/packs/pack_check.gd:23` `OWN_CLOSINGS = [voyager, expert]` (the closing scenes a campaign may name without the generic finale) and
  `src/gameplay/game.gd:210` (maps `voyager`/`expert` to their closing scenes).
- `src/checks/sector_changes.gd` compares a sector with the original's tables (`fixtures/original`): only the line diff, `sprite_sets_of` and
  "has no original" are engine; it reads the `DELIBERATE_*` constants out of eight legacy test files by path (`sector_changes.gd:52-59`: seven
  `res://tests/legacy/test_*_fidelity.gd` and `test_foe_asm_legacy.gd`).
- `src/checks/sector_checks.gd`: "more creatures than any original sector" (`OriginalBytes.max_creatures`) and "longer than any original script" are original-based warnings (tested in legacy).
- `NameRegistry.original()` (the project's `names/original.json`, which dev follows) is the registry of `Catalog.text`, `SectorPanel.label_of`, `FoeNames`.
- `src/autoload/audio.gd` `music_for_sector` is campaign-based: a sector in no campaign plays `sector_song_1` whatever its `music_name`.

**Sectors and editors**
- The screen editor's status text and `ScreenData.original_sector` provenance exist only for sectors 0-31 (dev's screens say -1).
- Dev's backgrounds are 640 x 400, the original's 608 x 288: not checked which size the engine expects.
- `Catalog.sector_ids()` loops ("every sector of the chain") fail on dev's test sectors (empty creature labels, no backgrounds); the suites that loop
  use `Ground.clean_sectors()` (the tour and the clean test sectors) instead.

**Creatures and skins**
- `skins/creatures/puffer_rig_3d.gd:27` `PICTURE_SIZE` (80, 48) is the original's puffer picture size; `skins/creatures/creature_species.gd` names
  the original's fish by registry picture names.
- `src/gameplay/foe.gd:25` `HOPPING_PICTURES` is zone 0's `jellyfish_tentacle`.
- `src/skins/hud_labels.gd`: the default zone words are the original's ("Dragon Reef").
- The tiny test skin (`tests/skins/tiny/`) maps registry keys (`ui_picture/title_sky`, a creature picture, the first zone's name box), which dev has
  because it follows the original's registry. `tests/engine/test_assets.gd:21`, `test_no_asset_numbers.gd` and `test_skin.gd` name dev's
  `assets/ui/title/title_sky_1039.png`, which works only because dev's inventory has the original's file names.

**Problems**
- `src/problems/prompt_sender.gd:23-28` sender picture position and header/body x/y are absolute original coordinates; `:35` ship slots `2..19` and `>= 60`.
- `src/problems/problem_flow.gd:69,72` `NO_SHIP_NOTICE_TYPES`, `SUCCESS_REPLAY_TYPES` and `src/problems/practice_mode.gd:26` `WIDE_PANEL_TYPES` are original type numbers.
- `src/rules/sim_world.gd:118` `CANISTER_SLOT := 1`; `src/problems/combination_lock.gd:48` operator-reveal timings and lock-wheel constants.
- `src/problems/problem_texts.gd`: per-type wording hard-codes the original's field meanings.
- `src/problems/diagrams/`: dev draws only items, lock and ballast_panel; sonar, nav_chart, barnacles, pie, ruler, tank, line_graph, storage_boxes,
  search_area, search_grid are exercised only by legacy tests.

**Flow and story**
- `src/resources/bubble_rules.gd:34` `finale_sector := 30`: the sector whose finale bubbles are special.
- `src/story/surface_ship_screen.gd:39` `SHIP_POSITION` fixed.
- `src/ui/sign_in.gd:250` hard-codes " (c)" and "Final"; `src/rules/game_flow.gd` messages ("Operation Neptune", "You have run out of oxygen...") are code literals;
  the sign-in screen's 24-picture scan and welcome speech are the original's.
- Text contracts a pack must meet: menu items one per line (File 3, Options 5, Help 7); the Hall header's first line is 3 words; string 11212
  uses `\b`+Ð and `\b`+Ñ; 11208 holds the exit hotkey letters.
- The canister log's page is the original's: two columns of eight rows (`src/core/canister_log.gd:20-23`), which holds the original's 15 entries
  per game. The closing flag is creature-semaphore bit 15 (`SimWorld.FINALE_SEMAPHORE_BIT`), the bit a finale's treasure sets
  (`tests/engine/test_closing_trigger.gd`).

**Dev pack gaps** (generator limits, not engine): `dev_sectors.py` writes no animated decos, dormant or hidden creatures (the test-sector modules
patch them in); dev's flipped hit rectangle equals the unflipped one.
