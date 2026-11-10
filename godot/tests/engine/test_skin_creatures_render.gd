class_name TestSkinCreaturesRender
extends GdUnitTestSuite
## Teaches: looking at what a skin really draws, in a window. The puffer fish is 3D in a `SubViewport` of the Compatibility renderer;
## with `--headless` (the dummy renderer) nothing is drawn, so these tests are skipped there and `tools/run_tests.sh` runs this file in
## a window (see WINDOWED in the script). They read the pixels back, like `test_snapshots.gd`, and write the pictures to
## `user://snapshots/` for a human to look at.
##   * the 3D picture is transparent where there is no fish, and opaque and fish-coloured where there is,
##   * the playfield shows the 3D picture where the original's picture would be (the creature's picture rectangle),
##   * the rainbow fish's `AnimationTree` moves the body (its pivot is not at rest while the tree plays).

const SNAPSHOT_DIR := "user://snapshots/"
const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"


func before_test() -> void:
	GameClock.paused = true
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


## The playfield of `sector`/`screen` with the creatures skin in a `SubViewport` of its own, a few frames drawn.
func _render(sector: int, screen: int) -> Array:
	SkinChoice.select_id(&"creatures")
	var viewport := SubViewport.new()
	viewport.size = TileGrid.PLAYFIELD_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as SectorWorld
	viewport.add_child(world)
	add_child(viewport)
	world.load_sector(sector, screen)
	for i in 4:
		world.presenter.show_between_ticks(0.5)
		await get_tree().process_frame
	RenderingServer.force_draw()
	await get_tree().process_frame
	RenderingServer.force_draw()
	return [viewport, world]


func _save(image: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SNAPSHOT_DIR))
	assert_int(image.save_png(ProjectSettings.globalize_path(SNAPSHOT_DIR + name))).is_equal(OK)


func test_the_3d_picture_is_transparent_around_a_fish_that_is_there(do_skip := DisplayServer.get_name() == "headless",
		skip_reason := "needs a real renderer (run it in a window)") -> void:
	var made := await _render(DevCreatures.FISH, 0)
	var world := made[1] as SectorWorld
	var rig := (world.presenter as CreaturesPresenter).rig_for(DevCreatures.PUFFERS[0]) as PufferRig3D
	var image := rig.viewport().get_texture().get_image()
	assert_vector(Vector2(image.get_size())).is_equal(Vector2(320, 192))
	assert_float(image.get_pixel(1, 1).a).is_equal(0.0)                         # a corner: the sea behind shows through
	assert_float(image.get_pixel(318, 190).a).is_equal(0.0)
	var opaque := 0
	var yellow := 0
	for y in range(0, 192, 2):
		for x in range(0, 320, 2):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.9:
				opaque += 1
				if pixel.r > 0.5 and pixel.g > 0.4 and pixel.b < 0.45:
					yellow += 1
	assert_int(opaque).override_failure_message("nothing drawn in the 3D picture").is_greater(1500)
	assert_int(yellow).override_failure_message("the body is not yellow").is_greater(opaque / 3)
	_save(image, "creatures_puffer_viewport.png")
	made[0].queue_free()


func test_the_playfield_shows_the_3d_fish_where_the_original_picture_was(do_skip := DisplayServer.get_name() == "headless",
		skip_reason := "needs a real renderer (run it in a window)") -> void:
	var made := await _render(DevCreatures.FISH, 0)
	var viewport := made[0] as SubViewport
	var world := made[1] as SectorWorld
	var rig := (world.presenter as CreaturesPresenter).rig_for(DevCreatures.PUFFERS[0]) as PufferRig3D
	var image := viewport.get_texture().get_image()
	assert_vector(Vector2(image.get_size())).is_equal(Vector2(608, 288))
	_save(image, "creatures_s00_screen00.png")
	var rect := rig.drawn_rect()
	var yellow := 0
	for y in range(int(rect.position.y), int(rect.end.y)):
		for x in range(int(rect.position.x), int(rect.end.x)):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.55 and pixel.g > 0.45 and pixel.b < 0.4:
				yellow += 1
	assert_int(yellow).override_failure_message("no yellow fish in the original picture's rectangle %s" % rect).is_greater(400)
	viewport.queue_free()


func test_the_rainbow_fishs_body_is_moved_by_the_tree(do_skip := DisplayServer.get_name() == "headless",
		skip_reason := "needs a real renderer (run it in a window)") -> void:
	var made := await _render(DevCreatures.FISH, 3)
	var world := made[1] as SectorWorld
	var rig := (world.presenter as CreaturesPresenter).rig_for(DevCreatures.RAINBOW_FISH[0]) as RainbowFishRig
	var body := rig.get_node("Body") as Node2D
	var seen := {}
	for i in 30:
		await get_tree().process_frame
		seen[snappedf(body.rotation, 0.001)] = true
	assert_int(seen.size()).override_failure_message("the animation does not move the body").is_greater(3)
	_save((made[0] as SubViewport).get_texture().get_image(), "creatures_s00_screen03.png")
	made[0].queue_free()
