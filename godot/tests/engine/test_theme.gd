class_name TestTheme
extends GdUnitTestSuite
## Teaches: a Theme is data and can be checked like data. The tests make sure there is ONE
## project-wide theme, that it defines the looks the UI scenes ask for, and that no UI scene brings
## its own theme or hard-codes a font.

const THEME_PATH := "res://themes/neptune_theme.tres"
const UI_FOLDERS: Array[String] = ["res://src/ui", "res://src/problems", "res://src/gameplay"]


func test_project_uses_the_neptune_theme() -> void:
	assert_str(ProjectSettings.get_setting("gui/theme/custom")).is_equal(THEME_PATH)
	assert_object(ThemeDB.get_project_theme()).is_not_null()
	assert_bool(ThemeDB.get_project_theme().has_default_font()).is_true()


## The font is the project's (`res://fonts`, size and squeeze built into the theme), and every pack's screen layout describes that font: its cell height gives
## the theme's size. (A pack cannot change the font, so dev's layout states the same metrics; the numbers were first taken from the original by `theme_builder.gd`.)
func test_the_font_is_the_project_font_and_the_packs_layout_describes_it() -> void:
	var font := ThemeDB.get_project_theme().default_font as FontVariation
	assert_object(font).is_not_null()
	assert_str(font.base_font.resource_path).is_equal("res://fonts/LiberationSans-Bold.ttf")
	assert_int(ThemeDB.get_project_theme().default_font_size).is_equal(Catalog.screen_layout().font_size())
	assert_object(Catalog.screen_layout().make_font()).is_same(font)       # diagrams draw with the same font


func test_every_look_the_ui_asks_for_exists() -> void:
	var theme: Theme = load(THEME_PATH)
	for variation in ["CalcKey", "ConsolePanel", "ConsoleTitle", "HudLabel", "DebugLabel", "SmallLabel", "Good", "Bad", "Hint"]:
		assert_bool(theme.is_type_variation(variation, "Label") or theme.is_type_variation(variation, "Button")
				or theme.is_type_variation(variation, "PanelContainer")).override_failure_message(variation).is_true()
	for type in ["Button", "Panel", "PanelContainer", "MenuBar", "PopupMenu", "LineEdit"]:
		assert_bool(theme.get_stylebox_type_list().has(type) or theme.has_stylebox("panel", type)).override_failure_message(type).is_true()


## Reads a .tscn as text: a scene file that sets `theme =` on a node or an explicit `font` override
## would bypass the project theme.
func test_ui_scenes_inherit_the_project_theme() -> void:
	var checked := 0
	for folder in UI_FOLDERS:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".tscn"):
				continue
			var text := FileAccess.get_file_as_string("%s/%s" % [folder, file])
			checked += 1
			assert_bool(text.contains("\ntheme = ")).override_failure_message("%s sets its own theme" % file).is_false()
			assert_bool(text.contains("theme_override_fonts/")).override_failure_message("%s overrides a font" % file).is_false()
	assert_int(checked).is_greater(8)


func test_scene_controls_resolve_the_themed_font() -> void:
	var counter := auto_free(PieceCounter.new()) as PieceCounter
	add_child(counter)                                                              # _ready builds the title label
	var label := counter.get_child(0) as Label
	assert_object(label.get_theme_default_font()).is_same(ThemeDB.get_project_theme().default_font)
	assert_object(label.get_theme_color("font_color")).is_equal(Color("ffffff"))    # DebugLabel variation: white
