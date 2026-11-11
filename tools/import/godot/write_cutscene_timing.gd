extends SceneTree
## Writes godot/tests/fixtures/cutscene_timing.json from the legacy pack's cutscene timelines: one SHA-256 of each cutscene's timing record
## (`CutsceneTimingRecord`), never a tick. The one writer of that fixture; run it only to move the reference (the pack is the importer's
## output from your copy of the game, so a different release or a patched copy writes different hashes).
## Run:  tools/godot.sh --headless --path godot -s ../tools/import/godot/write_cutscene_timing.gd
##
## Teaches: a one-off tool as a `SceneTree` script, and a fixture that proves a timeline without holding it (docs/port/FIDELITY.md,
## "Fixtures commit hashes, not bytes").

const FIXTURE := "res://tests/fixtures/cutscene_timing.json"
const STORY_DIR := "res://packs/legacy/data/story/"

## The timelines of data files, by the name the fixture uses.
const TIMELINES := ["title_ship", "title_reveal", "expert_hoist", "expert_deck", "expert_wait", "news_cartoon", "news_ambient"]

## The Voyager closing's flight depends on where the finale finds the sub: window x, y and the picture cell. Test inputs, ours.
const VOYAGER_STARTS := {
	"voyager_closing_a": [184, 212, 6],
	"voyager_closing_b": [500, 180, 0],
	"voyager_closing_c": [40, 300, 8],
	"voyager_closing_d": [300, 200, 2],
	"voyager_closing_e": [250, 100, 3],
}

const DOC := "One SHA-256 per cutscene of its timing record (CutsceneTimingRecord in tests/legacy/cutscene_timing_record.gd, tools/import/step_story.py timing_record): the length, whether it loops, every moment at which anything changes and every sound and event, in thousandths of a tick of the original's 73 Hz timer. It holds no tick: the original's cutscenes are its presentation and are not committed. Written by tools/import/godot/write_cutscene_timing.gd from the legacy pack, never by hand. The timelines of the legacy pack, the animations the scenes build from them (tests/legacy/test_cutscene_timing.gd) and the importer's own timelines (tools/import/test_story.py) must give these hashes. voyager_closing_* are the flight for the sub starting at window position (x, y) in cell c ('start')."


func _init() -> void:
	var cutscenes := {}
	for timeline_name: String in TIMELINES:
		var timeline: CutsceneTimeline = load(STORY_DIR + timeline_name + ".tres")
		cutscenes[timeline_name] = {"sha256": CutsceneTimingRecord.digest(CutsceneTimingRecord.of_timeline(timeline))}
	var script: VoyagerClosingScript = load(STORY_DIR + "voyager_closing_script.tres")
	for timeline_name: String in VOYAGER_STARTS:
		var start: Array = VOYAGER_STARTS[timeline_name]
		var timeline := script.timeline(start[0], start[1], start[2])
		cutscenes[timeline_name] = {"start": start, "sha256": CutsceneTimingRecord.digest(CutsceneTimingRecord.of_timeline(timeline))}
	var fixture := {"_doc": DOC, "ticks_per_second": int(CutsceneTimeline.TICKS_PER_SECOND), "cutscenes": cutscenes}
	var file := FileAccess.open(ProjectSettings.globalize_path(FIXTURE), FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture, " ", true) + "\n")
	file.close()
	print("cutscene timing: %d cutscenes written to %s" % [cutscenes.size(), FIXTURE])
	quit()
