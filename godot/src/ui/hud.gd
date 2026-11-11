class_name Hud
extends Control
## The sub console around the playfield: spare tanks, oxygen cells, ink pellets, the
## Game / Zone / Sector lettering and the ship and computer message lights. (The original has no
## piece read-out, so neither does this; the F3 debug overlay shows one, see `PieceCounter`.)
##
## Teaches: a view that OBSERVES a model. `Hud` never asks `GameState` for numbers in
## `_process`; it connects to the signals once in `_ready` and each handler touches only the
## nodes that change, and what it puts there is what `ConsoleState` says (the same part of it a script would be told: what the
## gauges hold, the low-air warning, each label's picture and word, the lights). Where things go is not in this file: `HudLayout` (generated from the
## decompiled `DisplayBezel`) holds every position and picture. The blinking is done by an
## `AnimationPlayer`, not by timers in code.
##
## SKINS. The scene holds the original's layout; the HUD shows the layout of the skin in use (`Catalog.skinned`: the skin's own
## pictures in it, or its own layout) and shows it AGAIN when the skin changes (`SkinChoice.events.changed`). The zone, sector and game
## words are pictures of text; a skin with `HudLabels` gets them as `Label` nodes with its own font, put in the very rectangle the
## picture had (`HudLayout.game_size` ...), so a font that is larger or smaller moves and resizes nothing.
##
## A SKIN MOD may draw the console: its script is asked for the parts it names (`SkinLayers.HUD_NODES`, or the whole console, `SkinLayers.HUD`) once a frame by a `ModLayerHost` made for this HUD (the host the original presenter's layers use, with the HUD's ground: `layer_nodes`,
## `layer_clip`, `console_state`), told `console_state` (what the HUD itself shows, `ConsoleState`, built again every frame from `GameState`, with the places of the HUD's two animations in their cycles). What it draws is cut to the part's rectangle and the original's nodes of
## the part are transparent while it answers; the HUD's own handlers go on, so a script that faults leaves the original's part on show. A HUD with no such skin does nothing in `_process`.
##
## The scene covers the whole 640 x 400 window and ignores the mouse. The playfield sits
## ABOVE it at (16, 32) (`Game` puts the HUD before the world): the original paints the frame first and then the
## playfield, whose left column covers the last pixel of the frame's 5 px wide black strip (x 12-16).

## A message light just went on. The HUD plays the original's sound `message_light` for it (`_on_message_light_changed`).
signal light_switched_on

const SFX_MESSAGE_LIGHT := &"message_light"

## The layout in use. A scene or a test may set one; otherwise `_ready` takes the pack's. `_ready` and a change of skin replace it with the skin's version of that.
@export var layout: HudLayout

@onready var bezel: TextureRect = %Bezel
@onready var tanks: IconGauge = %Tanks
@onready var oxygen: IconGauge = %Oxygen
@onready var ink: IconGauge = %Ink
## The four lettering labels. Each is a `TextureRect` that is the label's BOX (its rectangle is the layout's, with a picture or with
## text) and has a `Label` child for the skin that shows the words as text (`*_text`, hidden while the picture is shown).
@onready var game_label: TextureRect = %GameLabel
@onready var custom_label: TextureRect = %CustomLabel
@onready var zone_label: TextureRect = %ZoneLabel
@onready var sector_label: TextureRect = %SectorLabel
@onready var game_text: Label = %GameText
@onready var custom_text: Label = %CustomText
@onready var zone_text: Label = %ZoneText
@onready var sector_text: Label = %SectorText
@onready var ship_light: TextureRect = %ShipLight
@onready var ship_glow: TextureRect = %ShipGlow
@onready var computer_light: TextureRect = %ComputerLight
@onready var computer_glow: TextureRect = %ComputerGlow
@onready var frame: ConsoleFrame = %Frame
## Two players because one AnimationPlayer plays one animation at a time and the two effects overlap.
@onready var air_animations: AnimationPlayer = %AirAnimations
@onready var light_animations: AnimationPlayer = %LightAnimations


## The skin this HUD is dressed in, or null: the skin in use. Only the side-by-side tool (`src/debug/skin_compare.tscn`) sets it, before the
## HUD enters the tree, so that two HUDs of two skins can be on screen at once; a HUD with a skin of its own ignores changes of the skin in use.
var skin: GameSkin

## The layout of the pack in use (`data/ui/hud_layout.tres` of the first pack of the chain that has one): what a skin's version is made from, again and again.
var _scene_layout: HudLayout
## The skin's lettering as text, or null while the labels are the original's pictures.
var _labels: HudLabels
## The host of the parts a skin mod's script draws (`ModLayerHost`), or null when the skin worn draws none.
var _mod_layers: ModLayerHost


func _ready() -> void:
	_scene_layout = layout if layout != null else Catalog.pack_resource("data/ui/hud_layout.tres") as HudLayout
	_apply_skin()
	SkinChoice.events.changed.connect(_on_skin_changed)
	GameState.oxygen_changed.connect(_on_oxygen_changed)
	GameState.ink_changed.connect(_on_ink_changed)
	GameState.sector_changed.connect(_on_sector_changed)
	GameState.message_light_changed.connect(_on_message_light_changed)
	# One initial read so a HUD created in the middle of a game starts correct.
	_on_oxygen_changed(GameState.tanks(), GameState.oxygen())
	_on_ink_changed(GameState.ink)
	_on_sector_changed(GameState.sector)
	_on_message_light_changed(GameState.ship_light, GameState.computer_light)


## Another skin is in use: the layout and the lettering are put on again, and the labels show what the game is at now.
func _on_skin_changed(_skin: GameSkin) -> void:
	if skin != null:
		return
	_apply_skin()
	_on_sector_changed(GameState.sector)


## Takes the layout and the lettering of the skin in use and puts them on.
func _apply_skin() -> void:
	var wearing := SkinChoice.worn(skin)
	layout = wearing.skinned(_scene_layout) as HudLayout
	_labels = wearing.labels()
	_apply_layout()
	_apply_label_style()
	if _mod_layers != null:
		_mod_layers.end()
	_mod_layers = ModLayerHost.make_hud(self, wearing)
	set_process(_mod_layers != null)


## Puts every picture and gauge where the original has it (or where the skin's layout has it).
func _apply_layout() -> void:
	bezel.texture = layout.bezel
	bezel.position = Vector2(layout.bezel_position)

	tanks.slot_positions = layout.tank_positions
	tanks.full_texture = layout.tank_full
	tanks.empty_texture = layout.tank_empty
	oxygen.slot_positions = layout.oxygen_positions
	oxygen.full_texture = layout.oxygen_full
	oxygen.empty_texture = layout.oxygen_empty
	oxygen.low_texture = layout.oxygen_low
	oxygen.low_value = ConsoleState.LOW_OXYGEN
	ink.slot_positions = layout.ink_positions
	ink.full_texture = layout.ink_full
	ink.empty_texture = layout.ink_empty

	custom_label.position = Vector2(layout.custom_position)
	game_label.position = Vector2(layout.game_position)
	zone_label.position = Vector2(layout.zone_position)
	sector_label.position = Vector2(layout.sector_position)

	ship_light.texture = layout.ship_textures[0]
	ship_glow.texture = layout.ship_textures[1]
	ship_light.position = Vector2(layout.ship_position)
	ship_glow.position = Vector2(layout.ship_position)
	computer_light.texture = layout.computer_textures[0]
	computer_glow.texture = layout.computer_textures[1]
	computer_light.position = Vector2(layout.computer_position)
	computer_glow.position = Vector2(layout.computer_position)
	frame.layout = layout


## The font, colour and box of the skin's text labels (nothing to do while the labels are pictures).
func _apply_label_style() -> void:
	if _labels == null:
		return
	for text: Label in [game_text, custom_text, zone_text, sector_text]:
		if _labels.font != null:
			text.add_theme_font_override(&"font", _labels.font)
		else:
			text.remove_theme_font_override(&"font")
		text.add_theme_font_size_override(&"font_size", _labels.font_size)
		text.add_theme_color_override(&"font_color", _labels.font_color)
		var box := StyleBoxFlat.new()
		box.bg_color = _labels.box_color
		box.content_margin_left = _labels.inset
		text.add_theme_stylebox_override(&"normal", box)


## Shows one label from its part of `ConsoleState.labels`: the picture `picture` in its box, or, for a skin with text, the label's word in the box (its `rect`'s size). The box is
## the same rectangle either way (position set by `_apply_layout`, size from the layout's data), and it cuts off what a font
## would let stick out.
func _show_label(label: TextureRect, text: Label, picture: Texture2D, shown: Dictionary) -> void:
	text.visible = _labels != null
	label.clip_contents = _labels != null
	if _labels == null:
		label.texture = picture
		label.size = Vector2.ZERO                  # (a TextureRect cannot be smaller than its picture: this is its picture's size)
	else:
		label.texture = null
		label.size = shown["rect"].size
		text.text = shown["word"]


func _on_oxygen_changed(_tank_count: int, _oxygen_cells: int) -> void:
	tanks.value = ConsoleState.tanks(layout)["value"]
	var air := ConsoleState.oxygen(layout)
	oxygen.value = air["value"]
	# One cell left: the original shows a red warning cell; we also pulse it.
	if air["low"]:
		air_animations.play(&"low_oxygen")
	else:
		air_animations.stop()
		oxygen.self_modulate = Color.WHITE


func _on_ink_changed(_pellets: int) -> void:
	ink.value = ConsoleState.ink(layout)["value"]


## Game (Voyager / Expert), zone and sector words follow the sector being played.
func _on_sector_changed(_sector_index: int) -> void:
	var state := ConsoleState.labels(layout, _labels)
	var game: Dictionary = state["game"]
	var zone: Dictionary = state["zone"]
	var sector: Dictionary = state["sector"]
	game_label.visible = game["visible"]
	zone_label.visible = zone["visible"]
	sector_label.visible = sector["visible"]
	custom_label.visible = state["custom"]["visible"]
	_show_label(custom_label, custom_text, layout.custom_texture, state["custom"])
	if not game["visible"]:
		return
	var banner: Texture2D = layout.game_textures[game["picture"]] if game["picture"] >= 0 else ConsoleState.campaign_of(GameState.sector).banner
	_show_label(game_label, game_text, banner, game)
	_show_label(zone_label, zone_text, layout.zone_textures[zone["picture"]], zone)
	_show_label(sector_label, sector_text, layout.sector_final_texture if sector["final"] else layout.sector_textures[sector["picture"]], sector)


func _on_message_light_changed(_ship: bool, _computer: bool) -> void:
	var lights := ConsoleState.lights(layout)
	var ship: bool = lights["ship"]["on"]
	var computer: bool = lights["computer"]["on"]
	ship_glow.visible = ship
	computer_glow.visible = computer
	if ship or computer:
		light_animations.play(&"blink")
		light_switched_on.emit()
		Audio.play_sfx(SFX_MESSAGE_LIGHT)
	else:
		light_animations.stop()


# --- a skin mod's script draws parts of the console (`ModLayerHost`) ----------------------------------------------------

func _process(_delta: float) -> void:
	show_mod_layers(GameClock.tick_fraction())


## One frame of the script's parts: it is asked what each draws, from the console's state as it is now (nothing when the skin worn has no script that draws the console).
func show_mod_layers(fraction: float) -> void:
	if _mod_layers != null:
		_mod_layers.show(fraction)


## The state a script that draws the console is told: what the HUD shows, built from the owner now (`ConsoleState.build`), with the places of the light's blink and the warning cell's pulse (the HUD's two animations: the one clock the original's own picture is drawn from).
func console_state() -> Dictionary:
	return ConsoleState.build(layout, _labels, _phase(light_animations), _phase(air_animations))


## How far into its cycle `player`'s animation is (0 to 1), 0 while it does not play.
func _phase(player: AnimationPlayer) -> float:
	if not player.is_playing() or player.current_animation_length <= 0.0:
		return 0.0
	return player.current_animation_position / player.current_animation_length


## The original's nodes of the console layer `layer` (`SkinLayers.HUD_NODES`, or `SkinLayers.HUD`: all of them): what the host makes transparent while the script draws the layer, and behind which it stands.
func layer_nodes(layer: StringName) -> Array[CanvasItem]:
	var found: Array[CanvasItem] = []
	for node_name in SkinLayers.hud_node_names(layer):
		found.append(get_node("%" + node_name) as CanvasItem)
	return found


## The rectangle the script's picture of the layer `layer` is cut to (`ConsoleState.rects`, from the layout in use).
func layer_clip(layer: StringName) -> Rect2:
	return ConsoleState.rects(layout)[String(layer)]


## The game's time as a shader wants it (`ModShader.PHASE_UNIFORM`): the ticks the clock has run plus `fraction` of the current one. It grows smoothly at the speed of play and stands still while the clock does, as the sector's does (`SectorPresenter.game_phase`, which counts from the sector's first tick).
func game_phase(fraction: float) -> float:
	return GameClock.tick_count + fraction


## Runs `action` as this HUD's skin (`SkinChoice.within`; just runs it when `skin` is null): a picture a script names by key is the one this HUD's skin shows.
func run_in_skin(action: Callable) -> Variant:
	return SkinChoice.within(skin, action)


## Does a skin mod's script draw parts of this console?
func hosts_mod_layers() -> bool:
	return _mod_layers != null


## The host of the script's parts (for a test); null with none.
func mod_host() -> ModLayerHost:
	return _mod_layers
