class_name ResourceCompare
extends RefCounted
## Are two resources the same data? The deep comparison the round-trip tests share (`test_resource_json`, `test_data_form`, the legacy round trips).
##
## Resources of the game are compared by their own `@export` fields, arrays and dictionaries element by element, the rest with `==` (a number is the
## same number as an int or a float, a StringName the same words as a String). A picture or a sound is the same when it came from the same file of
## a pack (the path under the pack's folder: a trusted pack's `.tres` loads `res://packs/dev/assets/x.png`, its data form in a copy of the pack reads
## `user://packs/copy/assets/x.png`), else when the bytes are. The engine classes the data form describes are compared through their methods:
## `SpriteFrames` by animation, `TileSet` by layers, sources and tiles.
##
## Teaches: comparing by what a thing IS (the file it came from) when its identity differs by construction, and walking an engine class with its
## methods, as `EngineJson` does to write it.


## The folders of the packs the two sides come from, when they differ (`legacy` and its export): a string that is a path into one of them is compared by what follows
## the folder (`res://packs/legacy/assets/a.png` is `user://x/legacy_as_data/assets/a.png`). Empty when both sides are one pack. A test sets it and clears it.
static var pack_roots: Array[String] = []


## `text` without the pack folder it starts with (when it starts with one of `pack_roots`).
static func _unrooted(text: String) -> String:
	for root in pack_roots:
		if text.begins_with(root + "/"):
			return text.trim_prefix(root + "/")
	return text


## Appends one sentence to `differences` for each place `a` and `b` differ. `path` names where in the data they were met.
static func same(a: Variant, b: Variant, path: String, differences: Array[String]) -> void:
	if a is Resource and b is Resource:
		_resources(a, b, path, differences)
	elif a is Array and b is Array:
		if a.size() != b.size():
			differences.append("%s: %d items against %d" % [path, a.size(), b.size()])
			return
		for i in a.size():
			same(a[i], b[i], "%s[%d]" % [path, i], differences)
	elif a is PackedStringArray and b is PackedStringArray:
		same(Array(a), Array(b), path, differences)
	elif a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			differences.append("%s: %d keys against %d" % [path, a.size(), b.size()])
			return
		for key in a:
			if not b.has(key):
				differences.append("%s: key %s is missing" % [path, key])
			else:
				same(a[key], b[key], "%s[%s]" % [path, key], differences)
	elif typeof(a) != typeof(b) or a != b:
		var same_words := (a is String or a is StringName) and (b is String or b is StringName) and _unrooted(str(a)) == _unrooted(str(b))
		if not (same_words or ((a is int or a is float) and (b is int or b is float) and a == b)):
			differences.append("%s: %s against %s" % [path, str(a).left(60), str(b).left(60)])


## The path of a file of a pack under the pack's folder, or "" for what is not a file of a pack.
static func rel_of(resource: Resource) -> String:
	var source := Packs.source_of(resource)
	var unrooted := _unrooted(source)
	return unrooted if unrooted != source else Packs.relative(source)


static func _resources(a: Resource, b: Resource, path: String, differences: Array[String]) -> void:
	if a is Texture2D and b is Texture2D:
		_pictures(a, b, path, differences)
		return
	if a is AudioStream and b is AudioStream:
		_sounds(a, b, path, differences)
		return
	if a is SpriteFrames and b is SpriteFrames:
		_frames(a, b, path, differences)
		return
	if a is TileSet and b is TileSet:
		_tile_set(a, b, path, differences)
		return
	if a.get_script() != b.get_script():
		differences.append("%s: another class" % path)
		return
	if a is FoeScript:
		if a.source != b.source:
			differences.append("%s: the script text differs" % path)
		return
	for info in a.get_property_list():
		if info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and info.usage & PROPERTY_USAGE_STORAGE:
			same(a.get(info.name), b.get(info.name), "%s.%s" % [path, info.name], differences)


static func _pictures(a: Texture2D, b: Texture2D, path: String, differences: Array[String]) -> void:
	var from_a := rel_of(a)
	var from_b := rel_of(b)
	if not from_a.is_empty() and not from_b.is_empty():
		if from_a != from_b:
			differences.append("%s: the picture %s against %s" % [path, from_a, from_b])
		return
	var image_a := a.get_image()
	var image_b := b.get_image()
	if image_a == null or image_b == null or image_a.get_size() != image_b.get_size() or image_a.get_data() != image_b.get_data():
		differences.append("%s: the pictures differ" % path)


static func _sounds(a: AudioStream, b: AudioStream, path: String, differences: Array[String]) -> void:
	var from_a := rel_of(a)
	var from_b := rel_of(b)
	if from_a.is_empty() or from_b.is_empty() or from_a != from_b:
		differences.append("%s: the sounds %s against %s" % [path, from_a, from_b])


static func _frames(a: SpriteFrames, b: SpriteFrames, path: String, differences: Array[String]) -> void:
	var names_a := Array(a.get_animation_names())
	var names_b := Array(b.get_animation_names())
	if names_a != names_b:
		differences.append("%s: animations %s against %s" % [path, names_a, names_b])
		return
	for animation in names_a:
		var where := "%s.%s" % [path, animation]
		if a.get_animation_speed(animation) != b.get_animation_speed(animation) or a.get_animation_loop(animation) != b.get_animation_loop(animation):
			differences.append("%s: speed or loop differ" % where)
		if a.get_frame_count(animation) != b.get_frame_count(animation):
			differences.append("%s: %d frames against %d" % [where, a.get_frame_count(animation), b.get_frame_count(animation)])
			continue
		for i in a.get_frame_count(animation):
			if a.get_frame_duration(animation, i) != b.get_frame_duration(animation, i):
				differences.append("%s[%d]: duration differs" % [where, i])
			same(a.get_frame_texture(animation, i), b.get_frame_texture(animation, i), "%s[%d]" % [where, i], differences)


static func _tile_set(a: TileSet, b: TileSet, path: String, differences: Array[String]) -> void:
	if a.tile_size != b.tile_size:
		differences.append("%s: tile size %s against %s" % [path, a.tile_size, b.tile_size])
	if a.get_physics_layers_count() != b.get_physics_layers_count() or a.get_custom_data_layers_count() != b.get_custom_data_layers_count():
		differences.append("%s: the layers differ" % path)
		return
	for layer in a.get_physics_layers_count():
		if a.get_physics_layer_collision_layer(layer) != b.get_physics_layer_collision_layer(layer) \
				or a.get_physics_layer_collision_mask(layer) != b.get_physics_layer_collision_mask(layer):
			differences.append("%s: physics layer %d differs" % [path, layer])
	for layer in a.get_custom_data_layers_count():
		if a.get_custom_data_layer_name(layer) != b.get_custom_data_layer_name(layer) or a.get_custom_data_layer_type(layer) != b.get_custom_data_layer_type(layer):
			differences.append("%s: custom data layer %d differs" % [path, layer])
	if a.get_source_count() != b.get_source_count():
		differences.append("%s: %d sources against %d" % [path, a.get_source_count(), b.get_source_count()])
		return
	for i in a.get_source_count():
		var id := a.get_source_id(i)
		if id != b.get_source_id(i):
			differences.append("%s: source %d has another id" % [path, i])
			continue
		_source(a, b, id, "%s.sources[%d]" % [path, id], differences)


static func _source(set_a: TileSet, set_b: TileSet, id: int, path: String, differences: Array[String]) -> void:
	var a := set_a.get_source(id) as TileSetAtlasSource
	var b := set_b.get_source(id) as TileSetAtlasSource
	if a.resource_name != b.resource_name or a.texture_region_size != b.texture_region_size or a.margins != b.margins \
			or a.separation != b.separation or a.use_texture_padding != b.use_texture_padding:
		differences.append("%s: name, region size, margins, separation or padding differ" % path)
	same(a.texture, b.texture, path + ".texture", differences)
	if a.get_tiles_count() != b.get_tiles_count():
		differences.append("%s: %d tiles against %d" % [path, a.get_tiles_count(), b.get_tiles_count()])
		return
	for i in a.get_tiles_count():
		var at := a.get_tile_id(i)
		if at != b.get_tile_id(i) or a.get_tile_size_in_atlas(at) != b.get_tile_size_in_atlas(at):
			differences.append("%s: tile %d is at another place or size" % [path, i])
			continue
		var tile_a := a.get_tile_data(at, 0)
		var tile_b := b.get_tile_data(at, 0)
		var where := "%s%s" % [path, at]
		for layer in set_a.get_physics_layers_count():
			if tile_a.get_collision_polygons_count(layer) != tile_b.get_collision_polygons_count(layer):
				differences.append("%s: polygons of layer %d differ" % [where, layer])
				continue
			for p in tile_a.get_collision_polygons_count(layer):
				if tile_a.get_collision_polygon_points(layer, p) != tile_b.get_collision_polygon_points(layer, p):
					differences.append("%s: polygon %d of layer %d differs" % [where, p, layer])
		for layer in set_a.get_custom_data_layers_count():
			same(tile_a.get_custom_data_by_layer_id(layer), tile_b.get_custom_data_by_layer_id(layer), "%s.data%d" % [where, layer], differences)
		for flag in EngineJson.TILE_FLAGS + ["texture_origin", "z_index", "probability"]:
			if tile_a.get(flag) != tile_b.get(flag):
				differences.append("%s: %s differs" % [where, flag])
