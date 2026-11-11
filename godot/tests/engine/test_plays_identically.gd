class_name TestPlaysIdentically
extends GdUnitTestSuite
## Teaches: the proof of the split between the rules and the picture: the game plays the SAME with every
## presenter and with every skin. A scripted visit to a sector (`SectorScenario`: the launch, a flight with the creatures awake, a problem, a lost tank and
## its dissolve, the dock, the balloon; or the finale) is played
##   * with no presenter at all (`HeadlessStage`, plain objects),
##   * in a `SectorWorld` with the original presenter (all its nodes),
##   * in a `SectorWorld` with the debug rectangles (`DebugRectPresenter`: nothing but `_draw()`),
##   * in a `SectorWorld` with a blank presenter (`SectorPresenter`: it shows nothing),
##   * in a `SectorWorld` with a vandal (`SkinVandal`: a skin that scribbles over every copy the skin API gives it),
## and the traces are compared line by line: every event with the tick it happened in, the whole state of the rules after every tick,
## and how many ticks each step took (the launch, the dock and the balloon as the pack's rules give them, the dissolve 21). Any difference means a presenter
## changed a rule or a duration - which a presenter must never do. A whole mission through the real `Game` scene is the last test.
##
## (The whole mission through the real `Game` scene, on the original's two games, is in `legacy/test_plays_identically_legacy.gd`.)
##
## The same, with every SKIN (`SkinRoster.all()`: whatever is in `res://skins/`, the tiny test skin, a hostile one, a data skin with no script, a skin mod that draws and one that faults on every frame), the visits and the
## whole mission, with the debug rectangles laid over the picture too. Switching skins in the middle of a visit and what a skin cannot
## reach (the rules' data) are in `test_skins_dont_change_the_game.gd`.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const HUD_SCENE := "res://src/ui/hud.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
## Sectors of the scripted visit: the arena, the fish, a sector of the tour and the closing (a finale screen). Between them they have launch, balloon, dock,
## a problem, a lost tank, screen changes and the closing.
const SECTORS := [DevCreatures.ARENA, DevCreatures.FISH, 3, DevCreatures.CLOSING]


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false              # (the trips and the dissolve are the point)
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	GameState.reset()
	SkinRoster.mount_mod_skins()


func after_test() -> void:
	GameClock.paused = false
	SectorWorld.skip_animations = false
	PresenterChoice.forced = &""
	SkinChoice.select(SkinChoice.original())
	SkinRoster.release_mod_skins()
	GameState.reset()


# --- the shells --------------------------------------------------------------------------------------

## Plays `SectorScenario` on sector `sector` with the given shell and returns the scenario.
## `shell`: &"none" (plain objects), or the presenter of a `SectorWorld`: PresenterChoice.ORIGINAL, PresenterChoice.DEBUG_RECTS, &"blank",
## &"vandal" (`SkinVandal`: scribbles over every copy of the skin API), &"overlay" (the original presenter with the debug rectangles laid over it).
## With `skin`, the skin is in use before the world is made, so the world is built the way the game is with that skin, and the game's console (`Hud`) is beside the world, shown after every tick as the presenter is.
## With `player`, a player of a campaign (a campaign that declares a mod, `ModRuleShelf`), the run begins as the sign-in screen begins it, so its rule hooks are the run's, and the visit is that player's.
func _play(sector: int, shell: StringName, skin: GameSkin = null, player: PlayerProfile = null) -> SectorScenario:
	GameState.reset()
	if shell == &"none":
		var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
		if player != null:
			run.begin_run(player)
		else:
			run.reset()
		var scenario := SectorScenario.new(HeadlessStage.new(run), run)
		scenario.play(sector, player)
		return scenario
	if player != null:
		GameState.begin_run(player)
	if skin != null:
		SkinChoice.select(skin)
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	match shell:
		&"overlay":
			world.set_overlay(true)
		PresenterChoice.DEBUG_RECTS:
			world.replace_presenter(DebugRectPresenter.new())
		&"blank":
			world.replace_presenter(SectorPresenter.new())
		&"vandal":                              # a skin that overwrites everything the skin API gives it
			world.replace_presenter(SkinVandal.new())
	var console: Hud = null                      # (the console of a skin's visit: the game's own HUD, whose parts a skin mod's script may draw)
	if skin != null:
		console = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
		world.add_child(console)
	# the picture is asked to follow after every tick, as the frames of the game do
	var fraction := [0.0]
	world.sim.ticked.connect(func() -> void:
		fraction[0] = fmod(fraction[0] + 0.37, 1.0)
		world.presenter.show_between_ticks(fraction[0])
		if console != null:
			console.show_mod_layers(fraction[0])
		if world.presenter is DebugRectPresenter:
			(world.presenter as DebugRectPresenter).boxes()
		if world.overlay != null:
			world.overlay.show_between_ticks(fraction[0])
			world.overlay.boxes())
	var scenario := SectorScenario.new(world, GameState)
	scenario.play(sector, player)
	if skin != null:
		SkinChoice.select(SkinChoice.original())
	return scenario


func _text_of(scenario: SectorScenario) -> String:
	return "\n".join(scenario.trace.lines)


## The lines of the trace that tell how long each step that holds up play took: the trips as the pack's rules lay them out, the dissolve.
func _step_lines() -> Array[String]:
	return ["-- launch took %d ticks" % StationSequence.launch().ticks, "-- dock took %d ticks" % StationSequence.dock().ticks,
			"-- balloon took %d ticks" % StationSequence.balloon().ticks, "-- dissolve of %d ticks" % SimWorld.dissolve_length()]


# --- one sector, every presenter ----------------------------------------------------------------------

func test_a_scripted_visit_gives_the_same_trace_with_every_presenter() -> void:
	for sector in SECTORS:
		var plain := _play(sector, &"none")
		var plain_lines := plain.trace.lines
		assert_int(plain_lines.size()).override_failure_message("sector %d: nothing was recorded" % sector).is_greater(100)
		for shell: StringName in [PresenterChoice.ORIGINAL, PresenterChoice.DEBUG_RECTS, &"blank", &"vandal", &"overlay"]:
			_assert_same_trace(plain_lines, _play(sector, shell).trace.lines, "sector %d, %s" % [sector, shell])


## `lines` is the trace of the plain objects; `other` must be the same, line by line: every event with its tick, the rules' state after every
## tick, the length of every step that holds up play.
func _assert_same_trace(lines: Array[String], other: Array[String], what: String) -> void:
	assert_int(other.size()).override_failure_message("%s: another number of lines" % what).is_equal(lines.size())
	for i in mini(lines.size(), other.size()):
		if other[i] != lines[i]:
			fail("%s: the rules differ from the plain objects at line %d\n  plain: %s\n  other: %s" % [what, i, lines[i], other[i]])
			return


# --- every skin ----------------------------------------------------------------------------------------

func test_a_scripted_visit_gives_the_same_trace_with_every_skin() -> void:
	var skins := SkinRoster.all()
	assert_int(skins.size()).is_greater(2)                       # (the original, the tiny one, the hostile one, and whatever ships)
	for sector in SECTORS:
		var plain := _play(sector, &"none").trace.lines
		for skin in skins:
			_assert_same_trace(plain, _play(sector, PresenterChoice.ORIGINAL, skin).trace.lines, "sector %d, skin %s" % [sector, skin.id])
			# (and with the rectangles of the authoring tool laid over the skin's picture)
			_assert_same_trace(plain, _play(sector, &"overlay", skin).trace.lines, "sector %d, skin %s with the overlay" % [sector, skin.id])


func test_the_steps_that_hold_up_play_take_the_same_ticks_with_every_skin() -> void:
	for skin in SkinRoster.all():
		var trace := _play(DevCreatures.ARENA, PresenterChoice.ORIGINAL, skin).trace
		var timings := trace.lines.filter(func(line: String) -> bool: return line.contains(" took ") or line.begins_with("-- dissolve"))
		var expected := _step_lines()
		for line in expected:
			assert_bool(timings.has(line)).override_failure_message("skin %s: no '%s' in %s" % [skin.id, line, timings]).is_true()
		assert_bool(timings.all(func(line: String) -> bool: return expected.has(line))).override_failure_message("skin %s: %s" % [skin.id, timings]).is_true()


# --- a campaign that declares a mod ------------------------------------------------------------------------------

## A visit of a campaign that declares a rule-hook mod (`ModRuleShelf`: a good one, then one that faults in every hook) is the same play with every presenter and every skin, and the same play each time. A mod changes
## the rules for the campaign that declares it, and only for it; what shows the play never does.
func test_a_scripted_visit_with_a_mod_gives_the_same_trace_with_every_presenter_and_skin() -> void:
	if not ModLoader.sandbox_available():
		return
	for fixture in ["rules", "rules_chaos"]:
		var shelf := ModRuleShelf.mount(fixture, Packs.chosen().id)
		if fixture == "rules_chaos":
			ModHost.mod(String(ModRuleShelf.PACK)).call("set_mode", "raise")
		var sector := ModRuleShelf.SECTOR
		var plain := _play(sector, &"none", null, ModRuleShelf.player())
		assert_int(plain.trace.lines.size()).is_greater(100)
		assert_int(plain.run.hooks.calls).override_failure_message("%s: the mod was never asked" % fixture).is_greater(0)
		_assert_same_trace(plain.trace.lines, _play(sector, &"none", null, ModRuleShelf.player()).trace.lines, "%s, the same visit again" % fixture)
		for shell: StringName in [PresenterChoice.ORIGINAL, PresenterChoice.DEBUG_RECTS, &"blank", &"vandal", &"overlay"]:
			_assert_same_trace(plain.trace.lines, _play(sector, shell, null, ModRuleShelf.player()).trace.lines, "%s, %s" % [fixture, shell])
		for skin in SkinRoster.all():
			_assert_same_trace(plain.trace.lines, _play(sector, PresenterChoice.ORIGINAL, skin, ModRuleShelf.player()).trace.lines, "%s, skin %s" % [fixture, skin.id])
		Mods.loader().forgive(String(ModRuleShelf.PACK))
		ModRuleShelf.release(shelf)
		SkinRoster.release_mod_skins()
		SkinRoster.mount_mod_skins()


func test_the_skin_mods_of_the_roster_really_run_in_the_visit() -> void:
	for skin in SkinRoster.mod_skins():
		var mod := ModHost.mod(String(skin.id))
		if mod == null:                                          # (the data skin: no script to ask; it is worn with the original's presenter)
			assert_object(skin.presenter_scene_or_null()).is_null()
			assert_bool((skin as ModSkin).pictures.is_empty()).is_false()
			continue
		var faults := int(mod.get("monitor_exceptions"))
		var trace := _play(DevCreatures.ARENA, PresenterChoice.ORIGINAL, skin).trace
		assert_array(trace.lines).is_not_empty()
		if mod.has_method(&"heard_events"):
			assert_array(mod.call("heard_events")).override_failure_message("the skin %s was told nothing of the visit" % skin.id).contains(["ticked"])
			assert_int(int(mod.get("monitor_exceptions"))).override_failure_message("the skin %s faulted in the visit" % skin.id).is_equal(faults)
		else:
			assert_int(int(mod.get("monitor_exceptions"))).override_failure_message("the faulty skin %s was never asked" % skin.id).is_greater(faults)
		Mods.loader().resume(String(skin.id))


func test_the_steps_that_hold_up_play_take_the_rules_ticks_with_every_presenter() -> void:
	for shell: StringName in [&"none", PresenterChoice.ORIGINAL, PresenterChoice.DEBUG_RECTS, &"blank", &"vandal"]:
		var trace := _play(DevCreatures.ARENA, shell).trace
		var steps := trace.lines.filter(func(line: String) -> bool: return line.begins_with("-- "))
		var timings := steps.filter(func(line: String) -> bool: return line.contains(" took ") or line.begins_with("-- dissolve"))
		for expected in _step_lines():
			assert_bool(timings.has(expected)).override_failure_message("presenter %s: no '%s' in %s" % [shell, expected, timings]).is_true()
		assert_bool(timings.all(func(line: String) -> bool: return _step_lines().has(line))).is_true()


func test_the_visit_has_what_it_claims_to_have() -> void:
	var trace := _play(DevCreatures.ARENA, &"none").trace
	assert_array(trace.events_like("screen ")).override_failure_message("no screen change").is_not_empty()        # the flight crossed a screen edge
	assert_array(trace.events_like("pellet_fired")).is_not_empty()
	assert_array(trace.events_like("requested")).is_not_empty()
	assert_array(trace.events_like("dock")).has_size(1)
	# the launch, and the launch of every respawn before the midpoint (`GameFlow.respawn` begins the sector again on the station)
	assert_int(trace.events_like("trip_started 0 ticks=%d" % StationSequence.launch().ticks).size()).is_equal(trace.events_like("trip_started 0").size())
	assert_int(trace.events_like("trip_started 0").size()).is_greater(1)
	assert_array(trace.events_like("pieces_reset")).has_size(1)              # the canister's problem cost the tank
	assert_array(trace.events_like("trip_started 1 ticks=%d" % StationSequence.dock().ticks)).has_size(1)
	assert_array(trace.events_like("trip_started 2 ticks=%d" % StationSequence.balloon().ticks)).has_size(1)
	assert_array(trace.events_like("dissolve_started %d" % SimWorld.dissolve_length())).is_not_empty()


func test_the_visit_to_a_finale_sector_ends_with_the_closing() -> void:
	var trace := _play(DevCreatures.CLOSING, &"none").trace
	assert_array(trace.events_like("finale")).has_size(1)
	assert_array(trace.events_like("dock")).is_empty()                  # (the finale sector is not left by the dock)


func test_choosing_the_presenter_before_the_world_exists_changes_nothing_either() -> void:
	# the way the game is started with the debug rectangles (`-- --presenter=debug_rects`): the world swaps in its own presenter
	var plain := _play(3, &"none")
	PresenterChoice.forced = PresenterChoice.DEBUG_RECTS
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	assert_object(world.presenter).is_instanceof(DebugRectPresenter)
	assert_object(world.original).is_null()
	GameState.reset()
	var scenario := SectorScenario.new(world, GameState)
	scenario.play(3)
	assert_array(scenario.trace.lines).is_equal(plain.trace.lines)


func test_swapping_the_presenter_in_the_middle_of_a_visit_changes_nothing() -> void:
	# the F3 key R: the rules go on, whichever presenter is looking
	var plain := _play(DevCreatures.FISH, &"none")
	GameState.reset()
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var swaps := [0]
	var scenario := SectorScenario.new(world, GameState)
	scenario.after_tick = func() -> void:
		swaps[0] += 1
		if swaps[0] % 40 == 0:
			world.toggle_presenter()
	scenario.play(DevCreatures.FISH)
	assert_int(swaps[0]).is_equal(SectorScenario.FLY_TICKS)
	assert_object(world.presenter).is_instanceof(DebugRectPresenter)       # (three swaps: original, debug, original, debug)
	assert_array(scenario.trace.lines).is_equal(plain.trace.lines)


# --- a whole mission through the real game -----------------------------------------------------------


