class_name SkinTheme
extends Resource
## What a skin says of the look of the menus (sign-in, the dialogs, the message box and every control that has no theme of its own), as plain data: a font, named colours and named styles. It holds no `Theme`: `ThemeBuilder` is the
## one place a `Theme` is made, and it lays this on the engine's own theme (`themes/neptune_theme.tres`), so what a skin does not say is the engine's. A `GameSkin` holds one (`menu_theme`, a skin mod's `skin.theme`, `ModSpec`).
##
## The names are the vocabulary the manifest, `ModSpec` (which checks the values) and `ThemeBuilder` (which says what each name is in a theme) share:
##   * `colors`: `text` (labels, text boxes, the text of a message and of the problem screen), `title` (the headings and hints), `button`, `button_hover`, `button_pressed`, `button_disabled` (the letters of a button), `good`, `bad` (the wrong answer's message on the
##     problem screen too), `caret` and `display` (the field behind the digits of the calculator and the "Ans:" panel).
##   * `styles`: `panel` (panels), `console` (the frame of a dialog and of the message box), `button` with a state (`normal`, `hover`, `pressed`, `disabled`, `focus`), `input` with one (`normal`, `focus`, `read_only`) and `key` with one (`normal`, `hover`, `pressed`: the calculator's keys, which are the original's picture with a button over each; `normal` is clear, `hover` and `pressed` are the glass that lights a key). A style is
##     the fields it says, laid over the engine's own style of that name: `fill` and `border` (`Color`), `border_width`, `radius` (whole numbers), `margin` (`Vector2i`: the space between the border and the content, x and y), or a
##     picture, `picture` (a skin key, `ThemeBuilder` finds it as the draw list of a mod does, `Assets.picture_by_key`) with `slice` (`Vector4i`: the margins that stay unstretched, left, top, right, bottom).
## The controls, their order, their rectangles and what they do are the engine's: nothing here names one.
##
## Teaches: a look as a table of names to values, so that a skin is a few lines of data, a partial one is a layer over a whole one (the same idea as `GameSkin.fallback`), and the thing that makes a `Theme` is one function.

## The colours a theme may name (`colors`).
const COLORS: Array[String] = ["text", "title", "button", "button_hover", "button_pressed", "button_disabled", "good", "bad", "caret", "display"]
## The styles a theme may name: style -> its states (empty: the style has none). `styles` is keyed by the style, or by `<style>/<state>`.
const STYLES: Dictionary[String, Array] = {
	"panel": [],
	"console": [],
	"button": ["normal", "hover", "pressed", "disabled", "focus"],
	"input": ["normal", "focus", "read_only"],
	"key": ["normal", "hover", "pressed"],
}
## The fields a style says.
const FIELDS: Array[String] = ["fill", "border", "border_width", "radius", "margin", "picture", "slice"]

## The default font of the menus, or null for the engine's. `font_size` (pixels) is the size of the default font, 0 for the engine's.
@export var font: Font
@export var font_size := 0
## colour name (`COLORS`) -> the colour.
@export var colors: Dictionary[String, Color] = {}
## style name (`panel`, `console`, or `button/hover`: `STYLES`) -> the fields it says (`FIELDS`).
@export var styles: Dictionary[String, Dictionary] = {}


## Does it say nothing at all? (A skin whose theme says nothing wears the engine's.)
func is_empty() -> bool:
	return font == null and font_size == 0 and colors.is_empty() and styles.is_empty()


## The names of every style there is: `panel`, `console`, `button/normal`, ... (the keys `styles` may have).
static func style_names() -> Array[String]:
	var names: Array[String] = []
	for style in STYLES:
		if STYLES[style].is_empty():
			names.append(style)
		for state: String in STYLES[style]:
			names.append("%s/%s" % [style, state])
	return names
