class_name DebugHud
extends Label
## A text read-out of the player's air, ink and pieces for the debug scenes (toggle with F3).
## The real console is `Hud`; this stays as a cross-check that the numbers agree.
##
## Teaches: a view that OBSERVES a model. It never asks `GameState` for numbers
## in `_process`; it redraws its text only when a signal says something changed.

func _ready() -> void:
	GameState.oxygen_changed.connect(_on_oxygen_changed)
	GameState.ink_changed.connect(_on_ink_changed)
	GameState.piece_collected.connect(func(_index: int) -> void: _show(GameState.tanks(), GameState.oxygen(), GameState.ink))
	_show(GameState.tanks(), GameState.oxygen(), GameState.ink)


func _on_oxygen_changed(tanks: int, oxygen: int) -> void:
	_show(tanks, oxygen, GameState.ink)


func _on_ink_changed(pellets: int) -> void:
	_show(GameState.tanks(), GameState.oxygen(), pellets)


func _show(tanks: int, oxygen: int, pellets: int) -> void:
	text = "Spare tanks %d   Pieces %d\nOxygen %s%s\nInk pellets %d" % [
		tanks, GameState.pieces_collected(), "#".repeat(oxygen), ".".repeat(GameState.tuning.max_oxygen - oxygen), pellets]
