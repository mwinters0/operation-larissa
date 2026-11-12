# AdLib music: the Windows B songs and the DOS game's own FM songs

What is known about the game's AdLib (OPL2) music, for the day the port plays three soundtracks: **Windows General MIDI**
(`E*.MID`), **Windows AdLib** (`B*.MID`) and **DOS AdLib** (the DOS game's own FM sequences, which the Windows CD carries in
`NE0SOUND.DLL`). The first two are played; the third is extracted and measured but not played. The DOS driver is described in
section 2 completely enough to write a generator from the blobs alone; the measurements of section 1 are reproduced by the
scripts in `tools/analysis/adlib/` ([README](../../tools/analysis/adlib/README.md)); the mapping of section 3 is committed as
`tools/analysis/data/adlib_midi_map.json`, a result whose derivation is described in section 3, not scripted.

Tags as in [`DESIGN.md`](DESIGN.md): **[V]** verified (read from the files, or reproduced by running code), **[I]** inferred or
measured (a fit, a vote, a deduction), **[R]** a guess the prototype makes. No game bytes are in this document or in the scripts:
note data, patch registers and sequences stay in `extracted/`.

## 1. The two AdLib sources

### 1.1 Windows: `B*.MID`

Ten files, one per song, next to ten `E*.MID` (`SOUNDS/` on the CD). `InitMIDIDriver` (0x413bdc) reads `midimap.cfg` and, when its
setup name contains an AdLib-class card name, selects the `B` set; `LoadMidiFile` (0x413e8c) opens `SOUNDS\<B|E><name>.MID`;
`PlayBackgroundMusic` (0x43206e) asks for it **[V]**. The file plays through the Windows MIDI mapper with the card driver's own
patches **[I]**: no patch data is in the files. Where our copies are:

| Copy | Made by |
| --- | --- |
| the ISO's `SOUNDS/` folder | the CD |
| `extracted/music/B*.MID`, `E*.MID` | the importer's `extract` step (`tools/extract/extract_sounds.py`) |
| `<legacy pack>/midi/` | the importer's `audio` step (original bytes) |
| `extracted/sounds/fm_patches_undecoded/NE0SOUND_<id>.bin` (ids 9000-9190, section 1.2) | the importer's `extract` step |

Every `B` file is **[V]** format 0, 480 ticks per beat, one tempo, **channels 13, 14, 15 melodic and 16 percussion** (the base-level
multi-timbral layout; channel 10 is unused). Programs are listed 0-based. No volume or pan controller occurs; pitch bend occurs in
`BSECT3` (278 events) and `BSECT5` (143), with controllers 6, 100, 101 (bend range) on the channels that bend. Per file
(`midi_report.py`):

| File | Tempo | Length | Notes (all) | Programs on channel 13 / 14 / 15 |
| --- | --- | --- | --- | --- |
| `BEND` | 114 | 67.4 s | 2576 | 34 / 13 / 69 |
| `BEND2` | 150 | 51.2 s | 1184 | 5 / 32 / 60 |
| `BNEPT1` | 95 | 80.8 s | 696 | 5 / 51 / 51 |
| `BNEPT2` | 150 | 38.4 s | 696 | 37 / 11 / - |
| `BSECT1` | 123 | 117.1 s | 1963 | 12 / 13 / 33 |
| `BSECT2` | 103 | 149.1 s | 1835 | 5 / 12, 54, 62 / 39 |
| `BSECT3` | 103 | 139.8 s | 2345 | 12 / 13, 80 / 37, 39 |
| `BSECT4` | 126 | 144.8 s | 2244 | 12, 76, 80 / 13, 80 / 37, 39 |
| `BSECT5` | 119 | 145.2 s | 2706 | 45, 60, 71 / 5 / 33, 35, 37 |
| `BSECT6` | 102 | 160.0 s | 3106 | 54, 73, 80 / 5 / 35, 37, 38 |

The `B` songs are **reductions of the `E` songs** **[V]** (`compare.py`): the drum notes on channel 16 are exactly the `E` file's
channel 10 notes (tick and key) in all ten; the melodic notes are a subset of `E`'s. `BEND`, `BEND2`, `BNEPT1`, `BNEPT2` carry every
melodic note of their `E` file, parts with the same program merged onto one channel; `BSECT1` to `BSECT6` keep 1155 of 1573, 508 of
588, 1162 of 1349, 868 of 902, 816 of 980 and 922 of 955 melodic notes. Velocities are the `E` file's. A `B` song needs up to 10
melodic and 6 percussion voices at once (`poly.py`), more than the chip's 6 + 4.

Drum keys are General MIDI keys 35-69; `BSECT2`, `BSECT5` and `BSECT6` use 14 to 15 different keys. The importer and the
runtime move channel 16 to channel 10 so that a General MIDI player plays drums
([`../engine/AUDIO.md`](../engine/AUDIO.md), [`../play/LEGACY.md`](../play/LEGACY.md) "Soundfonts"). `soundfonts/opl.sf2` is a
**sampled** OPL3 bank (internal name "OPL-3 FM 128M", by Zandro Reveille, comment "Yamaha YMF262 FM Operator Type-L"): it plays
recordings of an OPL3, not the chip's registers, so it is not the DOS sound either.

### 1.2 DOS: the FM sequences in `NE0SOUND.DLL`

`NE0SOUND.DLL` resources 9000-9190 are the DOS engine's sound data **[V]**: the Windows game does not read them. Each resource
starts with a `u32` device type, which is also the first byte of the blob:

| Ids | Content | Device types |
| --- | --- | --- |
| 9000-9047 | 48 effects, one rendering | 1 (34 of them) or 0 (14) |
| 9048-9095 | the same 48 effects | 3 (AdLib; 113 to 132 bytes each) |
| 9096-9143 | the same 48 effects | 4 (MPU-401) |
| 9144-9155 | three further sets of songs, grouped by device **[I]** | 1, 2, 3, 4 (three each) |
| 9156-9183 | seven songs of the DOS file `NEP001.DAT`, four variants each | 1, 2, 3, 4 |
| 9184-9190 | the songs of `NEP002.DAT` | 1 to 4 |

Device types: 1 PC speaker, 2 Tandy / PS-1 (SN76496), 3 AdLib, 4 MPU-401 (General MIDI) **[V]**; device type 0 of the effects is a raw
PC-speaker stream (divisors) **[I]**. The DOS game picks the variant of its sound card. The type-3 resources are the AdLib
sequences: **nine songs**, `NE0SOUND` 9158, 9162, 9166, 9170, 9174, 9178, 9182 (the DOS `NEP001.DAT` entries 0x63 + 4k, resource
ids 0x1063 to 0x107B) and 9185, 9189 (`NEP002` 0x20E5, 0x20E9). Their blobs are byte-identical to the DOS game's decompressed
resources from byte 0x4E on (the `NE0SOUND` copy is 1 to 8 bytes shorter at the end) **[V]**. Three more type-3 resources exist: 9151
is byte-identical to 9185 (and 9148 to 9184, 9154 to 9186); 9150 and 9152 are two further short AdLib sequences (725 and 210
bytes), see section 1.3.

A DOS song carries 6 to 9 patches (`BEND2` and `BEND` 6, `BNEPT2` 7, `BSECT3` 8, the others 9); a channel selects one by program
number. `patch_decode.py` prints them.

The DOS data files `NEP001.DAT` and `NEP002.DAT` (not on the Windows CD) hold the same blobs compressed: a `u32` offset table
(entry `i` spans `offs[i]..offs[i+1]`), a resource id is `(file number << 12) | entry`, an entry is `[type byte][compression
byte][u16 decompressed size][data]`, a song's type byte is `'S'`, the compression is the game's own LZW (a second pass for one
mode). Each song is stored four times in consecutive entries, **+0 PC speaker, +1 Tandy, +2 AdLib, +3 MPU-401** **[V]**. The
`NE0SOUND` copies are already decompressed, so a reader of the Windows CD does not need any of this.

### 1.3 Which DOS song is which Windows song

A DOS song is a loop of an integer number of MIDI beats (to within two ticks) **[I]**; the Windows song is that loop repeated in
sections, each repetition with lines muted or added, the melodic notes at the same pitch. The identification started from a
melody-interval fingerprint (each DOS song's pitch intervals against each Windows song's; the scores are not archived) and is
confirmed by the note-level alignment of section 3 for six of the nine; for `BSECT2`, `BSECT3`, `BSECT4` the match rests mostly on
the loop length and on the lines that do align, and is weak. The General MIDI variants (device type 4) of the same DOS songs agree
with the pairing **[I]**.

| DOS resource | NE0SOUND | Loop (ticks / s) | Beats | Win song | MIDI repetitions | DOS melodic notes found at the exact pitch | Match |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0x1063 | 9158 | 569 / 7.81 | 16 | `BSECT1` | 15 | 107 / 147 = 73 % | usable |
| 0x1067 | 9162 | 340 / 4.67 | 8 | `BSECT2` | 32 | 28 / 66 = 42 % | weak |
| 0x106B | 9166 | 340 / 4.67 | 8 | `BSECT3` | 30 | 34 / 95 = 36 % (62 % allowing octave shifts) | weak |
| 0x106F | 9170 | 569 / 7.81 | 16 | `BSECT4` | 19 | 46 / 143 = 32 % | weak |
| 0x1073 | 9174 | 589 / 8.09 | 16 | `BSECT5` | 18 | 104 / 130 = 80 % | usable |
| 0x1077 | 9178 | 344 / 4.72 | 8 | `BSECT6` | 34 | 79 / 83 = 95 % | good |
| 0x107B | 9182 | 308 / 4.23 | 8 | `BEND` | 16 | 80 / 80 = 100 % | good |
| 0x20E5 | 9185 | 351 / 4.82 | 12 | `BNEPT2` | 8 | 29 / 33 = 88 % | good |
| 0x20E9 | 9189 | 467 / 6.41 | 16 | `BEND2` | 8 | 79 / 96 = 82 % (96 / 96 allowing octave shifts) | usable |

The loop column is the tick of the first restart; a song starts at tick 1 (section 2.5), so the loop period is one tick less. The
DOS tick is 1/72.8274 s (section 2.1); a beat is the Windows song's `60 / tempo` s. `BNEPT1` has **no DOS song in the DOS game's
data files** **[V]**; `NE0SOUND` 9150 is an AdLib sequence of 737 ticks (10.12 s, 16 beats at BNEPT1's 95 beats per minute) that
the DOS game never loads, and 9152 is a 47-tick one-shot cue, also never loaded **[I]**. The Windows songs are 38 to 160 s, the DOS
loops 4 to 8 s: the DOS game plays a loop and varies it in play by muting channels (section 2.9), and the Windows composer unrolled
that variation into the long `B` and `E` files. `BSECT1` is the loop 15 times (117 s = 15 x 7.8 s) with the lines entering and
leaving per repetition.

## 2. The DOS game's own AdLib driver

The DOS game has its own sound driver (no third-party sound library): a timer interrupt steps every playing sequence, and a
per-device handler turns a sequence into hardware writes. The type-3 handler is described here from its behaviour. Everything in
this section is **[V]** unless tagged: the description was checked against a capture of the register writes (address and data
port, with the timer tick of each) that the real driver makes while it plays each of the nine songs for two passes, and an
independent model written from this description reproduces that stream **with 0 differences** (all nine songs, both passes). The
capture itself is game-derived and not committed; section 5 says what one needs to make one.

### 2.1 Time

One timer: the game programs the PC's timer chip with divisor 0x4000, so the interrupt, and the driver's step, runs at
1193182 / 16384 = **72.8274 Hz**. Every delay in a song is a number of these ticks; there is no tempo event and no other clock. One
tick is 2048/3 samples of the chip's 49716 Hz output (`opl_sample = floor(tick * 2048 / 3)`; a tick is 196608 clocks of the
14.318 MHz master). Per tick and playing sequence the driver counts the elapsed ticks (a callback runs when the count reaches a
value the game set, section 2.9), decrements the sequence's delay, and when the delay reaches 0 runs the events of the sequence.

Chip access is always: write the register number to port 0x388, read the status port 6 times, write the value to 0x389, read the
status port about 35 times (the chip's settle delays); only the sequence of `(register, value)` pairs matters here.

### 2.2 The type-3 blob

Offsets in the decompressed resource (an `NE0SOUND` type-3 resource from byte 0, as section 1.2 says):

| Offset | Meaning |
| --- | --- |
| 0x00 | device type, 3 |
| 0x01-0x0D | runtime state of the sequence (delay, elapsed ticks, event pointer, callback tick, callback address, loop flag), zero in the file |
| 0x0E + 4c | record of channel `c` (0-15): `flags` (0x80 the channel is used; bit 0 muted by the game; bit 1 pre-empted by a higher-priority sequence), `program` (0xFF = none yet), `pitch` as `u16`. In the file each channel the song uses has flags 0x80 and program 0xFF, the pitch is 0 |
| 0x4E | the song index the game starts (the loop target) |
| 0x4F, 0x50, 0x51 | runtime state: current song, current transpose, running status |
| 0x52 | the number of songs `n` (1 in all nine) |
| 0x53 + 4i | song `i`: `u16` offset of its event data, `u8 next` (0xFF = loop or stop, else the song to chain to), `u8 transpose` (semitones; 0 in all nine) |
| 0x53 + 4n | `u8` patch count `p`, then `p` `u16` absolute offsets of the patches, indexed by program number |
| then | the patches, 11 bytes each, and the event data |

A patch is `[mod 20, 40, 60, 80, E0] [C0] [car 20, 40, 60, 80, E0]`: the values of the OPL2 registers of the modulator operator
(0x20 = tremolo / vibrato / sustain / multiple, 0x40 = key scale level and total level, 0x60 = attack / decay, 0x80 = sustain /
release, 0xE0 = waveform), of the channel's feedback / connection register 0xC0, and of the carrier operator. The rhythm
channels (section 2.5) that drive one operator have 5 or 6 bytes (section 2.8). The song-level fields `next` and `transpose` and the
per-channel records are the driver's own; the effects (type 3, 48 of them) are the same format with one patch at 0x5A **[I]**.

### 2.3 Events

The event data is a byte stream of `status [data...] delta`. The first byte of a song's event data is a delay that the driver
skips (0xFF means two more bytes are skipped), then the sequence starts with its delay set to 1, so its first events run at tick 1.

`status & 15` is the **channel**: 16 channels, each monophonic. A first byte below 0x80 is not a status: the previous status is
reused and the byte is its first data byte (for a note-off, which has no data, the byte is the delta).

| Status | Data after the status | Action |
| --- | --- | --- |
| 0x80-0x8F | none | note off (section 2.7) |
| 0x90-0xBF | `key`, `level` | write the operator level, then note on (section 2.6); all three high nibbles behave alike |
| 0xC0-0xDF | `program` | when it differs from the channel's remembered program: remember it and load the patch (section 2.8), unless the channel is pre-empted |
| 0xE0-0xEF | `lo`, `hi` | the channel's pitch word `hi:lo`; when it differs from the stored one, store it and re-pitch the sounding key (section 2.6) |
| 0xF0-0xFF | `01`, `song` | end of song when the second byte is 1 and the third is the current song; otherwise ignored (the two bytes are still consumed) |

An event on a channel whose `flags & 3` is not 0 is parsed but writes no register, except that program numbers are still
remembered when only bit 0 (muted) is set. `delta` follows every event: **0** means the next event is at the same tick, **1-0xFE**
that many ticks, **0xFF** a `u16` tick count after it. Playback is one loop: run events while the delta is 0, set the delay from
the first non-zero delta, wait.

### 2.4 End of song, restart, loops

At the end event: when the song's `next` byte is not 0xFF the driver chains to that song; else if the sequence's loop flag is 0 the
sequence stops (a stop key-offs every channel the sequence owns); else it restarts the song at blob byte 0x4E. **The first event
of the new pass runs in the same tick** as the end event. A start or restart (a) skips the leading delay as section 2.3 says, (b)
sets the elapsed count to 0, (c) sets all 16 pitch words to 0, (d) takes the song's transpose, and does **not** reset programs or
flags: a restarted loop reloads no patch whose program is unchanged. The nine songs run with the loop flag on; the effects run with
it off. The dumps of the loop play every channel; the game's scene masks (section 2.9) are the only way a song is varied.

### 2.5 Voices: melodic and rhythm channels

Channels 0-5 are the six melodic OPL voices, two operators each. Channels 6-10 are the OPL **rhythm** instruments, switched on by
bit 5 of register `BD` (0xBD) in the chip init: 6 bass drum (two operators), 7 snare (one), 8 tom (one), 9 top cymbal (one),
10 hi-hat (one). The nine songs use 6, 7, 8 and 10 and never channel 9, and none uses channels 11-15. Per channel the driver has the
operator pair `(modulator, carrier)` as indices into the chip's 18 operators, and each operator index has a register offset:

```
channel   0     1     2     3     4     5     6      7     8     9     10
(mod,car) (0,3) (1,4) (2,5) (6,9) (7,10)(8,11) (12,15) (16,-) (14,-) (17,-) (13,-)     "-" = no carrier
operator index 0..17 -> register offset 00 01 02 03 04 05 08 09 0A 0B 0C 0D 10 11 12 13 14 15
```

These are the OPL2's own operator layout: a register `20 + offset` addresses one operator. A single-operator channel is the
chip's snare (operator 16, offset 0x14), tom (14, 0x12), top cymbal (17, 0x15) and hi-hat (13, 0x11); the tom and top cymbal share
the chip voice 8 for their pitch, the snare and hi-hat voice 7.

### 2.6 Note on, level and pitch

Note on is `90 key level` with a delta. The driver

1. writes `level` **verbatim** to the level register of the channel's carrier, `0x40 + offset(carrier)` (the modulator's for a
   channel with no carrier). It is the whole `KSL << 6 | TL` byte (key scale level in bits 6-7, total level in bits 0-5, 0.75 dB
   per step; 0 is loudest), not a MIDI velocity, and the driver scales nothing;
2. derives the pitch (below) and writes `A0 + voice` (the low 8 bits of the F-number) and `B0 + voice` (F-number high 2 bits,
   block in bits 2-4);
3. keys the note: for a melodic channel bit 5 of the same `B0` write is set (`B0 | 0x20`); for a rhythm channel `B0 + voice` is
   written without the key bit and the driver writes `BD` with the instrument's bit set (below).

Pitch: `k = key + song transpose + (pitch word high byte) - 12`, in 8-bit arithmetic (a negative result becomes 0, then it is
limited to 95); `block = k / 12`, `note = k % 12`; `fnum = FNUM[pitch word low byte][note]`; `lo = fnum & 0xFF`, `hi = (fnum >> 8) |
(block << 2)`. A key of 0x80 or more writes nothing; the key is remembered per channel so that a later pitch word re-pitches it
(an `E0` event writes the pitch registers again for the sounding key).

`FNUM` is a table of the driver's data segment (DS:0x35B0 of the DOS executable; it is not in the blob), 25 rows by 12 columns:
the row is the **fine tune** (the pitch word's low byte, 0 to 24), the column the semitone of the octave. Row 0 is **[V]**
`343 364 385 408 433 459 486 515 546 579 614 650`. Each further row is that row sharper by 1/288 of an octave per step, so row 24
is row 0 one semitone up: `round(row0[note] * 2^(row / 288))` is within 1 of the table, within 2 at row 24 **[I]** (the table
is not exactly this formula, so exact register values need the table itself). Eight songs keep every pitch word at 0; `BSECT5`
sets 12 distinct words (rows 0, 3, 4, 7, 11, 13, 15, 17, 18, 19, 22, 24 with the high byte 0 or 1, and once 0xFF, which in the
8-bit arithmetic is one semitone down) **[V]**.

Rhythm notes use the chip voice `v = {6: 6, 7: 7, 8: 8, 9: 8, 10: 7}[channel]` for `A0 / B0` and the shadow of `BD` (it starts
at 0x20, the rhythm-mode bit, and the driver keeps it, because the register cannot be read back): note on sets bit `10 - channel`
and writes `BD` (so the writes are 0x30 for the bass drum, 0x28 snare, 0x24 tom, 0x22 top cymbal, 0x21 hi-hat, ORed with the
instruments already sounding).

### 2.7 Note off

A melodic channel writes `B0 + voice` with the value of the last `B0` write for that channel with bit 5 cleared (`& 0xDF`). A
rhythm channel clears its bit in the `BD` shadow and writes `BD`. The state "note off" is remembered per channel; a pitch event on a
channel in that state writes nothing.

### 2.8 Patch load

A program event with a new program number loads the patch whose offset is the `u16` at `0x54 + 4n + 2 * program` (`n` is the song
count, 0x52). Let `m` and `c` be the register offsets of the channel's modulator and carrier (section 2.5). The patch bytes go to
registers in this order: bytes 0-4 to `20, 40, 60, 80, E0` each `+ m`; byte 5 to `C0 + voice` where the voice is the channel for
channels 0-6, 8 for channel 8, 7 for channel 10, and **channels 7 and 9 have no byte 5** (the feedback byte is skipped); then, when
the channel has a carrier (channels 0-6), the next 5 bytes to `20, 40, 60, 80, E0` each `+ c`. The patch of a single-operator
channel is therefore 5 or 6 bytes long. A patch write includes the modulator's level register; the next note on rewrites the
carrier's. A patch loads only on a program event (not at start) and only when the channel's program differs from the new one
(section 2.4).

### 2.9 Chip init and the game's use of a sequence

The chip is initialised with **117 writes** **[V]**, all at tick 0:

- the timer / detection sequence: `04=60, 04=80, 02=FF, 04=21, 04=60, 04=80` (6 writes);
- `BD=20` (rhythm mode on, no instrument keyed), `08=00`;
- `A0+v=00, B0+v=00` for the nine voices `v = 0..8` (18 writes);
- for each of the 18 operators, the registers `E0, 20, 40, 60, 80` (plus the operator's offset) = 00 (90 writes);
- `01=20` (waveform select enable).

That is 6 + 2 + 18 + 90 + 1 = 117.

The driver's calls, as the game uses them: initialise and detect the cards (a bit mask: 1 PC speaker, 2 Tandy, 4 AdLib, 8 MPU-401),
register a blob (returns a handle), start (handle, song index, priority, loop flag), stop and unregister, set the transpose, mute or
unmute one channel, set the elapsed-tick callback, and the timer step. The device handler per sequence is chosen by the blob's device
type from a table in the data segment; the device the game plays on is a variable of the game (0 to 3 = PC speaker, Tandy, AdLib,
MPU-401) **[I]**.

**[I]** A scene of the game (a room or level) selects a song and a **9-byte parameter record**, `u16 song, u16 channel-on mask, u16
per-pass toggle mask, s8 transpose, u16 tick`, from two 32-entry tables of the game's data (the scene-to-song table holds only the
seven `NEP001` base ids 0x1061 + 4k, two scenes sharing the last; the parameter records are `NEP001.DAT` entries 0x107D to
0x10B4, 14 banks of four device variants); the record's `tick` is the song's loop period, at which a game callback runs and sets the
masks, and the game mutes and unmutes channels with it as the puzzle state changes. So one loop of 4 to 8 s is varied in play. The
56 records are in the DOS file, not in any `NE0SOUND` resource **[I]**; they and the scene to song assignment are not recorded here.
Sound effects start with the loop flag off and a priority from a 48-entry table of the game's data; a lower-priority sequence's
channels are marked pre-empted (flags bit 1) and skipped.

## 3. Mapping a Windows song onto the DOS sound

Everything below is measured on the nine songs; `tools/analysis/data/adlib_midi_map.json` lists it per line (indices, counts and
shares only). A MIDI line is a (channel, program) pair.

**How it was derived.** [I] (1) Each DOS song's loop is decoded with the driver of section 2 into notes: tick, voice (channel),
key, carrier level, patch index (program number). (2) The loop length in ticks, divided by 72.8274 and by the Windows song's beat
length, is a whole number of beats (the "Beats" column of section 1.3) to within two ticks; the Windows song is searched for the
loop repeated every that many beats, and the phase (the tick the first repetition starts at) is the one at which most DOS notes
find a MIDI note. (3) For each MIDI line and each DOS voice, a DOS note is "found" when the line has a note at the same pitch,
within 25 ms of the DOS note's position inside the loop, in some repetition; a line may be searched with a semitone shift, which for
the weak songs only fits noise. The line's partner is the voice whose notes the line finds the most; the share is notes found /
voice notes. (4) Drums: the MIDI onsets of one drum key, folded on the loop, are scored against each DOS rhythm instrument's
onsets by F1 (recall and precision at 25 ms). (5) Velocity: within each matched line, the DOS carrier total level (the low 6 bits
of the level byte) is fitted linearly against the MIDI velocity, pooled over all matched notes. The table is the committed result;
the scripts of the derivation are not committed.

**Well-matched songs, line to DOS patch** (patch = program number of the song's own blob; the indices are per song and do not carry
over: the same sound has different indices in different songs) **[I]**:

| Song | MIDI line (channel / program) -> DOS patch | DOS voices with no MIDI line |
| --- | --- | --- |
| `BEND` | 13/34 -> 3; 15/69 -> 4 | voice 4 (patch 4; doubles voice 2) |
| `BSECT6` | 13/73 -> 2; 13/80 -> 6; 14/5 -> 5; 15/35 -> 0 (octave -10); 15/37, 15/38 -> 4 | voice 3 (patch 5) |
| `BNEPT2` | 13/37 -> 4; 14/11 -> 1 | voice 0 (patch 0; 4 notes) |
| `BEND2` | 13/5 -> 3; 14/32 -> 2 (an octave lower than DOS); 15/60 -> 0 | voices 1, 2 (patch 3, a chord) and 4 (patch 0) |
| `BSECT5` | 13/45 -> 7; 13/60 -> 0; 14/5 -> 5; 15/37 -> 4; 15/35 -> 6 (weak, 59 %) | voice 0 (patch 5); 13/71 and 15/33 match nothing |
| `BSECT1` | 13/12 -> 3; 14/13 -> 1; 15/33 -> 2 | voices 3, 4 (patch 4) and 5 (patch 5) |

`BSECT2`, `BSECT3`, `BSECT4` have one to four lines that align (`BSECT2`: 13/5 -> 6, 14/12 -> 8 at an offset of -19 semitones, 15/39 -> 5;
`BSECT3`: 13/12 -> 2, 14/13 -> 1); the rest do not, and the per-line shift of the search is noise there **[I]**. The data file marks
each line `ok` (at least 80 % of the voice's notes found), `weak` (50 %) or `none`. Several Windows lines share one DOS voice
(`BSECT6` 15/37 and 15/38, `BEND` 14/13 and 15/69) because the DOS voice is monophonic and the Windows song splits it by program.

**Drum keys** **[I]**. The DOS song has three or four rhythm instruments, and MIDI drum onsets folded on the DOS loop score against
each by F1 (recall and precision at 25 ms). Settled, mean F1 of 0.8 or more: **35, 36 -> bass drum; 38 -> snare; 39, 42, 44 ->
hi-hat** (42 in six of seven songs; in the seventh it lands on the tom). Not settled: the toms 41, 43, 45, 47, 48, 50 (F1 0.04 to 0.55;
BSECT1's toms are keys 41, 47, 50, 65, 66), the open hi-hat 46 (once SD), the cymbals 49-59 and the latin keys 60-69 (F1 0.07 to 0.78,
no consistent partner).

**Velocity to level** **[I]**. Within one line the DOS carrier level falls linearly as the MIDI velocity rises. The pooled fit over 3570
matched notes of the nine songs is **-0.222 TL per velocity unit** (TL is 0.75 dB per step). It is a fit, not a rule: per line the slope
runs from 0 to -0.57, and the KSL bits (0, 1, 2 seen) belong to the instrument.

**BSECT1 in detail** **[V]**: per loop the DOS plays 120 rhythm hits at 64 distinct ticks (bass drum 16, snare 8, tom 64, hi-hat
32). The MIDI has **no drums in the first five repetitions**; in repetitions 5-10 it has 44 to 52 onsets per loop and covers every bass
drum, snare and hi-hat hit but only 32 of the 64 tom hits (it has no tom-key onsets then; the 32 are positions where a hi-hat or
another drum also falls); in repetitions 11-14 it has 126 to 134 onsets and covers all 120, the toms by keys 41, 47, 50, 65, 66. Three DOS
melodic voices have no MIDI line (section 3 table).

**Guesses of the prototype** **[R]** (a prototype, not archived, wrote a `B` song as a DOS-style register log with the DOS patches):
the patch of a MIDI line that matches no DOS voice (the voice with the nearest register); the tom pitch ladder (the DOS tom key is a
melodic pattern, not one key per MIDI tom); the latin percussion (60-69) on the tom voice; the dropped cymbals (49, 51-53, 55, 57,
59: no DOS voice); a hit's length (a few ticks, 50 to 110 ms, from the DOS hits); the voice allocation (a free voice that already has
the patch, else the one whose note ends first, a stolen voice keyed off 2 samples before); the carrier level of a note (the line's
mean DOS level plus the velocity fit).

## 4. Playing the DOS soundtrack

**[V]** The chip is rendered by ymfm, the library every emulator of the Yamaha OPL family can use
([github.com/aaronsgiles/ymfm](https://github.com/aaronsgiles/ymfm), BSD-3-Clause): `ymfm::ym3812` at 3579545 Hz gives 49716 Hz,
linear interpolation to 44100 Hz, gain 0.8, mono duplicated to stereo. `ymfm_render` (`tools/analysis/adlib/ymfm_render.cpp`, about
60 lines over ymfm, built by `build_ymfm_render.sh` against a ymfm checkout named by `YMFM_DIR`) turns a register log into a WAV
and **reproduces a reference rendering of the same writes made with the same chip, resampler and gain for all nine songs bit for
bit** (identical samples 100 %, maximum difference 0). The chip state matters: ymfm's `reset()` does not clear the envelope counter,
the LFO phase and the noise generator, so the reference (one chip for all songs) and the check carry the chip samples run before a
song (`PRERUN`); only bit-exactness depends on it, not what is audible.

**What a real extraction would need** **[I]**:

- A generator of about 150 lines: the type-3 blob to a register log by the driver of section 2 (events, patch loads, the init
  writes, looping) for a number of loops. Python, reading `NE0SOUND_9158.bin` and eight more from `extracted/` (the importer's
  `extract` step). The `FNUM` table (section 2.6) is the one constant that is not in the blob: row 0 and the formula give it to
  within a count, the exact table is in the DOS executable's data segment.
- The register log to WAV: `ymfm_render` is about 60 lines of C++ plus ymfm (BSD-3-Clause, three source files). A new external
  program for the importer, so: an entry in `tools/import/tool_check.py`, a pin or build in `mise.toml`, a row in `docs/SETUP.md`,
  a step in `tools/setup_windows.ps1` ([`../../AGENTS.md`](../../AGENTS.md) "Tools").
- Or no external program: an OPL2 core in the engine (the chip's operator model, envelope and phase generators are small but exact
  work; ymfm is the reference), which would play the sequences live.

**Three ways to play it, undecided.** (a) *Live ymfm*: the engine runs the driver (a GDScript port of section 2, 200 lines) and an
OPL2 core in an audio stream; exact, loops and the per-scene mutes follow the DOS game, needs the core. (b) *Pre-rendered ymfm*: the
importer renders each loop to an OGG as it does the MIDI songs; no runtime cost, exact sound, but the DOS game's scene mutes
(not recorded here) cannot apply and the loop is fixed length. (c) *FluidSynth with an OPL2 soundfont*: one tool for all three
soundtracks and the engine's existing MIDI path, but the patches are an approximation of the chip. The choice is open.

**Long form or loops.** The DOS soundtrack proper is the nine loops (4 to 8 s) with the scene mutes; the Windows B songs played with
the DOS patches are a different thing: a guess-laden hybrid whose quality depends on section 3. `BNEPT1` has no DOS song at all. The
importer's three soundtracks would be `E*.MID` (FluidR3), `B*.MID` (`opl.sf2`) and the nine DOS loops.

## 5. Getting the data

```sh
# the Windows files (extracted/music, extracted/sounds/fm_patches_undecoded) from your ISO
uv run tools/import/import_all.py --only extract

# the Windows side of the research (reads extracted/; writes under build/adlib/ or $ADLIB_OUT)
uv run tools/analysis/adlib/midi_report.py        # the table of section 1.1
uv run tools/analysis/adlib/compare.py            # B against E
uv run tools/analysis/adlib/poly.py               # polyphony and drum keys
uv run tools/analysis/adlib/patch_decode.py       # the 11-byte patches of the NE0SOUND type-3 resources
YMFM_DIR=<a ymfm checkout> tools/analysis/adlib/build_ymfm_render.sh   # ymfm_render
```

Whoever has a DOS build of the game can capture the register writes of the real driver for each song (every `out` to ports 0x388 /
0x389 with the timer tick it happens in, a few passes of each song's loop) and compare an implementation of section 2 against it
event for event; that is how section 2 was verified. Such a capture is game-derived and is not committed.

## 6. Not known

- The scenes each DOS song belongs to, and the content of the 56 scene records (section 2.9), are not recorded here.
- Whether `BSECT2`, `BSECT3` and `BSECT4` are the right partners (section 1.3), and what device type 0 of the effects is exactly
  (section 1.2, a guess).
- Which playback to build (section 4).
- Whether the same sound has the same bytes across songs (the patch indices differ per song; a comparison of the 11-byte patches
  across the nine blobs would tell which instrument the Windows programs 5, 12, 13, 33, 37 correspond to throughout).
- The PC speaker and Tandy song handlers, and whether shipped play ever selects the MPU-401 one, are not examined.
