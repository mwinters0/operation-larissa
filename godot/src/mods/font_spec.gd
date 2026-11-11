class_name FontSpec
extends RefCounted
## A font as a skin's manifest says it: a `.ttf` of the pack's `skin/` folder, a weight and a size in pixels. The ONE parser of that object, for `hud_font` (the console's lettering) and for the font of a skin's `theme`
## (the menus' default font), so the two cannot differ in what they accept, what they refuse or how they make a font: `parse` judges the manifest (`ModSpec` calls it), `font` makes the `Font` from the pack's file.
##
##     {"file": "skin/fonts/Exo2.ttf", "weight": 600, "size": 14}
##
## `file` is read through the pack's door (`Pack.font`: from its bytes, no import). `weight` (`MIN_WEIGHT` to `MAX_WEIGHT`) is the `wght` axis of a VARIABLE font (Exo 2 has one): the font is a `FontVariation` whose
## `variation_opentype` is that weight; a font with no such axis ignores it. `size` is in pixels, within the range the caller allows (a console box and a menu have their own).
##
## Teaches: a font is a base font plus how it is varied: `FontVariation` wraps any font and changes its OpenType axes (weight, width, slant), its spacing and its transform without a second file.

const KEYS: Array[String] = ["file", "weight", "size"]
## The weights a manifest may ask for: CSS's scale (400 is regular, 700 bold).
const MIN_WEIGHT := 100
const MAX_WEIGHT := 900
## The OpenType axis of weight, `wght`, as the number a font's variation names it by (the four letters' bytes).
const WEIGHT_TAG := 0x77676874

## The file of the pack (`skin/....ttf`), "" for none: the font in force is then the default one of whoever asked (the menus' theme, or the engine's).
var file := ""
## The weight on the `wght` axis, 0 for the font's own.
var weight := 0
## The size in pixels, 0 for none said.
var size := 0


## The spec `value` (the manifest's object) describes, or null with every mistake appended to `found`. `name` is what the manifest calls the object (it begins each sentence), `example` shows its shape, `allowed` are the keys the object may have
## (`KEYS` and what the caller reads itself: a colour), `sizes` is the smallest and largest `size` (x, y). The file may be left out.
static func parse(value: Variant, name: String, example: String, allowed: Array[String], sizes: Vector2i, found: Array[String]) -> FontSpec:
	if not value is Dictionary:
		found.append("\"%s\" must be an object like %s" % [name, example])
		return null
	var before := found.size()
	var spec := FontSpec.new()
	for key: String in value:
		if not allowed.has(key):
			found.append("\"%s\" has no \"%s\" (it has %s)" % [name, key, ", ".join(allowed)])
	if value.has("file"):
		if not value["file"] is String or not ModSpec.is_font_path(value["file"]):
			found.append("the font %s must be a file of the pack's %s folder ending .%s" % [JSON.stringify(value["file"]), ModSpec.SKIN_FOLDER, Pack.FONT_EXTENSION])
		else:
			spec.file = value["file"]
	if value.has("size"):
		if not ModSpec.is_whole(value["size"]) or int(value["size"]) < sizes.x or int(value["size"]) > sizes.y:
			found.append("the font's \"size\" must be a whole number from %d to %d" % [sizes.x, sizes.y])
		else:
			spec.size = int(value["size"])
	if value.has("weight"):
		if not ModSpec.is_whole(value["weight"]) or int(value["weight"]) < MIN_WEIGHT or int(value["weight"]) > MAX_WEIGHT:
			found.append("the font's \"weight\" must be a whole number from %d to %d" % [MIN_WEIGHT, MAX_WEIGHT])
		elif not value.has("file"):
			found.append("a \"weight\" is the weight of the \"file\" it is with: \"%s\" needs a \"file\"" % name)
		else:
			spec.weight = int(value["weight"])
	return spec if found.size() == before else null


## The font of the pack `pack` this spec describes: its file (`Pack.font`), varied to its weight when it has one; null when it names no file or the pack has no usable font by that name (`Pack.font_problem` says why).
func font(pack: Pack) -> Font:
	if file.is_empty():
		return null
	var base := pack.font(file)
	if base == null or weight == 0:
		return base
	var varied := FontVariation.new()
	varied.base_font = base
	varied.variation_opentype = {WEIGHT_TAG: float(weight)}
	return varied


## The keys the manifest writes for this spec (what the spec says: nothing for a size or weight that is 0), for the keys of `KEYS` only.
func to_dict() -> Dictionary:
	var written := {}
	if not file.is_empty():
		written["file"] = file
	if weight != 0:
		written["weight"] = weight
	if size != 0:
		written["size"] = size
	return written
