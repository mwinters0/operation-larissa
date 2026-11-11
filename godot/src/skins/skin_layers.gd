class_name SkinLayers
extends RefCounted
## The layers of a screen a skin's script may draw (`script_layers`, `ModLayerHost`), and the first of them a skin may put a shader on: the name a skin says -> the unique name of the layer's node. The ONE list of the names, a class of its own because `ModSpec`
## (read by `Pack`) needs it and may not depend on the presenter or the HUD, which depend on the packs.
## `NODES` are the layers of the original presenter (`original_presenter.tscn`, `OriginalPresenter.layer_node`; `GameSkin.layer_materials` and the `layers` of a skin's manifest dress them); the `currents` and `triggers` of the presenter are debug overlays, not layers a skin dresses.
## The nodes inside a layer have `use_parent_material` set, so the material of a layer is the one every picture in it is drawn with.
## `HUD_NODES` are the parts of the console (`hud.tscn`, `Hud.layer_nodes`): each is the unique names of the nodes the original draws the part with, and a script that draws the part has them made transparent. `HUD` is the whole console: every part at once.
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

## The layers of `NODES` that hold the screen's still decorations, back to front (`SimView.decorations`, `SkinState`'s `decos`).
const DECOS: Array[StringName] = [&"back_decos", &"mid_decos", &"front_decos"]

## The parts of the console a script may draw: the layer's name -> the unique names of the HUD's nodes that are the original's part.
const HUD_NODES: Dictionary[StringName, Array] = {
	&"hud_bezel": ["Bezel"],
	&"hud_tanks": ["Tanks"],
	&"hud_oxygen": ["Oxygen"],
	&"hud_ink": ["Ink"],
	&"hud_game": ["GameLabel"],
	&"hud_custom": ["CustomLabel"],
	&"hud_zone": ["ZoneLabel"],
	&"hud_sector": ["SectorLabel"],
	&"hud_ship": ["ShipLight", "ShipGlow"],
	&"hud_computer": ["ComputerLight", "ComputerGlow"],
}
## The whole console as one layer (every part of `HUD_NODES`).
const HUD := &"hud"


## Is `layer` a layer of the original presenter?
static func is_presenter_layer(layer: StringName) -> bool:
	return NODES.has(layer)


## Is `layer` a layer of the console (a part of it, or the whole, `HUD`)?
static func is_hud_layer(layer: StringName) -> bool:
	return layer == HUD or HUD_NODES.has(layer)


## The names of the console's layers: the whole console first, then each part in the order the HUD draws them.
static func hud_layers() -> Array[StringName]:
	var found: Array[StringName] = [HUD]
	found.append_array(HUD_NODES.keys())
	return found


## The unique names of the HUD's nodes that are the original's `layer` (every part's, for `HUD`).
static func hud_node_names(layer: StringName) -> Array[String]:
	var found: Array[String] = []
	for part: StringName in (HUD_NODES.keys() if layer == HUD else [layer]):
		found.append_array(HUD_NODES[part])
	return found
