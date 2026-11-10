@tool
class_name ScreenEditorPlaytest
extends RefCounted
## Starts the game on the screen being edited: "Playtest screen".
##
## Teaches: handing a running game what it needs without a command line. `EditorInterface.play_custom_scene` takes no arguments,
## and the game is another process that reads the files from disk. So (1) the screen is written first, and (2) the words of the
## `PlaytestSetup` travel in an environment variable (`FoeSandbox.ARGS_ENV`) that is set only for the moment the game process is
## created, the same way the Foe Script editor's "Run in sandbox" does it (addons/foe_script_editor/plugin.gd). The scene
## `screen_playtest.tscn` reads them back with `PlaytestSetup.from_arguments`.

const SCENE := "res://src/debug/screen_playtest.tscn"
## How long the environment variable stays set: the game process has been created long before.
const ENV_SECONDS := 2.0


## Why this editor's screen can not be played ("" when it can).
static func why_not(editor: ScreenEditor) -> String:
	if not editor.load_error.is_empty():
		return "the screen could not be loaded: " + editor.load_error
	if editor.data_dir != ScreenEditor.DATA_DIR:
		return "this editor works on a copy of the data (%s), and the game reads the sectors of the project" % editor.data_dir
	return ""


## Writes the screen when it has unsaved changes, because the game reads the files. "" when the files are the screen now,
## else why not (a screen with problems is not written, and playing the old file would not be what the designer sees).
static func save_first(editor: ScreenEditor) -> String:
	var reason := why_not(editor)
	if not reason.is_empty():
		return reason
	var built := editor.build()
	if not built.problems.is_empty():
		return "screen %d of sector %d can not be saved yet, so the game would not see what is on the screen (%s)" % [
				editor.screen, editor.sector, built.problems[0]]
	if editor.is_dirty() and not editor.save_screen():
		return "screen %d of sector %d could not be written" % [editor.screen, editor.sector]
	return ""


## Plays `setup` on the screen `editor` shows. Returns "" when the game was started, else why not (nothing was started). The
## setup is for this editor's sector and screen whatever it says. `launch` takes the words and starts the game; the default is
## `start_game`, a test passes its own.
static func run(editor: ScreenEditor, setup: PlaytestSetup, launch: Callable = Callable()) -> String:
	var reason := save_first(editor)
	if not reason.is_empty():
		return "Not played: " + reason
	setup.sector = editor.sector
	setup.screen = editor.screen
	var arguments := setup.to_arguments()
	if launch.is_valid():
		launch.call(arguments)
	else:
		start_game(arguments)
	return ""


## Sets the variable, starts the scene (the editor saves everything else it knows of first, `_build`) and takes the variable away
## again, so that a sandbox started by hand later does not repeat this run.
static func start_game(arguments: String) -> void:
	OS.set_environment(FoeSandbox.ARGS_ENV, arguments)
	EditorInterface.play_custom_scene(SCENE)
	EditorInterface.get_base_control().get_tree().create_timer(ENV_SECONDS).timeout.connect(
			func() -> void: OS.unset_environment(FoeSandbox.ARGS_ENV))
