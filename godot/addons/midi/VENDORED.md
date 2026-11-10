# Vendored: Godot MIDI Player for Godot Engine 4.x

- Author: arlez80 (Yui Kinomoto). License: MIT (`LICENSE.txt`, unchanged).
- Source: https://bitbucket.org/arlez80/godot-midi-player-g4, branch master, the commit of 2025-12-10; plugin version 4.5.0
  (`plugin.cfg`). The files of its `addons/midi/` folder are copied unchanged, in the same folder name: the scenes refer to
  `res://addons/midi/...`.
- Not enabled as an editor plugin (the project does not need `GMP.gd`'s custom types). Only `src/audio/midi_music.gd` uses it.
- Pure GDScript, no network access, no compiled code; it reads only the files it is given (`FileAccess`).
- Known limits (see `godot/README.md`, "Music from MIDI"): notes start on the frame after their event; a damaged `.sf2` stops at
  a `breakpoint` when a debugger is attached (`MidiMusic.is_soundfont` checks the header first); its own 49 audio buses are added
  on first use (`MidiMusic.remove_buses` takes them out); `play()` parses the SoundFont again every time (`MidiMusic` avoids it
  with a subclass).
- To update: copy the new `addons/midi/` over this folder, keep this file, run `tools/run_tests.sh tests/engine/test_midi_music.gd`.
