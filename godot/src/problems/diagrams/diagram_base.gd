class_name DiagramBase
extends Control
## The diagram of a math problem: the original's panel picture with the problem's numbers
## drawn onto it (pictures stacked, needles, markers, printed values ...).
##
## Teaches: custom 2D drawing with `_draw()`, data-driven design (what to draw comes from a
## Dictionary the importer filled, `ProblemType.diagram`) and a base class that subclasses
## specialise by overriding `_build()`.
##
## HOW IT WORKS. `setup(problem)` calls `_build()`, which fills `items` (a list of
## `DiagramItem`: pictures, texts, rectangles); `_draw()` paints them. The tests read `items`.
## The default `_build()` understands the generic "items" list of the type's spec:
##
##   {"pic": 3, "pos": [x, y]}                   a picture of the type's art bundle at window pixels (x, y)
##   {"pic": ..., "flip": true}                  mirrored;  "flip_field": i  mirrors when record field i is not 0
##   "pic" may also be {"field": i, "add": n}    picture number = field i + n
##                       or {"field": i, "table": [...]}   picture number looked up by field i
##   {"pic": 3, "pos": [x, y], "repeat": {"count": COUNT, "step": [dx, dy]}}   a column / row of copies
##   COUNT = {"field": i, "add": a, "divisor": d, "round": "floor"|"ceil", "extra": e}
##           = (field i + a) / d, rounded, + e;  "divisor_table": {"field": j, "table": [...]} picks d by field j
##   {"text": {"field": i}, "box": [x, w], "y": y}      field i printed centred in the box x .. x + w
##                  {"literal": "5000"} prints a fixed text;  "format": "int" cuts a number to a whole number
##                  "suffix": "°C" is appended;  "right": x  right-aligns the text at x instead of "box"
##   {"pos": [x, y], "lookup": {"field": i, "entries": [{"pic": 2, "pos": [x, y], "flip": true}, ...]}}
##                  one picture chosen by field i from a table ("divisor": d divides the value first,
##                  "exact": true draws nothing unless it divides evenly, "pre": "hour12" turns hhmm into an hour)
##   {..., "when": {"levels": [0, 2]}}  or  {"field": i, "eq"|"ne"|"lt"|"ge": v}   draw only if it applies
##   {..., "animate": true}                      this entry appears step by step in the build-up animation (see below)
##
## ANIMATIONS (DESIGN 5.5). The original does not show a diagram at once: its `Prob*_Diagram` function draws, plays a
## sound and waits (`DelayTicks`) between the steps, and after a right answer `ShowSuccessMessage` replays a second
## animation for a few types. The port keeps the picture (`items`) as the END state and describes each animation as a
## `DiagramTimeline` (`intro`, `success_replay`). Who owns the CLOCK matters: the timeline says how many ticks the animation takes
## (`intro_length()`, `success_replay_length()`), the step machine (`ProblemFlow`) counts them and the screen tells the diagram where it is
## (`animate_to(tick)`); the diagram only shows what belongs to that tick. `play_intro()` / `play_success_replay()` are for tools and tests
## that have no step machine: they count the ticks themselves. The type's spec says how:
##   "intro": {"mode": "sequence"|"bars"|"lockstep"|"run", "sfx": id, "interval": ticks, ...}  groups = the "animate" entries
##        sequence: one group per `interval` ticks;  bars: the copies of a group one by one, `gap` ticks between groups;
##        lockstep: copy i of every group together;  run: one sound for the whole run of copies, `lead` ticks first, `trail` after
##   "success": {"mode": "overlay"|"thermometer"|"heading"|"pictures"|"needle", ...}  see `_schedule_success_replay()`
## Families with their own drawing code (`PieDiagram`, `TankDiagram`, `BarnacleDiagram` ...) mark their groups with `_end_group()`.
##
## Families with more to do (`PieDiagram`, `LineGraphDiagram` ...) override `_build()` and add
## items by code; `DiagramFactory.create()` picks the class from the spec's "family".

## A sound effect starts (its `sound` name). `ProblemScreen` forwards it to the `Audio` autoload. (The plans of the diagrams hold the
## original's sound numbers, as the importer read them; `_run_step` gives the number its name.)
signal sfx_requested(sfx: StringName)
## The original's `StopCommonSoundEffect`: the effect that is still sounding is cut off.
signal sfx_stop_requested
## An animation started by `play_intro()` / `play_success_replay()` reached its end (or was skipped).
signal animation_finished

## The window the original draws into.
const WINDOW_SIZE := Vector2(640, 400)

var type: ProblemType
var problem: ProblemInstance
var record: ProblemRecord
var level: int = 0
## The attempts so far (the flow's session), set by the screen right after the diagram is made: a picture reads it, never writes (`ModDiagram` tells a script which try the player is on). Null in a diagram made on its own.
var session: ProblemSession
var spec: Dictionary = {}
var layout: ProblemScreenLayout
var font: Font
var font_size: int = 17
var items: Array[DiagramItem] = []
var _textures: Array[Texture2D] = []
## The build-up animation (tick by tick) and the replay after a right answer; empty timelines for most types.
var intro: DiagramTimeline = DiagramTimeline.new()
var success_replay: DiagramTimeline = DiagramTimeline.new()
## What `_draw()` paints: `items` normally, the items of the current step while an animation runs.
var _shown: Array[DiagramItem] = []
var _groups: Array = []
var _collecting: bool = false
var _playing: bool = false
var _playing_timeline: DiagramTimeline
var _keeps_last_step: bool = false
var _next_step: int = 0                       # the first step of the playing timeline that has not been shown yet
var _own_clock: TickMeter                       # only while `play_intro()` / `play_success_replay()` count the ticks themselves
var _own_tick: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = WINDOW_SIZE
	custom_minimum_size = WINDOW_SIZE
	set_process(false)                          # only a diagram that counts its own ticks needs `_process`


## What the player has typed so far changed (`text` is what the calculator or the answer box shows). A diagram whose picture does not depend on the entry ignores it; `ModDiagram` does not.
func entry_changed(_text: String) -> void:
	pass


## The step of the problem changed. Ignored by a diagram whose picture does not depend on it; `ModDiagram` does not ignore it.
func step_changed(_step: ProblemFlow.Step) -> void:
	pass


## Something happened on the screen (`ProblemEvents`: started, step, verdict, damage, success, timeout), told by the screen after the flow decided it, in the order it happened. The one place a diagram hears them; no family needs one for its
## own picture (the build-up and the replay start from the flow's steps, with the lengths of data), `ModDiagram` hands them to its script.
func told(_event: Array) -> void:
	pass


## Builds the drawing for `new_problem` (a `ProblemInstance`) and shows it.
func setup(new_problem: ProblemInstance) -> void:
	problem = new_problem
	type = new_problem.type
	record = new_problem.record
	level = new_problem.level
	spec = type.diagram
	layout = Catalog.screen_layout()
	font = layout.make_font()
	font_size = layout.font_size()
	_textures.clear()
	for path in type.art_files:
		_textures.append(Assets.texture_at(path))          # (the skin's picture for the file, else the file)
	_end_animation_clock()
	items.clear()
	_groups.clear()
	_collecting = true
	_build()
	_collecting = false
	intro = _schedule_intro()
	success_replay = _schedule_success_replay()
	_groups.clear()
	_shown = items
	queue_redraw()


## Fills `items`. Subclasses override this (and usually call `add_spec_items` first).
func _build() -> void:
	add_spec_items(spec.get("items", []))


func _draw() -> void:
	for item in _shown:
		match item.kind:
			DiagramItem.Kind.PICTURE:
				_draw_picture(item)
			DiagramItem.Kind.TEXT:
				_draw_text(item)
			DiagramItem.Kind.RECT:
				draw_rect(Rect2(item.position, item.size), item.color)


func _draw_picture(item: DiagramItem) -> void:
	if item.flip:
		# mirror left to right around the picture's own centre line: scale x by -1 about its right edge, then draw as usual
		draw_set_transform(item.position + Vector2(item.texture.get_width(), 0.0), 0.0, Vector2(-1.0, 1.0))
		draw_texture(item.texture, Vector2.ZERO)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture(item.texture, item.position)


## The original calls TextOut(x, y): `y` is the top of the line, so the baseline is one ascent lower.
func _draw_text(item: DiagramItem) -> void:
	var width := font.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := item.position.x
	match item.align:
		DiagramItem.Align.CENTER:
			x += int((item.anchor_width - width) / 2.0)        # integer maths like the original's (box - width) >> 1
		DiagramItem.Align.RIGHT:
			x -= width
		DiagramItem.Align.MIDDLE:
			x -= width / 2.0
	var baseline := Vector2(x, item.position.y + font.get_ascent(font_size))
	draw_string(font, baseline, item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, item.color)


# --- building blocks for subclasses -------------------------------------------------------

## Adds picture number `pic` of the type's art bundle with its top-left corner at `at`.
func add_picture(pic: int, at: Vector2, flip: bool = false) -> DiagramItem:
	var item := DiagramItem.new()
	item.kind = DiagramItem.Kind.PICTURE
	item.pic = pic
	item.texture = _textures[pic]
	item.position = at
	item.flip = flip
	items.append(item)
	return item


## Adds `text` (white unless `color_index` says otherwise). With `box_width` > 0 it is centred in
## the box that starts at `at.x`; with `right_aligned` it ends at `at.x`.
func add_text(text: String, at: Vector2, box_width: float = 0.0, right_aligned: bool = false, color_index: int = 15) -> DiagramItem:
	var item := DiagramItem.new()
	item.kind = DiagramItem.Kind.TEXT
	item.text = text
	item.position = at
	item.anchor_width = box_width
	if right_aligned:
		item.align = DiagramItem.Align.RIGHT
	elif box_width > 0.0:
		item.align = DiagramItem.Align.CENTER
	item.color = layout.color(color_index)
	items.append(item)
	return item


## Adds `text` centred on the point `centre` (the x of `centre`; its y is the top of the line). Where the text starts depends on
## the font, so the item keeps the point and `_draw_text` centres it.
func add_centred_text(text: String, centre: Vector2, color_index: int = 15) -> DiagramItem:
	var item := add_text(text, centre, 0.0, false, color_index)
	item.align = DiagramItem.Align.MIDDLE
	return item


## Adds a filled rectangle (`color_index` is the original's SetColor number).
func add_rect(rect: Rect2, color_index: int) -> DiagramItem:
	var item := DiagramItem.new()
	item.kind = DiagramItem.Kind.RECT
	item.position = rect.position
	item.size = rect.size
	item.color = layout.color(color_index)
	items.append(item)
	return item


## All picture items showing picture `pic`.
func pictures(pic: int) -> Array[DiagramItem]:
	var found: Array[DiagramItem] = []
	for item in items:
		if item.kind == DiagramItem.Kind.PICTURE and item.pic == pic:
			found.append(item)
	return found


## Every text item's string, in drawing order.
func texts() -> PackedStringArray:
	var found := PackedStringArray()
	for item in items:
		if item.kind == DiagramItem.Kind.TEXT:
			found.append(item.text)
	return found


# --- animations ------------------------------------------------------------------------------

## How many ticks the build-up takes (`DiagramTimeline.end_tick`: when the original's drawing function returns, i.e. when the prompt
## appears). The step machine counts that many and is the authority; a diagram without a build-up says 0.
func intro_length() -> int:
	return intro.end_tick


## How many ticks the replay after a right answer takes (0 if the type has none).
func success_replay_length() -> int:
	return success_replay.end_tick


## Starts the build-up at tick 0: what happens at tick 0 shows in the very first frame. The owner then calls `animate_to` with the
## tick it is at, as time goes by. Does nothing for a diagram that is drawn at once.
func begin_intro() -> void:
	begin_animation(intro, false)


## Starts the replay of the right answer (`ShowSuccessMessage`, types 6, 11, 12, 16, 22, 23, 26, 27); it keeps its last picture.
func begin_success_replay() -> void:
	begin_animation(success_replay, true)


func begin_animation(timeline: DiagramTimeline, keeps_last_step: bool) -> void:
	_end_animation_clock()
	if timeline.is_empty():
		return
	_playing = true
	_playing_timeline = timeline
	_keeps_last_step = keeps_last_step
	_next_step = 0
	animate_to(0)


## The animation is `tick` ticks old: shows every step that is due by now (each once, in order, with its sound). At the timeline's
## end tick the animation is over (`animation_finished`). A tick is never missed, whatever the frame rate.
func animate_to(tick: int) -> void:
	if not _playing:
		return
	var steps := _playing_timeline.steps
	while _next_step < steps.size() and steps[_next_step].tick <= tick:
		_apply_step(steps[_next_step])
		_next_step += 1
	if tick >= _playing_timeline.end_tick:
		_finish(_keeps_last_step)


## Runs the build-up on its OWN clock and returns when it is over: for tools and tests that have no step machine (the debug menu,
## screenshots). `ProblemScreen` does not use it: there the step machine owns the length.
func play_intro() -> void:
	await _play(intro, false)


## Replays the right answer on its own clock (see `play_intro`). Returns when it is over.
func play_success_replay() -> void:
	await _play(success_replay, true)


## True for the types whose diagram builds up in front of the player.
func has_intro() -> bool:
	return not intro.is_empty()


## True for the types that have a success animation.
func has_success_replay() -> bool:
	return not success_replay.is_empty()


func is_playing() -> bool:
	return _playing


## Jumps to the end of the running animation (silently): the debug screenshots and the tests use it. The step machine hears
## `animation_finished` and ends the build-up or the replay at once.
func skip_animation() -> void:
	if not _playing:
		return
	_end_animation_clock()
	sfx_stop_requested.emit()
	_finish()


func _play(timeline: DiagramTimeline, keeps_last_step: bool) -> void:
	if timeline.is_empty() or not is_inside_tree():
		_end_animation_clock()
		return
	begin_animation(timeline, keeps_last_step)
	if not _playing:
		return                                      # (everything happened at tick 0)
	_own_clock = TickMeter.new()
	_own_tick = 0
	set_process(true)
	await animation_finished


func _process(delta: float) -> void:
	if _own_clock == null:
		return
	var whole := _own_clock.feed(delta)
	if whole > 0:
		_own_tick += whole
		animate_to(_own_tick)


func _end_animation_clock() -> void:
	_own_clock = null
	set_process(false)


func _apply_step(step: DiagramStep) -> void:
	_shown = step.items
	if step.stop_sfx:
		sfx_stop_requested.emit()
	if step.sfx >= 0:
		sfx_requested.emit(Catalog.sfx_catalog().name_of(step.sfx))
	queue_redraw()


## The animation is over: the intro ends in the end state (`items`), the success replay keeps its last picture.
func _finish(keeps_last_step: bool = false) -> void:
	_end_animation_clock()
	_playing = false
	if keeps_last_step and not _playing_timeline.steps.is_empty():
		_shown = _playing_timeline.steps.back().items
	else:
		_shown = items
	queue_redraw()
	animation_finished.emit()


## Marks the items added since `from_index` as one animation group (they appear together).
func _end_group(from_index: int) -> void:
	if _collecting:
		_groups.append(items.slice(from_index))


## Builds items with the given Callable without touching `items`, and returns them.
func _aside(build: Callable) -> Array[DiagramItem]:
	var saved := items
	var made: Array[DiagramItem] = []
	items = made
	build.call()
	items = saved
	return made


## The picture of one animation frame: the panel (first entry of the spec) plus whatever `build` adds.
func _frame(build: Callable) -> Array[DiagramItem]:
	return _aside(func() -> void:
		add_spec_items([spec["items"][0]])
		build.call())


## Builds the intro timeline. Subclasses with their own sequence override this.
func _schedule_intro() -> DiagramTimeline:
	var plan: Dictionary = spec.get("intro", {})
	if plan.is_empty() or _groups.is_empty():
		return DiagramTimeline.new()
	var events := []
	var end := 0
	var interval: int = plan["interval"]
	var sfx: int = plan.get("sfx", -1)
	match plan["mode"]:
		"sequence":
			for i in _groups.size():
				events.append(_event(i * interval, _groups[i], sfx))
			end = (_groups.size() if plan.get("trailing", true) else _groups.size() - 1) * interval
		"bars":
			var tick := 0
			for bar in _groups.size():
				for item: DiagramItem in _groups[bar]:
					events.append(_event(tick, [item], sfx))
					tick += interval
				if bar < _groups.size() - 1:
					tick += int(plan["gap"])
			end = tick
		"lockstep":
			var longest := 0
			for group: Array in _groups:
				longest = maxi(longest, group.size())
			for i in longest:
				var together := []
				for group: Array in _groups:
					if i < group.size():
						together.append(group[i])
				events.append(_event(i * interval, together, sfx))
			end = longest * interval
		"run":
			var run: Array = _groups[0]
			var lead: int = plan["lead"]
			events.append(_event(lead, run.slice(0, 1), sfx))
			for i in range(1, run.size()):
				events.append(_event(lead + i * interval, [run[i]]))
			var stop_at := lead + run.size() * interval
			events.append(_event(stop_at, [], -1, true))
			end = stop_at + int(plan["trail"])
		_:
			push_error("DiagramBase: unknown intro mode '%s'" % plan["mode"])
	return _assemble(events, end)


## One keyframe for `_assemble`: at `tick` the `reveal` items appear.
static func _event(tick: int, reveal: Array, sfx: int = -1, stop_sfx: bool = false) -> Dictionary:
	return {"tick": tick, "reveal": reveal, "sfx": sfx, "stop": stop_sfx}


## Turns keyframes into a timeline: every item that belongs to a group stays hidden until its event, the others (the panel ...) are
## there from tick 0. The picture of each step keeps the drawing order of `items`.
func _assemble(events: Array, end_tick: int) -> DiagramTimeline:
	var timeline := DiagramTimeline.new()
	var hidden := {}
	for group: Array in _groups:
		for item: DiagramItem in group:
			hidden[item] = true
	if events.is_empty() or events[0]["tick"] > 0:
		timeline.add_step(0, _without(hidden))
	for event: Dictionary in events:
		for item: DiagramItem in event["reveal"]:
			hidden.erase(item)
		timeline.add_step(event["tick"], _without(hidden), event["sfx"], event["stop"])
	timeline.end_tick = maxi(timeline.end_tick, end_tick)
	return timeline


func _without(hidden: Dictionary) -> Array[DiagramItem]:
	var visible: Array[DiagramItem] = []
	for item in items:
		if not hidden.has(item):
			visible.append(item)
	return visible


## Builds the success replay timeline from the spec's "success" entry (types 6, 11, 12, 16, 22, 23, 26, 27).
func _schedule_success_replay() -> DiagramTimeline:
	var plan: Dictionary = spec.get("success", {})
	var timeline := DiagramTimeline.new()
	match plan.get("mode", ""):
		"overlay":                                  # 6, 11, 16: the answer is written onto the picture, no sound, no delay
			var shown: Array[DiagramItem] = items.duplicate()
			shown.append_array(_aside(func() -> void: add_spec_items(plan["items"])))
			timeline.add_step(0, shown)
		"thermometer":                              # 12: the mercury moves from the question's temperature to the answer
			_success_thermometer(plan, timeline)
		"heading":                                  # 22: the needle turns from the heading to the answer in 45 degree steps
			_success_heading(plan, timeline)
		"pictures":                                 # 23: two pictures after each other
			var flip := record.int_at(plan["flip_field"]) != 0
			for frame: Dictionary in plan["frames"]:
				timeline.add_step(frame["tick"], _frame(func() -> void:
						add_picture(frame["pic"], vector(plan["pos"]), flip)), plan["sfx"])
			timeline.end_tick = plan["end"]
		"needle":                                   # 26, 27: the needle moves one step per `interval`
			_success_needle(plan, timeline)
	return timeline


## AnimateThermometerSolution (0x41f8e3) and AnimateThermometerColumn (0x41f813).
func _success_thermometer(plan: Dictionary, timeline: DiagramTimeline) -> void:
	var from := record.int_at(plan["from_field"])
	var to := record.int_at(plan["to_field"])
	var divisor: int = plan["divisor"]
	@warning_ignore("integer_division")
	var top_pieces := (from + int(plan["offset"])) / divisor           # pieces above the bulb piece
	@warning_ignore("integer_division")
	var moved := absi((to - from) / divisor)
	var rising := from < to
	var piece_count := moved + 1 if rising else moved                  # a rising column starts by redrawing its top piece
	var x: int = plan["x"]
	var top_y: int = int(plan["y0"]) - int(plan["step"]) * top_pieces
	var lead: int = plan["lead"]
	var interval: int = plan["interval"]
	var shown: Array[DiagramItem] = items.duplicate()
	timeline.add_step(0, shown.duplicate())
	if piece_count == 0:
		timeline.add_step(lead, shown.duplicate(), plan["sfx"])
	for i in piece_count:
		var piece_y: int = top_y - int(plan["step"]) * i if rising else top_y + int(plan["step"]) * i
		var picture: int = plan["rise_pic"] if rising else plan["erase_pic"]
		shown.append_array(_aside(func() -> void: add_picture(picture, Vector2(x, piece_y))))
		timeline.add_step(lead + i * interval, shown.duplicate(), plan["sfx"] if i == 0 else -1)
	var stop_at := lead + piece_count * interval
	timeline.add_step(stop_at, shown.duplicate(), -1, true)
	timeline.end_tick = stop_at + int(plan["trail"])


## Prob22_SuccessAnimation (0x42108d): at least one picture, then up to the answer (8 positions around the dial at most).
func _success_heading(plan: Dictionary, timeline: DiagramTimeline) -> void:
	var angle := record.int_at(plan["start_field"])
	var turn: int = int(plan["angle_step"]) * (1 if record.int_at(plan["direction_field"]) != 0 else -1)
	var target := record.int_at(plan["end_field"])
	var needle: Dictionary = spec["items"][1]
	var entries: Array = needle["lookup"]["entries"]
	var tick := 0
	for _guard in entries.size() + 1:
		angle += turn
		if angle > 359:
			angle = 0
		if angle < 0:
			angle = plan["wrap_to"]
		@warning_ignore("integer_division")
		var chosen: Dictionary = entries[clampi(angle / int(plan["angle_step"]), 0, entries.size() - 1)]
		timeline.add_step(tick, _frame(func() -> void:
				add_picture(chosen["pic"], vector(needle["pos"]), chosen.get("flip", false))), plan["sfx"])
		tick += int(plan["interval"])
		if angle == target:
			break
	timeline.end_tick = tick + int(plan["trail"])


## Prob26_SuccessAnimation (0x4317d4) / Prob27_SuccessAnimation (0x42f398): the needle table is the one of the diagram.
func _success_needle(plan: Dictionary, timeline: DiagramTimeline) -> void:
	var entries: Array = spec["items"][1]["lookup"]["entries"]
	var start := record.int_at(plan["start_field"])
	var count := record.int_at(plan["count_field"])
	for k in count + 1:
		var chosen: Dictionary = entries[clampi(start + int(plan["direction"]) * k, 0, entries.size() - 1)]
		timeline.add_step(k * int(plan["interval"]), _frame(func() -> void:
				add_picture(chosen["pic"], vector(chosen["pos"]), chosen.get("flip", false))),
				plan["sfx"] if k > 0 else -1)
	timeline.end_tick = (count + 1) * int(plan["interval"])


# --- the generic "items" vocabulary ---------------------------------------------------------

func add_spec_items(entries: Array) -> void:
	for entry: Dictionary in entries:
		if not _applies(entry.get("when", {})):
			continue
		var first := items.size()
		if entry.has("text"):
			_add_text_entry(entry)
		elif entry.has("lookup"):
			_add_lookup_entry(entry)
		elif entry.has("repeat"):
			var at := vector(entry["pos"])
			var step := vector(entry["repeat"]["step"])
			var pic := _picture_number(entry["pic"])
			for i in count_of(entry["repeat"]["count"]):
				add_picture(pic, at + step * i, _flipped(entry))
		else:
			add_picture(_picture_number(entry["pic"]), vector(entry["pos"]), _flipped(entry))
		if entry.get("animate", false):
			_end_group(first)


func _add_text_entry(entry: Dictionary) -> void:
	var source: Dictionary = entry["text"]
	var text: String
	if source.has("literal"):
		text = source["literal"]
	elif source.get("format", "number") == "int":
		text = str(record.int_at(source["field"]))
	else:
		text = record.number_at(source["field"]).to_text()
	text += source.get("suffix", "")
	var y: float = entry["y"]
	if entry.has("right"):
		add_text(text, Vector2(entry["right"], y), 0.0, true)
	else:
		add_text(text, Vector2(entry["box"][0], y), entry["box"][1])


func _add_lookup_entry(entry: Dictionary) -> void:
	var lookup: Dictionary = entry["lookup"]
	var value := record.int_at(lookup["field"])
	if lookup.get("pre", "") == "hour12":
		value = hour_on_12_hour_clock(value)
	var divisor: int = lookup.get("divisor", 1)
	if lookup.get("exact", false) and value % divisor != 0:
		return
	var entries: Array = lookup["entries"]
	@warning_ignore("integer_division")
	var chosen: Dictionary = entries[clampi(value / divisor, 0, entries.size() - 1)]
	var at := vector(chosen["pos"]) if chosen.has("pos") else vector(entry["pos"])
	add_picture(chosen["pic"], at, chosen.get("flip", false))


## hhmm on a 24 hour clock -> the hour hand's position on the 12 hour dial (the minutes are ignored,
## like the original does): 1800 -> 6, 2400 -> 12, 100 -> 1.
static func hour_on_12_hour_clock(hhmm: int) -> int:
	@warning_ignore("integer_division")
	return (hhmm if hhmm <= 1200 else hhmm - 1200) / 100


## Does a "when" condition hold for this level and record?
func _applies(when: Dictionary) -> bool:
	if when.has("levels") and not level in when["levels"]:
		return false
	if when.has("field"):
		var value := record.int_at(when["field"])
		if when.has("eq") and value != when["eq"]:
			return false
		if when.has("ne") and value == when["ne"]:
			return false
		if when.has("lt") and value >= when["lt"]:
			return false
		if when.has("ge") and value < when["ge"]:
			return false
	return true


## How many copies a "repeat" draws, see the vocabulary at the top.
func count_of(expression: Dictionary) -> int:
	var value: int = record.int_at(expression["field"]) + int(expression.get("add", 0))
	var divisor: int = expression.get("divisor", 1)
	if expression.has("divisor_table"):
		var by: Dictionary = expression["divisor_table"]
		divisor = by["table"][record.int_at(by["field"])]
	@warning_ignore("integer_division")
	var count := (value + divisor - 1) / divisor if expression.get("round", "floor") == "ceil" else value / divisor
	return maxi(0, count + int(expression.get("extra", 0)))


## A picture number: a plain int, or computed from a record field.
func _picture_number(source: Variant) -> int:
	if source is Dictionary:
		var value := record.int_at(source["field"])
		if source.has("table"):
			return source["table"][value]
		return value + int(source.get("add", 0))
	return source


func _flipped(entry: Dictionary) -> bool:
	if entry.has("flip_field"):
		return record.int_at(entry["flip_field"]) != 0
	return entry.get("flip", false)


## [x, y] from the JSON as a Vector2.
static func vector(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])


