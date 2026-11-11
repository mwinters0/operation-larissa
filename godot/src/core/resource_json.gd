class_name ResourceJson
extends RefCounted
## A Resource of the game as JSON, and back: the form a DATA pack holds a `Campaign`, a `SectorData`, a problem type in.
##
## The shape is the shape of the resource: one key per `@export` field, under the field's own name, so the class's doc comments explain the
## file and a campaign that is written by hand is the .tres without Godot's syntax. A field that has its default value is LEFT OUT, so a
## hand-written file names only what it changes. `{"class": "Campaign", "id": "orchard", "title": "Orchard", "sectors": [40, 41]}` is a
## campaign.
##
## HOW EACH KIND OF FIELD LOOKS
##   * int, float, bool, String, StringName: the JSON number, boolean or string.
##   * Vector2i, Vector2: [x, y].
##   * PackedInt32Array, PackedInt64Array, PackedFloat64Array, PackedStringArray, Array: a JSON array. A typed Array (`Array[PieceData]`,
##     `Array[StringName]`, `Array[PackedInt64Array]`) is read back with its type, which the class says.
##   * PackedByteArray: a base64 string (a screen's tiles).
##   * Dictionary: an object whose keys stay words, except in a field the class lists in `JSON_INT_KEYS` (`TextTable.texts`: "1204" is the
##     key 1204). Inside a Dictionary or an untyped Array a number that is whole becomes an int, and a packed array that the code
##     reads as one is written `{"$": "PackedInt32Array", "v": [2, 3]}` (the type cannot be known from the field there).
##   * a Resource field (`PieceData`, `FoeData`, ...): an object of its own, with the same rules, without "class" (the field says it).
##   * a Texture2D or AudioStream field, or an element of a list or a value of a dictionary: `{"$ref": "assets/sprites/sub/sub_00.png"}`, the
##     file of the pack by its AUTHORING path (the path a `.tres` of a trusted pack names it by). It is looked for in the pack the file is in and then in
##     the packs under it in the chain (`Packs.provider_below`), never above. A `.ogg` / `.wav` is an AudioStream, a `.png` a Texture2D, a `.tres` another
##     resource of the pack (its data form, `X.json`). A Texture2D field may also be a bare path of a PNG in the pack (a campaign by hand).
##   * a String field that holds a path into a pack (`JSON_PATH_FIELDS`): `{"$path": "assets/audio/voice/x.wav"}`, read as the full path of the
##     file in the pack that holds it (`res://packs/dev/assets/...`), which `Packs.file_at` then serves. A string that is not under a pack stays as it is.
##   * a sub-resource used more than once in the file: `{"$id": "r1", ...fields}` the first time and `{"$id": "r1"}` after.
##   * `SpriteFrames` and `TileSet`: engine classes, described by `EngineJson`; any other engine class is a problem.
##   * Rect2i and Rect2 `[x, y, w, h]`, Color `[r, g, b, a]`, PackedVector2Array a list of `[x, y]`, PackedColorArray a list of `[r, g, b, a]`.
##   * where the field's type does not say what a value is (inside a Dictionary or an untyped Array), the value is tagged `{"$": "float", "v": 1}`
##     (a whole float; a whole number alone is an int), `StringName`, `Vector2`, `Vector2i`, `Rect2i`, `Rect2`, `Color` or a packed array.
## A field the class does not have is a problem (`problems`, a typo is found), not silently ignored.
##
## NEVER `ResourceLoader`. Nothing here opens a .tres or a script: the objects are made with `Script.new()` of the classes the game itself
## defines and filled with JSON values, so a file from anyone can only say numbers, words and lists. That is why this is the form of every
## pack from outside the project (the data form).
##
## Teaches: reflection (`get_property_list`, `Array.get_typed_script`) to write one serializer for every Resource instead of one per class,
## and why a data format should be a DESCRIPTION of the resource, not Godot's own save format.

## A class may declare `const JSON_INT_KEYS: Array[String] = ["field"]`: the Dictionary fields whose keys are whole numbers (JSON keys are text).
## A class may declare `const JSON_PATH_FIELDS: Array[String] = ["field"]`: the String or PackedStringArray fields whose strings are paths into a pack
## (`res://packs/<id>/assets/...`), written relative to the pack (`$path`) so the file means the same in whichever folder the pack is.


## The class name of a top-level resource, so a file says what it is (`resource_from` can then be called without a class).
const CLASS_KEY := "class"
## The keys of the references: another file of the pack, a path into the pack, a sub-resource shared inside the file.
const REF_KEY := "$ref"
const PATH_KEY := "$path"
const ID_KEY := "$id"
## The tag of a value whose kind the field's type does not say (inside a Dictionary or an untyped Array): {"$": tag, "v": value}.
const TAG_KEY := "$"

## What went wrong while reading, one sentence each (a field that is not a field, a value of the wrong kind). Empty after a clean read.
var problems: Array[String] = []
## The fields to leave out when writing and to ignore when reading (the caller handles them: `SectorData.foe_script`).
var skip: PackedStringArray = PackedStringArray()
## The pack the file is in: where a `Texture2D` field's path points and where a `$ref` starts looking. May be null.
var pack: Pack

## The tags of the values a plain JSON value cannot say (see the header).
const TAGS := {
	TYPE_PACKED_INT32_ARRAY: "PackedInt32Array", TYPE_PACKED_INT64_ARRAY: "PackedInt64Array", TYPE_PACKED_FLOAT32_ARRAY: "PackedFloat32Array",
	TYPE_PACKED_FLOAT64_ARRAY: "PackedFloat64Array", TYPE_PACKED_STRING_ARRAY: "PackedStringArray", TYPE_PACKED_VECTOR2_ARRAY: "PackedVector2Array",
	TYPE_PACKED_COLOR_ARRAY: "PackedColorArray", TYPE_STRING_NAME: "StringName", TYPE_VECTOR2: "Vector2", TYPE_VECTOR2I: "Vector2i",
	TYPE_RECT2I: "Rect2i", TYPE_RECT2: "Rect2", TYPE_COLOR: "Color", TYPE_FLOAT: "float",
}

static var _classes: Dictionary = {}
## The files being read, "<pack id>/<rel>": a `$ref` that leads back into one of them is a problem, not an endless loop.
static var _reading: Array[String] = []

## id -> the resource a `{"$id": ...}` made while reading.
var _shared: Dictionary = {}
## While writing: the number of times each resource is used (instance id -> count), and the ids given to those used more than once.
var _uses: Dictionary = {}
var _named: Dictionary = {}


func _init(from_pack: Pack = null) -> void:
	pack = from_pack


# --- reading -----------------------------------------------------------------------------------------------------

## The resource in the JSON file `rel` of `pack` (its "class", or `script`), or null (with `problems` and a warning).
func read(rel: String, script: Script = null) -> Resource:
	var parser := JSON.new()
	if not pack.has(rel) or parser.parse(pack.read_text(rel)) != OK:
		problems.append("%s: %s" % [rel, "no such file" if not pack.has(rel) else "line %d: %s" % [parser.get_error_line(), parser.get_error_message()]])
		push_warning("ResourceJson: " + problems[-1])
		return null
	if not parser.data is Dictionary:
		problems.append("%s: a JSON object was expected" % rel)
		push_warning("ResourceJson: " + problems[-1])
		return null
	var here := "%s/%s" % [pack.id, rel]
	if _reading.has(here):
		problems.append("%s: refers to itself" % rel)
		push_warning("ResourceJson: " + problems[-1])
		return null
	_reading.append(here)
	var loaded := resource_from(parser.data, script)
	_reading.erase(here)
	for problem in problems:
		push_warning("ResourceJson: %s: %s" % [rel, problem])
	return loaded


## The resource `data` describes. `script` is its class; without it the "class" key says (a name of the game's own classes, or `SpriteFrames` / `TileSet`).
func resource_from(data: Dictionary, script: Script = null) -> Resource:
	if script == null and EngineJson.handles(String(data.get(CLASS_KEY, ""))):
		return EngineJson.new().build(data, self, String(data[CLASS_KEY]))
	if script == null:
		script = script_named(String(data.get(CLASS_KEY, "")))
	if script == null:
		problems.append("no class: say \"class\" (%s)" % ", ".join(["Campaign", "SectorData", "ProblemType"]))
		return null
	var resource: Resource = script.new()
	if data.get(ID_KEY) is String:
		_shared[data[ID_KEY]] = resource                 # (before its fields, so a field may name it)
	var fields := _fields(resource)
	var constants := script.get_script_constant_map()
	var int_keys: Array = constants.get("JSON_INT_KEYS", [])
	var path_fields: Array = constants.get("JSON_PATH_FIELDS", [])
	for key: String in data:
		if key == CLASS_KEY or key == ID_KEY or skip.has(key):
			continue
		if not fields.has(key):
			problems.append("%s has no field '%s'" % [script.get_global_name(), key])
			continue
		var label := "%s.%s" % [script.get_global_name(), key]
		if path_fields.has(key):
			resource.set(key, _decode_paths(data[key], resource.get(key), label))
		else:
			resource.set(key, _decode(data[key], fields[key], resource.get(key), label, int_keys.has(key)))
	return resource


func _decode(value: Variant, info: Dictionary, template: Variant, label: String, int_keys: bool = false) -> Variant:
	var kind: int = info.type
	if kind == TYPE_OBJECT:
		return _decode_object(value, info, label)
	if kind == TYPE_ARRAY:
		if not value is Array:
			return _wrong(label, "a list", template)
		return _decode_array(value, template, label)
	return _decode_value(value, kind, template, label, int_keys)


func _decode_value(value: Variant, kind: int, template: Variant, label: String, int_keys: bool = false) -> Variant:
	match kind:
		TYPE_BOOL:
			return value if value is bool else _wrong(label, "true or false", template)
		TYPE_INT:
			return int(value) if value is float or value is int else _wrong(label, "a number", template)
		TYPE_FLOAT:
			return float(value) if value is float or value is int else _wrong(label, "a number", template)
		TYPE_STRING:
			return value if value is String else _wrong(label, "text", template)
		TYPE_STRING_NAME:
			return StringName(value) if value is String else _wrong(label, "text", template)
		TYPE_VECTOR2I:
			return Vector2i(int(value[0]), int(value[1])) if _is_numbers(value, 2) else _wrong(label, "[x, y]", template)
		TYPE_VECTOR2:
			return Vector2(float(value[0]), float(value[1])) if _is_numbers(value, 2) else _wrong(label, "[x, y]", template)
		TYPE_RECT2I:
			return Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3])) if _is_numbers(value, 4) else _wrong(label, "[x, y, width, height]", template)
		TYPE_RECT2:
			return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3])) if _is_numbers(value, 4) else _wrong(label, "[x, y, width, height]", template)
		TYPE_COLOR:
			return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3])) if _is_numbers(value, 4) else _wrong(label, "[r, g, b, a]", template)
		TYPE_PACKED_BYTE_ARRAY:
			return Marshalls.base64_to_raw(value) if value is String else _wrong(label, "base64 text", template)
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
				TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			if not value is Array:
				return _wrong(label, "a list", template)
			return _packed(kind, value)
		TYPE_DICTIONARY:
			return _plain(value, int_keys, label) if value is Dictionary else _wrong(label, "an object", template)
	problems.append("%s: this kind of field (type %d) is not in a JSON file" % [label, kind])
	return template


func _decode_object(value: Variant, info: Dictionary, label: String) -> Variant:
	var declared := String(info.class_name)
	if value is Dictionary:
		if value.has(REF_KEY):
			return _reference(value[REF_KEY], declared, label)
		if value.has(ID_KEY) and value.size() == 1:
			return _shared_resource(value[ID_KEY], label)
	if declared == "Texture2D" or ClassDB.is_parent_class(declared, "Texture2D"):
		if value is String and pack != null and pack.has(value):
			return pack.texture(value)
		problems.append("%s: no picture '%s' in the pack (say {\"$ref\": \"assets/...png\"})" % [label, value])
		return null
	if declared == "AudioStream" or ClassDB.is_parent_class(declared, "AudioStream"):
		problems.append("%s: a sound is a file of the pack (say {\"$ref\": \"assets/...wav\"})" % label)
		return null
	if value is Dictionary and (EngineJson.handles(declared) or ((declared.is_empty() or declared == "Resource") and EngineJson.handles(String(value.get(CLASS_KEY, ""))))):
		var described: Dictionary = value if value.has(CLASS_KEY) else value.merged({CLASS_KEY: declared})
		return EngineJson.new().build(described, self, label)
	var script := script_named(declared)
	if script == null and (declared.is_empty() or declared == "Resource") and value is Dictionary:
		script = script_named(String(value.get(CLASS_KEY, "")))
	if script == null or not value is Dictionary:
		problems.append("%s: an object of %s was expected" % [label, declared])
		return null
	return resource_from(value, script)


func _decode_array(items: Array, template: Variant, label: String) -> Array:
	var typed: Array = template
	var builtin := typed.get_typed_builtin()
	var script: Variant = typed.get_typed_script()
	var out: Array = Array([], builtin, typed.get_typed_class_name(), script) if typed.is_typed() else []
	for i in items.size():
		var where := "%s[%d]" % [label, i]
		if not typed.is_typed():
			out.append(_plain(items[i], false, where))
		elif builtin == TYPE_OBJECT:
			var declared := String((script as Script).get_global_name()) if script != null else String(typed.get_typed_class_name())
			var element: Variant = _decode_object(items[i], {"class_name": declared}, where)
			if element != null:
				out.append(element)
		else:
			out.append(_decode_value(items[i], builtin, _empty_of(builtin), where))
	return out


## The strings of a field `JSON_PATH_FIELDS` names: each is a plain string (kept) or `{"$path": rel}` (the full path of the file in the pack that holds it).
func _decode_paths(value: Variant, template: Variant, label: String) -> Variant:
	if template is String:
		return _path_of(value, label) if value is String or value is Dictionary else _wrong(label, "text or {\"$path\": ...}", template)
	if not value is Array:
		return _wrong(label, "a list", template)
	var out := PackedStringArray()
	for i in value.size():
		out.append(_path_of(value[i], "%s[%d]" % [label, i]))
	return out


func _path_of(value: Variant, label: String) -> String:
	if value is String:
		return value
	if not value is Dictionary or not (value as Dictionary).get(PATH_KEY) is String or value.size() != 1:
		problems.append("%s should be text or {\"$path\": \"assets/...\"}" % label)
		return ""
	var rel: String = value[PATH_KEY]
	var holder := Packs.provider_below(pack, rel, true) if Pack.is_safe(rel) else null
	if holder == null:
		if pack == null or not Pack.is_safe(rel):
			problems.append("%s: '%s' is not a path inside a pack" % [label, rel])
			return ""
		return pack.path_of(rel)                         # (a file nobody has: named where it should be, so what is missing is said)
	return holder.path_of(rel)


## The file `rel` of the pack as a resource: looked for in `pack` and then in the packs under it. A picture, a sound, or a resource of the pack by its authoring path.
func _reference(rel: Variant, declared: String, label: String) -> Variant:
	if not rel is String or not Pack.is_safe(rel):
		problems.append("%s: '%s' is not a path inside a pack" % [label, rel])
		return null
	var holder := Packs.provider_below(pack, rel)
	if holder == null:
		problems.append("%s: no pack holds '%s'" % [label, rel])
		return null
	var made: Variant = holder.file(rel)
	if made == null:
		problems.append("%s: '%s' cannot be read" % [label, rel])
		return null
	var wrong := _not_a(made, declared)
	if not wrong.is_empty():
		problems.append("%s: '%s' is %s, not %s" % [label, rel, made.get_class(), declared])
		return null
	return made


## "" when `made` may stand in a field of class `declared`, else a reason.
static func _not_a(made: Resource, declared: String) -> String:
	if declared.is_empty() or declared == "Resource":
		return ""
	var script := script_named(declared)
	if script != null:
		return "" if made.get_script() == script else declared
	return "" if made.is_class(declared) else declared


func _shared_resource(id: Variant, label: String) -> Resource:
	if _shared.has(id):
		return _shared[id]
	problems.append("%s: nothing is called '%s' yet" % [label, id])
	return null


## `value` from JSON as the game's plain data: whole numbers are ints, a tagged value is that value, lists and objects inside. The keys
## of the top object are ints when `int_keys` (they are text unless the class says so).
func _plain(value: Variant, int_keys: bool = false, label: String = "") -> Variant:
	if value is float and value == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	if value is Array:
		var list := []
		for i in value.size():
			list.append(_plain(value[i], false, "%s[%d]" % [label, i]))
		return list
	if value is Dictionary:
		if value.size() == 2 and value.get(TAG_KEY) is String and value.has("v") and TAGS.values().has(value[TAG_KEY]):
			return _tagged(value[TAG_KEY], value["v"], label)
		if value.has(REF_KEY):
			return _reference(value[REF_KEY], "", label)
		var map := {}
		for key: String in value:
			map[key.to_int() if int_keys and key.is_valid_int() else key] = _plain(value[key], false, "%s[%s]" % [label, key])
		return map
	return value


func _tagged(tag: String, v: Variant, label: String) -> Variant:
	var kind: int = TAGS.find_key(tag)
	match kind:
		TYPE_FLOAT:
			return float(v) if v is float or v is int else _wrong(label, "a number", 0.0)
		TYPE_STRING_NAME:
			return StringName(v) if v is String else _wrong(label, "text", &"")
	if not v is Array:
		return _wrong(label, "a list", null)
	if kind in [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2I, TYPE_RECT2, TYPE_COLOR]:
		return _decode_value(v, kind, null, label)
	return _packed(kind, v)


static func _packed(kind: int, items: Array) -> Variant:
	match kind:
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array(items.map(func(v: Variant) -> int: return int(v)))
		TYPE_PACKED_INT64_ARRAY:
			return PackedInt64Array(items.map(func(v: Variant) -> int: return int(v)))
		TYPE_PACKED_FLOAT32_ARRAY:
			return PackedFloat32Array(items.map(func(v: Variant) -> float: return float(v)))
		TYPE_PACKED_FLOAT64_ARRAY:
			return PackedFloat64Array(items.map(func(v: Variant) -> float: return float(v)))
		TYPE_PACKED_VECTOR2_ARRAY:
			return PackedVector2Array(items.filter(func(v: Variant) -> bool: return _is_numbers(v, 2)).map(
					func(v: Variant) -> Vector2: return Vector2(float(v[0]), float(v[1]))))
		TYPE_PACKED_COLOR_ARRAY:
			return PackedColorArray(items.filter(func(v: Variant) -> bool: return _is_numbers(v, 4)).map(
					func(v: Variant) -> Color: return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]))))
	return PackedStringArray(items.map(func(v: Variant) -> String: return str(v)))


static func _empty_of(kind: int) -> Variant:
	return type_convert(null, kind)


static func _is_numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	return (value as Array).all(func(item: Variant) -> bool: return item is float or item is int)


func _wrong(label: String, wanted: String, fallback: Variant) -> Variant:
	problems.append("%s should be %s" % [label, wanted])
	return fallback


# --- what EngineJson asks of its host -------------------------------------------------------------------------------

## Says a problem for each key of `data` that is not in `allowed` (a typo is found, not ignored).
func check_keys(data: Dictionary, allowed: Array, label: String) -> void:
	for key: String in data:
		if key != CLASS_KEY and not allowed.has(key):
			problems.append("%s has no field '%s'" % [label, key])


func number(value: Variant, label: String, fallback: float) -> float:
	return float(value) if value is float or value is int else _wrong(label, "a number", fallback)


func vector2i(value: Variant, label: String, fallback: Vector2i) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1])) if _is_numbers(value, 2) else _wrong(label, "[x, y]", fallback)


## The picture a `texture` entry names: `{"$ref": ...}`, or null (a texture is optional).
func texture_from(value: Variant, label: String) -> Texture2D:
	if value == null:
		return null
	if value is Dictionary:
		return _reference(value.get(REF_KEY), "Texture2D", label) as Texture2D
	problems.append("%s should be {\"$ref\": \"assets/...png\"}" % label)
	return null


## A value of Variant type `kind` from its typed JSON form (a custom data value of a tile).
func value_of_kind(value: Variant, kind: int, label: String) -> Variant:
	return _decode_value(value, kind, _empty_of(kind), label)


# --- writing -------------------------------------------------------------------------------------------------------

## The JSON-ready Dictionary of `resource`: its "class" and every field that is not the default (and not in `skip`).
func data_of(resource: Resource) -> Dictionary:
	if EngineJson.class_of(resource) != "":
		return _engine_data(resource)
	_uses = {}
	_named = {}
	_count_uses(resource)
	var data := {CLASS_KEY: resource.get_script().get_global_name()}
	data.merge(_fields_to_data(resource))
	return data


func _engine_data(resource: Resource) -> Dictionary:
	var engine := EngineJson.new()
	var data := engine.data_of(resource, self)
	for what in engine.unsupported:
		problems.append("%s: %s" % [resource.get_class(), what])
	return data


func _fields_to_data(resource: Resource) -> Dictionary:
	var data := {}
	var script := resource.get_script() as Script
	var defaults: Resource = script.new()
	var fields := _fields(resource)
	var path_fields: Array = script.get_script_constant_map().get("JSON_PATH_FIELDS", [])
	for field: String in fields:
		var value: Variant = resource.get(field)
		if skip.has(field) or value == null:
			continue
		var fresh: Variant = defaults.get(field)
		if typeof(value) == typeof(fresh) and not value is Object and value == fresh:
			continue                                     # (the default: a file names only what it changes)
		var encoded: Variant = _encode_paths(value) if path_fields.has(field) else _encode(value, false)
		if encoded != null:
			data[field] = encoded
	return data


## `loose`: inside a Dictionary or an untyped Array, where a value whose kind the type does not say is tagged (the reader cannot tell it from a plain one otherwise).
func _encode(value: Variant, loose: bool) -> Variant:
	if loose and TAGS.has(typeof(value)) and not (typeof(value) == TYPE_FLOAT and not _is_whole(value)):
		return {TAG_KEY: TAGS[typeof(value)], "v": _encode(value, false)}
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return String(value)
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_RECT2I, TYPE_RECT2:
			return [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_PACKED_BYTE_ARRAY:
			return Marshalls.raw_to_base64(value)
		TYPE_PACKED_VECTOR2_ARRAY:
			return Array(value).map(func(point: Vector2) -> Array: return [point.x, point.y])
		TYPE_PACKED_COLOR_ARRAY:
			return Array(value).map(func(color: Color) -> Array: return [color.r, color.g, color.b, color.a])
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return Array(value)
		TYPE_ARRAY:
			var list := []
			for item in value:
				list.append(_encode(item, not value.is_typed()))
			return list
		TYPE_DICTIONARY:
			var map := {}
			for key in value:
				map[str(key)] = _encode(value[key], true)
			return map
		TYPE_OBJECT:
			return _encode_object(value)
	return null


func _encode_object(value: Object) -> Variant:
	if value is Texture2D or value is AudioStream:
		return reference_of(value)
	if value is Resource and EngineJson.class_of(value) != "":
		return _engine_data(value)
	if value is Resource and value.get_script() != null:
		var id := _id_of(value)
		if id.is_empty():
			return _fields_to_data(value)
		if _named.get(value.get_instance_id(), false):
			return {ID_KEY: id}
		_named[value.get_instance_id()] = true
		var data := {ID_KEY: id}
		data.merge(_fields_to_data(value))
		return data
	return null


## The strings of a `JSON_PATH_FIELDS` field with the pack's folder taken off.
func _encode_paths(value: Variant) -> Variant:
	if value is String:
		return _path_data(value)
	if value is PackedStringArray:
		return Array(value).map(_path_data)
	return _encode(value, false)


func _path_data(path: String) -> Variant:
	var holder := Packs.pack_of_path(path, pack)
	if holder == null:
		return path
	return {PATH_KEY: path.trim_prefix(holder.root + "/")}


## `{"$ref": rel}` for a picture or a sound that is a file of a pack (the file `Packs.source_of` names), else null with a problem.
func reference_of(resource: Resource) -> Variant:
	var path := Packs.source_of(resource)
	var holder := Packs.pack_of_path(path, pack)
	if holder == null:
		problems.append("%s is not a file of a pack (%s)" % [resource.get_class(), path if not path.is_empty() else "made in memory"])
		return null
	return {REF_KEY: path.trim_prefix(holder.root + "/")}


func encode_value(value: Variant) -> Variant:
	return _encode(value, false)


static func _is_whole(value: float) -> bool:
	return value == floorf(value) and absf(value) < 9.0e15


## Counts how many times each script resource is held (by a field, a list or a dictionary), so the ones held more than once get an id.
func _count_uses(value: Variant) -> void:
	if value is Resource:
		if (value as Resource).get_script() == null or value is Texture2D or value is AudioStream or EngineJson.class_of(value) != "":
			return
		var key: int = value.get_instance_id()
		_uses[key] = int(_uses.get(key, 0)) + 1
		if _uses[key] > 1:
			return
		for field: String in _fields(value):
			if not skip.has(field):
				_count_uses(value.get(field))
	elif value is Array:
		for item in value:
			_count_uses(item)
	elif value is Dictionary:
		for key in value:
			_count_uses(value[key])


## The id of `resource` when it is held more than once, else "".
func _id_of(resource: Resource) -> String:
	if int(_uses.get(resource.get_instance_id(), 0)) < 2:
		return ""
	return "r%d" % (_uses.keys().filter(func(key: int) -> bool: return _uses[key] > 1).find(resource.get_instance_id()) + 1)


## The fields of `resource` the file holds: its own `@export` variables (not Resource's), by name.
func _fields(resource: Resource) -> Dictionary:
	var fields := {}
	for info in resource.get_property_list():
		if info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and info.usage & PROPERTY_USAGE_STORAGE:
			fields[info.name] = info
	return fields


# --- classes by name --------------------------------------------------------------------------------------------------

## The script of the game's class called `class_name` (`Campaign`, `PieceData` ...), or null.
static func script_named(name_of_class: String) -> Script:
	if name_of_class.is_empty():
		return null
	if _classes.is_empty():
		for entry in ProjectSettings.get_global_class_list():
			_classes[String(entry["class"])] = String(entry["path"])
	return load(_classes[name_of_class]) as Script if _classes.has(name_of_class) else null


## Every `$ref` and `$path` in the data of a file (what it names: a closure of the files it needs), as the relative paths they hold.
static func named_files(data: Variant) -> Array[String]:
	var found: Array[String] = []
	if data is Array:
		for item in data:
			found.append_array(named_files(item))
	elif data is Dictionary:
		for key: String in data:
			if (key == REF_KEY or key == PATH_KEY) and data[key] is String:
				found.append(data[key])
			else:
				found.append_array(named_files(data[key]))
	return found


# --- files ----------------------------------------------------------------------------------------------------------

## Writes `data` as readable JSON (keys in the order given, tab-indented) to `path`; the folder is made. `OK` or the error.
static func save_json(data: Variant, path: String) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(stringify(data) + "\n")
	return OK


## `data` as readable JSON text (keys in the order given, tab-indented). Godot writes a vertical tab (a character of the original's texts) as `\v`, which its
## own parser refuses; here it is `\u000b`, so every string the game holds survives a file.
static func stringify(data: Variant) -> String:
	var text := JSON.stringify(data, "\t", false)
	if not text.contains("\\v"):
		return text
	var out := PackedStringArray()
	var at := 0
	while at < text.length():
		var slash := text.find("\\", at)
		if slash < 0:
			break
		out.append(text.substr(at, slash - at))
		out.append("\\u000b" if text[slash + 1] == "v" else text.substr(slash, 2))            # (an escape is two characters: `\\` is skipped whole, so `\\v` stays a backslash and a v)
		at = slash + 2
	out.append(text.substr(at))
	return "".join(out)
