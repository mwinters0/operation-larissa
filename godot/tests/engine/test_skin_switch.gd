class_name TestSkinSwitch
extends GdUnitTestSuite
## Teaches: a skin is looked at, never played. The sector world makes its presenter again when the skin changes and the rules
## never hear of it. That switching skins in the middle of a visit changes no line of the trace is checked for every skin there is in
## `test_skins_dont_change_the_game.gd`. Here: a skin's own presenter scene is the one the world builds, and a new skin's pictures show up.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const TINY := "res://tests/skins/tiny/skin.tres"
const BLANK_PRESENTER := "res://tests/skins/tiny/marker_presenter.tscn"


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	GameState.reset()


## A skin whose presenter is a scene of its own: a root that extends `SectorPresenter` and shows nothing.
func _skin_with_presenter() -> GameSkin:
	var skin := GameSkin.new()
	skin.id = &"marker_presenter"
	skin.presenter_scene = load(BLANK_PRESENTER) as PackedScene
	return skin


# --- the presenter of the skin -------------------------------------------------------------------------------

func test_a_skins_presenter_scene_is_the_original_kind_of_presenter() -> void:
	var original := PresenterChoice.make_presenter(PresenterChoice.ORIGINAL)
	assert_object(original).is_instanceof(OriginalPresenter)
	original.free()
	SkinChoice.select(_skin_with_presenter())
	var presenter := PresenterChoice.make_presenter(PresenterChoice.ORIGINAL)
	assert_str(String(presenter.name)).is_equal("MarkerPresenter")
	assert_str(String(PresenterChoice.kind_of(presenter))).is_equal("original")
	presenter.free()
	var debug := PresenterChoice.make_presenter(PresenterChoice.DEBUG_RECTS)            # (the debug rectangles are the skin's no matter what)
	assert_object(debug).is_instanceof(DebugRectPresenter)
	debug.free()


func test_a_world_started_with_a_skin_has_the_skins_presenter() -> void:
	SkinChoice.select(_skin_with_presenter())
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_str(world.presenter.scene_file_path).is_equal(BLANK_PRESENTER)               # (it took the name of the scene's own, "Presenter")
	assert_object(world.original).is_null()
	await await_idle_frame()                                    # (the scene's own presenter, taken out, is freed in this frame)


func test_a_world_changes_its_presenter_when_the_skin_changes() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(3, 0)
	var first := world.presenter
	assert_object(first).is_instanceof(OriginalPresenter)
	SkinChoice.select(_skin_with_presenter())
	assert_object(world.presenter).is_not_same(first)
	assert_str(world.presenter.scene_file_path).is_equal(BLANK_PRESENTER)
	assert_str(String(world.presenter.name)).is_equal("Presenter")             # (it takes the place, and the name, of the old one)
	assert_bool(world.presenter is OriginalPresenter).is_false()
	SkinChoice.select(SkinChoice.original())
	assert_object(world.presenter).is_instanceof(OriginalPresenter)
	assert_int(world.original.foes.size()).is_equal(world.sim.foes.size())      # (and it shows the sector that is loaded, built from the rules)


func test_the_new_presenter_draws_with_the_new_skins_pictures() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(0, 0)
	var marker := load("res://tests/skins/tiny/marker.png") as Texture2D
	var background := world.original.background.texture
	assert_object(background).is_not_same(marker)
	var skin := GameSkin.new()
	skin.id = &"marker_background"
	skin.pictures = {"background/bg_s00_00": marker}
	SkinChoice.select(skin)
	assert_object(world.original.background.texture).is_same(marker)
	SkinChoice.select(SkinChoice.original())
	assert_object(world.original.background.texture).is_same(background)


func test_a_debug_presenter_stays_debug_when_the_skin_changes() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.toggle_presenter()
	assert_object(world.presenter).is_instanceof(DebugRectPresenter)
	SkinChoice.select(load(TINY) as GameSkin)
	assert_object(world.presenter).is_instanceof(DebugRectPresenter)


# --- stepping through the skins (the debug key S) -------------------------------------------------------------

func test_after_steps_through_every_shipped_skin_and_wraps_to_the_original() -> void:
	var ids := SkinChoice.available()
	var seen: Array[StringName] = []
	var id := SkinChoice.ORIGINAL
	for i in ids.size():
		seen.append(id)
		id = SkinChoice.after(id)
	assert_array(seen).contains_exactly(ids)
	assert_str(String(id)).is_equal(String(SkinChoice.ORIGINAL))


func test_after_a_skin_that_is_not_shipped_comes_the_original() -> void:
	assert_str(String(SkinChoice.after((load(TINY) as GameSkin).id))).is_equal(String(SkinChoice.ORIGINAL))
