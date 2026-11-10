class_name PackDialog
extends Control
## The pack screen: the packs that are installed or come with the game, the chain of packs the game is using and why, and the buttons to check one, install one
## and remove one. It is OUR addition, not the original's, so the sign-in screen reaches it by a key (P) and shows a small "Packs"
## button only once there is a pack to talk about (see `SignIn`): a game with no pack installed looks as the original did. There is nothing to switch on: the
## game uses the pack `--pack=<id>` names, else the first pack found, and the packs it is laid over (`Packs`). The one exception: when the game refused its choice
## (`Packs.is_refused`), `PackWarning` opens it with `choosing` set and it also has a button that chooses the selected pack (`used`).
##
## Teaches: a dialog that only asks questions and shows answers, like the sign-in screen's others. What is true about a pack is worked out by
## `PackCheck` and kept by `PackChoice`, `PackInstall` and `PackExport`; this scene lists `PackChoice.entries()` and calls them. Checking a pack runs the quick
## check and shows its report here. A pack outside the project is read as data, and the only code it can hold is a sandboxed mod script that reaches only what the game hands it (`ModLoader`), so no pack asks for trust.

## The player closed the screen (Done or Esc). Every change is already made and kept.
signal closed
## The player chose the pack `id` with the Use button (`choosing`): `Packs.choose` has been called, `Packs.fallback_reason()` says if the chain is whole.
signal used(id: StringName)
## A pack was installed or removed: whoever shows campaigns or skins should look again.
signal changed

@onready var tree: Tree = %PackList
@onready var details: RichTextLabel = %Details
@onready var intro: Label = %Intro
@onready var use_button: Button = %Use
@onready var check_button: Button = %Check
@onready var install_button: Button = %Install
@onready var remove_button: Button = %Remove
@onready var done_button: Button = %Done
@onready var folder_label: Label = %Folder

## Does the screen offer to choose a pack? Set before the screen is added to the tree (`PackWarning` does, when the game refused its choice).
var choosing := false
## What the next press of the Remove button must confirm ("remove:<id>"), or "".
var _confirming := ""
var _picker: FileDialog


func _ready() -> void:
	tree.columns = 3
	tree.column_titles_visible = true
	tree.hide_root = true
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		tree.set_focus_neighbor(side, ^".")                               # (an arrow at the edge of the list keeps the focus on it; Tab leaves)
	for column in 3:
		tree.set_column_title(column, ["Pack", "Where", "State"][column])
	tree.set_column_expand(0, true)
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 64)
	tree.set_column_expand(2, false)
	tree.set_column_custom_minimum_width(2, 96)
	tree.item_selected.connect(_on_selected)
	tree.item_activated.connect(check)
	use_button.visible = choosing
	use_button.pressed.connect(use_selected)
	check_button.pressed.connect(check)
	install_button.pressed.connect(_ask_for_a_pack)
	remove_button.pressed.connect(remove_selected)
	done_button.pressed.connect(close)
	folder_label.text = "Packs are kept in %s" % ProjectSettings.globalize_path(PackInstall.DIR)
	refresh()
	tree.grab_focus()


# --- the list ---------------------------------------------------------------------------------------------------------------

## Builds the list again from `PackChoice.entries()`, keeping the selection.
func refresh() -> void:
	var previous := selected_id()
	intro.text = PackChoice.summary()
	tree.clear()
	var root := tree.create_item()
	var to_select: TreeItem = null
	for entry in PackChoice.entries():
		var row := tree.create_item(root)
		row.set_metadata(0, entry.id())
		row.set_text(0, entry.pack.title if not entry.pack.title.is_empty() else String(entry.id()))
		row.set_text(1, "project" if entry.pack.trusted else "installed")
		row.set_text(2, PackChoice.state_text(entry))
		if entry.id() == previous:
			to_select = row
	if to_select == null and root.get_child_count() > 0:
		to_select = root.get_first_child()
	if to_select != null:
		to_select.select(0)
	else:
		_describe(null)
	_update_buttons()


func selected_id() -> StringName:
	var item := tree.get_selected()
	return item.get_metadata(0) if item != null else &""


func selected_entry() -> PackChoice.Entry:
	return PackChoice.entry(selected_id()) if selected_id() != &"" else null


func entry_count() -> int:
	return tree.get_root().get_child_count() if tree.get_root() != null else 0


## Selects the row of the pack `id` (for tests and for a pack just installed).
func select(id: StringName) -> void:
	var item := tree.get_root().get_first_child() if tree.get_root() != null else null
	while item != null:
		if item.get_metadata(0) == id:
			item.select(0)
			return
		item = item.get_next()


func _on_selected() -> void:
	_confirming = ""
	_describe(selected_entry())
	_update_buttons()


func _update_buttons() -> void:
	var entry := selected_entry()
	use_button.disabled = entry == null or not entry.pack.is_valid()
	use_button.text = "Use this pack"
	check_button.disabled = entry == null
	check_button.text = "Check"
	remove_button.disabled = entry == null or not is_installed_by_player(entry)
	remove_button.text = "Remove"


## Was this pack put in the player's folder (and so can be taken out again)? The game's own packs (`res://packs/`) cannot.
static func is_installed_by_player(entry: PackChoice.Entry) -> bool:
	return entry.pack.root.begins_with(PackInstall.DIR + "/")


## What the details box says about `entry`: who made it, what it holds, why it is not loaded.
func _describe(entry: PackChoice.Entry) -> void:
	if entry == null:
		details.text = "No packs yet. A pack is a folder or a .larissa file: press Install, or put it in the folder below."
		return
	var pack := entry.pack
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]  (%s)" % [_plain(pack.title if not pack.title.is_empty() else String(pack.id)), pack.id])
	if not pack.version.is_empty():
		lines.append("version %s%s" % [_plain(pack.version), " by %s" % _plain(pack.author) if not pack.author.is_empty() else ""])
	if not pack.description.is_empty():
		lines.append(_plain(pack.description))
	var holds := holds_text(pack)
	if not holds.is_empty():
		lines.append("holds " + holds)
	if entry.in_use():
		lines.append("In use%s." % (" (the chosen pack)" if entry.position == 0 else ", under %s" % Packs.chain()[entry.position - 1].id))
	if not pack.base.is_empty():
		lines.append("laid over the pack '%s'" % pack.base)
	for message in pack.errors:
		lines.append("[color=#ff6666]%s[/color]" % _plain(message))
	details.text = "\n".join(lines)


## "1 campaign, 3 sectors" / "".
static func holds_text(pack: Pack) -> String:
	var parts := PackedStringArray()
	if not pack.is_valid():
		return ""
	var campaigns := pack.campaign_ids()
	if not campaigns.is_empty():
		parts.append("%d campaign%s" % [campaigns.size(), "" if campaigns.size() == 1 else "s"])
		var sectors := pack.sector_ids()
		parts.append("%d sector%s" % [sectors.size(), "" if sectors.size() == 1 else "s"])
	return ", ".join(parts)


static func _plain(text: String) -> String:
	return text.replace("[", "[lb]")


# --- actions ----------------------------------------------------------------------------------------------------------------

## Checks the selected pack and shows the report.
func check() -> void:
	var entry := selected_entry()
	if entry == null:
		return
	_confirming = ""
	var report := PackCheck.run(entry.pack, PackChoice.check_options())
	details.text = "[b]%s[/b] %s\n%s" % [_plain(entry.pack.title), ("passes the check." if report.passes() else "has errors."), report.bbcode()]
	_update_buttons()


## Chooses the selected pack (`Packs.choose`) and says so (`used`). Only on a screen that offers it (`choosing`).
func use_selected() -> void:
	var entry := selected_entry()
	if not choosing or entry == null or not entry.pack.is_valid():
		return
	_confirming = ""
	Packs.choose(entry.id())
	refresh()
	used.emit(entry.id())


## Asks the player for a folder or a `.larissa` pack file to install.
func _ask_for_a_pack() -> void:
	if _picker == null:
		_picker = FileDialog.new()
		_picker.title = "Install a pack"
		_picker.file_mode = FileDialog.FILE_MODE_OPEN_ANY
		_picker.access = FileDialog.ACCESS_FILESYSTEM
		_picker.use_native_dialog = true
		_picker.filters = PackedStringArray(["*.%s ; Packs" % Pack.FILE_EXTENSION])
		_picker.file_selected.connect(install_from)
		_picker.dir_selected.connect(install_from)
		add_child(_picker)
	_picker.popup_centered_ratio(0.7)


## Installs the pack at `path` (a folder or a `.larissa` pack file) and selects it. The game does not use it unless it is chosen.
func install_from(path: String) -> void:
	var result := PackInstall.install(path)
	refresh()
	if result.ok:
		select(result.id)
		_on_selected()
		details.text = "%s\n\n%s" % [_plain(result.message), details.text]
		changed.emit()
	else:
		details.text = "[color=#ff6666]Not installed: %s[/color]" % _plain(result.message)


## Takes the selected pack out of the player's folder (asks once).
func remove_selected() -> void:
	var entry := selected_entry()
	if entry == null or not is_installed_by_player(entry):
		return
	if _confirming != "remove:%s" % entry.id():
		_confirming = "remove:%s" % entry.id()
		remove_button.text = "Really remove"
		details.text = "Press Remove again to delete [b]%s[/b] from your packs folder. Players of its campaign keep their records, but cannot play them until it is installed again." % _plain(entry.pack.title)
		return
	_confirming = ""
	var failure := PackInstall.uninstall(entry.id())
	refresh()
	details.text = "[color=#ff6666]%s[/color]" % _plain(failure) if not failure.is_empty() else "%s is removed." % _plain(entry.pack.title)
	changed.emit()


func close() -> void:
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
