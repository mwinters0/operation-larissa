class_name AudioService
extends Node
## The one place that makes noise: sound effects, speech and music. Registered as the autoload `Audio`.
##
## Teaches:
##   * audio buses (`Master` > `Music`, `SFX`, `Voice`, see `default_bus_layout.tres`): a bus has a volume and a
##     mute switch, so "Options > Music" is `AudioServer.set_bus_mute` and a volume slider is
##     `AudioServer.set_bus_volume_db`; no player node has to know about either;
##   * `AudioStreamPlayer` (non-positional: this is a flat 2D game with no listener); sound effects and speech
##     share ONE wave device in the original, so here the effect player and the voice player cut each other off;
##   * looping an `AudioStreamOggVorbis` (`loop = true`) and cross-fading two music players with a `Tween`;
##   * a service that other scenes ask by NAME (`Audio.play_sfx(&"correct")`, `Audio.play_music(&"title")`) instead of by
##     file or number: the name -> number comes from the NameRegistry, the number -> file knowledge is generated data
##     (`SfxCatalog`, `MusicCatalog`, `VoiceIndex`, `VoiceCues`);
##   * settings that belong to the machine (volumes) in a `ConfigFile`, and settings that belong to the player
##     (sound / music / voice on or off) in the player's save, applied with `apply_profile`.
##
## How the original behaved (all found in the decompilation, see docs/data/audio_map.json):
##   * ONE wave device [V]: `PlayWave` (0x4150c4) starts with `KillWave` (0x4151a4), and every effect
##     (`PlaySoundEffect` 0x431f1f, `RepeatCommonSoundEffect` 0x431f97, which has the same body here) and every speech
##     clip goes through it. So a new effect cuts the previous effect AND a speech clip, a speech clip cuts an effect,
##     effects never overlap. `StopCommonSoundEffect` (0x431ef2) is `KillWave` too. The Sound Effects / Voice options
##     only decide whether the new sound is started: a speech clip with the voice off still cuts the effect that
##     was sounding (the original calls `KillWave` before it looks at `VoiceOn`). The music is a MIDI song on its own
##     device and is not affected.
##   * Speech is played clip by clip (the original's loops wait with `IsWavePlaying`, so after an effect interrupted a
##     clip the next clip follows once the effect is over); Esc / Enter cut it off (`stop_voice`).
##   * `pause_sound` (0x414145): every modal dialog (`PauseSoundForDialog` 0x415ce0: `RunModalDialog` 0x4174ec,
##     `RunPagedDialog` 0x417755, `SaveAndExit`, `JustExit`, `show_hall_of_fame`, the customization dialog) and every loss
##     of window focus (`PauseSoundOnDeactivate` 0x413847) calls `KillWave` (a speech clip or effect that is sounding is
##     CUT, not held) and pauses the song; `resume_sound` (0x414163) lets the song go on from the same place. The levels nest
##     (counter 0x440e68); only the first one pauses the song. A speech sequence whose clip was killed goes on with its
##     next clip when the last level is left (the original's `IsWavePlaying` loop sees the wave gone and plays the next).
##   * Music: one MIDI song at a time. It is (re)started when a sector begins and after a problem or message that
##     stopped it, but NOT when the sub changes screens; it stops while a
##     math problem or a message from mission control is up, and pauses (and later resumes) behind dialogs.
##
## Every request fires a signal even when that kind of sound is switched off (`sfx_played`, `voice_played`,
## `music_changed`): the sound test shows them and the tests listen to them, so "this event plays the sound `correct`" can
## be checked without a loudspeaker. The signals carry NAMES (`sound`, `voice` and `music` names of names/original.json),
## not the original's numbers.

## An effect was requested: its `sound` name (`SfxCatalog`).
signal sfx_played(sfx: StringName)
## Speech was requested: the `voice` names of the clips, in order.
signal voice_played(clips: Array[StringName])
## One speech clip started (`transcript` is the machine-generated text, possibly wrong).
signal voice_started(clip: StringName, transcript: String)
## The speech sequence ended, or was cut off.
signal voice_finished
## The music changed: the `music` name of the song, or `NO_MUSIC` when it stopped.
signal music_changed(song: StringName)
## A volume, a switch or the sound set changed.
signal settings_changed

const MASTER := &"Master"
const MUSIC := &"Music"
const SFX := &"SFX"
const VOICE := &"Voice"
const BUSES: Array[StringName] = [MASTER, MUSIC, SFX, VOICE]

const NO_MUSIC := &""
## The songs the game asks for by name (the `music` names of names/original.json; the six songs of the sectors are
## `sector_song_1` .. `sector_song_6`).
const SONG_CLOSING := &"closing"
const SONG_OPENING := &"opening"
const SONG_TITLE := &"title"

const FADE_SECONDS := 0.6
const SILENT_DB := -60.0
const SETTINGS_PATH := "user://audio_settings.cfg"
## Linear volumes a fresh install starts with. The music is rendered loud, the clips are quiet: the speech must
## stay understandable over the song, so the music bus starts lower.
const DEFAULT_VOLUMES := {MASTER: 1.0, MUSIC: 0.55, SFX: 0.9, VOICE: 1.0}

## Cleared by `reset_pauses`, which `SceneRouter.start_fresh` calls at every scene change: the pauses that the dialogs and messages of
## the scene before took (and the speech they held). The level of a window without the focus stays (see `reset_pauses`).
const SCENE_FIELDS: Array[StringName] = [&"_music_pause_count", &"_sound_pause_level", &"_voice_held"]
## Member variables that no scope clears, and why (docs/engine/ARCHITECTURE.md, "Lifetimes of state").
const KEPT_FIELDS: Dictionary[StringName, String] = {
	&"settings_path": "configuration: tests point it at a scratch file",
	&"sound_set": "a setting of the machine (`save_settings`)",
	&"midi_soundfont": "a setting of the machine (`save_settings`)",
	&"song": "a song plays on across a scene change; the scene that follows starts or stops it (`play_music`, `stop_music`)",
	&"log_cues": "configuration: the project setting or the command line",
	&"_sfx_player": "wiring: made once in `_ready`",
	&"_music_players": "wiring: made once in `_ready`",
	&"_voice_player": "wiring: made once in `_ready`",
	&"_midi": "wiring: made with the first song played through a SoundFont",
	&"_active_music_player": "which of the two players the song is on",
	&"_music_tween": "a running fade: it ends by itself",
	&"_midi_tween": "a running fade: it ends by itself",
	&"_window_active": "the window's focus, not a scene's",
	&"_voice_cut_by_sfx": "a speech: it runs to its end, or `stop_voice` ends it",
	&"_voice_queue": "a speech: it runs to its end, or `stop_voice` ends it",
	&"_voice_speaking": "a speech: it runs to its end, or `stop_voice` ends it",
	&"_clip_ticks_left": "a speech: it runs to its end, or `stop_voice` ends it",
	&"_speech_meter": "a speech: it runs to its end, or `stop_voice` ends it",
	&"speech_ticks": "the length of the speech that ran last, for whoever asks (`speak`)",
	&"_warned": "each warning is printed once per session",
}

## Where `save_settings` / `load_settings` read and write. Tests point it at a scratch file.
var settings_path: String = SETTINGS_PATH
## `MusicCatalog.SoundSet`: the General MIDI rendering (default) or the AdLib one.
var sound_set: int = MusicCatalog.SoundSet.GENERAL_MIDI
## The `.sf2` the songs are played through at runtime from their MIDI files, or "" for the rendered OGGs (the default).
## Set it with `set_soundfont`, the setting file, the project setting `neptune/audio/soundfont` or `-- --soundfont=PATH`. A song
## without a MIDI file, or with a SoundFont that cannot be read, plays from its OGG as before.
var midi_soundfont: String = ""
## The song that is (supposed to be) playing, or `NO_MUSIC`.
var song: StringName = NO_MUSIC
## Print one line per cue ("[audio] sfx correct"). Off normally; turn it on with the project setting
## `neptune/audio/log_cues` or the command line argument `-- --audio-log`, to check from the console which sound
## an event plays when you cannot listen.
var log_cues: bool = false

var _sfx_player: AudioStreamPlayer
var _voice_cut_by_sfx: bool = false     # an effect interrupted a speech clip: the next clip waits for it to end
var _music_players: Array[AudioStreamPlayer] = []
var _active_music_player: int = 0
var _music_tween: Tween
var _midi: MidiMusic                    # made when the first song is played through a SoundFont
var _midi_tween: Tween
var _music_pause_count: int = 0
var _sound_pause_level: int = 0         # nesting of `pause_sound` (the original's counter 0x440e68)
var _voice_held: bool = false           # `pause_sound` killed a clip of a running sequence: its next clip waits for the resume
var _window_active: bool = true         # the original's flag 0x440d80
var _voice_player: AudioStreamPlayer
var _voice_queue: Array[StringName] = []
var _voice_speaking: bool = false
## Ticks (1/73 s) the clip that is sounding still has to last, by its RECORDED length (`VoiceIndex.durations`); 0 when none is
## counting (nothing sounds, or the clip was cut off and the next one waits). See `_process`.
var _clip_ticks_left: int = 0
var _speech_meter := TickMeter.new()
## How many ticks of the speech that is running (or ran last) have been counted. `speak` returns it.
var speech_ticks: int = 0
var _warned: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # the fades must run while a dialog pauses the game
	_ensure_buses()
	_sfx_player = _make_player(SFX)
	_sfx_player.finished.connect(_on_sfx_player_finished)
	for i in 2:
		_music_players.append(_make_player(MUSIC))
	_voice_player = _make_player(VOICE)
	_voice_player.finished.connect(_on_voice_player_finished)
	load_settings()
	log_cues = bool(ProjectSettings.get_setting("neptune/audio/log_cues", false)) or OS.get_cmdline_user_args().has("--audio-log")
	var configured := String(ProjectSettings.get_setting("neptune/audio/soundfont", ""))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--soundfont="):
			configured = argument.trim_prefix("--soundfont=")
	if not configured.is_empty():
		midi_soundfont = configured                  # (a SoundFont chosen on the command line beats the saved one)
	sfx_played.connect(func(sfx: StringName) -> void:
		if log_cues:
			print("[audio] sfx ", sfx))
	voice_played.connect(func(clips: Array[StringName]) -> void:
		if log_cues:
			print("[audio] voice ", clips))
	voice_started.connect(func(clip: StringName, text: String) -> void:
		if log_cues:
			print("[audio]   clip %s \"%s\"" % [clip, text]))
	music_changed.connect(func(new_song: StringName) -> void:
		if log_cues:
			print("[audio] music %s %s" % [new_song, _song_file(new_song)]))


## THE LENGTH OF A SPEECH IS THE ORIGINAL'S. A clip lasts as long as the importer recorded for it (`VoiceIndex.durations`), counted
## here in ticks of 1/73 s while it sounds (not while a dialog or a lost focus holds it, not after an effect cut it off). When the
## recorded ticks are over the next clip starts, or the speech is finished (`voice_finished`) - whatever the stream of the clip does,
## so a step that waits for the speech (a story page, the supply message) never depends on playback. The recorded lengths are the legacy pack's
## (the original's); a clip of a mounted pack lasts what THAT pack says (stated, or its file's length measured when it was mounted:
## `VoiceIndex.ticks_named`), so a student's narration is neither cut off nor followed by silence.
func _process(delta: float) -> void:
	if not _voice_speaking or _clip_ticks_left <= 0 or _voice_held:
		return
	var counted := mini(_speech_meter.feed(delta), _clip_ticks_left)
	_clip_ticks_left -= counted
	speech_ticks += counted
	if _clip_ticks_left <= 0:
		_voice_player.stop()
		_next_voice_clip()


## The window lost / regained the focus (`MainWindowProc` 0x41312f: WM_ACTIVATE -> `PauseSoundOnDeactivate` 0x413847 /
## `ResumeSoundOnActivate` 0x413861). Godot sends these two notifications to every node of the tree.
func _notification(what: int) -> void:
	if not WindowFocus.enabled:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pause_sound_on_deactivate()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		resume_sound_on_activate()


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


## The bus layout normally comes from `default_bus_layout.tres`; this only adds a bus that is missing (a project
## that lost its layout file still gets sound).
func _ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, MASTER)


# --- buses: switches and volumes -------------------------------------------------------------

## Options > Sound Effects / Music / Voice: mutes or unmutes the bus.
func set_bus_enabled(bus: StringName, enabled: bool) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("Audio: no bus called " + String(bus))
		return
	AudioServer.set_bus_mute(index, not enabled)
	if not enabled and bus == VOICE:
		stop_voice()                                 # (like the original: switching it off silences it at once)
	elif not enabled and bus == SFX:
		stop_sfx()
	settings_changed.emit()


func is_bus_enabled(bus: StringName) -> bool:
	var index := AudioServer.get_bus_index(bus)
	return index >= 0 and not AudioServer.is_bus_mute(index)


## `volume` is linear, 0.0 (silent) to 1.0 (full); the bus works in decibels.
func set_bus_volume(bus: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("Audio: no bus called " + String(bus))
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(volume, 0.0, 1.0)))
	settings_changed.emit()


func get_bus_volume(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(index)) if index >= 0 else 0.0


## The player's own choices (Options menu, stored in his record). `null` (nobody signed in) switches everything on.
func apply_profile(profile: PlayerProfile) -> void:
	set_bus_enabled(SFX, profile == null or profile.sound_on)
	set_bus_enabled(MUSIC, profile == null or profile.music_on)
	set_bus_enabled(VOICE, profile == null or profile.voice_on)


## Options > Music answered Yes or No (`SetMusicOn` 0x431db0). Off: the song is silenced but remembered
## (`song` stays); on: the remembered song starts again FROM THE BEGINNING (`PlayBackgroundMusic(current id)`;
## the original's MIDI file was closed when the music went off), also when the music already was on.
func set_music_on(enabled: bool) -> void:
	set_bus_enabled(MUSIC, enabled)
	if enabled and song != NO_MUSIC:
		play_music(song)


## Changes between the General MIDI and the AdLib rendering of the music; a song that is playing is cross-faded.
func set_sound_set(new_set: int) -> void:
	if new_set == sound_set:
		return
	sound_set = new_set
	if song != NO_MUSIC:
		play_music(song)
	settings_changed.emit()


## Chooses the SoundFont (`.sf2`) the songs are played through at runtime from their MIDI files, or "" for the rendered OGGs. A song
## that is playing starts again with the new sound. Returns false (and stays on the OGGs, with a warning) for a path that is not a
## SoundFont 2 file. The MIDI files are looked up by `MidiMusic.find_midi`.
func set_soundfont(path: String) -> bool:
	var usable := path.is_empty() or MidiMusic.is_soundfont(path)
	if not usable:
		_warn_once("soundfont " + path, "Audio: '%s' is not a SoundFont 2 file; the rendered music is used" % path)
		path = ""
	if path == midi_soundfont:
		return usable
	midi_soundfont = path
	if path.is_empty():
		_release_midi()                              # the parsed SoundFont (hundreds of MB) and the player's buses go
	if song != NO_MUSIC:
		play_music(song)
	settings_changed.emit()
	return usable


## True while the music is played from MIDI through a SoundFont rather than from the rendered OGG.
func is_midi_music() -> bool:
	return _midi != null and _midi.is_playing()


## Volumes and the sound set live in a ConfigFile (the INI-like `.cfg` format Godot uses for editor settings).
func save_settings() -> Error:
	var config := ConfigFile.new()
	for bus in BUSES:
		config.set_value("volume", String(bus), get_bus_volume(bus))
	config.set_value("music", "sound_set", sound_set)
	config.set_value("music", "soundfont", midi_soundfont)
	return config.save(settings_path)


## Reads the file if there is one; a missing or damaged file leaves the defaults.
func load_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)                       # on an error the config stays empty: every get_value gives its default
	for bus in BUSES:
		var volume: Variant = config.get_value("volume", String(bus), DEFAULT_VOLUMES[bus])
		set_bus_volume(bus, float(volume) if volume is float or volume is int else float(DEFAULT_VOLUMES[bus]))
	var saved_set: Variant = config.get_value("music", "sound_set", MusicCatalog.SoundSet.GENERAL_MIDI)
	sound_set = saved_set if saved_set is int and saved_set in [MusicCatalog.SoundSet.GENERAL_MIDI, MusicCatalog.SoundSet.ADLIB] \
			else MusicCatalog.SoundSet.GENERAL_MIDI
	var saved_font: Variant = config.get_value("music", "soundfont", "")
	midi_soundfont = saved_font if saved_font is String else ""


# --- sound effects ---------------------------------------------------------------------------------

## Plays the common effect called `sfx` (a `sound` name: `&"correct"`, `&"lock_tick"`). It cuts whatever the one wave device was playing: the effect
## before it, or a speech clip (`PlaySoundEffect` (0x431f1f) -> `PlayWave` (0x4150c4) -> `KillWave`).
## With the Sound Effects option off nothing starts and nothing is cut (`SoundOn`).
## While the window is not the active one nothing starts: the original's loops stand still then (`PollInputEvent` 0x410bc5
## does not return), so no effect is ever requested; an animation that fires one anyway is not heard.
func play_sfx(sfx: StringName) -> void:
	sfx_played.emit(sfx)
	if not is_bus_enabled(SFX) or not _window_active:
		return
	var stream := Catalog.sfx_catalog().stream_named(sfx)
	if stream == null:
		_warn_once("sfx %s" % sfx, "Audio: there is no sound effect '%s'" % sfx)
		return
	if _voice_player.playing:
		_voice_player.stop()
		_voice_cut_by_sfx = _voice_speaking
		_clip_ticks_left = 0
	_sfx_player.stream = stream
	_sfx_player.play()


## 1 while an effect is sounding, else 0 (there is one wave device; the tests look at this).
func busy_sfx_players() -> int:
	return 1 if _sfx_player.playing else 0


## `StopCommonSoundEffect` (0x431ef2): silences the effect that is sounding.
func stop_sfx() -> void:
	_sfx_player.stop()
	_resume_voice_after_sfx()


func _on_sfx_player_finished() -> void:
	_resume_voice_after_sfx()


## A speech clip that an effect interrupted is not played again; the sequence goes on with its next clip.
func _resume_voice_after_sfx() -> void:
	if _voice_cut_by_sfx and _voice_speaking:
		_voice_cut_by_sfx = false
		_next_voice_clip()
	else:
		_voice_cut_by_sfx = false


# --- speech -----------------------------------------------------------------------------------------

## Says the clips (`voice` names) one after the other, cutting off any speech that is going on. Returns at once;
## `voice_finished` tells when it is over. An empty list, or the Voice option off, finishes without a sound.
func play_voice_sequence(clips: Array[StringName]) -> void:
	var was_speaking := _voice_speaking
	_sfx_player.stop()                               # (`KillWave` comes first, also when the voice is off)
	_voice_cut_by_sfx = false
	_voice_held = false
	_voice_player.stop()
	_voice_queue.clear()
	_voice_speaking = false
	_clip_ticks_left = 0
	_speech_meter.reset()
	speech_ticks = 0
	voice_played.emit(clips)
	if not is_bus_enabled(VOICE) or clips.is_empty():
		if was_speaking:
			voice_finished.emit()
		return
	_voice_queue.assign(clips)
	_voice_speaking = true
	_next_voice_clip()


## Says the clips and returns when they are over (`await Audio.speak(clips)`), with the number of ticks that took. They are over when the
## RECORDED lengths of the clips are (see `_process`). When nothing can be heard (the Voice option is off, or there are no clips) it
## waits `silent_ticks` instead (`silent_speech_ticks()`: 146 = 2 s, data), so a story page that is paced by its speech does not flash by. That also holds when
## every clip of the list is missing (nothing starts, so there is nothing to hear). `stop_voice()` ends a speech that sounds, NOT this
## silent wait (a plain timer, which stands still with the tree): a caller that can be skipped checks its own `done` / generation
## after the `await`, as `StoryPages` and `NewsCartoon` do.
func speak(clips: Array[StringName], silent_ticks: int = -1) -> int:
	if silent_ticks < 0:
		silent_ticks = silent_speech_ticks()
	if not is_bus_enabled(VOICE) or clips.is_empty():
		voice_played.emit(clips)
		_sfx_player.stop()
		return await _wait_silently(silent_ticks)
	play_voice_sequence(clips)
	if not _voice_speaking:                          # (no clip has a stream: `voice_finished` was emitted before there was anything to await)
		return await _wait_silently(silent_ticks)
	await voice_finished
	return speech_ticks


## How long `speak` waits when there is nothing to hear (Voice off): `speech.silent_ticks` of `data/rules/durations.json`, 146 ticks of
## 1/73 s = 2 s in the original. It holds up play (a story page is paced by its speech), so it is data a pack may change.
static func silent_speech_ticks() -> int:
	return Durations.at("speech.silent_ticks")


func _wait_silently(silent_ticks: int) -> int:
	await get_tree().create_timer(TickMeter.seconds(silent_ticks), false).timeout     # (not while the director pauses the tree: inactive window)
	return silent_ticks


func play_voice(clip: StringName) -> void:
	play_voice_sequence([clip] as Array[StringName])


func is_voice_playing() -> bool:
	return _voice_speaking


## Esc / Enter in the original: stops the speech (and the clips that were still waiting).
func stop_voice() -> void:
	_voice_player.stop()
	_clip_ticks_left = 0
	_voice_cut_by_sfx = false
	_voice_held = false
	_voice_queue.clear()
	if _voice_speaking:
		_voice_speaking = false
		voice_finished.emit()


func _next_voice_clip() -> void:
	var index := Catalog.voice_index()
	while not _voice_queue.is_empty():
		var clip: StringName = _voice_queue.pop_front()
		var stream := index.stream_named(clip)
		if stream == null:
			_warn_once("voice %s" % clip, "Audio: there is no voice clip '%s'" % clip)
			continue
		_sfx_player.stop()                           # one wave device: the clip cuts an effect that is sounding
		_voice_cut_by_sfx = false
		_voice_player.stream = stream
		_voice_player.play()
		_clip_ticks_left = index.ticks_named(clip)
		voice_started.emit(clip, index.transcript_named(clip))
		return
	_voice_speaking = false
	voice_finished.emit()


func _on_voice_player_finished() -> void:
	if _clip_ticks_left <= 0:                        # (a clip with a recorded length is over when `_process` has counted it)
		_next_voice_clip()


# --- pausing: dialogs and the window focus --------------------------------------------------------------------

## `KillWave` (0x4151a4): the one wave device is reset. An effect that is sounding is gone; a speech clip that is sounding
## is gone too, and the sequence it belonged to goes on with its next clip only when `resume_sound` lets it.
func kill_wave() -> void:
	_sfx_player.stop()
	_voice_cut_by_sfx = false
	if _voice_speaking:
		_voice_player.stop()
		_clip_ticks_left = 0
		_voice_held = true


## `IsWavePlaying` (0x415214): is the one wave device sounding (an effect or a speech clip)?
func is_wave_playing() -> bool:
	return _sfx_player.playing or _voice_player.playing


## `pause_sound` (0x414145): `KillWave`, then the song is paused (the first level only; calls nest).
func pause_sound() -> void:
	_sound_pause_level += 1
	kill_wave()
	pause_music()


## `resume_sound` (0x414163): one level less; the song goes on from the same place when none is left.
func resume_sound() -> void:
	_sound_pause_level = maxi(0, _sound_pause_level - 1)
	resume_music()
	if _sound_pause_level == 0:
		_let_held_voice_go_on()


## A new scene begins (`SceneRouter.start_fresh`): every pause that a dialog or a message of the scene before took is gone with that
## scene, however its nodes left (`SCENE_FIELDS`). Only the level of a window without the focus stays, for it is the window's, not a
## scene's (`pause_sound_on_deactivate`; `resume_sound_on_activate` gives it back). The song goes on from where it was held, and a
## speech that a pause held goes on with its next clip.
func reset_pauses() -> void:
	var level := 0 if _window_active else 1
	_sound_pause_level = level
	_music_pause_count = level
	_apply_music_pause()
	if level == 0:
		_let_held_voice_go_on()


func _let_held_voice_go_on() -> void:
	if not _voice_held:
		return
	_voice_held = false
	if _sfx_player.playing:
		_voice_cut_by_sfx = true                 # (an effect started meanwhile: the clip after it, as always)
	elif _voice_speaking:
		_next_voice_clip()


## `PauseSoundOnDeactivate` (0x413847): the window lost the focus (or a menu opened, WM_ENTERMENULOOP). Once: asking
## again while already inactive does nothing (flag 0x440d80).
func pause_sound_on_deactivate() -> void:
	if _window_active:
		_window_active = false
		pause_sound()


## `ResumeSoundOnActivate` (0x413861): the window has the focus again.
func resume_sound_on_activate() -> void:
	if not _window_active:
		_window_active = true
		resume_sound()


func is_window_active() -> bool:
	return _window_active


# --- music ------------------------------------------------------------------------------------------

## The song of a sector: the one its `SectorData.music_name` names, through its campaign (`Campaign.song_for`). The original's data gives
## one of six tunes by `sector % 6` (so sectors 0 and 6 share a song: `sector_song_1` .. `sector_song_6`) and the finale song to the
## two finale sectors 30 and 31 (`SelectSectorMusic` 0x43200f); a sector that belongs to no campaign plays `Campaign.DEFAULT_SONG`.
static func music_for_sector(sector: int) -> StringName:
	var campaign := Catalog.campaign_of_sector(sector)
	return campaign.song_for(sector) if campaign != null else Campaign.DEFAULT_SONG


## Plays the song called `new_song` (a `music` name) and cross-fades from whatever was playing. A song that is already playing
## starts over unless `restart` is false (a song that is already playing is then kept).
func play_music(new_song: StringName, restart: bool = true) -> void:
	if new_song == song and not restart and _song_sounding():
		return
	if _play_midi(new_song):
		song = new_song
		_cross_fade(null, _music_players[_active_music_player])      # a rendered song that was sounding fades out
		music_changed.emit(new_song)
		return
	var stream := Catalog.music_catalog().stream_named(new_song, sound_set)
	if stream == null:
		stop_music()
		return
	_stop_midi()
	song = new_song
	var outgoing := _music_players[_active_music_player]
	_active_music_player = 1 - _active_music_player
	var incoming := _music_players[_active_music_player]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	incoming.stream_paused = _music_pause_count > 0
	_cross_fade(incoming, outgoing)
	music_changed.emit(new_song)


## Fades the song out. `song` forgets it: the next `play_music` starts a song again.
func stop_music() -> void:
	if song == NO_MUSIC:
		return
	song = NO_MUSIC
	_stop_midi()
	_cross_fade(null, _music_players[_active_music_player])
	music_changed.emit(NO_MUSIC)


## Dialogs hold the music (and let it go on from the same place). Calls nest: two pauses need two resumes.
func pause_music() -> void:
	_music_pause_count += 1
	_apply_music_pause()


func resume_music() -> void:
	_music_pause_count = maxi(0, _music_pause_count - 1)
	_apply_music_pause()


func is_music_playing() -> bool:
	return song != NO_MUSIC and _song_sounding()


func _song_sounding() -> bool:
	return _midi_sounding() or _music_sounding(_music_players[_active_music_player])


## Is this music player started, whether it is held by a dialog or not? A paused `AudioStreamPlayer` reports `playing == false`
## (the server's playback is not in the PLAYING state), so behind a dialog `playing` alone would take a held song for a stopped one: a
## fade would leave it out and it would sound again at the resume.
func _music_sounding(player: AudioStreamPlayer) -> bool:
	return player.playing or (_music_pause_count > 0 and player.stream_paused)


func _apply_music_pause() -> void:
	for player in _music_players:
		player.stream_paused = _music_pause_count > 0
	if _midi != null:
		_midi.set_paused(_music_pause_count > 0)


# --- music from MIDI ------------------------------------------------------------------------------------------

## Starts the song from its MIDI file through `midi_soundfont`, fading in. False when that is not set up (no SoundFont chosen, no
## MIDI file for the song, a file that cannot be read): the caller then plays the rendered OGG. A song that is already playing is
## cut, not cross-faded: the player's channel buses are shared, so two songs cannot fade against each other.
func _play_midi(new_song: StringName) -> bool:
	if midi_soundfont.is_empty():
		return false
	if _midi == null:
		_midi = MidiMusic.new()
		add_child(_midi)
	var file := Catalog.music_catalog().midi_file_of(new_song, sound_set)
	var path := _midi.find_midi(file) if not file.is_empty() else ""
	if path.is_empty():
		_warn_once("midi " + file, "Audio: no MIDI file '%s' in %s; the rendered music is used" % [file, MidiMusic.default_midi_dirs()])
		return false
	if not _midi.set_soundfont(midi_soundfont):
		_warn_once("soundfont " + midi_soundfont, "Audio: cannot read the SoundFont '%s'; the rendered music is used" % midi_soundfont)
		return false
	_midi.volume_db = SILENT_DB
	if not _midi.play_file(path):
		_warn_once("midi " + path, "Audio: cannot play '%s'; the rendered music is used" % path)
		return false
	_midi.set_paused(_music_pause_count > 0)
	_fade_midi(0.0)
	return true


func _fade_midi(target_db: float, then_stop: bool = false) -> void:
	if _midi_tween != null and _midi_tween.is_valid():
		_midi_tween.kill()
	_midi_tween = create_tween()
	_midi_tween.tween_property(_midi, "volume_db", target_db, FADE_SECONDS)
	if then_stop:
		_midi_tween.tween_callback(_midi.stop)


## Frees the MIDI player at once, with its SoundFont and its buses (a rendered song, if one is wanted, is started by the caller).
func _release_midi() -> void:
	if _midi_tween != null and _midi_tween.is_valid():
		_midi_tween.kill()
	if _midi != null:
		remove_child(_midi)
		_midi.free()
		_midi = null
		MidiMusic.remove_buses()


func _stop_midi() -> void:
	if _midi != null and _midi.playing_file != "":
		_fade_midi(SILENT_DB, true)


## Is a MIDI song started, whether a dialog holds it or not?
func _midi_sounding() -> bool:
	return _midi != null and _midi.playing_file != "" and (_midi.is_playing() or _music_pause_count > 0)


## `incoming` fades up while `outgoing` fades down and is then stopped (either can be null/silent).
## Only these two may sound afterwards. A request in the middle of a fade kills the tween, and with it the `stop` that the earlier
## fade had queued for ITS outgoing player; that player is neither of the two now (A -> B, then stop: B fades out, A would play on
## quietly with `song` empty), so it is stopped here.
func _cross_fade(incoming: AudioStreamPlayer, outgoing: AudioStreamPlayer) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()                          # a new request in the middle of a fade: start from where we are
	for player in _music_players:
		if player != incoming and player != outgoing:
			player.stop()
	var fading_out := outgoing != null and _music_sounding(outgoing)
	if incoming == null and not fading_out:
		return                                       # nothing to fade (a Tween without a Tweener is an error)
	_music_tween = create_tween().set_parallel(true)
	if incoming != null:
		_music_tween.tween_property(incoming, "volume_db", 0.0, FADE_SECONDS)
	if fading_out:
		_music_tween.tween_property(outgoing, "volume_db", SILENT_DB, FADE_SECONDS)
		_music_tween.chain().tween_callback(outgoing.stop)


## The original's file of a song, for the log ("ESECT1.MID").
func _song_file(song_name: StringName) -> String:
	return Catalog.music_catalog().midi_name_of(song_name)


## A missing file is a warning, once, never a crash (and not a flood of warnings every time it is requested).
func _warn_once(key: String, message: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(message)
