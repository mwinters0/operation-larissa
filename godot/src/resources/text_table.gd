class_name TextTable
extends Resource
## A set of strings keyed by their original NEP.DLL / ONWIN string id.
##
## Teaches: a Dictionary-backed lookup Resource for game text.

## (Its keys are numbers: how the JSON form of a pack reads them, `ResourceJson`.)
const JSON_INT_KEYS: Array[String] = ["texts"]

@export var texts: Dictionary = {}

## Text for `id`, or an empty string (with a warning) if missing.
func text(id: int) -> String:
	if not texts.has(id):
		push_warning("TextTable: no text with id %d" % id)
		return ""
	return texts[id]

func ids() -> Array:
	var keys := texts.keys()
	keys.sort()
	return keys
