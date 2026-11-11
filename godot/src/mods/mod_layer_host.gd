class_name ModLayerHost
extends RefCounted
## What the original presenter does for a skin mod whose script draws layers (`ModSkin.script_layers`, or the whole screen, `draws_frame`): for each layer the script draws, a `ModLayerStack` stands right behind that layer's node in the presenter, and the layer's own node is
## made transparent while the script's answer is on. Every other layer stays the original's, so the presenter is ONE presenter, whatever a mod does of it: a mod that draws every layer is this host with every name, and a script that draws the whole screen
## (`skin_frame`) is one slot that stands over everything and hides every layer.
##
## Each frame the script is called once for each slot, with the state (`SkinState.build` of the presenter's `view`: plain data, built again after any event, never patched), the tick fraction and the events since the last frame (the same list for every slot of
## a frame), and the game checks the answer (`ModDraw.validate`) and shows it in the slot's stack. THE FAULT POLICY is a layer at a time: a call that faults or answers what is not a list leaves that slot's last good answer on, and a slot that has never had one
## shows the original's layer; a mod that is gone, quarantined (`ModLoader`) or a presenter with no sector shows the original's layers again, and `SkinChoice` puts the original skin on when the mod is quarantined. The script holds no node, no texture and no material; what it
## draws changes nothing about the game (`tests/engine/test_skins_dont_change_the_game.gd`, `test_plays_identically.gd`), and bound in the middle of anything the host shows what one bound from the start shows (`test_presenter_binds_late.gd`): the state is rebuilt from `view`, only the
## `events` list depends on what the presenter heard, and a script builds what it shows from the state (the skin API's rule 5).
##
## Teaches: one host for every mod that draws a part of a screen: the part is named by a layer, the original is the fallback of every part, and "hide the original" is a derived fact (has the script answered?), never a flag to keep in step.

## What a slot is: the draw list of the script for one place in the presenter. `after` is the layer whose node the stack follows ("" = the end of the presenter), `hides` the layers' nodes the answer replaces, `key` what the script is told (a layer's name).
class Slot:
	extends RefCounted
	var key: StringName = &""
	var after: StringName = &""
	var hides: Array[StringName] = []
	var stack := ModLayerStack.new()
	var answered := false

var _presenter: OriginalPresenter
var _skin: ModSkin
var _slots: Array[Slot] = []
## The state last built, and whether an event came since (`_dirty`): the next frame builds it again. The events heard since the last frame.
var _state: Dictionary = {}
var _dirty := true
var _events: Array = []
var _fraction := 1.0


## The host of `presenter` dressed in `worn`, or null when `worn` is no skin mod whose script draws anything.
static func make(presenter: OriginalPresenter, worn: GameSkin) -> ModLayerHost:
	var mod_skin := worn as ModSkin
	if mod_skin == null or not mod_skin.is_scripted():
		return null
	var host := ModLayerHost.new()
	host._presenter = presenter
	host._skin = mod_skin
	if mod_skin.draws_frame:
		var everything: Array[StringName] = []
		everything.assign(SkinLayers.NODES.keys())
		host._add_slot(&"", &"", everything)
	else:
		for layer in mod_skin.script_layers:
			var hidden: Array[StringName] = [layer]
			host._add_slot(layer, layer, hidden)
	host.place()
	return host


func _add_slot(key: StringName, after: StringName, hides: Array[StringName]) -> void:
	var slot := Slot.new()
	slot.key = key
	slot.after = after
	slot.hides = hides
	slot.stack.name = "Mod%s" % String(key).capitalize().replace(" ", "") if key != &"" else "ModFrame"
	_presenter.add_child(slot.stack)
	_slots.append(slot)


## The presenter lets the mod go: the stacks are freed and every layer is the original's again.
func end() -> void:
	for slot in _slots:
		slot.answered = false
		_dress(slot)
		_presenter.remove_child(slot.stack)
		slot.stack.queue_free()
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


## Puts each stack right behind the node of its layer (the presenter orders its layers by what is happening, `OriginalPresenter._arrange`): the one place the stacks are ordered.
func place() -> void:
	for slot in _slots:
		var behind := _presenter.get_child_count() - 1
		if slot.after != &"":
			var node := _presenter.layer_node(slot.after)
			behind = node.get_index() + (0 if slot.stack.get_index() < node.get_index() else 1)
		_presenter.move_child(slot.stack, behind)


## One frame: ask the script what each slot draws (the state is built again first if anything happened) and show the checked answers.
func show(fraction: float) -> void:
	_fraction = fraction
	var view := _presenter.view
	if view == null:
		return
	var node := ModHost.mod(_skin.pack_id, false) if _skin.alive else null
	if node == null or ModHost.is_quarantined(_skin.pack_id) or view.sector_index < 0:
		_forget()
		return
	if _dirty:
		_state = SkinState.build(view)
		_dirty = false
	var events := _events
	_events = []
	var pack := Packs.pack(_skin.pack_id)
	for slot in _slots:
		var arguments: Array = [_state, fraction, events]
		if not _skin.draws_frame:
			arguments.push_front(String(slot.key))
		var answer := ModLoader.call_mod(node, ModSkin.FRAME_FUNCTION if _skin.draws_frame else ModSkin.LAYER_FUNCTION, arguments)
		if not answer["ok"]:                       # (a fault: the frame went wrong, the last answer stays, or the original's layer if there is none)
			continue
		var checked: Variant = answer["value"]
		var drawn := _presenter.run_in_skin(func() -> ModDraw.Drawn: return ModDraw.validate(checked, pack, _skin.assets)) as ModDraw.Drawn      # (a picture named by key is the one this presenter's skin shows)
		if drawn != null:                          # (not a list: likewise)
			slot.stack.show_drawn(drawn, _skin.assets)
			slot.answered = true
			_dress(slot)


## The script cannot be asked (the mod is gone or quarantined, no sector): every layer is the original's.
func _forget() -> void:
	for slot in _slots:
		slot.stack.clear()
		slot.answered = false
		_dress(slot)


## The layers of `slot` are the original's unless the script has answered for them: derived from `answered` each time, so no step leaves a layer hidden for a script that is not there. The node is made transparent, not invisible: the original's own code
## keeps deciding when its layer is `visible` (the sub, the station), and keeps running.
func _dress(slot: Slot) -> void:
	for layer in slot.hides:
		_presenter.layer_node(layer).modulate = Color(1, 1, 1, 0) if slot.answered else Color.WHITE


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
