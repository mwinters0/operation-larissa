# Your first skin

A tutorial: from a copy of the example pack to a skin of your own that you can hand to someone else. You change how the game *looks*
(the console's pictures, the lettering, a shader on the water and on the creatures) and nothing of how it plays. No script and no Godot
editor is needed: a skin like this is a folder of text and pictures.

Written for a teacher, a student or an artist who is comfortable in a terminal and in an image editor, and has not read this
codebase. Two pages come with it, and this one links to them instead of repeating them:

- [`SKIN_API.md`](SKIN_API.md), "A skin with no script": the reference for every key of the manifest and every limit. When a step
  below says "see the reference", that is where the full rule is.
- [`CONTENT.md`](CONTENT.md), "Skins and packs" and "Where packs are found": what a pack is, how the game finds one, what is committed.

The tutorial uses the example pack `examples/packs/modern/` (water shimmer, Exo 2 lettering and menus, smooth filtering, the console's
templates). Packs and skins in general, and the skins that are scenes and scripts of the project, are
[`MAKING_CONTENT.md`](MAKING_CONTENT.md) Part C; a skin that draws with a script is "Writing a skin mod" in `SKIN_API.md`.

You will make a skin called **reef** and, along the way:

- play the example, then your copy of it under your own id;
- make the **art templates** and draw one picture over its template;
- swap the **font** of the console's lettering, and dress the **menus** in it;
- write a **shader** that uses the game's time (`phase`), and set its values from the manifest;
- **check** the pack, **install** it, and write the `.larissa` file you can give away.

## 1. Before you start

1. **The legacy pack.** The example is laid over `legacy` (its `base`): the skin dresses the original game's pictures, so the original
   has to be built from your copy first ([`LEGACY.md`](../play/LEGACY.md)).
2. **The tools.** `mise` and the Godot it pins ([`SETUP.md`](../SETUP.md)). The commands below are written for a terminal in the
   repository root; each one is the `mise run` task, or the `tools/godot.sh` line the task runs.
3. **An image editor** that writes PNG with transparency (GIMP, Krita, Aseprite, Photoshop, anything). A text editor for the manifest and
   the shaders.

## 2. Copy the example and play it

Packs the project owns live in `godot/packs/<id>/`. Everything in that folder except `dev/` is git-ignored ([`godot/packs/README.md`](../../godot/packs/README.md)),
so it is the place to work: the game finds the pack there when it starts, and a change you save is in the game the next time you start it. No install step.

```sh
cp -r examples/packs/modern godot/packs/reef
tools/godot.sh --path godot -- --pack=reef --skin=reef
```

`--pack=` chooses the pack the game uses (your folder laid over `legacy`); `--skin=` wears its skin. The skin's id is the pack's id. In a
debug build you can also press **F3**, then **S**, to switch skins while you play. To play the example itself
instead, `mise run examples:install modern` installs it into the game's user folder and `--pack=modern --skin=modern` wears it
(`--uninstall=modern` of the pack tool takes it out again: step 8).

For a quick look at one screen without going through the menus, the sector viewer takes the same two options and can save a picture:

```sh
tools/godot.sh --path godot res://src/debug/sector_viewer.tscn -- --pack=reef --skin=reef --sector=1 --fly
# add  --ticks=30 --snapshot=/some/folder/shot.png  to run 30 ticks and save the window as a picture, then quit
```

A picture taken this way shows the original's art: do not commit it.

Now make it yours. Open `godot/packs/reef/pack.json` and change the first lines:

```json
{
 "id": "reef",
 "title": "Reef",
 "version": "1.0",
 "author": "your name",
 "description": "What your skin looks like, in a sentence.",
 "base": "legacy",
```

`id` is what `--pack=` and `--skin=` take, and it must be a name no other pack has. `base` is the pack your skin is laid over: the
game's pictures, sounds and levels come from there, and your skin changes only what its `skin` entry says.

## 3. The manifest, key by key

Everything a skin with no script says is under `mod.skin` in `pack.json`. The whole file is short enough to read at once; here it is
in the order of the keys, each with the sentence that says what it does and the place that says the rest.

| Key | What it does | Reference |
| --- | --- | --- |
| `"requires_api": 12` | the version of the skin API the manifest is written for. A manifest with `render`, `pictures`, `hud_font` or `layers` and no `entry` says at least 5, one with a `theme` (or a font `weight`) says 12 | `SKIN_API.md`, "A skin with no script" |
| `render` | filtering and pixel snapping while the skin is worn. The example's `"linear"` and `false` make the original's small pictures smooth; leave `render` out and the original's `"nearest"` stays | the first bullet of the list there |
| `hud_font` | the console's three boxes (game, zone, sector) as text in your font, with a size and a colour (step 5) | `hud_font` bullet |
| `theme` | the look of the menus (sign-in, the dialogs, the message box): a font, colours, panel and button styles, pictures by key (step 5) | "The menus' theme" |
| `shaders` | the list of shader files (text) of `skin/` the skin uses | `layers` bullet, "Shaders" |
| `layers` | a shader on a layer of the picture of a sector: `background`, `walls`, `foes`, and the others the reference lists, with values for the shader's `uniforms` (step 6) | `layers` bullet |
| `pictures` | a PNG of the pack for each picture of the console the skin redraws, by the picture's key (step 4) | `pictures` bullet |

The files sit in the pack under `skin/`: `skin/fonts/`, `skin/*.gdshader`, `skin/ui_picture/`. A file the manifest does not name is a
warning when you check the pack (step 7), and one it names that is not there is an error, so a typo does not go unnoticed.

What a skin never touches: a rule, a duration, a hit rectangle, the sounds, what a menu's controls are and do (only how they look). They are not keys of the manifest, and the
tests that play every skin against the original fail if one ever changed them ([`SKIN_API.md`](SKIN_API.md), "The rules a skin keeps").

## 4. The art templates, and a picture of your own

The example's `pictures` list holds 24 pictures: the console's. Each is a **template**, a flat colour at the original's size with the
picture's key and size written on it, so you can draw the real art at the right size without opening the original's files. (The
templates carry nothing of the original: the sizes come from the layouts, the lettering is made by the tool.)

Your copy already holds them. To make fresh ones (a template you painted over and want back, or the dev pack's sizes), from the
repository root:

```sh
mise run skin:templates --out $HOME/skin_templates
# the same, without mise:  tools/godot.sh --headless --path godot res://src/skins/skin_templates_tool.tscn -- --out=$HOME/skin_templates
```

It writes `ui_picture/<name>.png` under the folder (24 files) and replaces files of the same name, so aim it at a folder of its own and copy
what you need into `godot/packs/reef/skin/ui_picture/`. `--list` prints the keys and sizes without writing; `--pack=dev` takes the dev
pack's sizes; the default is `legacy` when you have it.

Which key is what (the key is `ui_picture/` and the name; the sizes are the original's):

| Names | Size | What it is |
| --- | --- | --- |
| `ui_1189` | 616 x 72 | the console's bezel: the panel behind everything below |
| `ui_1204`, `ui_1205` | 20 x 24 | a tank, full and empty |
| `ui_1206`, `ui_1207`, `ui_1208` | 20 x 20 | an oxygen cell: full, empty, low |
| `ui_1193`, `ui_1194` | 24 x 8 | an ink cell: full, empty |
| `ui_1210`, `ui_1211` | 52 x 26 | the ship's message light (two states) |
| `ui_1212`, `ui_1213` | 52 x 26 | the computer's message light (two states) |
| `ui_1190` to `ui_1192` | 48 x 20, 88 x 20 | the label boxes of the game ("Voyager", "Expert", custom) |
| `ui_1195` to `ui_1199` | 144 x 20 | the zone label boxes |
| `ui_1200` to `ui_1203` | 84 x 20 | the sector label boxes |

(That is the fields of `HudLayout` as the legacy pack sets them. The numbers are the importer's names for pictures the original never
gave a name; `pictures` takes them as they stand.) While `hud_font` is set, the label boxes are lettered as text instead
([`SKIN_API.md`](SKIN_API.md), "A skin with no script"): their pictures `ui_1190` to `ui_1203` matter when you take `hud_font` out.

**Draw one.** Start with the bezel: open `godot/packs/reef/skin/ui_picture/ui_1189.png` in your editor and paint over it. Keep the file's name and its size. A picture of another size is
drawn into the place the original's had (stretched to it, so a drawing at twice the size fills the same place); keep the proportions. Save as PNG, in the same place under the same name. Start the game again (step 2): the new bezel is there.

**Keep only what you drew.** The example maps all 24 templates, so every picture you have not drawn yet shows its flat colour with its
key on it. Open `pictures` and remove the keys you have not drawn: a picture the skin does not map is the original's. Add a key as
you finish a picture.

```json
"pictures": {
  "ui_picture/ui_1189": "skin/ui_picture/ui_1189.png"
}
```

The value is a path under `skin/`; the key is the picture's, `ui_picture/` and the name. A key the game never asks for (`ui_picture/ui_9999`) is a
**warning** when you check the pack, and the picture is never drawn: it is the first thing to look for when a picture does not appear.

Draw only your own art. A picture made by tracing or editing the original's is the original's, and it does not belong in a pack you
give away.

## 5. The lettering

`hud_font` sets the font of the console's boxes:

```json
"hud_font": { "file": "skin/fonts/Exo2.ttf", "weight": 600, "size": 14, "color": "#dbf7ff" }
```

`weight` (100 to 900) picks the heaviness of a **variable** font such as Exo 2 (600 is its semibold); a font with one weight ignores it.

To use a font of your own: put a `.ttf` under `skin/` (a TrueType file: the game reads `.ttf` only), point `file` at it, and choose the size (6 to 32) and the colour
(`"#rrggbb"`). Delete the font you no longer use: the old file is a warning when you check the pack, as is any `.ttf` the manifest does not name.
The words and the boxes' green are the original's: the boxes keep their rectangles, so a font too large for them is cut off at the box. Use a
font you may share: the example's Exo 2 is under the SIL Open Font License, and its licence text, `OFL.txt`, travels beside it in
`skin/fonts/` ([`fonts/README.md`](../../examples/packs/modern/skin/fonts/README.md)). Do the same with yours.

**The menus.** The same font can dress the menus too. `theme` says how the sign-in screen, the dialogs and the message box look: a default
font, named colours, and the styles of panels and buttons, each field optional and laid over the engine's own:

```json
"theme": {
  "font":    { "file": "skin/fonts/Exo2.ttf", "weight": 600, "size": 16 },
  "colors":  { "title": "#7fe0ff", "button": "#bfe9f7" },
  "console": { "fill": "#07151f", "border": "#5fd0f0", "radius": 10 },
  "button":  { "normal": { "fill": "#123347", "radius": 6 }, "hover": { "fill": "#1c5675" } }
}
```

Put it in (the manifest says `"requires_api": 12`), start the game and open a dialog: the message box, with its title in your colour and its
frame in your fill, is the quickest look. Leave `hud_font`'s `file` out and the console's boxes use the theme's font, so one font dresses the console and the menus.
A style may also be a picture of yours: `"pressed": { "picture": "ui_picture/button_pressed", "slice": [4, 4, 4, 4] }` (map the key in `pictures`; `slice` is
the margins of the picture that stay unstretched). The controls keep their places and what they do: only fonts, colours, borders and pictures change.
The keys, their bounds and what each name dresses are in [`SKIN_API.md`](SKIN_API.md), "The menus' theme".

## 6. A shader, and the game's time

A **shader** is a small program on the graphics card that decides the colour of each point of a picture. A skin with no script
can put one on any layer of the sector (`background`, `walls`, `foes`, ...: the list is in the reference). The example has two,
`skin/water_shimmer.gdshader` (the water behind the screen) and `skin/sharp_walls.gdshader` (keeps the walls sharp under the smooth filter);
read the first: its comments say what each line does.

**Tune what is there.** The water's shader declares `uniform` values (`waver`, `glint`, `cell`). The manifest can set them, per layer:

```json
"layers": {
  "background": { "shader": "skin/water_shimmer.gdshader", "uniforms": { "glint": 0.25, "waver": 3.0 } },
  "walls":      { "shader": "skin/sharp_walls.gdshader" }
}
```

A number sets a `float` (or an `int`), a list of 2 to 4 numbers a `vec2` to `vec4`, `true` or `false` a `bool`, a string `"#rrggbb"` a colour.
A name the shader does not declare is an error when you check the pack, and it tells you the names it declares. Save, start the game, look at the water.

**Write one.** Make `godot/packs/reef/skin/glow.gdshader`:

```glsl
shader_type canvas_item;
// A slow glow on the creatures: their picture, a little brighter and bluer, then back.

uniform float phase = 0.0;                       // the game's time (the game sets it)
uniform float strength : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform vec4 tint : source_color = vec4(0.4, 0.8, 1.0, 1.0);

void fragment() {
	vec4 picture = texture(TEXTURE, UV);
	float pulse = 0.5 + 0.5 * sin(phase * 0.5);   // 0 to 1; one round is about four seconds
	picture.rgb = mix(picture.rgb, tint.rgb, pulse * strength * picture.a);
	COLOR = picture;
}
```

List it and put it on the creatures' layer:

```json
"shaders": [ "skin/water_shimmer.gdshader", "skin/sharp_walls.gdshader", "skin/glow.gdshader" ],
"layers": {
  "background": { "shader": "skin/water_shimmer.gdshader" },
  "walls":      { "shader": "skin/sharp_walls.gdshader" },
  "foes":       { "shader": "skin/glow.gdshader", "uniforms": { "strength": 0.6, "tint": "#66ccff" } }
}
```

**`phase`** is the game's time: ticks so far plus the fraction of the tick being drawn (about 12 a second). Declare `uniform float phase`
and the game fills it every frame; a manifest cannot set it. Use it where you would use Godot's `TIME`, and for this reason:
`TIME` never stops, `phase` stands still when the game does (a message box, a problem, the sub dissolving, a pause) and the same
moment of the same sector always looks the same, which makes a picture you took repeatable.

The rules of the small shader language (`shader_type canvas_item;`, no `#include`/`#define`, **no loops**, at most 8192 bytes, at most 8 shaders) are
in [`SKIN_API.md`](SKIN_API.md), "Shaders". A shader only changes how a picture looks; it cannot reach a rule, a wait or a hit rectangle.

**Two kinds of mistake, found in two places.** The pack check (next step) reads a shader as text: a loop, a preprocessor line, a size over the limit, a
uniform the shader does not declare, a layer that names a shader the skin does not list. What the graphics driver says about the
shader (a misspelt name, a wrong type) is printed in the terminal as `SHADER ERROR: ...` with the line, when the skin is made, and the pack check may still say "no problems" after it: read what is printed above the verdict.
A shader that does not compile changes nothing else, so a skin whose creatures do not glow and whose terminal says `SHADER ERROR` has a typo in `glow.gdshader`.

## 7. Check the pack

```sh
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --check=godot/packs/reef --no-reach
```

(`--no-reach` skips the reachability search of a pack's sectors, which a skin has none of.) It prints `reef: no problems`, or the warnings and errors, and the exit
code is 1 when there is an error. What it says of a skin: the manifest, the pictures named and where they are, the font and the theme, a file
the manifest never names, the shaders as text, and the uniforms. Examples of what it prints:

```
  error: manifest: the font's "size" must be a whole number from 6 to 32
  error: mod: the layer "background" sets "glimt", which skin/water_shimmer.gdshader does not declare (it declares phase, picture_size, waver, glint, cell)
  error: mod: skin/glow.gdshader uses `for`: a mod's shader has no loops
  warning: mod: the skin's picture ui_picture/ui_9999 names no picture of the game: it is never asked for
  warning: mod: skin/fonts/Exo2.ttf is never used: a skin names its font in "skin": {"hud_font": {"file": ...}} or {"theme": {"font": {"file": ...}}}
```

Errors refuse the skin when the game loads it, with the same reason; warnings do not. Check after every change to the manifest, a shader or a font. The editor's "Check pack..." in Project > Tools runs the same
code ([`MAKING_CONTENT.md`](MAKING_CONTENT.md), section 10).

## 8. Install it, and give it away

A pack in `godot/packs/` is yours alone: it is in your project, not in your game's user folder, and not in a copy of the game you give someone else. To hand it over, write the pack file:

```sh
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --archive-folder=godot/packs/reef --out=$HOME/packs --no-reach
```

That writes `$HOME/packs/reef.larissa`: the folder as one file, checked first. The task for the
example is `mise run examples:pack modern [--out <dir>]` (it writes `modern.larissa`: `--archive-folder=examples/packs/modern`).

To try the file the way a friend would:

```sh
tools/godot.sh --headless --path godot res://src/packs/pack_tool.tscn -- --install=$HOME/packs/reef.larissa
tools/godot.sh --path godot -- --pack=reef --skin=reef
```

`--install=` copies a pack (a folder or a `.larissa`) into the game's user folder, `user://packs/` (the pack screen, **P** on the sign-in screen, does the same with
a button). The id must not be one the project already has: an installed `reef` and a `godot/packs/reef/` are the same id, and the
project's folder is used first ([`CONTENT.md`](CONTENT.md), "Where packs are found"), so take your working folder out of the way, or use another id, to see the installed one.
`--list` shows what is found and which is used; `--uninstall=reef` takes the pack out of `user://packs/` again.

Whoever installs your pack needs the game pack it is laid over: `reef.larissa` says `"base": "legacy"`, so they build the legacy pack from their own
copy of the game ([`LEGACY.md`](../play/LEGACY.md)) like everyone who plays it. Your file holds only your files. The pack screen does not choose a skin: a player starts the game with
`--pack=reef --skin=reef`.

Before you share it, read your own `pack.json` again (`title`, `author`, `description`, `version`) and keep the licences of everything in it: a font's licence
file beside the font, and nothing in `skin/` that is not yours to share.

## 9. Where to go next

- Redraw more pictures: the same steps, one key at a time. The templates tool writes one template for every picture a skin with no script may replace
  (the console's); what is planned beyond it is in [`ROADMAP.md`](../ROADMAP.md).
- A shader on the sub, the pellets or the decorations: the layers are listed in `SKIN_API.md`; a new layer is one more line of `layers`.
- Compare your skin with the original, side by side, and see the rectangles the rules test: `res://src/debug/skin_compare.tscn` and the **O** key
  ([`MAKING_CONTENT.md`](MAKING_CONTENT.md), C3).
- A skin whose script draws a layer of the sector, or all of them, in a sandbox: "Writing a skin mod" in [`SKIN_API.md`](SKIN_API.md).
- How the engine builds this skin from the manifest: [`SKINS.md`](../engine/SKINS.md) and [`PACKS.md`](../engine/PACKS.md), "Mod packs".
