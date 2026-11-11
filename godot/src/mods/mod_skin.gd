class_name ModSkin
extends GameSkin
## The skin a skin MOD is: an ordinary entry of `SkinChoice` (`--skin=<id>`, F3 then S) whose id is the mod pack's id, that maps only what its manifest says (its `render` and `pictures`; the HUD's layout, the screens and the sounds stay the base game's)
## and, for a skin with an entry script, whose presenter scene is `ModPresenter`, which asks the sandboxed script what to draw. `ModHost` makes one when it loads a mod whose manifest has `skin` (`make`), keeps it while the mod runs
## and lets it go with the mod (`alive` false); `SkinChoice` puts the original skin on again when the one in use stops being alive.
##
## It also holds what the script may name: the shaders the manifest lists, compiled by `ModShader` once, when the mod is loaded. The manifest is judged in one place, `ModParts.make`, which `PackCheck`
## (for the author) and `ModHost` (before the mod runs) both ask.
##
## A DATA skin (a manifest with no `entry`) is the same object with no script: `render` and `pictures` of the manifest become the `GameSkin` fields of the same names (the pictures are the pack's `skin/*.png`
## read through the pack's door, so they are worn only while this skin is: a pack's `pictures/` folder wins under every skin), and its presenter is the original's, so it needs no Sandbox. Its `hud_font` (a `.ttf` of the pack read through the pack's door, `Pack.font`) with its size and colour is the skin's `GameSkin.hud_labels`, the one field the project's own skins set the HUD's lettering with (`HudLabels`: the boxes keep the layout's sizes).
##
## Its `layers` are the shaders of the original presenter's layers: each becomes a `ShaderMaterial` of `layer_materials` (`OriginalPresenter` puts a copy on its layer and sets `phase`), which is why a skin with a script has none: its presenter is its own.
##
## Teaches: one choice for every skin: a skin from a stranger is a `GameSkin` like the project's own, built by one function from what the pack holds, so everything that wears a skin (the
## presenter, the HUD, the compare tool, the tests) needs no second path, whether it carries code or only data.

const PRESENTER_SCENE := "res://src/mods/mod_presenter.tscn"
## The function a skin mod defines, called every frame by `ModPresenter` (`ModSpec.functions` lists it).
const FUNCTION := "skin_frame"

## The mod pack's id: the skin's id too.
var pack_id: StringName = &""
## What the skin may name: the pictures of `skin/` and the shaders of the manifest, by the path it lists (`ModAssets`).
var assets: ModAssets
## False once the mod that made it is unloaded: `SkinChoice` does not offer it and does not keep it.
var alive := true


## The skin of the mod pack `pack`, or null with every reason in `reasons`: its id is the id of a skin that comes with the game, a shader of the manifest is not what `ModShader` accepts, a
## picture of `skin/` is not a PNG the engine can decode, a picture the manifest maps is not in the pack, the font of `hud_font` is no font the engine can use (`Pack.font_problem`). (Null with no reason for a pack that is not a skin.)
static func make(pack: Pack, reasons: Array[String]) -> ModSkin:
	if pack.mod == null or not pack.mod.is_skin:
		return null
	var skin := ModSkin.new()
	skin.id = pack.id
	skin.pack_id = pack.id
	skin.display_name = pack.title
	if pack.mod.has_entry():
		skin.presenter_scene = load(PRESENTER_SCENE) as PackedScene
	if pack.mod.render != null:
		skin.render = pack.mod.render.duplicate() as RenderSettings
	if pack.id == SkinChoice.ORIGINAL or ResourceLoader.exists(SkinChoice.path_of(pack.id)):
		reasons.append("the pack's id '%s' is the id of a skin that comes with the game; a skin mod needs an id of its own" % pack.id)
	if pack.mod.hud_font != null:
		var problem := pack.font_problem(pack.mod.hud_font_file)
		if problem.is_empty():
			skin.hud_labels = pack.mod.hud_font.duplicate() as HudLabels
			skin.hud_labels.font = pack.font(pack.mod.hud_font_file)
		else:
			reasons.append("the skin's hud_font: %s" % problem)
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



## The material the layer `layer` of a data skin wears (`GameSkin.layer_materials`): its shader, already compiled for the skin (`ModAssets`), with the values of the manifest in the uniforms the shader declares. A uniform the shader has not,
## or of a kind the value does not fill (`ModShader.uniform_problem`), is a reason: the author is told, the game does not run on a guess.
static func _make_layer(skin: ModSkin, layer: String, entry: Dictionary, reasons: Array[String]) -> void:
	var shader := skin.assets.shaders.get(entry["shader"]) as Shader
	if shader == null:
		return                                                   # (`ModAssets.make` said why)
	var declared := ModShader.uniform_types(shader.code)
	var material := ShaderMaterial.new()
	material.shader = shader
	var before := reasons.size()
	var uniforms: Dictionary = entry["uniforms"]
	for uniform: String in uniforms:
		if not declared.has(uniform):
			reasons.append("the layer \"%s\" sets \"%s\", which %s does not declare (it declares %s)" % [layer, uniform, entry["shader"], ", ".join(declared.keys()) if not declared.is_empty() else "no uniform"])
			continue
		var problem := ModShader.uniform_problem(declared[uniform], uniforms[uniform])
		if problem.is_empty():
			material.set_shader_parameter(uniform, ModShader.uniform_value(declared[uniform], uniforms[uniform]))
		else:
			reasons.append("the layer \"%s\" sets \"%s\", which %s %s" % [layer, uniform, entry["shader"], problem])
	if reasons.size() == before:
		skin.layer_materials[StringName(layer)] = material
