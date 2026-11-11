class_name ModLayerHost
extends RefCounted
## What a screen does for a skin mod whose script draws layers (`ModSkin.script_layers`, or the whole sector screen, `draws_frame`): for each layer the script draws, a `ModLayerStack` stands right behind that layer's nodes, and the nodes are made transparent while the
## script's answer is on. Every other layer stays the original's, so the screen is ONE screen, whatever a mod does of it: a mod that draws every layer is this host with every name, and a script that draws the whole sector (`skin_frame`) is one slot that stands over every
## layer of the presenter and hides them all. There are two screens with layers, the sector (`OriginalPresenter`, `SkinLayers.NODES`) and the console (`Hud`, `SkinLayers.HUD_NODES`), and ONE host serves both: what differs is the `Site` it stands on (where the layers' nodes are, the
## rectangle a layer's picture is cut to, the state the script is told), and `make` / `make_hud` make the host with the site of each. A skin that draws layers of both has two hosts, one for each screen, and the script is asked for each layer once a frame by the host of its screen.
##
## Each frame the script is called once for each slot, with the state (the site's: `SkinState.build` of the presenter's `view` or `ConsoleState.build` of the HUD, plain data, built again after any event or, for the console, every frame, never patched), the tick fraction and the events since
## the last frame (the same list for every slot of a frame; the console hears none, its state is all there is), and the game checks the answer (`ModDraw.validate`) and shows it in the slot's stack. THE FAULT POLICY is a layer at a time: a call that faults or answers what is not a list leaves
## that slot's last good answer on, and a slot that has never had one shows the original's layer; a mod that is gone, quarantined (`ModLoader`) or a site with nothing to say (a presenter with no sector) shows the original's layers again, and `SkinChoice` puts the original skin on when the mod is
## quarantined. The script holds no node, no texture and no material; what it draws changes nothing about the game (`tests/engine/test_skins_dont_change_the_game.gd`, `test_plays_identically.gd`), and bound in the middle of anything the host shows what one bound from the start shows
## (`test_presenter_binds_late.gd`, `test_mod_skin_hud.gd`): the state is rebuilt from the owner, only the `events` list depends on what the presenter heard, and a script builds what it shows from the state (the skin API's rule 5).
##
## Teaches: one host for every mod that draws a part of a screen: the part is named by a layer, the original is the fallback of every part, and "hide the original" is a derived fact (has the script answered?), never a flag to keep in step.

## What a host stands on: the places of one screen. `parent` is the node the stacks are children of, `nodes_of(layer)` the original's nodes of a layer (`Array[CanvasItem]`, in the order they are drawn: the stack stands behind the last one and all of them are made transparent while the
## script's answer is on), `clip_of(layer)` the rectangle a layer's picture is cut to (an invalid Callable: not cut), `state()` the state the script is told (empty: there is nothing to show yet), `in_skin(action)` runs `action` as the screen's skin (a picture named by key is
## the one this screen's skin shows), `phase(fraction)` the game's time the shaders of the stacks are given (`ModShader.PHASE_UNIFORM`: the sector's `SectorPresenter.game_phase`, the console's `Hud.game_phase`), and `fresh` says the state is built again every frame (else after an event or `refresh`).
class Site:
	extends RefCounted
	var parent: Node
	var nodes_of: Callable
	var clip_of: Callable
	var state: Callable
	var in_skin: Callable
	var phase: Callable
	var fresh := false

## What a slot is: the draw list of the script for one place in the screen. `after` is the layer whose nodes the stack follows ("" = the end of the screen), `hides` the layers' nodes the answer replaces, `key` what the script is told (a layer's name). `root` is what stands in the tree: the stack, or,
## where the layer has a rectangle, the `Control` that cuts the stack to it (`clip`).
class Slot:
	extends RefCounted
	var key: StringName = &""
	var after: StringName = &""
	var hides: Array[StringName] = []
	var stack := ModLayerStack.new()
	var root: Node
	var clip: Control
	var answered := false

var _site: Site
var _skin: ModSkin
var _slots: Array[Slot] = []
## The state last built, and whether an event came since (`_dirty`): the next frame builds it again. The events heard since the last frame.
var _state: Dictionary = {}
var _dirty := true
var _events: Array = []
var _fraction := 1.0


## The host of `presenter` dressed in `worn`, or null when `worn` is no skin mod whose script draws anything of the presenter.
static func make(presenter: OriginalPresenter, worn: GameSkin) -> ModLayerHost:
	var mod_skin := worn as ModSkin
	if mod_skin == null or not mod_skin.is_scripted():
		return null
	var site := Site.new()
	site.parent = presenter
	site.nodes_of = func(layer: StringName) -> Array[CanvasItem]: return [presenter.layer_node(layer)]
	site.state = func() -> Dictionary: return SkinState.build(presenter.view) if presenter.view != null and presenter.view.sector_index >= 0 else {}      # (the original's layers stay until a sector is shown)
	site.in_skin = presenter.run_in_skin
	site.phase = presenter.game_phase
	var host := ModLayerHost.new()
	host._site = site
	host._skin = mod_skin
	if mod_skin.draws_frame:
		var everything: Array[StringName] = []
		everything.assign(SkinLayers.NODES.keys())
		host._add_slot(&"", &"", everything)
	else:
		for layer in mod_skin.presenter_layers():
			host._add_slot(layer, layer, [layer] as Array[StringName])
	return host._placed()


## The host of `hud` dressed in `worn`, or null when `worn` is no skin mod whose script draws a layer of the console. The layers are asked for by name, `Hud` hides the original's nodes of a layer while the script's answer is on, and what the script draws in a part is cut to the part's rectangle
## (`ConsoleState.rects`). The state is built again every frame (`ConsoleState.build`: a few gauges and four words, with the phases of the HUD's own animations), so there is no copy of it to go stale.
static func make_hud(hud: Hud, worn: GameSkin) -> ModLayerHost:
	var mod_skin := worn as ModSkin
	if mod_skin == null or mod_skin.hud_layers().is_empty():
		return null
	var site := Site.new()
	site.parent = hud
	site.nodes_of = hud.layer_nodes
	site.clip_of = hud.layer_clip
	site.state = hud.console_state
	site.in_skin = hud.run_in_skin
	site.phase = hud.game_phase
	site.fresh = true
	var host := ModLayerHost.new()
	host._site = site
	host._skin = mod_skin
	for layer in mod_skin.hud_layers():
		host._add_slot(layer, layer, [layer] as Array[StringName])
	return host._placed()


func _placed() -> ModLayerHost:
	if _slots.is_empty():
		return null
	place()
	return self


func _add_slot(key: StringName, after: StringName, hides: Array[StringName]) -> void:
	var slot := Slot.new()
	slot.key = key
	slot.after = after
	slot.hides = hides
	slot.stack.name = "Mod%s" % String(key).capitalize().replace(" ", "") if key != &"" else "ModFrame"
	slot.root = slot.stack
	if _site.clip_of.is_valid():
		slot.clip = Control.new()
		slot.clip.name = slot.stack.name + "Clip"
		slot.clip.clip_contents = true
		slot.clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.clip.add_child(slot.stack)
		slot.root = slot.clip
	_site.parent.add_child(slot.root)
	_slots.append(slot)


## The screen lets the mod go: the stacks are freed and every layer is the original's again.
func end() -> void:
	for slot in _slots:
		slot.answered = false
		_dress(slot)
		_site.parent.remove_child(slot.root)
		slot.root.queue_free()
	_slots.clear()


## The presenter heard the event `event_name` of the rules: the script is told of it on the next frame, and the state is built again.
func heard(event_name: StringName, args: Array) -> void:
	_dirty = true
	_events.append(SkinState.event(event_name, args))
	if _events.size() > SkinState.MAX_EVENTS:
		_events.pop_front()


## The whole state again, as if every event had just happened.
func refresh() -> void:
	_dirty = true
	show(_fraction)


## Puts each stack right behind the last node of its layer (the presenter orders its layers by what is happening, `OriginalPresenter._arrange`): the one place the stacks are ordered.
func place() -> void:
	for slot in _slots:
		var behind: int = _site.parent.get_child_count() - 1
		if slot.after != &"":
			var node := _nodes(slot.after).back() as Node
			behind = node.get_index() + (0 if slot.root.get_index() < node.get_index() else 1)
		_site.parent.move_child(slot.root, behind)
		_fit(slot)


## One frame: ask the script what each slot draws (the state is built again first if anything happened) and show the checked answers.
func show(fraction: float) -> void:
	_fraction = fraction
	var node := ModHost.mod(_skin.pack_id, false) if _skin.alive else null
	if node == null or ModHost.is_quarantined(_skin.pack_id):
		_forget()
		return
	if _dirty or _site.fresh:
		_state = _site.state.call()
		_dirty = _state.is_empty()
	if _state.is_empty():                          # (nothing to show yet: a presenter with no sector)
		_forget()
		return
	var events := _events
	_events = []
	var pack := Packs.pack(_skin.pack_id)
	for slot in _slots:
		_fit(slot)
		var arguments: Array = [_state, fraction, events]
		if not _skin.draws_frame:
			arguments.push_front(String(slot.key))
		var answer := ModLoader.call_mod(node, ModSkin.FRAME_FUNCTION if _skin.draws_frame else ModSkin.LAYER_FUNCTION, arguments)
		if not answer["ok"]:                       # (a fault: the frame went wrong, the last answer stays, or the original's layer if there is none)
			continue
		var checked: Variant = answer["value"]
		var drawn := _site.in_skin.call(func() -> ModDraw.Drawn: return ModDraw.validate(checked, pack, _skin.assets)) as ModDraw.Drawn      # (a picture named by key is the one this screen's skin shows)
		if drawn != null:                          # (not a list: likewise)
			slot.stack.set_phase(_site.phase.call(fraction))
			slot.stack.show_drawn(drawn, _skin.assets)
			slot.answered = true
			_dress(slot)


## The script cannot be asked (the mod is gone or quarantined, no sector): every layer is the original's.
func _forget() -> void:
	for slot in _slots:
		slot.stack.clear()
		slot.answered = false
		_dress(slot)


## The layers of `slot` are the original's unless the script has answered for them: derived from `answered` each time, so no step leaves a layer hidden for a script that is not there. The nodes are made transparent, not invisible: the original's own code
## keeps deciding when its layer is `visible` (the sub, the station, a light), and keeps running.
func _dress(slot: Slot) -> void:
	for layer in slot.hides:
		for node in _nodes(layer):
			node.modulate = Color(1, 1, 1, 0) if slot.answered else Color.WHITE


## The rectangle of a slot's layer, asked of the site each time (a layout that changed moves it): the clip stands there and the stack inside it is shifted back, so the script draws in the screen's own pixels.
func _fit(slot: Slot) -> void:
	if slot.clip == null:
		return
	var area: Rect2 = _site.clip_of.call(slot.key)
	slot.clip.position = area.position
	slot.clip.size = area.size
	slot.stack.position = -area.position


func _nodes(layer: StringName) -> Array[CanvasItem]:
	var found: Array[CanvasItem] = []
	found.assign(_site.nodes_of.call(layer))
	return found


## The layers the script has answered for, by name (for a test).
func answered_layers() -> Array[StringName]:
	var found: Array[StringName] = []
	for slot in _slots:
		if slot.answered:
			found.append_array(slot.hides)
	return found


## What the stacks show, as lines: for a test that compares what two presenters show.
func lines() -> Array[String]:
	var found: Array[String] = []
	for slot in _slots:
		found.append("slot %s" % slot.key)
		found.append_array(slot.stack.lines())
	return found


## The `ModLayer` nodes of every stack, in the order of the slots (for a test).
func layers() -> Array[ModLayer]:
	var found: Array[ModLayer] = []
	for slot in _slots:
		found.append_array(slot.stack.layers())
	return found
