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

## The console background picture (616 x 72) and its size, written from the picture at import (a layout is data: what a script may draw in is the layout's rectangle, `ConsoleState.rects`, never what a picture happens to be).
@export var bezel: Texture2D
@export var bezel_position: Vector2i = Vector2i.ZERO
@export var bezel_size: Vector2i = Vector2i.ZERO

## The area of each gauge, the rectangle the original redraws when the gauge changes (`DisplayBezel` and the functions after it: the `dirty_rect` of `docs/data/hud_gauges.json`); every slot of the gauge lies inside it.
## Spare oxygen tanks: one icon per slot, full or empty.
@export var tank_positions: PackedVector2Array = PackedVector2Array()
@export var tank_rect: Rect2i = Rect2i()
@export var tank_full: Texture2D
@export var tank_empty: Texture2D

## The oxygen gauge: four cells. With one cell left, the first one shows `oxygen_low` instead.
@export var oxygen_positions: PackedVector2Array = PackedVector2Array()
@export var oxygen_rect: Rect2i = Rect2i()
@export var oxygen_full: Texture2D
@export var oxygen_empty: Texture2D
@export var oxygen_low: Texture2D

## Ink pellets: 21 icons.
@export var ink_positions: PackedVector2Array = PackedVector2Array()
@export var ink_rect: Rect2i = Rect2i()
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

## The two message lights (surface ship, onboard computer): [off, on] pictures each, the same size (written from the pictures at import, like the lettering's).
@export var ship_position: Vector2i = Vector2i.ZERO
@export var ship_textures: Array[Texture2D] = []
@export var ship_size: Vector2i = Vector2i.ZERO
@export var computer_position: Vector2i = Vector2i.ZERO
@export var computer_textures: Array[Texture2D] = []
@export var computer_size: Vector2i = Vector2i.ZERO

## The frame around playfield and console, drawn last: filled rectangles in drawing order.
@export var frame_rects: Array[Rect2i] = []
@export var frame_colors: PackedColorArray = PackedColorArray()


## The area of the console's part `layer` (a key of `SkinLayers.HUD_NODES`), in window pixels: the bezel's rectangle, a gauge's area, a lettering box, a light. The one mapping from a part's name to its numbers in this layout.
func rect_of(layer: StringName) -> Rect2:
	match layer:
		&"hud_bezel":
			return _box(bezel_position, bezel_size)
		&"hud_tanks":
			return Rect2(tank_rect)
		&"hud_oxygen":
			return Rect2(oxygen_rect)
		&"hud_ink":
			return Rect2(ink_rect)
		&"hud_game":
			return _box(game_position, game_size)
		&"hud_custom":
			return _box(custom_position, custom_size)
		&"hud_zone":
			return _box(zone_position, zone_size)
		&"hud_sector":
			return _box(sector_position, sector_size)
		&"hud_ship":
			return _box(ship_position, ship_size)
		&"hud_computer":
			return _box(computer_position, computer_size)
	push_error("HudLayout: no part '%s' (the parts are %s)" % [layer, ", ".join(PackedStringArray(SkinLayers.HUD_NODES.keys()))])
	return Rect2()


static func _box(position: Vector2i, size: Vector2i) -> Rect2:
	return Rect2(Vector2(position), Vector2(size))


## The number of the zone picture a sector shows: the finale zones (5, 6) reuse the last picture.
func zone_picture(zone: int) -> int:
	return clampi(zone, 0, zone_textures.size() - 1)


## Which zone picture a sector shows (`zone_picture`).
func zone_texture(zone: int) -> Texture2D:
	return zone_textures[zone_picture(zone)]


## The number of the picture of a sector, 0 to 2 for First, Second and Third (`place` is the sector's place in its campaign, 0-based: `Campaign.position_of`), -1 for a finale sector (`sector_final_texture`).
func sector_picture(place: int, is_finale: bool) -> int:
	if is_finale:
		return -1
	return maxi(place, 0) % sector_textures.size()


## The picture of a sector (`sector_picture`).
func sector_texture(place: int, is_finale: bool) -> Texture2D:
	var picture := sector_picture(place, is_finale)
	return sector_final_texture if picture < 0 else sector_textures[picture]
