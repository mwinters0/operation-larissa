class_name SkinVandal
extends SectorPresenter
## Test helper: a presenter that does its worst with everything the skin API gives it. Every event's argument and every answer of
## `view` is overwritten, field by field, with nonsense (numbers, flags, places, the nested `Motion`s, rectangles) - and asked for again
## after every tick. If the API had a way to the rules, the game would change; `test_skin_api.gd` and `test_plays_identically.gd`
## check that it does not: the trace is the same as with no presenter at all.
##
## Teaches: why copies make a read-only API. The vandal is not a hacker - it uses only the documented API, like any skin. A skin that
## reaches round the API (`Catalog`, the autoloads, a private `_` field) is outside it; the API's promise is that doing what it
## is for cannot touch a rule.

## How many things were overwritten (a test asserts the vandal really did something).
var scribbles: int = 0


func bind(sim_world: SimWorld) -> void:
	super.bind(sim_world)
	sim = null
	_listen(view.ticked, _on_ticked)
	for event in SimView.EVENTS:
		if event == &"ticked":
			continue
		var event_signal := Signal(view, event)
		var count := _argument_count(event)
		match count:
			0:
				pass
			1:
				_listen(event_signal, func(a: Variant) -> void: _scribble(a))
			_:
				_listen(event_signal, func(a: Variant, b: Variant) -> void:
					_scribble(a)
					_scribble(b))


func _argument_count(event: StringName) -> int:
	for info in view.get_signal_list():
		if info["name"] == event:
			return (info["args"] as Array).size()
	return 0


func _on_ticked() -> void:
	_scribble(view.sub())
	_scribble(view.creatures())
	_scribble(view.pellets())
	_scribble(view.pieces())
	_scribble(view.triggers())
	_scribble(view.sequence())


## Overwrites every script variable of `thing` (and of what it holds), or of every element if it is an array.
func _scribble(thing: Variant) -> void:
	if thing is Array:
		for element in thing:
			_scribble(element)
	elif thing is RefCounted:
		var object := thing as RefCounted
		for property in object.get_property_list():
			if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var name := property["name"] as String
			var value: Variant = object.get(name)
			match typeof(value):
				TYPE_INT:
					object.set(name, -12345)
				TYPE_FLOAT:
					object.set(name, 1.0e9)
				TYPE_BOOL:
					object.set(name, not (value as bool))
				TYPE_VECTOR2:
					object.set(name, Vector2(9999, -9999))
				TYPE_VECTOR2I:
					object.set(name, Vector2i(9999, -9999))
				TYPE_RECT2I:
					object.set(name, Rect2i(1, 2, 3, 4))
				TYPE_OBJECT:
					_scribble(value)
			scribbles += 1
