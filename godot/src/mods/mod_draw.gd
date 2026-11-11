class_name ModDraw
extends RefCounted
## What a mod draws: a DRAW LIST the script returns (a skin from `skin_layer` or `skin_frame`, the screen of a problem type from `problem_frame`), which the game checks command by command and draws itself. The script holds no
## node, no texture, no material and no canvas: it returns an Array of Arrays (strings, numbers, places, colours, names of its own files), and `validate` makes of it what the game is willing to draw, dropping
## every command that is not exactly one of those below. A dropped command costs nothing and is counted (`Drawn.dropped`); a list is cut at `MAX_COMMANDS`. ONE validator for every kind of mod: what differs
## between a skin and a problem screen is only where the pictures and shaders come from (`ModAssets`) and the canvas it is drawn on (`ModLayer`).
##
##     ["rect", Rect2 area, Color]                                       a filled rectangle
##     ["line", Vector2 from, Vector2 to, Color, float width]
##     ["picture", "skin/x.png" or "frame/sub_00", Vector2 or Rect2 where, mirrored?, Color?]  a picture of the mod's own pack, or of the game by its skin key; a Vector2 puts its top-left corner there at its own size, a Rect2 stretches it
##     ["region", "skin/x.png" or "deco/coral_fan_cyan", Rect2 where, Rect2 source, mirrored?, Color?]   part of a picture (a tile of a sheet), source in pixels of the picture
##     ["text", "words", Vector2 where, int size, Color, float width?, "left" or "center" or "right"?]   one line in the game's font, its top-left corner at `where`
##     ["layer", "skin/x.gdshader" or "", {"uniform": number, bool, Vector2 or Color, ...}?]   starts a layer drawn through that shader (one the manifest lists); "" is no shader
##
## `mirrored` is a bool, the Color after it a modulate. The list starts in an unshaded layer. At most `MAX_LAYERS` layers, `MAX_UNIFORMS` uniforms each, numbers finite and within `LIMIT`. A picture is a PNG under the
## folder of `ModAssets` (`skin/` or `problems/`) of THE MOD'S OWN PACK (`Pack.texture`, never the chain's lookup), so a path that names another pack, a folder above, or a file the pack lacks draws nothing. A name that is not under that folder but
## is a SKIN KEY (`<kind>/<name>`, a kind of `GameSkin.KEY_KINDS`: `ModSpec.is_drawable_key`) names a picture of the game: the game resolves it (`Assets.picture_by_key`, the lookup `OriginalPresenter` makes: a pack's picture for the key, else the
## skin in use's, else the chain's file), the mod never holds it, and a key nothing holds draws nothing. A layer
## whose shader the manifest does not list draws nothing (it is never drawn unshaded). A text is cut to `MAX_TEXT` characters (a control character becomes a space), its size held to `MIN_FONT_SIZE`..`MAX_FONT_SIZE`, at
## most `MAX_TEXTS` of them in a list; there is one font, the game's, so a mod names none. With a `width` the line is aligned in that width and clipped to it. Nothing here asks the script anything or runs its code.
##
## Teaches: validating what an untrusted program hands back as a whole language of its own: a table of commands with exact shapes, copied element by element (so what the game keeps shares nothing
## with the script and cannot be changed after the check), and caps on every dimension of the input.

## A picture by key is the game's own, drawn as the original look would draw it, so what it shows follows the skin and the pack in use (the state tells a script which keys the screen has: `SkinState`). ONE lookup for a key in a list (`keys`
## of `validate`), so a list that names a key a hundred times asks the chain once.
##
## The commands there are (the table above; `docs/create/SKIN_API.md` lists the same, a test keeps them one list).
const OPS: Array[String] = ["rect", "line", "picture", "region", "text", "layer"]
const MAX_COMMANDS := 4000
const MAX_LAYERS := 8
const MAX_UNIFORMS := 16
## A text: the most characters, the most texts in a list, and the sizes of the font (pixels).
const MAX_TEXT := 200
const MAX_TEXTS := 200
const MIN_FONT_SIZE := 6
const MAX_FONT_SIZE := 64
## Numbers beyond this (a place, a size, a uniform) are refused: far past anything on a 640 x 400 window, and nowhere near float limits.
const LIMIT := 100000.0
const MAX_PATH := 96

static var _uniform_name := RegEx.create_from_string("^[a-z_][a-z0-9_]{0,31}$")


## One layer of a list: the shader it is drawn through (a path the manifest lists, "" for none), its uniforms, its commands in the form `ModLayer` draws, and whether its shader is unusable (then nothing of it is drawn).
class Layer:
	extends RefCounted
	var shader := ""
	var uniforms: Dictionary = {}
	var commands: Array = []
	var blocked := false


## A checked list: its layers and how many commands were dropped (malformed, over the caps, or in a blocked layer).
class Drawn:
	extends RefCounted
	var layers: Array[Layer] = []
	var dropped := 0
	var texts := 0


## The list `raw` (what the mod's function returned) as what the game draws, or null when `raw` is not even an Array. `pack` is the mod's own pack, `assets` the folder its pictures are in and the shaders it may name.
static func validate(raw: Variant, pack: Pack, assets: ModAssets) -> Drawn:
	if not raw is Array:
		return null
	var drawn := Drawn.new()
	var keys := {}                                      # (key -> the picture it names, asked of the chain once for the whole list)
	var layer := Layer.new()
	drawn.layers.append(layer)
	var list: Array = raw
	var count := mini(list.size(), MAX_COMMANDS)
	drawn.dropped = list.size() - count
	for i in count:
		var command: Variant = list[i]
		if not command is Array or (command as Array).is_empty() or not (command[0] is String or command[0] is StringName):
			drawn.dropped += 1
			continue
		if String(command[0]) == "layer":
			var next := _layer(command, assets)
			if next == null or drawn.layers.size() >= MAX_LAYERS:
				drawn.dropped += 1
				layer = Layer.new()
				layer.blocked = true                       # (what follows a layer that was refused is not drawn at all)
			else:
				layer = next
				drawn.layers.append(layer)
			continue
		var made: Variant = null if layer.blocked else _command(command, pack, assets, keys)
		if made != null and made[0] == "text":
			if drawn.texts >= MAX_TEXTS:
				made = null
			else:
				drawn.texts += 1
		if made == null:
			drawn.dropped += 1
		else:
			layer.commands.append(made)
	return drawn


## Does `drawn` show nothing at all? (Every layer without a command.)
static func is_empty(drawn: Drawn) -> bool:
	return drawn == null or drawn.layers.all(func(layer: Layer) -> bool: return layer.commands.is_empty() or layer.blocked)


## A checked command as one line of words (a picture by its file): for a test or a tool that compares what two drawings show.
static func describe(command: Array) -> String:
	var parts := PackedStringArray()
	for part: Variant in command:
		if part is Texture2D:
			parts.append(String((part as Texture2D).get_meta(Pack.SOURCE_META, "texture")).get_file())
		else:
			parts.append(str(part))
	return " ".join(parts)


# --- the commands ----------------------------------------------------------------------------------------------------------

static func _command(command: Array, pack: Pack, assets: ModAssets, keys: Dictionary) -> Variant:
	var size := command.size()
	match String(command[0]):
		"rect":
			if size == 3 and _rect(command[1]) and command[2] is Color and _color(command[2]):
				return ["rect", Rect2(command[1]), Color(command[2])]
		"line":
			if size == 5 and _point(command[1]) and _point(command[2]) and command[3] is Color and _color(command[3]) and _number(command[4]):
				return ["line", Vector2(command[1]), Vector2(command[2]), Color(command[3]), clampf(float(command[4]), 0.0, 64.0)]
		"picture":
			if size >= 3 and size <= 5:
				var picture := _picture(command, pack, assets, keys, 1)
				var where: Variant = command[2]
				if picture != null and (_point(where) or _rect(where)):
					var rest: Variant = _flags(command, 3)
					if rest != null:
						return ["picture", picture, Vector2(where) if where is Vector2 else Rect2(where), rest[0], rest[1]]
		"region":
			if size >= 4 and size <= 6:
				var picture := _picture(command, pack, assets, keys, 1)
				if picture != null and _rect(command[2]) and _rect(command[3]):
					var rest: Variant = _flags(command, 4)
					if rest != null:
						return ["region", picture, Rect2(command[2]), Rect2(command[3]), rest[0], rest[1]]
		"text":
			if size >= 5 and size <= 7 and command[1] is String and _point(command[2]) and _number(command[3]) and command[4] is Color and _color(command[4]):
				var tail: Variant = _text_tail(command)
				if tail != null:
					return ["text", _clean_text(command[1]), Vector2(command[2]), clampi(roundi(float(command[3])), MIN_FONT_SIZE, MAX_FONT_SIZE), Color(command[4]), tail[0], tail[1]]
	return null


## `[width, alignment]` from the optional tail of a text command (`float width?`, then `"left"`, `"center"` or `"right"`?), or null when the tail is anything else. No width is -1.
static func _text_tail(command: Array) -> Variant:
	var width := -1.0
	var alignment := HORIZONTAL_ALIGNMENT_LEFT
	var i := 5
	if i < command.size() and (command[i] is int or command[i] is float):
		if not _number(command[i]) or float(command[i]) < 0.0:
			return null
		width = float(command[i])
		i += 1
	if i < command.size():
		match command[i]:
			"left":
				alignment = HORIZONTAL_ALIGNMENT_LEFT
			"center":
				alignment = HORIZONTAL_ALIGNMENT_CENTER
			"right":
				alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_:
				return null
		i += 1
	return [width, alignment] if i == command.size() else null


## `text` cut to `MAX_TEXT` characters, with a control character replaced by a space.
static func _clean_text(text: String) -> String:
	var out := ""
	for i in mini(text.length(), MAX_TEXT):
		out += " " if text.unicode_at(i) < 32 or text.unicode_at(i) == 127 else text[i]
	return out


## The texture named by `command[at]`: a plain path under the assets' folder ending `.png` that the mod's pack holds, or a skin key the chain holds a picture for (`keys` keeps the answers), or null.
static func _picture(command: Array, pack: Pack, assets: ModAssets, keys: Dictionary, at: int) -> Texture2D:
	var path: Variant = command[at]
	if not path is String or (path as String).length() > MAX_PATH:
		return null
	if assets != null and (path as String).begins_with(assets.folder):
		if (path as String).get_extension() != "png" or pack == null or not Pack.is_safe(path):
			return null
		return pack.texture(path)
	if not ModSpec.is_drawable_key(path):
		return null
	if not keys.has(path):
		keys[path] = Assets.picture_by_key(path)
	return keys[path]


## `[mirrored, modulate]` from the optional tail of a command from index `at`, or null when the tail is not (bool?, Color?) in that order.
static func _flags(command: Array, at: int) -> Variant:
	var mirrored := false
	var modulate := Color.WHITE
	var i := at
	if i < command.size() and command[i] is bool:
		mirrored = command[i]
		i += 1
	if i < command.size() and command[i] is Color:
		if not _color(command[i]):
			return null
		modulate = command[i]
		i += 1
	return [mirrored, modulate] if i == command.size() else null


static func _layer(command: Array, assets: ModAssets) -> Layer:
	if command.size() < 2 or command.size() > 3 or not command[1] is String:
		return null
	var layer := Layer.new()
	layer.shader = command[1]
	if not layer.shader.is_empty() and (assets == null or not assets.shaders.has(layer.shader)):
		return null
	if command.size() == 3:
		if not command[2] is Dictionary or (command[2] as Dictionary).size() > MAX_UNIFORMS:
			return null
		for key: Variant in command[2]:
			var value: Variant = command[2][key]
			if not key is String or _uniform_name.search(key) == null or not _uniform_value(value):
				return null
			layer.uniforms[key] = value
	return layer


static func _uniform_value(value: Variant) -> bool:
	if value is bool:
		return true
	if value is int or value is float:
		return _number(value)
	if value is Vector2:
		return _point(value)
	if value is Color:
		return _color(value)
	return false


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= LIMIT


static func _point(value: Variant) -> bool:
	return value is Vector2 and _number(value.x) and _number(value.y)


static func _rect(value: Variant) -> bool:
	return value is Rect2 and _point(value.position) and _point(value.size) and value.size.x >= 0.0 and value.size.y >= 0.0


static func _color(value: Color) -> bool:
	return _number(value.r) and _number(value.g) and _number(value.b) and _number(value.a)
