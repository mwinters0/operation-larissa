class_name TestSnapshots
extends GdUnitTestSuite
## Renders reference screens into PNG files (in `user://snapshots/`, so a test run never changes a file of the project; the pictures a
## reviewer has looked at can be kept under tests/snapshots/, which is ignored by version control: they show the original's art, so they
## are the legacy pack) so a human (or a student) can look at them, and checks they are not blank.
##
## Teaches: rendering a scene offscreen with a SubViewport and reading the pixels back.
## Needs a real renderer: with `--headless` (dummy renderer) the pictures are empty, so there the tests are skipped
## (gdUnit4's `do_skip` argument) and `tools/run_tests.sh` runs this file in a window.

const SNAPSHOT_DIR := "user://snapshots/"


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


## Renders screen `screen` of sector `sector` at native 608 x 288 into a PNG.
func _render(sector: int, screen: int) -> Image:
	var viewport := SubViewport.new()
	viewport.size = TileGrid.PLAYFIELD_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := (load("res://src/gameplay/sector_world.tscn") as PackedScene).instantiate() as SectorWorld
	viewport.add_child(world)
	add_child(viewport)
	world.load_sector(sector, screen)
	await get_tree().process_frame
	# The test runner is a plain SceneTree script: make sure a frame really gets drawn.
	RenderingServer.force_draw()
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


func _snapshot_test(sector: int, screen: int) -> void:
	var image := await _render(sector, screen)
	assert_int(image.get_width()).is_equal(608)
	assert_int(image.get_height()).is_equal(288)
	# Not blank: the picture contains plenty of different colours.
	var colors := {}
	for y in range(0, 288, 4):
		for x in range(0, 608, 4):
			colors[image.get_pixel(x, y)] = true
	assert_int(colors.size()).is_greater(50)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SNAPSHOT_DIR))
	var path := ProjectSettings.globalize_path(SNAPSHOT_DIR + "s%02d_screen%02d.png" % [sector, screen])
	assert_int(image.save_png(path)).is_equal(OK)


func test_snapshot_sector_0_screen_0(do_skip := DisplayServer.get_name() == "headless",
		skip_reason := "needs a real renderer (run it in a window)") -> void:
	await _snapshot_test(0, 0)


func test_snapshot_sector_0_screen_3(do_skip := DisplayServer.get_name() == "headless",
		skip_reason := "needs a real renderer (run it in a window)") -> void:
	await _snapshot_test(0, 3)
