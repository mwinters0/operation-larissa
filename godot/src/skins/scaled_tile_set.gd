class_name ScaledTileSet
extends RefCounted
## A tile set for the run's picture scale. The game's tile grid is 16 x 16 units and the tile set a pack holds says so (`data/neptune_tileset.tres`: cells of 16, atlases cut in 16 x 16 tiles); its atlases hold `PictureRef`s, which are `ScaledTexture`s when the
## run draws at a scale N above 1 (`PictureScale`), and a `ScaledTexture` reports 1/N of its file. A `TileMapLayer` reads that size for the atlas grid but hands the renderer the texture's own RID, which a `ScaledTexture` has none of (and, with
## `use_texture_padding`, builds its padded atlas from `get_image()`, which it has none of either), so the tile set is made again for the layer that draws it: `of` is the same tile set with every atlas holding the stored file and every length of it N times
## as long (cell size, tile size in the atlas, margins, separation, the texture origin of a tile, the points of its collision polygons), and `dress` puts it on layers scaled by 1/N. A cell is then still 16 game units, a tile is drawn from N x N times the pixels,
## and the cell a tile is set in, its atlas coordinates and its custom data (`TileCodec`) are the ones of the tile set a pack holds.
##
## THE OWNER of N is `Packs.picture_scale`, read each time a set is made; the tile set a pack holds is never changed (the copy is deep). A layer that is shown again (the chain changed: `Pictures.events`) is dressed again from `Catalog.tileset()`, so the
## presenter first made, the one made after a pack change and the one bound in the middle of a sector see the same thing.
##
## Teaches: what a `TileMapLayer` asks of its tile set (the atlas texture's RID and `get_image()`, not its `draw` methods), a deep `Resource.duplicate` of a tile set, and a node's `scale` as the way to draw a finer grid in the same space.


## The tile set `tile_set` for pictures of scale `scale`: `tile_set` itself when `scale` is 1 (nothing to change), else a deep copy whose atlases hold the stored files of their pictures and whose lengths are `scale` times as long. An atlas whose picture no pack holds is left
## without a texture (as the pack's own tile set has none to draw).
static func of(tile_set: TileSet, scale: int) -> TileSet:
	if tile_set == null or scale <= 1:
		return tile_set
	var made := tile_set.duplicate(true) as TileSet
	made.tile_size = tile_set.tile_size * scale
	for index in made.get_source_count():
		var source := made.get_source(made.get_source_id(index)) as TileSetAtlasSource
		if source != null:
			_scale_source(source, tile_set.get_source(tile_set.get_source_id(index)) as TileSetAtlasSource, scale, made)
	return made


## Puts the tile set for the run's picture scale (`Packs.picture_scale`) on `layers`, and the layers at `1 / scale`: the one place a layer is given a tile set, so each path that shows tiles (the presenter, the debug scenes) dresses them the same way.
static func dress(layers: Array[TileMapLayer], tile_set: TileSet) -> void:
	var scale := Packs.picture_scale()
	var made := of(tile_set, scale)
	for layer in layers:
		layer.tile_set = made
		layer.scale = Vector2.ONE / float(scale)


static func _scale_source(source: TileSetAtlasSource, original: TileSetAtlasSource, scale: int, tile_set: TileSet) -> void:
	var stored := ScaledTexture.stored(original.texture)
	if stored == null:
		source.texture = null
		return
	source.texture = stored                                                       # (first: the larger file makes room for the larger region size, so no tile is dropped for the moment the two disagree)
	source.texture_region_size = original.texture_region_size * scale
	source.margins = original.margins * scale
	source.separation = original.separation * scale
	for tile_index in source.get_tiles_count():
		var coords := source.get_tile_id(tile_index)
		for alternative_index in source.get_alternative_tiles_count(coords):
			_scale_tile(source.get_tile_data(coords, source.get_alternative_tile_id(coords, alternative_index)), scale, tile_set)


## The lengths of a tile's data: where its picture sits and the points of its collision polygons (the two things the data form of a tile set holds that are lengths, `EngineJson`).
static func _scale_tile(tile: TileData, scale: int, tile_set: TileSet) -> void:
	tile.texture_origin *= scale
	for layer in tile_set.get_physics_layers_count():
		for polygon in tile.get_collision_polygons_count(layer):
			var points := tile.get_collision_polygon_points(layer, polygon)
			for i in points.size():
				points[i] *= float(scale)
			tile.set_collision_polygon_points(layer, polygon, points)
