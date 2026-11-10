@tool
class_name ZoneData
extends Resource
## Per-zone art and defaults. zones.tres holds 7 of these: 5 zones plus the
## two finale "zones" (Voyager 5, Expert 6), which reuse zone 4's floor and decos.

@export var index: int = 0
@export var title: String = ""
## Which of the 5 art zones supplies floor tiles and decos (0-4).
@export var tile_zone: int = 0
## Source id of this zone's atlas inside neptune_tileset.tres (== tile_zone).
@export var tile_source_id: int = 0
## Number of zone-specific decos (slots 70 .. 70 + deco_count - 1).
@export var deco_count: int = 0
## Number of zone-specific foe sprites (slots 35 .. 35 + foe_count - 1).
@export var foe_count: int = 0
## Name banner shown on the map / HUD (may be null for finales).
@export var banner_texture: Texture2D
## Default educational level (0-3) when the player did not customise.
@export var default_edu_level_voyager: int = 0
@export var default_edu_level_expert: int = 0
