class_name CalculatorPanel
extends Control
## What the calculator and the "Ans:" box have in common: one of the original's pictures, stretched to the rectangle a `CalculatorLayout` gives it, with an `LcdDisplay` drawn on it. Both are dressed by one function each
## (`Calculator._dress`, `AnswerBox._dress`: `_ready` and a skin put on in the middle of a problem both call it) and this class is the part of it that is the same: where the panel stands, its picture, its size and the display's.
##
## Teaches: a base class for the shared steps of a builder, so two screens that dress alike cannot drift apart.

## The layout the scene was given (else the pack's, `_load_layout`).
@export var layout: CalculatorLayout

## The pack's layout (or the one the scene was given): what the skin's version is made from, again and again.
var _scene_layout: CalculatorLayout

@onready var picture: TextureRect = %Picture
@onready var display: LcdDisplay = %Display


## The pack's layout, or the one the scene was given: the layout `_dress` starts from.
func _load_layout() -> void:
	_scene_layout = layout if layout != null else Catalog.pack_resource("data/ui/calculator_layout.tres") as CalculatorLayout       # (the pack's; the skin in use may show another)


## Puts the panel at `at` with `texture` stretched to `panel_size` and the display on it (the display's layout is `layout`, in use now): the size is the layout's data, not the texture's that happens to be loaded, so a skin's picture of another size moves nothing.
func _dress_panel(at: Vector2i, texture: Texture2D, panel_size: Vector2i, display_origin: Vector2i) -> void:
	position = Vector2(at)
	picture.texture = texture
	picture.size = Vector2(panel_size)
	size = Vector2(panel_size)
	custom_minimum_size = size
	display.layout = layout
	display.frame_origin = at
	display.origin = display_origin
