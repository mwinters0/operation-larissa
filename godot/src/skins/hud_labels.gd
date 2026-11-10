class_name HudLabels
extends Resource
## The words of the HUD's lettering, and how to write them: the "Game", "Zone" and "Sector" boxes of the console are PICTURES of
## words in the original (an 8-bit-colour bitmap font, yellow on green); a skin that supplies a `HudLabels` gets those boxes as real text
## in its own font instead. The BOXES do not change: the rectangle of each one is in `HudLayout` (`game_size`,
## `zone_size`, `sector_size`, `custom_size`), so a larger or smaller font cannot move anything.
##
## The defaults are the words and colours of the original's pictures, so a skin only has to set a `font`.
##
## Teaches: text as DATA. The words belong to the skin, not to the game rules, so a translation or a different tone is a resource
## in the Inspector; a font is a `Font` resource (a `.ttf` / `.otf` file or a `SystemFont`) chosen the same way.

## The font of the four boxes. Null: the project theme's font.
@export var font: Font
@export var font_size: int = 14
## The colour of the letters (the original's yellow) and of the box behind them (the original's green).
@export var font_color: Color = Color(0.988, 0.957, 0.0)
@export var box_color: Color = Color(0.016, 0.345, 0.0)
## Pixels between the box's left edge and the first letter.
@export var inset: int = 4

## "Voyager" and "Expert", by the campaign's `banner_index`.
@export var game_words: Array[String] = ["Voyager", "Expert"]
## The word added for a customised game.
@export var custom_word: String = "Cust"
## One word per zone (the finale zones, 5 and 6, show the last).
@export var zone_words: Array[String] = ["Dragon Reef", "Fossil Trench", "Limestone Ridge", "Sea Forest", "Hammerhead"]
## "First", "Second", "Third" (sector number within its zone) and the word of the finale sectors.
@export var sector_words: Array[String] = ["First", "Second", "Third"]
@export var sector_final_word: String = "Final"


func game_word(game: int) -> String:
	return game_words[clampi(game, 0, game_words.size() - 1)]


func zone_word(zone: int) -> String:
	return zone_words[clampi(zone, 0, zone_words.size() - 1)]


## The word of a sector: `place` is its place in the campaign (0-based, `Campaign.position_of`), `is_finale` says it is a finale.
func sector_word(place: int, is_finale: bool) -> String:
	if is_finale:
		return sector_final_word
	return sector_words[maxi(place, 0) % sector_words.size()]
