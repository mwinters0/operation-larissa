class_name TimelineSegment
extends StorySegment
## A part of the opening that PLAYS A SCENE FILE (`StoryScene`, `data/story/<scene>.tres` of the pack chain): the news cartoon is the scene `news_cartoon`. The segment builds the scene's stage
## (`StageBuilder`), plays its timelines, starts its song and says its speech; nothing of what is drawn, when or by whom is in this script. Original: the first loop of `OpeningSequence` (OPENING.C)
## and its small speech state machine `CartoonSpeech` (0x42984d) for the news cartoon; the second half of `OpeningSequence` and `TitleScreenPromptLoop` (0x42a49a) for the title.
##
## The title is such a scene too (the ship, the reveal of the title, the Start / Intro prompt): `advance` (Enter) goes on to the next timeline of the scene, in a timeline with marks to the next mark (a HOLD that Enter cuts short), and once the verb
## `prompt` has run it answers the prompt; the stage's buttons (`StageActor.BUTTON`) and their keys are the prompt's, `choice` is the answer the director (`Opening`) compares with the part's `leads_on`.
##
## Teaches: a scene whose whole content is data, played by one script. Each timeline is an `Animation` made by `Cutscene.animation` on an `AnimationPlayer`: a player plays one animation at a time, so every
## LOOPING timeline has a player of its own (the alarm lights, the pulsing ring and the flickering console lights of the news cartoon are one such loop) and the ONE-SHOT timelines share one that plays them in order.
## What happens at a moment of a timeline is an event cue that is a VERB with its words (`StoryVerbs.VERBS`): `cue` parses it and calls `_verb_<name>`, so a verb is one more entry of `VERBS` and one more method, and a cue
## that names a verb the engine lacks is told once and does nothing (`StoryVerbs.problem`, the same judgement `PackCheck` uses). The speech is NOT in an animation, because how long a clip lasts is not known
## when the animation is built: a coroutine (`_speak`) walks the scene's `speech` steps, waits each pause and `await`s the verb `speak` (the voice group of that name, `Audio.speak`). Space / Escape end the segment (`skip`); the director (`Opening`) reads the keys and forwards them.

## The scene's name (`Catalog.story_scene`).
var scene_name: StringName = &""
## The scene, null when no pack of the chain holds it (the segment then ends at once).
var scene: StoryScene
## Which node plays which actor of the scene's stage; the timelines' tracks are bound through it.
var cast: CutsceneCast
## The node the stage's actors are made under.
var stage: Node2D
## The players of the looping timelines (one each, in the scene's order) and the player of the one-shot timelines.
var loop_players: Array[AnimationPlayer] = []
var script_player: AnimationPlayer
## True from the verb `prompt` on: the buttons are up, Enter / a click elsewhere / the time-out mean Intro, a button's key its own answer.
var prompting: bool = false
## The buttons of the stage, by what they answer.
var buttons: Dictionary[StringName, TextureButton] = {}
## How many ticks the prompt waits for an answer before it means Intro (`prompt.timeout_ticks`, read by the verb `prompt`); 0 before the prompt begins.
var prompt_timeout_ticks: int = 0

var _loop_names: Array[StringName] = []    # the timeline each of `loop_players` plays
var _chain: Array[StringName] = []         # the one-shot timelines that are there to play, in order
var _chain_index: int = 0
var _keys: Dictionary = {}                 # keycode -> the choice of the button it presses


## A segment that plays the scene `name_of_scene`: the scene is built when the segment enters the tree.
static func of(name_of_scene: StringName) -> TimelineSegment:
	var segment := TimelineSegment.new()
	segment.scene_name = name_of_scene
	segment.name = String(name_of_scene).to_pascal_case()
	segment.size = Vector2(640, 400)
	return segment


## The text of a timeline's `text` track as the teletype prints it: the original's text with its odd characters cleaned (the importer counts the typing time on this text).
static func tidy(text: String) -> String:
	return text.strip_edges().replace("\r", "\n")


func _ready() -> void:
	scene = Catalog.story_scene(scene_name)
	if scene == null:
		TroubleLog.session.tell("[story] no pack of the chain holds the scene '%s' (data/story/%s.tres): that part of the opening is skipped" % [scene_name, scene_name])
		finish.call_deferred()                    # (not at once: the director awaits `finished` only after it has added the segment)
		return
	_build()
	if scene.song != &"":
		Audio.play_music(scene.song)
	_play()
	_speak()


## The nodes of the scene, all of them: the black backdrop, the stage with the actors, a player for each loop and one for the one-shot timelines, with every animation installed. The one place they are made.
func _build() -> void:
	for line in scene.unresolved():
		TroubleLog.session.tell("[story] pack '%s': the scene '%s' %s" % [Catalog.story_pack_id(scene_name), scene_name, line])
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color.BLACK
	backdrop.size = size
	add_child(backdrop)
	stage = Node2D.new()
	stage.name = "Stage"
	add_child(stage)
	cast = CutsceneCast.new(self)
	cast.texts = _text
	_wire_buttons(StageBuilder.build(scene.stage, stage, cast))
	for timeline_name in scene.loops:
		var timeline := Catalog.story_timeline(timeline_name)
		if timeline != null:
			var player := _new_player(String(timeline_name))
			Cutscene.install_timeline(player, timeline_name, timeline, cast)
			loop_players.append(player)
			_loop_names.append(timeline_name)
	script_player = _new_player("Script")
	for timeline_name in scene.timelines:
		var timeline := Catalog.story_timeline(timeline_name)
		if timeline != null:
			Cutscene.install_timeline(script_player, timeline_name, timeline, cast)
			_chain.append(timeline_name)
	script_player.animation_finished.connect(_on_animation_finished)


## The stage's buttons answer the prompt: a press chooses what the button says, its key does the same from the keyboard.
func _wire_buttons(built: CutsceneStage) -> void:
	if built == null:
		return
	for actor in built.actors:
		var button := cast.node_of(actor.name) as TextureButton if actor.kind == StageActor.BUTTON else null
		if button == null:
			continue
		button.pressed.connect(_choose.bind(actor.choice))
		buttons[actor.choice] = button
		if actor.hotkey != "":
			_keys[OS.find_keycode_from_string(actor.hotkey)] = actor.choice


func _new_player(player_name: String) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = player_name
	add_child(player)
	return player


func _play() -> void:
	for i in loop_players.size():
		loop_players[i].play(_loop_names[i])
	if not _chain.is_empty():
		_enter_step(0)


## The one-shot timeline `index` of the scene begins. At its start the song stops when the scene says so, and the keys at its first moment are applied at once (they set the stage it needs: the parts of the ship are hidden when the title is revealed), not at the next frame.
func _enter_step(index: int) -> void:
	if done:
		return
	_chain_index = index
	if scene.song_stops_at == _chain[index]:
		Audio.stop_music()
	script_player.play(_chain[index])
	if index > 0:
		script_player.advance(0.0)


## The timeline that played ends: the next one begins. After the last, the scene waits for what ends it (an `end` cue, Enter, the prompt).
func _on_animation_finished(_finished: StringName) -> void:
	if _chain_index + 1 < _chain.size() and not done:
		_enter_step.call_deferred(_chain_index + 1)


## The loop is over for good: stop the animations (the speech and the prompt's waits stop in `finish`: `done` ends every `pause_ticks`).
func finish() -> void:
	if done:
		return
	for player in loop_players:
		player.stop()
	if script_player != null:
		script_player.stop()
	super.finish()


# --- the keys: the director (`Opening`) forwards Enter, clicks and Space / Escape ---------------------------------------

## Enter, by what is going on (`OpeningSequence` 0x42b16b, `TitleRevealText` 0x42a211, `WaitEnterSpaceEscOrTicks` 0x428fbe, `TitleScreenPromptLoop` 0x42a49a):
##   a prompt is up    Intro
##   a timeline with marks, before its last mark    the hold that is running ends: the next mark is reached at once, with its cues (the original waits up to 292 ticks for Enter / Space / Escape twice; an Enter ends the wait and is taken,
##                     it never skips a picture)
##   another timeline follows    it begins in place of this one (the ship scene ends, the reveal starts from its first moment)
##   the last timeline (or none)    the scene ends
func advance() -> void:
	if done:
		return
	if prompting:
		_choose(StageActor.INTRO)
	elif not _end_hold():
		if _chain_index + 1 < _chain.size():
			script_player.stop()                    # first: stopping puts the animated properties back to where they were, and the next timeline's first moments set what it needs
			_enter_step(_chain_index + 1)
		else:
			finish()


## Cuts the running hold short: the next mark of the timeline that plays is reached (a hair past it, so that playing on does not fire its keys again) and the cues of that moment are done here, because `AnimationPlayer.seek` calls no method
## tracks. False when the timeline has no mark ahead.
func _end_hold() -> bool:
	if _chain.is_empty():
		return false
	var timeline := Catalog.story_timeline(_chain[_chain_index])
	if timeline == null:
		return false
	var position := script_player.current_animation_position
	var target := &""
	for mark: StringName in timeline.marks:
		var tick: float = timeline.marks[mark]
		if CutsceneTimeline.seconds(tick) > position and (target == &"" or tick < timeline.marks[target]):
			target = mark
	if target == &"":
		return false
	var target_tick: float = timeline.marks[target]
	script_player.seek(CutsceneTimeline.seconds(target_tick) + 0.001, true)
	for cue_entry in timeline.cues:
		if is_equal_approx(cue_entry.tick, target_tick):
			if cue_entry.kind == CutsceneCue.SOUND:
				play_sfx(cue_entry.cue_name)
			else:
				cue(cue_entry.cue_name)
	return true


## A left-button release: Enter (the whole-screen hotspot 0xd), except over a button of the prompt: that is the button's own hotspot (0x975 / 0x977), whose release nobody answers (the buttons act on the PRESS, code 0x8975 / 0x8977).
func click(at: Vector2) -> void:
	if prompting and buttons.values().any(func(button: TextureButton) -> bool: return button.get_global_rect().has_point(at)):
		return
	advance()


## The prompt's keys: each button's own (`StageActor.hotkey`).
func _unhandled_key_input(event: InputEvent) -> void:
	if not prompting or not event.is_pressed() or event.is_echo():
		return
	var keycode := (event as InputEventKey).keycode
	if _keys.has(keycode):
		get_viewport().set_input_as_handled()
		_choose(_keys[keycode])


## The answer of the prompt (a button, its key, or the time-out): remembered in `choice`, then the scene ends.
func _choose(answer: StringName) -> void:
	if done:
		return
	choice = answer
	finish()


func _text(text_name: StringName) -> String:
	return tidy(Catalog.text(text_name)) if text_name != &"" else ""



# --- the verbs ------------------------------------------------------------------------------------------------

## An event cue of a timeline: a verb and its words. A verb the engine lacks, or a cue with the wrong number of words, is told once and does nothing.
func cue(event: StringName) -> void:
	var problem := StoryVerbs.problem(event)
	if not problem.is_empty():
		TroubleLog.session.tell("[story] pack '%s': the scene '%s' %s" % [Catalog.story_pack_id(scene_name), scene_name, StoryVerbs.line(event, problem)])
		return
	var words := StoryVerbs.parse(event)
	call("_verb_%s" % words[0], words.slice(1))


## `end`: the scene is over.
func _verb_end(_words: PackedStringArray) -> void:
	finish()


## `speak <group>`: the clips of the voice group, one after the other, until the last has been heard (`Audio.speak`: as long as the recording, or a silent wait when Voice is off). A coroutine: `cue` does not wait for it, `_speak` does.
func _verb_speak(words: PackedStringArray) -> void:
	var clips := Catalog.voice_cues().clips(words[0])
	if not done:
		await Audio.speak(clips)


## `prompt`: the buttons of the stage appear and the countdown starts (`prompt.timeout_ticks`: nobody chose, Intro); after `prompt.music_delay_ticks` the scene's `prompt_song` starts. Both waits are coroutines (`_time_out`, `_start_prompt_song`)
## that `pause_ticks` ends when the scene does, so the prompt is up before either waits.
func _verb_prompt(_words: PackedStringArray) -> void:
	if prompting or done:
		return
	prompting = true
	for button: TextureButton in buttons.values():
		button.visible = true
	prompt_timeout_ticks = maxi(Durations.at("prompt.timeout_ticks"), 1)
	_time_out()
	_start_prompt_song()


func _time_out() -> void:
	if await pause_ticks(prompt_timeout_ticks):
		_choose(StageActor.INTRO)


func _start_prompt_song() -> void:
	if scene.prompt_song != &"" and await pause_ticks(maxi(Durations.at("prompt.music_delay_ticks"), 0)):
		Audio.play_music(scene.prompt_song)


# --- the speech -----------------------------------------------------------------------------------------------

## The scene's speech: each step waits its pause, then speaks its group. A step whose group holds no clips is left out whole, pause and all (`StoryScene.unresolved` told it).
func _speak() -> void:
	for step in scene.speech:
		if Catalog.voice_cues().clips(String(step.group)).is_empty():
			continue
		if not await pause_ticks(maxi(step.pause_ticks, 0)):
			return
		await _verb_speak(PackedStringArray([step.group]))
		if done:
			return
