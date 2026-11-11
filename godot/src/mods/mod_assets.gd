class_name ModAssets
extends RefCounted
## What a mod's draw list may name from its own pack: the pictures under one folder of the pack (`skin/` for a skin, `problems/` for the screens of problem types) and the shaders the manifest lists for it, compiled once
## by `ModShader` when the mod is loaded. A mod never holds a picture or a shader; `ModDraw` looks a name up here and in the pack, and `ModLayer` draws with the `Shader`. One class for both kinds of mod: the
## draw list is checked the same way for a skin and for a problem screen.
##
## Teaches: a capability made of names, not objects: the script says "skin/glow.gdshader", the game holds the one shader that name stands for, and a name the manifest did not list is nothing.

## The folder of the pack the pictures and shaders are in (`ModSpec.SKIN_FOLDER`, `ModSpec.PROBLEM_FOLDER`).
var folder := ""
## The shaders of the manifest, by the path it lists: path -> Shader.
var shaders: Dictionary[String, Shader] = {}
## The uniforms each of those shaders declares, by the same path: path -> (name -> type, `ModShader.uniform_types`). Read once, with the text, so that judging a draw list's uniforms every frame reads no text.
var declared: Dictionary[String, Dictionary] = {}


## The assets of `pack` under `folder` with the shaders `listed`, or null with every reason in `reasons`: a shader that is not what `ModShader` accepts, a picture of the folder that is not a PNG the engine can decode.
static func make(pack: Pack, folder_name: String, listed: Array[String], reasons: Array[String]) -> ModAssets:
	var assets := ModAssets.new()
	assets.folder = folder_name
	var before := reasons.size()
	for rel in listed:
		var shader := ModShader.make(pack, rel, folder_name, reasons)
		if shader != null:
			assets.shaders[rel] = shader
			assets.declared[rel] = ModShader.uniform_types(shader.code)
	for rel in pack.all_files():
		if rel.begins_with(folder_name) and rel.get_extension() == "png" and pack.texture(rel) == null:
			reasons.append("%s is not a PNG picture the engine can decode" % rel)
	return assets if reasons.size() == before else null
