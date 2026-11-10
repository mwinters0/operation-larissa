class_name ExpertClosingCable
extends Control
## The chain the crane lets down in the Expert closing: a hook at the bottom, then pieces stacked upwards for as
## far as the picture reaches. Original: `ExpertClosingDrawCable` (0x41cc8d) draws it from the hook up,
## `ExpertClosingEraseCable` (0x41cbac) restores the background behind it, both once per step.
##
## Teaches: a composite built from one repeated rule. The original loops "draw a piece, move up by its height"; here the
## same rule places ordinary `Sprite2D` children once, and a single property (`bottom`) moves the whole chain, so an
## `AnimationPlayer` track can animate it. The control clips its children (`clip_contents`) the way the original clips the
## drawing at `ExpertClosingCableTop`: the chain is cut at the top edge of this control.
##
## The pieces, from the bottom: piece 0 is the hook (pictures 2018-2020, 40 x 26, x 220), pieces 1-3 are chain links
## (2013, 8 x 12, x 236), piece 4 is the ball (2014, 28 x 22, x 228), every further piece is a link again.

## Window pixels: the top-left corner of the playfield. Positions of this class are in window pixels.
const PLAYFIELD_ORIGIN := Vector2(16, 32)
const HOOK_PICTURES: Array[StringName] = [&"crane_hook_0", &"crane_hook_1", &"crane_hook_2"]     # open, closing, closed
const LINK_PICTURE := &"crane_link"
const BALL_PICTURE := &"crane_ball"
const HOOK_X := 220
const BALL_X := 228
const LINK_X := 236
const BALL_PIECE := 4
## The chain is built this long; whatever sticks out above the control is clipped.
const REACH := 300

## y of the last pixel row of the hook (the original's `ExpertClosingCableBottom`).
@export var bottom: int = 0:
	set(value):
		bottom = value
		_place()
## 0 open, 1 closing, 2 closed (`ExpertClosingHookFrame`).
@export_range(0, 2) var hook_frame: int = 0:
	set(value):
		hook_frame = value
		_show_hook_frame()

## The pictures of the pieces from the hook up (`ui_picture` names) and their top edge relative to `bottom`.
var piece_pictures: Array[StringName] = []
var piece_tops := PackedInt32Array()
var pieces: Array[Sprite2D] = []
var _chain: Node2D


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chain = Node2D.new()
	_chain.name = "Chain"
	_chain.position = -position                # the pieces are placed in playfield coordinates
	add_child(_chain)
	var covered := 0
	var index := 0
	while covered < REACH:
		var picture := _picture_of_piece(index)
		var texture := Assets.ui_picture(picture)
		var piece := Sprite2D.new()
		piece.name = "Piece%d" % index
		piece.centered = false
		piece.texture = texture
		_chain.add_child(piece)
		pieces.append(piece)
		piece_pictures.append(picture)
		piece_tops.append(-(covered + texture.get_height() - 1))
		covered += texture.get_height()
		index += 1
	_show_hook_frame()
	_place()


func _picture_of_piece(index: int) -> StringName:
	if index == 0:
		return HOOK_PICTURES[hook_frame]
	return BALL_PICTURE if index == BALL_PIECE else LINK_PICTURE


func _show_hook_frame() -> void:
	if not pieces.is_empty():
		pieces[0].texture = Assets.ui_picture(HOOK_PICTURES[hook_frame])


func _place() -> void:
	for i in pieces.size():
		var x := HOOK_X if i == 0 else (BALL_X if i == BALL_PIECE else LINK_X)
		pieces[i].position = Vector2(x, bottom + piece_tops[i]) - PLAYFIELD_ORIGIN
