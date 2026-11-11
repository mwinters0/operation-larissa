class_name TestPresenterBindsLate
extends GdUnitTestSuite
## "A presenter bound in the middle of anything shows what a presenter bound from the start shows" (rule 2 of "Derived state is built
## from its owner", docs/engine/ARCHITECTURE.md). For every presenter (the original, the debug rectangles, every skin that ships and the
## tiny test skin) the rules are run into the moments where a view that builds itself from the events alone goes wrong: a pellet in
## flight, a dissolve that runs and one that has run out, a launch, a dock and the balloon, the creatures reloaded (the lock opening)
## with ink in flight and during the dock, and a sector loaded in the middle of a dissolve. At each moment a fresh presenter is bound,
## and what it shows is compared with the one bound before the first load: every node's visibility, place and picture, the materials
## (the dissolve and how far it is), the pellets, the station's door and balloon, and the debug rectangles' boxes.
##
## Teaches: a test of a property instead of a case. Nothing here knows what a presenter has inside: `_snapshot` walks whatever nodes it
## made, so a skin added later is held to the same rule without a line of this test changing.

const ORIGINAL_SCENE := "res://src/gameplay/original_presenter.tscn"
## The tick fraction both presenters are shown at before they are compared (between two ticks, where the smoothing matters).
const FRACTION := 0.5


func before_test() -> void:
	GameClock.paused = true
	GameState.reset()
	SkinRoster.mount_mod_skins()


func after_test() -> void:
	GameClock.paused = false
	SkinRoster.release_mod_skins()
	GameState.reset()


# --- the presenters -------------------------------------------------------------------------------------------------------

## Every presenter to hold to the rule, by name: a Callable that makes a new one (not in the tree yet).
func _kinds() -> Dictionary:
	var kinds := {
		"original": func() -> SectorPresenter: return (load(ORIGINAL_SCENE) as PackedScene).instantiate() as SectorPresenter,
		"debug_rects": func() -> SectorPresenter: return DebugRectPresenter.new(),
	}
	var skins := SkinRoster.shipped()
	skins.append(load(SkinRoster.TINY) as GameSkin)                # (the hostile skin scribbles over what it is given: nothing to compare)
	skins.append_array(SkinRoster.mod_skins())                     # (the skin mods: a good one that draws, and one that faults on every frame)
	for skin in skins:
		kinds["skin " + String(skin.id)] = PresenterChoice.make_presenter_for.bind(skin)
	return kinds


## A new presenter of `kind` in the tree, bound to `sim` (inside its skin, as `SectorWorld` does it).
func _bound(kind: Callable, sim: SimWorld) -> SectorPresenter:
	var presenter := auto_free(kind.call()) as SectorPresenter
	presenter.run_in_skin(func() -> void:
		add_child(presenter)
		presenter.bind(sim))
	return presenter


# --- the moments ----------------------------------------------------------------------------------------------------------

## The moments to bind at, by name: a Callable that drives a sim (with a presenter already bound to it) there.
func _moments() -> Dictionary:
	return {
		"a pellet in flight": func(sim: SimWorld) -> void:
			_fly(sim, 0)
			sim.tick(InputSnapshot.firing())
			sim.tick(),
		"a dissolve that runs": func(sim: SimWorld) -> void:
			_fly(sim, 0)
			sim.begin_dissolve()
			sim.advance_dissolve(SimWorld.dissolve_length() / 3),
		"a dissolve that has run out": func(sim: SimWorld) -> void:
			_fly(sim, 0)
			sim.begin_dissolve()
			sim.advance_dissolve(SimWorld.dissolve_length()),
		"a sector loaded during a dissolve": func(sim: SimWorld) -> void:
			_fly(sim, 0)
			sim.begin_dissolve()
			sim.advance_dissolve(SimWorld.dissolve_length() / 2)
			_fly(sim, 0),
		"a launch": func(sim: SimWorld) -> void:
			sim.load_sector(DevCreatures.ARENA, 0)
			sim.start_launch()
			for t in 4:
				sim.tick(),
		"a dock": func(sim: SimWorld) -> void:
			_fly(sim, SimWorld.DOCK_SCREEN)
			sim.start_dock()
			for t in 3:
				sim.tick(),
		"the balloon": func(sim: SimWorld) -> void:
			_fly(sim, SimWorld.DOCK_SCREEN)
			sim.start_dock()
			while not sim.sequence.is_done():
				sim.tick()
			sim.start_balloon()
			for t in 6:
				sim.tick(),
		"a screen with animated decorations, some ticks on": func(sim: SimWorld) -> void:
			sim.load_sector(100, 6)                                 # (the dev pack's sector with decorations in every layer)
			sim.foe_context.rng.seed = 4242
			sim.start_flight(200, 150, 6)
			for t in 5:
				sim.tick(),
		"the creatures reloaded with ink in flight": func(sim: SimWorld) -> void:
			_fly(sim, 0)
			sim.tick(InputSnapshot.firing())
			sim.tick()
			sim.reload_creatures(),
		"the creatures reloaded and the dock begun (the lock opens)": func(sim: SimWorld) -> void:
			_fly(sim, SimWorld.DOCK_SCREEN)
			sim.tick(InputSnapshot.firing())
			sim.reload_creatures()                                  # (`GameFlow.complete_sector`: the creatures, then `EnterSupplyStation`)
			sim.start_dock()
			for t in 2:
				sim.tick(),
	}


## The sector loaded on `screen`, the sub flying where nothing reaches it at once, one tick run.
func _fly(sim: SimWorld, screen: int) -> void:
	sim.load_sector(DevCreatures.ARENA, screen)
	sim.foe_context.rng.seed = 4242
	if screen == SimWorld.DOCK_SCREEN:
		sim.start_flight(400, 200, 6)
	else:
		sim.start_flight(200, 150, 6)
	sim.tick()


# --- the test -------------------------------------------------------------------------------------------------------------

func test_a_presenter_bound_in_the_middle_of_anything_shows_what_one_bound_from_the_start_shows() -> void:
	var kinds := _kinds()
	var moments := _moments()
	var checked := 0
	for kind_name: String in kinds:
		for moment_name: String in moments:
			GameState.reset()
			var sim := SimWorld.new(GameState)
			var first := _bound(kinds[kind_name], sim)
			(moments[moment_name] as Callable).call(sim)
			var late := _bound(kinds[kind_name], sim)
			var shown: Array[String] = []
			for presenter: SectorPresenter in [first, late]:
				presenter.run_in_skin(presenter.show_between_ticks.bind(FRACTION))
				shown.append("\n".join(_snapshot(presenter)))
			assert_str(shown[1]).override_failure_message("%s, bound at %s, shows otherwise than one bound from the start:\n%s" \
					% [kind_name, moment_name, _difference(shown[0], shown[1])]).is_equal(shown[0])
			first.unbind()
			late.unbind()
			sim.abandon_damage()
			checked += 1
	assert_int(checked).is_equal(kinds.size() * moments.size())


## The moments are what they claim to be (else the comparison above proves nothing).
func test_the_moments_hold_what_they_are_named_for() -> void:
	var moments := _moments()
	var sim := SimWorld.new(GameState)
	moments["a pellet in flight"].call(sim)
	assert_int(sim.pellets.size()).is_greater(0)
	sim = SimWorld.new(GameState)
	moments["a dissolve that runs"].call(sim)
	assert_bool(sim.is_dissolving()).is_true()
	assert_int(sim.dissolve_elapsed).is_greater(0)
	sim = SimWorld.new(GameState)
	moments["a dissolve that has run out"].call(sim)
	assert_bool(sim.is_dissolving()).is_false()
	assert_int(sim.dissolve_ticks).is_greater(0)
	for name: String in ["a launch", "a dock", "the balloon", "the creatures reloaded and the dock begun (the lock opens)"]:
		sim = SimWorld.new(GameState)
		moments[name].call(sim)
		assert_object(sim.sequence).override_failure_message(name).is_not_null()
		assert_bool(sim.sequence.is_done()).override_failure_message(name).is_false()
	sim = SimWorld.new(GameState)
	moments["a screen with animated decorations, some ticks on"].call(sim)
	assert_int(sim.sector.screens[sim.screen_index].anim_decos.size()).is_greater(0)
	assert_int(SimView.new(sim).screen_ticks()).is_equal(5)
	sim = SimWorld.new(GameState)
	moments["the creatures reloaded with ink in flight"].call(sim)
	assert_int(sim.pellets.size()).is_greater(0)
	GameState.reset()


# --- what a presenter shows -----------------------------------------------------------------------------------------------

## Every node the presenter made, in tree order, as lines: its place in the tree by child index (made nodes have made-up names),
## its class, and what it shows (a hidden node: only that it is hidden). The ambient bubbles are left out: they are no state of the rules (their own random numbers and the
## clock, `Bubbles`), so two presenters made at different moments differ there by design.
func _snapshot(presenter: SectorPresenter) -> Array[String]:
	var lines: Array[String] = []
	if presenter.has_method(&"boxes"):
		for box: DebugRectPresenter.Box in presenter.call(&"boxes"):
			lines.append("box %s %s %s %s %s" % [box.kind, box.rect, box.color, box.filled, box.label])
	if presenter.has_method(&"drawn"):
		for line: String in presenter.call(&"drawn"):
			lines.append("drawn " + line)
	_walk(presenter, "", lines)
	return lines


func _walk(node: Node, path: String, lines: Array[String]) -> void:
	for child in node.get_children():
		if child is Bubbles:
			continue
		var at := "%s/%d" % [path, child.get_index()]
		if child is CanvasItem and not (child as CanvasItem).visible:
			lines.append("%s %s hidden" % [at, child.get_class()])     # (a hidden node shows nothing, whatever it holds)
			continue
		lines.append("%s %s%s" % [at, child.get_class(), _shows(child)])
		_walk(child, at, lines)


func _shows(node: Node) -> String:
	var parts: Array[String] = []
	if node is CanvasItem:
		parts.append(_material((node as CanvasItem).material))
		parts.append("parent_material=%s" % (node as CanvasItem).use_parent_material)
	if node is Node2D:
		var node_2d := node as Node2D
		parts.append("at=%s rot=%s scale=%s" % [node_2d.position, node_2d.rotation, node_2d.scale])
	if node is Sprite2D:
		var sprite := node as Sprite2D
		parts.append("texture=%s frame=%d flip=%s,%s" % [_texture(sprite.texture), sprite.frame, sprite.flip_h, sprite.flip_v])
	if node is AnimatedSprite2D:
		var animated := node as AnimatedSprite2D
		parts.append("animation=%s frame=%d flip=%s,%s" % [animated.animation, animated.frame, animated.flip_h, animated.flip_v])
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		var cells := layer.get_used_cells()
		cells.sort()
		var tiles: Array[String] = []
		for cell in cells:
			tiles.append("%s:%d:%s" % [cell, layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell)])
		parts.append("cells=%s" % hash(",".join(tiles)))
	return " " + " ".join(parts)


## A material by what decides the picture: its shader, for the dissolve how many passes are drawn, for the shader of a layer (a data skin's) its `phase` and a value it was given.
func _material(material: Material) -> String:
	if material == null:
		return "material=none"
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return "material=%s" % material.get_class()
	return "material=%s code=%d passes=%s phase=%s glint=%s" % [shader_material.shader.resource_path, shader_material.shader.code.hash(), shader_material.get_shader_parameter("passes_done"),
			shader_material.get_shader_parameter("phase"), shader_material.get_shader_parameter("glint")]


func _texture(texture: Texture2D) -> String:
	if texture == null:
		return "none"
	return texture.resource_path if not texture.resource_path.is_empty() else "#%d" % texture.get_instance_id()


## The lines that differ, for the failure message.
func _difference(expected: String, got: String) -> String:
	var want := expected.split("\n")
	var have := got.split("\n")
	var found: Array[String] = []
	for i in maxi(want.size(), have.size()):
		var a := want[i] if i < want.size() else "(nothing)"
		var b := have[i] if i < have.size() else "(nothing)"
		if a != b:
			found.append("  from the start: %s\n  bound late:     %s" % [a, b])
		if found.size() >= 8:
			break
	return "\n".join(found)
