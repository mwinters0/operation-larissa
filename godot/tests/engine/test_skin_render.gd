class_name TestSkinRender
extends GdUnitTestSuite
## Teaches: a project setting is only the DEFAULT of a node's property. Nearest filtering and pixel snapping are set for the
## whole project today (`project.godot`), and are also properties of every `Viewport` (and the filter of every `CanvasItem`), so a skin
## carries its own `RenderSettings`. The original skin's settings ARE the project's (tested here against `ProjectSettings`), so the
## original look is exactly today's; a skin that sets other ones changes the window while it is in use and gives them back when it is not.

const TINY := "res://tests/skins/tiny/skin.tres"
const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"


func before_test() -> void:
	SkinChoice.select(SkinChoice.original())


func after_test() -> void:
	SkinChoice.select(SkinChoice.original())


func _window() -> Window:
	return get_tree().root


# --- the original look is the project's ---------------------------------------------------------------------

func test_the_original_skins_settings_are_the_projects() -> void:
	var settings := SkinChoice.original().render_settings()
	assert_int(settings.texture_filter).is_equal(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"))
	assert_bool(settings.snap_transforms).is_equal(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel"))
	assert_bool(settings.snap_vertices).is_equal(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_vertices_to_pixel"))
	assert_int(settings.playfield_filter).is_equal(CanvasItem.TEXTURE_FILTER_PARENT_NODE)
	# and a blank `RenderSettings` (what a skin with none falls back to) is the same thing
	var blank := RenderSettings.new()
	assert_int(blank.texture_filter).is_equal(settings.texture_filter)
	assert_bool(blank.snap_transforms).is_equal(settings.snap_transforms)
	assert_bool(blank.snap_vertices).is_equal(settings.snap_vertices)


func test_the_window_has_the_original_skins_settings() -> void:
	assert_bool(SkinChoice.original().render_settings().is_applied_to(_window())).is_true()
	assert_int(_window().canvas_item_default_texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	assert_bool(_window().snap_2d_transforms_to_pixel).is_true()
	assert_bool(_window().snap_2d_vertices_to_pixel).is_true()


# --- a skin with its own settings ------------------------------------------------------------------------------

func test_a_skin_sets_the_windows_filter_and_snapping_and_gives_them_back() -> void:
	var tiny := load(TINY) as GameSkin
	SkinChoice.select(tiny)
	assert_int(_window().canvas_item_default_texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
	assert_bool(_window().snap_2d_transforms_to_pixel).is_false()
	assert_bool(_window().snap_2d_vertices_to_pixel).is_false()
	assert_bool(tiny.render_settings().is_applied_to(_window())).is_true()
	SkinChoice.select(SkinChoice.original())
	assert_bool(SkinChoice.original().render_settings().is_applied_to(_window())).is_true()


func test_a_skin_without_settings_leaves_them_as_the_skin_behind_it_has() -> void:
	var skin := GameSkin.new()
	skin.id = &"no_settings"
	SkinChoice.select(skin)
	assert_bool(SkinChoice.original().render_settings().is_applied_to(_window())).is_true()
	var smooth := GameSkin.new()
	smooth.id = &"smooth_child"
	smooth.fallback = load(TINY) as GameSkin
	SkinChoice.select(smooth)
	assert_int(_window().canvas_item_default_texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)


func test_a_sub_viewport_is_given_the_settings_by_the_skin_that_makes_it() -> void:
	# a SubViewport does not inherit the window's settings (3D creatures and shaders draw into one)
	var view := auto_free(SubViewport.new()) as SubViewport
	var settings := SkinChoice.original().render_settings()
	assert_bool(settings.is_applied_to(view)).is_false()
	assert_bool(view.snap_2d_transforms_to_pixel).is_false()
	settings.apply_to(view)
	assert_bool(settings.is_applied_to(view)).is_true()
	assert_bool(view.snap_2d_transforms_to_pixel).is_true()


func test_a_skin_may_filter_the_playfield_on_its_own() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_int(world.presenter.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_PARENT_NODE)      # the original: like the window
	var settings := RenderSettings.new()
	settings.playfield_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var skin := GameSkin.new()
	skin.id = &"smooth_playfield"
	skin.render = settings
	SkinChoice.select(skin)
	assert_int(world.presenter.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_LINEAR)          # (a new presenter, put in by the switch)
	assert_int(_window().canvas_item_default_texture_filter).is_equal(Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST)     # (the HUD keeps its own)
