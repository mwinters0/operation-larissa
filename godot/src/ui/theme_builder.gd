extends SceneTree
## Builds `themes/neptune_theme.tres`, the ONE Theme of the whole game.
##
## Teaches: a Theme is just a Resource holding fonts, colours, StyleBoxes and constants per Control
## type. Everything a Control looks like comes from the nearest Theme up the tree, and the PROJECT
## theme (Project Settings > GUI > Theme > Custom) is the last stop, so a Control that sets nothing
## still looks like the game. Instead of clicking the theme together in the editor (which hides
## the numbers in a binary-ish blob) this script writes it from code, so the look is readable,
## reviewable and repeatable.
##
## Run it after changing a colour or a size:
##     tools/godot.sh --headless --path godot -s res://src/ui/theme_builder.gd
##
## The font is the problem screen's: Arial Bold's metric twin, squeezed to the width the original's
## GDI font had (`ProblemScreenLayout` holds those two numbers, taken from the game's own strings).
## The palette is the original's 16 VGA colours; the console look (dark grey panels, yellow
## lettering) comes from the bezel art.

const OUTPUT := "res://themes/neptune_theme.tres"
const FONT_FILE := preload("res://fonts/LiberationSans-Bold.ttf")

# The VGA colours the original draws its console with.
const BLACK := Color("000000")
const DARK_GREY := Color("555555")
const GREY := Color("c0c0c0")
const WHITE := Color("ffffff")
const YELLOW := Color("ffff55")
const RED := Color("ff5555")
const GREEN := Color("55ff55")
const PANEL := Color("2b2b2b")             # the console's metal, a little darker than DARK_GREY

const MENU_FONT_SIZE := 13
const SMALL_FONT_SIZE := 13


func _init() -> void:
	var layout := Packs.resource("data/problems/screen_layout.tres") as ProblemScreenLayout
	var theme := Theme.new()
	theme.default_font = _make_font(layout)
	theme.default_font_size = layout.font_size()

	_label(theme)
	_buttons(theme)
	_panels(theme)
	_menus(theme)
	_text_inputs(theme)
	_variations(theme)

	var error := ResourceSaver.save(theme, OUTPUT)
	if error != OK:
		push_error("could not save %s (error %d)" % [OUTPUT, error])
	else:
		print("saved ", OUTPUT)
	quit(0 if error == OK else 1)


## Liberation Sans Bold narrowed to the original's average character width.
func _make_font(layout: ProblemScreenLayout) -> Font:
	var em := layout.font_size()
	var squeeze := layout.font_average_width / (em * ProblemScreenLayout.ARIAL_BOLD_AVERAGE_PER_EM)
	var font := FontVariation.new()
	font.base_font = FONT_FILE
	font.variation_transform = Transform2D(Vector2(squeeze, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	# the transform narrows the glyphs but not the advance, so tighten the spacing by the same amount
	font.spacing_glyph = -roundi(ProblemScreenLayout.ADVANCE_PER_EM * em * (1.0 - squeeze))
	return font


func _label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", WHITE)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	theme.set_color("default_color", "RichTextLabel", WHITE)
	theme.set_constant("line_separation", "RichTextLabel", 0)


func _buttons(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _box(PANEL, GREY, 1, 6, 3))
	theme.set_stylebox("hover", "Button", _box(DARK_GREY, WHITE, 1, 6, 3))
	theme.set_stylebox("pressed", "Button", _box(BLACK, YELLOW, 1, 6, 3))
	theme.set_stylebox("disabled", "Button", _box(PANEL, DARK_GREY, 1, 6, 3))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), YELLOW, 1, 6, 3))
	theme.set_color("font_color", "Button", GREY)
	theme.set_color("font_hover_color", "Button", WHITE)
	theme.set_color("font_pressed_color", "Button", YELLOW)
	theme.set_color("font_focus_color", "Button", YELLOW)
	theme.set_color("font_disabled_color", "Button", DARK_GREY)

	# CalcKey: the calculator's buttons are invisible rectangles over the original's key art;
	# only the hover / pressed / keyboard states show (a yellow glass over the key).
	var none := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0)
	theme.set_type_variation("CalcKey", "Button")
	theme.set_stylebox("normal", "CalcKey", none)
	theme.set_stylebox("disabled", "CalcKey", none)
	theme.set_stylebox("focus", "CalcKey", none)
	theme.set_stylebox("hover", "CalcKey", _box(Color(1, 1, 0.33, 0.16), YELLOW, 1, 0, 0))
	theme.set_stylebox("pressed", "CalcKey", _box(Color(1, 1, 1, 0.38), WHITE, 1, 0, 0))


func _panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", _box(PANEL, GREY, 2, 8, 6))
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, GREY, 2, 8, 6))
	# Console: a black screen in a grey frame, like the monitors of the problem screen.
	theme.set_type_variation("ConsolePanel", "PanelContainer")
	theme.set_stylebox("panel", "ConsolePanel", _box(BLACK, GREY, 2, 10, 8))
	theme.set_type_variation("ConsoleTitle", "Label")
	theme.set_color("font_color", "ConsoleTitle", YELLOW)


func _menus(theme: Theme) -> void:
	var clear := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 2)
	var highlight := _box(DARK_GREY, DARK_GREY, 0, 6, 2)
	theme.set_font_size("font_size", "MenuBar", MENU_FONT_SIZE)
	theme.set_stylebox("normal", "MenuBar", clear)
	theme.set_stylebox("hover", "MenuBar", highlight)
	theme.set_stylebox("pressed", "MenuBar", highlight)
	theme.set_stylebox("disabled", "MenuBar", clear)
	theme.set_stylebox("hover_pressed", "MenuBar", highlight)
	theme.set_color("font_color", "MenuBar", GREY)
	theme.set_color("font_hover_color", "MenuBar", WHITE)
	theme.set_color("font_pressed_color", "MenuBar", YELLOW)
	theme.set_color("font_hover_pressed_color", "MenuBar", YELLOW)
	theme.set_color("font_disabled_color", "MenuBar", DARK_GREY)
	theme.set_constant("h_separation", "MenuBar", 4)

	theme.set_font_size("font_size", "PopupMenu", MENU_FONT_SIZE)
	theme.set_stylebox("panel", "PopupMenu", _box(BLACK, GREY, 1, 2, 2))
	theme.set_stylebox("hover", "PopupMenu", _box(DARK_GREY, DARK_GREY, 0, 4, 1))
	theme.set_stylebox("separator", "PopupMenu", _box(DARK_GREY, DARK_GREY, 0, 0, 0))
	theme.set_color("font_color", "PopupMenu", GREY)
	theme.set_color("font_hover_color", "PopupMenu", WHITE)
	theme.set_color("font_disabled_color", "PopupMenu", DARK_GREY)
	theme.set_color("font_accelerator_color", "PopupMenu", DARK_GREY)
	theme.set_constant("v_separation", "PopupMenu", 2)
	theme.set_constant("item_start_padding", "PopupMenu", 6)
	theme.set_constant("item_end_padding", "PopupMenu", 6)


func _text_inputs(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _box(BLACK, GREY, 1, 4, 2))
	theme.set_stylebox("focus", "LineEdit", _box(BLACK, YELLOW, 1, 4, 2))
	theme.set_stylebox("read_only", "LineEdit", _box(BLACK, DARK_GREY, 1, 4, 2))
	theme.set_color("font_color", "LineEdit", WHITE)
	theme.set_color("caret_color", "LineEdit", YELLOW)


## Named looks for particular jobs: `theme_type_variation = "HudLabel"` on a Label picks them up.
func _variations(theme: Theme) -> void:
	theme.set_type_variation("HudLabel", "Label")
	theme.set_font_size("font_size", "HudLabel", SMALL_FONT_SIZE)
	theme.set_color("font_color", "HudLabel", YELLOW)

	theme.set_type_variation("DebugLabel", "Label")
	theme.set_font_size("font_size", "DebugLabel", SMALL_FONT_SIZE)
	theme.set_color("font_color", "DebugLabel", WHITE)
	theme.set_color("font_outline_color", "DebugLabel", BLACK)
	theme.set_constant("outline_size", "DebugLabel", 3)

	theme.set_type_variation("SmallLabel", "Label")
	theme.set_font_size("font_size", "SmallLabel", SMALL_FONT_SIZE)

	theme.set_type_variation("Good", "Label")
	theme.set_color("font_color", "Good", GREEN)
	theme.set_type_variation("Bad", "Label")
	theme.set_color("font_color", "Bad", RED)
	theme.set_type_variation("Hint", "Label")
	theme.set_color("font_color", "Hint", YELLOW)


## A StyleBoxFlat: fill, border, and the space between border and content.
func _box(fill: Color, border: Color, border_width: int, margin_x: int, margin_y: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box
