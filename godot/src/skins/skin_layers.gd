class_name SkinLayers
extends RefCounted
## The layers of the original presenter a skin may put a shader on (`GameSkin.layer_materials`; the `layers` of a data skin's manifest, `ModSpec`): the name a skin says -> the unique name of the layer's node in
## `original_presenter.tscn` (`OriginalPresenter.layer_node`). The ONE list of the names, a class of its own because `ModSpec` (read by `Pack`) needs it and may not depend on the presenter, which depends on the packs.
## The `currents` and `triggers` of the presenter are debug overlays, not layers a skin dresses. The nodes inside a layer have `use_parent_material` set, so the material of a layer is the one every picture in it is drawn with.
##
## Teaches: a list of names in a file of its own, so that the code that checks a manifest and the code that draws agree without one having to load the other.

const NODES: Dictionary[StringName, String] = {
	&"background": "Background",
	&"back_decos": "BackDecos",
	&"walls": "Walls",
	&"station": "Station",
	&"mid_decos": "MidDecos",
	&"collectibles": "Collectibles",
	&"sub": "Sub",
	&"foes": "Foes",
	&"pellets": "Pellets",
	&"front_decos": "FrontDecos",
	&"anim_decos": "AnimDecos",
	&"bubbles": "Bubbles",
}
