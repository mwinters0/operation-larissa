class_name ModSkin
extends GameSkin
## The skin a skin MOD is: an ordinary entry of `SkinChoice` (`--skin=<id>`, F3 then S) whose id is the mod pack's id, that maps only what its manifest says (its `render` and `pictures`; the HUD's layout, the screens and the sounds stay the base game's).
## Its sector is always shown by the original presenter, its console by the original HUD. For a skin with an entry script the presenter and the HUD hand chosen layers to the sandboxed script (`ModLayerHost`): the layers of `script_layers`, one call of `skin_layer` each, or, for a script that
## draws the whole screen (`draws_frame`), every layer at once from one call of `skin_frame`. `ModHost` makes the skin when it loads a mod whose manifest has `skin` (`make`), keeps it while the mod runs
## and lets it go with the mod (`alive` false); `SkinChoice` puts the original skin on again when the one in use stops being alive.
##
## It also holds what the script may name: the shaders the manifest lists, compiled by `ModShader` once, when the mod is loaded. The manifest is judged in one place, `ModParts.make`, which `PackCheck`
## (for the author) and `ModHost` (before the mod runs) both ask.
##
## A DATA skin (a manifest with no `entry`) is the same object with no script: `render` and `pictures` of the manifest become the `GameSkin` fields of the same names (the pictures are the pack's `skin/*.png`
## read through the pack's door, so they are worn only while this skin is: a pack's `pictures/` folder wins under every skin), and its presenter is the original's, so it needs no Sandbox. Its `hud_font` (a `.ttf` of the pack read through the pack's door, `Pack.font`, at its weight, `FontSpec`) with its size and colour is the skin's `GameSkin.hud_labels`, the one field the project's own skins set the HUD's lettering with (`HudLabels`: the boxes keep the layout's sizes); a `hud_font` with no file has no font of its own, and its boxes take the menus' default font. Its `theme` is the skin's `GameSkin.menu_theme` (`SkinTheme`: its font, made the same way, and the colours and styles of the manifest; `ThemeBuilder` puts it on the menus).
##
## Its `layers` are the shaders of the original presenter's layers: each becomes a `ShaderMaterial` of `layer_materials` (`OriginalPresenter` puts a copy on its layer and sets `phase`); a layer the script draws has none (the script names a shader in its draw list).
##
## Teaches: one choice for every skin: a skin from a stranger is a `GameSkin` like the project's own, built by one function from what the pack holds, so everything that wears a skin (the
## presenter, the HUD, the compare tool, the tests) needs no second path, whether it carries code or only data.

## The functions a skin mod defines, called every frame by `ModLayerHost` (`ModSpec.functions` lists them): `skin_layer(name, state, fraction, events)` for each layer of `script_layers`, or `skin_frame(state, fraction, events)` for a script that draws the whole screen.
const LAYER_FUNCTION := "skin_layer"
const FRAME_FUNCTION := "skin_frame"

## The mod pack's id: the skin's id too.
var pack_id: StringName = &""
## What the skin may name: the pictures of `skin/` and the shaders of the manifest, by the path it lists (`ModAssets`).
var assets: ModAssets
## False once the mod that made it is unloaded: `SkinChoice` does not offer it and does not keep it.
var alive := true
## What the script draws: the layers it draws one by one (`ModSpec.script_layers`: layers of the original presenter and parts of the console, `SkinLayers`), or the whole screen of the sector at once (`draws_frame`: `ModSpec.draws_frame`; the console stays the original's). A data skin has neither.
var script_layers: Array[StringName] = []
var draws_frame := false


## Does a script draw anything of this skin (a layer, or the whole screen)?
func is_scripted() -> bool:
	return draws_frame or not script_layers.is_empty()


## The layers of `script_layers` that are the original presenter's (`SkinLayers.NODES`): what `ModLayerHost` of the presenter draws.
func presenter_layers() -> Array[StringName]:
	return script_layers.filter(SkinLayers.is_presenter_layer)


## The layers of `script_layers` that are the console's (`SkinLayers.HUD_NODES`, `SkinLayers.HUD`): what `ModLayerHost` of the HUD draws.
func hud_layers() -> Array[StringName]:
	return script_layers.filter(SkinLayers.is_hud_layer)


## The skin of the mod pack `pack`, or null with every reason in `reasons`: its id is the id of a skin that comes with the game, a shader of the manifest is not what `ModShader` accepts, a
## picture of `skin/` is not a PNG the engine can decode, a picture the manifest maps is not in the pack, the font of `hud_font` is no font the engine can use (`Pack.font_problem`). (Null with no reason for a pack that is not a skin.)
static func make(pack: Pack, reasons: Array[String]) -> ModSkin:
	if pack.mod == null or not pack.mod.is_skin:
		return null
	var skin := ModSkin.new()
	skin.id = pack.id
	skin.pack_id = pack.id
	skin.display_name = pack.title
	skin.script_layers = pack.mod.script_layers.duplicate()
	skin.draws_frame = pack.mod.draws_frame()
	if pack.mod.render != null:
		skin.render = pack.mod.render.duplicate() as RenderSettings
	if pack.id == SkinChoice.ORIGINAL or ResourceLoader.exists(SkinChoice.path_of(pack.id)):
		reasons.append("the pack's id '%s' is the id of a skin that comes with the game; a skin mod needs an id of its own" % pack.id)
	if pack.mod.hud_font != null:
		var problem := _font_problem(pack, pack.mod.hud_font_spec)
		if problem.is_empty():
			skin.hud_labels = pack.mod.hud_font.duplicate() as HudLabels
			skin.hud_labels.font = pack.mod.hud_font_spec.font(pack)
		else:
			reasons.append("the skin's hud_font: %s" % problem)
	if pack.mod.theme != null:
		var problem := _font_problem(pack, pack.mod.theme_font)
		if problem.is_empty():
			skin.menu_theme = pack.mod.theme.duplicate() as SkinTheme
			skin.menu_theme.font = pack.mod.theme_font.font(pack) if pack.mod.theme_font != null else null
		else:
			reasons.append("the skin's theme font: %s" % problem)
	skin.assets = ModAssets.make(pack, ModSpec.SKIN_FOLDER, pack.mod.shaders, reasons)
	if skin.assets != null:
		for layer in pack.mod.layers:
			_make_layer(skin, layer, pack.mod.layers[layer], reasons)
	for key in pack.mod.pictures:
		var texture := pack.texture(pack.mod.pictures[key])
		if texture == null:
			reasons.append("the picture %s of \"%s\" is not in the pack" % [pack.mod.pictures[key], key])
		else:
			skin.pictures[key] = texture
	return skin if reasons.is_empty() else null



## Why the font `spec` names (null: none) is no font the pack can give, "" when it is fine or names no file (`Pack.font_problem`).
static func _font_problem(pack: Pack, spec: FontSpec) -> String:
	return pack.font_problem(spec.file) if spec != null and not spec.file.is_empty() else ""


## The material the layer `layer` of a data skin wears (`GameSkin.layer_materials`): its shader, already compiled for the skin (`ModAssets`), with the values of the manifest in the uniforms the shader declares. A uniform the shader has not,
## or of a kind the value does not fill (`ModShader.check_uniforms`), is a reason: the author is told, the game does not run on a guess. The presenter sets `phase` on the material it wears.
static func _make_layer(skin: ModSkin, layer: String, entry: Dictionary, reasons: Array[String]) -> void:
	var shader := skin.assets.shaders.get(entry["shader"]) as Shader
	if shader == null:
		return                                                   # (`ModAssets.make` said why)
	var material := ShaderMaterial.new()
	material.shader = shader
	var before := reasons.size()
	var values := {}
	for problem in ModShader.check_uniforms(entry["uniforms"], skin.assets.declared[entry["shader"]], values):
		reasons.append("the layer \"%s\" (%s) %s" % [layer, entry["shader"], problem])
	for uniform: String in values:
		material.set_shader_parameter(uniform, values[uniform])
	if reasons.size() == before:
		skin.layer_materials[StringName(layer)] = material
