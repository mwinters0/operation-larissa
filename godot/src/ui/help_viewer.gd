class_name HelpViewer
extends Control
## The Help window: one topic, paged with "Go Back a Page" / "See Next Page" / "Done".
##
## Teaches: a small modal dialog scene. It dims the screen, takes the keyboard (PageUp / PageDown turn the
## pages, Escape closes, Enter presses the highlighted button) and reports back with one signal, `closed`. All
## looks come from the project Theme; the words are the original's (`HelpTopics`).
##
## The buttons follow the original's `RunPagedDialog` (0x417755): a one-page topic shows only "Done"; the first page of a
## longer topic only "See Next Page"; a middle page "Go Back a Page" + "See Next Page"; the last page "Go Back a Page" +
## "Done". The highlighted button is the first one on page 1 and the right one on every other page, so Enter on a
## page that is not the last goes on to the next page and only the last page's Enter closes the topic.

signal closed

var topic: int = 0
var page: int = 0
var _pages: PackedStringArray = PackedStringArray()

@onready var title_label: Label = %Title
@onready var body: RichTextLabel = %Body
@onready var page_label: Label = %PageNumber
@onready var back_button: Button = %Back
@onready var next_button: Button = %Next
@onready var done_button: Button = %Done


func _ready() -> void:
	back_button.text = Catalog.text(&"help_back_button")
	next_button.text = Catalog.text(&"help_next_button")
	done_button.text = Catalog.text(&"help_done_button")
	back_button.pressed.connect(show_page.bind(-1, true))
	next_button.pressed.connect(show_page.bind(1, true))
	done_button.pressed.connect(close)
	_refresh()


## Shows topic `index` (0-6, the Help menu's order) from its first page. In Math Practice (`practice`) the menu
## has two topics: 0 = Math Practice, 1 = About.
func show_topic(index: int, practice: bool = false) -> void:
	topic = index
	_pages = HelpTopics.pages(index, practice)
	title_label.text = Catalog.text(&"practice_help_menu_items" if practice else &"help_menu_items").split("\n")[index]
	page = 0
	_refresh()


## Turns the page: to page number `target`, or (relative) by `target` pages.
func show_page(target: int, relative: bool = false) -> void:
	page = clampi(page + target if relative else target, 0, maxi(_pages.size() - 1, 0))
	_refresh()


func page_count() -> int:
	return _pages.size()


func _refresh() -> void:
	body.text = _pages[page] if page < _pages.size() else ""
	body.scroll_to_line(0)
	page_label.text = "%d / %d" % [page + 1, maxi(_pages.size(), 1)]
	var first := page == 0
	var last := page >= _pages.size() - 1
	back_button.visible = not first
	next_button.visible = not last
	done_button.visible = last
	(done_button if last else next_button).grab_focus()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
	elif key == KEY_PAGEDOWN:
		get_viewport().set_input_as_handled()
		show_page(1, true)
	elif key == KEY_PAGEUP:
		get_viewport().set_input_as_handled()
		show_page(-1, true)
