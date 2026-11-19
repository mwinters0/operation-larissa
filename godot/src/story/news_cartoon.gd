class_name NewsCartoon
extends StorySegment
## The opening's first scene: a radar map of the Pacific, a control room with a worried crew, the falling space
## capsule, and the news bulletins typed out and read aloud ("RED ALERT... GALAXY SPACE CAPSULE HAS ALTERED ITS
## COURSE ..."). Original: the first loop of `OpeningSequence` (OPENING.C).
##
## Teaches: a cutscene whose choreography is DATA (`data/story/news_cartoon.tres`, a `CutsceneTimeline` of the pack; the legacy pack's is written by the importer from
## the original's tables) and whose stage is data too (`data/story/news_cartoon_stage.tres`, a `CutsceneStage`: which pictures stand where). The script asks `StageBuilder` for the
## nodes, which tells a `CutsceneCast` which node plays which actor ("crew_4" is the `Crew4` sprite), and has `Cutscene.animation()` turn the timeline into `Animation`s. There are
## TWO `AnimationPlayer`s, because one player plays one animation at a time:
##
##   * `Ambient` loops forever: the alarm lights, the pulsing radar ring and the flickering console lights (`news_ambient.tres`; the lights' flicker is random in the original and is ours:
##     the importer and the dev pack's generator bake it into the file, so a pack's own cartoon flickers as its timeline says);
##   * `Script` plays once: the capsule's dots appear along its path, the bulletins are typed (a `reveal` track), the crew
##     act out their scripts (the man on the left only walks in after 30 s), the alarm lights come on one after the other,
##     and at the end an event cue tells the segment to finish.
##
## The speech is NOT in an animation: how long a clip lasts is not known when the animation is built, so a
## coroutine (`_speak`) waits for each group of clips with `await Audio.speak(...)`, exactly like the
## original's small speech state machine (`CartoonSpeech` (0x42984d)). Space / Escape skip everything, Enter goes on to the
## title; the director (`Opening`) handles the keys.
##
## Timing facts from the decompilation: the original redraws every 10 ticks of its 73 Hz timer ("call n" below is
## the n-th redraw, at t = 10 (n - 1) ticks); a bulletin is typed at 3 ticks per character and then read for
## 25 redraws (3.4 s); the capsule's trail gets a new dot every 11 redraws, the ring starts 6 redraws after the
## last one. The crew's pictures and timings are the original's five little scripts; the importer plays them out, redraw by
## redraw, into the timeline.

## The stage the cartoon plays on (`Catalog.story_stage`), and the timelines played on it: the alarm lights and the ring, which loop, and the cartoon itself.
const STAGE := &"news_cartoon_stage"
const AMBIENT := &"news_ambient"
const TIMELINE := &"news_cartoon"
const TIMELINES: Array[StringName] = [AMBIENT, TIMELINE]
## The speech is the voice groups `news_speech_0`, `news_speech_1` ... of the pack (`VoiceCues`: which clips, in the original's `CartoonSpeech` (0x42984d) 2, 3, 1, 1 and 4 of the 11 clips) and,
## before each, the pause `news.group_pauses[i]` of `data/rules/durations.json` (`Durations`), in ticks of the original's 1/73 s (the original's pause precedes clips 1, 3, 6 and 7, the others follow their
## predecessor at once; the port waited 3.4 s, 248.2 ticks, so 248; the bulletin is read for 25 redraws of 10 ticks, 250, which may be where the pause comes from: not checked in the decompilation).
## The speech goes on as long as the pack holds the next group. How long a group SPEAKS is not here: it is the clips' recorded lengths (`VoiceIndex.durations`, `Audio.speak`).
const SPEECH_GROUP_PREFIX := "news_speech_"


## The wait before the first clip: 3 s (`news.speech_start_delay_ticks`).
static func speech_start_delay_ticks() -> int:
	return maxi(Durations.at("news.speech_start_delay_ticks"), 0)


## The groups of the speech as `[pause ticks, clips]`: the voice groups of the chain in turn, each with its pause from the data. A chain with no first group says so (the cartoon is silent), and a group
## without a pause follows the one before it at once, both told once.
static func speech_groups() -> Array[Array]:
	var pauses := Durations.list_at("news.group_pauses")
	var cues := Catalog.voice_cues()
	var groups: Array[Array] = []
	while true:
		var index := groups.size()
		var clips := cues.clips(SPEECH_GROUP_PREFIX + str(index))
		if clips.is_empty():
			break
		if index >= pauses.size():
			TroubleLog.session.tell("[story] pack '%s': news.group_pauses of rules/durations.json has no pause for the speech group '%s%d': it follows the group before at once" % [_pack_id(), SPEECH_GROUP_PREFIX, index])
		groups.append([maxi(pauses[index], 0) if index < pauses.size() else 0, clips])
	if groups.is_empty():
		TroubleLog.session.tell("[story] pack '%s': voice_cues holds no group '%s0': the news cartoon is silent" % [_pack_id(), SPEECH_GROUP_PREFIX])
	return groups


static func _pack_id() -> String:
	return String(Packs.chosen().id) if Packs.chosen() != null else ""


@onready var stage: Node2D = %Stage
@onready var ambient: AnimationPlayer = %Ambient
@onready var script_player: AnimationPlayer = %Script

## The teletype, the text box the stage holds as the actor `teletype`.
var teletype: Label
var _cast: CutsceneCast


func _ready() -> void:
	_cast = CutsceneCast.new(self)
	_cast.texts = _bulletin_text
	StageBuilder.build(STAGE, stage, _cast)
	teletype = _cast.node_of(&"teletype") as Label
	Cutscene.install_timeline(ambient, &"ambient", Catalog.story_timeline(AMBIENT), _cast)
	Cutscene.install_timeline(script_player, &"news", Catalog.story_timeline(TIMELINE), _cast)
	ambient.play(&"ambient")
	script_player.play(&"news")
	Audio.play_music(AudioService.SONG_OPENING)
	_speak()


## The loop is over for good: stop the animations (the speech stops in `finish`).
func finish() -> void:
	if done:
		return
	ambient.stop()
	script_player.stop()
	super.finish()


## The timeline's only event: the last bulletin has been read.
func cue(event: StringName) -> void:
	if event == &"end":
		finish()


## Bulletin `index` (0-5) as the teletype prints it: the original's text with its odd characters cleaned.
static func bulletin(index: int) -> String:
	return tidy(Catalog.text(StringName("news_bulletin_%d" % index)))


## The original's text as the teletype shows it (the importer counts the typing time on this text).
static func tidy(text: String) -> String:
	return text.strip_edges().replace("\r", "\n")


func _bulletin_text(text_name: StringName) -> String:
	return tidy(Catalog.text(text_name)) if text_name != &"" else ""


# --- the speech ---------------------------------------------------------------------------------

## The clips of the bulletins in their groups, with the original's pauses.
func _speak() -> void:
	var groups := speech_groups()
	if not await pause_ticks(speech_start_delay_ticks()):
		return
	for group in groups:
		if not await pause_ticks(group[0]):
			return
		await Audio.speak(group[1])
		if done:
			return
