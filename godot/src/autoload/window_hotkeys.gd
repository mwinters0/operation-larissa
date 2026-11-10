extends Node
## Alt+Enter toggles fullscreen, from every screen of the game (autoload "WindowHotkeys").
##
## Teaches: a global key handled in ONE place instead of in every screen, and what that takes in Godot's input order. A key goes
## `_input` -> the GUI -> `_shortcut_input` -> `_unhandled_key_input` -> `_unhandled_input`. A handler that calls
## `Viewport.set_input_as_handled()` in `_input` ends the walk, so the screens that only listen in `_unhandled_*` never see the
## key. But `_input` itself is called in REVERSE tree order (the last node of the tree first), and an autoload sits at the top of
## the tree, so it would hear the key LAST, after the few screens that take every key in `_input` (the sign-in screen while it
## listens, the log screen, the calculator notice). So this node moves itself to the end of the root's children, and again
## whenever a scene is added after it (`SceneTree.change_scene_to_file` adds the new scene at the end), and then it is the first to
## hear every key. (`Window.window_input` is no way round this: the viewport clears "handled" right after that signal.)
##
## The Alt+Enter is swallowed completely (the press, its key repeat, and the release), so no screen reads it as an Enter. A
## plain Enter, or Enter with Ctrl / Shift / Meta, is none of our business. Settings in project.godot stay as they are (a
## 1280 x 800 window); this only switches the running window between `MODE_WINDOWED` and `MODE_FULLSCREEN`.

## Told after each switch, with the mode the window was asked for (tests listen: a headless window does not report its mode back).
signal fullscreen_toggled(mode: Window.Mode)


func _ready() -> void:
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)
	_move_to_end.call_deferred()


## True for Alt + Enter or Alt + keypad Enter, as a press, a key repeat or a release.
static func is_toggle_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	return key != null and key.keycode in [KEY_ENTER, KEY_KP_ENTER] and key.alt_pressed \
			and not key.ctrl_pressed and not key.meta_pressed and not key.shift_pressed


func _input(event: InputEvent) -> void:
	if not is_toggle_key(event):
		return
	get_viewport().set_input_as_handled()
	if event.is_pressed() and not event.is_echo():
		toggle_fullscreen()


## The mode a toggle leads to: fullscreen (or exclusive fullscreen) -> windowed, anything else (windowed, minimized) -> fullscreen.
static func mode_after(current: Window.Mode) -> Window.Mode:
	var is_fullscreen := current == Window.MODE_FULLSCREEN or current == Window.MODE_EXCLUSIVE_FULLSCREEN
	return Window.MODE_WINDOWED if is_fullscreen else Window.MODE_FULLSCREEN


func toggle_fullscreen() -> void:
	var window := get_window()
	var to_mode := mode_after(window.mode)
	window.mode = to_mode
	fullscreen_toggled.emit(to_mode)


func _on_root_child_entered(_node: Node) -> void:
	_move_to_end.call_deferred()       # (not now: the root is still busy adding that child)


func _move_to_end() -> void:
	var root := get_tree().root
	if get_parent() == root and get_index() != root.get_child_count() - 1:
		root.move_child(self, root.get_child_count() - 1)
