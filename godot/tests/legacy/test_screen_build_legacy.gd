class_name TestScreenBuildLegacy
extends GdUnitTestSuite
## The original's backgrounds: one 608 x 288 picture (the size of the playfield) behind each screen of a sector. The screen building is in `tests/engine/test_screen_build.gd`.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"


func test_background_matches_sector_and_screen() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(2, 7)
	assert_str(Packs.source_of(world.original.background.texture)).ends_with("bg_s02_07.png")
	assert_that(world.original.background.texture.get_size()).is_equal(Vector2(608, 288))
