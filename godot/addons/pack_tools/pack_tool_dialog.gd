@tool
class_name PackToolDialog
extends AcceptDialog
## The "Pack tools" window: pick what to export (a campaign or a complete pack) or a pack to check, fill in the manifest, press Run, read what the tool says.
##
## Teaches: building a window out of code, and running a long job without freezing the editor: a `Thread` runs the other process (`OS.execute` blocks) and
## hands the text back with `call_deferred`, so the window keeps drawing. The job itself is `res://src/packs/pack_tool.tscn` (the same scene a terminal runs):
## `arguments` turns the window's fields into its command line, `run` starts it, and the output is shown as it came.

enum Job { EXPORT_CAMPAIGN, CHECK, NEW_PACK, EXPORT_PACK }

const TOOL_SCENE := "res://src/packs/pack_tool.tscn"
const DEFAULT_OUT := "user://pack_exports"
const MODE_NAMES: Array[String] = ["Export a campaign (a pack over another)", "Check a pack", "New pack (a copy of a pack of the project)", "Export a complete pack (data form)"]

var _mode_box: OptionButton
var _target_box: OptionButton
var _target_edit: LineEdit
var _id_edit: LineEdit
var _title_edit: LineEdit
var _version_edit: LineEdit
var _author_edit: LineEdit
var _out_edit: LineEdit
var _archive_box: CheckBox
var _reach_box: CheckBox
var _run_button: Button
var _output: RichTextLabel
var _last_text := ""
var _thread: Thread

## Emitted on the main thread when the tool has finished: its exit code and everything it printed.
signal finished(code: int, text: String)


func _init() -> void:
	title = "Pack tools"
	ok_button_text = "Close"
	min_size = Vector2i(900, 640)
	exclusive = false
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(column)
	var mode_row := HBoxContainer.new()
	column.add_child(mode_row)
	mode_row.add_child(_label("What"))
	_mode_box = OptionButton.new()
	for i in MODE_NAMES.size():
		_mode_box.add_item(MODE_NAMES[i], i)
	_mode_box.item_selected.connect(func(_index: int) -> void: _fill_targets())
	mode_row.add_child(_mode_box)
	mode_row.add_child(_label("   Which"))
	_target_box = OptionButton.new()
	_target_box.custom_minimum_size.x = 220
	mode_row.add_child(_target_box)
	_target_edit = LineEdit.new()
	_target_edit.placeholder_text = "a folder with a pack.json, or the id of a pack"
	_target_edit.custom_minimum_size.x = 420
	mode_row.add_child(_target_edit)
	var manifest_row := HBoxContainer.new()
	column.add_child(manifest_row)
	_id_edit = _field(manifest_row, "Pack id", "the campaign's or pack's own", 150)
	_title_edit = _field(manifest_row, "Title", "the campaign's or pack's own", 200)
	_version_edit = _field(manifest_row, "Version", "1.0", 70)
	_version_edit.text = "1.0"
	_author_edit = _field(manifest_row, "Author", "", 130)
	var out_row := HBoxContainer.new()
	column.add_child(out_row)
	_out_edit = _field(out_row, "Folder for exports", DEFAULT_OUT, 420)
	_out_edit.text = DEFAULT_OUT
	_archive_box = CheckBox.new()
	_archive_box.text = "one .larissa pack file"
	out_row.add_child(_archive_box)
	_reach_box = CheckBox.new()
	_reach_box.text = "reachability search (slow)"
	_reach_box.button_pressed = true
	out_row.add_child(_reach_box)
	_run_button = Button.new()
	_run_button.text = "Run"
	_run_button.pressed.connect(run)
	out_row.add_child(_run_button)
	var copy := Button.new()
	copy.text = "Copy report"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_last_text))
	out_row.add_child(copy)
	_output = RichTextLabel.new()
	_output.bbcode_enabled = false
	_output.selection_enabled = true
	_output.context_menu_enabled = true
	_output.scroll_following = false
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(860, 400)
	column.add_child(_output)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text + " "
	return label


func _field(row: HBoxContainer, caption: String, placeholder: String, width: int) -> LineEdit:
	row.add_child(_label(caption))
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size.x = width
	row.add_child(edit)
	return edit


## Shows the window set to `job`.
func open(job: Job = Job.EXPORT_CAMPAIGN) -> void:
	_mode_box.select(job)
	_fill_targets()
	popup_centered()


## The targets to choose from: the campaigns of the designer (`res://data/campaigns/*.tres` and the packs' own, but not the original's two), or the packs of the project.
func _fill_targets() -> void:
	_target_box.clear()
	var mode: int = _mode_box.get_selected_id()
	_target_box.visible = mode != Job.CHECK
	_target_edit.visible = mode == Job.CHECK
	_archive_box.visible = mode == Job.EXPORT_CAMPAIGN or mode == Job.EXPORT_PACK
	_out_edit.visible = mode != Job.NEW_PACK
	_id_edit.placeholder_text = "the new pack's id (a lowercase word)" if mode == Job.NEW_PACK else "the campaign's or pack's own"
	var ids: Array[String]
	match mode:
		Job.EXPORT_CAMPAIGN: ids = own_campaign_ids()
		Job.NEW_PACK, Job.EXPORT_PACK: ids = copyable_pack_ids()
	for id in ids:
		_target_box.add_item(id)


## The ids of the campaign files in the project (the legacy pack's folder and `res://data/campaigns`) that are not the original's.
static func own_campaign_ids() -> Array[String]:
	var found: Array[String] = []
	for folder in Catalog.own_campaign_dirs():
		for file in DirAccess.get_files_at(folder):
			var id := file.get_basename()
			if file.get_extension() == "tres" and not Catalog.ORIGINAL_CAMPAIGNS.has(StringName(id)) and not found.has(id):
				found.append(id)
	found.sort()
	return found


## The packs that are folders of the project and so can be copied (`pack_tool --new=<id> --from=<pack>`) or exported whole (`--export-pack=<pack>`): `dev` first (when there is a dev pack), then the others.
static func copyable_pack_ids() -> Array[String]:
	var found: Array[String] = []
	for folder in DirAccess.get_directories_at(Packs.PROJECT_PACKS_DIR):
		if FileAccess.file_exists("%s/%s/%s" % [Packs.PROJECT_PACKS_DIR, folder, Pack.MANIFEST]) and folder != String(Packs.DEV):
			found.append(folder)
	found.sort()
	if Packs.has_dev():
		found.push_front(String(Packs.DEV))
	return found


## The command line of the tool for `job` and these choices (what follows the scene path; the arguments after `--`).
static func arguments(job: Job, target: String, pack_id := "", pack_title := "", version := "", author := "", out := DEFAULT_OUT, archive := false, reach := true) -> PackedStringArray:
	var args := PackedStringArray()
	match job:
		Job.EXPORT_CAMPAIGN:
			args.append("--export-campaign=" + target)
		Job.EXPORT_PACK:
			args.append("--export-pack=" + target)
		Job.CHECK:
			args.append("--check=" + target)
		Job.NEW_PACK:
			args.append("--new=" + pack_id.strip_edges())
			args.append("--from=" + target)
			if not pack_title.strip_edges().is_empty():
				args.append("--title=" + pack_title.strip_edges())
			return args
	if job != Job.CHECK:
		args.append("--out=" + out)
		for pair in [["pack-id", pack_id], ["title", pack_title], ["version", version], ["author", author]]:
			if not String(pair[1]).strip_edges().is_empty():
				args.append("--%s=%s" % [pair[0], String(pair[1]).strip_edges()])
		if archive and (job == Job.EXPORT_CAMPAIGN or job == Job.EXPORT_PACK):
			args.append("--archive")
	if not reach:
		args.append("--no-reach")
	return args


## Runs the tool with `args` in a process of its own and waits for it: [exit code, everything it printed]. (This blocks: `run` calls it on a thread.)
static func run_tool(args: PackedStringArray) -> Array:
	var output: Array = []
	var full := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), TOOL_SCENE, "--"])
	full.append_array(args)
	var code := OS.execute(OS.get_executable_path(), full, output, true)
	return [code, "\n".join(PackedStringArray(output.map(func(chunk: Variant) -> String: return str(chunk))))]


## Starts the job of the window's choices in the background; `finished` says when its report is shown.
func run() -> void:
	if _thread != null and _thread.is_started():
		return                                                            # one at a time
	var mode: int = _mode_box.get_selected_id()
	var target := _target_edit.text.strip_edges() if mode == Job.CHECK else _target_box.get_item_text(maxi(_target_box.selected, 0)) if _target_box.item_count > 0 else ""
	if mode == Job.NEW_PACK and _id_edit.text.strip_edges().is_empty():
		_output.text = "Nothing to run: write the new pack's id in the Pack id field (a lowercase word, not 'dev')."
		return
	if target.is_empty():
		_output.text = "Nothing to run: %s." % ("say which pack to check" if mode == Job.CHECK else "there is no pack in res://packs/ to copy (the dev pack, dev.larissa, comes with the creator download)" if mode == Job.NEW_PACK or mode == Job.EXPORT_PACK else "there is no campaign of your own in res://data/campaigns/ to export")
		return
	var args := arguments(mode, target, _id_edit.text, _title_edit.text, _version_edit.text, _author_edit.text, _out_edit.text.strip_edges(), _archive_box.button_pressed, _reach_box.button_pressed)
	_run_button.disabled = true
	_output.text = "Running ... (the same as: godot --headless --path godot %s -- %s)" % [TOOL_SCENE, " ".join(args)]
	_thread = Thread.new()
	_thread.start(func() -> void: _done.call_deferred(run_tool(args)))


func _done(result: Array) -> void:
	_thread.wait_to_finish()
	_thread = null
	_last_text = result[1]
	_output.text = _last_text if not _last_text.strip_edges().is_empty() else "The tool printed nothing (exit code %d)." % result[0]
	_run_button.disabled = false
	finished.emit(result[0], _last_text)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
