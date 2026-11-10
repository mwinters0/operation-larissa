extends Node2D
## Smoke test scene: draws one screen of one sector from the generated data.
##
## Teaches: how the generated Resources fit together (SectorData -> ScreenData ->
## TileSet / SpriteFrames). This is a bare preview; the game's playfield is
## `SectorWorld`. Keys: Left/Right = previous/next screen, PageUp/PageDown = sector.

@export var sector_index: int = 0
@export var screen_index: int = 3

const PLAYFIELD_OFFSET := Vector2(16, 32)   # where the 608x288 playfield sits in the 640x400 window
const FLOOR_ATLAS_COLUMNS := 8
const CURRENTS_SOURCE := 5

var _world := Node2D.new()
var _label := Label.new()


func _ready() -> void:
	_world.position = PLAYFIELD_OFFSET
	add_child(_world)
	_label.position = Vector2(4, 4)
	add_child(_label)
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var key := (event as InputEventKey).keycode
	match key:
		KEY_RIGHT:
			screen_index = (screen_index + 1) % Catalog.SCREENS_PER_SECTOR
		KEY_LEFT:
			screen_index = (screen_index + Catalog.SCREENS_PER_SECTOR - 1) % Catalog.SCREENS_PER_SECTOR
		KEY_PAGEUP:
			sector_index = Catalog.step_sector(sector_index, -1)
		KEY_PAGEDOWN:
			sector_index = Catalog.step_sector(sector_index, 1)
		_:
			return
	_build()


func _build() -> void:
	for child in _world.get_children():
		child.queue_free()
	var sector := Catalog.sector(sector_index)
	var screen := sector.screens[screen_index]
	var zone := Catalog.zone(sector.zone)
	_label.text = "sector %d screen %d  zone %s" % [sector_index, screen_index, zone.title]

	# Draw order = node order (docs/engine/ARCHITECTURE.md): background, back decos, tiles, mid decos, foes, front decos.
	var bg := Sprite2D.new()
	bg.centered = false
	var bg_path := Assets.background_path(sector_index, screen_index)
	if Packs.exists_at(bg_path):
		bg.texture = Packs.file_at(bg_path) as Texture2D
	_world.add_child(bg)

	_add_decos(screen.bg_decos, Catalog.decos_frames(sector.zone))
	_world.add_child(_build_tiles(screen, zone))
	_add_decos(screen.mid_decos, Catalog.decos_frames(sector.zone))
	_add_foes(sector)
	_add_decos(screen.fg_decos, Catalog.decos_frames(sector.zone))


func _build_tiles(screen: ScreenData, zone: ZoneData) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = Catalog.tileset()
	for i in screen.tiles.size():
		var byte := screen.tiles[i]
		var cell := Vector2i(i % ScreenData.TILE_COLUMNS, floori(i / float(ScreenData.TILE_COLUMNS)))
		if byte & 0x40:
			var picture := byte & 0x3F
			if picture > 0:   # picture 0 is an invisible wall: collision only, nothing to draw
				layer.set_cell(cell, zone.tile_source_id, Vector2i(picture % FLOOR_ATLAS_COLUMNS, floori(picture / float(FLOOR_ATLAS_COLUMNS))))
		elif byte & 0x80:
			layer.set_cell(cell, CURRENTS_SOURCE, Vector2i(byte & 7, (byte & 0x38) >> 3))
	return layer


func _add_decos(placements: Array[DecoPlacement], frames: SpriteFrames) -> void:
	for placement in placements:
		_world.add_child(_make_sprite(frames, placement.slot, placement.pos, false))


func _add_foes(sector: SectorData) -> void:
	var frames := Catalog.foes_frames(sector.zone)
	for foe in sector.foes:
		if foe.screen == screen_index and not foe.hidden:
			_world.add_child(_make_sprite(frames, foe.frame, foe.pos, foe.flip))


func _make_sprite(frames: SpriteFrames, frame: int, pos: Vector2i, flip: bool) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = &"all"       # the indexed set: frame number == slot number
	sprite.frame = frame
	sprite.centered = false
	sprite.flip_h = flip
	sprite.position = Vector2(pos)
	return sprite
