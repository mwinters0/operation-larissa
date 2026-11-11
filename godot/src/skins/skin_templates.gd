class_name SkinTemplates
extends RefCounted
## The art templates of a skin: for every picture a skin may replace, a PNG of the picture's size in one flat colour with the picture's skin key and its size written on it,
## for a person to draw the real art over (`docs/create/SKIN_API.md` "Art templates"; the command line is `skin_templates_tool.tscn`).
##
## WHICH PICTURES. `SOURCES` is the one table: the layout files (of the pack in use, as the pack holds them, no skin) whose pictures a skin may replace. Each texture a layout holds is a picture
## of its own, whose key and size are read off the texture: the key is the one `GameSkin.key_of` makes, which is the key a skin's `pictures` names (`ModSpec.REPLACEABLE_KINDS`), and the size is the
## texture's. The sizes come from the layout, so a template has nothing of any picture in it, only its key and its size. A phase that lets a skin replace more pictures adds the layout that holds them
## to `SOURCES`; nothing else changes.
## THE LAYERS OF THE CONSOLE. A skin's script may draw a part of the console, or all of it (`SkinLayers.HUD_NODES`), in the part's rectangle (`ConsoleState.rects`): the HUD layout in `SOURCES` also gives one template for each such layer, key `hud_layer/<layer>`
## (`hud_layer/hud_oxygen`), the size of the layer's rectangle in the layout's own data, for a picture of the whole part that the script draws (`skin/<name>.png`, a path in a draw list) at the size it will show.
##
## THE PROBLEM SCREEN. The frame of the problem screen is pictures a skin replaces (`pictures` takes the kind `problem_art` too, `ModSpec.REPLACEABLE_KINDS`): the screen picture the layout holds (`problem_art/pa_1780`), the calculator (`pa_1781`), the "Ans:" panel (`pa_1802`)
## and the calculator's digits and signs, all in the layouts of the screen and of the calculator in `SOURCES`, and the sender's two pictures beside the first line of a prompt (`ui_picture/prompt_sender_ship`, `PromptSender.PICTURE_SIZE`, which the screen stretches
## to); each has a template at its size. A mod that draws the screen of a problem type (`ModDiagram`, `docs/create/CONTENT.md` "Problem screens") draws in the window's 640 x 400 pixels and may name the same pictures by key: the screen's layout also gives one template for the whole window a
## mod draws, key `problem_layer/window`, for a picture of the whole screen of a type. It is not a picture a skin replaces: it is drawn over and put in the `problems/` folder of a problem mod, named in its draw list.
##
## THE SIZES ARE THE PACK'S. The dev pack's console has the sizes the dev pack made for itself; the original's are those of the legacy pack (`--pack=legacy` reads only the sizes, and writes none of the
## original's pixels).
##
## Teaches: drawing into an `Image` with no renderer (so it runs headless): a flat fill and a 3 x 5 pixel font of our own, since a `Font` draws only through the rendering server; and walking a
## `Resource`'s stored properties to find every texture in it, arrays included, the way `GameSkin` does to dress a layout.

## The layouts, as a path in a pack's `data/`, whose textures are the pictures a skin may replace.
const SOURCES: Array[String] = ["data/ui/hud_layout.tres", "data/problems/screen_layout.tres", "data/ui/calculator_layout.tres"]

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


## Every picture of `SOURCES` in the pack in use, once, in the layouts' order: the key and the size.
static func entries() -> Array[Entry]:
	var found: Array[Entry] = []
	var seen := {}
	for rel in SOURCES:
		var layout := Catalog.pack_resource(rel)
		if layout == null:
			continue
		for texture in _textures_in(layout):
			var key := GameSkin.key_of(Packs.source_of(texture))
			if key.is_empty() or seen.has(key) or not ModSpec.is_drawable_key(key):
				continue
			seen[key] = true
			found.append(Entry.new(key, Vector2i(texture.get_size())))
		if layout is HudLayout:
			var rects := ConsoleState.rects(layout)
			for layer in SkinLayers.hud_layers():
				found.append(Entry.new("%s/%s" % [LAYER_KIND, layer], Vector2i((rects[String(layer)] as Rect2).size)))
		if layout is ProblemScreenLayout:
			for sender in [PromptSender.PICTURE_SHIP, PromptSender.PICTURE_CONTROL_ROOM]:
				found.append(Entry.new("ui_picture/%s" % sender, PromptSender.PICTURE_SIZE))
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
