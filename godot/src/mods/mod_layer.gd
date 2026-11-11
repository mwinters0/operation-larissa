class_name ModLayer
extends Node2D
## One layer of a mod's picture: a node that draws the commands of a `ModDraw.Layer` (already checked, so nothing here asks whether it may), through the layer's shader when it has one. A `ModLayerStack` keeps as many as a
## mod's list has layers (a skin's layer, `ModLayerHost`; a problem screen, `ModDiagram`) and gives each its commands whenever the list changes. The node is the game's: the mod's script never holds it.
##
## Teaches: immediate-mode drawing on a retained canvas: `_draw` replays a list of commands, `queue_redraw` asks for it again, and a `ShaderMaterial` is the only thing a layer needs to look different.

## The commands being shown (`ModDraw` forms).
var commands: Array = []
var _shader: Shader
var _material: ShaderMaterial
var _phase := 0.0


## Shows `layer` from now on: its commands, and its shader with its uniforms (the material is kept while the shader stays the same).
func show_layer(layer: ModDraw.Layer, shader: Shader) -> void:
	commands = layer.commands
	if shader != _shader:
		_shader = shader
		_material = null
		if shader != null:
			_material = ShaderMaterial.new()
			_material.shader = shader
			_material.set_shader_parameter(ModShader.PHASE_UNIFORM, _phase)
		material = _material
	if _material != null:
		for key: String in layer.uniforms:
			_material.set_shader_parameter(key, layer.uniforms[key])
	queue_redraw()


## The font of every text a mod draws: the default font of the theme in use (the project Theme: the engine's font, or the one the skin worn gives its `theme`, `ThemeBuilder.apply`), the font the menus' controls and the problem screen's title and prompt are lettered in. A mod names none.
## The diagrams' own text is not this font: it is always the engine's (`ThemeBuilder.engine_font`), because the data puts each of its words at a pixel.
static func theme_font() -> Font:
	var project_theme := ThemeDB.get_project_theme()
	if project_theme != null and project_theme.has_default_font():
		return project_theme.default_font
	return ThemeDB.fallback_font


## The game's time for the layer's shader (`ModShader.PHASE_UNIFORM`), from now on: the one place a mod's shader gets its `phase`, whoever shows the layer.
func set_phase(phase: float) -> void:
	_phase = phase
	if _material != null:
		_material.set_shader_parameter(ModShader.PHASE_UNIFORM, phase)


func _draw() -> void:
	for command: Array in commands:
		match command[0]:
			"rect":
				draw_rect(command[1], command[2])
			"line":
				draw_line(command[1], command[2], command[3], command[4])
			"picture":
				var texture: Texture2D = command[1]
				var where: Variant = command[2]
				var area := Rect2(where, texture.get_size()) if where is Vector2 else where as Rect2
				draw_texture_rect(texture, _flipped(area, command[3]), false, command[4])
			"region":
				draw_texture_rect_region(command[1], _flipped(command[2], command[4]), command[3], command[5])
			"text":
				var font := theme_font()
				draw_string(font, command[2] + Vector2(0.0, font.get_ascent(command[3])), command[1], command[6], command[5], command[3], command[4])


## `area`, mirrored left to right when `mirrored` (a negative width flips the picture).
static func _flipped(area: Rect2, mirrored: bool) -> Rect2:
	return Rect2(area.position + Vector2(area.size.x, 0.0), Vector2(-area.size.x, area.size.y)) if mirrored else area
