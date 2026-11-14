# Generated pictures for redistributable packs

How we make packs of new pictures with image generation and ship them. This file is the working rules and technique for the agent that
does the work. It is not legal advice.

## Goal

A pack anyone may download, holding only **pictures**: new art for keys the game already has, replaced through the pack's `pictures.json`
and layered over the player's own legacy import ([`create/CONTENT.md`](../create/CONTENT.md), "The picture table"). It carries none of
the original's levels, scripts, texts or sounds, and none of its pixels. Every picture is independent work: made without the original
art as input, and not recognizably any original picture.

## The line

Free to use: what a picture *does* (its key, size, frame count, place on the screen, hitbox), the genre, the setting's stock elements
(kelp, coral, rivets, sonar, portholes), and a general period style. Protected: the original drawings themselves (their composition,
silhouettes and details) and recognizable designs. Using a generator changes nothing. Overall look decides, so a faithful copy with a
detail changed is still a copy. The sub is the one design close to a character. We design our own from its function (a small research
submarine with a signal light for an incoming problem) and do not adjust the original's.

## Rules of the work

1. **No original pixels go to a generator or a service.** That covers screenshots, extracted art, crops and "style references". Inputs
   are text, the art templates, the dev pack's art, our own sketches, and our own earlier outputs. A screenshot of the running game shows
   legacy art wherever our pack does not yet cover a key. So a mock screen is built from our own files, or a game screenshot is sent
   only when every picture on it is ours (the run's coverage, `Packs.picture_decision()`, names the keys still uncovered).
2. **Prompts come from function**, from a spec for each key (below). They never name the game, its characters, or describe an original
   picture.
3. **Side-by-side gate.** Before an output is accepted, and before it seeds other frames, compare it with the original picture of its
   key, viewed locally. Reject anything someone who knows the game would call "the same picture, redrawn". The user does the final
   review of a set.
4. **Human work on every picture**: cleanup, one palette, consistency across the set, our own lettering. It makes the art coherent and
   gives the pack copyright, which purely generated images may not have.
5. **Provenance for every picture** (below), shipped in the pack.
6. **The service's terms are checked before first use**: who owns the output, whether redistribution and commercial use are allowed,
   whether uploads train the model, and any indemnity. Record the service and the date the terms were read in the provenance file.

## Inputs: sizes and keys

- **Console and problem frame** (`ui_picture`, `problem_art`, `hud_layer`): the art templates, `mise run skin:templates --pack legacy`
  ([`create/SKIN_API.md`](../create/SKIN_API.md), "Art templates"). They hold a key and a size only, read from the layouts.
- **Sprites, tiles, backgrounds and story pictures** have no templates. Take each key's size and frame count from the legacy pack's data
  (its `pictures.json` and sprite frames), as numbers only.
- A spec for each key, kept beside the work: key, size, frames, what it must convey in play (the readable states, a danger colour, where an
  opening is, the hitbox it must fill), and its neighbours in the set it must match.

## Technique

**One look, fixed before the set.** A style sheet comes first: a fixed palette (a set number of colours), the light direction, an outline
rule, a short list of materials, a pixel density per game unit, and the viewpoint (side elevation for the sector view). Next comes an
anchor set: one wall tile, one background, the sub's side view, one creature and the console bezel, put together into a mock gameplay
screen. The user approves the look on that screen before anything else is made. Every later prompt is given the anchors as image
references. One model at one pinned version makes the whole set; a local model with a small style adapter trained on the anchors gives
the most control.

**A second pass for coherence.** With a screen's worth of pictures made, compose the mock screen again to find the outliers. Fix them
first with our own scripts, applied to every file: a remap to the palette, one colour grade (a lookup table), one outline and dithering
pass. Only a picture still out of place goes back to the generator, with the mock screen as its reference. A whole screen is never
regenerated, since that breaks sizes and registration, and every changed picture goes through the gate again.

**Geometry the model cannot get wrong.** Prompting does not prevent impossible shapes (extra fins, an impossible hull); giving the model the
shape does. Make a simple 3D blockout (boxes and cylinders) of an approved object, render each pose as depth, lines or a silhouette, and
generate over it with structure guidance (ControlNet or the service's equivalent), so the model paints only the surface. Ask for flat side
elevations and orthographic views, which models draw far better than dramatic perspective. Generate many candidates and choose; fix a
local fault by inpainting its region. Geometry checks join the gate: the silhouette fills the hitbox, the shape is symmetric where the
object is, the shape changes smoothly from frame to frame, and the count of parts matches the spec.

**Resolution.** Generate large and ship at 4x: `"picture_scale": 4` in `pack.json`, each file four times the template's size
([`create/CONTENT.md`](../create/CONTENT.md), "The picture table"). Bring every picture to one fixed palette and pixel grid at the end, not
one at a time.

**Animated pictures (the sub, creatures).** Iterate on one defining frame (the side view) until it passes the gate and the user approves
it. Derive the other frames from it ("this submarine, three-quarter view"), asking for a turnaround sheet in **one image** rather than
one call per pose, since a model stays consistent within an image. Better still, generate each pose over the blockout's render of
it (above), so the frames agree in shape. Then register every frame to one anchor, scale and light direction.
Frame counts are the data's: a skin never changes timing.

**The console and the calculator.** Generate a whole part (the console, the calculator keypad) as **one image**, so the parts look like
one object, guided by a wireframe of the layout's rectangles (the templates placed at their layout positions; flat boxes and our own
lettering only). Slice it by the layout's rectangles into the template files. Make state variants (lit and unlit keys, pressed states,
gauge fill levels) by masked inpainting or hand edits of the accepted base, never as fresh generations, so they line up to the pixel. Do
not let a model draw text: digits and labels are drawn with a font whose license allows redistribution. For a nine-patch picture (a theme's
frame or panel), keep the stretched middle uniform. Wireframe and slicing tools: [`ROADMAP.md`](../ROADMAP.md), "Generated picture packs".

**Assembling the pack.** Put the files under `<kind>/<name>.png`, write the table with `pack_tool --pictures-table=<folder>`, run the pack
check, play it over legacy under each skin, then `mise run pack:archive` ([`create/FIRST_SKIN.md`](../create/FIRST_SKIN.md)).

## Provenance

`provenance.json` at the pack's root holds the `service` (name, model, the date its terms were read) and `pictures`, keyed by
picture key. Each picture lists its prompt or prompts, its inputs (by kind: text, template, dev art, sketch, or the key of our own output
it was derived from), its seed when the service gives one, its date, and the human edits made to it. With it, a challenged picture can be
shown to be independent work. It records only our own material, never the original's.
