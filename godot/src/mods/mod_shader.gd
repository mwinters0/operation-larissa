class_name ModShader
extends RefCounted
## A mod's shader: TEXT that the game checks and compiles, never code the mod runs. The mod pack carries `skin/<name>.gdshader` files (a skin) or `problems/<name>.gdshader` files (problem screens) and lists them in its manifest
## (`ModSpec.shaders`, `ModSpec.problem_shaders`); `make` reads one through the pack's door as text, refuses what `problem` finds in it, and builds the `Shader` the layers of a draw list use (`ModDraw`). A mod never holds a shader or a
## material: it names a layer's shader by the path it listed.
##
## A canvas-item shader cannot reach a file, the network or the rules, but it can hang the graphics card or draw a great deal, so the text is held to a small language: one `shader_type
## canvas_item`, at most `MAX_BYTES`, no preprocessor line (`#include` would read a file of the game, `##` can build any word), no `for`, `while` or `do` (a loop that never ends is a frozen
## game), brackets that match, and a `fragment`, `vertex` or `light` function. This is a check of the text; the renderer is the compiler, and a shader it cannot compile only logs its
## error and draws nothing different from what the game draws (a headless run has no renderer, so only the checks here run).
##
## A data skin's `layers` set the uniforms of a shader by name: `uniform_types` reads what the text declares and `uniform_problem` says whether a manifest's value fills one (`ModSkin` judges, `PackCheck` tells the author).
##
## Teaches: containing what you cannot sandbox by checking it before it is used: a small allow-list of the language, a size cap, and the comment-stripping that makes a keyword scan honest.

## A shader source is at most this many bytes.
const MAX_BYTES := 8192
## Words a shader may not use: loops.
const FORBIDDEN_WORDS: Array[String] = ["for", "while", "do"]

## The uniform types a manifest's value may fill, and how: `float` and `int` a number (an `int` a whole one), `bool` true or false, `vec2` / `vec3` / `vec4` a list of that many numbers, `vec3` / `vec4` also a colour string.
const SETTABLE_TYPES: Array[String] = ["float", "int", "bool", "vec2", "vec3", "vec4"]

static var _uniform := RegEx.create_from_string("\\buniform\\s+(?:(?:lowp|mediump|highp)\\s+)?(\\w+)\\s+(\\w+)\\s*(\\[?)")
static var _type_line := RegEx.create_from_string("^\\s*shader_type\\s+canvas_item\\s*;")
static var _function := RegEx.create_from_string("\\bvoid\\s+(?:fragment|vertex|light)\\s*\\(")


## What is wrong with the shader source `bytes`, or "" when nothing is. The reason is a sentence for the pack's author.
static func problem(bytes: PackedByteArray) -> String:
	if bytes.size() > MAX_BYTES:
		return size_problem(bytes.size())
	for byte in bytes:
		if byte == 0 or (byte < 32 and byte != 9 and byte != 10 and byte != 13):
			return "holds a control character"
	var source := bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes:
		return "is not UTF-8 text"
	var code := without_comments(source)
	if _type_line.search(code) == null:
		return "must start with `shader_type canvas_item;`"
	if code.contains("#"):
		return "uses a preprocessor line (`#`), which a mod's shader may not"
	for word in FORBIDDEN_WORDS:
		if RegEx.create_from_string("\\b%s\\b" % word).search(code) != null:
			return "uses `%s`: a mod's shader has no loops" % word
	if _function.search(code) == null:
		return "defines no fragment(), vertex() or light() function"
	if not _balanced(code):
		return "has brackets that do not match"
	return ""


## The sentence for a source of `size` bytes that is too large, or "".
static func size_problem(size: int) -> String:
	return "is %d bytes, over the %d a mod's shader may have" % [size, MAX_BYTES] if size > MAX_BYTES else ""


## `source` without its `//` and `/* */` comments (a comment hides nothing from the scan above, and a keyword inside one is not a keyword).
static func without_comments(source: String) -> String:
	var out := ""
	var i := 0
	while i < source.length():
		var two := source.substr(i, 2)
		if two == "//":
			while i < source.length() and source[i] != "\n":
				i += 1
		elif two == "/*":
			var end := source.find("*/", i + 2)
			i = source.length() if end < 0 else end + 2
			out += " "
		else:
			out += source[i]
			i += 1
	return out


## The shader of the file `rel` of `pack` (listed by the manifest, in `folder`), or null with the reason in `reasons`.
static func make(pack: Pack, rel: String, folder: String, reasons: Array[String]) -> Shader:
	if not ModSpec.is_shader_path(rel, folder) or not pack.has(rel):
		reasons.append("%s is not in the pack" % rel)
		return null
	var too_big := size_problem(pack.size_of(rel))        # (before reading it: a pack's shader may be as large as a hostile author likes; only `MAX_BYTES` of it is ever read)
	if not too_big.is_empty():
		reasons.append("%s %s" % [rel, too_big])
		return null
	var message := problem(pack.read_bytes(rel))
	if not message.is_empty():
		reasons.append("%s %s" % [rel, message])
		return null
	var shader := Shader.new()
	shader.code = pack.read_text(rel)
	return shader


## The uniforms the shader text declares, name -> type (an array reads as "array"; a name a comma list declares after the first is not seen). Read from the text, so that it works where no renderer compiles the shader (a headless run, the pack check).
static func uniform_types(source: String) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for declared in _uniform.search_all(without_comments(source)):
		found[declared.get_string(2)] = "array" if not declared.get_string(3).is_empty() else declared.get_string(1)
	return found


## What is wrong with `value` (as `ModSpec` reads a manifest's uniform value: a float, a bool, a `Vector2` / `Vector3` / `Vector4` or a `Color`) for a uniform of `type`, or "".
static func uniform_problem(type: String, value: Variant) -> String:
	if not SETTABLE_TYPES.has(type):
		return "is a %s, which a manifest cannot set (it can set %s)" % [type, ", ".join(SETTABLE_TYPES)]
	match type:
		"float":
			return "" if value is float else "is a float: a number is needed"
		"int":
			return "" if value is float and is_equal_approx(value, roundf(value)) else "is an int: a whole number is needed"
		"bool":
			return "" if value is bool else "is a bool: true or false is needed"
		"vec2":
			return "" if value is Vector2 else "is a vec2: a list of 2 numbers is needed"
		"vec3":
			return "" if value is Vector3 or value is Color else "is a vec3: a list of 3 numbers, or a colour like \"#ff8800\", is needed"
	return "" if value is Vector4 or value is Color else "is a vec4: a list of 4 numbers, or a colour like \"#ff8800\", is needed"


## `value` as the shader's uniform of `type` has it (after `uniform_problem` found nothing): an `int` uniform gets an int.
static func uniform_value(type: String, value: Variant) -> Variant:
	return int(value) if type == "int" else value


static func _balanced(code: String) -> bool:
	var stack: Array[String] = []
	var pairs := {")": "(", "]": "[", "}": "{"}
	for character in code:
		if character == "(" or character == "[" or character == "{":
			stack.append(character)
		elif pairs.has(character):
			if stack.is_empty() or stack.pop_back() != pairs[character]:
				return false
	return stack.is_empty()
