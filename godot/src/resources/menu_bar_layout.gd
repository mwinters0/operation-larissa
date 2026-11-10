class_name MenuBarLayout
extends Resource
## Where the menu bar's popups open. Filled by the importer (`MENU_TITLE_X` in `tools/import/step_console.py`).
##
## Teaches: layout as data. The `MenuBar` draws its titles with the theme font and cannot say where a title is, so the keyboard
## way into a menu (F10, then Left / Right) used to measure the titles with the font to find the x to open the popup at.
## Now the x of each title is one number here, and a skin with another menu font brings other numbers.

## For menu number `i` (File, Options, Help): pixels from the bar's left edge to where its popup opens.
@export var title_x: PackedInt32Array = PackedInt32Array()


## The x offset for menu `index`, or the last one if the bar has more menus than the table.
func popup_x(index: int) -> int:
	return title_x[clampi(index, 0, title_x.size() - 1)]
