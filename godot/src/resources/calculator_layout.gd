class_name CalculatorLayout
extends Resource
## The original's calculator: its pictures, where every key is, and how the display is drawn.
## Filled by the importer from the decompiled `GetAnswer` / `AddHotspot` / display routines
## (`tools/analysis/data/console_layout.json`).
##
## Teaches: hit areas as data. The original registered one rectangle per key ("hotspot"); the Godot
## calculator creates one transparent `Button` per rectangle on top of the picture, so the key faces
## stay exactly as the artists drew them.
##
## Positions are pixels of the 640 x 400 window.

## The calculator picture (292 x 130) and where it goes.
@export var picture: Texture2D
@export var picture_position: Vector2i = Vector2i.ZERO
## The sizes of the two pictures, written by the importer from the picture files, so that the widgets take their size from DATA
## and not from whichever texture is loaded (a skin with other pictures cannot move a key or the display).
@export var picture_size: Vector2i = Vector2i.ZERO
## The "Ans:" picture shown instead when the calculator is off (296 x 40).
@export var answer_panel: Texture2D
@export var answer_position: Vector2i = Vector2i.ZERO
@export var answer_size: Vector2i = Vector2i.ZERO

## One entry per key: its calculator key ("0"-"9", ".", "+", "-", "*", "/", "=", "F", "N", "S", "R", "C",
## "Enter") and its rectangle in window pixels.
@export var key_names: PackedStringArray = PackedStringArray()
@export var key_rects: Array[Rect2i] = []

## The LCD display. `display_origin` is the (x0, y0) of the original's routine; the digits are drawn
## right to left starting `digits_right` pixels to the right of x0, `advance` pixels apart.
@export var display_origin_calculator: Vector2i = Vector2i.ZERO
@export var display_origin_answer: Vector2i = Vector2i.ZERO
@export var display_clear_rect: Rect2i = Rect2i()       # relative to the origin: the black field
@export var digits_right: int = 0
@export var digit_y: int = 0
@export var advance: int = 16
@export var point_offset: Vector2i = Vector2i.ZERO
@export var fraction_flag_offset: Vector2i = Vector2i.ZERO
## Where the pending operator and the memory marker are drawn (window pixels, calculator only).
@export var operator_position: Vector2i = Vector2i.ZERO
@export var memory_position: Vector2i = Vector2i.ZERO

## The green LCD pictures: digits 0-9, decimal point, fraction slash, minus, fraction flag "F", memory "M".
@export var digit_textures: Array[Texture2D] = []
@export var point_texture: Texture2D
@export var slash_texture: Texture2D
@export var minus_texture: Texture2D
@export var fraction_flag_texture: Texture2D
@export var memory_texture: Texture2D
## The sizes of those pictures (digits 0-9 in order), for the rectangle each glyph covers.
@export var digit_sizes: Array[Vector2i] = []
@export var point_size: Vector2i = Vector2i.ZERO
@export var slash_size: Vector2i = Vector2i.ZERO
@export var minus_size: Vector2i = Vector2i.ZERO
## Pending operator markers, keyed by the operator character "+", "-", "*", "/".
@export var operator_textures: Dictionary = {}


## The rectangle of key `name` relative to `origin` (a node's position), or an empty Rect2i.
func key_rect(name: String) -> Rect2i:
	var i := key_names.find(name)
	return key_rects[i] if i >= 0 else Rect2i()
