class_name CreaturesPresenter
extends OriginalPresenter
## The presenter of the "creatures" skin: the original look for everything, and two species of creature drawn in new ways -
## the rainbow fish by an `AnimationTree` (`RainbowFishRig`) and the puffer fish as a 3D model in a `SubViewport` (`PufferRig3D`).
##
## HOW IT IS BUILT. It extends `OriginalPresenter` (its scene is the original's scene with this script on it) and adds one layer of rigs
## above the original's creatures. Everything it adds is written against the skin API (`docs/create/SKIN_API.md`) and uses `view` and nothing
## else of the rules: where a creature is (`CreatureState.motion`, `Motion.at(fraction)`), what it shows (`picture`, `mirrored`), what
## happened to it (`creature_picture_changed`, `creature_mirror_changed`, `creature_hit_by_ink`). `tests/engine/test_skin_creatures.gd` reads
## this folder's source and fails if a script here names `sim` or a rule object. (The base class keeps `sim` for the built-in presenters;
## the part that is inherited uses it, the part written here never does.)
##
## WHICH CREATURES. A creature belongs to a species if its picture is one of the species' pictures (`CreatureSpecies`); it gets a rig the
## first time it shows one. A creature the skin does not know stays the original's, and so does a rig's creature while it shows a picture
## the rig leaves to the original (a puffer fish that has been hit by ink is the original's ink cloud). The original's picture of a
## creature that has a rig is hidden (`Foe.sprite`); the rig is drawn in the same place, inside the same picture rectangle.
##
## Teaches: extending a presenter instead of rewriting it (a skin changes what it wants to change), listening to the events of the skin
## API, and the order in which things arrive: the skin API's events come before the original's own handlers, so this node never counts on
## the original's `foes` being built when an event arrives; it hides the original's pictures every frame instead (`_hide_replaced`).

## The rigs by the creature's number in the sector.
var _rigs := {}
var _layer: Node2D


func bind(sim_world: SimWorld) -> void:
	super.bind(sim_world)
	if _layer == null:
		_layer = Node2D.new()
		_layer.name = "Rigs"
		add_child(_layer)
		move_child(_layer, foes_layer.get_index() + 1)       # (the rigs are drawn over the original's creatures)
	_listen(view.sector_loaded, func(_sector: int) -> void: _clear_rigs())
	_listen(view.creature_picture_changed, _on_picture_changed)
	_listen(view.creature_mirror_changed, func(creature: SimView.CreatureState, mirrored: bool) -> void:
		if _rigs.has(creature.index):
			_rigs[creature.index].show_mirror(mirrored))
	_listen(view.creature_visibility_changed, func(creature: SimView.CreatureState, shown: bool) -> void:
		if _rigs.has(creature.index):
			_rigs[creature.index].show_visible(shown))
	_listen(view.creature_hit_by_ink, func(creature: SimView.CreatureState) -> void:
		if _rigs.has(creature.index):
			_rigs[creature.index].hit_by_ink())
	_listen(view.ticked, _on_view_ticked)
	refresh()


## Shows every creature as it is now (a skin switched in the middle of a sector, a tool that moved things).
func refresh() -> void:
	super.refresh()
	if view == null:
		return
	for creature in view.creatures():
		_adopt(creature)
		if _rigs.has(creature.index):
			_rigs[creature.index].follow(creature)
	_hide_replaced()


func show_between_ticks(fraction: float) -> void:
	super.show_between_ticks(fraction)
	for rig: CreatureRig in _rigs.values():
		rig.show_between_ticks(fraction)
	_hide_replaced()


## The rig that draws creature number `index` (null: the original draws it), and how many rigs there are. For the tests and tools.
func rig_for(index: int) -> CreatureRig:
	return _rigs.get(index)


func rig_count() -> int:
	return _rigs.size()


# --- the events ----------------------------------------------------------------------------------------

func _on_picture_changed(creature: SimView.CreatureState, picture: int) -> void:
	_adopt(creature)
	if _rigs.has(creature.index):
		_rigs[creature.index].show_picture(picture)


## After every tick the rigs are told where their creatures are going.
func _on_view_ticked() -> void:
	for index: int in _rigs:
		_rigs[index].follow(view.creature(index))


# --- the rigs ------------------------------------------------------------------------------------------

## Makes a rig for `creature` if it shows a picture of a species this skin draws and has none yet.
func _adopt(creature: SimView.CreatureState) -> void:
	if _rigs.has(creature.index):
		return
	var rig: CreatureRig
	match CreatureSpecies.of_picture(view.zone, creature.picture):
		CreatureSpecies.RAINBOW_FISH:
			rig = RainbowFishRig.new()
		CreatureSpecies.PUFFER:
			rig = PufferRig3D.new()
		_:
			return
	_rigs[creature.index] = rig
	_layer.add_child(rig)                              # (in the tree first: a rig builds its nodes in `setup`)
	rig.setup(creature, Catalog.foes_frames(view.zone), view.zone)


func _clear_rigs() -> void:
	for rig: CreatureRig in _rigs.values():
		_layer.remove_child(rig)
		rig.queue_free()
	_rigs.clear()


## The original's picture of a creature is hidden while its rig draws it, and back when the rig leaves the picture to the original.
func _hide_replaced() -> void:
	for index: int in _rigs:
		if index < foes.size():
			foes[index].sprite.visible = not _rigs[index].is_drawing()
