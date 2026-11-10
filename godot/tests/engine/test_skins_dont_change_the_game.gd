class_name TestSkinsDontChangeTheGame
extends GdUnitTestSuite
## Teaches: "skins never change rules or timing" as a test: the same sector and the same hands give the same
## event trace with every skin, and two skins can be switched at run time with no line of the trace changing. Phase E is done when this passes.
##
## The skins are not named here: `SkinRoster.all()` asks `SkinChoice.available()` (whatever is in `res://skins/`), adds the tiny test skin and a
## hostile one, so a skin that is added later is covered the moment its folder exists. Where each part lives:
##   * `test_plays_identically.gd`: every skin through the scripted visits of several sectors, the lengths of the steps that hold up play, and
##     a whole mission through the real `Game` scene (the HUD included), each against plain objects with no presenter at all;
##   * here: switching skins in the middle of a visit (every pair, and all of them in turn), a skin that tries to change the rules' DATA
##     (`SkinRoster.hostile`), the guard on what `Catalog` lets a skin touch, and a check that the comparison itself can fail.
##
## How to add your skin to these tests: put it in `res://skins/<id>/skin.tres` (a `GameSkin`). That is all. Its presenter scene, its pictures, its
## render settings and its HUD are used by those tests as the game uses them. Run `tools/run_tests.sh tests/engine/test_plays_identically.gd
## tests/engine/test_skins_dont_change_the_game.gd`.

const WORLD_SCENE := "res://src/gameplay/sector_world.tscn"
const GAME_STATE_SCRIPT := "res://src/autoload/game_state.gd"
## The data a skin may not replace, as `Catalog` files (the keys of `GameSkin.resources` are these without the folder and `.tres`).
const CATALOG_SOURCE := "res://src/core/catalog.gd"


func before_test() -> void:
	GameClock.paused = true
	SectorWorld.skip_animations = false
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


# --- switching at run time ------------------------------------------------------------------------------------

## The trace of a scripted visit to `sector` with plain objects: no presenter, no skin.
func _plain(sector: int) -> Array[String]:
	GameState.reset()
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.reset()
	var scenario := SectorScenario.new(HeadlessStage.new(run), run)
	scenario.play(sector)
	return scenario.trace.lines


## The trace of the visit in a `SectorWorld` that starts in `skins[0]` and wears the next one of `skins` every `every` ticks of the flight
## (the last one stays). The world's presenter is checked after each switch: it is the new skin's.
func _switching(sector: int, skins: Array[GameSkin], every: int) -> Array[String]:
	GameState.reset()
	SkinChoice.select(skins[0])
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	var count := [0]
	var scenario := SectorScenario.new(world, GameState)
	scenario.after_tick = func() -> void:
		count[0] += 1
		if count[0] % every == 0 and count[0] / every < skins.size():
			var next := skins[count[0] / every]
			SkinChoice.select(next)
			# (the presenter of the new skin's kind is there, built from the rules' state: a skin's own scene, or the original's)
			var asked := next.presenter_scene_or_null()
			if asked != null:
				assert_str(world.presenter.scene_file_path).is_equal(asked.resource_path)
			else:
				assert_object(world.presenter).is_instanceof(OriginalPresenter)
			world.presenter.show_between_ticks(0.5)
	scenario.play(sector)
	assert_int(count[0]).is_equal(SectorScenario.FLY_TICKS)
	return scenario.trace.lines


func _assert_same(plain: Array[String], other: Array[String], what: String) -> void:
	assert_int(other.size()).override_failure_message("%s: another number of lines" % what).is_equal(plain.size())
	for i in mini(plain.size(), other.size()):
		if other[i] != plain[i]:
			fail("%s: the rules differ at line %d\n  plain: %s\n  other: %s" % [what, i, plain[i], other[i]])
			return


func test_switching_from_any_skin_to_any_other_in_the_middle_of_a_visit_changes_nothing() -> void:
	var skins := SkinRoster.all()
	var plain := _plain(DevCreatures.ARENA)
	for a in skins.size():
		for b in skins.size():
			if a == b:
				continue
			# a, then b at tick 40, then a again at tick 80: every ordered pair is a switch both ways
			var lines := _switching(DevCreatures.ARENA, [skins[a], skins[b], skins[a]], 40)
			_assert_same(plain, lines, "sector %d, %s then %s" % [DevCreatures.ARENA, skins[a].id, skins[b].id])


func test_going_through_every_skin_in_turn_changes_nothing() -> void:
	var skins := SkinRoster.all()
	skins.append(SkinChoice.original())
	var plain := _plain(DevCreatures.FISH)
	_assert_same(plain, _switching(DevCreatures.FISH, skins, 15), "sector %d, every skin in turn" % DevCreatures.FISH)


# --- what a skin cannot reach -----------------------------------------------------------------------------------

func test_the_hostile_skin_asks_for_a_lot_and_gets_none_of_it() -> void:
	var hostile := SkinRoster.hostile()
	var refused := hostile.refused_resources()
	assert_array(refused).contains(["zones", "trigger_table", "problems/problem_type_00", "problems/ui_strings", "bubble_rules"])
	assert_array(refused).contains(["sprite_meta/sprite_meta_zone2", SkinRoster.data_key(Catalog.sector_path(0))])
	assert_int(refused.size()).is_equal(hostile.resources.size())          # (every one of the doctored resources is refused: none is presentation)
	for key in hostile.resources:
		assert_bool(hostile.resource_for(key) == null).override_failure_message("the skin got '%s' through" % key).is_true()


func test_no_skin_in_the_roster_asks_for_data_it_may_not_have() -> void:
	for skin in SkinRoster.shipped():
		assert_array(skin.refused_resources()).override_failure_message("skin %s maps resources that are rules or content" % skin.id).is_empty()
	assert_array(load(SkinRoster.TINY).refused_resources()).is_empty()


## The rules' data, as `Catalog` hands it out, with the skin `skin` in use.
func _rules_data(skin: GameSkin) -> Dictionary:
	SkinChoice.select(skin)
	var data := {"zones": Catalog.zones(), "triggers": Catalog.trigger_table(), "tuning": LayeredJson.read_all(Tuning.files(), "test"), "bubbles": Catalog.bubble_rules()}
	for index in Catalog.sector_ids():
		data["sector %d" % index] = Catalog.sector(index)
	for table in Catalog.TEXT_TABLES:
		data["texts %s" % table] = Catalog.texts(table)
	for zone in Catalog.ZONE_COUNT:
		data["sprite_meta %d" % zone] = SpriteMeta.for_zone(zone)
	for index in Catalog.PROBLEM_TYPE_COUNT:                                  # (a problem type holds the records, the answers and the texts)
		var type := Catalog.problem_type(index)
		data["problem %d records" % index] = type.records
		data["problem %d answers" % index] = [type.answer_fields, type.compare_mode, type.tolerances, type.texts, type.record_levels]
	return data


func test_choosing_a_skin_never_changes_the_rules_data() -> void:
	var original := _rules_data(SkinChoice.original())
	assert_int(original.size()).is_greater(50)
	for skin in SkinRoster.all():
		var wearing := _rules_data(skin)
		for key: String in original:
			var same: bool
			if original[key] is Resource:
				same = is_same(original[key], wearing[key])               # (loaded from its file, never copied, so the very same object)
			else:
				same = original[key] == wearing[key]
			assert_bool(same).override_failure_message("skin %s changed %s" % [skin.id, key]).is_true()
	# and what the rules build from it: the sub's wall box is the file's, whatever a skin offered
	SkinChoice.select(SkinChoice.original())
	var wall_box := Tuning.resolve().sub.wall_box
	SkinChoice.select(SkinRoster.hostile())
	var run := auto_free(load(GAME_STATE_SCRIPT).new()) as Node
	run.begin_run()                                                   # (a run takes the rule values of the chain)
	var sim := SimWorld.new(run)
	assert_that(sim.sub.tuning.wall_box).is_equal(wall_box)
	sim.load_sector(DevCreatures.ARENA, 0)
	assert_int(sim.triggers.size()).is_greater(0)
	assert_bool(sim.sector.pieces.size() > 0).is_true()


func test_the_loaders_that_ask_the_skin_are_presentation_only() -> void:
	# `Catalog` asks the skin (`_skinned`) only for these files: the pictures, layouts, picture bundles and the tile set. A new rules file that
	# went through `_skinned` would let a skin replace it, so it fails here until somebody decides it should not.
	var source := FileAccess.get_file_as_string(CATALOG_SOURCE)
	var asked := RegEx.create_from_string("_skinned(?:_project)?\\(\"(?:data/)?([^\"]+)\"").search_all(source)
	assert_int(asked.size()).is_greater(8)
	for found in asked:
		var path := found.get_string(1)
		var data_key := path.get_basename().replace("%02d", "00").replace("%d", "0")
		var presentation := GameSkin.is_replaceable(data_key) or data_key.begins_with("problems/problem_type_")     # (a problem type is copied with the skin's pictures only)
		assert_bool(presentation).override_failure_message("Catalog asks the skin for '%s', which is rules or content" % path).is_true()
	# the rules' own files are loaded without it
	for file in ["sectors", "zones.tres", "trigger_table.tres", "bubble_rules.tres"]:
		assert_bool(source.contains("_skinned(\"data/%s" % file)).override_failure_message("%s goes through the skin" % file).is_false()


# --- the comparison can fail ------------------------------------------------------------------------------------

## A presenter that cheats: it reaches round the skin API to the rules (`sim`) and pushes the sub. (The point of the API is that nothing
## it hands out can do this; the point of this class is to show that the comparisons above would notice if something did.)
class Meddler:
	extends SectorPresenter

	func bind(sim_world: SimWorld) -> void:
		super.bind(sim_world)
		_listen(sim.ticked, func() -> void: sim.sub.position.x += 1.0 if sim.tick_number % 9 == 0 else 0.0)


func test_a_presenter_that_changed_a_rule_would_be_caught() -> void:
	GameState.reset()
	var world := scene_runner(WORLD_SCENE).scene() as SectorWorld
	world.replace_presenter(Meddler.new())
	var scenario := SectorScenario.new(world, GameState)
	scenario.play(DevCreatures.ARENA)
	var plain := _plain(DevCreatures.ARENA)
	var differs := plain.size() != scenario.trace.lines.size()
	for i in mini(plain.size(), scenario.trace.lines.size()):
		differs = differs or plain[i] != scenario.trace.lines[i]
	assert_bool(differs).override_failure_message("a presenter that moves the sub changed no line of the trace").is_true()
