# The skin API

What a skin is given by the rules, and what it must not do. A skin is a `SectorPresenter` (`godot/src/gameplay/sector_presenter.gd`):
a node that draws a sector from what the rules say. `OriginalPresenter` is the original look and the model to read; `DebugRectPresenter` is the
smallest one. Everything below is pinned by `godot/tests/engine/test_skin_api.gd`, which fails when this page and the code stop agreeing. A skin that is a stranger's code, a mod pack that
draws the sector from a sandbox, is given the same state and events as plain data and returns a draw list: the last section, "Writing a skin mod" (pinned by `test_mod_skin.gd`). A skin with no script, made from the example pack step by step: the tutorial [`FIRST_SKIN.md`](FIRST_SKIN.md).

## The rules a skin keeps

1. **Nothing waits for a presenter.** Every method a presenter is asked is instant. The rules never wait for a picture, a sound, an
   animation or a `Tween`; a presenter that draws nothing changes nothing about when play goes on.
2. **A presenter never decides a length.** The steps that hold up play (the launch, the dock, the balloon, the dissolve) last as long as the
   rules say, and the rules tell the presenter ("you have N ticks"). A presenter fits its drawing to N (`elapsed / ticks`) and never chooses
   N: a fancier dock in the same time is a skin, a longer one is a content change (the lengths are data in `data/rules/durations.json`, which a pack may override).
3. **A presenter cannot change a rule.** The API gives it copies, not rule objects (below). It does not call `sim.tick`, hold the clock, write
   state or read the keyboard. Same sector and same hands give the same trace with any presenter (`test_plays_identically.gd`).
4. **The tick fraction is an argument.** A presenter needs no autoload to know how far into a tick a frame is.
5. **The state is the truth, the events are changes.** In `bind`, and on `sector_loaded` and `screen_loaded`, a presenter builds what it shows
   from what `view` holds at that moment (`pellets()`, `sequence()`, `is_dissolving()` and the rest), never from what it assumes the event
   implies; the events after it carry only changes. A presenter bound in the middle of anything (F3 R, a skin change, a tool) shows what one
   bound from the start shows: `godot/tests/engine/test_presenter_binds_late.gd` checks it for every presenter and every skin that ships.

## What a presenter receives

`bind(sim_world)` makes `view`, a `SimView` (`godot/src/rules/sim_world.gd` is what it looks at; `godot/src/rules/sim_view.gd` is the API).
**A skin uses `view` and nothing else of the rules.** (`sim` is also kept on the base class, for `OriginalPresenter`, `DebugRectPresenter`
and the tools, which are part of the game. A skin that reaches round the API - `sim`, a private `_` field, `Catalog` to change data - is
outside it, and the guarantees do not hold.) Connect events with `_listen(view.some_event, handler)` in `bind`; `unbind` takes them back.

### The coordinates

All places are **playfield pixels** (x 0..607, y 0..287; the rules' window pixels minus `SubModel.PLAYFIELD_ORIGIN` = (16, 32)). A place is the
**top-left corner of the picture**, except the sub's, which is the **centre** of its 96 x 54 picture (`SubState.top_left()` is the corner).
Pictures are numbers in the zone's lists (`picture`); the skin chooses how they look.

### The state

Each call makes new **copies**: ask on `ticked` and keep the answer, do the arithmetic per frame.

| Call | Answer |
| --- | --- |
| `view.sub()` | `SubState`: `motion`, `cell`, `propeller_phase`, `picture`, `mirrored`, `picture_visible` (false on the off ticks of the blink), `bubble_picture` (-1: none), `invulnerability`, `blinking`, `message_light`, `active`, `controlled`, `hurt_rect`, `wall_rect` (the two rectangles the rules test, for an overlay) |
| `view.creatures()`, `view.creature(i)` | `CreatureState` (all the sector's creatures, also on other screens): `index`, `picture`, `mirrored`, `hidden`, `shown`, `screen`, `motion`, `jumped`, `was_hidden`, `damage`, `hit_rect` (what the rules test, for an overlay) |
| `view.pellets()` | `PelletState`: `id`, `splashing`, `splash_picture` (0 flying, 1..3), `splash_offset`, `motion` |
| `view.pieces()` | `PieceState` of the shown screen, not collected: `index` (0 is the data canister), `is_canister`, `position` |
| `view.triggers()` | `TriggerState` of the shown screen: `screen`, `index`, `slot`, `armed`, `position` (invisible in the game) |
| `view.sequence()` | `SequenceState` of the supply trip that runs or ran last (null before the first): `kind`, `ticks`, `started_tick`, `elapsed`, `done`, `door_picture()`, `is_drive()`, `progress(fraction)`, `balloon_position(fraction)` |
| `view.is_dissolving()`, `dissolve_elapsed()`, `dissolve_ticks()`, `dissolve_progress()` | the dissolve, in ticks of 1/73 s |
| `view.is_dissolved()` | the sub has dissolved away in this load: nothing of it is drawn until it is placed again |
| `view.sector_index`, `screen_index`, `zone`, `tick_number` | where we are; `tick_number` counts ticks from 0 (during a tick and in its `ticked` it is that tick's; between ticks the next one's) |
| `view.is_solid(column, row)`, `view.current_at(column, row)` | the walls and water currents of the shown screen (38 x 18 tiles of 16 px) |

The pictures of the screen itself (background, decorations) are content: read them with `Catalog` as `OriginalPresenter` does, once per
`screen_loaded`. The player's game (air, ink, pieces) belongs to the console, not to the presenter.

### The previous state and the tick fraction

Everything that moves is a `SimView.Motion`: `previous` (at the start of the last tick), `current`, `moved()`, and `at(fraction)`.
`show_between_ticks(fraction)` is called once per drawn frame: 0.0 = a tick has just happened, 1.0 = the next is due. Draw each moving
thing at `motion.at(fraction)`; the picture lags the rules by up to a tick (82 ms) and so does everything else, so they line up
(`TickSmoothing` is the same arithmetic, the original look's shift; the test checks that `Motion.at` puts the sub, the creatures, the
pellets and the balloon exactly where `OriginalPresenter` draws them).

* The sub's `previous` is its place at the start of the tick; `sub_placed` marks a jump (a launch, a respawn): `previous == current`.
* A creature's step is a glide unless `jumped` (a SET_POS, the end of an interrupt script) or `was_hidden != hidden`. The original look also
  jumps steps longer than 24 px and the jellyfish's loose tentacle (`Foe`); a skin may animate a step as it likes.
* Timed things: a supply trip has `ticks` (the rules' length), `started_tick`, `elapsed`, and
  `progress(fraction) = (elapsed - 1 + fraction) / ticks` (0..1; done = 1.0). `balloon_position(fraction)` is the balloon's corner (the original look draws the balloon behind the station);
  the door is `door_picture()` (2 closed, 3 and 4 moving, -1 open; the schedule is in `StationSequence`) and the sub that drives is just the
  sub's `motion`. The lengths (`ticks`, the dissolve's) are data, not constants: `data/rules/durations.json`, which a pack may
  override, so a skin must take `ticks` from the state it is given and never assume 30 / 31 / 44 / 21; a skin that needs a particular length
  depends on the pack that sets it. Trip tick `k` (0-based) runs in game tick `started_tick + k`; the last is `started_tick + ticks - 1`.
  The dissolve is counted in ticks of 1/73 s while the game clock is held (no `ticked` comes), so there is no fraction:
  progress is `elapsed / ticks` (`dissolve_advanced(elapsed, ticks)`), fine enough for any frame rate.

## The events

Signals of `view`, named for what happened, with copies as arguments. They come **in the step of the tick** shown (`SimWorld.TICK_ORDER`
is `fire, pending_problem, dock, pieces, sub, finale, triggers, creatures, contacts, pellets`); "between ticks" means a load or a call of the
owner (start of a flight, a trip, the owner resolving a problem), not a step. At any event the state calls above give the state **as of
that moment**: a creature's step is already made when `creature_picture_changed` comes, a pellet fired in `fire` has not moved yet.
A skin may ignore any event; none is needed for the rules to go on. The test of the table is `test_each_event_comes_in_the_step_of_the_tick_the_document_says`.

| Event | Arguments | When |
| --- | --- | --- |
| `sector_loaded` | `sector_index` | between ticks; the creatures exist (all of them). Also when the lock at the end station opens: the same sector, every creature from its start record (`screen_loaded` of the same screen follows) |
| `screen_loaded` | `sector_index`, `screen_index` | between ticks, or in `sub` when the sub flew out of a screen: build the screen from `pieces()`, `triggers()`, `is_solid()`, `pellets()` and the content; the pellets are gone after the sub flew out of a screen, and those in flight stay when the lock opens |
| `screen_changed` | `screen_index`, `direction` (`SectorData.Direction`) | `sub`; the sub left the previous screen through `direction`; `screen_loaded` came first |
| `creature_picture_changed` | `CreatureState`, `picture` | `creatures` (after all creature scripts ran), `sub` (a new screen), or between ticks (a load). Every creature's first picture is announced after a load |
| `creature_mirror_changed` | `CreatureState`, `mirrored` | as above |
| `creature_visibility_changed` | `CreatureState`, `shown` | as above (on the shown screen and not hidden) |
| `creature_hit_by_ink` | `CreatureState` | `contacts`; a pellet reached it (it becomes an ink cloud) |
| `creature_hit_by_sub` | `CreatureState` | `contacts`; the sub touched it (a skin may flash it) |
| `sub_damaged` | `damage`, `tank_lost` | `contacts`; `tank_lost`: the dissolve follows |
| `piece_collected` | `PieceState` | `pieces`; `piece.position` is where it lay; a `sound_requested` for the pick-up follows |
| `pieces_reset` | none | when the owner resolves the canister problem (a failed one lays the canister out again): read `pieces()` |
| `trigger_fired` | `TriggerState` | `triggers`; the trigger is disarmed |
| `problem_pending` | `slot` | `triggers`; a problem waits for ~36 ticks; `beacon_changed(true)` came just before it |
| `beacon_changed` | `lit` | the beacon on the sub (`sub().message_light`) went on: `triggers` (a trigger fired; how it blinks is the skin's, the original look shows it on every other propeller phase); or out: `pending_problem` or between ticks (the problem opens), `pieces` (the canister takes the countdown over), between ticks (a load: a respawn, a new sector) |
| `problem_requested` | `slot` | `pending_problem` (the countdown ran out) or between ticks (the player pressed Enter); the owner opens the problem |
| `problem_finished` | `slot`, `solved` | when the owner resolves the problem, which for one opened in `pending_problem` is in the middle of that tick. A problem that cost the tank ends that tick: no further step and no `ticked` follow (`DoAction` returns), and the sub is placed again by the respawn (`sub_placed`) |
| `pellet_fired` | `PelletState` | `fire`; it may already be splashing (fired facing the viewer) |
| `pellet_splashed` | `PelletState` | `fire`, `contacts` (hit a creature) or `pellets` (hit rock) |
| `pellet_gone` | `PelletState` | `pellets` (splash done, left the playfield), `sub` or between ticks (the screen changed) |
| `sub_placed` | `SubState` | between ticks; the sub was put somewhere by hand: do not glide; a dissolved sub is back |
| `dock_reached` | none | `dock`; the sub entered the dock rectangle |
| `finale_reached` | none | `finale`; the closing of the game begins |
| `sequence_started` | `SequenceState` | between ticks; "you have `ticks` ticks", `elapsed` is 0, the sub is where the trip starts |
| `sequence_finished` | `SequenceState` | `sub`, in game tick `started_tick + ticks - 1`; play goes on |
| `dissolve_started` | `ticks` | between ticks, or `contacts`; the game clock is held until `dissolve_finished` |
| `dissolve_advanced` | `elapsed`, `ticks` | between ticks (the owner feeds real time) |
| `dissolve_finished` | none | between ticks; the sub is gone until `sub_placed` |
| `sound_requested` | `sfx` (a name of `names/original.json`) | any step; the owner plays it, a skin may react |
| `ticked` | none | after the last step of every tick, and always last: **read the state now** |

The events of the flow of the game (the problem screens, the news, the Hall of Fame) are the owner's: `SectorWorld` passes them to `Game`,
and the presenter does not hear them.

## Writing one

```gdscript
class_name MySkin
extends SectorPresenter

var _sub_motion: SimView.Motion

func bind(sim_world: SimWorld) -> void:
	super.bind(sim_world)
	_listen(view.ticked, func() -> void: _sub_motion = view.sub().motion)
	_listen(view.pellet_fired, func(pellet: SimView.PelletState) -> void: add_child(make_ink_node(pellet.id)))
	for pellet in view.pellets():                     # (bound in the middle of a sector: the ink in flight is there already)
		add_child(make_ink_node(pellet.id))

func show_between_ticks(fraction: float) -> void:
	if _sub_motion != null:
		$Sub.position = _sub_motion.at(fraction)
```

Swap it in with `SectorWorld.replace_presenter(MySkin.new())` (or a scene), or `PresenterChoice`; a skin (`GameSkin`) brings it as its
`presenter_scene`. Tools to check your work:

* **The overlay.** `DebugRectPresenter` with `backdrop = false` laid over your presenter, bound to the same rules: the rectangles the rules
  test (walls, the sub's `hurt_rect` and `wall_rect`, every creature's `hit_rect`, pellets, pieces, triggers, the dock), so you can see whether a
  picture covers its rectangle. Key `O` in the sector viewer and (after F3) in the game, `-- --overlay` on the command line, `SectorWorld.set_overlay`.
* **Side by side.** `src/debug/skin_compare.tscn`: one sector, one set of rules, the original skin on the left and yours on the right, with the
  overlay on both. To build something like it yourself: set `presenter.skin` (a presenter dressed for a skin fetches its pictures from that skin
  whatever `SkinChoice.current()` is, `SkinChoice.within`) before the presenter enters the tree.
* **The tests.** `SkinVandal` and `SkinRecorder` in `godot/tests/` (a presenter against the API only), and the one that matters: every skin in
  `res://skins/` is played against the original over several sectors, switched at run time, and played through a whole mission in the real
  game, and must give the same event trace (`test_plays_identically.gd`, `test_skins_dont_change_the_game.gd`). A skin that is in `res://skins/`
  is in those tests with no further step.

## What the API does not promise

* `sim`, `SimView._sim` and other private members are not API. GDScript cannot enforce that: the test only proves that the documented API
  does not allow a change, and that a presenter using only it cannot alter a trace.
* Content (`Catalog`, `SectorData`, screens) is shared data; reading is free, changing it is not what a skin is for.
* A creature's script state (`pc`, registers) is not exposed; follow what it looks like.

## Writing a skin mod

A skin mod is a [mod pack](../engine/PACKS.md) (a pack whose `pack.json` has a `mod` entry) that is also a skin. It is code of a stranger, so the game runs it in the godot-sandbox extension with restrictions on and **grants it nothing**: it is called with the state of the sector as plain data and returns what to draw as plain
data, and the game checks the answer and draws it. It cannot reach the rules, the tree, another mod, a file by path or another pack, and it cannot change a hit rectangle, a wait or a tick (the same rules as above; `test_plays_identically.gd` and `test_skins_dont_change_the_game.gd` play a skin mod and a faulty one with every other skin). It needs the
extension (`uv run tools/fetch_sandbox.py`, [`SETUP.md`](../SETUP.md)); a skin with no script ("A skin with no script", below) does not. The worked example is `godot/tests/mods/skinny/` (`skinny.sgd`, `skin/glow.gdshader`).

```
pack.json     {"id": "reef", "title": "Reef", "version": "1.0", "base": "legacy",
               "mod": {"entry": "reef.sgd", "requires_api": 2, "skin": {"shaders": ["skin/glow.gdshader"]}}}
reef.sgd      the script (SafeGDScript, a safe GDScript: no classes of the game, no `load`, no nodes)
skin/*.png    the skin's pictures (PNG; any folder below skin/)
skin/*.gdshader   shaders as text, each listed in the manifest
```

The skin's id is the pack's id (not the id of a skin that ships); it appears in `SkinChoice.available()` while the pack is in use, so `--pack=reef --skin=reef` and F3 then S wear it. It keeps the game's HUD layout, screens and sounds, and dresses the pictures its manifest maps ("A skin with no script"). `pack_tool --check=<folder>` judges the manifest, the pictures, the shaders and the
presence of `skin_frame`; a skin that fails the check is refused with the reason when the game loads it.

### A skin with no script

A skin that only changes how the game's own pictures look needs no script, so no Sandbox: leave `entry` out. The worked example is the pack `examples/packs/modern/` ([`CONTENT.md`](CONTENT.md), "Skins and packs": its water shimmer, its Exo 2 lettering, its smooth filter and its templates). It is the same `ModSkin` in `SkinChoice` (the id is the pack's id; `--skin=<id>`, F3 then S), and it shows the sector with the original presenter. Four keys of `skin` say what it does (a manifest that has any of them, or no `entry`, says `"requires_api": 5`; a skin with a script may have the first three too, `layers` only a skin with no script has):

```
pack.json     {"id": "reef", "title": "Reef", "version": "1.0", "base": "legacy",
               "mod": {"requires_api": 5, "skin": {"render": {"texture_filter": "linear", "snap_transforms": false, "snap_vertices": false},
                                                   "pictures": {"ui_picture/title_sky": "skin/sky.png"},
                                                   "hud_font": {"file": "skin/hud.ttf", "size": 14, "color": "#dcf7ff"},
                                                   "shaders": ["skin/shimmer.gdshader"],
                                                   "layers": {"background": {"shader": "skin/shimmer.gdshader", "uniforms": {"glint": 0.25, "tint": "#ff8800"}}}}}}
skin/sky.png  a PNG of the pack
skin/hud.ttf  a TrueType font of the pack
skin/shimmer.gdshader  a shader of the pack, as text
```

* `render` is the `RenderSettings` the skin puts on the window while it is worn (`SkinChoice.select`): `texture_filter` is `"nearest"` (the original's), `"linear"`, `"nearest_mipmaps"` or `"linear_mipmaps"`; `snap_transforms` and `snap_vertices` are true (the original's) or false. A key it leaves out stays the project's.
* `pictures` maps a skin key `ui_picture/<name>` (the console's, the screens' and the story's pictures; `<name>` is the registry's name of the picture, or the made-up name of its number, `ui_1195`; `pack_tool --check` warns about a name the game never asks for) to a PNG of the pack's `skin/` folder, at most `ModSpec.MAX_PICTURES`. The skin's pictures are worn only while this skin is: another skin, and the original, show the base game's (a pack's own `pictures/` folder is different: it is the content's picture for a key and wins under every skin, [`CONTENT.md`](CONTENT.md) section 4).

**Art templates.** To draw the pictures a skin replaces at the right sizes, run `mise run skin:templates [--out <dir>] [--pack <id>]` (the tool scene is `res://src/skins/skin_templates_tool.tscn`, options `--out=<dir>`, `--pack=<id>`, `--list`; [`MAKING_CONTENT.md`](MAKING_CONTENT.md) B5). It writes, for every picture a skin may replace (now the console's: the bezel, the gauges' cells, the message lights and the label boxes), a PNG of the picture's size in one flat colour with its skin key and its size written on it, as `<dir>/ui_picture/<name>.png`. Draw the real art over a template, keep its size, and map its key to your file in `pictures`. The sizes are those of the pack's layout (`SkinTemplates`): the legacy pack's are the original's, the dev pack's are its own; the default is the legacy pack when you have one. A picture too small for the words (8 by 8 pixels) is flat colour: its file name is its key. The example pack `examples/packs/modern/` holds the console's templates, made from the legacy pack's layouts, as the files `skin/ui_picture/<name>.png` its `pictures` maps: copy the folder, draw over the templates and keep their sizes.

* `hud_font` letters the console's three boxes (game, zone, sector, and the custom-game box) as text in the pack's font while this skin is worn, instead of the original's pictures of the words. `file` is a `.ttf` of the pack's `skin/` folder (TrueType, at most `Pack.MAX_FONT_BYTES`; it is read from its bytes, no import), `size` the letters' size in pixels (`ModSpec.MIN_HUD_FONT_SIZE` to `MAX_HUD_FONT_SIZE`, default 14) and `color` the letters' colour (`"#rrggbb"` or `"#rrggbbaa"`, default the original's yellow). The words ("Voyager", "Dragon Reef", "First" ...) and the green of the boxes are the original lettering's; each box keeps the rectangle of the layout, so a larger font is cut off at the box and moves nothing. It is the skin's `GameSkin.hud_labels` (`HudLabels`), the field the project's skins set the same way ([`../engine/SKINS.md`](../engine/SKINS.md)). A file that is not a TrueType font, or larger than the limit, refuses the skin with that reason (`pack_tool --check` says it first); a `.ttf` in the pack that no manifest names is a warning.

* `layers` puts a shader on a layer of the original presenter. The layers are, back to front, `background` (the picture behind the screen), `back_decos`, `walls` (the tiles the rules read), `station`, `mid_decos`, `collectibles` (the pieces), `sub`, `foes` (the creatures), `pellets` (the ink), `front_decos`, `anim_decos` (the swaying decorations) and `bubbles` (`SkinLayers.NODES` is the list). Each entry names one of the skin's `shaders` (text files `skin/<name>.gdshader`, at most `ModSpec.MAX_SHADERS`, held to the small language of `ModShader`: `shader_type canvas_item`, no preprocessor, no loops, at most `ModShader.MAX_BYTES`) and may set its `uniforms`: a number (a `float`, or an `int` when it is whole), `true` or `false` (a `bool`), a list of 2, 3 or 4 numbers (a `vec2`, `vec3` or `vec4`) or a colour string `"#rrggbb"` / `"#rrggbbaa"` (a `vec4`, or a `vec3` without its alpha); at most `ModSpec.MAX_LAYER_UNIFORMS` of them, every number from -`ModSpec.MAX_UNIFORM_VALUE` to `MAX_UNIFORM_VALUE`. A uniform the shader does not declare, or one a value of that kind cannot fill (a `sampler2D`, a colour for a `float`), refuses the skin with that reason (`pack_tool --check` says it first), and so does a layer that names a shader the skin does not list. The shader is drawn on every picture of the layer, those the game makes later too (a creature, a pellet), and the sub's dissolve is its own shader while it runs. The game sets `uniform float phase`: the game's time, the ticks so far plus the fraction of the current one (`SectorPresenter.game_phase`), which stands still while the game clock does (a problem or a message is open, the sub dissolves, a pause) and runs at the speed of play otherwise, which a shader's `TIME` cannot do; a manifest cannot set it. A shader changes how a picture looks and nothing else: the rules, the timing and the hit rectangles do not know it. Each presenter has its own copy of a layer's material, built from the skin when the presenter is made, so a skin put on in the middle of a sector shows what one put on at the start shows, and another skin takes the shader away with it. The worked example is `godot/tests/mods/skin_data/`.

A picture or font file is read once, when the pack is chosen; a changed manifest or script is a new skin when the pack is chosen again. Nothing here can change a rule or a wait: it is data the game dresses its own pictures with (`test_plays_identically.gd`, `test_skins_dont_change_the_game.gd` and `test_presenter_binds_late.gd` play the worked example, `godot/tests/mods/skin_data/`, with every other skin).

### The script

```
var api : Dictionary = {}

func mod_init(granted : Dictionary) -> void:
	api = granted                  # keep the dictionary; do not keep one of its Callables on its own

func skin_frame(state : Dictionary, fraction : float, events : Array) -> Array:
	var out := []
	out.append(["rect", Rect2(0, 0, 608, 288), Color(0.02, 0.10, 0.18)])
	var sub : Dictionary = state["sub"]
	if sub["active"] and sub["visible"]:
		var centre : Vector2 = sub["previous"].lerp(sub["current"], fraction)
		out.append(["picture", "skin/sub.png", Rect2(centre - Vector2(48, 27), Vector2(96, 54)), sub["mirrored"]])
	return out
```

`skin_frame` is called once per drawn frame (`show_between_ticks`) and when the game shows the whole state again (`refresh`). It takes the state, how far into the tick the frame is (`fraction`, 0 to 1: put each moving thing at `previous.lerp(current, fraction)`, as `Motion.at` does) and the events since its last call, and returns the draw list. It runs under the
mod's limits (`limits` in the manifest's `mod`, never above the game's ceilings: instructions per call, memory, allocations, references; a skin's instruction limit is at most 10 million, because it is called every frame, and no limit can be 0): a call that goes over them is stopped and counts as a fault; a call that raises, or returns something that is not an Array, leaves the last good frame on, and a skin that faults `ModLoader.MAX_FAULTS` times is quarantined and replaced by the original skin.
Build the picture from `state`, never from what the script remembers of the events (rule 5 above): a skin started in the middle of a sector draws what one started at the beginning draws. `api["skin"]` has the plain facts a skin needs: `columns`, `rows`, `tile` (16), `playfield` (608 x 288), the caps below (`max_commands`, `max_layers`, `max_uniforms`, `max_texts`, `max_text`, `min_font_size`, `max_font_size`) and the manifest's `shaders`.

A script may hold only so many of the game's objects at a time (`references_max`, at most 100 handles at once): build the draw list with `append`, not one literal that holds every command at once, and walk each array of `state` once.

### The state

A read-only Dictionary, made again after any event (`SkinState.build`; places are playfield pixels as in "The coordinates"). Only values: numbers, bools, Strings, `Vector2`, `Rect2`, `Color`, Arrays and Dictionaries.

| Key | Value |
| --- | --- |
| `sector`, `screen`, `zone`, `tick` | where we are; `tick` is `view.tick_number` |
| `sub` | Dictionary: `previous`, `current` (the centre of its 96 x 54 picture), `cell`, `propeller_phase`, `picture`, `mirrored`, `visible` (false on the off ticks of the blink), `bubble` (-1: none), `invulnerability`, `blinking`, `beacon`, `active`, `controlled`, `hurt_rect`, `wall_rect` |
| `creatures` | Array of the creatures that are shown: `index`, `picture`, `mirrored`, `previous`, `current` (the top-left corner of the picture), `jumped`, `was_hidden`, `damage`, `hit_rect` |
| `pellets` | Array: `id`, `splashing`, `splash_picture`, `splash_offset`, `previous`, `current` |
| `pieces` | Array: `index`, `canister`, `position` |
| `sequence` | null before the first supply trip, else `kind`, `ticks`, `started_tick`, `elapsed`, `done`, `drive`, `door` (the door's picture, -1 open), `balloon_previous`, `balloon_current`; progress is `(elapsed - 1 + fraction) / ticks`, 1.0 when `done` |
| `dissolve` | `running`, `elapsed`, `ticks`, `progress` (0..1), `done` (the sub has dissolved away) |
| `walls` | one String of `columns * rows` characters, `"1"` for a wall tile and `"0"` for water: the tile at (column, row) is `walls[row * columns + column]` |

The triggers and the water currents are not in it (invisible in the game; the rectangles of the overlay are the author's tool, `O`).

### The events

`events` is an Array of `[name, arguments...]` with the names, order and meaning of "The events" above (`ticked` last of a tick). An argument is a number, a bool, a place or a name: a creature, a piece or a trigger is its `index`, a pellet its `id`, a supply trip its `kind`, a sound its name; the sub is not passed (it is in `state`). The newest `SkinState.MAX_EVENTS` are kept. Every element a script reads costs it instructions (a skin has at most 10 million per call): a skin that draws from `state` alone leaves the list unread.

### The draw list

`skin_frame` returns an Array of commands (the same list, checked by the same code, is what a mod returns to draw a problem screen: [`CONTENT.md`](CONTENT.md), "Problem screens"), drawn in order, each an Array whose first element is its name. Everything the script can draw is here:

| Command | Draws |
| --- | --- |
| `["rect", Rect2 area, Color]` | a filled rectangle |
| `["line", Vector2 from, Vector2 to, Color, float width]` | a line |
| `["picture", "skin/x.png", Vector2 or Rect2 where, mirrored?, Color?]` | a picture of the pack: a `Vector2` puts its top-left corner there at its own size, a `Rect2` stretches it; `mirrored` (bool) flips it left to right; the Color multiplies it (alpha fades it) |
| `["region", "skin/x.png", Rect2 where, Rect2 source, mirrored?, Color?]` | the part `source` (pixels of the picture) stretched into `where`: a tile of a sheet |
| `["text", "words", Vector2 where, int size, Color, float width?, "left" or "center" or "right"?]` | one line of text in the game's font (there is one: a mod names none), its top-left corner at `where`; with a `width` the line is aligned in that width (`"left"` by default) and clipped to it |
| `["layer", "skin/x.gdshader" or "", {"name": value, ...}?]` | starts a new layer, drawn through that shader (a file the manifest lists) with those uniforms; `""` is no shader. The list starts in an unshaded layer |

The game drops, and counts, every command that is not exactly one of these: another name, a wrong number or type of arguments, a number that is not finite or beyond +-100000, a negative size, a path that is not a plain `skin/....png` of the skin's own pack or that the pack lacks, a shader the manifest does not list (and what follows it up to the next layer: it is never drawn unshaded), a uniform whose name is not
`[a-z_][a-z0-9_]*` or whose value is not a number, bool, `Vector2` or `Color`. A text longer than `max_text` (200) characters is cut and a control character in it becomes a space; its `size` is held to `min_font_size` to `max_font_size` (6 to 64) pixels; a list holds at most `max_texts` (200) of them. At most `max_commands` (4000) commands, `max_layers` (8) layers and `max_uniforms` (16) uniforms per layer count; the rest is dropped. Drawing is clipped to the playfield. Nothing here can give the script a node, a texture or a material.

### Shaders

A shader is a text file `skin/<name>.gdshader` of the pack, listed in the manifest (at most 8). The game reads it as text, checks it (`ModShader`) and compiles it; the script only names it in a `layer`. It must be a `shader_type canvas_item;` of at most 8192 bytes with a `fragment()`, `vertex()` or `light()` function, with matching brackets, no preprocessor line (no `#include`, no `#define`) and no loop (`for`,
`while`, `do`: a loop that never ends would freeze the graphics card). A shader that breaks one of these refuses the whole skin, with the reason, when the pack is checked and when the game loads it. The renderer is the compiler: a shader it cannot compile logs its error and changes nothing else (a headless run has no renderer).

### What a skin mod cannot do

Everything not in the lists above: the script has no class of the game, no node, no `get_node`, no `load` (the pictures are named in the draw list, not loaded), no file, no shader or material of its own, no other pack and no other mod (`tests/mods/skin_hostile/` tries all of it and every attempt is refused), and what it is handed is read-only. A skin mod is as safe to install as a data pack in everything but memory:
the sandbox bounds the script's own memory and instructions, not data it asks the host to build (`docs/ROADMAP.md`, Open items).
