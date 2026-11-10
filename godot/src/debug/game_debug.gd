class_name GameDebug
extends CanvasLayer
## Cheat keys and a read-out for the running game. F3 shows or hides them.
##
## Teaches: keeping debugging tools OUT of the game's own script. `Game` knows nothing about this node;
## it is a child scene that finds its parent, and in an exported release build `OS.is_debug_build()` is false,
## so it deletes itself and no cheat can reach a player. (Run from the editor, or with a debug export, it is
## there.) The row of piece boxes (`PieceCounter`) is part of it, not of the real HUD: the original console
## has no piece read-out.
##
##   F3   show / hide this overlay (text read-out, row of piece boxes, key list) and switch the keys on
##   1 lose a point of oxygen        2 gain one (Zoom's tank)       3 take the next missing piece (as the rules do when the sub
##                                                                      touches it: the canister also starts its problem)
##   4 refill the ink                5 message light: none > ship > computer
##   6 open a problem (slot 2)       7 toggle "Cust" on the console
##   8 jump to the finale sector     9 raise the finale semaphore bit (fly to the finale screen to end the game)
##   0 finish this sector as if the lock were solved
##   R swap the original look for the debug rectangles (`DebugRectPresenter`) and back: the game goes on as it was
##   O lay the debug rectangles over the picture (a skin being authored: does it cover what the rules test?) and take them off
##   S put on the next skin (`SkinChoice.after`: original > every other folder of res://skins/ > original); the game goes on as it was

@onready var game: Game = get_parent() as Game
@onready var readout: Label = %DebugHud
@onready var keys: Label = %DebugKeys
@onready var pieces: PieceCounter = %Pieces


func _ready() -> void:
	if not OS.is_debug_build() or game == null:
		queue_free()
		return
	readout.visible = false
	keys.visible = false
	pieces.visible = false
	GameState.pieces_changed.connect(_on_pieces_changed)
	_on_pieces_changed()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_overlay"):
		readout.visible = not readout.visible
		keys.visible = readout.visible
		pieces.visible = readout.visible
	elif keys.visible and not game.messages.is_open() and event is InputEventKey and event.pressed and not event.echo:
		_press((event as InputEventKey).keycode)


func _on_pieces_changed() -> void:
	pieces.show_pieces(GameState.piece_total, GameState.pieces_mask)


func _press(keycode: Key) -> void:
	var world := game.world
	match keycode:
		KEY_1:
			GameState.update_oxygen(-1)
		KEY_2:
			GameState.update_oxygen(1)
		KEY_3:
			_take_next_piece()
		KEY_4:
			GameState.refill_ink()
		KEY_5:
			# none -> ship -> computer -> none
			GameState.set_message_light(not GameState.ship_light and not GameState.computer_light, GameState.ship_light)
		KEY_6:
			_open_problem(2)
		KEY_7:
			GameState.customized = not GameState.customized
		KEY_8:
			_jump_to_finale()
		KEY_9:
			world.foe_context.semaphore |= 1 << SimWorld.FINALE_SEMAPHORE_BIT
		KEY_0:
			game.complete_sector()
		KEY_R:
			world.toggle_presenter()
		KEY_O:
			world.toggle_overlay()
		KEY_S:
			var next := SkinChoice.after(SkinChoice.current().id)
			SkinChoice.select_id(next)
			print("GameDebug: skin '%s'" % next)


## Takes the first piece that is not collected yet THROUGH THE RULES (`SimWorld.take_piece`), so the run, the rules' list of pieces and
## the picture agree: the sound plays, the midpoint is checked, the piece leaves the screen it lies on, and the canister starts its
## problem. The rules refuse while the sub is not under control or a problem is open, and then nothing happens.
func _take_next_piece() -> void:
	var sim := game.world.sim
	for i in sim.sector.pieces.size():
		if not GameState.has_piece(i):
			sim.take_piece(i)
			return


## Opens the problem of trigger slot `slot` THROUGH THE RULES' entry, the one a trigger's countdown opens its problem with
## (`SimWorld.open_problem`): a problem that was waiting is taken over, the countdown stops, the beacon and the console's lights go
## out and the flow is asked for the problem. Nothing while a problem is open (the entry refuses it).
func _open_problem(slot: int) -> void:
	game.world.sim.open_problem(slot)


## Starts the finale sector of this game (30 for Voyager, 31 for Expert), as if the last ordinary sector were done: the entries of
## `GameFlow.complete_sector` that start the next sector, without the dock and the balloon. The run's half of a new sector
## (`GameState.begin_sector`: nothing collected, the midpoint forgotten, a new life), the player's progress (the source the sector and
## the level are read from), then `GameFlow.begin_sector` (the level, the song, the rules' half and the launch).
func _jump_to_finale() -> void:
	var finales := game.profile.campaign().finales
	if finales.is_empty():
		print("GameDebug: this campaign has no finale")
		return
	GameState.begin_sector()
	game.profile.progress = finales[0] * 2
	game.begin_sector(game.profile.sector(), false)
