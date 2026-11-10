class_name TestStoryTimelines
extends GdUnitTestSuite
## Teaches: a cutscene's timeline is data and can be checked as data: well formed, and every picture, text, frame and sound it names exists in the registry. The pack's
## news cartoon and the project's other timelines are checked. (Their numbers against the original's tables: tests/legacy/test_story_timelines_legacy.gd.)

## (The news cartoon is the pack's own; the other timelines are the project's, `res://data/story/`.)
var NEWS: CutsceneTimeline = load(Packs.path(NewsCartoon.TIMELINE_REL))
const AMBIENT := preload("res://data/story/news_ambient.tres")
const SHIP := preload("res://data/story/title_ship.tres")
const REVEAL := preload("res://data/story/title_reveal.tres")
const HOIST := preload("res://data/story/expert_hoist.tres")
const DECK := preload("res://data/story/expert_deck.tres")
const WAIT := preload("res://data/story/expert_wait.tres")
const STORY := preload("res://data/story/story_script.tres")
const VOYAGER := preload("res://data/story/voyager_closing_script.tres")

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

