class_name ModalHost
extends RefCounted
## The modal dialogs of one screen: the message box and every dialog the screen opens over itself. Each screen that shows dialogs
## (sign-in, Math Practice, the game, the Voyager closing) owns one, and opens every dialog through it.
##
## Teaches: keyboard focus as something a modal BORROWS and gives back. While anything is open, the screen's `frozen` nodes sleep:
## `process_mode = DISABLED` keeps their input handlers (and a problem screen's polling) from hearing the keys, and
## `focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED` takes their controls out of the focus chain, so the arrow keys and Tab
## stay inside the dialog. (Godot looks for the next control under the same top-level control: a dialog on its own `CanvasLayer` keeps
## the arrows anyway, one that shares its screen's root, as in Math Practice, needs this.) The frozen controls' focus behaviour does
## not reach the dialogs, which are not their children. When the top modal closes, the focus goes back to the control that had it
## when that modal opened, or to the screen's `home` control when that one is gone.
##
##     var modals := ModalHost.new(self, [tree, buttons], tree)
##     modals.attach(messages, message_view)               # the message box is a modal like the others
##     await modals.open(dialog, overlay)                  # returns when the dialog has left the tree
##
## A dialog closes by leaving the tree: it frees itself, or its screen frees it in the handler of its answer signal.

## One open modal and the focus owner it took over.
class Entry extends RefCounted:
	var focus: Object = null


var _screen: Node
var _frozen: Array[Node] = []
var _home: Control
var _open: Array[Entry] = []
var _message_entry: Entry = null
var _view: MessageBoxView


## `screen` is the scene that owns the dialogs; `frozen` are its nodes that sleep while a modal is open (they must be at their
## default `process_mode` and `focus_behavior_recursive`); `home` takes the focus back when the control that had it is gone.
func _init(screen: Node, frozen: Array[Node], home: Control = null) -> void:
	_screen = screen
	_frozen = frozen
	_home = home


## The message box shows `queue`'s messages; each message is a modal of this host while it is up.
func attach(queue: MessageQueue, view: MessageBoxView) -> void:
	_view = view
	view.queue = queue
	queue.message_shown.connect(_on_message_shown)


## True while a message or a dialog is open.
func is_open() -> bool:
	return not _open.is_empty()


## Adds `dialog` under `parent` (a `CanvasLayer` of the screen) as a modal, and returns once it has left the tree. `configure`
## runs once the dialog is in the tree (its `@onready` nodes exist only then). The dialog takes the focus itself when it opens.
func open(dialog: Control, parent: Node, configure: Callable = Callable()) -> void:
	var entry := _push()
	parent.add_child(dialog)
	if configure.is_valid():
		configure.call()
	await dialog.tree_exited
	_pop(entry)


func _on_message_shown(message: MessageQueue.Message) -> void:
	if message != null:
		if _message_entry == null:                       # (the next message of the queue keeps the focus owner of the first)
			_message_entry = _push()
		_view.show_message(message)
		return
	_view.show_message(null)
	if _message_entry != null:
		var entry := _message_entry
		_message_entry = null
		_pop(entry)


func _push() -> Entry:
	var entry := Entry.new()
	if _screen.is_inside_tree():
		entry.focus = _screen.get_viewport().gui_get_focus_owner()
	if _open.is_empty():
		for node in _frozen:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is Control:
				(node as Control).focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_open.append(entry)
	return entry


## A modal closed. Only the TOP one gives the focus back: one that closes under another (a dialog freed while the message it
## posted is up) leaves the focus to the one above it.
func _pop(entry: Entry) -> void:
	var was_top: bool = not _open.is_empty() and _open.back() == entry
	_open.erase(entry)
	if _open.is_empty():
		for node: Variant in _frozen:
			if is_instance_valid(node):
				(node as Node).process_mode = Node.PROCESS_MODE_INHERIT
				if node is Control:
					(node as Control).focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	if not was_top or not is_instance_valid(_screen) or not _screen.is_inside_tree() or _screen.is_queued_for_deletion():
		return
	if _can_take_focus(entry.focus):
		(entry.focus as Control).grab_focus()
	elif _can_take_focus(_home):
		_home.grab_focus()


## (`control` is untyped: it may be a freed object, which a typed argument refuses.)
static func _can_take_focus(control: Variant) -> bool:
	if not is_instance_valid(control) or not control is Control:
		return false
	var c := control as Control
	if not c.is_inside_tree() or not c.is_visible_in_tree() or c.get_focus_mode_with_override() == Control.FOCUS_NONE:
		return false
	var node: Node = c
	while node != null:                                  # (a control of a dialog that is being freed)
		if node.is_queued_for_deletion():
			return false
		node = node.get_parent()
	return true
