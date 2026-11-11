class_name ThemeBuilder
extends SceneTree
## Builds `themes/neptune_theme.tres`, the engine's Theme, and every other Theme the game wears: the one place a `Theme` is made.
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
## A SKIN'S THEME. A skin that says how the menus look (`GameSkin.menu_theme`, `SkinTheme`: font, colours, panel and button styles, pictures by key; a skin mod's `skin.theme`, `docs/create/SKIN_API.md`) is worn by
## the project theme itself: `SkinChoice.select` calls `apply`, which derives a theme from the engine's own and the skin's data (`derive`: the engine's theme with only what the skin says laid over it) and puts it in the
## project Theme in place. Every control with no theme of its own looks it up, so it reaches the sign-in screen, the dialogs and the message box whatever they are children of (a `CanvasLayer` breaks the chain of a theme
## set on a node), a control already on screen when the skin changes is told by Godot, and a control made later finds it: there is no per-screen step. A skin with no theme puts the engine's theme back. The controls, their
## rectangles and their order are the scenes', and the font's size stays in a small range so that text keeps fitting (`ModSpec.MIN_THEME_FONT_SIZE`); the diagrams' text (`engine_font`) is the engine's whatever the skin says.
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

## What each colour a skin may name (`SkinTheme.COLORS`) sets in a theme: theme type, item.
const COLOR_ITEMS: Dictionary[String, Array] = {
	"text": [["Label", "font_color"], ["RichTextLabel", "default_color"], ["LineEdit", "font_color"]],
	"title": [["ConsoleTitle", "font_color"], ["HudLabel", "font_color"], ["Hint", "font_color"]],
	"button": [["Button", "font_color"]],
	"button_hover": [["Button", "font_hover_color"]],
	"button_pressed": [["Button", "font_pressed_color"], ["Button", "font_focus_color"]],
	"button_disabled": [["Button", "font_disabled_color"]],
	"good": [["Good", "font_color"]],
	"bad": [["Bad", "font_color"]],
	"caret": [["LineEdit", "caret_color"]],
}
## What each style a skin may name (`SkinTheme.style_names`) sets in a theme: theme type, item.
const STYLE_ITEMS: Dictionary[String, Array] = {
	"panel": [["Panel", "panel"], ["PanelContainer", "panel"]],
	"console": [["ConsolePanel", "panel"]],
	"button/normal": [["Button", "normal"]],
	"button/hover": [["Button", "hover"]],
	"button/pressed": [["Button", "pressed"]],
	"button/disabled": [["Button", "disabled"]],
	"button/focus": [["Button", "focus"]],
	"input/normal": [["LineEdit", "normal"]],
	"input/focus": [["LineEdit", "focus"]],
	"input/read_only": [["LineEdit", "read_only"]],
}

## The engine's own theme (the project theme without a skin's theme on it), made once; null until a skin's theme is first worn. Never changed: every theme derived from it is a copy.
static var _engine: Theme
## Does the project theme hold a skin's theme (so that the engine's has to be put back)?
static var _worn := false


func _init() -> void:
	var error := ResourceSaver.save(build_engine_theme(), OUTPUT)
	if error != OK:
		push_error("could not save %s (error %d)" % [OUTPUT, error])
	else:
		print("saved ", OUTPUT)
	quit(0 if error == OK else 1)


## The engine's theme, from the code: what `OUTPUT` holds.
static func build_engine_theme() -> Theme:
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
	return theme


## The engine's own theme: the project theme as it is before a skin's theme is laid on it. A copy that no skin's theme touches (the items are shared, and an item is replaced, never changed).
static func engine() -> Theme:
	if _engine == null:
		_engine = Theme.new()
		_engine.merge_with(ThemeDB.get_project_theme())
	return _engine


## The default font of the engine's own theme: what the diagrams of the problem screens draw their text in (`ProblemScreenLayout.make_font`), under every skin.
static func engine_font() -> Font:
	var base := ThemeDB.get_project_theme() if _engine == null else _engine
	return base.default_font if base != null and base.has_default_font() else ThemeDB.fallback_font


## Puts the theme `skin` asks for on the project theme: the engine's with the skin's `menu_theme` laid over it, or the engine's own again for a skin that says none. `SkinChoice.select` calls it, so it is
## the one entry (a skin put on in the middle of anything, a skin taken off, a skin mod that stops: all of them are a `select`). Nothing in the editor: the project theme there is not the game's.
static func apply(skin: GameSkin) -> void:
	var project := ThemeDB.get_project_theme()
	if project == null or Engine.is_editor_hint():
		return
	var data := skin.menu_theme_in_use()
	if data == null and not _worn:
		return
	var theme := engine() if data == null else derive(data, skin)
	project.merge_with(theme)                                    # (over the project theme, never after a `clear`: an emptied theme for a moment makes every control size itself by the fallback font, and a control that grew does not shrink back)
	_worn = data != null


## The engine's theme with `data` laid over it (it only ever changes items the engine's theme has, `COLOR_ITEMS` and `STYLE_ITEMS`, so merging the engine's theme over it again restores every one): the font and its size, the colours by name (`COLOR_ITEMS`) and the styles by name (`STYLE_ITEMS`), each style the engine's own with the fields it says changed or, with a
## `picture`, a texture box from the picture `skin` shows for that key (`Assets.picture_by_key`, the lookup a mod's draw list makes) whose content margins stay the engine's unless the style says `margin`. A picture that no
## pack or skin holds leaves the style's other fields to do.
static func derive(data: SkinTheme, skin: GameSkin) -> Theme:
	var theme := Theme.new()
	theme.merge_with(engine())
	if data.font != null:
		theme.default_font = data.font
	if data.font_size > 0:
		theme.default_font_size = data.font_size
	for name in data.colors:
		for item: Array in COLOR_ITEMS[name]:
			theme.set_color(item[1], item[0], data.colors[name])
	for name in data.styles:
		for item: Array in STYLE_ITEMS[name]:
			var base := theme.get_stylebox(item[1], item[0]) if theme.has_stylebox(item[1], item[0]) else null
			theme.set_stylebox(item[1], item[0], _styled(base, data.styles[name], skin))
	return theme


## `base` (a style of the engine's theme, or null) with the fields of `fields` (`SkinTheme.FIELDS`) laid over it.
static func _styled(base: StyleBox, fields: Dictionary, skin: GameSkin) -> StyleBox:
	var margin: Vector2i = fields.get("margin", Vector2i(-1, -1))
	if fields.has("picture"):
		var texture := SkinChoice.within(skin, Assets.picture_by_key.bind(fields["picture"])) as Texture2D
		if texture != null:
			var slice: Vector4i = fields["slice"]
			var box := StyleBoxTexture.new()
			box.texture = texture
			box.texture_margin_left = slice.x
			box.texture_margin_top = slice.y
			box.texture_margin_right = slice.z
			box.texture_margin_bottom = slice.w
			for side in [SIDE_LEFT, SIDE_RIGHT]:
				box.set_content_margin(side, margin.x if margin.x >= 0 else (base.get_margin(side) if base != null else -1.0))
			for side in [SIDE_TOP, SIDE_BOTTOM]:
				box.set_content_margin(side, margin.y if margin.y >= 0 else (base.get_margin(side) if base != null else -1.0))
			return box
	var flat := (base.duplicate() as StyleBoxFlat) if base is StyleBoxFlat else StyleBoxFlat.new()
	if fields.has("fill"):
		flat.bg_color = fields["fill"]
	if fields.has("border"):
		flat.border_color = fields["border"]
	if fields.has("border_width"):
		flat.set_border_width_all(fields["border_width"])
	if fields.has("radius"):
		flat.set_corner_radius_all(fields["radius"])
	if margin.x >= 0:
		flat.content_margin_left = margin.x
		flat.content_margin_right = margin.x
		flat.content_margin_top = margin.y
		flat.content_margin_bottom = margin.y
	return flat


## Liberation Sans Bold narrowed to the original's average character width.
static func _make_font(layout: ProblemScreenLayout) -> Font:
	var em := layout.font_size()
	var squeeze := layout.font_average_width / (em * ProblemScreenLayout.ARIAL_BOLD_AVERAGE_PER_EM)
	var font := FontVariation.new()
	font.base_font = FONT_FILE
	font.variation_transform = Transform2D(Vector2(squeeze, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	# the transform narrows the glyphs but not the advance, so tighten the spacing by the same amount
	font.spacing_glyph = -roundi(ProblemScreenLayout.ADVANCE_PER_EM * em * (1.0 - squeeze))
	return font


static func _label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", WHITE)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	theme.set_color("default_color", "RichTextLabel", WHITE)
	theme.set_constant("line_separation", "RichTextLabel", 0)


static func _buttons(theme: Theme) -> void:
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


static func _panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "Panel", _box(PANEL, GREY, 2, 8, 6))
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, GREY, 2, 8, 6))
	# Console: a black screen in a grey frame, like the monitors of the problem screen.
	theme.set_type_variation("ConsolePanel", "PanelContainer")
	theme.set_stylebox("panel", "ConsolePanel", _box(BLACK, GREY, 2, 10, 8))
	theme.set_type_variation("ConsoleTitle", "Label")
	theme.set_color("font_color", "ConsoleTitle", YELLOW)


static func _menus(theme: Theme) -> void:
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


static func _text_inputs(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _box(BLACK, GREY, 1, 4, 2))
	theme.set_stylebox("focus", "LineEdit", _box(BLACK, YELLOW, 1, 4, 2))
	theme.set_stylebox("read_only", "LineEdit", _box(BLACK, DARK_GREY, 1, 4, 2))
	theme.set_color("font_color", "LineEdit", WHITE)
	theme.set_color("caret_color", "LineEdit", YELLOW)


## Named looks for particular jobs: `theme_type_variation = "HudLabel"` on a Label picks them up.
static func _variations(theme: Theme) -> void:
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
static func _box(fill: Color, border: Color, border_width: int, margin_x: int, margin_y: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box
