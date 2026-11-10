## Method

1. `audit_callsites.py` (PyGhidra) lists every reference to each primitive and to the wrappers around it, with the constant
   arguments pushed just before the CALL. The wrapper closure is part of the target list: `PauseSoundForDialog`,
   `SetMusicOn`, `WaitEnterOrTicks`, `RunModalDialog`, `WriteMessageText`, `ShowFirstTimeHint` and the one-line `StopBackgroundMusic`
   aliases are tracked the same way, so a caller of a wrapper is found even when it never names the primitive.
2. Ghidra misses code: the handlers behind `JMP [reg*4 + table]` switches (the calculator's `HighlightCalcKey`, `GetNumber`)
   and functions that nothing calls. The script (a) disassembles the handlers of every byte-indexed jump table and (b) cross-checks
   against a raw scan of every `E8` / `E9` rel32 in the code section, disassembling from the nearest `push ebp; mov ebp, esp`
   when the raw scan finds a call Ghidra has no instruction for. This found two sound calls that a pure xref listing misses:
   the calculator key click (`PlaySoundEffect(0x1f)` at 0x41b7fd) and the Backspace click in `GetNumber` (0x41fefd).
3. `audit_rows.py` holds the human reading of each caller (context, reachability, the port file:line or what is missing).
   `audit_report.py` joins the two and stops if any call site is without a row, which is what keeps this table complete.

Re-run:
```zsh
cd tools/analysis/ghidra && export NEP_GHIDRA_PROJECT=/tmp/neptune-ghidra
./run.sh apply_problem_types.py && ./run.sh apply_names.py
./run.sh audit_callsites.py /tmp/calls.json
uv run python audit_report.py /tmp/calls.json ../../../docs/port/AUDIT_CALLSITES.md
```

## Things that are not what they look like

* `LoadSpeechClip` (0x411315) is the generic loose-resource loader: it loads speech clips AND pictures (lock screen 0x1a0,
  problem background 0xf3, the per-screen still 23000 + sector * 12 + screen). Only the six `*Speech` functions use it for sound.
* `wait_alarm(6)` in `WrapTextLayout` waits on alarm slot 6, which no `set_alarm` ever sets (slots used: 0, 1, 2): a no-op.
* `if (DAT_00446600 != 0) PlayBackgroundMusic(0)` in `VoyagerClosingSequence` is dead: `DAT_00446600` is never written.
* Dead code (no caller, no pointer): the function at 0x4232a0 (a text + Enter screen), the function at 0x415b7c (a paged
  picture dialog), `PlayWaveUntilKey` (0x415250), `PlayWaveBlocking` (0x4152cd), `StopMusicUnused` (0x4320ad). Ghidra has
  no function for the first two; they are reached only through the raw-scan step above.
* The problem diagrams `Probnn_Diagram` build themselves in front of the player with sounds and `DelayTicks`, and nothing
  skips them; the port runs the same timelines (`DiagramBase.play_intro`, data in `problem_diagrams.json`, DESIGN 5.5) and holds
  the prompt back until they end. On a right answer `ShowSuccessMessage` replays a second animation for
  types 6, 11, 12, 16, 22, 23, 26 and 27 (`play_success_replay`), then waits 146 ticks for Enter or a click (it does not wait for ever).
* `pause_sound` (0x414145) calls `KillWave`: every modal dialog and every loss of window focus cuts a speech clip or effect that is
  playing. `SignInSpeech` (0x42fe4d) is synchronous: it loops on `IsWavePlaying` until each clip has ended (or a key cuts it).
