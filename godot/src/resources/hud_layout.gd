class_name HudLayout
extends Resource
## Where everything of the sub console (the "bezel") goes on the 640 x 400 screen, and which
## pictures it uses. Filled by the importer from the decompiled `DisplayBezel` family of
## functions (`docs/data/hud_gauges.json` + `console_layout.json`), so no number is typed in a script.
##
## Teaches: a settings Resource as the ONE place for positions ("data, not code"). `Hud` and its
## tests read this file and nothing else; to move a gauge you change the generator, not the HUD.
##
## All positions are pixels of the 640 x 400 window, as in the original.

## The playfield window (where `SectorWorld` is placed).
@export var playfield: Rect2i = Rect2i()

## The console background picture (616 x 72).
@export var bezel: Texture2D
@export var bezel_position: Vector2i = Vector2i.ZERO

## Spare oxygen tanks: one icon per slot, full or empty.
@export var tank_positions: PackedVector2Array = PackedVector2Array()
@export var tank_full: Texture2D
@export var tank_empty: Texture2D

## The oxygen gauge: four cells. With one cell left, the first one shows `oxygen_low` instead.
@export var oxygen_positions: PackedVector2Array = PackedVector2Array()
@export var oxygen_full: Texture2D
@export var oxygen_empty: Texture2D
@export var oxygen_low: Texture2D

## Ink pellets: 21 icons.
@export var ink_positions: PackedVector2Array = PackedVector2Array()
@export var ink_full: Texture2D
@export var ink_empty: Texture2D

## "Game" label: [Voyager, Expert]; `custom_texture` (the word "Cust") is added for customised games.
@export var game_position: Vector2i = Vector2i.ZERO
@export var game_textures: Array[Texture2D] = []
@export var custom_position: Vector2i = Vector2i.ZERO
@export var custom_texture: Texture2D
## The boxes of the four lettering labels (all the pictures of one label are the same size). The HUD puts a skin's TEXT in exactly this
## rectangle, so another font cannot move or resize anything (`HudLabels`); the importer writes them from the pictures.
@export var game_size: Vector2i = Vector2i.ZERO
@export var custom_size: Vector2i = Vector2i.ZERO

## "Zone" label: one picture per zone (the finale sectors reuse the last one).
@export var zone_position: Vector2i = Vector2i.ZERO
@export var zone_textures: Array[Texture2D] = []
@export var zone_size: Vector2i = Vector2i.ZERO

## "Sector" label: First / Second / Third, and "Final" for a finale sector (the campaign says which: `Campaign.is_finale`).
@export var sector_position: Vector2i = Vector2i.ZERO
@export var sector_textures: Array[Texture2D] = []
@export var sector_final_texture: Texture2D
@export var sector_size: Vector2i = Vector2i.ZERO

## The two message lights (surface ship, onboard computer): [off, on] pictures each.
@export var ship_position: Vector2i = Vector2i.ZERO
@export var ship_textures: Array[Texture2D] = []
@export var computer_position: Vector2i = Vector2i.ZERO
@export var computer_textures: Array[Texture2D] = []

## The frame around playfield and console, drawn last: filled rectangles in drawing order.
@export var frame_rects: Array[Rect2i] = []
@export var frame_colors: PackedColorArray = PackedColorArray()


## Which zone picture a sector shows: the finale zones (5, 6) reuse the last picture.
func zone_texture(zone: int) -> Texture2D:
	return zone_textures[clampi(zone, 0, zone_textures.size() - 1)]


## "First", "Second" or "Third" for the sectors to play (`place` is the sector's place in its campaign, 0-based: `Campaign.position_of`), "Final"
## for a finale sector.
func sector_texture(place: int, is_finale: bool) -> Texture2D:
	if is_finale:
		return sector_final_texture
	return sector_textures[maxi(place, 0) % sector_textures.size()]
