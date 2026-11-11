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
## read through the pack's door, so they are worn only while this skin is: a pack's `pictures/` folder wins under every skin), and its presenter is the original's, so it needs no Sandbox.
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
## picture of `skin/` is not a PNG the engine can decode, a picture the manifest maps is not in the pack. (Null with no reason for a pack that is not a skin.)
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
	skin.assets = ModAssets.make(pack, ModSpec.SKIN_FOLDER, pack.mod.shaders, reasons)
	for key in pack.mod.pictures:
		var texture := pack.texture(pack.mod.pictures[key])
		if texture == null:
			reasons.append("the picture %s of \"%s\" is not in the pack" % [pack.mod.pictures[key], key])
		else:
			skin.pictures[key] = texture
	return skin if reasons.is_empty() else null

