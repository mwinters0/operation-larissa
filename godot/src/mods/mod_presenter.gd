class_name ModPresenter
extends SectorPresenter
## The presenter of a skin MOD (`ModSkin`): it shows the sector by asking the mod's sandboxed script what to draw, and draws that. This is the skin API handed to a stranger's code, so everything
## that crosses is plain data and nothing is granted: each frame the script gets the state (`SkinState.build` of `view`: Dictionaries and numbers, built from the same `SimView` as every
## presenter reads), the tick fraction and the events since its last frame, and returns a draw list (`ModDraw`) that the game checks and draws in `ModLayer` nodes of its own. The script holds
## no node of the game, no texture and no material; it cannot reach the rules, the tree or another mod, and a frame it spoils (an error, a list that is not a list) leaves the last one on.
##
## Timing and rules: the script is called from `show_between_ticks` and `refresh`, which are instant for the rules; it runs under the sandbox's instruction and memory limits, a script that keeps
## faulting is quarantined (`ModLoader`) and then draws nothing, and `SkinChoice` puts the original skin on again. A presenter that draws nothing, or badly, changes nothing about the game
## (`tests/engine/test_skins_dont_change_the_game.gd` plays a good mod skin and a faulty one).
##
## Bound in the middle of anything it shows what one bound from the start shows: the state is rebuilt from `view` on the first frame after any event (`_dirty`), never patched; only the `events`
## list depends on what the presenter heard, and a script builds what it shows from the state (the skin API's rule 5).
##
## Teaches: the same contract as every presenter, with a sandbox in the middle: bind, listen, rebuild from the owner's state when anything changed, and draw. And a read-only edge made of values.

## What shows where the script draws nothing: the sea's dark blue, the debug presenter's backdrop.
const BACKDROP := Color(0.04, 0.06, 0.12)

var _mod_skin: ModSkin
var _fraction := 1.0
## The state last built, and whether an event came since (`_dirty`): the next frame builds it again.
var _state: Dictionary = {}
var _dirty := true
## The events heard since the script's last frame (`SkinState.event`).
var _events: Array = []
var _drawn: ModDraw.Drawn
var _layers: Array[ModLayer] = []


func bind(sim_world: SimWorld) -> void:
	super.bind(sim_world)
	_mod_skin = (skin if skin != null else SkinChoice.current()) as ModSkin
	for event_name in SimView.EVENTS:
		_listen(Signal(view, event_name), func(...args: Array) -> void: _heard(event_name, args))
	refresh()


func unbind() -> void:
	super.unbind()
	_clear()
	_state = {}
	_events = []
	_dirty = true
	queue_redraw()


func refresh() -> void:
	_dirty = true
	_show(_fraction)


func show_between_ticks(fraction: float) -> void:
	_fraction = fraction
	_show(fraction)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(TileGrid.PLAYFIELD_SIZE)), BACKDROP)


## What is on screen, as lines (the layers and their commands, a picture by its file): for a test that compares what two presenters show.
func drawn() -> Array[String]:
	var lines: Array[String] = []
	if _drawn == null:
		return lines
	for layer in _drawn.layers:
		lines.append("layer shader=%s uniforms=%s" % [layer.shader, layer.uniforms])
		for command: Array in layer.commands:
			lines.append(ModDraw.describe(command))
	return lines


func _heard(event_name: StringName, args: Array) -> void:
	_dirty = true
	_events.append(SkinState.event(event_name, args))
	if _events.size() > SkinState.MAX_EVENTS:
		_events.pop_front()


## One frame: ask the script what to draw (the state is built again first if anything happened) and show the checked answer.
func _show(fraction: float) -> void:
	if view == null:
		return
	var node := ModHost.mod(_mod_skin.pack_id, false) if _mod_skin != null and _mod_skin.alive else null
	if node == null or ModHost.is_quarantined(_mod_skin.pack_id) or view.sector_index < 0:
		_apply(ModDraw.Drawn.new())
		return
	if _dirty:
		_state = SkinState.build(view)
		_dirty = false
	var events := _events
	_events = []
	var answer := ModLoader.call_mod(node, ModSkin.FUNCTION, [_state, fraction, events])
	if not answer["ok"]:                       # (a fault: the frame went wrong, the last one stays on)
		return
	var drawn_now := ModDraw.validate(answer["value"], Packs.pack(_mod_skin.pack_id), _mod_skin.assets)
	if drawn_now != null:                      # (not a list: likewise)
		_apply(drawn_now)


## Makes the layers nodes show `drawn`.
func _apply(drawn_now: ModDraw.Drawn) -> void:
	_drawn = drawn_now
	while _layers.size() < drawn_now.layers.size():
		var layer := ModLayer.new()
		layer.name = "Layer%d" % _layers.size()
		add_child(layer)
		_layers.append(layer)
	while _layers.size() > drawn_now.layers.size():
		_remove_layer(_layers.pop_back())
	for i in drawn_now.layers.size():
		var wanted := drawn_now.layers[i]
		_layers[i].show_layer(wanted, _mod_skin.assets.shaders.get(wanted.shader) if _mod_skin != null and _mod_skin.assets != null else null)


func _clear() -> void:
	_drawn = null
	while not _layers.is_empty():
		_remove_layer(_layers.pop_back())


func _remove_layer(layer: ModLayer) -> void:
	remove_child(layer)
	layer.queue_free()
