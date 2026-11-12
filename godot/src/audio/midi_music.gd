class_name MidiMusic
extends Node
## Plays a MIDI file through a SoundFont (`.sf2`) at runtime, instead of the OGG the importer rendered from it.
## Off unless `Audio.midi_soundfont` names a SoundFont: see `AudioService.set_soundfont` and docs/play/LEGACY.md.
##
## Godot has no MIDI synthesizer. This wraps `addons/midi` (arlez80's Godot MIDI Player, MIT, 100% GDScript: no compiled
## binary, so it runs in the editor, on every desktop and in the Web export). That addon keeps one `AudioStreamPlayer` per sounding
## note and plays the SoundFont's samples through them, so a note starts on the frame after its MIDI event (up to 1/60 s late)
## instead of on its sample, and the mixing is the engine's own. It is a software player, not a renderer: good for music, not for
## timing-critical sound.
##
## Teaches: wrapping a third-party node behind a small class of our own (the rest of the game never mentions `MidiPlayer`), the
## audio bus tree (`MidiMusic` bus > `Music` bus, with a limiter), and a cache for work that is expensive to repeat (the
## `.sf2` is parsed once, a song builds only the instruments it uses).
##
## What the importer does to the rendered songs, and what stands in for it here (see `tools/import/step_audio.py`):
##   * trailing silence trimmed: nothing to trim, a MIDI song ends at its last event. The song is within ~0.1 s of the rendered
##     OGG's length plus the release of its last notes (which the loop below cuts short);
##   * loudness limits (a song above -19 dB mean is turned down to -22 dB; every song stays 1.5 dB below full scale): the
##     peak limit is the limiter on the `MidiMusic` bus. The mean level cannot be measured before the song has been heard, so a
##     leveler measures what comes out of the player (an `AudioEffectCapture`), keeps the running mean of the song and turns the
##     song down by the same rule as the importer; it starts from a typical song's level and remembers each song's mean, so the
##     second time a song plays it starts at its final level;
##   * the AdLib songs' percussion: the original's `B*.MID` use the base-level layout (melodic channels 13-15, percussion on 16) that the
##     importer moves to channel 10 before it renders; `play_bytes` does the same to the bytes it hands to the player
##     (`percussion_to_channel_10`), because the player, like General MIDI, plays only channel 10 as drums;
##   * looping: `loop = true`, back to the first event when the last one has played (the original restarts the song from its
##     start); a song with the "tkool" loop-point controller (CC 111) loops to that point instead.

## The bus the player's notes go through: a child of `Music` with a peak limiter.
const BUS := &"MidiMusic"
## Where a MIDI file is looked up by name, first hit wins: the player's own folder, then the `midi/` folder of each pack of the chain (the importer fills the
## legacy pack's with the original songs; a pack file's is a virtual path, `Pack.path_of`, that `find_midi` and `play_file` ask the pack about). A campaign can add its own folder with `add_midi_dir`.
static func default_midi_dirs() -> Array[String]:
	var dirs: Array[String] = ["user://midi"]
	for each in Packs.chain():
		dirs.append(each.path_of("midi"))
	return dirs


## The peak ceiling of the importer (`PEAK_LIMIT_DB` in step_audio.py).
const CEILING_DB := -1.5
## The level the player itself is set to: headroom, so that a loud passage does not clip before the leveler has heard it.
const GAIN_DB := -6.0
## The importer's loudness rule (`TARGET_MEAN_DB` in step_audio.py): a song whose mean level is more than 3 dB above the target is
## turned down to the target, a quieter one is left alone.
const TARGET_MEAN_DB := -22.0
const TOLERANCE_DB := 3.0
## What the General MIDI songs measure with FluidR3 at `GAIN_DB` (-8 to -17 dB mean), as the leveler's first guess, counted as this
## many seconds of the song.
const PRIOR_MEAN_DB := -14.0
const PRIOR_SECONDS := 10.0
## The leveler moves the gain this slowly (dB per second), so it never pumps.
const MAX_SLEW_DB_PER_SECOND := 3.0
const MAX_POLYPHONY := 160
## The AdLib songs (`B*.MID`) play their percussion on MIDI channel 16 and the player plays channel 10 as drums (counted from 0 here).
const ADLIB_PERCUSSION := 15
const GM_PERCUSSION := 9

var soundfont_path: String = ""
## The song's level on top of `GAIN_DB`: what a fade changes (0.0 full, `SILENT_DB` silent).
var volume_db: float = 0.0:
	set(value):
		volume_db = value
		if _player != null:
			_player.volume_db = GAIN_DB + value
## The file that is (supposed to be) playing, or "".
var playing_file: String = ""

var _midi_dirs: Array[String] = default_midi_dirs()
var _player: CachedMidiPlayer
var _font: SoundFont.SoundFontData
var _font_path: String = ""
var _paused: bool = false
var _capture: AudioEffectCapture
var _amplify: AudioEffectAmplify
## The leveler's gain now (dB, <= 0), and what the songs heard so far added up to: file -> [energy, sample count].
var _gain_db: float = 0.0
var _heard: Dictionary = {}
var _energy: float = 0.0
var _count: float = 0.0


## A MidiPlayer that parses the SoundFont once. The addon's own `play()` parses the whole file again for every song (140 MB of
## FluidR3: ~1.5 s each time) before it builds the instruments the song needs; here only that second step is repeated.
class CachedMidiPlayer extends MidiPlayer:
	var font: SoundFont.SoundFontData
	var _built_for: Array = []

	func set_soundfont(path: String) -> void:
		soundfont = path
		if font == null:
			bank = null
			return
		var needed: Array = [] if load_all_voices_from_soundfont else _used_program_numbers.duplicate()
		needed.sort()
		if bank != null and needed == _built_for:
			return                                  # `load_from_bytes` and `play` both ask: build once
		_built_for = needed
		bank = Bank.new()
		bank.read_soundfont(font, needed)


## Is `path` a SoundFont 2 file? The addon stops at a `breakpoint` on a file that is not one, so check the header first
## ("RIFF" size "sfbk").
static func is_soundfont(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 12:
		return false
	var head := file.get_buffer(12)
	return head.slice(0, 4).get_string_from_ascii() == "RIFF" and head.slice(8, 12).get_string_from_ascii() == "sfbk"


## How long a MIDI file lasts in seconds when it plays at its own tempo: its last event, with the tempo changes on the way. The
## rendered OGG of the same song is this long plus the release of the last notes (the sound test and `test_midi_music.gd` compare).
static func song_seconds(bytes: PackedByteArray) -> float:
	var parsed := SMF.new().read_data(bytes)
	if parsed.error != OK or parsed.data == null:
		return 0.0
	var events: Array = []
	for track in parsed.data.tracks:
		events.append_array(track.events)
	events.sort_custom(func(a: SMF.MIDIEventChunk, b: SMF.MIDIEventChunk) -> bool: return a.time < b.time)
	var microseconds_per_beat := 500000.0                      # (120 beats per minute until a tempo event says otherwise)
	var seconds := 0.0
	var last_time := 0
	for chunk: SMF.MIDIEventChunk in events:
		seconds += (chunk.time - last_time) * microseconds_per_beat / 1.0e6 / parsed.data.timebase
		last_time = chunk.time
		if chunk.event.type == SMF.MIDIEventType.system_event and chunk.event.args.type == SMF.MIDISystemEventType.set_tempo:
			microseconds_per_beat = float(chunk.event.args.bpm)       # (the addon calls the microseconds per beat "bpm")
	return seconds


## The AdLib songs' percussion on the channel the player plays as drums: every channel event on MIDI channel 16 gets the status byte of
## channel 10 (a run on running status follows its first byte). The same rule as `percussion_to_channel_10` in tools/import/step_audio.py,
## which does it before it renders. Bytes with no channel 16 (the General MIDI songs), with channel 10 as well as 16, or that are not
## a MIDI file that parses come back as they are.
static func percussion_to_channel_10(bytes: PackedByteArray) -> PackedByteArray:
	var statuses := _channel_status_offsets(bytes)
	if statuses.is_empty():
		return bytes
	var found_16 := false
	for offset: int in statuses:
		match bytes[offset] & 0x0F:
			ADLIB_PERCUSSION: found_16 = true
			GM_PERCUSSION: return bytes
	if not found_16:
		return bytes
	var moved := bytes.duplicate()
	for offset: int in statuses:
		if moved[offset] & 0x0F == ADLIB_PERCUSSION:
			moved[offset] = (moved[offset] & 0xF0) | GM_PERCUSSION
	return moved


## The offset of every status byte of a channel event in a standard MIDI file (an event on running status has none: it follows the
## byte before). Empty for bytes that do not parse.
static func _channel_status_offsets(bytes: PackedByteArray) -> PackedInt32Array:
	var offsets := PackedInt32Array()
	var size := bytes.size()
	if size < 14 or bytes.slice(0, 4).get_string_from_ascii() != "MThd":
		return offsets
	var pos := 8 + _big_endian(bytes, 4)
	while pos < size:
		if pos + 8 > size or bytes.slice(pos, pos + 4).get_string_from_ascii() != "MTrk":
			return PackedInt32Array()
		var end := pos + 8 + _big_endian(bytes, pos + 4)
		if end > size:
			return PackedInt32Array()
		pos += 8
		var running := 0
		while pos < end:
			while bytes[pos] & 0x80 != 0:                                  # the delta time: a variable-length number
				pos += 1
				if pos >= end:
					return PackedInt32Array()
			pos += 1
			if pos >= end:
				return PackedInt32Array()
			var status := bytes[pos]
			if status == 0xFF or status == 0xF0 or status == 0xF7:         # a meta event or a system exclusive: a length, then that many bytes
				running = 0
				pos += 2 if status == 0xFF else 1
				var length := 0
				while true:
					if pos >= end:
						return PackedInt32Array()
					length = (length << 7) | (bytes[pos] & 0x7F)
					pos += 1
					if bytes[pos - 1] & 0x80 == 0:
						break
				pos += length
				continue
			if status >= 0xF0:
				return PackedInt32Array()
			if status & 0x80 != 0:
				running = status
				offsets.append(pos)
				pos += 1
			elif running == 0:
				return PackedInt32Array()
			pos += 1 if (running & 0xF0) == 0xC0 or (running & 0xF0) == 0xD0 else 2
		if pos != end:
			return PackedInt32Array()
	return offsets


static func _big_endian(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## Removes the buses the player made (its own 49 and `BUS`), e.g. when the SoundFont is switched off. Not while a MidiMusic plays.
static func remove_buses() -> void:
	for index in range(AudioServer.bus_count - 1, -1, -1):
		var bus_name := String(AudioServer.get_bus_name(index))
		if bus_name == String(BUS) or bus_name.begins_with("arlez80_GMP_"):
			AudioServer.remove_bus(index)


## Adds a folder where `find_midi` looks first (a campaign's songs).
func add_midi_dir(dir: String) -> void:
	_midi_dirs.push_front(dir)


## The path of the MIDI file called `file_name` ("ESECT1.MID") in the first folder that has it, or "". (The one lookup; `play_file` takes what it returns.)
func find_midi(file_name: String) -> String:
	for dir in _midi_dirs:
		for candidate in [file_name, file_name.to_upper(), file_name.to_lower()]:
			var path := dir.path_join(candidate)
			if Packs.has_file_at(path):
				return path
	return ""


## Chooses the SoundFont. Parses it (about 0.15 s for 140 MB) unless it is the one already loaded. False for a missing or damaged
## file; the previous SoundFont then stays.
func set_soundfont(path: String) -> bool:
	if path == _font_path and _font != null:
		return true
	if not is_soundfont(path):
		return false
	var parsed := SoundFont.new().read_file(path)
	if parsed.error != OK or parsed.data == null:
		return false
	_font = parsed.data
	_font_path = path
	soundfont_path = path
	if _player != null:
		_player.stop()
		_player.font = _font
		_player.bank = null
	return true


## Starts the song in `path` from the beginning, looping. False when the file cannot be read as a MIDI file or no SoundFont is set.
## Reads the bytes itself (`Packs.bytes_at`: a file of a pack is asked of the pack); a caller that has the bytes hands them over with `play_bytes`.
func play_file(path: String) -> bool:
	if not Packs.has_file_at(path):
		return false
	return play_bytes(Packs.bytes_at(path), path)


## `bytes` is a whole MIDI file; `key` names the song (the leveler remembers what it heard of it; `play_file` passes the path).
func play_bytes(bytes: PackedByteArray, key: String = "bytes") -> bool:
	playing_file = ""
	if _font == null or bytes.size() < 14:
		return false
	_ensure_player()
	_player.stop()
	if not _player.load_from_bytes(percussion_to_channel_10(bytes)):
		return false
	var heard: Array = _heard.get(key, [0.0, 0.0])
	_energy = heard[0]
	_count = heard[1]
	_gain_db = _wanted_gain_db()                   # starts at the level it needs (a song heard before: its own; else the prior's)
	_player.play()
	_player.playing = not _paused
	playing_file = key
	return true


func stop() -> void:
	if _player != null:
		_player.stop()
	playing_file = ""


## The leveler. It reads what the player produced since the last frame, adds it to the running mean of the song and slews the gain
## toward what the importer's rule would have used for that mean.
func _process(delta: float) -> void:
	if _capture == null:
		return
	var frames := _capture.get_frames_available()
	if frames > 0:
		var chunk := _capture.get_buffer(frames)
		if playing_file != "" and _player != null and _player.playing and volume_db > -3.0:     # (not while fading or holding)
			var energy := 0.0
			for frame in chunk:
				energy += frame.x * frame.x + frame.y * frame.y
			_energy += energy
			_count += frames * 2
			_heard[playing_file] = [_energy, _count]
	_gain_db = move_toward(_gain_db, _wanted_gain_db(), MAX_SLEW_DB_PER_SECOND * delta)
	_amplify.volume_db = _gain_db


## The gain the song needs given what has been heard of it: the importer's rule (`music_gain_db`), on the running mean that
## starts as `PRIOR_MEAN_DB` and turns into the song's own as it plays.
func _wanted_gain_db() -> float:
	var prior_samples := PRIOR_SECONDS * AudioServer.get_mix_rate() * 2.0
	var power := (pow(10.0, PRIOR_MEAN_DB / 10.0) * prior_samples + _energy) / (prior_samples + _count)     # (mean of squares)
	var mean_db := 10.0 * log(power) / log(10.0)
	return minf(0.0, TARGET_MEAN_DB - mean_db) if mean_db > TARGET_MEAN_DB + TOLERANCE_DB else 0.0


## Holds the song (notes sounding are cut) or lets it go on from the same place.
func set_paused(paused: bool) -> void:
	_paused = paused
	if _player != null and _player.smf_data != null and playing_file != "":
		if paused:
			_player.stop()
		else:
			_player.playing = true


func is_playing() -> bool:
	return _player != null and _player.playing


## How many notes sound right now (the sound test and the benchmark show it).
func voices() -> int:
	return _player.get_now_playing_polyphony() if _player != null else 0


func _ensure_player() -> void:
	if _player != null:
		return
	_ensure_bus()
	_player = CachedMidiPlayer.new()
	_player.font = _font
	_player.loop = true
	_player.load_all_voices_from_soundfont = false     # only the instruments the song uses
	_player.bus = BUS
	_player.volume_db = GAIN_DB + volume_db
	add_child(_player)
	# The addon makes 96 note players in `_ready` and, when told another number, takes them out of the tree without freeing them.
	for note_player in _player.audio_stream_players:
		_player.remove_child(note_player)
		note_player.free()
	_player.audio_stream_players = []
	_player.set_max_polyphony(MAX_POLYPHONY)


## `MidiMusic` under `Music` (or under `Master` where there is no `Music` bus): capture (for the leveler), amplify (the leveler's
## gain) and the limiter, in that order. Made on first use; the addon
## adds its own 49 buses (a master and three per MIDI channel) in front of it.
func _ensure_bus() -> void:
	var index := AudioServer.get_bus_index(BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master")
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		_amplify = AudioEffectAmplify.new()
		AudioServer.add_bus_effect(index, _capture)
		AudioServer.add_bus_effect(index, _amplify)
	else:                                              # another MidiMusic made it: use its effects
		for i in AudioServer.get_bus_effect_count(index):
			var effect := AudioServer.get_bus_effect(index, i)
			_capture = effect as AudioEffectCapture if effect is AudioEffectCapture else _capture
			_amplify = effect as AudioEffectAmplify if effect is AudioEffectAmplify else _amplify
		return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = CEILING_DB
	AudioServer.add_bus_effect(index, limiter)
