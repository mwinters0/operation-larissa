class_name TestPictureScale
extends GdUnitTestSuite
## Teaches: the scale a run draws its pictures at as a DERIVED fact, tested by its effect. A pack of `picture_scale` 4 is used when the packs of that scale together hold a row for every picture the chain needs (`PackNeeds`), and then the run draws every picture at
## 1/4 of its file (`ScaledTexture`); otherwise the run draws at scale 1 and the shortfall is told once per run (`TroubleLog`). The packs of another scale give no picture, an alias of a 4x pack never lands on a 1x row, and every change of the chain decides again.
## `PicturesShelf.mount_hires` is a 4x pack that covers; the other scratch packs here cover nothing, or part. A covering pack holds a row for every key of the dev pack's table (`PackShelf.dev_picture_keys`), never what the engine says the chain needs: the fixture is not made by the function it is used to test.

var _shelf: PicturesShelf
var _extra: Array[PackShelf] = []


func before_test() -> void:
	GameState.reset()                                                               # (a run begins: the session's log is a new one)
	_shelf = PicturesShelf.new()


func after_test() -> void:
	for shelf in _extra:
		shelf.remove()
	_extra.clear()
	_shelf.remove()
	GameState.reset()


func _told_about(text: String) -> Array[String]:
	var found: Array[String] = []
	for line in TroubleLog.session.told:
		if line.contains(text):
			found.append(line)
	return found


## The colour of the file a picture is drawn from (a `ScaledTexture` is asked for its file).
func _color_of(texture: Texture2D) -> Color:
	return PicturesShelf.color_of((texture as ScaledTexture).source if texture is ScaledTexture else texture)


## A scratch pack of picture scale `scale` laid over `base` that holds a row for each of `keys` (16 x 16 files of `color`, so 4 x 4 at scale 4) and then the rows of `others` (key -> a file name or `{"alias": key}`).
func _pack_of(base: StringName, scale: int, keys: Array[String], color: Color, others := {}) -> PackShelf:
	var shelf := PackShelf.new(&"", base)
	_extra.append(shelf)
	shelf.add_scaled_rows(scale, keys, color)
	for key: String in others:
		shelf.add_row(key, others[key])
	return shelf


# --- the manifest ----------------------------------------------------------------------------------------------------------

func test_a_manifest_says_its_picture_scale_as_a_whole_number_from_1_to_the_most() -> void:
	var shelf := PackShelf.new()
	_extra.append(shelf)
	assert_int(Pack.open(shelf.root).picture_scale).is_equal(1)
	assert_bool(Pack.open(shelf.root).manifest().has("picture_scale")).is_false()
	shelf.set_picture_scale(4)
	var pack := Pack.open(shelf.root)
	assert_array(pack.errors).is_empty()
	assert_int(pack.picture_scale).is_equal(4)
	assert_int(pack.manifest()["picture_scale"]).is_equal(4)
	for bad: Variant in [0, -1, Pack.MAX_PICTURE_SCALE + 1, 2.5, "4", true, null]:
		var manifest: Dictionary = shelf.pack_json("pack.json")
		manifest["picture_scale"] = bad
		shelf.write_json("pack.json", manifest)
		assert_array(Pack.open(shelf.root).errors).override_failure_message("picture_scale %s" % [bad]).contains(["\"picture_scale\" must be a whole number from 1 to %d" % Pack.MAX_PICTURE_SCALE])


func test_a_chain_of_packs_of_scale_1_is_decided_without_reading_what_it_needs() -> void:
	var decision := PictureScale.decide(Packs.chain(), [])
	assert_int(decision.scale).is_equal(1)
	assert_array(decision.shortfalls).is_empty()
	assert_int(Packs.picture_decision().scale).is_equal(1)
	assert_array(Packs.picture_decision().packs).is_equal(Packs.chain())


# --- a covering pack is chosen ------------------------------------------------------------------------------------------------

func test_a_pack_of_scale_4_that_covers_the_chains_pictures_is_the_run_s_scale_and_draws_at_a_quarter_of_its_file() -> void:
	_shelf.mount_hires()
	assert_int(Packs.picture_decision().scale).is_equal(4)
	assert_array(Packs.picture_decision().packs.map(func(each: Pack) -> StringName: return each.id)).is_equal([_shelf.hires.id])
	var drawn := Pictures.resolve("frame/sub_00")
	assert_object(drawn).is_instanceof(ScaledTexture)
	assert_vector(drawn.get_size()).is_equal(Vector2(4, 4))
	assert_vector((drawn as ScaledTexture).source.get_size()).is_equal(Vector2(16, 16))
	assert_object(Pictures.resolve("frame/sub_00")).is_same(drawn)                          # (one row, one object)
	var sky := Pictures.resolve("ui_picture/title_sky")                                     # (the base's own row for it is not asked: the 4x pack's is)
	assert_that(_color_of(sky)).is_equal(PicturesShelf.CYAN)
	assert_vector(sky.get_size()).is_equal(Vector2(4, 4))
	assert_array(TroubleLog.session.told).is_empty()
	assert_array(Packs.picture_decision().shortfalls).is_empty()


func test_the_pictures_of_a_pack_of_another_scale_are_off_but_the_rest_of_the_pack_stays() -> void:
	_shelf.mount_hires()
	assert_object(Pictures.resolve("deco/coral_fan_cyan")).is_null()                        # (`over` is not in this chain; the base's own 1x rows are off)
	assert_object(Pictures.resolve("ui_picture/loop_a")).is_null()
	assert_bool(Packs.in_chain(_shelf.base.id)).is_true()                                   # (still in the chain: its other content answers)
	assert_object(Pictures.in_pack(Packs.pack(_shelf.base.id), "ui_picture/title_sky")).is_not_null()      # (what the pack itself draws, whatever the run does)


func test_two_packs_of_scale_4_that_together_cover_are_chosen() -> void:
	var needed := PackShelf.dev_picture_keys()                                                                                     # (the dev pack holds every picture the game needs)
	assert_int(needed.size()).is_greater(100)
	var half := needed.size() / 2
	var below := _pack_of(PackShelf.base_id(), 4, needed.slice(0, half), Color.RED)
	var above := _pack_of(below.id, 4, needed.slice(half), Color.BLUE)
	above.mount()
	assert_int(Packs.picture_decision().scale).is_equal(4)
	assert_array(Packs.picture_decision().packs.map(func(each: Pack) -> StringName: return each.id)).is_equal([above.id, below.id])
	assert_that(_color_of(Pictures.resolve(needed[0]))).is_equal(Color.RED)
	assert_that(_color_of(Pictures.resolve(needed[needed.size() - 1]))).is_equal(Color.BLUE)
	assert_array(TroubleLog.session.told).is_empty()
	below.mount()                                                                            # (the lower alone does not cover)
	assert_int(Packs.picture_decision().scale).is_equal(1)


func test_the_highest_covering_scale_wins_and_a_lower_one_is_not_told() -> void:
	var needed := PackShelf.dev_picture_keys()
	var twice := _pack_of(PackShelf.base_id(), 2, needed, Color.GREEN)
	var four := _pack_of(twice.id, 4, needed, Color.RED)
	four.mount()
	assert_int(Packs.picture_decision().scale).is_equal(4)
	assert_that(_color_of(Pictures.resolve(needed[0]))).is_equal(Color.RED)
	assert_array(TroubleLog.session.told).is_empty()
	twice.mount()
	assert_int(Packs.picture_decision().scale).is_equal(2)


# --- a pack that does not cover is off, and told once -------------------------------------------------------------------------

func test_a_pack_of_scale_4_that_does_not_cover_is_off_and_told_once_per_run() -> void:
	var held := PackShelf.dev_picture_keys().slice(0, 2)
	var partial := _pack_of(PackShelf.base_id(), 4, held, Color.RED)
	partial.mount()
	assert_int(Packs.picture_decision().scale).is_equal(1)
	var drawn := Pictures.resolve(held[0])                                                    # (the dev pack's picture: a 4x pack that does not cover gives none)
	assert_bool(drawn is ScaledTexture).is_false()
	assert_vector(drawn.get_size()).is_equal(Vector2(Packs.dev().texture(Packs.dev().picture_table().files[held[0]]).get_size()))
	var shortfall := Packs.picture_decision().shortfalls[0]
	var missing := shortfall.missing
	assert_int(missing.size()).override_failure_message("the pack lacks nearly every key of the dev pack").is_greater(100)
	assert_int(shortfall.needed).override_failure_message("the pack's two rows are two of the pictures the game needs").is_equal(missing.size() + 2)
	for key in held:
		assert_array(missing).not_contains([key])
	var expected := "[pictures] pack '%s' (picture scale 4) has no picture for %d of the %d pictures the game needs (%s, %s, %s, %s, %s and %d more), so the pictures of that pack are not drawn and the game draws the pictures of scale 1 (pack '%s') instead" % [
			partial.id, missing.size(), shortfall.needed, missing[0], missing[1], missing[2], missing[3], missing[4], missing.size() - 5, PackShelf.base_id()]
	for i in 3:
		Pictures.resolve(held[0])
		Pictures.forget()                                                                     # (asked again from scratch: the same cause is not told again)
		Pictures.resolve(held[1])
	assert_array(TroubleLog.session.told).is_equal([expected])
	GameState.reset()                                                                         # (a new run is told too)
	assert_array(TroubleLog.session.told).is_empty()
	Pictures.resolve(held[0])
	assert_array(TroubleLog.session.told).is_equal([expected])


func test_the_check_of_the_pack_gives_the_same_finding_with_every_key() -> void:
	var keys := PackShelf.dev_picture_keys()
	var partial := _pack_of(PackShelf.base_id(), 4, [keys[0]] as Array[String], Color.RED)
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(partial.root), options)
	var told := report.findings.filter(func(finding: PackReport.Finding) -> bool: return finding.area == "pictures" and finding.message.contains("picture scale 4"))
	assert_array(told).has_size(1)
	assert_int(told[0].severity).is_equal(PackReport.Severity.WARNING)
	var decision := PackNeeds.inspect(PackNeeds.chain_of(Pack.open(partial.root))).decision
	assert_str(told[0].message).is_equal(decision.shortfalls[0].text(-1))
	for key in decision.shortfalls[0].missing:
		assert_str(told[0].message).contains(key)
	assert_int(decision.shortfalls[0].missing.size()).is_greater(100)
	assert_str(told[0].message).not_contains("more)")


func test_a_4x_alias_never_lands_on_a_1x_row() -> void:
	_shelf.mount_hires()
	assert_object(Pictures.resolve("ui_picture/lost_in_4x")).is_null()                       # (only the 1x base has a row for it)
	assert_object(Pictures.resolve("ui_picture/four_x_alias")).is_null()                     # (the alias is in the 4x pack, its target is not: left out, told)
	var told := _told_about("'ui_picture/four_x_alias' is an alias of 'ui_picture/lost_in_4x'")
	assert_array(told).has_size(1)
	assert_str(told[0]).contains("pack '%s'" % _shelf.hires.id)
	assert_str(Pictures.unanswered("ui_picture/four_x_alias", Packs.picture_decision().packs)).contains("no pack of the chain has a row for that")
	_shelf.mount_base()
	assert_object(Pictures.resolve("ui_picture/lost_in_4x")).is_not_null()                   # (at scale 1 the row answers)


# --- every change of the chain decides again --------------------------------------------------------------------------------------

func test_every_change_of_the_chain_decides_the_scale_again_and_the_pictures_follow() -> void:
	var ref := PictureRef.of("frame/sub_00")
	_shelf.mount_base()
	assert_object(ref.resolved()).is_not_instanceof(ScaledTexture)
	var epoch := Pictures.epoch
	_shelf.mount_hires()
	assert_int(Packs.picture_decision().scale).is_equal(4)
	assert_int(Pictures.epoch).is_greater(epoch)
	assert_object(ref.resolved()).is_instanceof(ScaledTexture)                                # (a holder of the key follows the chain)
	assert_vector(ref.get_size()).is_equal(Vector2(4, 4))
	_shelf.mount_over()                                                                       # (`over` is laid over the 1x base: the 4x pack is no longer in the chain)
	assert_int(Packs.picture_decision().scale).is_equal(1)
	assert_object(ref.resolved()).is_not_instanceof(ScaledTexture)
	_shelf.mount_hires()
	assert_int(Packs.picture_decision().scale).is_equal(4)
	var saved := Packs.snapshot()
	_shelf.base.mount()                                                                       # (a chain borrowed and put back: `restore`)
	assert_int(Packs.picture_decision().scale).is_equal(1)
	Packs.restore(saved)
	assert_int(Packs.picture_decision().scale).is_equal(4)
	assert_object(ref.resolved()).is_instanceof(ScaledTexture)


# --- covered means would draw ----------------------------------------------------------------------------------------------------

func test_a_set_whose_alias_leads_to_a_key_only_a_pack_of_scale_1_answers_does_not_cover() -> void:
	var keys := PackShelf.dev_picture_keys()
	var aliased := keys[0]
	var target := keys[1]
	var held := keys.slice(2)                                                                   # (the set holds neither `aliased` as a file nor its target)
	_pack_of(PackShelf.base_id(), 4, held, Color.RED, {aliased: {"alias": target}}).mount()      # (a row for `aliased` that answers nothing at scale 4: the target is a row of the dev pack only)
	assert_int(Packs.picture_decision().scale).is_equal(1)
	assert_array(Packs.picture_decision().shortfalls[0].missing).contains([aliased, target])
	_pack_of(PackShelf.base_id(), 4, held, Color.RED, {aliased: {"alias": target}, target: "art/scaled.png"}).mount()      # (the target in the set: the alias answers)
	assert_int(Packs.picture_decision().scale).is_equal(4)


func test_a_set_whose_row_names_a_file_the_pack_does_not_hold_does_not_cover() -> void:
	var keys := PackShelf.dev_picture_keys()
	_pack_of(PackShelf.base_id(), 4, keys.slice(1), Color.RED, {keys[0]: "art/not_there.png"}).mount()
	assert_int(Packs.picture_decision().scale).is_equal(1)
	assert_array(Packs.picture_decision().shortfalls[0].missing).is_equal([keys[0]])


func test_the_decision_asks_the_resolver_of_the_lookups() -> void:
	var keys := PackShelf.dev_picture_keys()
	_pack_of(PackShelf.base_id(), 4, keys.slice(1), Color.RED, {keys[0]: {"alias": keys[1]}}).mount()      # (an alias to a key of the same set)
	assert_int(Packs.picture_decision().scale).is_equal(4)
	assert_object(Pictures.resolve(keys[0])).is_instanceof(ScaledTexture)                       # (covered = drawn: the lookup answers every key the set was measured on)
	for key in keys:
		assert_object(Pictures.resolve(key)).override_failure_message("'%s' is covered but not drawn" % key).is_not_null()


## What a chain on the dev pack needs is among the rows of the dev pack's table, so a pack that holds a row for every key of the table covers it: the keys the tests above build their packs from stand for the needs. (The one place a test asks the engine for the needs to look at them.)
func test_the_keys_a_chain_needs_are_rows_of_the_dev_pack_and_the_named_ones_are_among_them() -> void:
	var keys := PackShelf.dev_picture_keys()
	var needed := PictureScale.needed(Packs.chain(), PackNeeds.picture_keys(Packs.chain()))
	assert_int(needed.size()).is_greater(100)
	for key in needed:
		assert_array(keys).override_failure_message("'%s' is needed and no row of the dev pack" % key).contains([key])
	assert_array(needed).contains(["background/bg_s01_03", "ui_picture/control_console", "frame/anemone_mid"])


# --- backgrounds and wildcards of mods count ------------------------------------------------------------------------------------

func test_a_set_without_a_background_the_game_would_draw_at_scale_1_does_not_cover() -> void:
	var keys := PackShelf.dev_picture_keys()
	assert_array(keys.filter(func(key: String) -> bool: return key.begins_with("background/"))).is_not_empty()
	assert_array(PackNeeds.gaps(Packs.chain())).is_empty()                                      # (no background is a gap: a chain without one starts)
	var lacking := "background/bg_s01_03"
	assert_array(keys).contains([lacking])
	var held: Array[String] = []
	held.assign(keys.filter(func(key: String) -> bool: return key != lacking))
	_pack_of(PackShelf.base_id(), 4, held, Color.RED).mount()
	assert_int(Packs.picture_decision().scale).is_equal(1)
	assert_array(Packs.picture_decision().shortfalls[0].missing).is_equal([lacking])
	assert_array(TroubleLog.session.told).is_empty()
	Pictures.resolve("ui_picture/title_sky")
	assert_array(TroubleLog.session.told).has_size(1)                                           # (told once, naming the background)
	assert_str(TroubleLog.session.told[0]).contains(lacking)
	_pack_of(PackShelf.base_id(), 4, keys, Color.RED).mount()
	assert_int(Packs.picture_decision().scale).is_equal(4)
	assert_object(Assets.background(1, 3)).is_not_null()
	assert_object(Pictures.resolve(lacking)).is_instanceof(ScaledTexture)


# --- the decision is pure and the scan is made once --------------------------------------------------------------------------------

func test_a_chain_is_decided_from_its_own_scan_not_from_the_decision_of_the_chain_in_use() -> void:
	_shelf.mount_hires()                                                                        # (the chain in use is at 4)
	var covering := Packs.picture_decision()
	assert_int(covering.scale).is_equal(4)
	var partial := _pack_of(PackShelf.base_id(), 4, [PackShelf.dev_picture_keys()[0]] as Array[String], Color.RED)
	var scan := PackNeeds.inspect(PackNeeds.chain_of(Pack.open(partial.root)))                  # (a chain that does not cover, asked while the decision in use is the covering one)
	assert_int(scan.decision.scale).is_equal(1)
	assert_array(scan.decision.shortfalls).has_size(1)
	assert_object(Packs.picture_decision()).override_failure_message("a question about another chain leaves the decision in use alone").is_same(covering)
	_shelf.mount_base()                                                                         # (and the other way round: the chain in use at 1, asked about a covering chain)
	assert_int(Packs.picture_decision().scale).is_equal(1)
	var hires := Pack.open(_shelf.hires.root)
	var keys := PackNeeds.picture_keys(PackNeeds.chain_of(hires))
	assert_int(PictureScale.decide(PackNeeds.chain_of(hires), keys).scale).is_equal(4)
	assert_int(Packs.picture_decision().scale).is_equal(1)


func test_the_closure_is_walked_once_per_chain_change_whichever_way_it_is_asked() -> void:
	_shelf.mount_hires()
	var walks := PackNeeds.walks
	var decision := Packs.picture_decision()
	assert_int(decision.scale).is_equal(4)
	assert_int(PackNeeds.walks - walks).override_failure_message("deciding walks the closure once").is_equal(1)
	assert_object(Packs.picture_decision()).is_same(decision)
	Pictures.resolve("ui_picture/title_sky")
	assert_int(PackNeeds.walks - walks).override_failure_message("a lookup asks the decision, it does not scan").is_equal(1)
	walks = PackNeeds.walks                                                                     # (a question about another chain: lent, walked once, and the decision in use comes back as it was)
	var other := PackNeeds.chain_of(Pack.open(_shelf.base.root))
	PackNeeds.gaps(other)
	assert_int(PackNeeds.walks - walks).is_equal(1)
	assert_object(Packs.picture_decision()).override_failure_message("restore gives back the decision of the chain").is_same(decision)
	assert_int(PackNeeds.walks - walks).is_equal(1)
	_shelf.mount_over()                                                                         # (a change of the chain: one walk, when a decision is asked, and only when a pack holds a scale above 1)
	walks = PackNeeds.walks
	assert_int(Packs.picture_decision().scale).is_equal(1)
	assert_int(PackNeeds.walks - walks).is_equal(0)


func test_a_decision_tells_its_shortfalls_once_made() -> void:
	_pack_of(PackShelf.base_id(), 4, [PackShelf.dev_picture_keys()[0]] as Array[String], Color.RED).mount()
	var decision := Packs.picture_decision()
	assert_array(decision.texts).is_equal([decision.shortfalls[0].text()])
	assert_array(decision.packs.map(func(each: Pack) -> StringName: return each.id)).is_equal([PackShelf.base_id()])


func test_every_picture_of_a_run_is_of_the_scale_of_the_decision() -> void:
	_shelf.mount_hires()
	var needed := Packs.pack(_shelf.hires.id).picture_table().files.keys()                          # (every file row of the 4x pack)
	assert_int(Packs.picture_decision().scale).is_equal(4)
	for key in needed:
		assert_int(ScaledTexture.scale_of(Pictures.resolve(key))).override_failure_message("'%s' is not drawn at the run's scale" % key).is_equal(Packs.picture_decision().scale)
	_shelf.mount_base()
	for key in needed.slice(0, 50):
		assert_int(ScaledTexture.scale_of(Pictures.resolve(key))).is_equal(1)


func test_the_size_a_pack_of_a_higher_scale_is_held_to_follows_an_alias_across_the_packs_of_scale_1() -> void:
	var key := "ui_picture/zz_alias_of_the_title_sky"
	var shelf := PackShelf.new(&"", PackShelf.base_id())
	_extra.append(shelf)
	shelf.write_json(PictureTable.FILE, {"format": PictureTable.FORMAT, "pictures": {key: {"alias": "ui_picture/title_sky"}}})     # (the alias is in the pack above, its target in the pack below)
	shelf.mount()
	var dev := Packs.dev()
	var target := dev.png_size(dev.picture_table().files["ui_picture/title_sky"])
	assert_vector(target).is_not_equal(Vector2i.ZERO)
	assert_vector(Pictures.scale_one_size(key)).is_equal(target)
	assert_vector(Pictures.scale_one_size("ui_picture/zz_nothing")).is_equal(Vector2i.ZERO)
