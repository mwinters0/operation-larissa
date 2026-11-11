class_name SkinTemplates
extends RefCounted
## The art templates of a skin: for every picture a skin may replace, a PNG of the picture's size in one flat colour with the picture's skin key and its size written on it,
## for a person to draw the real art over (`docs/create/SKIN_API.md` "Art templates"; the command line is `skin_templates_tool.tscn`).
##
## TWO LISTS, never mixed. THE PICTURES A SKIN MAY REPLACE (`pictures`, `ModSpec.is_picture_key`): `SOURCES` is the table of the layout files (of the pack in use, as the pack holds them, no skin) whose pictures they are. Each texture a layout holds is a
## picture of its own, whose key and size are read off the texture: the key is the one `GameSkin.key_of` makes, which is the key a skin's `pictures` names (`ModSpec.REPLACEABLE_KINDS`), and the size is the texture's. The sizes come from the layout, so a
## template has nothing of any picture in it, only its key and its size. `PromptSender.picture_keys` adds the two pictures beside the first line of a prompt, which no layout holds (their size is `PromptSender.PICTURE_SIZE`, which the screen stretches to).
## The frame of the problem screen is among them: the screen picture (`problem_art/pa_1780`), the calculator (`pa_1781`), the "Ans:" panel (`pa_1802`) and the calculator's digits and signs are in the layouts of the screen and of the calculator.
## THE PICTURES A SCRIPT DRAWS, whole-part pictures of a screen (`layers`), not pictures a skin replaces (no `pictures` entry names them; they are drawn over and put in the skin's `skin/` folder, or in the `problems/` folder of a problem mod, named in a draw list):
## one for each layer of the console (`SkinLayers.hud_layers`, key `hud_layer/<layer>`, `hud_layer/hud_oxygen`), the size of the layer's rectangle in the HUD layout (`ConsoleState.rects`), and one for the whole 640 x 400 window of a problem screen
## (`problem_layer/window`, `ProblemState.WINDOW_SIZE`; `ModDiagram`, `docs/create/CONTENT.md` "Problem screens").
##
## THE SIZES ARE THE PACK'S. The dev pack's console has the sizes the dev pack made for itself; the original's are those of the legacy pack (`--pack=legacy` reads only the sizes, and writes none of the
## original's pixels).
##
## Teaches: drawing into an `Image` with no renderer (so it runs headless): a flat fill and a 3 x 5 pixel font of our own, since a `Font` draws only through the rendering server; and walking a
## `Resource`'s stored properties to find every texture in it, arrays included, the way `GameSkin` does to dress a layout.

## The layouts, as a path in a pack's `data/`, whose textures are the pictures a skin may replace.
const HUD_LAYOUT := "data/ui/hud_layout.tres"
const SOURCES: Array[String] = [HUD_LAYOUT, "data/problems/screen_layout.tres", "data/ui/calculator_layout.tres"]

## The glyphs: 3 pixels wide and 5 high, a row to an int (the left pixel is the 4s bit). Only what a key and a size are written with.
const GLYPHS := {
	"a": [2, 5, 7, 5, 5], "b": [6, 5, 6, 5, 6], "c": [3, 4, 4, 4, 3], "d": [6, 5, 5, 5, 6], "e": [7, 4, 6, 4, 7], "f": [7, 4, 6, 4, 4],
	"g": [3, 4, 5, 5, 3], "h": [5, 5, 7, 5, 5], "i": [7, 2, 2, 2, 7], "j": [1, 1, 1, 5, 2], "k": [5, 5, 6, 5, 5], "l": [4, 4, 4, 4, 7],
	"m": [5, 7, 7, 5, 5], "n": [6, 5, 5, 5, 5], "o": [2, 5, 5, 5, 2], "p": [6, 5, 6, 4, 4], "q": [2, 5, 5, 7, 3], "r": [6, 5, 6, 5, 5],
	"s": [3, 4, 2, 1, 6], "t": [7, 2, 2, 2, 2], "u": [5, 5, 5, 5, 7], "v": [5, 5, 5, 5, 2], "w": [5, 5, 7, 7, 5], "x": [5, 5, 2, 5, 5],
	"y": [5, 5, 2, 2, 2], "z": [7, 1, 2, 4, 7],
	"0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [6, 1, 2, 4, 7], "3": [6, 1, 2, 1, 6], "4": [5, 5, 7, 1, 1], "5": [7, 4, 6, 1, 6],
	"6": [3, 4, 7, 5, 7], "7": [7, 1, 2, 2, 2], "8": [7, 5, 7, 5, 7], "9": [7, 5, 7, 1, 6],
	"_": [0, 0, 0, 0, 7], "/": [1, 1, 2, 4, 4], " ": [0, 0, 0, 0, 0],
}
const GLYPH_WIDTH := 3
const GLYPH_HEIGHT := 5
## The most a letter is magnified (the largest that fits is used), and the empty pixels kept clear all round the words (none at all for a picture so small that nothing else would fit).
const MAX_SCALE := 3
const MARGIN := 1
const TEXT_COLOR := Color8(26, 26, 31)


## The kind of key a layer's template has: not a picture a skin replaces (no `pictures` entry names it) but the picture of a layer a script draws.
const LAYER_KIND := "hud_layer"
## The kind of key the whole window of a problem screen has (`problem_layer/window`), and its key.
const PROBLEM_LAYER_KIND := "problem_layer"
const PROBLEM_WINDOW := "window"

## One picture to draw: its skin key (`ui_picture/ui_1195`, `problem_art/pa_1780`, or `hud_layer/hud_oxygen` for a layer's) and its size.
class Entry extends RefCounted:
	var key := ""
	var size := Vector2i.ZERO

	func _init(picture_key: String, picture_size: Vector2i) -> void:
		key = picture_key
		size = picture_size

	## Where the template goes under a folder: the key's kind is a folder, its name the file (`ui_picture/ui_1195.png`).
	func rel_path() -> String:
		return key + ".png"


## Every picture to make a template of, in the pack in use: those a skin may replace (`pictures`), then those a script draws (`layers`).
static func entries() -> Array[Entry]:
	var found := pictures()
	found.append_array(layers())
	return found


## The pictures a skin may replace (`ModSpec.is_picture_key`), once each: those of the layouts of `SOURCES` in their order, then the prompt sender's. The key and the size.
static func pictures() -> Array[Entry]:
	var found: Array[Entry] = []
	var seen := {}
	for rel in SOURCES:
		var layout := Catalog.pack_resource(rel)
		if layout == null:
			continue
		for texture in _textures_in(layout):
			var key := GameSkin.key_of(Packs.source_of(texture))
			if not key.is_empty() and not seen.has(key) and ModSpec.is_picture_key(key):
				seen[key] = true
				found.append(Entry.new(key, Vector2i(texture.get_size())))
	for key in PromptSender.picture_keys():
		found.append(Entry.new(key, PromptSender.PICTURE_SIZE))
	return found


## The size of each picture a skin may replace in the pack in use, by key (`pictures`). What `PackCheck` compares a skin's PNG with.
static func sizes() -> Dictionary[String, Vector2i]:
	var found: Dictionary[String, Vector2i] = {}
	for entry in pictures():
		found[entry.key] = entry.size
	return found


## The pictures a script draws: a layer of the console for each of `SkinLayers.hud_layers()` (the size of its rectangle, from the HUD layout), and the problem screen's window.
static func layers() -> Array[Entry]:
	var found: Array[Entry] = []
	var hud := Catalog.pack_resource(HUD_LAYOUT) as HudLayout
	if hud != null:
		var rects := ConsoleState.rects(hud)
		for layer in SkinLayers.hud_layers():
			found.append(Entry.new("%s/%s" % [LAYER_KIND, layer], Vector2i((rects[String(layer)] as Rect2).size)))
	found.append(Entry.new("%s/%s" % [PROBLEM_LAYER_KIND, PROBLEM_WINDOW], ProblemState.WINDOW_SIZE))
	return found


## Every `Texture2D` the resource keeps in its stored properties, in an array too, in the order the properties are declared.
static func _textures_in(resource: Resource) -> Array[Texture2D]:
	var found: Array[Texture2D] = []
	for info in resource.get_property_list():
		if not (info.usage & PROPERTY_USAGE_STORAGE):
			continue
		var value: Variant = resource.get(info.name)
		if value is Texture2D:
			found.append(value)
		elif value is Array:
			for item: Variant in value:
				if item is Texture2D:
					found.append(item)
	return found


# --- drawing -----------------------------------------------------------------------------------------------------------------

## The template of `entry`: its size, one flat colour (the key's own, so that two pictures are easy to tell apart), the words in dark pixels.
static func image(entry: Entry) -> Image:
	var picture := Image.create_empty(entry.size.x, entry.size.y, false, Image.FORMAT_RGBA8)
	picture.fill(color_of(entry.key))
	var lines := _lines(entry)
	var scale := _scale_of(lines, entry.size)
	if scale > 0:
		_draw_lines(picture, lines, scale)
	return picture


## The colour of a key: a light colour whose hue is the key's (the same key always has it), exact in the 8 bits a PNG keeps.
static func color_of(key: String) -> Color:
	var sum := key.md5_buffer()
	var color := Color.from_hsv(float(sum[0] * 256 + sum[1]) / 65536.0, 0.35, 0.95)
	return Color8(color.r8, color.g8, color.b8)


## The words that go on a picture of this size: the key and the size, else the name and the size (the key without its kind), else the size alone, each cut into lines that fit, at the first
## of these that fits at all. Empty when not even the size does (a picture a few pixels wide is flat colour).
static func _lines(entry: Entry) -> PackedStringArray:
	var size_text := "%dx%d" % [entry.size.x, entry.size.y]
	var name := entry.key.get_slice("/", 1)
	for words: Array in [[entry.key, size_text], [name, size_text], [size_text]]:
		var lines := PackedStringArray()
		for word: String in words:
			lines.append_array(_cut(word, entry.size.x))
		if _scale_of(lines, entry.size) > 0:
			return lines
	return PackedStringArray()


## `word` cut into lines of as many letters as the width has room for.
static func _cut(word: String, width: int) -> PackedStringArray:
	var room := maxi(1, (width + 1) / (GLYPH_WIDTH + 1))
	var lines := PackedStringArray()
	for start in range(0, word.length(), room):
		lines.append(word.substr(start, room))
	return lines


## The size of one pixel of the lettering that makes `lines` fit in `size` with the margin (at most `MAX_SCALE`); one pixel without the margin when that is all that fits; 0 when they do not fit at all.
static func _scale_of(lines: PackedStringArray, size: Vector2i) -> int:
	if lines.is_empty():
		return 0
	for scale in range(MAX_SCALE, 0, -1):
		if _fits(lines, scale, MARGIN, size):
			return scale
	return 1 if _fits(lines, 1, 0, size) else 0


static func _fits(lines: PackedStringArray, scale: int, margin: int, size: Vector2i) -> bool:
	var block := _block_size(lines, scale)
	return block.x + 2 * margin <= size.x and block.y + 2 * margin <= size.y


## The pixels the lines take, a pixel of lettering being `scale` pixels, with a pixel of space between letters and `scale` pixels between lines.
static func _block_size(lines: PackedStringArray, scale: int) -> Vector2i:
	var widest := 0
	for line in lines:
		widest = maxi(widest, line.length())
	return Vector2i((widest * (GLYPH_WIDTH + 1) - 1) * scale, (lines.size() * (GLYPH_HEIGHT + 1) - 1) * scale)


## The lines in the middle of the picture, each in the middle of its row.
static func _draw_lines(picture: Image, lines: PackedStringArray, scale: int) -> void:
	var block := _block_size(lines, scale)
	var top := (picture.get_height() - block.y) / 2
	for row in lines.size():
		var line := lines[row]
		var left := (picture.get_width() - (line.length() * (GLYPH_WIDTH + 1) - 1) * scale) / 2
		for column in line.length():
			_draw_glyph(picture, line[column], left + column * (GLYPH_WIDTH + 1) * scale, top + row * (GLYPH_HEIGHT + 1) * scale, scale)


static func _draw_glyph(picture: Image, letter: String, x: int, y: int, scale: int) -> void:
	var rows: Array = GLYPHS.get(letter, GLYPHS[" "])
	for row in GLYPH_HEIGHT:
		for column in GLYPH_WIDTH:
			if (int(rows[row]) >> (GLYPH_WIDTH - 1 - column)) & 1 == 1:
				picture.fill_rect(Rect2i(x + column * scale, y + row * scale, scale, scale), TEXT_COLOR)


# --- writing -----------------------------------------------------------------------------------------------------------------

## Writes the template of every entry under `dir` (a path, `user://` too; `Entry.rel_path` below it). Returns the files written, and says in `failures` what could not be.
static func write(dir: String, failures: Array[String] = []) -> PackedStringArray:
	var written := PackedStringArray()
	for entry in entries():
		var path := "%s/%s" % [dir.trim_suffix("/"), entry.rel_path()]
		var made := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var saved := image(entry).save_png(path) if made == OK else made
		if saved == OK:
			written.append(path)
		else:
			failures.append("%s: %s" % [path, error_string(saved)])
	return written
