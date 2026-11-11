class_name TestModSkinHudRender
extends GdUnitTestSuite
## Teaches: looking at what a mod really draws, in a window. The clip that keeps a script's picture inside its part's rectangle is the renderer's (`Control.clip_contents` on the node that holds the stack), so only a render shows it works: the fixture `skin_hud`
## paints its light with a rectangle over the WHOLE window and the test reads the pixels back from a `SubViewport` (the dummy renderer of `--headless` draws nothing, so the tests are skipped there and `tools/run_tests.sh` runs this file in a window, WINDOWED in the script).
##   * what the script draws in its part's rectangle is there, and nothing of the overpainting is outside the rectangle,
##   * a part the script does not draw is the original's picture.

const HUD_SCENE := "res://src/ui/hud.tscn"
const FIXTURE := "res://tests/mods/skin_hud"

var _shelves: Array[PackShelf] = []


func before() -> void:
	assert_bool(ModLoader.sandbox_available()).override_failure_message("the godot-sandbox extension is not loaded: run `uv run tools/fetch_sandbox.py`, then `tools/godot.sh --headless --path godot --import` (docs/SETUP.md)").is_true()


func before_test() -> void:
	GameClock.paused = true
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	GameState.set_sector(0, 9)


func after_test() -> void:
	GameClock.paused = false
	SkinChoice.select(SkinChoice.original())
	ModSkinShelf.release(_shelves)
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	GameState.sector = -1
	GameState.piece_total = 0


## The console wearing the fixture's skin, in a transparent `SubViewport` of the window's size, drawn.
func _render() -> Array:
	var shelf := PackShelf.new()
	_shelves.append(shelf)
	shelf.add_mod_fixture(FIXTURE)
	ModSkinShelf.add_files(shelf)
	shelf.mount()
	Mods.sync()
	SkinChoice.select(SkinChoice.load_skin(shelf.id))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 400)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var hud := (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	viewport.add_child(hud)
	add_child(viewport)
	for i in 4:
		hud.show_mod_layers(0.5)
		await get_tree().process_frame
	RenderingServer.force_draw()
	await get_tree().process_frame
	RenderingServer.force_draw()
	return [viewport, hud]


func test_the_overpainting_is_cut_off_at_the_lights_rectangle(do_skip := DisplayServer.get_name() == "headless",
		skip_reason := "needs a real renderer (run it in a window)") -> void:
	var made := await _render()
	var viewport := made[0] as SubViewport
	var hud := made[1] as Hud
	var image := viewport.get_texture().get_image()
	var area: Rect2 = ConsoleState.rects(hud.layout)["hud_ship"]
	var inside := image.get_pixelv(Vector2i(area.get_center()))
	assert_float(inside.a).override_failure_message("nothing in the light's rectangle").is_greater(0.0)
	assert_bool(inside.is_equal_approx(Color(0.2, 0.2, 0.0))).override_failure_message("the light's own picture (a dark yellow square, drawn over the overpainting) is in its rectangle: %s" % inside).is_true()
	assert_float(image.get_pixelv(Vector2i(300, 100)).a).override_failure_message("the overpainting shows over the playfield, where the console draws nothing").is_equal(0.0)
	var bezel := Color(0.10, 0.12, 0.16)                                                  # (the bezel's own part, drawn by the script: a place no other part covers is exactly its colour, the overpainting of the light is not on it)
	var apart := image.get_pixelv(Vector2i(20, 360))
	assert_float(absf(apart.r - bezel.r) + absf(apart.g - bezel.g) + absf(apart.b - bezel.b)).override_failure_message("the bezel's colour is spoiled at (20, 360): %s" % apart).is_less(0.03)
	viewport.queue_free()


func test_a_part_the_script_draws_shows_its_picture_and_one_it_does_not_is_the_originals(do_skip := DisplayServer.get_name() == "headless",
		skip_reason := "needs a real renderer (run it in a window)") -> void:
	var made := await _render()
	var viewport := made[0] as SubViewport
	var hud := made[1] as Hud
	var image := viewport.get_texture().get_image()
	var zone: Rect2 = ConsoleState.rects(hud.layout)["hud_zone"]
	var green := image.get_pixelv(Vector2i(zone.end) - Vector2i(2, 2))
	assert_float(green.g).override_failure_message("the zone box of the script is green: %s" % green).is_greater(green.r + 0.1)
	var game: Rect2 = ConsoleState.rects(hud.layout)["hud_game"]                          # (a part the script does not draw: the original's picture, in the dev pack a flat colour with its words)
	assert_float(image.get_pixelv(Vector2i(game.position) + Vector2i(1, 1)).a).is_greater(0.0)
	assert_bool(hud.game_label.modulate.a > 0.0).is_true()
	viewport.queue_free()
