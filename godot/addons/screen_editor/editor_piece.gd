@tool
class_name ScreenEditorPiece
extends ScreenEditorItem
## A capsule piece or the data canister lying on this screen (`PieceData` of the SECTOR, not of the screen).
##
## Teaches: an editor node that stands for data living in ANOTHER file. The piece list belongs to `sector_NN.tres`
## (the original keeps it in the sector header, not in a screen record), so saving a screen with a moved piece also
## rewrites those lines of the sector file. The node therefore keeps the piece's number: pieces are numbered in the
## sector (piece 0 is the data canister) and the game remembers which ones the player holds BY NUMBER. A piece is added or
## removed with its marker (Ctrl+D, Delete, or "Add piece" on the `ScreenEditor`): that calls `SectorData.add_piece` /
## `remove_piece`, which refuse what would break the numbering (the data canister can go only when it is alone) and then the
## marker comes back. The marker keeps the record it stands for (`record`), because the numbers after a removed piece move up.
##
## "Move to screen" changes `PieceData.screen`. When it differs from the screen you are editing the piece will have left
## this screen after saving; it stays visible (dimmed) until the screen is reloaded.

## Position in the sector's piece list (0 = the data canister). Read only; the `ScreenEditor` keeps it right.
@export var piece_index: int = 0
## The first piece of every sector is the data canister, every other piece is a rock. Read only.
@export var is_canister: bool = false
## Which of the sector's 12 screens the piece lies on. Change it to move the piece to another screen.
@export_range(0, 11) var move_to_screen: int = 0:
	set(value):
		move_to_screen = value
		modulate = Color.WHITE if _on_this_screen() else Color(1, 1, 1, 0.4)
		queue_redraw()
		_edited()


## The piece of `SectorData.pieces` this marker stands for; null for a marker nobody has added to the sector yet (a duplicate).
var record: PieceData = null


func _init() -> void:
	super()
	grid = Vector2i(2, 2)                 # the original stores piece positions as words / 2


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == &"piece_index" or property.name == &"is_canister":
		property.usage |= PROPERTY_USAGE_READ_ONLY


func show_picture() -> void:
	if sprite_frames != null:
		frame = 3 if is_canister else 0          # the pieces bundle: 0 rock, 3 red canister (DESIGN 4.1)


func _on_this_screen() -> bool:
	var editor := ScreenEditor.find_for(self)
	return editor == null or editor.screen == move_to_screen


func _draw() -> void:
	if not _on_this_screen():
		draw_string(ThemeDB.fallback_font, Vector2(0, -4), "-> screen %d" % move_to_screen, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.8, 0.3))


func to_record() -> PieceData:
	var record := PieceData.new()
	record.screen = move_to_screen
	record.pos = pixel_position()
	record.is_canister = is_canister
	return record


static func from_record(record: PieceData, index: int) -> ScreenEditorPiece:
	var node := ScreenEditorPiece.new()
	node.record = record
	node.piece_index = index
	node.is_canister = record.is_canister
	node.move_to_screen = record.screen
	node.position = Vector2(record.pos)
	node.name = marker_name(record.is_canister, index)
	return node


## "Canister" or "Piece 3": the name of the marker of piece number `index`.
static func marker_name(canister: bool, index: int) -> String:
	return "Canister" if canister else "Piece %d" % index


## What keeps the piece from being stored; empty when it fits.
static func problems_of(pos: Vector2i, what: String) -> Array[String]:
	var found: Array[String] = []
	if pos.x < 0 or pos.x > 65534 or pos.y < 0 or pos.y > 65534:
		found.append("%s at %s: the original stores x / 2 and y / 2 as 16-bit numbers, so 0 to 65534" % [what, pos])
	if pos.x % 2 != 0 or pos.y % 2 != 0:
		found.append("%s at %s is not on the grid: the original stores x / 2 and y / 2, so both must be even" % [what, pos])
	return found


func _get_configuration_warnings() -> PackedStringArray:
	var found := _common_warnings()
	for message in problems_of(pixel_position(), "piece %d" % piece_index):
		found.append(message)
	return found
