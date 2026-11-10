class_name TestStoryTimelinesLegacy
extends GdUnitTestSuite
## (The legacy half: the original's tables. Well-formedness of every timeline: tests/engine/test_story_timelines.gd.)
## Teaches: checking generated data against its source, again. The cutscenes' timelines (`data/story/*.tres`) are produced by the
## importer from `docs/data/opening.json` (the opening's tables, decompiled from OPENING.C) and from the decompiled loops of
## CLOSING.C; these tests re-read the JSON and compare in GDScript, with their own small copy of the rules (a crew member's
## script repeats, only the man on the left walks), so a mistake in the Python cannot make its own test agree. The sailors of the
## Expert closing are checked against `ClosingCrewActor`, the GDScript twin of the importer's interpreter.
##
## (Lengths and the moments of every cutscene as they were before the timelines became data: `test_cutscene_timing.gd`.)

## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py)") -> void:
	pass


## (The news cartoon is made of the game's text, so it is the legacy pack and loaded, not preloaded: this file compiles without the game.)
var NEWS: CutsceneTimeline = load(LegacyPack.ROOT + "data/story/news_cartoon.tres") if FileAccess.file_exists(LegacyPack.ROOT + "data/story/news_cartoon.tres") else null
const AMBIENT := preload("res://data/story/news_ambient.tres")
const SHIP := preload("res://data/story/title_ship.tres")
const REVEAL := preload("res://data/story/title_reveal.tres")
const HOIST := preload("res://data/story/expert_hoist.tres")
const DECK := preload("res://data/story/expert_deck.tres")
const WAIT := preload("res://data/story/expert_wait.tres")
const STORY := preload("res://data/story/story_script.tres")
const VOYAGER := preload("res://data/story/voyager_closing_script.tres")

var _json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/data/opening.json"))


## The `ui_picture` name of the original's picture number.
func _name(number: int) -> StringName:
	return StringName(NameRegistry.original().name_of(&"ui_picture", number))


## The value of `actor`'s `property` at `tick`: the last key at or before it (the player holds a value until the next key).
func _at(timeline: CutsceneTimeline, actor: StringName, property: StringName, tick: float) -> Variant:
	var track := timeline.find_track(actor, property)
	assert_object(track).is_not_null()
	var value: Variant = null
	for i in track.times.size():
		if track.times[i] <= tick + 1e-9:
			value = track.values[i]
	return value


func _all() -> Array[CutsceneTimeline]:
	return [NEWS, AMBIENT, SHIP, REVEAL, HOIST, DECK, WAIT]


# --- every timeline is well formed and names things that exist ---------------------------------------------

func test_every_timeline_is_well_formed() -> void:
	for timeline in _all():
		assert_array(Array(timeline.problems())).is_empty()
		assert_str(timeline.provenance).is_not_empty()


func test_every_name_in_the_timelines_exists() -> void:
	var registry := NameRegistry.original()
	for timeline in _all():
		for track in timeline.tracks:
			match track.property:
				CutsceneTrack.PROP_PICTURE:
					for value in track.values:
						assert_int(registry.index_of(&"ui_picture", String(value))).is_greater_equal(0)
						assert_object(Assets.ui_picture(value)).is_not_null()
				CutsceneTrack.PROP_TEXT:
					for value in track.values:
						if value != &"":
							assert_int(registry.index_of(&"text", String(value))).is_greater_equal(0)
				CutsceneTrack.PROP_FRAME:
					for value in track.values:
						if value is StringName:
							assert_int(registry.index_of(&"frame", String(value), 6)).is_greater_equal(0)
		for cue_entry in timeline.cues:
			if cue_entry.kind == CutsceneCue.SOUND:
				assert_int(registry.index_of(&"sound", String(cue_entry.cue_name))).is_greater_equal(0)


# --- the news cartoon --------------------------------------------------------------------------------------

func test_the_crew_scripts_are_the_decompiled_ones() -> void:
	var members: Array = _json.news_cartoon.crew.members
	assert_int(members.size()).is_equal(5)
	var step: float = _json.news_cartoon.redraw_ticks
	var calls := ceili(NEWS.length / step)
	for m in 5:
		var member: Dictionary = members[m]
		for call in range(int(member.first_call), calls + 1):
			var frame := _crew_frame(member, call)
			var tick := (call - 1) * step
			var actor := StringName("crew_%d" % m)
			assert_str(_at(NEWS, actor, CutsceneTrack.PROP_PICTURE, tick)).is_equal(_name(frame[0]))
			assert_bool(_at(NEWS, actor, CutsceneTrack.PROP_MIRROR, tick)).is_equal(frame[1] == 1)
		var first := NEWS.find_track(StringName("crew_%d" % m), CutsceneTrack.PROP_PICTURE)
		assert_float(first.times[0]).is_equal((int(member.first_call) - 1) * step)


## (picture, mirror, x) of crew member `member` in redraw `call` (1-based): the script repeats, and a walking member also moves
## on by the sum of `dx` of a whole cycle each time round (his x is not reset).
func _crew_frame(member: Dictionary, call: int) -> Array:
	var index: int = call - int(member.first_call)
	var cycle: Array = member.pictures
	var cycle_total := 0
	for entry: Array in cycle:
		cycle_total += int(entry[2])
	var x := int(member.x0) + (index / cycle.size()) * cycle_total
	for k in index % cycle.size() + 1:
		x += int(cycle[k][2])
	var entry: Array = cycle[index % cycle.size()]
	return [int(entry[0]), int(entry[1]), x]


func test_only_the_man_on_the_left_is_late_and_walks() -> void:
	var members: Array = _json.news_cartoon.crew.members
	for m in 4:
		assert_int(int(members[m].first_call)).is_equal(1)
		assert_object(NEWS.find_track(StringName("crew_%d" % m), CutsceneTrack.PROP_POSITION)).is_null()      # he stands still
	assert_int(int(members[4].first_call)).is_equal(220)
	var walk := NEWS.find_track(&"crew_4", CutsceneTrack.PROP_POSITION)
	var walker_visible := NEWS.find_track(&"crew_4", CutsceneTrack.PROP_VISIBLE)
	assert_float(walk.times[0]).is_equal(2190.0)                                      # call 220
	assert_bool(_at(NEWS, &"crew_4", CutsceneTrack.PROP_VISIBLE, 2189.0)).is_false()
	assert_float(walker_visible.times[0]).is_equal(0.0)
	var first: Vector2 = walk.values[0]
	assert_float(first.x).is_equal(0.0)
	assert_float(first.y).is_equal(350.0)
	assert_str(_at(NEWS, &"crew_4", CutsceneTrack.PROP_PICTURE, 2190.0)).is_equal(_name(1024))
	assert_bool(_at(NEWS, &"crew_4", CutsceneTrack.PROP_MIRROR, 2190.0)).is_true()
	assert_float((_at(NEWS, &"crew_4", CutsceneTrack.PROP_POSITION, 2200.0) as Vector2).x).is_equal(12.0)
	assert_float((_at(NEWS, &"crew_4", CutsceneTrack.PROP_POSITION, 2190.0 + 27 * 10) as Vector2).x).is_equal(324.0)      # 27 steps of 12 px
	assert_float((_at(NEWS, &"crew_4", CutsceneTrack.PROP_POSITION, 2190.0 + 69 * 10) as Vector2).x).is_equal(324.0)      # the pose part of the cycle
	assert_float((_at(NEWS, &"crew_4", CutsceneTrack.PROP_POSITION, 2190.0 + 70 * 10) as Vector2).x).is_equal(324.0)      # the script restarts, x is not reset
	assert_float((_at(NEWS, &"crew_4", CutsceneTrack.PROP_POSITION, 2190.0 + 97 * 10) as Vector2).x).is_equal(648.0)      # off the right edge ...
	assert_bool(_at(NEWS, &"crew_4", CutsceneTrack.PROP_VISIBLE, 2190.0 + 97 * 10)).is_false()                            # ... and no longer drawn


func test_the_trail_the_ring_and_the_alarm_gates_are_at_the_originals_calls() -> void:
	var step: float = _json.news_cartoon.redraw_ticks
	var trail: Dictionary = _json.news_cartoon.trail_and_ring
	for i in 21:
		var dot: Dictionary = trail.dots[i]
		var track := NEWS.find_track(StringName("dot_%02d" % i), CutsceneTrack.PROP_VISIBLE)
		assert_array(Array(track.times)).is_equal([0.0, (int(dot.call) - 1) * step])
	assert_array(Array(NEWS.find_track(&"ring", CutsceneTrack.PROP_VISIBLE).times)).is_equal([0.0, 2360.0])
	var gate: Dictionary = _json.news_cartoon.alarm_lights.gate_call
	assert_array(Array(NEWS.find_track(&"alarm_1", CutsceneTrack.PROP_VISIBLE).times)).is_equal([0.0, (int(gate.centre) - 1) * step])
	assert_array(Array(NEWS.find_track(&"alarm_0", CutsceneTrack.PROP_VISIBLE).times)).is_equal([0.0, (int(gate.outer) - 1) * step])
	assert_array(Array(NEWS.find_track(&"alarm_2", CutsceneTrack.PROP_VISIBLE).times)).is_equal([0.0, (int(gate.outer) - 1) * step])


func test_the_bulletins_are_typed_at_three_ticks_a_character_and_read_for_25_redraws() -> void:
	# the box is empty for 25 redraws (250 ticks); then each bulletin is typed and read for 250 ticks
	var text := NEWS.find_track(&"teletype", CutsceneTrack.PROP_TEXT)
	var reveal := NEWS.find_track(&"teletype", CutsceneTrack.PROP_REVEAL)
	assert_bool(reveal.smooth).is_true()
	assert_int(text.times.size()).is_equal(7)
	var at := 250.0
	for i in 6:
		assert_str(text.values[i + 1]).is_equal(StringName("news_bulletin_%d" % i))
		assert_float(text.times[i + 1]).is_equal(at)
		var typing := NewsCartoon.bulletin(i).length() * 3.0      # the characters the teletype shows, 3 ticks each
		assert_float(_at(NEWS, &"teletype", CutsceneTrack.PROP_REVEAL, at)).is_equal(0.0)
		var typed := reveal.times.find(at + typing)
		assert_int(typed).is_greater_equal(0)
		assert_float(reveal.values[typed]).is_equal(1.0)
		at += typing + 250.0
	assert_float(NEWS.length).is_equal(at)                    # the cartoon ends when the last bulletin has been read
	assert_float(NEWS.cues[0].tick).is_equal(NEWS.length)
	assert_str(NEWS.cues[0].cue_name).is_equal(&"end")
	assert_str(text.values[0]).is_equal(&"")
	# the original counts 98 characters in bulletin 0, the teletype shows the text without its blank at the edge (97)
	var counted := 0.0
	for bulletin: Dictionary in _json.news_cartoon.bulletins:
		counted += int(bulletin.typing_ticks)
	assert_float(counted - 1461.0).is_equal(0.0)
	assert_float(NEWS.length - (7 * 250.0 + counted)).is_between(-3.0, 0.0)


func test_the_ambient_loop_is_the_alarm_states_and_the_ring() -> void:
	var step: float = _json.news_cartoon.redraw_ticks
	assert_bool(AMBIENT.loop).is_true()
	assert_float(AMBIENT.length).is_equal(64.0 * step)
	var states: Dictionary = _json.news_cartoon.alarm_lights.state_to_picture
	var start: Dictionary = _json.news_cartoon.alarm_lights.start_state
	for side in 3:
		var first: int = start[["left", "centre", "right"][side]]
		for s in 64:
			var state: Dictionary = states[str((first + s) % 4)]
			var tick := s * step
			assert_str(_at(AMBIENT, StringName("alarm_%d" % side), CutsceneTrack.PROP_PICTURE, tick)).is_equal(_name(int(state.picture)))
			assert_bool(_at(AMBIENT, StringName("alarm_%d" % side), CutsceneTrack.PROP_MIRROR, tick)).is_equal(int(state.mirror) == 1)
	var ring: Array = _json.news_cartoon.trail_and_ring.ring_pictures
	for s in 64:
		assert_str(_at(AMBIENT, &"ring", CutsceneTrack.PROP_PICTURE, s * step)).is_equal(_name(int(ring[s % 4])))


# --- the title scene -----------------------------------------------------------------------------------------

func test_the_ship_table_matches_the_json() -> void:
	var frames: Array = _json.title_scene.frames
	assert_int(frames.size()).is_equal(163)
	assert_float(SHIP.length).is_equal(163.0 * 12.0)
	var size_x: int = _json.title_scene.sub.size[0]
	for r in 163:
		var f: Dictionary = frames[r]
		var tick := r * 12.0
		assert_vector(_at(SHIP, &"ship", CutsceneTrack.PROP_POSITION, tick)).is_equal(Vector2(int(f.hull.x), int(f.hull.y)))
		assert_str(_at(SHIP, &"radar", CutsceneTrack.PROP_PICTURE, tick)).is_equal(_name(int(f.radar.picture)))
		assert_bool(_at(SHIP, &"radar", CutsceneTrack.PROP_MIRROR, tick)).is_equal(int(f.radar.mirror) == 1)
		assert_str(_at(SHIP, &"hook", CutsceneTrack.PROP_PICTURE, tick)).is_equal(_name(int(f.hook.picture)))
		assert_vector(_at(SHIP, &"mini_sub", CutsceneTrack.PROP_POSITION, tick)).is_equal(Vector2(int(f.sub.x), int(f.sub.y)))
		assert_object(_at(SHIP, &"mini_sub", CutsceneTrack.PROP_CLIP, tick)).is_equal(Rect2(0, 0, size_x, int(f.sub.visible_rows)))
		assert_bool(_at(SHIP, &"mini_sub", CutsceneTrack.PROP_VISIBLE, tick)).is_equal(int(f.sub.visible_rows) > 0)
		assert_bool(_at(SHIP, &"spray", CutsceneTrack.PROP_VISIBLE, tick)).is_equal(f.spray != null)
		if f.spray != null:
			assert_str(_at(SHIP, &"spray", CutsceneTrack.PROP_PICTURE, tick)).is_equal(_name(int(f.spray.picture)))
			assert_vector(_at(SHIP, &"spray", CutsceneTrack.PROP_POSITION, tick)).is_equal(Vector2(int(f.spray.x), int(f.spray.y)))
		assert_bool(_at(SHIP, &"splash_left", CutsceneTrack.PROP_VISIBLE, tick)).is_equal(f.splash != null)
		assert_bool(_at(SHIP, &"splash_right", CutsceneTrack.PROP_VISIBLE, tick)).is_equal(f.splash != null)
		if f.splash != null:
			assert_str(_at(SHIP, &"splash_left", CutsceneTrack.PROP_PICTURE, tick)).is_equal(_name(int(f.splash.picture)))
	assert_int(SHIP.cues.size()).is_equal(1)
	assert_float(SHIP.cues[0].tick).is_equal(float(_json.title_scene.splash.sound_redraw) * 12.0)


func test_the_drop_in_the_table() -> void:
	# the hook opens in frames 68-71, the sub starts to fall in frame 69, the splash sound is in frame 73 and the
	# sub is gone (no rows left) from frame 81 on, while the ship keeps sailing
	for r in range(68, 72):
		assert_str(_at(SHIP, &"hook", CutsceneTrack.PROP_PICTURE, r * 12.0)).is_equal(_name(1032))
	assert_str(_at(SHIP, &"hook", CutsceneTrack.PROP_PICTURE, 67 * 12.0)).is_equal(_name(1031))
	assert_str(_at(SHIP, &"hook", CutsceneTrack.PROP_PICTURE, 72 * 12.0)).is_equal(_name(1031))
	var y68: float = _at(SHIP, &"mini_sub", CutsceneTrack.PROP_POSITION, 68 * 12.0).y
	var y69: float = _at(SHIP, &"mini_sub", CutsceneTrack.PROP_POSITION, 69 * 12.0).y
	assert_float(y69 - y68).is_equal(6.0)
	assert_float(y68).is_equal(_at(SHIP, &"mini_sub", CutsceneTrack.PROP_POSITION, 67 * 12.0).y)
	assert_float(SHIP.cues[0].tick).is_equal(73.0 * 12.0)
	assert_str(SHIP.cues[0].cue_name).is_equal(&"opening_scene")
	for r in range(81, 163):
		assert_bool(_at(SHIP, &"mini_sub", CutsceneTrack.PROP_VISIBLE, r * 12.0)).is_false()
	assert_bool(_at(SHIP, &"mini_sub", CutsceneTrack.PROP_VISIBLE, 80 * 12.0)).is_true()
	assert_float((_at(SHIP, &"ship", CutsceneTrack.PROP_POSITION, 162 * 12.0) as Vector2).x).is_greater(
			(_at(SHIP, &"ship", CutsceneTrack.PROP_POSITION, 100 * 12.0) as Vector2).x)
	assert_float((_at(SHIP, &"ship", CutsceneTrack.PROP_POSITION, 57 * 12.0) as Vector2).x).is_equal(56.0)
	assert_float((_at(SHIP, &"ship", CutsceneTrack.PROP_POSITION, 87 * 12.0) as Vector2).x).is_equal(56.0)
	for r in range(75, 80):
		assert_str(_at(SHIP, &"splash_left", CutsceneTrack.PROP_PICTURE, r * 12.0)).is_equal(_name(1034 + r - 75))


func test_the_reveal_holds_each_picture_for_292_ticks() -> void:
	var data: Dictionary = _json.reveal_and_prompt
	var hold := float(data.hold_ticks)
	assert_float(hold).is_equal(292.0)
	assert_dict(REVEAL.marks).is_equal({&"presents": 0.0, &"operation": hold, &"neptune": 2.0 * hold})
	# one sound before each picture, the prompt with the third
	var sounds: Array = []
	for cue_entry in REVEAL.cues:
		if cue_entry.kind == CutsceneCue.SOUND:
			sounds.append(cue_entry.tick)
			assert_str(cue_entry.cue_name).is_equal(&"opening_end")
		else:
			assert_str(cue_entry.cue_name).is_equal(&"prompt")
			assert_float(cue_entry.tick).is_equal(2.0 * hold)
	assert_array(sounds).is_equal([0.0, hold, 2.0 * hold])
	assert_bool(_at(REVEAL, &"presents", CutsceneTrack.PROP_VISIBLE, hold - 1.0)).is_true()
	assert_bool(_at(REVEAL, &"presents", CutsceneTrack.PROP_VISIBLE, hold)).is_false()          # erased as OPERATION appears
	assert_bool(_at(REVEAL, &"operation", CutsceneTrack.PROP_VISIBLE, hold)).is_true()
	assert_bool(_at(REVEAL, &"neptune", CutsceneTrack.PROP_VISIBLE, 2.0 * hold - 1.0)).is_false()
	assert_bool(_at(REVEAL, &"copyright", CutsceneTrack.PROP_VISIBLE, 2.0 * hold)).is_true()


# --- the Expert closing -------------------------------------------------------------------------------------

func test_the_deck_sailors_are_what_closing_crew_actor_draws() -> void:
	var crew := Catalog.closing_crew()
	var actors: Array[ClosingCrewActor] = []
	for n in 6:
		actors.append(ClosingCrewActor.new(crew, n))
	for step in 146:
		var tick := step * 18.0
		for n in 6:
			var actor := actors[n]
			actor.step()
			var name := StringName("crew_%d" % n)
			assert_bool(_at(DECK, name, CutsceneTrack.PROP_VISIBLE, tick)).is_equal(actor.visible)
			if actor.visible:
				assert_vector(_at(DECK, name, CutsceneTrack.PROP_POSITION, tick)).is_equal(Vector2(actor.x, actor.y))
				assert_str(_at(DECK, name, CutsceneTrack.PROP_PICTURE, tick)).is_equal(_name(actor.picture))
				assert_bool(_at(DECK, name, CutsceneTrack.PROP_MIRROR, tick)).is_equal(actor.mirrored)


func test_the_expert_stages_are_whole_steps_of_18_ticks() -> void:
	assert_float(HOIST.length).is_equal(55.0 * 18.0)
	assert_float(DECK.length).is_equal(146.0 * 18.0)
	assert_float(WAIT.length).is_equal(4.0 * 18.0)
	assert_bool(WAIT.loop).is_true()
	for timeline in [HOIST, DECK, WAIT]:
		for t in timeline.key_times():
			assert_float(fmod(t, 18.0)).is_equal(0.0)


# --- the story and the Voyager closing -----------------------------------------------------------------------------

func test_the_story_has_nine_pages_and_the_originals_holds() -> void:
	assert_int(STORY.pages.size()).is_equal(9)
	assert_float(STORY.minimum_page_ticks).is_equal(365.0)
	assert_float(STORY.last_page_ticks).is_equal(3285.0)
	for i in 8:
		assert_bool(STORY.pages[i].last).is_false()
		assert_float(STORY.hold_ticks(i)).is_equal(365.0)
	assert_bool(STORY.pages[8].last).is_true()
	assert_float(STORY.hold_ticks(8)).is_equal(3285.0)
	var rings := 0
	for page in STORY.pages:
		rings += int(page.ring)
	assert_int(rings).is_equal(1)
	assert_bool(STORY.pages[4].ring).is_true()
	for i in 9:
		assert_str(STORY.pages[i].caption).is_equal(_name(2056 + i))


func test_the_voyager_flight_depends_on_where_the_sub_is() -> void:
	# the helicopter leaves when x <= -136, 8 px a step: the farther right the sub starts, the longer the flight
	var near := VOYAGER.timeline(40, 300, 2)
	var far := VOYAGER.timeline(500, 300, 2)
	var steps_near := ceili((40 + 136) / 8.0)
	var steps_far := ceili((500 + 136) / 8.0)
	assert_float(far.length - near.length).is_equal((steps_far - steps_near) * 6.0)
	assert_array(Array(near.problems())).is_empty()
	assert_array(Array(far.problems())).is_empty()
	# a sub that already faces the turn's end cell does not turn; one that faces the other way takes steps to do it
	var facing := VOYAGER.timeline(300, 200, 2)
	var turning := VOYAGER.timeline(300, 200, 8)
	assert_float(turning.length - facing.length).is_greater(0.0)
	# the flash sound comes when the rise and the turn are over, the surge sound 36 ticks (three pictures of 12) later
	var sounds := []
	for cue_entry in facing.cues:
		if cue_entry.kind == CutsceneCue.SOUND:
			sounds.append(cue_entry.tick)
	assert_array(sounds).is_equal([18.0 * 6.0, 18.0 * 6.0 + 36.0])
	assert_str(facing.cues[0].cue_name).is_equal(&"closing_flash")
	assert_str(facing.cues[1].cue_name).is_equal(&"closing_surge")
	assert_str(facing.cues[2].cue_name).is_equal(&"pages")
	assert_float(facing.cues[2].tick).is_equal(facing.length - 14.6)
