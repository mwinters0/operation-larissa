class_name TestStoryTimelines
extends GdUnitTestSuite
## Teaches: a cutscene's choreography is data of a pack and can be checked as data: well formed, and every picture, text, frame and sound it names exists in the
## registry. The timelines the chain answers (`Catalog.story_timeline`, here the dev pack's own) are checked, and the scripts that are not timelines: the story pages, the
## Voyager's flight, the sailors of the Expert closing. (The original's numbers against its tables: tests/legacy/test_story_timelines_legacy.gd.)

const TIMELINES: Array[StringName] = [&"news_cartoon", &"news_ambient", &"title_ship", &"title_reveal", &"expert_hoist", &"expert_deck", &"expert_wait"]


func _all() -> Array[CutsceneTimeline]:
	var found: Array[CutsceneTimeline] = []
	for timeline_name in TIMELINES:
		found.append(Catalog.story_timeline(timeline_name))
	return found


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


# --- where they come from -----------------------------------------------------------------------------------

func test_every_timeline_and_script_is_the_dev_packs_when_nothing_is_laid_over_it() -> void:
	for timeline_name in TIMELINES:
		assert_object(Catalog.story_timeline(timeline_name)).is_same(Packs.dev().resource(Catalog.STORY_REL % timeline_name))
	assert_object(Catalog.story_script()).is_same(Packs.dev().resource(Catalog.STORY_REL % "story_script"))
	assert_object(Catalog.voyager_closing_script()).is_same(Packs.dev().resource(Catalog.STORY_REL % "voyager_closing_script"))
	assert_object(Catalog.closing_crew()).is_same(Packs.dev().resource(Catalog.STORY_REL % "closing_crew"))


# --- the scripts that are not timelines ----------------------------------------------------------------------

func test_the_story_pages_hold_and_name_pictures_that_exist() -> void:
	var script := Catalog.story_script()
	assert_int(script.pages.size()).is_greater(1)
	assert_int(script.pages.filter(func(page: StoryPage) -> bool: return page.last).size()).is_equal(1)
	assert_bool(script.pages[script.pages.size() - 1].last).is_true()
	assert_float(script.hold_ticks(0)).is_equal(script.minimum_page_ticks)
	assert_float(script.hold_ticks(script.pages.size() - 1)).is_equal(script.last_page_ticks)
	assert_float(script.last_page_ticks).is_greater(script.minimum_page_ticks)


## The flight of the Voyager closing is run for the place the sub is in when the finale starts: whatever cell it shows, the flight is a well formed timeline that
## ends in the event that brings the surface ship's pages and has the helicopter leave the screen.
func test_the_voyager_flight_is_a_timeline_for_every_cell_and_ends_with_the_pages() -> void:
	var script := Catalog.voyager_closing_script()
	for cell in script.turn_table.size():
		var flight := script.timeline(300, 250, cell)
		assert_array(Array(flight.problems())).is_empty()
		assert_bool(flight.cues.any(func(cue_entry: CutsceneCue) -> bool: return cue_entry.kind == CutsceneCue.EVENT and cue_entry.cue_name == &"pages")).is_true()
		var body := flight.find_track(&"helicopter", CutsceneTrack.PROP_POSITION)
		assert_float((body.values[body.values.size() - 1] as Vector2).x).is_less_equal(script.fly_until_x)


func test_the_sailors_of_the_deck_shot_are_six_programs_that_end_and_run() -> void:
	var crew := Catalog.closing_crew()
	assert_int(crew.scripts.size()).is_equal(6)
	assert_int(crew.start_x.size()).is_equal(6)
	assert_int(crew.start_y.size()).is_equal(6)
	for member in 6:
		var program := crew.scripts[member]
		assert_int(program.size() % ClosingCrewActor.RECORD_SIZE).is_equal(0)
		assert_int(program[program.size() - ClosingCrewActor.RECORD_SIZE]).is_equal(ClosingCrewActor.Op.END)
		var actor := ClosingCrewActor.new(crew, member)
		assert_int(actor.x).is_equal(crew.start_x[member])
		var drew := false
		for step in 3 * actor.record_count() * 4:                      # (a program restarts at its end: run it round a few times)
			actor.step()
			drew = drew or actor.visible
		assert_bool(drew).override_failure_message("sailor %d never draws" % member).is_true()
