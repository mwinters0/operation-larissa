class_name TestTilesetBytesLegacy
extends GdUnitTestSuite
## The legacy pack's tile set: the importer names the sources after the original's zone titles, for the tile set panel of the editor.
## The tile set of dev and the tile_byte layer are in `tests/engine/test_tileset_bytes.gd`.


func _source(id: int) -> TileSetAtlasSource:
	return Catalog.tileset().get_source(id) as TileSetAtlasSource


func test_sources_are_named_for_the_tileset_panel() -> void:
	var titles: Array[String] = ["Dragon Reef", "Fossil Trench", "Limestone Ridge", "Sea Forest", "Hammerhead"]
	for zone in 5:
		assert_str(_source(zone).resource_name).starts_with("Zone %d: %s" % [zone, titles[zone]])
	assert_str(_source(4).resource_name).contains("finales")
	assert_str(_source(OriginalPresenter.CURRENTS_SOURCE_ID).resource_name).starts_with("Currents")
	assert_str(_source(OriginalPresenter.INVISIBLE_WALL_SOURCE_ID).resource_name).starts_with("Invisible wall")
