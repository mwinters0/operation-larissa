# Roadmap

Future work only. What exists is described in the permanent docs ([`OVERVIEW.md`](OVERVIEW.md), [`CODEMAP.md`](CODEMAP.md)); when an
item here is done, delete it and describe the result in the doc that owns the topic. Work items are numbered so commits
can name them; the ids are not used outside this file.

## Open items

Known gaps of the existing systems, by area. The engine's remaining assumptions about the original content are listed in
[`engine/HARD_CODED.md`](engine/HARD_CODED.md); differences from the original in [`port/PORT_GAPS.md`](port/PORT_GAPS.md).

**Not yet exercised by hand.** The editor tools (screen editor, Sector panel, New sector, Check sector, the pack tools window), the
pack screen, a skin mod, a mod with rule hooks in a campaign, a student campaign, the debug-rectangles presenter and the `modern` / `creatures` skins
through a whole real-time session, and the runtime MIDI music have been driven only by tests and command-line processes, not used by
hand in a window.

**Engine and packs**
- A mod can exhaust the game's memory with data it builds in the host (a string doubled forty times, a `PackedByteArray` resized to gigabytes, arrays nested a hundred thousand deep): godot-sandbox 0.60 limits the guest's instructions and memory, not
  what the guest asks the host to build, so such a mod crashes the game. A limit upstream, or running mods in a process of their own, is needed before "as safe as a data pack" holds for memory. It is the one hostile act that is not contained: instructions, guest memory,
  the objects a mod may reach and everything a mod hands back to the game (a draw list, a rule hook's answer) are bounded and tested.
- A skin mod draws from the state alone: it is told no background, decoration or station of the screen, so it paints those itself or leaves them out; and a shader of its is vetted as text but compiled only by the renderer, so a shader
  that fails to compile is found when it is drawn, not when the pack is checked.
- A rule hook that keeps state in variables of its own (rather than the memory the game hands back) is outside the promise that the same inputs are the same play; `RuleHooks.verify_pure` catches it in tests and tools, not while playing.
  The hooks are three (the judging of an answer, a creature instruction, the sub's velocity and invulnerability); another point (a piece, a trigger, a contact, a creature that a mod adds) is a new named hook in `RuleHooks`.
- A problem-screen mod draws a still picture over the calculator or the answer box: no build-up or success animation, no sound, and a type a pack adds is worded from its texts and fields only and never uses the combination lock or the ballast panel.
- High-resolution pictures in packs (`pictures/<kind>/<name>@4x.png`, high-res sprite frames and tile sets); today only a skin can
  supply them, and tiles and backgrounds have no 4x path (`ScaledTexture` does not reach `TileSet` atlases).
- Story timelines other than the news cartoon are preloaded by their scenes, so no pack can replace them.
- No player-facing menu to choose a pack or a skin (`--pack=`, `--skin=`, F3 then S); the soundfont is per `Audio`, not per skin.
- Unnamed creature and decoration pictures share one skin key (`frame/foe`), so they cannot be skinned one by one; there is no
  supported "this skin draws creature N" hook (`creatures` hides `Foe.sprite`); `SimView` events reach a skin before
  `OriginalPresenter`'s handlers.
- The supply station's door x positions are literals in the views.
- `Campaign.text()` shows the original's string for a sentence that is exactly a text name; a generic finale has no voice or music of
  its own. `SectorData.game` is read only by the importer and the sector checks.

**Exports**
- A custom release export template (`disable_3d`, `optimize=size`, LTO, unused modules off): the stock Godot template is about 73.5 MB of the
  77 MB release binary and is where the size is; the game's own files are about 4 MB.

**Rules and fidelity**
- The news pause may be 250 ticks in the original (unchecked).
- The `Game` mission trace test runs with `skip_animations`.

**Editors**
- The creature script editor offers `Mod_Instruction` in every sector, and the sector checks do not warn of one in a sector of a campaign that declares no mod (its creature faults when it reaches it).
- New creatures are copies of existing ones. Playtest presets keep creatures' place and program counter from the file and do not check
  the sub's start against walls. Dock-undo of a refused marker delete relies on English undo-step names.
- Renaming a name from inside the Foe Script editor; plain-string hits in tests and `tools/import/*.py` seeds are reported by the rename
  tool, not rewritten. All names are provisional (sounds 0-21 were named without listening).

**Legacy pack and provenance**
- The int8 voice transcripts are verified on one machine only (an AMD CPU with AVX-512); compare on another CPU vendor (fall back to
  `float32`). Two clips transcribe as long letter runs (`NE1SOUND_4244`, `NE0SOUND_8037`): hand-correct them.
- A few short game-text phrases remain in the Ghidra JSON files, `port/AUDIT_CALLSITES.md` and `port/DESIGN.md`.

**Documentation**
- Walkthroughs for students: one game tick from input to picture, a creature's life (script, VM, contact, ink), a trigger to a solved
  problem.

## K: mods draw the game

Mods take over drawing step by step, from data alone up to the problem screens and the menus' style. Every step keeps the promises
of skins (`create/SKIN_API.md`): no rule, timing or hit rectangle changes, a skin bound mid-anything shows what one bound from the
start shows, and `test_plays_identically` / `test_skins_dont_change_the_game` cover each new form. The engine keeps every menu's
function and every duration; a mod changes only what they look like. 3D models and animation trees need real nodes, which a sandbox
cannot grant: they stay what a project skin can do (`creatures`), and the docs say so.

**Art templates.** Each phase that lets a skin replace pictures ends with templates for them: for every picture key it opens up
(K1: the HUD's bezel, gauges, lights and label boxes; later phases their own keys), a PNG of the original's exact size in one flat
colour with the key and the size written on it, made by a committed tool (one line in `CODEMAP.md`; the sizes come from the layouts,
not from the original's pixels, so the templates carry no original content and are committed in the example pack). The user draws the
real art from them.

- **K1: skins as data.** A skin pack needs no script. New `skin` keys in the manifest (`ModSpec`, `PackCheck`, `ModSkin`):
  - `render`: texture filter and the two snapping flags (`RenderSettings`).
  - `hud_font` (and size, colour): a `.ttf` of the pack, loaded from bytes; packs accept `.ttf` (`Pack`, the data form).
  - `pictures`: skin key to a PNG of the pack (`ui_picture/<name>`, the HUD's keys), worn only while this skin is (unlike a pack's
    `pictures/`, which win under every skin).
  - `layers`: a layer of the original presenter by name (`background`, `back_decos`, `walls`, `station`, `mid_decos`,
    `collectibles`, `sub`, `foes`, `pellets`, `front_decos`, `anim_decos`, `bubbles`) to a checked shader (`ModShader`) and
    uniforms; the engine sets `phase` (ticks plus the tick fraction, still while the clock is held) as `modern_presenter.gd` does.
  - An `entry` script is optional for a skin with no `skin_frame`.
  - `modern` becomes the example pack (`examples/packs/modern/`, its `.larissa` built by a mise task): the water shimmer on
    `background`, Exo 2 on the HUD, linear filtering, and the HUD art from the templates. `res://skins/modern/` and
    `test_skin_modern.gd` go; the example's tests take their place. A creator tutorial "Your first skin" in `create/` walks through it.
  - Settle the export: `create/CONTENT.md` says the project's skins are not exported, and the export filter does not exclude
    `skins/*`; make the two agree.
- **K2: layers drawn by a script.** A script replaces chosen layers (`skin_layer(name, state, fraction, events)` returns a draw list
  for that layer); the others stay the original's. The draw list may name a picture of the chain by skin key (`frame/sub_00`,
  `background/<current>`): the game resolves it, the mod never holds it. The state gains the screen's background, decorations and
  station (closing the Open item of a skin mod told no background). The skin mod that draws everything becomes the case "every layer".
  Templates for any key a K2 example replaces.
- **K3: the HUD as a layer.** The console's state as plain data (oxygen, ink, tanks, pieces, the labels' words, the lights), and a
  script that draws the HUD or parts of it inside the layout's rectangles. Templates for the HUD's parts at their sizes.
- **K4: problem screens.** A mod opts in to drawing original types (0 to 33) by number, the original diagram being the fallback;
  presentation events for every type (start, step, verdict, damage, success, timeout), told after the rules decided; animation on the
  engine's clock, whose lengths stay the original's whatever the mod draws; sounds by name. Templates for the problem screen's frame
  and panels.
- **K5: the menus' style.** A theme as data (fonts, colours, panel and button styles, pictures by key) for sign-in, the dialogs, the
  message box and the problem screen's frame, applied by `ThemeBuilder`; the controls, their order and what they do stay the
  engine's. Templates for each picture the theme may replace.

## After this: the remake

Whatever needs a change to an existing rule is a separate project. What this one gives it: the named content through an exporter,
`port/DESIGN.md` as the specification, and the original campaigns as a reference; the remake can play original sectors and report
where it behaves differently.
