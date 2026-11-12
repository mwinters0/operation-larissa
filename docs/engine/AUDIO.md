# Audio

Everything that makes noise goes through the `Audio` autoload (`src/autoload/audio.gd`, class `AudioService`), by registry name
([`../create/NAMES.md`](../create/NAMES.md)): `Audio.play_sfx(&"correct")` (a `sound` name), `Audio.play_voice_sequence(VoiceCues...)`
(`voice` names), `Audio.play_music(AudioService.music_for_sector(s))` (a `music` name). The signals (`sfx_played`, `voice_played`,
`music_changed`, and the `sfx_requested` of the world, the problem screen and the diagrams) carry names too. Which number the original
plays when is [`../port/DESIGN.md`](../port/DESIGN.md) section 7 (from `extracted/tables/audio_map.json`). Paths are relative to `godot/`.

- **A mod asks by name too.** A problem-screen mod of the version that draws the game ([`../create/CONTENT.md`](../create/CONTENT.md), "API versions") names a `sound` and the diagram that holds its script emits it as any diagram's `sfx_requested`, which the problem screen sends to `Audio.play_sfx`; `ModSounds` keeps only names the chain can play (`SfxCatalog.can_play`: the original's effects and any pack's `audio/sound/<name>.ogg`) and bounds the rate ([`../create/CONTENT.md`](../create/CONTENT.md), "Problem screens", "Sounds"). A mod holds no stream and no player.
- **Buses** `Music`, `SFX`, `Voice`. One effect player and one voice player cut each other off, as the original's single wave device does.
- **Options.** Sound Effects / Music / Voice are per player (the Options menu); Options > Audio Settings holds the volumes and the music
  set, per machine, in `user://audio_settings.cfg`.
- **Seeing what plays** without listening: `-- --audio-log` (or the project setting `neptune/audio/log_cues`) prints an `[audio] ...`
  line for every cue.
- **Speech holds up play for a number of ticks, not for the playback.** Every clip's length in ticks of 1/73 s is data
  (`VoiceIndex.durations` in a complete pack; measured or stated for a pack's own clips, [`PACKS.md`](PACKS.md)); `Audio` counts those ticks
  while the clip sounds and ends the speech (`voice_finished`) when they are over. With the Voice option off it waits
  `speech.silent_ticks`. No sound or song holds up play.
- **Pauses are counted and belong to a scene.** `pause_sound` / `resume_sound` (every message box and dialog) and `pause_music` /
  `resume_music` nest; the song is held while any level is left. A window without the focus (or with a menu open) holds one level of its
  own (`pause_sound_on_deactivate` / `resume_sound_on_activate`). `reset_pauses`, which `SceneRouter.start_fresh` calls at every scene
  change, sets both counts back to that window level, so no pause of a scene outlives it (`SCENE_FIELDS` of `audio.gd`,
  [`ARCHITECTURE.md`](ARCHITECTURE.md), "Lifetimes of state").
- **Music** is the pack's OGG files: for legacy, the 20 MIDI songs rendered by the importer in two sets, General MIDI
  (`assets/audio/music/`) and AdLib (`assets/audio/music/adlib/`) ([`../play/LEGACY.md`](../play/LEGACY.md), "Soundfonts").

## Music from MIDI at runtime (off by default)

`Audio.set_soundfont(path)` (also `-- --soundfont=PATH`, the project setting `neptune/audio/soundfont`, and `[music] soundfont` in
`user://audio_settings.cfg`; an empty path goes back to the OGGs) plays each song from its MIDI file through that `.sf2` instead of the
rendered OGG. Nothing is re-imported: swap the file and restart the song.

- `addons/midi/` is arlez80's [Godot MIDI Player](https://bitbucket.org/arlez80/godot-midi-player-g4) 4.5.0 (MIT, pure GDScript,
  unmodified; `LICENSE.txt` beside it; `VENDORED.md`). It is not an editor plugin. A pure-GDScript player is used because the
  GDExtension players (TinySoundFont and FluidSynth wrappers) are compiled binaries that do not build for the Web export.
- `src/audio/midi_music.gd` (`MidiMusic`) is the one class that names the addon. It parses the `.sf2` once (0.15-0.2 s for 140 MB),
  builds only the instruments a song uses (0.07-0.25 s at the song's start), loops, pauses, finds the MIDI file (`user://midi/`, then
  the `midi/` folder of each pack of the chain, then any folder given to `add_midi_dir`) and keeps the level. `play_bytes` takes the
  bytes of a MIDI file.
- `Audio` asks `MusicCatalog.midi_file_of(song, sound_set)` (`ESECT1.MID` for General MIDI, `BSECT1.MID` for AdLib) and falls back to
  the OGG when no soundfont is set, the file is not a SoundFont 2, or the song has no MIDI file. `Audio.is_midi_music()` tells which.

What stands in for the importer's treatment of a render:

- **Length.** Trailing silence is trimmed in a render; a MIDI song ends at its last event. `MidiMusic.song_seconds` is the render's
  length minus the release of the last notes, within 3 s (`tests/engine/test_midi_music.gd`).
- **Loudness.** The importer turns a song above -19 dB mean down to -22 dB and keeps every song 1.5 dB under full scale. A limiter on the
  `MidiMusic` bus keeps the ceiling, and a leveler measures the player's output (`AudioEffectCapture`), keeps the song's running mean and
  applies the same rule, slewing at 3 dB/s from a typical song's level; a song's mean is remembered for its next play. With FluidR3 all
  ten songs measure -20.8 to -21.8 dB mean (the renders: -19.7 to -23.0) and none passes -1.5 dB.
- **The AdLib songs' percussion.** The `B*.MID` files put their drums on MIDI channel 16 and none on channel 10 (the base-level layout:
  melodic channels 13-15, percussion on 16; [`../port/DESIGN.md`](../port/DESIGN.md), section 7). The player, like FluidSynth and
  General MIDI, plays only channel 10 as drums, so `MidiMusic.percussion_to_channel_10` gives every channel-16 event the status byte of
  channel 10 in the bytes `play_bytes` hands to the player (running status follows its first byte; the addon is not touched). Bytes
  with no channel 16, with channel 10 as well, or that do not parse play as they are. The importer applies the same rule before it
  renders the AdLib set (`step_audio.percussion_to_channel_10`); the `midi/` files stay the original bytes.
- **Looping** goes back to the first event (or a CC 111 loop point), as the original restarted a song.

Audible differences: a note starts on the frame after its MIDI event (up to 1/60 s late), the loop cuts the release of the last notes,
a song fades in but is cut (not cross-faded) when another follows because the addon's channel buses are shared, and reverb and chorus are
the addon's simple effects.

Cost (Linux, headless, dummy audio driver, 60 fps, per core): idle 0.4 %, an OGG 0.4 %, a MIDI song through FluidR3_GM (141 MB) 3.2-8.7 %
(the densest passages have 65-128 notes at once; the limit is 160), through the 135 MB `opl.sf2` 2.0-4.4 %. Memory: the parsed soundfont
stays resident, about 250-370 MB for those two files (peak 640 MB while parsing) plus the song's instruments; `set_soundfont("")` frees
it. For the Web export use a small soundfont. The addon halts at a `breakpoint` on a file with a valid header but damaged contents when a
debugger is attached.
