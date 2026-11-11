class_name ProblemScreenLayout
extends Resource
## The parts of the problem screen that are the same for all 34 types, as the original lays
## them out on its 640 x 400 window (DESIGN 5.5): the background picture, where the title and the
## prompt text go, and the colours and font of the text.
##
## Teaches: a small settings Resource filled by the importer (`tools/import/step_problems.py`,
## from `extracted/tables/problem_diagrams.json`) so that no layout number is written in a script.

## The screen picture: a title bar, the diagram monitor (left) and the text monitor (right).
@export var background: Texture2D
@export var background_position: Vector2i = Vector2i.ZERO
## The size of that picture, written from the picture file (a screen takes its rectangle from data, and stretches a skin's picture of another size to it).
@export var background_size: Vector2i = Vector2i.ZERO
## The title is centred in the box [title_box_x, title_box_x + title_box_width) at height `title_y`.
@export var title_box_x: int = 0
@export var title_box_width: int = 0
@export var title_y: int = 0
## Where prompt, hint and solution are written (white text on the black right-hand monitor).
@export var message_box: Rect2i = Rect2i()
## Top-left corner of the original's calculator picture.
@export var calculator_position: Vector2i = Vector2i.ZERO
## The GDI font the original makes: `font_cell_height` px tall (em size = cell height / 1.117 for
## Arial), `font_average_width` px per character on average, `line_height` px between lines (`GetFontLineHeight` (0x414dc4): 20,
## the larger of the Arial cell and the bitmap font's height, for every text).
@export var font_cell_height: int = 19
@export var font_average_width: int = 7
@export var line_height: int = 20
## Extra pixels between two lines of text so that they are `line_height` apart: `line_height` minus the height of one line of the
## project font (20). It is DATA because a screen must not ask the font; the importer writes it
## (`STOCK_FONT_LINE_HEIGHT` in `tools/import/step_problems.py`) and the test `test_layout_from_data.gd` checks it against the theme's font.
@export var line_separation: int = 0
## The 16 VGA colours of the original's `SetColor(n)`.
@export var palette: PackedColorArray = PackedColorArray()

## Arial's ascent plus descent is 1.117 em, so a 19 px cell is a 17 px em.
const ARIAL_CELL_PER_EM := 1.117
## Arial Bold's average character is about 8.3 px wide at 17 px; the original asks for 7 px.
const ARIAL_BOLD_AVERAGE_PER_EM := 0.49
## A typical Arial Bold letter advances about 0.55 em.
const ADVANCE_PER_EM := 0.55


## The em size in pixels of the original's font (17).
func font_size() -> int:
	return roundi(font_cell_height / ARIAL_CELL_PER_EM)


## The font of every text the problem screen's diagrams draw. It is the default font of the engine's theme (`themes/neptune_theme.tres`, built by `src/ui/theme_builder.gd` from the numbers above:
## Liberation Sans Bold narrowed to the original's average character width), so there is ONE font definition in the whole game, and a skin's theme does not change it (`ThemeBuilder.engine_font`). `Control`s get their font
## from the theme automatically; this helper is for code that draws strings itself with `draw_string` and may run outside the scene tree.
func make_font() -> Font:
	return ThemeBuilder.engine_font()


## `SetColor(n)`: palette entry `index` (0-15).
func color(index: int) -> Color:
	return palette[clampi(index, 0, palette.size() - 1)]
