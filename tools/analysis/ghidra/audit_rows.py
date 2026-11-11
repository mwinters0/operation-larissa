"""Hand-written annotations for docs/port/AUDIT_CALLSITES.md (see audit_report.py, which merges them with audit_callsites.py's
mechanical call-site list and fails when a site is not covered).

Row = R(table, module, caller, prims, ctx, reach, status, port, impact=None, sites=None, arg=None)
  table   S sound effects, M music, V speech / wave, T timing, I input waits, X text, P pictures / bundle loads
  caller  function name as in names_onwin32.json ('NOFUNC' + sites=[...] for code Ghidra has no function for)
  prims   '*' (every primitive of that table in that caller) or a comma list of primitive names
  status  PORTED | MISSING | DIFFERS | N/A
  impact  for MISSING / DIFFERS: N (noticeable) or C (cosmetic) or G (game-breaking)
"""

ROWS = []


def R(table, module, caller, prims, ctx, reach, status, port, impact=None, sites=None, arg=None):
    ROWS.append(dict(table=table, module=module, caller=caller, prims=prims, ctx=ctx, reach=reach, status=status,
                     port=port, impact=impact, sites=sites, arg=arg))


YES = "yes"

# ================================================================================================================
# S: sound effects (PlaySoundEffect 0x431f1f, RepeatCommonSoundEffect 0x431f97, StopCommonSoundEffect 0x431ef2)
# ================================================================================================================
M = "ACTION.C"
R("S", M, "DoAction", "*", "a piece or the data canister is picked up (CheckProbeCollision hit)", YES, "PORTED",
  "sim_world.gd:take_piece (SFX_PIECE_PICKED_UP 0x1b)")
R("S", M, "ApplyCreatureDamage", "*", "creature contact: damage > 0 and a tank lost (RedrawFrameAfterTankLoss), or damage > 0 with oxygen left. NOT for damage < 0 (Zoom's tank, silent)", YES, "PORTED",
  "sim_world.gd:sub_touches (SFX_CREATURE_HIT 0x1a); its silent Zoom branch (damage < 0) is in the same function")
R("S", "FOES.C", "update_animals", "*", "FoeVM opcode SOUND n (case 7), only when the creature is on CurScreen; id comes from the creature script", YES, "PORTED",
  "foe_vm.gd:_execute_one (FoeOps.Op.SOUND) -> sim_world.gd:_tick_creatures (foe_context.sounds)", arg="script operand")
R("S", "WORLD.C", "DrawScreen", "*", "DrawScreen(1): first screen of a sector (start, respawn, resume). DrawScreen(0) (edge crossings, redraw after a problem) is silent", YES, "PORTED",
  "sim_world.gd:begin_sector_on (SFX_BEGIN 0x16), called by begin_sector and the screen playtest")
R("S", "SOUNDHI.C", "StartStunGun", "*", "fire button: 0x1e when no pellets are left, 0x18 when a pellet is launched (only if fewer than 2 in flight)", YES, "PORTED",
  "sim_world.gd:request_fire (SFX_NO_PELLETS 0x1e), fire_pellet (SFX_INK_FIRED 0x18)")
R("S", "SOUNDHI.C", "UpdateStunGun", "*", "a pellet starts its splash picture (picture 1)", YES, "PORTED", "sim_world.gd:_on_pellet_splashed (SFX_INK_SPLASH 0x19)")
R("S", "SUPPLY.C", "ExitSupplyStation", "*", "launch from the left station: door sound at the instant the door starts to CLOSE behind the sub (state 2, SubX > 0x5f)", YES, "PORTED",
  "sim_world.gd `_advance_sequence` (SFX_STATION_DOOR 0x17) at StationSequence.door_sound_tick (close_start + 1), i.e. with closing picture 3; test_flow_fidelity.gd (door sound) and test_supply_station.gd")
R("S", "SUPPLY.C", "EnterSupplyStation", "*", "docking at the right station: door sound when the door starts to close (state 2, SubX > 0x1c3)", YES, "PORTED",
  "station_sequence.gd:door_sound_tick, same sound; the launch is silent until the door closes (test_flow_fidelity.gd test_the_launch_is_silent_until_the_door_closes)")
R("S", "BEZEL.C", "DisplayShipMathIcon", "*", "a message light turns on (ship light 1,0 or computer light 0,1): math-trigger blink, first piece (computer), pieces-missing message at the dock (ship)", YES, "PORTED",
  "hud.gd:_on_message_light_changed plays SFX_MESSAGE_LIGHT 0x2f for every light that turns on: computer light sim_world.gd:take_piece (canister code), touch_trigger (math trigger); ship light game_flow.gd:on_dock_reached (pieces missing at the dock, off again after the message; test_flow_fidelity.gd test_the_pieces_missing_message_turns_the_ship_light_on_with_its_sound_and_off_after)")
R("S", "CALC.C", "NOFUNC", "*", "HighlightCalcKey (0x41b4f1) switch handlers: every calculator key press (22 keys, mouse or keyboard), key valid or not; the release call is silent", YES, "PORTED",
  "calculator.gd:SFX_KEY (0x1f), emitted for every key by input_key (deferred command key) and press", sites=["0041b7fd"])
R("S", "GETNUM.C", "GetNumber", "*", "'Ans:' box without calculator: Backspace (8) in each of the two input states (even on an empty entry)", YES, "PORTED",
  "answer_box.gd:_unhandled_key_input (SFX_BACKSPACE 0x1f, always, even on an empty entry)")
R("S", "GETNUM.C", "NOFUNC", "*", "GetNumber Backspace branch at 0x41fefd (switch handler Ghidra did not follow), same rule as above", YES, "PORTED",
  "answer_box.gd:_unhandled_key_input, see above", sites=["0041fefd"])
R("S", "BALLAST.C", "GetBallastAnswer", "PlaySoundEffect", "each ballast weight button toggled (label LAB_00419ac7 is reached from the 10 weight hotspots)", YES, "PORTED",
  "ballast_panel_diagram.gd:toggle (SFX_CLICK 0x22); Done clicks too, in _press_done")
R("S", "MATHPROB.C", "DoMathProblem", "*", "right answer 0x20 (first or second try), wrong answer 0x21 (after the first AND after the second try; also in practice mode)", YES, "PORTED",
  "problem_flow.gd:_on_right (SFX_CORRECT 0x20), _lose_oxygen (SFX_WRONG 0x21: emitted before the practice early-return)")
R("S", "LOCK.C", "LockSpinOperandWheel", "*", "operand wheel: tick 0x26 per quarter step, settle 0x27 when it stops", YES, "PORTED",
  "combination_lock.gd:_tick_operands (SFX_TICK 0x26), _operand_landed (SFX_SETTLE 0x27)")
R("S", "LOCK.C", "LockAdvanceAnswerWheel", "*", "answer wheel advances one position: 0x26 per step", YES, "PORTED", "combination_lock.gd:_tick (SFX_TICK 0x26, Phase.ANSWER)")
R("S", "LOCK.C", "LockRunStage", "*", "key window ended on the right label 0x20; wrong or no stop 0x21", YES, "PORTED",
  "problem_screen.gd:_on_lock_right -> problem_flow.gd:lock_stage_right (SFX_CORRECT 0x20); problem_screen.gd:_on_lock_missed -> problem_flow.gd:lock_missed -> _lose_oxygen (SFX_WRONG 0x21)")
R("S", "MONITOR.C", "AnimateBarnacles", "*", "barnacle problem (type 14) intro: 0x24 for each barnacle picture drawn", YES, "PORTED",
  "barnacle_diagram.gd:_schedule_intro (0x24 at the start of each of the three rounds when a healthy barnacle exists; the original's burst of back-to-back calls is one audible sound, DESIGN 5.5)")
R("S", "OPENING.C", "TitleSplash", "*", "title scene: sub enters the water (y > 262) 0x2b", YES, "PORTED", "data/story/title_ship.tres (a sound cue at the splash frame, written by tools/import/step_story.py:build_title_ship)")
R("S", "OPENING.C", "OpeningMusicCue", "PlaySoundEffect", "cue 4: 0x33 sound, then the song stops (the 'next title picture')", YES, "PORTED", "data/story/title_reveal.tres (a sound cue before each title picture, written by tools/import/step_story.py:build_title_reveal)")
R("S", "OPENING.C", "TitleScreenPromptLoop", "*", "title screen ends (timeout 25 s or click): StopCommonSoundEffect before OpeningMusicCue(5)", YES, "N/A",
  "stops a possibly playing effect; the port plays no looping effect on the title")
R("S", "CLOSING.C", "VoyagerClosingSequence", "*", "0x2c when the sub is turned, 0x2d (RepeatCommon, looping) during the rise, StopCommonSoundEffect before the pages", YES, "PORTED",
  "voyager_closing_script.gd:flash_sound / surge_sound (0x2c, 0x2d), cues of the closing timeline played by StorySegment.play_sfx")
R("S", "DATABANK.C", "AnimateLogScan", "*", "canister log screen: scanner 0x1d looping while the 6 x 8 picture sweep runs (240 ticks), then stopped", YES, "PORTED",
  "log_screen.gd:run_scan (SFX_SCANNER 0x1d: play_sfx at the start, stop_sfx when the scan ticks are over); the 6 x 8 picture sweep is advance_scan / _show_scan_picture")
R("S", "SIGNIN.C", "AnimateSecurityScan", "*", "sign-in Start: scanner 0x1d looping for 6 sweeps x 4 pictures x 5 ticks, Enter ends it", YES, "PORTED",
  "sign_in.gd:run_scan (play_sfx, stop_sfx); Enter (or a released click) shortens it as the inner loop does (the picture that shows, then picture 0 for each sweep left, 5 ticks each): skip_scan; the first input is kept as PendingInput: _listen")
R("S", "FOES.C", "AnimateThermometerColumn", "*", "thermometer problems (12, 13): 0x25 looping while the mercury marker moves, 10 ticks per 16 px step", YES, "PORTED",
  "diagram_base.gd:_schedule_intro (intro mode \"run\": 0x25 at t = 30, stop at the end), played by _play; test_diagram_animations_legacy.gd test_type_12_and_13_thermometer_30_ticks_then_mercury_10_ticks_a_piece_then_60_ticks")
R("S", "FOES.C", "Prob30_Diagram", "*", "diagram build-up, type 30: 0x29 per picture, 15 ticks apart, alternating", YES, "PORTED",
  "diagram_base.gd:_schedule_intro (intro mode \"sequence\", 0x29 every 15 ticks, one box per step); test_diagram_animations_legacy.gd test_type_30_storage_boxes_one_box_every_15_ticks")
R("S", "BALLAST.C", "Prob07_Diagram", "*", "type 7 diagram: four values revealed one by one, 0x22 each, 30 ticks apart", YES, "PORTED",
  "diagram_base.gd:_schedule_intro (\"sequence\", 0x22 at t = 0, 30, 60, 90, 120); test_diagram_animations_legacy.gd test_type_7_four_values_one_by_one_30_ticks_apart")
R("S", "CALC.C", "Prob04_Diagram", "*", "type 4 diagram build-up: 0x23 per step, 15-tick cadence (set_alarm / wait_alarm)", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"sequence\", 0x23 every 15 ticks); test_diagram_animations_legacy.gd test_type_4_and_5_four_and_six_pieces_every_15_ticks")
R("S", "OPTIONS.C", "Prob05_Diagram", "*", "type 5 diagram build-up: 0x23 per step, 15-tick cadence", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"sequence\", 0x23 every 15 ticks); test_diagram_animations_legacy.gd test_type_4_and_5_four_and_six_pieces_every_15_ticks")
R("S", "OPTIONS.C", "Prob17_Diagram", "*", "type 17 (pie / food supply): 0x29 per slice, 88 ticks apart (six reveals)", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"sequence\", 0x29 every 88 ticks); test_diagram_animations_legacy.gd test_type_17_pie_the_slices_come_every_88_ticks")
R("S", "ROSTER.C", "Prob32_Diagram", "*", "type 32/33 diagram: 0x29 per drawn item, 2 ticks apart", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"sequence\", 0x29 every 2 ticks; the single wave device makes it a stutter as in the original, but the original also reloads the file from the CD each time, so its real pace is slower); test_diagram_animations_legacy.gd test_type_32_and_33_search_grid_one_square_every_2_ticks")
R("S", "SOUNDHI.C", "Prob02_AnimateBar", "*", "type 2 (speed bar): 0x22 for every 5 mph segment, 6 ticks per segment", YES, "PORTED", "diagram_base.gd:_schedule_intro (intro mode \"bars\": 0x22 per segment, 6 ticks); test_diagram_animations_legacy.gd test_type_2_speed_bars_one_segment_per_6_ticks_and_30_ticks_between_bars")
R("S", "SIGNIN.C", "RadarBlip", "*", "type 3 (radar): 0x29 each time a blip is drawn", YES, "PORTED", "sonar_diagram.gd:animate_to (blip_sfx emitted when the beam reaches the blip)")
R("S", "SUPPLY.C", "Prob20_Diagram", "*", "type 20 diagram: 0x22 per 100 units of the drawn quantity, 10 ticks apart", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"lockstep\": 0x22 per pass, 10 ticks); test_diagram_animations_legacy.gd test_type_20_a_slice_per_100_units_every_10_ticks")
R("S", "SUPPLY.C", "Prob25_Diagram", "*", "type 25: seven items revealed with 0x23, 15 ticks apart", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"sequence\", 0x23 every 15 ticks, none after the seventh); test_diagram_animations_legacy.gd test_type_25_toxicity_graph_seven_readings_15_ticks_apart")
R("S", "SUPPLY.C", "Prob21_Diagram", "*", "type 21 (tank fill): 0x28 looping while the level rises (6 ticks per step), then stopped", YES, "PORTED", "tank_diagram.gd:_schedule_intro (0x28 with the first water frame, 6 ticks per frame, stop when full); test_diagram_animations_legacy.gd test_type_21_tank_the_sound_runs_while_the_level_rises_6_ticks_a_frame")
R("S", "OPTIONS.C", "Prob22_SuccessAnimation", "*", "right answer to type 22: the solution pictures are replayed with 0x29, 22 ticks apart", YES, "PORTED",
  "diagram_base.gd:_success_heading (0x29, 22 ticks), run by problem_screen.gd:_play_replay; test_diagram_animations_legacy.gd test_type_22_the_needle_turns_in_45_degree_steps_to_the_answer")
R("S", "ROSTER.C", "Prob23_SuccessAnimation", "*", "right answer to type 23: replay with 0x29 (22 / 44 tick pauses)", YES, "PORTED", "diagram_base.gd:_schedule_success_replay (\"pictures\", 0x29 at t = 22 and 44); test_diagram_animations_legacy.gd test_type_23_two_pictures_22_and_44_ticks_apart")
R("S", "SIGNIN.C", "Prob26_SuccessAnimation", "*", "right answer to type 26: replay with 0x22, 20 ticks per step", YES, "PORTED", "diagram_base.gd:_success_needle (0x22, 20 ticks); test_diagram_animations_legacy.gd test_type_26_and_27_the_needle_moves_one_step_every_20_ticks_and_ends_on_the_answer")
R("S", "ROSTER.C", "Prob27_SuccessAnimation", "*", "right answer to type 27: replay with 0x22, 20 ticks per step", YES, "PORTED", "diagram_base.gd:_success_needle, see above")
R("S", "SOUNDHI.C", "PlaySoundEffect", "*", "internal: StopCommonSoundEffect before loading an effect that is not cached (one wave device, a new sound cuts the old one)", YES, "PORTED",
  "audio.gd:play_sfx: ONE effect player; a new effect replaces the sounding one and cuts a speech clip (_resume_voice_after_sfx), and speech cuts an effect (play_voice_sequence); documented in the header comment of audio.gd")
R("S", "SOUNDHI.C", "RepeatCommonSoundEffect", "*", "internal: same body as PlaySoundEffect in the 32-bit build", YES, "N/A", "audio.gd:play_sfx")
R("S", "SOUNDHI.C", "SetSoundOn", "*", "Options > Sound Effects off: StopCommonSoundEffect for each of the 0x34 effects", YES, "PORTED", "audio.gd:set_bus_enabled -> stop_sfx")

# ================================================================================================================
# M: music (PlayBackgroundMusic 0x43206e, StopBackgroundMusic 0x43208f, PlaySectorMusic, StopSectorMusic, expert, pause / resume)
# ================================================================================================================
R("M", "ACTION.C", "DoAction", "PlaySectorMusic", "PlaySectorMusic(1) at sector start (4180b6), after a math problem (418129 / 418145), after the dock message when pieces are missing (4181df), after the lock opened (41822d) and again before LaunchBalloon (41824c); PlaySectorMusic(0) at the four screen edges is a no-op", YES, "PORTED",
  "game_flow.gd:begin_sector (sector start), open_problem (after a problem), on_dock_reached (after the pieces-missing message), complete_sector (docking song after the lock opened, and again before the balloon), played by game.gd:play_sector_music; test_flow_fidelity.gd test_the_lock_opening_plays_the_song_while_docking_is_silent_on_the_map_and_plays_for_the_balloon and test_flow_fidelity_legacy.gd test_the_songs_around_the_dock_are_the_originals",
  sites=["004180b6", "00418129", "00418145", "004181df", "0041822d", "0041824c"])
R("M", "ACTION.C", "DoAction", "PlaySectorMusic", "PlaySectorMusic(0): the four screen-edge crossings (no-op, the song plays on)", YES, "PORTED",
  "no restart at a screen change (no music call in sector_world.gd; comment at sim_world.gd:_on_sub_crossed_edge)", sites=["00418634", "004186dc", "00418779", "00418821"])
R("M", "ACTION.C", "DoAction", "StopSectorMusic", "song stops: when the blinking-light problem opens (4180f1+), at the supply dock (StopSectorMusic before CountPiecesRemaining), and again before DisplaySupplyStationMessage", YES, "PORTED",
  "game_flow.gd:run_problem (problem opens), on_dock_reached (dock), complete_sector (silence for the supply message)")
R("M", "CLOSING.C", "VoyagerClosingSequence", "StopSectorMusic,PlayBackgroundMusic,StopBackgroundMusic", "StopSectorMusic at the start; 'if (DAT_00446600 != 0) PlayBackgroundMusic(0)' is dead (DAT_00446600 is never written, always 0); StopBackgroundMusic after the pages", "partly (the PlayBackgroundMusic branch is dead)", "PORTED",
  "game_flow.gd:play_closing (stop_music before the closing starts); voyager_closing.gd:show_pages (stop_music)")
R("M", "CLOSING.C", "ExpertClosingSequence", "StopSectorMusic,PlayExpertClosingMusic", "closing song (id 9501) starts with the sequence", YES, "PORTED", "expert_closing.gd:_ready (SONG_CLOSING)")
R("M", "CLOSING.C", "ExpertClosingSequence", "StopBackgroundMusic", "song stops when the sequence ends (before the Hall of Fame)", YES, "PORTED",
  "expert_closing.gd:finish (stop_music when the sequence ends, before the Hall of Fame); test_flow_fidelity_legacy.gd test_the_expert_closing_song_ends_with_the_sequence")
R("M", "OPENING.C", "OpeningMusicCue", "PlayBackgroundMusic,StopBackgroundMusic", "cue 1: 9502 (opening cartoon) ; cue 3: 9503 (title) ; cue 4: stop after the 0x33 sound ; cue 5: stop, play 9502 ; cue 6: stop", YES, "PORTED",
  "news_cartoon.gd:_ready (9502), title_scene.gd:_ready (9503), _leave_ship_scene (stop), _show_prompt (9502), opening.gd:_ready and _leave (stop)")
R("M", "SOUNDHI.C", "PlaySectorMusic", "*", "internal: if flag != 0 PlayBackgroundMusic(SectorMusicId)", YES, "PORTED", "audio.gd:play_music")
R("M", "SOUNDHI.C", "StopSectorMusic", "*", "internal: StopBackgroundMusic", YES, "PORTED", "audio.gd:stop_music")
R("M", "SOUNDHI.C", "PlayExpertClosingMusic", "*", "internal: PlayBackgroundMusic(DAT_0044b040)", YES, "PORTED", "audio.gd:play_music")
R("M", "SOUNDHI.C", "SetMusicOn", "*", "Options > Music turned on: PlayBackgroundMusic(current song id)", YES, "PORTED", "audio.gd:set_music_on (bus mute; on: the remembered song restarts from the beginning)")
R("M", "SOUNDHI.C", "FreeSectorStopMusic", "*", "FreeSectorResources stops the song (sector change / leaving the game)", YES, "PORTED", "game.gd:_leave stop_music")
R("M", "SOUNDHI.C", "FreeClosingStopMusic", "*", "FreeClosingResources stops the song", YES, "PORTED", "voyager_closing.gd:show_pages (stop_music)")
R("M", "SOUNDHI.C", "StopMusicUnused", "*", "no caller (dead code)", "dead", "N/A", "-")
R("M", "WMIDI.C", "PauseSoundOnDeactivate", "*", "window loses focus (WM_ACTIVATE 0x41312f; also WM_ENTERMENULOOP): pause_sound (wave killed, song paused); the game loop stands still too (PollInputEvent 0x410bc5 does not return while WindowActive 0x440d80 is 0)", YES, "PORTED",
  "audio.gd:_notification (NOTIFICATION_APPLICATION_FOCUS_OUT, only while WindowFocus.enabled: off under a script-driven run such as the test runner) -> pause_sound_on_deactivate (flag _window_active, asking twice pauses once) -> pause_sound; the clock: game_clock.gd:_notification sets window_active (read by paused), so no tick is emitted and nothing catches up; an open menu is the same state: game_menu_bar.gd:_add_menu (about_to_popup) -> _enter_menu_loop; test_sound_pause.gd")
R("M", "WMIDI.C", "ResumeSoundOnActivate", "*", "window regains focus (WM_ACTIVATE, WM_EXITMENULOOP): resume_sound", YES, "PORTED",
  "audio.gd:_notification (NOTIFICATION_APPLICATION_FOCUS_IN) -> resume_sound_on_activate -> resume_sound; game_clock.gd:_notification; game_menu_bar.gd:_add_menu (popup_hide) -> _exit_menu_loop")
R("M", "WWAVE.C", "PauseSoundForDialog", "*", "every modal dialog (RunModalDialog, RunPagedDialog, SaveAndExit, JustExit, hall of fame, sign-in dialogs, the customization dialog) pauses the song and kills the speech", YES, "PORTED",
  "game.gd:_on_message_shown (every message) / _show_modal Audio.pause_sound = KillWave + song held (audio.gd:pause_sound, see V table, pause_sound). Original callers: RunModalDialog, RunPagedDialog, SaveAndExit, JustExit, show_hall_of_fame, the customization dialog, ChooseGameLevelDialog; port: messages = RunModalDialog / SaveAndExit / JustExit, _show_modal = help (RunPagedDialog), hall of fame, customization (+ our audio settings dialog); the sign-in screen's own dialogs are not hooked (nothing sounds there)")
R("M", "WWAVE.C", "ResumeSoundAfterDialog", "*", "dialog closed: resume the song from the same place", YES, "PORTED", "game.gd:_on_message_shown / _show_modal Audio.resume_sound (audio.gd:resume_sound)")
R("M", "NEPTUNE.C", "NOFUNC", "PauseSoundForDialog,ResumeSoundAfterDialog", "undefined region 0x41d5c8-0x41d99d (the Problem Customization dialog loop, no Ghidra function)", YES, "PORTED",
  "game.gd:_show_modal wraps every dialog", sites=["0041d5ec", "0041d987"])
R("M", "OPTIONS.C", "SaveAndExit", "PauseSoundForDialog,ResumeSoundAfterDialog", "'save and exit?' dialog pauses / resumes the song", YES, "PORTED", "game.gd:_on_message_shown via messages")
R("M", "OPTIONS.C", "JustExit", "PauseSoundForDialog,ResumeSoundAfterDialog", "'quit without saving?' dialog", YES, "PORTED", "game.gd:_on_message_shown")
R("M", "OPTIONS.C", "show_hall_of_fame", "PauseSoundForDialog,ResumeSoundAfterDialog", "Hall of Fame screen pauses the song", YES, "PORTED", "game.gd:_show_modal (show_hall_of_fame is a modal)")
R("M", "SIGNIN.C", "ChooseGameLevelDialog", "PauseSoundForDialog,ResumeSoundAfterDialog", "game-level chooser", YES, "N/A", "no music runs on the sign-in screen (sign_in.gd:_ready stops it)")

# ================================================================================================================
# V: speech / wave (LoadSpeechClip 0x411315, PlayWave 0x4150c4, KillWave 0x4151a4, IsWavePlaying, set_sample_speed)
# ================================================================================================================
R("V", "CLOSING.C", "PlayVoyagerClosingSpeech", "*", "page 0 first plays 'incoming transmission' (logical 0x2df = clip 4243), then the page's 1-3 clips; Enter / Esc cuts the clip and the rest of the page", YES, "PORTED",
  "voyager_closing.gd:show_pages (jingle + closing_page, stop_voice)")
R("V", "DATABANK.C", "PlayLogEntrySpeech", "*", "canister log entry n read aloud (5-8 clips); Enter / Esc / arrow keys cut it", YES, "PORTED", "log_screen.gd:_speak (the clips of the entry from voice_cues); Esc / Enter / arrows cut it: _input, press, _leave")
R("V", "OPENING.C", "CartoonSpeech", "*", "news cartoon voices and beeps (logical 39 + n = clips 4000-4010), state 1-11, at 8000 Hz", YES, "PORTED", "news_cartoon.gd:_speak (Audio.speak)")
R("V", "OPENING.C", "PlayStoryPageSpeech", "*", "opening story page n: 1-3 clips (4011-4029), Space / Enter / Esc cuts", YES, "PORTED", "story_pages.gd:_page_clock (Audio.speak), advance (stop_voice)")
R("V", "OPENING.C", "OpeningSequence", "KillWave,set_sample_speed", "KillWave at the end of the cartoon; set_sample_speed(8000) before the cartoon and set_sample_speed(16000) after it (never undone)", YES, "PORTED",
  "rates are baked into the extracted WAV headers (DESIGN 7)")
R("V", "SIGNIN.C", "SignInSpeech", "*", "stage 1: clips 0x2e1 / 0x2e4 (classified mission, enter your name); stage 2/3: scanner then 0x2e7 'Security clearance issued' and 0x2ea / 0x2ed 'Begin / Resume mission'; Esc, Enter or a click cuts", YES, "PORTED",
  "synchronous like the original (IsWavePlaying loops): sign_in.gd:_first_visit_speech (called from _ready; the list sleeps via _busy; any key or mouse press cuts both clips and is then replayed to the list, as PeekInput leaves it pending) and request_start -> _enter_game -> _speak (awaits Audio.voice_finished; the game starts only after the last clip: SceneRouter.go_to); inputs: _listen (scan: Enter / released click end it, first input is kept; clearance speech: Esc / Enter / released click cut, other keys swallowed); Voice off: _speak starts nothing and does not wait (KillWave, no PlayWave, IsWavePlaying false); _enter_game applies the player's Voice option first (Audio.apply_profile copies VoiceOn before SignInSpeech); tests: test_sign_in_ui.gd (welcome_speech_*, start_waits_*, enter_/escape_during_the_scan_*)")
R("V", "SUPPLY.C", "PlaySupplyMessageSpeech", "*", "surface ship screen after a sector: 'incoming transmission' (0x2df) then the sector's 2-5 clips", YES, "PORTED", "surface_ship_screen.gd:show_supply_message (jingle + supply), finish -> stop_voice")
R("V", "MATHPROB.C", "DoCombinationLock", "LoadSpeechClip", "LoadSpeechClip(0x1a0) is the loose lock-screen picture (not speech)", YES, "N/A", "picture, see P table")
R("V", "MATHPROB.C", "DrawProblemBackground", "LoadSpeechClip", "LoadSpeechClip(0xf3) is the problem-screen background picture (not speech)", YES, "N/A", "picture")
R("V", "OPENING.C", "CartoonDrawMap", "LoadSpeechClip", "LoadSpeechClip(8): a cartoon picture (not speech)", YES, "N/A", "picture")
R("V", "OPENING.C", "StoryDrawLoosePicture", "LoadSpeechClip", "draws opening picture param_3 (not speech)", YES, "N/A", "picture")
R("V", "WORLD.C", "DrawScreen", "LoadSpeechClip", "screen still picture 23000 + sector * 12 + screen (not speech)", YES, "N/A", "picture")
R("V", "WWAVE.C", "MainWindowProc", "*", "MM_WOM_DONE (0x3bd): KillWave closes the finished clip", YES, "N/A", "AudioStreamPlayer.finished -> audio.gd:_on_voice_player_finished")
R("V", "WWAVE.C", "pause_sound", "*", "pause level 1 kills the wave and pauses the song", YES, "PORTED",
  "audio.gd:pause_sound = kill_wave (effect stopped, speech clip stopped, its sequence waits) + pause_music (levels nest, resume_sound lets the sequence go on with its next clip, as the IsWavePlaying loop does); callers game.gd:_on_message_shown / _show_modal, focus audio.gd:pause_sound_on_deactivate; test_sound_pause.gd")
R("V", "WWAVE.C", "PlayWave", "*", "internal: KillWave before opening the device", YES, "N/A", "-")
R("V", "WWAVE.C", "IsWavePlaying", "*", "internal: KillWave when MM_WOM_DONE arrives", YES, "N/A", "-")
R("V", "WWAVE.C", "ShutdownSoundAndMidi", "*", "program exit", YES, "N/A", "-")
R("V", "WWAVE.C", "PlayWaveUntilKey", "*", "no caller: dead code", "dead", "N/A", "-")
R("V", "WWAVE.C", "PlayWaveBlocking", "*", "no caller: dead code", "dead", "N/A", "-")
R("V", "SOUNDHI.C", "PlaySoundEffect", "*", "internal: set_sample_speed(-1) around PlayWave (effects always at the header rate 22050), restore after", YES, "N/A", "-")
R("V", "SOUNDHI.C", "RepeatCommonSoundEffect", "*", "internal, same as PlaySoundEffect", YES, "N/A", "-")
R("V", "SOUNDHI.C", "StopCommonSoundEffect", "*", "internal: KillWave", YES, "N/A", "-")
R("V", "SOUNDHI.C", "ToggleAllSound", "*", "all-sound toggle (dead: no caller, no pointer): all three off -> KillWave", "dead", "N/A", "audio.gd:set_bus_enabled per-bus switches")

# ================================================================================================================
# T: timing (DelayTicks, set_alarm, wait_alarm, alarm_expired, WaitKeyOrTicks); 73 ticks = 1 s
# ================================================================================================================
R("T", "ACTION.C", "DoAction", "set_alarm,wait_alarm", "game frame: set_alarm(0, 6) at the top, wait_alarm(0) at the bottom (12.17 frames/s)", YES, "PORTED", "game_clock.gd:TICK_HZ (73 / 6)")
R("T", "TEXTHI.C", "WrapTextLayout", "wait_alarm", "wait_alarm(6) per character in the text engine; alarm slot 6 is never set by any set_alarm call in the EXE (slots used: 0, 1, 2), so the wait returns at once", "no-op", "N/A", "-")
R("T", "BALLAST.C", "GetBallastAnswer", "DelayTicks", "after the ballast answer is confirmed: the pressed OK picture stays 73 ticks (1 s) before returning to the checker", YES, "PORTED",
  "ballast_panel_diagram.gd:_press_done (pressed OK picture, held for total.hold_ticks = 73 ticks by problem_flow.gd:hold_ballast, then submitted); test_diagram_animations_legacy.gd test_ballast_done_clicks_shows_the_pressed_ok_and_tells_the_flow_to_hold_73_ticks")
R("T", "CALC.C", "BlinkButton", "set_alarm,wait_alarm", "keyboard / mouse hit on a calculator key in GetAnswer: key highlighted 12 ticks (0.16 s), input blocked meanwhile", YES, "PORTED",
  "calculator.gd:input_key (deferred command key for a displayed result), _start_flash / end_flash (calculator.key_flash_ticks of data/rules/durations.json); keys during the flash queue in input_key")
R("T", "GETNUM.C", "GetNumber", "set_alarm,wait_alarm", "every key in calculator mode: highlight on, 12-tick hold (set_alarm(0,12)), redraw LCD, wait_alarm, highlight off", YES, "PORTED",
  "calculator.gd:input_key / _start_flash (12-tick flash and input lock), same as BlinkButton")
R("T", "BALLAST.C", "Prob07_Diagram", "DelayTicks", "type 7: 30 ticks between each of the four revealed values", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"sequence\", interval 30)")
R("T", "FOES.C", "Prob30_Diagram", "DelayTicks", "type 30: 15 ticks per picture", YES, "PORTED", "diagram_base.gd:_schedule_intro (interval 15)")
R("T", "FOES.C", "AnimateThermometerColumn", "set_alarm,wait_alarm", "thermometer: 10 ticks per 16 px mercury step", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"run\": lead 30, 10 ticks per piece, trail 60)")
R("T", "FOES.C", "AnimateThermometerSolution", "DelayTicks", "type 12 right answer: 73 ticks, mercury moves, 30 ticks", YES, "PORTED", "diagram_base.gd:_success_thermometer (lead 73, 10 ticks per piece, trail 30); test_diagram_animations_legacy.gd test_type_12_the_mercury_moves_to_the_answer_after_73_ticks")
R("T", "FOES.C", "Prob12_Diagram", "DelayTicks", "type 12 diagram: 30 ticks, mercury rises, 60 ticks", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"run\"), test_diagram_animations_legacy.gd test_type_12_and_13_thermometer_30_ticks_then_mercury_10_ticks_a_piece_then_60_ticks")
R("T", "FOES.C", "Prob13_Diagram", "DelayTicks", "type 13 diagram: 30 ticks, mercury, 60 ticks", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"run\"), test_diagram_animations_legacy.gd test_type_12_and_13_thermometer_30_ticks_then_mercury_10_ticks_a_piece_then_60_ticks")
R("T", "CALC.C", "Prob04_Diagram", "set_alarm,wait_alarm", "type 4: 15-tick cadence", YES, "PORTED", "diagram_base.gd:_schedule_intro (interval 15)")
R("T", "OPTIONS.C", "Prob05_Diagram", "set_alarm,wait_alarm", "type 5: 15-tick cadence", YES, "PORTED", "diagram_base.gd:_schedule_intro (interval 15)")
R("T", "OPTIONS.C", "Prob22_SuccessAnimation", "DelayTicks", "type 22 right answer: 22 ticks between pictures", YES, "PORTED", "diagram_base.gd:_success_heading (22 ticks per picture + 22)")
R("T", "LOCK.C", "LockSpinOperandWheel", "set_alarm,wait_alarm", "9 ticks per quarter step of the operand wheel", YES, "PORTED", "combination_lock.gd (advance_ticks; wheel step 9 ticks)")
R("T", "LOCK.C", "LockAdvanceAnswerWheel", "set_alarm,wait_alarm", "9 ticks per answer wheel step", YES, "PORTED", "combination_lock.gd:_tick (Phase.ANSWER)")
R("T", "LOCK.C", "LockRunStage", "set_alarm,alarm_expired", "73-tick key window (0x49) on the answer wheel", YES, "PORTED", "combination_lock.gd Phase.ANSWER")
R("T", "LOCK.C", "LockRunStage", "WaitKeyOrTicks", "OUT OF TIME / ERROR message and the worked solution: up to 146 ticks or Enter / click", YES, "PORTED", "ProblemFlow.message_ticks (problem.message_ticks of data/rules/durations.json), used by combination_lock.gd:_miss / _notice")
R("T", "LOCK.C", "LockRevealOperator", "*", "after every number: 146-tick blank, operator 24 on / 24 off / on", YES, "PORTED", "combination_lock.gd:OPERATOR_REVEAL")
R("T", "LOCK.C", "DoCombinationLock", "WaitKeyOrTicks", "lock intro and notice messages: up to 146 ticks or Enter / click", YES, "PORTED", "ProblemFlow.message_ticks, used by combination_lock.gd:_notice (Phase.INTRO / NOTICE)")
R("T", "MATHPROB.C", "ShowWrongAnswerNotice", "WaitKeyOrTicks", "after a WRONG answer: the monitor shows string 11000 'Error!' for up to 146 ticks / Enter; after the second wrong answer string 11114 'Problem has been directed to ship ...' (unless the type is in the 10-entry table at 0x442984)", YES, "PORTED",
  "problem_flow.gd:_on_wrong ('Error!' 11000 for message_ticks() = 146, _show_message), then _after_error: the hint or 11114 'directed to ship' except for the 10 types of NO_SHIP_NOTICE_TYPES)",
  arg="0x92 = 146")
R("T", "MATHPROB.C", "ShowSuccessMessage", "WaitKeyOrTicks", "final statement of every right answer: the success text stays up to 146 ticks or until Enter / click (self-advances)", YES, "PORTED",
  "problem_flow.gd:_show_success -> _after_replay -> _show_message (message_ticks() = 146, Enter / click skips); test_problem_flow.gd test_the_success_text_goes_on_by_itself_and_enter_skips_it")
R("T", "MATHPROB.C", "ShowCorrectPhrase", "WaitKeyOrTicks", "practice mode, right answer: random 'Correct.' / 'That's right.' / 'Good answer.' / 'Very good.' (11110-11113) up to 146 ticks", YES, "PORTED",
  "correct_phrase.gd:pick (11110 + rand % 4), shown by problem_flow.gd:_on_right for message_ticks()")
R("T", "CALC.C", "WaitKeyOrTicks", "set_alarm,alarm_expired", "internal of WaitKeyOrTicks: set_alarm(0, n), poll for Enter / click, Esc -> SaveAndExit", YES, "PORTED", "problem_flow.gd:message_ticks, _show_message / _wait_for_continue, advance_ticks, press_continue; combination_lock.gd:_notice")
R("T", "MONITOR.C", "AnimateBarnacles", "DelayTicks", "barnacle intro: two healthy pictures alternate with 30 and 40 ticks, three times", YES, "PORTED", "barnacle_diagram.gd:_schedule_intro (ticks from data)")
R("T", "MONITOR.C", "do_ccmonitor_opening", "DelayTicks", "20 ticks after the barnacle animation, before the prompt", YES, "PORTED", "barnacle_diagram.gd:_schedule_intro (end_tick = 3 rounds + plan.tail = 20); test_diagram_animations_legacy.gd test_type_14_barnacles_a_burst_of_sounds_at_the_start_of_each_of_three_rounds")
R("T", "OPENING.C", "OpeningStoryPages", "*", "story pages: DelayTicks(15) between pages, page min 365 ticks (5 s), last page 3285 ticks (45 s) or key", YES, "PORTED", "story_pages.gd:_script (Catalog.story_script: data/story/story_script.tres)")
R("T", "OPENING.C", "OpeningSequence", "*", "cartoon redraw every 10 ticks, title scene 12-tick steps; WaitEnterSpaceEscOrTicks(292) holds", YES, "PORTED", "news_cartoon.gd:REDRAW_TICKS, data/story/title_ship.tres (12-tick steps), data/story/title_reveal.tres (292-tick holds)")
R("T", "OPENING.C", "TitleScreenPromptLoop", "*", "title screen: 292-tick hold per picture, 1825-tick (25 s) prompt timeout", YES, "PORTED", "title_scene.gd:PROMPT_TIMEOUT, data/story/title_reveal.tres (292-tick holds)")
R("T", "OPENING.C", "WaitEnterSpaceEscOrTicks", "*", "wait n ticks (292) for Enter / Space / Esc", YES, "PORTED", "data/story/title_reveal.tres (marks, 292 ticks), title_scene.gd:advance / _end_hold")
R("T", "OPENING.C", "CartoonTypeLine", "*", "cartoon teletype: 2 + 1 ticks per character (3 ticks)", YES, "PORTED", "news_cartoon.gd header comment (3 ticks per character), data/story/news_cartoon.tres")
R("T", "CLOSING.C", "VoyagerClosingSequence", "*", "6-tick steps (rise, turn, fly), 12-tick pictures for the transformation", YES, "PORTED", "voyager_closing_script.gd:step_ticks (6), change_picture_steps")
R("T", "CLOSING.C", "ExpertClosingSequence", "*", "18-tick steps for the whole choreography", YES, "PORTED", "data/story/expert_hoist.tres, expert_deck.tres, expert_wait.tres (18-tick steps)")
R("T", "DATABANK.C", "AnimateLogScan", "DelayTicks", "scan picture 5 ticks x 8 pictures x 6 sweeps = 240 ticks", YES, "PORTED", "data/rules/durations.json log_scan (ticks_per_picture 5, sweeps 6; CanisterLog.scan_ticks), log_screen.gd:advance_scan / _show_scan_picture")
R("T", "SIGNIN.C", "AnimateSecurityScan", "DelayTicks", "scan picture 5 ticks", YES, "PORTED", "sign_in.gd:scan_picture_ticks")
R("T", "SIGNIN.C", "SignInSpeech", "DelayTicks", "stage 2/3: 18 ticks before the scan", YES, "PORTED", "sign_in.gd:pre_scan_ticks (_enter_game)")
R("T", "SIGNIN.C", "SignInScreenLoop", "DelayTicks", "36 ticks (0.5 s) of button feedback (Start / New / Practice / Exit pressed look)", YES, "PORTED", "sign_in.gd:pressed_ticks 36: Start when the game is customized (_enter_game), New (request_new_player); Practice and Exit look pressed at once (request_practice, _ask_exit_question); test_flow_fidelity.gd test_new_wears_its_pressed_look_for_36_ticks_before_the_dialog_opens")
R("T", "SIGNIN.C", "FlashScrollArrow", "DelayTicks", "2 ticks arrow highlight", YES, "N/A", "UI hover state")
R("T", "SIGNIN.C", "WaitKeyBlinkCaret", "set_alarm,alarm_expired", "name-entry caret blinks every 14 ticks", YES, "N/A", "LineEdit caret blink (Godot)")
R("T", "WWAVE.C", "FlashDialogButton", "DelayTicks", "dialog button chosen: pressed look for 4 x 4 ticks (16 ticks) before the dialog closes", YES, "N/A", "Button pressed state")
R("T", "SIGNIN.C", "RadarBlip", "set_alarm,wait_alarm", "2 ticks per blip picture (3 pictures)", YES, "PORTED", "sonar_diagram.gd:animate_to (the blip pictures)")
R("T", "SIGNIN.C", "RadarSweep", "set_alarm,wait_alarm", "2 turns x 12 steps x 6 ticks", YES, "PORTED", "sonar_diagram.gd:sweep_ticks (ticks_per_step)")
R("T", "SIGNIN.C", "Prob26_SuccessAnimation", "DelayTicks", "20 ticks per step", YES, "PORTED", "diagram_base.gd:_success_needle (interval 20)")
R("T", "ROSTER.C", "Prob27_SuccessAnimation", "DelayTicks", "20 ticks per step", YES, "PORTED", "diagram_base.gd:_success_needle (interval 20)")
R("T", "ROSTER.C", "Prob23_SuccessAnimation", "DelayTicks", "22 / 44 ticks", YES, "PORTED", "diagram_base.gd:_schedule_success_replay (frames at t = 22, 44, end 88)")
R("T", "ROSTER.C", "Prob32_Diagram", "DelayTicks", "2 ticks per item", YES, "PORTED", "diagram_base.gd:_schedule_intro (interval 2)")
R("T", "OPTIONS.C", "Prob17_Diagram", "DelayTicks", "88 ticks per pie slice", YES, "PORTED", "diagram_base.gd:_schedule_intro (interval 88, trailing)")
R("T", "SOUNDHI.C", "Prob02_AnimateBar", "set_alarm,wait_alarm", "6 ticks per bar segment", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"bars\": interval 6)")
R("T", "SOUNDHI.C", "Prob02_Diagram", "DelayTicks", "30 ticks x 5 between the speed bar steps", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"bars\": gap 30 between the bars)")
R("T", "SUPPLY.C", "Prob20_Diagram", "DelayTicks", "10 ticks per 100 units", YES, "PORTED", "diagram_base.gd:_schedule_intro (\"lockstep\": interval 10)")
R("T", "SUPPLY.C", "Prob25_Diagram", "DelayTicks", "15 ticks x 6", YES, "PORTED", "diagram_base.gd:_schedule_intro (interval 15, no trailing)")
R("T", "SUPPLY.C", "Prob21_Diagram", "set_alarm,wait_alarm", "6 ticks per tank level step", YES, "PORTED", "tank_diagram.gd:_schedule_intro (interval 6 per water frame)")
R("T", "SUPPLY.C", "ExitSupplyStation", "set_alarm,wait_alarm", "6-tick frames of the launch drive", YES, "PORTED", "station_sequence.gd (one step per SimWorld tick = 6 ticks; lengths in data/rules/durations.json station.launch), shown by supply_station.gd:show_sequence")
R("T", "SUPPLY.C", "EnterSupplyStation", "set_alarm,wait_alarm", "6-tick frames of the docking drive", YES, "PORTED", "station_sequence.gd (one step per SimWorld tick = 6 ticks; lengths in data/rules/durations.json station.dock), shown by supply_station.gd:show_sequence")
R("T", "SUPPLY.C", "LaunchBalloon", "set_alarm,wait_alarm", "6-tick frames, balloon rises 4 px per tick", YES, "PORTED", "supply_station.gd show_sequence (balloon behind the station; ticks counted by StationSequence.balloon)")
R("T", "SUPPLY.C", "WaitEnterOrTicks", "set_alarm,alarm_expired", "supply message screen: up to 1460 ticks (20 s) for Enter; Esc = SaveAndExit", YES, "PORTED", "surface_ship_screen.gd:wait_ticks (surface_ship.wait_ticks 1460)")

R("I", "MATHPROB.C", "NOFUNC", "WaitForInput", "dead function at 0x4232a0 (no caller, no pointer to it): shows string 0x2b38 + (n % 15) / 3 and waits for Enter", "dead", "N/A", "-", sites=["0042331c"])

# ================================================================================================================
# I: blocking input waits (WaitForInput 0x415b6c). PeekInput / FlushInput sites are listed by audit_report.py automatically
# ================================================================================================================
R("I", "ACTION.C", "DoAction", "WaitForInput", "inside the 6-tick frame loop: when PeekInput reports a key it is taken (Esc -> SaveAndExit, Enter -> math problem if the light is on)", YES, "PORTED", "game.gd:_unhandled_input (Esc); sector_world.gd:_unhandled_input (Enter) -> sim_world.gd:open_pending_problem")
R("I", "BALLAST.C", "GetBallastAnswer", "WaitForInput", "ballast picker main loop: hotspot ids 3000-3010, Esc -> SaveAndExit, Enter confirms", YES, "PORTED", "ballast_panel_diagram.gd")
R("I", "MATHPROB.C", "ShowProblemSolution", "WaitForInput", "after the second wrong answer: the solution text waits for Enter ('Click to go on.', string 11003)", YES, "PORTED", "problem_flow.gd:_show_solution (Step.SOLUTION), press_continue; problem_screen.gd:_show_go_on ('Click to go on.' label)")
R("I", "SUPPLY.C", "PiecesNotCollectedMessage", "WaitForInput", "pieces-missing message at the dock waits for Enter (Esc -> SaveAndExit)", YES, "PORTED", "game_flow.gd:on_dock_reached (await view.show_pieces_missing) -> game.gd:show_pieces_missing waits for the surface ship screen's finished")
R("I", "OPTIONS.C", "show_hall_of_fame", "WaitForInput", "Hall of Fame waits for a key", YES, "PORTED", "hall_of_fame_view.gd")
R("I", "DATABANK.C", "DoDataBank", "WaitForInput", "canister log menu: arrow keys / mouse pick one of the 15 entries, Enter plays it, 'DONE' or Esc leaves", YES, "PORTED", "log_screen.gd:_input, press, click_row, _activate (arrows / 8 2 4 6 / Enter / Esc / mouse; DONE row leaves); test_log_screen.gd")
R("I", "SIGNIN.C", "SignInScreenLoop", "WaitForInput", "sign-in list: arrows / mouse pick a player, Start / New / Practice / Exit buttons", YES, "PORTED", "sign_in.gd")
R("I", "PRACTICE.C", "PracticeSetupDialog", "WaitForInput", "practice-set setup dialog", YES, "PORTED", "practice_setup_dialog.gd")
R("I", "SIGNIN.C", "ChooseGameLevelDialog", "WaitForInput", "Voyager / Expert chooser for a new player", YES, "PORTED", "new_player_dialog.gd")
R("I", "CALC.C", "WaitKeyOrTicks", "WaitForInput", "internal: the key that ended the wait", YES, "N/A", "-")
R("I", "SUPPLY.C", "ExitSupplyStation", "WaitForInput", "a key pressed during the launch drive is swallowed (Esc included: no SaveAndExit there)", YES, "PORTED", "controls disabled during launch (sim_world.gd:start_launch sets sub.controlled = false)")
R("I", "SUPPLY.C", "EnterSupplyStation", "WaitForInput", "keys swallowed during docking", YES, "PORTED", "same")
R("I", "SUPPLY.C", "LaunchBalloon", "WaitForInput", "keys swallowed during the balloon", YES, "PORTED", "same")

# ================================================================================================================
# X: text (LoadStringResource 0x411726 = string table id; shown to the player unless noted)
# ================================================================================================================
NA_BOOT = "start-up / out-of-memory error boxes of the 1997 Windows runtime; no Godot equivalent needed"
R("X", "WFILE.C", "GetResource", "*", "'Not found or out of memory!' / 'Resource Load Failed' MessageBox when a resource cannot be loaded", "error path", "N/A", NA_BOOT)
R("X", "WGR.C", "LoadWinGDLL", "*", "WinG / video mode errors ('WinG graphic subsystem not found ...')", "error path", "N/A", NA_BOOT)
R("X", "WMEMORY.C", "MALLOC", "*", "'You are out of memory.' (GlobalAlloc failed)", "error path", "N/A", NA_BOOT)
R("X", "WSTARTUP.C", "InitInstance", "*", "'Error creating window'", "error path", "N/A", NA_BOOT)
R("X", "WSTARTUP.C", "InitApp", "*", "'Could not find Resource File!'", "error path", "N/A", NA_BOOT)
R("X", "WSTARTUP.C", "CheckSoundDllSize", "*", "'Data file missing - Please insert the Operation Neptune CD-ROM ...' (title 'Operation Neptune')", "error path", "N/A", NA_BOOT)
R("X", "WSTARTUP.C", "CreateTextFont", "*", "font parameters ('19', '7', '7', 'Arial'), not text for the player", YES, "N/A", "Godot theme font (theme_builder.gd)")
R("X", "TEXTHI.C", "LoadDialogButtonLabels", "*", "dialog button / footer labels: 'Go Back', 'Click to go on.', 'Done', 'Cancel', 'Yes', 'No' ...", YES, "PORTED", "message_box.gd, help_viewer.gd, game_flow.gd (11003, 11009-11013 ids; Yes / No literals)")
R("X", "BALLAST.C", "LoadBallastLabels", "*", "ballast weight labels '0.01' ... (11215-11218) loaded over display mode 1 (level 3)", YES, "PORTED",
  "step_problems.py:ballast_labels puts the loaded strings in the type's `labels` (read by AnswerChecker.denomination_labels, ballast_panel_diagram.gd:_build)")
R("X", "CALC.C", "GetAnswer", "*", "11246 'FfSsNnRrCc.': the calculator hot-key letters", YES, "PORTED", "calculator.gd:key_for_event")
R("X", "NUMBERS.C", "NumberToString", "*", "11246 (same key letters, used as a separator test)", YES, "N/A", "number_value.gd")
R("X", "CDGLUE.C", "write_users_dat", "*", "'Writing to the disk has failed. Your game cannot be saved.' / 'Write Error'", "error path", "N/A", "SaveStore returns an Error code (save_store.gd); no dialog")
R("X", "CUSTOM.C", "DrawCustomizationDialog", "*", "Set Customization Options dialog: 'Educational Level', Level 1-4 captions, 'Calculator', On / Off", YES, "PORTED", "customization_dialog.gd:_ready")
R("X", "CUSTOM.C", "DrawDialogControls", "*", "'Done' / 'Cancel'", YES, "PORTED", "customization_dialog.gd")
R("X", "DATABANK.C", "DoDataBank", "LoadStringResource", "canister log screen: 'ENTRY', 'LOG ENTRY MENU', 'DONE' (the entry number text 1.01 ... is built from it)", YES, "PORTED", "log_screen.gd:STRING_ENTRY / STRING_MENU / STRING_DONE, _build_rows ('ENTRY 1.04' via CanisterLog.label)")
R("X", "GETNUM.C", "ShowCalcNoticeDialog", "*", "modal 'Fraction Mode' help (11043) or 'Calculator Error' (11042) dialog when a calculator / answer-box key is not allowed", YES, "PORTED",
  "calc_notice_dialog.gd:TITLE_ERROR / TEXT_FRACTION_HELP / TITLE_FRACTION_HELP (11042-11044, 10174-10176), show_notice; wired in problem_screen.gd:_ready (answer_box.notice_requested); calculator_model.gd Notice enum")
R("X", "MATHPROB.C", "Prob10_Diagram", "*", "11251: unit letter 'C' (temperature) in the diagram", YES, "PORTED", "problem_type_10.tres")
R("X", "MATHPROB.C", "DoCombinationLock", "LoadStringResource", "lock label strings loaded at start: 11219-11226, 11228-11235, 11237-11244 into the wheel / solution label buffers (LockTenthLabelPtrs ...), 11227 '0.9' and 11245 '1.9'; the wheel and LockShowSolution show the loaded '0.5'", YES, "PORTED",
  "step_problems.py:lock_labels puts the loaded strings in the type's `operand_labels` / `answer_labels` (lock_diagram.gd:_add_labels, problem_texts.gd:lock_solution); form 11's answer slot 7 shows '0.90' instead of '1.9' (Deliberate deviation)")
R("X", "LOCK.C", "LockRunStage", "*", "11045 'OUT OF TIME', 11046 'ERROR', 11003 'Click to go on.'", YES, "PORTED", "lock_wheel.gd, combination_lock.gd:_miss, problem_screen.gd:_show_go_on")
R("X", "MATHPROB.C", "Prob09_PromptSubst", "*", "type 9 prompt substitutions: 'longitude' / 'latitude' / 'approximate'", YES, "PORTED", "problem_texts.gd:_type_09")
R("X", "MATHPROB.C", "Prob09_SolutionSubst", "*", "type 9 solution substitutions", YES, "PORTED", "problem_texts.gd:_type_09")
R("X", "WORLD.C", "LoadMenuStringsPlaying", "*", "in-game menu bar: &Help, &File, &Options and their items", YES, "PORTED", "game_menu_bar.gd:_ready (11052-11057)")
R("X", "WORLD.C", "LoadMenuStringsPractice", "*", "practice-mode menu bar", YES, "PORTED", "game_menu_bar.gd:_build_practice_menus (11058-11063)")
R("X", "MATHPROB.C", "NOFUNC", "*", "dead function at 0x4232a0 (never called)", "dead", "N/A", "-", sites=["004232c8"])
R("X", "MATHPROB.C", "ShowCorrectPhrase", "*", "practice mode right answer: 'Correct.' / 'That's right.' / 'Good answer.' / 'Very good.' (11110 + rand() % 4)", YES, "PORTED", "correct_phrase.gd:COUNT, pick (11110 + rand % 4); problem_flow.gd:_on_right")
R("X", "MATHPROB.C", "DisplayMathTitle", "*", "problem title (string 10xxx by type)", YES, "PORTED", "problem_instance.gd title")
R("X", "MATHPROB.C", "ShowProblemPrompt", "*", "problem prompt text (ProblemTextBundle item by type / level)", YES, "PORTED", "problem_texts.gd")
R("X", "MATHPROB.C", "ShowWrongAnswerNotice", "*", "wrong answer: 11000 'Error!' ; second wrong: 11114 'Problem has been directed to ship to avoid further loss of oxygen.' (types outside the 10-type table at 0x442984)", YES, "PORTED",
  "problem_flow.gd:STRING_ERROR / STRING_DIRECTED_TO_SHIP / NO_SHIP_NOTICE_TYPES, _on_wrong / _after_error; the lock has its own copy, combination_lock.gd:Phase.MISS_HINT")
R("X", "MATHPROB.C", "ShowProblemSolution", "*", "'Click to go on.' under the worked solution", YES, "PORTED", "problem_screen.gd:_show_go_on / problem_flow.gd:_show_solution")
R("X", "NEPTUNE.C", "Main", "*", "11249 'FALSE': the INI default string", "boot", "N/A", "-")
R("X", "NEPTUNE.C", "ShowFirstTimeHint", "*", "11115 'New Player Hint' dialog title; the hint text is bundle 0xf2 item n", YES, "PORTED", "game_flow.gd:show_hint (HintSystem ids 0-6, text 10167 + n)")
R("X", "ONHELP.C", "RunHelpTopic", "*", "Help menu topic titles (string param_2: 11xxx) and pages (bundle 0xf0)", YES, "PORTED", "help_topics.gd:TOPICS (pages), help_viewer.gd")
R("X", "OPENING.C", "TitleScreenPromptLoop", "*", "11001 'Copyright 1991,1994-97 TLC Properties Inc.' on the title screen", YES, "PORTED", "help_topics.gd (about); title_scene.gd shows the copyright picture")
R("X", "OPENING.C", "OpeningStoryPages", "*", "11003 'Click to go on.' on the story pages", YES, "PORTED", "story_pages.gd:_show_page (click_label on the last page)")
R("X", "OPTIONS.C", "MenuAboutBox", "*", "About Operation Neptune text (11144-11150) + copyright 11001 + version 11002", YES, "PORTED", "help_topics.gd:ABOUT_TEXTS (11001, 11002, 11144-11146; 11147-11149 are blank lines, 11150 is the menu item), about_text, cleaned by clean")
R("X", "OPTIONS.C", "MenuReturnToSignInSave", "*", "the IN-GAME menu's File > Return to Sign In (command table at file offset 0x2ddd0): 11126 'Only those sectors you have completed will be saved' / 11127 title, then SaveRosterData", YES, "PORTED",
  "game_flow.gd:ask_to_return_to_sign_in (11126 / 11127, Yes / No, default No); test_flow_fidelity_legacy.gd test_the_return_to_sign_in_question_has_the_originals_words, test_flow_fidelity.gd test_yes_saves_and_goes_back_to_sign_in")
R("X", "OPTIONS.C", "MenuReturnToSignIn", "*", "the PRACTICE menu's File > Return to Sign In (command table at file offset 0x2de54): 'Are you sure you want to return to the Sign In?' (11128 / 11129)", YES, "PORTED", "practice_mode.gd:ask_to_return")
R("X", "OPTIONS.C", "SaveAndExit", "*", "Esc: 'Do you want to exit the program?' (11130 / 11132)", YES, "PORTED", "game_flow.gd:ask_to_exit")
R("X", "OPTIONS.C", "JustExit", "*", "quit without saving (11134 / 11132) used by the problem screens", YES, "PORTED", "practice_mode.gd:ask_to_exit_from_problem")
R("X", "OPTIONS.C", "show_hall_of_fame", "*", "11124 column heading line, 11125 'Hall of Fame'", YES, "PORTED", "hall_of_fame_view.gd:_ready (11125, Done 11013); the Name / Level / Tries headings (_fill) come from the first line of string 11124 (_headings); test_hall_of_fame.gd")
R("X", "OPTIONS.C", "MenuNewPlayerHints", "*", "Options > New Player Hints dialog (11142 / 11143)", YES, "PORTED", "game_flow.gd:OPTION_QUESTIONS (&\"hints\": 11143 / 11142), ask_option")
R("X", "OPTIONS.C", "MenuSoundEffects", "*", "Options > Sound Effects: 'Do you want the Sound Effects on?' (11138 / 11139)", YES, "PORTED", "game_flow.gd:OPTION_QUESTIONS (&\"sound\": 11138 / 11139), ask_option (Yes / No; default = the button that changes the setting; Escape leaves it); audio_settings_dialog.gd is an extra (volumes)")
R("X", "OPTIONS.C", "MenuMusic", "*", "Options > Music dialog (11140 / 11141)", YES, "PORTED", "game_flow.gd:OPTION_QUESTIONS (&\"music\": 11140 / 11141), ask_option")
R("X", "OPTIONS.C", "MenuVoice", "*", "Options > Voice dialog (11136 / 11137)", YES, "PORTED", "game_flow.gd:OPTION_QUESTIONS (&\"voice\": 11136 / 11137), ask_option")
R("X", "PRACTICE.C", "DrawPracticeSetupDialog", "*", "Math Practice Customized Settings dialog (11155-11167)", YES, "PORTED", "practice_setup_dialog.gd")
R("X", "PRACTICE.C", "PracticeSetupDialog", "*", "11166 / 11167 On / Off captions", YES, "PORTED", "practice_setup_dialog.gd")
R("X", "PRACTICE.C", "PracticeShowScore", "*", "score dialog: Number of problems / Problems correct / Correct on 1st try / 2nd try (11168-11171)", YES, "PORTED", "practice_mode.gd:_update_score")
R("X", "PRACTICE.C", "do_math_practice", "*", "'You have completed this set ... Continue Math Practice' (11151 / 11152) and Done / Cancel (11153 / 11154)", YES, "PORTED", "practice_mode.gd:_ask_another")
R("X", "PROBE.C", "Prob11_PromptSubst", "*", "type 11 substitution: 'hours' / 'minutes' (11210 / 11211)", YES, "PORTED", "problem_texts.gd:_type_11")
R("X", "PROBE.C", "Prob11_HintSubst", "*", "type 11 hint substitution (hours / minutes)", YES, "PORTED", "problem_texts.gd:_type_11")
R("X", "ROSTER.C", "Prob23_SolutionSubst", "*", "type 23: 'port' / 'starboard' (11181 / 11182)", YES, "PORTED", "problem_type_23.tres, problem_texts.gd:_type_23")
R("X", "ROSTER.C", "CustomizedGameNotice", "*", "'This <game> game has been customized. EDUCATIONAL LEVEL ... CALCULATOR ...' (11195-11206)", YES, "PORTED", "sign_in.gd:_enter_game (after the 36-tick pressed look, before the scan) -> game_flow.gd:customized_notice_text")
R("X", "SIGNIN.C", "ChooseGameLevelDialog", "*", "'Choose a Game Level', note 11257, Voyager / Expert captions", YES, "PORTED", "new_player_dialog.gd")
R("X", "SIGNIN.C", "EnterNewPlayerNameDialog", "*", "'Enter New Player Name' / 'Type your name in the box below. Then press Enter'", YES, "PORTED", "new_player_dialog.gd")
R("X", "SIGNIN.C", "DrawSignInRow", "*", "(c) mark and level text of a roster row", YES, "PORTED", "sign_in.gd, hall_entry.gd:from_profile")
R("X", "SIGNIN.C", "SignInScreenLoop", "*", "list-full / remove-player dialogs (11185-11188), exit confirmation (11191 / 11192), 11208 'Ee' key letters", YES, "PORTED", "sign_in.gd (11185-11192)")
R("X", "SIGNIN.C", "SignInRun", "*", "re-prompt strings 11191 / 11192 when no player is selected", YES, "PORTED", "sign_in.gd")
R("X", "SIGNIN.C", "display_hof_player", "*", "hall of fame row text ((c) mark etc.)", YES, "PORTED", "hall_entry.gd:from_profile")
R("X", "SIGNIN.C", "Prob03_PromptSubst", "*", "type 3: 'hours' / 'minutes' substitution (11210 / 11211)", YES, "PORTED", "problem_texts.gd:_type_03")
R("X", "SIGNIN.C", "Prob06_Diagram", "*", "11250 '5000': radar scale number", YES, "PORTED", "problem_type_06.tres")
R("X", "SUPPLY.C", "PiecesNotCollectedMessage", "*", "'Surface Ship Message: Ship's magnetometer indicates the presence of N object(s) in this sector ...' (11212)", YES, "PORTED", "game_flow.gd:on_dock_reached (the ship light is set there; the text is the surface ship screen's)")
R("X", "SUPPLY.C", "Prob21_Diagram", "*", "' liters' / ' gallons' unit words (11213 / 11214)", YES, "PORTED", "tank_diagram.gd, problem_type_21.tres")

# ---- wrapper callers (transitive closure) ----
R("M", "WWAVE.C", "RunModalDialog", "PauseSoundForDialog,ResumeSoundAfterDialog", "every modal OK / Yes-No dialog pauses the song (and kills speech) on entry and resumes it on exit", YES, "PORTED", "game.gd:_on_message_shown (messages), _show_modal: Audio.pause_sound / resume_sound")
R("M", "WWAVE.C", "RunPagedDialog", "PauseSoundForDialog,ResumeSoundAfterDialog", "paged help dialog pauses / resumes the song", YES, "PORTED", "game.gd:_show_modal (help viewer is a modal)")
R("M", "OPTIONS.C", "MenuMusic", "SetMusicOn", "Options > Music answered Yes: the song restarts at once (PlayBackgroundMusic(current id))", YES, "PORTED", "game_flow.gd:ask_option (Yes -> set_option -> option_changed -> game.gd:_on_option_changed -> Audio.set_music_on, audio.gd:set_music_on restarts the song from the beginning); test_flow_fidelity.gd test_yes_on_music_restarts_the_song_from_the_beginning")
R("M", "OPTIONS.C", "MenuSoundEffects", "SetSoundOn", "Options > Sound Effects answered No: all 0x34 effects are stopped", YES, "PORTED", "audio.gd:set_bus_enabled (stop_sfx)")
R("M", "SOUNDHI.C", "ToggleAllSound", "SetMusicOn,SetSoundOn", "all-sound toggle: no caller and no pointer to it anywhere in the EXE", "dead", "N/A", "audio.gd:set_bus_enabled per-bus switches")
R("M", "WORLD.C", "FreeSectorResources", "FreeSectorStopMusic", "leaving a sector (death, new sector, quit to sign-in) stops the song", YES, "PORTED", "game.gd:_leave / game_flow.gd:begin_sector replaces the song")
R("M", "CLOSING.C", "FreeClosingResources", "FreeClosingStopMusic", "leaving the closing sequence stops the song", YES, "PORTED", "expert_closing.gd:finish and voyager_closing.gd:show_pages (stop_music)")
R("T", "SUPPLY.C", "DisplaySupplyStationMessage", "WaitEnterOrTicks", "supply message after a sector: up to 1460 ticks (20 s) for Enter", YES, "PORTED", "surface_ship_screen.gd:wait_ticks (Enter only; the timer starts after the speech)")
R("T", "OPENING.C", "TitleRevealText", "WaitEnterSpaceEscOrTicks", "title scene: 292 ticks hold after the 'Presents' strip", YES, "PORTED", "data/story/title_reveal.tres (marks, 292 ticks)")
R("X", "LOCK.C", "DoCombinationLock", "WriteMessageText", "lock intro / outcome texts written in the monitor (ids from the lock bundle)", YES, "PORTED", "combination_lock.gd (lock texts from data/problems/problem_type_00.tres)")
R("X", "LOCK.C", "LockShowSolution", "*", "worked solution text of the lock (strings 10181-10192)", YES, "PORTED", "combination_lock.gd Phase.MISS_SOLUTION")
R("X", "MATHPROB.C", "ShowProblemHint", "*", "the hint after a first wrong answer: ProblemTextBundle item by type / level / values (about 40 cases)", YES, "PORTED", "problem_texts.gd / problem_instance.hint")
R("X", "MATHPROB.C", "ShowSuccessMessage", "*", "right-answer text by type (item 3, 5, 6, 9 ... of ProblemTextBundle); types 6, 11, 12, 16, 22, 23, 26, 27 first replay a diagram animation", YES, "PORTED", "problem_flow.gd:_show_success: first the diagram's success replay (problem_screen.gd:_play_replay) for types 6, 11, 12, 16, 22, 23, 26, 27 (SUCCESS_REPLAY_TYPES), then problem.success; test_problem_flow.gd test_success_replay_lasts_as_many_ticks_as_the_diagram_says_before_the_success_text")
R("X", "CDGLUE.C", "write_hof_dat", "*", "second disk / save error dialog; title and text prepared by the caller", "error path", "N/A", "-")

R("X", "ACTION.C", "DoAction", "ShowFirstTimeHint", "new-player hints: 2 on the first piece (data canister), 5 when a math trigger starts blinking, 0 (controls) at the first frame", YES, "PORTED", "game_flow.gd:begin_mission (0), _on_piece_collected (2), _on_problem_pending (5)")
R("X", "BEZEL.C", "DisplayOxygen", "ShowFirstTimeHint", "new-player hint 1 (low oxygen)", YES, "PORTED", "game_flow.gd:_on_oxygen_changed")
R("X", "MATHPROB.C", "DoMathProblem", "ShowFirstTimeHint", "hints after the prompt: 3 (type your answer, calculator off) or 4 (calculator on), skipped for the ballast types 28 / 29 and the lock and in practice; hint 6 (fractions) when EduLevel is 1 OR 3", YES, "PORTED",
  "game_flow.gd:run_problem / show_problem_hints (after the diagram build-up: game.gd:show_problem calls after_prompt when intro_finished; none for types 0 / 28 / 29; 4 when profile.calculator_on else 3; 6 at edu_level 1 or 3); test_problem_hint_conditions.gd")
R("X", "TEXTHI.C", "NOFUNC", "RunPagedDialog", "dead function at 0x415b7c (not recognised by Ghidra, no caller, no pointer to it): builds a paged dialog from a picture bundle and runs RunPagedDialog", "dead", "N/A", "-", sites=["00415c83"])
