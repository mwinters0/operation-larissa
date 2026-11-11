class_name ConsoleState
extends RefCounted
## What the console shows, as PLAIN DATA built from the owner: the spare tanks, the oxygen cells, the ink pellets, the capsule pieces, the words of the four lettering boxes and the two message lights
## (the skin API, `docs/create/SKIN_API.md` "The console's state"). `Hud` is drawn from it: each part below is the only place its part is worked out (which cells are full, whether the air is low, which picture and
## which word a label has, whether a light is on), `Hud` takes its gauges, pictures, words and lights from the part and `build` makes the whole as one Dictionary, so what a script is told and what the HUD shows cannot differ.
## Every part reads `GameState` (the owner of the numbers, the lights and the sector) and the layout in use (`HudLayout`: how many slots a gauge has, which pictures a label can show, where each thing is), never what the HUD
## heard: a HUD or a script bound in the middle of anything gets what one bound from the start gets (`tests/engine/test_console_state.gd`).
##
## The values are numbers, bools, Strings, `Vector2`, `Rect2`, Arrays and Dictionaries made fresh per call; `build` makes them read-only (`ModLoader.freeze`) as `SkinState.build` does, and none holds an object. A `rect` is in the
## 640 x 400 window's pixels, as the layout has it (the playfield sits at (16, 32)); only the boxes of the lettering have a size there, a picture's size is the art's and the state does not tell it. A lit light blinks in the HUD (half a second a cycle); the state says only that it is lit.
##
## Teaches: one function per fact, shared by the view and the data. The HUD is not given the numbers and left to work out the rest: it asks the same builder the data comes from.

## The oxygen the original warns about: one cell left (the first cell is drawn red and the HUD pulses it).
const LOW_OXYGEN := 1


## The whole console, read-only: `sector` (-1: none), `customized`, `tanks`, `oxygen`, `ink`, `pieces`, `labels`, `lights`, `bezel` (the place of the console's picture) and `playfield` (the window of the sector, a rectangle).
static func build(layout: HudLayout, words: HudLabels) -> Dictionary:
	var state := {
		"sector": GameState.sector,
		"customized": GameState.customized,
		"tanks": tanks(layout),
		"oxygen": oxygen(layout),
		"ink": ink(layout),
		"pieces": pieces(),
		"labels": labels(layout, words),
		"lights": lights(layout),
		"bezel": Vector2(layout.bezel_position),
		"playfield": Rect2(layout.playfield),
	}
	ModLoader.freeze(state)
	return state


## The spare tanks: `value` full icons of `slots` (the gauge cannot show more than it has), `positions` the top-left corner of each icon (the first `value` are full).
static func tanks(layout: HudLayout) -> Dictionary:
	return _gauge(GameState.tanks(), layout.tank_positions)


## The oxygen cells, as `tanks`, and `low`: one cell left (`LOW_OXYGEN`).
static func oxygen(layout: HudLayout) -> Dictionary:
	var gauge := _gauge(GameState.oxygen(), layout.oxygen_positions)
	gauge["low"] = gauge["value"] == LOW_OXYGEN
	return gauge


## The ink pellets, as `tanks`.
static func ink(layout: HudLayout) -> Dictionary:
	return _gauge(GameState.ink, layout.ink_positions)


## The pieces of the sector: `total` (the data canister counts), `collected`, and `taken`, one bool for each piece in the order of its index (0 is the canister). The original's console shows none of it.
static func pieces() -> Dictionary:
	var taken: Array = []
	var collected := 0
	for index in GameState.piece_total:
		var is_taken := (GameState.pieces_mask & (1 << index)) != 0
		taken.append(is_taken)
		collected += 1 if is_taken else 0
	return {"total": GameState.piece_total, "collected": collected, "taken": taken}


## The four lettering boxes, `game`, `custom`, `zone` and `sector`, each with `visible`, `word` (what a text-only skin writes: `words`, or the original's words when it has none, a campaign's own title for a campaign with its own banner) and `rect` (the box,
## the same whether it shows a picture or text). `game` has `picture` too: the number of the original's picture of the game (0 Voyager, 1 Expert), or -1 for the campaign's own banner; `zone` has `picture`, the number of the zone's picture, and `sector` has `picture`
## (First, Second, Third: 0 to 2) and `final`, true for a finale (its picture is -1). A box with `visible` false has no sector to describe: its `word` is "" and its `picture` -1.
static func labels(layout: HudLayout, words: HudLabels) -> Dictionary:
	var lettering: HudLabels = words if words != null else HudLabels.new()     # (the words are only read for a skin with text)
	var campaign := campaign_of(GameState.sector) if GameState.sector >= 0 else null
	var known := campaign != null
	var found := {
		"custom": {"visible": known and GameState.customized, "word": lettering.custom_word, "rect": _box(layout.custom_position, layout.custom_size)},
		"game": {"visible": known, "word": "", "picture": -1, "rect": _box(layout.game_position, layout.game_size)},
		"zone": {"visible": known, "word": "", "picture": -1, "rect": _box(layout.zone_position, layout.zone_size)},
		"sector": {"visible": known, "word": "", "picture": -1, "final": false, "rect": _box(layout.sector_position, layout.sector_size)},
	}
	if not known:
		return found
	var data := Catalog.sector(GameState.sector)
	var place := campaign.position_of(GameState.sector)
	var finale := campaign.is_finale(GameState.sector)
	var game: Dictionary = found["game"]
	if campaign.banner_index >= 0:                       # the original's two pictures (a skin redraws them) ...
		game["picture"] = clampi(campaign.banner_index, 0, layout.game_textures.size() - 1)
		game["word"] = lettering.game_word(campaign.banner_index)
	else:                                                # ... or the campaign's own picture and name
		game["word"] = campaign.display_title()
	var zone: Dictionary = found["zone"]
	zone["picture"] = layout.zone_picture(data.zone)
	zone["word"] = lettering.zone_word(data.zone)
	var sector: Dictionary = found["sector"]
	sector["picture"] = layout.sector_picture(place, finale)
	sector["final"] = finale
	sector["word"] = lettering.sector_word(place, finale)
	return found


## The two message lights, `ship` and `computer`: `on` (lit) and `position` (the top-left corner of its picture).
static func lights(layout: HudLayout) -> Dictionary:
	return {
		"ship": {"on": GameState.ship_light, "position": Vector2(layout.ship_position)},
		"computer": {"on": GameState.computer_light, "position": Vector2(layout.computer_position)},
	}


## The campaign the sector being played belongs to: the player's own if it lists the sector, else the one that does (a sector viewed on its own).
static func campaign_of(sector_index: int) -> Campaign:
	if GameState.profile != null and GameState.profile.campaign().contains(sector_index):
		return GameState.profile.campaign()
	return Catalog.campaign_of_sector(sector_index)


static func _gauge(value: int, positions: PackedVector2Array) -> Dictionary:
	return {"value": clampi(value, 0, positions.size()), "slots": positions.size(), "positions": Array(positions)}


static func _box(position: Vector2i, size: Vector2i) -> Rect2:
	return Rect2(Vector2(position), Vector2(size))

