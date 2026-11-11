# Skins in code

A skin is the presentation layer as data: a `GameSkin` resource (`src/skins/game_skin.gd`; not `Skin`, which is a native class) at
`res://skins/<id>/skin.tres` that maps registry names to its own resources; everything it does not map falls back to the original
skin (`skins/original/skin.tres`). The rules and the content never see it (`tests/engine/test_skin_rules_blind.gd` reads their source
for the skin classes). What a skin author is given is [`../create/SKIN_API.md`](../create/SKIN_API.md); making one is
[`../create/MAKING_CONTENT.md`](../create/MAKING_CONTENT.md), Part C. Paths are relative to `godot/`.

## What a skin maps

- **`pictures`**: `<kind>/<registry name>` to a `Texture2D` (`ui_picture/title_sky`, `problem_art/log_scan_0`, `frame/dolphin_swim_0`,
  `deco/...`, and by file name `tile/zone0_tiles`, `background/bg_s00_00`). `GameSkin.key_of(path)` is the key of a file under a
  pack's `assets/`, so the `assets` paths inside `data/sprite_frames`, `data/problems`, `data/ui`, the tile set and
  `ProblemType.art_files` all resolve through one table.
- **`art_folder` / `art_scale`**: a folder of PNGs named by key, drawn at 1 / `art_scale` of their size (`ScaledTexture` reports the
  original size), so 4x art is sharp at the original's size. No shipped skin has one.
- **`resources`**: a whole presentation resource by its path under `data/` (`ui/hud_layout`, `problems/screen_layout`,
  `sprite_frames/foes_zone2`, `neptune_tileset`), for a skin whose pictures have other sizes. Only `GameSkin.REPLACEABLE` keys are
  taken (`ui/`, `sprite_frames/`, the tile set, the problem screen's layout); a key that names rules or content
  (`zones`, `trigger_table`, `problems/problem_type_NN`, `sprite_meta/*`, a sector, the texts) is ignored and listed by
  `GameSkin.refused_resources()`.
- **`presenter_scene`** (the root extends `SectorPresenter`), **`render`** (`RenderSettings`), **`hud_labels`** (`HudLabels`),
  **`fallback`** (another skin to build on).

**Resolution.** `Assets` (`ui_picture`, `problem_art`, `background`, `texture_at(path)`) asks the skin for every texture, and `Catalog`
(`foes_frames`, `decos_frames`, `sub_frames`, `fx_frames`, `pieces_frames`, `station_frames`, `tileset`, `problem_type`,
`screen_layout`, `hud_layout`, `calculator_layout`, `menu_layout`, `story_layout`, `skinned(resource)`) returns the skin's version: its
own resource, or the original's with the skin's pictures put in (a copy made once per skin; the file's resource is never written to).
With the original skin each is the very object loaded from the pack. Catalog asks the skin only for presentation files (a test reads
its source). A picture that a pack of the chain supplies by skin key wins over every skin ([`PACKS.md`](PACKS.md)).

## Choosing and switching

`SkinChoice` (`src/skins/skin_choice.gd`): `-- --skin=<id>` on the command line, `SkinChoice.forced` for a test, `current()`,
`select(skin)` / `select_id(id)` at run time, `events.changed(skin)`, `available()` (every folder of `res://skins/` with a
`skin.tres`, then the skin mods that run), `after()` (F3 then S in the game). On a switch `SectorWorld` makes a new presenter of the same kind (the skin's
`presenter_scene`, else `OriginalPresenter`) that builds the screen from the rules' state, `Hud` puts its layout and lettering on again,
and the window gets the skin's render settings; screens made later (a problem, a story page, the log) take the skin current then.

- **`RenderSettings`** (`src/skins/render_settings.gd`): `texture_filter` and the two snapping flags of a `Viewport` (the resource's
  defaults are the project's, pinned by `tests/engine/test_skin_render.gd`), and `playfield_filter` for the presenter alone.
  `RenderSettings.apply_to(viewport)` gives them to a `SubViewport` a skin makes.
- **`HudLabels`** (`src/skins/hud_labels.gd`: font, size, colours, the words) puts the HUD's game / zone / sector / "Cust" words in
  `Label` nodes inside the label boxes. The boxes' sizes are layout data (`HudLayout.game_size`, `zone_size`, `sector_size`,
  `custom_size`, written by `tools/import/step_console.py`) and the label clips to its box, so any font leaves every rectangle where it
  was (`tests/engine/test_skin_hud.gd`).

## Two skins at once: `skin_compare.tscn`

`src/debug/skin_compare.tscn` runs one sector and shows it twice, the original skin on the left and another on the right (two 640 x 400
`SubViewport`s with their own render settings and HUD), bound to the same rules. Keys: `[ ]` sector, arrows screen, `F` fly, Space
pause, `,` `.` or the drop-down for the right-hand skin, `O` rectangles over both halves, `L` level, `F1` help.

```
tools/godot.sh --path godot res://src/debug/skin_compare.tscn -- --skin=modern --sector=3 --screen=5 --fly --overlay
tools/godot.sh --path godot res://src/debug/skin_compare.tscn -- --skin=res://tests/skins/tiny/skin.tres      # a skin file anywhere
tools/godot.sh --path godot res://src/debug/skin_compare.tscn -- --ticks=40 --snapshot=/path/shot.png          # a PNG, then quit
```

The seam that makes it possible: `SkinChoice.current()` is one global, so a presenter carries its skin (`SectorPresenter.skin`,
`PresenterChoice.make_presenter_for(skin)`; so can the `Hud`), and everything it fetches through `Assets` / `Catalog` - when it is
built, in an event (`_listen` wraps the handlers), in a frame (`run_in_skin`) - comes from that skin (`SkinChoice.within`, which selects
nothing and tells nobody). Tested in `tests/engine/test_skin_compare.gd`; the game itself never sets it.

## The shipped skins

- **`modern`** (`skins/modern/`): a water shimmer over the background (`water_shimmer.gdshader` on the `Background` sprite of
  `modern_presenter.tscn`, an inherited copy of the original presenter's scene; `modern_presenter.gd` gives the shader the game's time,
  ticks plus the tick fraction, so the water stops when the clock is held), the Exo 2 font (SIL OFL 1.1, `skins/modern/fonts/OFL.txt`)
  for the HUD's words, linear filtering and no pixel snap. Test: `tests/engine/test_skin_modern.gd`.
- **`creatures`** (`skins/creatures/`): two species drawn in new ways by `CreaturesPresenter` (extends `OriginalPresenter`), whose own
  code uses only the skin API (`view`; `test_skin_creatures.gd` scans its source for `sim` and the rule objects). The rainbow fish
  (sector 0, screens 3 and 5) is moved by an `AnimationTree` (`RainbowFishRig`: `swim` / `chomp` / `turn` / `inked`, `swim` a blend of
  `hover` and `cruise` by how far it moved in the last tick). The puffer fish (sector 0, screens 0, 6 and 9) is a lit 3D model of
  primitive meshes (`PufferModel`) in a transparent `SubViewport` shown by a `Sprite2D` (`PufferRig3D`). Both draw inside the creature's
  original picture rectangle. Run on legacy: `tools/godot.sh --path godot res://src/debug/sector_viewer.tscn -- --pack=legacy
  --skin=creatures --sector=0 --screen=0 --fly` (on dev the fish are in sector 122, `tests/engine/dev_creatures.gd`). Tests: `test_skin_creatures.gd`, and in a window `test_skin_creatures_render.gd`.
- **`tests/skins/tiny/`** is a test skin, not a shipped one (one square in place of three pictures, linear filtering, HUD words as text).

## Skins do not change the game

The same sector and the same hands give the same event trace with every skin. `tests/engine/test_plays_identically.gd` plays scripted
visits with every skin (with and without the rectangles over it), checks the lengths of the steps that hold up play, and plays a whole
mission through the real `Game` scene with each skin; `tests/engine/test_skins_dont_change_the_game.gd` switches skins mid-visit (every
ordered pair) and runs a hostile skin (`tests/engine/skin_roster.gd`: a presenter that scribbles over everything, `resources` that try
to replace the tuning, tables, hit rectangles, problems and sectors) and shows the rules' data is the same objects and numbers whichever
skin is chosen. The skins compared are asked for, not listed: `SkinChoice.available()`, the tiny skin, the hostile one and the skin mods
(`SkinRoster.mount_mod_skins`: a good one that draws and one that faults on every frame), so a new skin is covered the moment it is in `res://skins/`.

```
tools/run_tests.sh tests/engine/test_plays_identically.gd tests/engine/test_skins_dont_change_the_game.gd     # about 15 s
```

Other skin tests: `test_skin.gd` (fallback, mapping, the original unchanged), `test_skin_render.gd`, `test_skin_hud.gd`,
`test_skin_switch.gd`, `test_skin_rules_blind.gd`, `test_skin_api.gd`, `test_skin_compare.gd`, `test_mod_skin.gd` (skin mods).

## Skin mods

A skin from a stranger is not a folder of `res://skins/` but a mod pack ([`PACKS.md`](PACKS.md), "Mod packs"): a sandboxed script that returns what to draw. `ModSkin` (`src/mods/mod_skin.gd`) is its `GameSkin`: the pack's id, no resources of its own and only the `render` and `pictures` its manifest maps
(the HUD's layout, the screens and the sounds stay the base game's), and `presenter_scene` = `ModPresenter` (`src/mods/mod_presenter.tscn`). A skin with no script (a manifest with no `entry`) has the same object with no `presenter_scene`, so the original presenter shows the sector, and needs no Sandbox. `ModHost` makes it when the mod loads and `SkinChoice` offers it with the others, so every path that wears a skin (the command line, F3 then S, `SectorWorld`,
`skin_compare`) wears it the same way, and `leave_dead_mod_skins` puts the original on when the mod stops. How to write one is [`../create/SKIN_API.md`](../create/SKIN_API.md), "Writing a skin mod".
