class_name ModLayerStack
extends Node2D
## The nodes that show ONE draw list of a mod (`ModDraw.Drawn`): as many `ModLayer` as the list has layers, each given its commands and its shader whenever the list changes. A mod's skin layer (`ModLayerHost`) and a mod's
## problem screen (`ModDiagram`) each keep one; the list is already checked, so nothing here asks whether it may. The nodes are the game's: the mod's script never holds them.
##
## Teaches: one owner for "a list becomes nodes": a node that grows and shrinks its children to match a list, so a caller only says what to show and never how many nodes that takes.

var _layers: Array[ModLayer] = []
var _drawn: ModDraw.Drawn
var _phase := 0.0


## Shows `drawn`: one `ModLayer` for each of its layers, with the compiled shader of `assets` the layer names.
func show_drawn(drawn: ModDraw.Drawn, assets: ModAssets) -> void:
	_drawn = drawn
	while _layers.size() < drawn.layers.size():
		var layer := ModLayer.new()
		layer.name = "Layer%d" % _layers.size()
		layer.set_phase(_phase)
		add_child(layer)
		_layers.append(layer)
	while _layers.size() > drawn.layers.size():
		_remove(_layers.pop_back())
	for i in drawn.layers.size():
		var wanted := drawn.layers[i]
		_layers[i].show_layer(wanted, assets.shaders.get(wanted.shader) if assets != null else null)


## The game's time for the shaders of every layer (`ModShader.PHASE_UNIFORM`): the screen that shows the list tells it each time it shows, a mod never does.
func set_phase(phase: float) -> void:
	_phase = phase
	for layer in _layers:
		layer.set_phase(phase)


## Shows nothing: no node is left.
func clear() -> void:
	_drawn = null
	while not _layers.is_empty():
		_remove(_layers.pop_back())


## The layer nodes, back to front.
func layers() -> Array[ModLayer]:
	return _layers


## What the nodes show, as lines (the layers and their commands, a picture by its file): for a test that compares what two things show.
func lines() -> Array[String]:
	var found: Array[String] = []
	if _drawn == null:
		return found
	for layer in _drawn.layers:
		found.append("layer shader=%s uniforms=%s" % [layer.shader, layer.uniforms])
		for command: Array in layer.commands:
			found.append(ModDraw.describe(command))
	return found


func _remove(layer: ModLayer) -> void:
	remove_child(layer)
	layer.queue_free()
