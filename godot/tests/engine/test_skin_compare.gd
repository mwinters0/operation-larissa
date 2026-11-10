class_name TestSkinCompare
extends GdUnitTestSuite
## Teaches: the tools of skin authoring and the one seam they need. `SkinChoice.current()` is global, but the side-by-side tool
## (`src/debug/skin_compare.tscn`) shows two skins at once, so a presenter can be dressed for one skin (`SectorPresenter.skin`): what it
## fetches through `Assets` / `Catalog` - when it is built, in an event, in a frame - comes from that skin (`SkinChoice.within`) while the rest
## of the game wears another. Also the overlay: the debug rectangles laid over whatever presenter a world has (`SectorWorld.set_overlay`).

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const COMPARE_SCENE := "res://src/debug/skin_compare.tscn"
const MARKER := "res://tests/skins/tiny/marker.png"

var _scale_size: Vector2i
var _window_size: Vector2i


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	PresenterChoice.overlay_forced = false
	SkinChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	_scale_size = get_window().content_scale_size                  # (the tool sets the window to its own size)
	_window_size = get_window().size
	GameState.reset()


func after_test() -> void:
	GameClock.paused = false
	PresenterChoice.overlay_forced = false
	SkinChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	get_window().content_scale_size = _scale_size
	get_window().size = _window_size
	GameState.reset()


## A skin that shows the marker square for the backgrounds of the first two screens of sector 0, and says the HUD's words as text.
func _marker_skin() -> GameSkin:
	var skin := load(SkinRoster.TINY).duplicate() as GameSkin
	skin.id = &"marker_backgrounds"
	var marker := load(MARKER) as Texture2D
	skin.pictures = {"background/bg_s00_00": marker, "background/bg_s00_01": marker}
	return skin


## A presenter that notes which skin is in use whenever it hears something.
class Probe:
	extends SectorPresenter
	var heard: Array[GameSkin] = []

	func bind(sim_world: SimWorld) -> void:
		super.bind(sim_world)
		_listen(view.ticked, func() -> void: heard.append(SkinChoice.current()))
		_listen(view.screen_loaded, func(_sector: int, _screen: int) -> void: heard.append(SkinChoice.current()))


# --- the seam ---------------------------------------------------------------------------------------------------

func test_within_makes_a_skin_current_for_a_while_and_selects_nothing() -> void:
	var skin := _marker_skin()
	var original := SkinChoice.original()
	var seen: Array[GameSkin] = []
	SkinChoice.within(skin, func() -> void:
		seen.append(SkinChoice.current())
		SkinChoice.within(original, func() -> void: seen.append(SkinChoice.current()))          # (nested: the inner one, then back)
		seen.append(SkinChoice.current()))
	assert_array(seen).is_equal([skin, original, skin])
	assert_object(SkinChoice.current()).is_same(original)
	assert_object(SkinChoice.within(null, func() -> Object: return SkinChoice.current())).is_same(original)       # (a null skin: just runs it)
	assert_object(SkinChoice.within(skin, func() -> Object: return Assets.background(0, 0))).is_same(load(MARKER))
	assert_object(Assets.background(0, 0)).is_not_same(load(MARKER))
	var changes := [0]
	var listener := func(_skin: GameSkin) -> void: changes[0] += 1
	SkinChoice.events.changed.connect(listener)
	SkinChoice.within(skin, func() -> void: pass)
	SkinChoice.events.changed.disconnect(listener)          # (`events` is a static: it outlives the test, and a lambda left on it points at the freed suite when the process exits)
	assert_int(changes[0]).is_equal(0)                                                       # (nobody is told: nothing was selected)


func test_a_presenter_with_a_skin_hears_every_event_inside_that_skin() -> void:
	var skin := _marker_skin()
	var sim := SimWorld.new(GameState)
	var dressed := auto_free(Probe.new()) as Probe
	dressed.skin = skin
	dressed.bind(sim)
	var plain := auto_free(Probe.new()) as Probe                          # (no skin: whichever is in use)
	plain.bind(sim)
	sim.load_sector(0, 0)
	sim.tick()
	assert_int(dressed.heard.size()).is_equal(2)                           # screen_loaded and ticked, with their arguments passed through
	assert_bool(dressed.heard.all(func(heard: GameSkin) -> bool: return heard == skin)).is_true()
	assert_bool(plain.heard.all(func(heard: GameSkin) -> bool: return heard == SkinChoice.original())).is_true()
	dressed.unbind()
	sim.tick()
	assert_int(dressed.heard.size()).is_equal(2)                           # (and unbinding takes the wrapped handlers back)
	assert_array(sim.ticked.get_connections().filter(func(c: Dictionary) -> bool: return not (c["callable"] as Callable).is_valid())).is_empty()


func test_a_dressed_original_presenter_builds_its_screens_from_its_own_skin() -> void:
	var skin := _marker_skin()
	var sim := SimWorld.new(GameState)
	var host := auto_free(Node2D.new()) as Node2D
	add_child(host)
	var presenter := PresenterChoice.make_presenter_for(skin)
	host.add_child(presenter)
	presenter.bind(sim)
	sim.load_sector(0, 0)
	var dressed := presenter as OriginalPresenter
	assert_object(dressed.background.texture).is_same(load(MARKER))
	sim.load_screen(1)                                                     # (an event: built inside the presenter's skin, while the skin in use is the original's)
	assert_object(dressed.background.texture).is_same(load(MARKER))
	sim.load_screen(2)
	assert_object(dressed.background.texture).is_not_same(load(MARKER))    # (a picture the skin does not map: the original's file)
	assert_object(SkinChoice.current()).is_same(SkinChoice.original())


# --- the overlay -----------------------------------------------------------------------------------------------

func test_a_world_can_wear_the_debug_rectangles_over_its_picture() -> void:
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.load_sector(3, 0)
	assert_object(world.overlay).is_null()
	world.set_overlay(true)
	var overlay := world.overlay
	assert_object(overlay).is_not_null()
	assert_bool(overlay.backdrop).is_false()
	assert_object(overlay.sim).is_same(world.sim)
	assert_object(world.presenter).is_instanceof(OriginalPresenter)         # (the picture stays: the rectangles are over it)
	assert_object(world.get_child(world.get_child_count() - 1)).is_same(overlay)
	assert_int(overlay.boxes().filter(func(box: DebugRectPresenter.Box) -> bool: return box.kind == &"wall").size()).is_greater(0)
	world.set_overlay(true)                                                  # (on again: nothing new)
	assert_object(world.overlay).is_same(overlay)
	# a new presenter (a skin, the key P) goes under the rectangles, which stay and keep showing the rules
	world.toggle_presenter()
	assert_object(world.get_child(world.get_child_count() - 1)).is_same(overlay)
	SkinChoice.select(load(SkinRoster.TINY) as GameSkin)
	assert_object(world.get_child(world.get_child_count() - 1)).is_same(overlay)
	assert_object(world.overlay).is_same(overlay)
	world.toggle_overlay()
	assert_object(world.overlay).is_null()
	assert_bool(is_instance_valid(overlay) and overlay.is_inside_tree()).is_false()
	assert_object(overlay.sim).is_null()                                      # (it stopped listening to the rules)


func test_the_overlay_can_be_asked_for_before_the_world_exists() -> void:
	PresenterChoice.overlay_forced = true                                      # (what `-- --overlay` does)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_object(world.overlay).is_not_null()


# --- the side-by-side tool ---------------------------------------------------------------------------------------

func _compare(skin_path: String) -> Control:
	var tool := (load(COMPARE_SCENE) as PackedScene).instantiate() as Control
	tool.set("start_skin", skin_path)
	tool.set("start_sector", 0)
	add_child(auto_free(tool))
	return tool


func test_the_tool_shows_one_set_of_rules_through_two_skins() -> void:
	var tool := _compare(SkinRoster.TINY)
	var world := tool.get("world") as SectorWorld
	var presenter := tool.get("_presenter") as SectorPresenter
	assert_object(SkinChoice.current()).is_same(SkinChoice.original())                 # (nothing was selected: the skin in use is the original)
	assert_object(world.presenter).is_instanceof(OriginalPresenter)
	assert_object(presenter.sim).is_same(world.sim)                                      # (ONE sim: the left half's world owns it, both look at it)
	assert_str(String(presenter.skin.id)).is_equal("tiny")
	var left_hud := tool.get_node("LeftContainer/LeftViewport/Hud") as Hud
	var right_hud := tool.get("_hud") as Hud
	assert_bool(left_hud.game_text.visible).is_false()                                  # (the original's HUD has the words as pictures, the tiny skin's as text)
	assert_bool(right_hud.game_text.visible).is_true()
	assert_str(right_hud.game_text.text).is_equal("Tiny Voyager")
	assert_object(tool.get("right_viewport").get_child(0)).is_not_null()
	# a screen change is one event of the rules and both halves follow it
	world.go(SectorData.Direction.RIGHT)
	assert_int(world.screen_index).is_equal(world.sim.screen_index)
	# the skin of the right half is picked from the drop-down: its presenter is made again for the new skin and the old one stops listening
	var before := presenter
	tool.call("_pick_skin", 0)                                                          # (the original, to look the same on both sides)
	var after := tool.get("_presenter") as SectorPresenter
	assert_object(after).is_not_same(before)
	assert_object(before.sim).is_null()
	assert_object(after.skin).is_same(SkinChoice.original())
	# the rectangles go over both halves, and the left one is the world's
	tool.call("_set_overlay", true)
	assert_object(world.overlay).is_not_null()
	assert_object(tool.get("_overlay")).is_not_null()
	assert_object((tool.get("_overlay") as DebugRectPresenter).sim).is_same(world.sim)
	tool.call("_pick_skin", 1)                                                          # (the overlay survives a new skin)
	assert_object(tool.get("_overlay")).is_not_null()


func test_the_right_half_keeps_its_skins_pictures_while_the_left_has_the_originals() -> void:
	var skin := _marker_skin()
	var tool := (load(COMPARE_SCENE) as PackedScene).instantiate() as Control
	tool.set("start_skin", SkinRoster.TINY)
	add_child(auto_free(tool))
	tool.call("_show_skin", skin)                                                       # (a skin that is not in the drop-down)
	var world := tool.get("world") as SectorWorld
	world.load_sector(0, 0)
	var right := tool.get("_presenter") as OriginalPresenter
	assert_object(right.background.texture).is_same(load(MARKER))
	assert_object(world.original.background.texture).is_not_same(load(MARKER))
	world.load_screen(1)
	assert_object(right.background.texture).is_same(load(MARKER))
	assert_object(world.original.background.texture).is_not_same(load(MARKER))
