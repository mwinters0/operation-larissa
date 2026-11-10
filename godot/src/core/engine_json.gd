class_name EngineJson
extends RefCounted
## The data form of the two engine classes a pack holds: `SpriteFrames` and `TileSet` (with its `TileSetAtlasSource`s).
##
## `ResourceJson` is the one serializer; it hands these two class names here, because they are not scripts of the game and have no `@export`
## fields to walk: Godot keeps them in properties of its own. They are described, and built again with their public methods (`add_animation`,
## `add_frame`, `add_physics_layer`, `create_tile`, ...), by a whitelist. Any other engine class in a data file is a problem in `problems`; there
## is no `ClassDB.instantiate` here, so a file can only ask for what this script knows how to build. What a pack never uses (a tile's terrain,
## a physics material, an animated tile) is not in the description; `data_of` reports a set that has such a thing in `unsupported`.
##
## SpriteFrames: {"class": "SpriteFrames", "animations": [{"name": "all", "speed": 0, "loop": false, "frames": [{"texture": {"$ref": "assets/sprites/x.png"},
## "duration": 2}, ...]}]}   (`duration` is left out when it is 1.)
## TileSet: {"class": "TileSet", "tile_size": [16, 16], "physics_layers": [{"collision_layer": 1, "collision_mask": 1}],
## "custom_data_layers": [{"name": "current", "type": 5}], "sources": [{"id": 0, "name": "Zone 0", "texture": {"$ref": "assets/tiles/zone0_tiles.png"},
## "region_size": [16, 16], "padding": false, "tiles": [{"at": [0, 0], "physics": [[[-8, -8, 8, -8, 8, 8, -8, 8]]], "data": {"0": [-2, -2], "1": 64}}]}]}
## (`physics` is, per physics layer, the polygons of the tile as flat lists x, y, x, y; `data` the custom data by layer; a key left out is the default.)
##
## Teaches: describing an engine class by a whitelist instead of trusting a file to name a class; and that a Godot class which is not a script
## has to be walked with its methods (`get_tiles_count`, `get_tile_id`, `get_frame_texture`), not with `get_property_list`.

const SPRITE_FRAMES := "SpriteFrames"
const TILE_SET := "TileSet"
const CLASSES: Array[String] = [SPRITE_FRAMES, TILE_SET]

## Tile properties that are written when they are not the default (name -> the kind of value; the setter is the property itself).
const TILE_FLAGS: Array[String] = ["flip_h", "flip_v", "transpose"]

## What `data_of` met that the description cannot hold, one sentence each; empty for a set the description holds whole.
var unsupported: Array[String] = []


static func handles(class_of: String) -> bool:
	return CLASSES.has(class_of)


## The name of the engine class `resource` is when this script describes it, else "".
static func class_of(resource: Resource) -> String:
	if resource is SpriteFrames:
		return SPRITE_FRAMES
	if resource is TileSet:
		return TILE_SET
	return ""


# --- writing -------------------------------------------------------------------------------------------------------

## The description of `resource` (a `SpriteFrames` or a `TileSet`), with its "class". `host` writes the pictures (`ResourceJson.reference_of`).
func data_of(resource: Resource, host: ResourceJson) -> Dictionary:
	if resource is SpriteFrames:
		return _frames_data(resource, host)
	if resource is TileSet:
		return _tile_set_data(resource, host)
	unsupported.append("%s is not an engine class the data form describes" % resource.get_class())
	return {}


func _frames_data(frames: SpriteFrames, host: ResourceJson) -> Dictionary:
	var animations: Array = []
	for animation_name in frames.get_animation_names():
		var list: Array = []
		for i in frames.get_frame_count(animation_name):
			var frame := {}
			var texture := frames.get_frame_texture(animation_name, i)
			frame["texture"] = host.reference_of(texture)
			var duration := frames.get_frame_duration(animation_name, i)
			if not is_equal_approx(duration, 1.0):
				frame["duration"] = duration
			list.append(frame)
		animations.append({
			"name": String(animation_name), "speed": frames.get_animation_speed(animation_name),
			"loop": frames.get_animation_loop(animation_name), "frames": list})
	return {ResourceJson.CLASS_KEY: SPRITE_FRAMES, "animations": animations}


func _tile_set_data(tile_set: TileSet, host: ResourceJson) -> Dictionary:
	var data := {ResourceJson.CLASS_KEY: TILE_SET}
	if tile_set.tile_size != Vector2i(16, 16):
		data["tile_size"] = [tile_set.tile_size.x, tile_set.tile_size.y]
	var physics: Array = []
	for layer in tile_set.get_physics_layers_count():
		physics.append({"collision_layer": tile_set.get_physics_layer_collision_layer(layer),
				"collision_mask": tile_set.get_physics_layer_collision_mask(layer)})
	if not physics.is_empty():
		data["physics_layers"] = physics
	var custom: Array = []
	for layer in tile_set.get_custom_data_layers_count():
		custom.append({"name": tile_set.get_custom_data_layer_name(layer), "type": tile_set.get_custom_data_layer_type(layer)})
	if not custom.is_empty():
		data["custom_data_layers"] = custom
	var sources: Array = []
	for i in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(i)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			unsupported.append("source %d is not an atlas" % source_id)
			continue
		sources.append(_source_data(tile_set, source_id, source, host))
	data["sources"] = sources
	return data


func _source_data(tile_set: TileSet, source_id: int, source: TileSetAtlasSource, host: ResourceJson) -> Dictionary:
	var data := {"id": source_id}
	if not source.resource_name.is_empty():
		data["name"] = source.resource_name
	if source.texture != null:
		data["texture"] = host.reference_of(source.texture)
	if source.texture_region_size != Vector2i(16, 16):
		data["region_size"] = [source.texture_region_size.x, source.texture_region_size.y]
	if source.margins != Vector2i.ZERO:
		data["margins"] = [source.margins.x, source.margins.y]
	if source.separation != Vector2i.ZERO:
		data["separation"] = [source.separation.x, source.separation.y]
	data["padding"] = source.use_texture_padding
	var tiles: Array = []
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		tiles.append(_tile_data(tile_set, source, coords, host))
	data["tiles"] = tiles
	return data


func _tile_data(tile_set: TileSet, source: TileSetAtlasSource, coords: Vector2i, host: ResourceJson) -> Dictionary:
	var data := {"at": [coords.x, coords.y]}
	var size := source.get_tile_size_in_atlas(coords)
	if size != Vector2i.ONE:
		data["size"] = [size.x, size.y]
	if source.get_tile_animation_frames_count(coords) > 1:
		unsupported.append("tile %s has an animation" % coords)
	var tile := source.get_tile_data(coords, 0)
	var physics: Array = []
	var any_polygon := false
	for layer in tile_set.get_physics_layers_count():
		var polygons: Array = []
		for p in tile.get_collision_polygons_count(layer):
			polygons.append(Array(tile.get_collision_polygon_points(layer, p)).reduce(
					func(flat: Array, point: Vector2) -> Array:
						flat.append_array([point.x, point.y])
						return flat, []))
			any_polygon = true
		physics.append(polygons)
	if any_polygon:
		data["physics"] = physics
	var values := {}
	for layer in tile_set.get_custom_data_layers_count():
		var value: Variant = tile.get_custom_data_by_layer_id(layer)
		if typeof(value) != TYPE_NIL and not is_same(value, type_convert(null, tile_set.get_custom_data_layer_type(layer))):
			values[str(layer)] = host.encode_value(value)
	if not values.is_empty():
		data["data"] = values
	for flag in TILE_FLAGS:
		if tile.get(flag):
			data[flag] = true
	if tile.texture_origin != Vector2i.ZERO:
		data["texture_origin"] = [tile.texture_origin.x, tile.texture_origin.y]
	if tile.z_index != 0:
		data["z_index"] = tile.z_index
	if tile.probability != 1.0:
		data["probability"] = tile.probability
	if tile.terrain_set != -1 or tile.material != null or tile.modulate != Color.WHITE:
		unsupported.append("tile %s has a terrain, a material or a colour" % coords)
	return data


# --- reading -------------------------------------------------------------------------------------------------------

## The engine resource `data` describes (its "class" says which). `host` reads the pictures and keeps the problems.
func build(data: Dictionary, host: ResourceJson, label: String) -> Resource:
	match String(data.get(ResourceJson.CLASS_KEY, "")):
		SPRITE_FRAMES:
			return _build_frames(data, host, label)
		TILE_SET:
			return _build_tile_set(data, host, label)
	host.problems.append("%s: '%s' is not an engine class the data form describes (%s)" % [label, data.get(ResourceJson.CLASS_KEY, ""), ", ".join(CLASSES)])
	return null


func _build_frames(data: Dictionary, host: ResourceJson, label: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	host.check_keys(data, ["animations"], label)
	var animations: Variant = data.get("animations", [])
	if not animations is Array:
		host.problems.append("%s.animations should be a list" % label)
		return frames
	for a in (animations as Array).size():
		var entry: Variant = animations[a]
		var where := "%s.animations[%d]" % [label, a]
		if not entry is Dictionary or not (entry as Dictionary).get("name") is String:
			host.problems.append("%s should be an object with a name" % where)
			continue
		host.check_keys(entry, ["name", "speed", "loop", "frames"], where)
		var animation_name := StringName(entry["name"])
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, host.number(entry.get("speed", 5.0), where + ".speed", 5.0))
		frames.set_animation_loop(animation_name, bool(entry.get("loop", true)))
		var list: Variant = entry.get("frames", [])
		if not list is Array:
			host.problems.append("%s.frames should be a list" % where)
			continue
		for f in (list as Array).size():
			var frame: Variant = list[f]
			var frame_where := "%s.frames[%d]" % [where, f]
			if not frame is Dictionary:
				host.problems.append("%s should be an object" % frame_where)
				continue
			host.check_keys(frame, ["texture", "duration"], frame_where)
			var texture := host.texture_from(frame.get("texture"), frame_where + ".texture")
			frames.add_frame(animation_name, texture, host.number(frame.get("duration", 1.0), frame_where + ".duration", 1.0))
	return frames


func _build_tile_set(data: Dictionary, host: ResourceJson, label: String) -> TileSet:
	var tile_set := TileSet.new()
	host.check_keys(data, ["tile_size", "physics_layers", "custom_data_layers", "sources"], label)
	if data.has("tile_size"):
		tile_set.tile_size = host.vector2i(data["tile_size"], label + ".tile_size", tile_set.tile_size)
	for layer in _list(data.get("physics_layers"), label + ".physics_layers", host):
		if layer is Dictionary:
			var index := tile_set.get_physics_layers_count()
			tile_set.add_physics_layer()
			tile_set.set_physics_layer_collision_layer(index, int(layer.get("collision_layer", 1)))
			tile_set.set_physics_layer_collision_mask(index, int(layer.get("collision_mask", 1)))
	for layer in _list(data.get("custom_data_layers"), label + ".custom_data_layers", host):
		if layer is Dictionary and layer.get("name") is String and (layer.get("type") is float or layer.get("type") is int):
			var index := tile_set.get_custom_data_layers_count()
			tile_set.add_custom_data_layer()
			tile_set.set_custom_data_layer_name(index, layer["name"])
			tile_set.set_custom_data_layer_type(index, int(layer["type"]) as Variant.Type)
		else:
			host.problems.append("%s.custom_data_layers: each is {\"name\": text, \"type\": number}" % label)
	var sources := _list(data.get("sources"), label + ".sources", host)
	for s in sources.size():
		if sources[s] is Dictionary:
			_build_source(tile_set, sources[s], host, "%s.sources[%d]" % [label, s])
		else:
			host.problems.append("%s.sources[%d] should be an object" % [label, s])
	return tile_set


func _build_source(tile_set: TileSet, data: Dictionary, host: ResourceJson, label: String) -> void:
	host.check_keys(data, ["id", "name", "texture", "region_size", "margins", "separation", "padding", "tiles"], label)
	var source := TileSetAtlasSource.new()
	source.resource_name = str(data.get("name", ""))
	source.texture = host.texture_from(data.get("texture"), label + ".texture")
	source.texture_region_size = host.vector2i(data.get("region_size", [16, 16]), label + ".region_size", Vector2i(16, 16))
	source.margins = host.vector2i(data.get("margins", [0, 0]), label + ".margins", Vector2i.ZERO)
	source.separation = host.vector2i(data.get("separation", [0, 0]), label + ".separation", Vector2i.ZERO)
	source.use_texture_padding = bool(data.get("padding", true))
	tile_set.add_source(source, int(data.get("id", -1)))
	var tiles := _list(data.get("tiles"), label + ".tiles", host)
	for t in tiles.size():
		if tiles[t] is Dictionary:
			_build_tile(tile_set, source, tiles[t], host, "%s.tiles[%d]" % [label, t])
		else:
			host.problems.append("%s.tiles[%d] should be an object" % [label, t])


func _build_tile(tile_set: TileSet, source: TileSetAtlasSource, data: Dictionary, host: ResourceJson, label: String) -> void:
	host.check_keys(data, ["at", "size", "physics", "data", "texture_origin", "z_index", "probability"] + TILE_FLAGS, label)
	var coords := host.vector2i(data.get("at"), label + ".at", Vector2i(-1, -1))
	var size := host.vector2i(data.get("size", [1, 1]), label + ".size", Vector2i.ONE)
	if coords.x < 0 or not source.has_room_for_tile(coords, size, 1, Vector2i.ZERO, 1, Vector2i(-1, -1)):
		host.problems.append("%s: no room for a tile at %s" % [label, coords])
		return
	source.create_tile(coords, size)
	var tile := source.get_tile_data(coords, 0)
	var layers := _list(data.get("physics"), label + ".physics", host)
	for layer in mini(layers.size(), tile_set.get_physics_layers_count()):
		for polygon in _list(layers[layer], label + ".physics", host):
			var points := PackedVector2Array()
			if polygon is Array and polygon.size() % 2 == 0:
				for i in range(0, polygon.size(), 2):
					points.append(Vector2(float(polygon[i]), float(polygon[i + 1])))
			else:
				host.problems.append("%s.physics: a polygon is a flat list x, y, x, y" % label)
				continue
			var index := tile.get_collision_polygons_count(layer)
			tile.add_collision_polygon(layer)
			tile.set_collision_polygon_points(layer, index, points)
	var values: Variant = data.get("data", {})
	if values is Dictionary:
		for key: String in values:
			var layer := key.to_int()
			if not key.is_valid_int() or layer < 0 or layer >= tile_set.get_custom_data_layers_count():
				host.problems.append("%s.data: no custom data layer '%s'" % [label, key])
				continue
			tile.set_custom_data_by_layer_id(layer, host.value_of_kind(values[key], tile_set.get_custom_data_layer_type(layer), "%s.data[%s]" % [label, key]))
	for flag in TILE_FLAGS:
		if data.has(flag):
			tile.set(flag, bool(data[flag]))
	if data.has("texture_origin"):
		tile.texture_origin = host.vector2i(data["texture_origin"], label + ".texture_origin", Vector2i.ZERO)
	if data.has("z_index"):
		tile.z_index = int(data["z_index"])
	if data.has("probability"):
		tile.probability = host.number(data["probability"], label + ".probability", 1.0)


static func _list(value: Variant, label: String, host: ResourceJson) -> Array:
	if value == null:
		return []
	if not value is Array:
		host.problems.append("%s should be a list" % label)
		return []
	return value
