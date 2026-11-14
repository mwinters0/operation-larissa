class_name TestPictureScale
extends GdUnitTestSuite
## Teaches: the scale a run draws its pictures at as a DERIVED fact, tested by its effect. A pack of `picture_scale` 4 is used when the packs of that scale together hold a row for every picture the chain needs (`PackNeeds`), and then the run draws every picture at
## 1/4 of its file (`ScaledTexture`); otherwise the run draws at scale 1 and the shortfall is told once per run (`TroubleLog`). The packs of another scale give no picture, an alias of a 4x pack never lands on a 1x row, and every change of the chain decides again.
## `PicturesShelf.mount_hires` is a 4x pack that covers; the other scratch packs here cover nothing, or part.

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


## A scratch pack of picture scale `scale` laid over `base` that holds a row for each of `keys` (16 x 16 files of `color`, so 4 x 4 at scale 4).
func _pack_of(base: StringName, scale: int, keys: Array[String], color: Color) -> PackShelf:
	var shelf := PackShelf.new(&"", base)
	_extra.append(shelf)
	shelf.set_picture_scale(scale)
	shelf.add_picture("art/big.png", color, Vector2i(16, 16))
	var rows := {}
	for key in keys:
		rows[key] = "art/big.png"
	shelf.write_json(PictureTable.FILE, {"format": PictureTable.FORMAT, "pictures": rows})
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
	for bad: Variant in [0, -1, PictureScale.MAX + 1, 2.5, "4", true, null]:
		var manifest: Dictionary = shelf.pack_json("pack.json")
		manifest["picture_scale"] = bad
		shelf.write_json("pack.json", manifest)
		assert_array(Pack.open(shelf.root).errors).override_failure_message("picture_scale %s" % [bad]).contains(["\"picture_scale\" must be a whole number from 1 to %d" % PictureScale.MAX])


func test_a_chain_of_packs_of_scale_1_is_decided_without_reading_what_it_needs() -> void:
	var decision := PictureScale.decide(Packs.chain())
	assert_int(decision.scale).is_equal(1)
	assert_array(decision.shortfalls).is_empty()
	assert_int(Packs.picture_scale()).is_equal(1)
	assert_array(Packs.picture_packs()).is_equal(Packs.chain())


# --- a covering pack is chosen ------------------------------------------------------------------------------------------------

func test_a_pack_of_scale_4_that_covers_the_chains_pictures_is_the_run_s_scale_and_draws_at_a_quarter_of_its_file() -> void:
	_shelf.mount_hires()
	assert_int(Packs.picture_scale()).is_equal(4)
	assert_array(Packs.picture_packs().map(func(each: Pack) -> StringName: return each.id)).is_equal([_shelf.hires.id])
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
	var needed := PictureScale.needed(Packs.chain())                                         # (the dev pack holds every picture the game needs)
	assert_int(needed.size()).is_greater(100)
	var half := needed.size() / 2
	var below := _pack_of(PackShelf.base_id(), 4, needed.slice(0, half), Color.RED)
	var above := _pack_of(below.id, 4, needed.slice(half), Color.BLUE)
	above.mount()
	assert_int(Packs.picture_scale()).is_equal(4)
	assert_array(Packs.picture_packs().map(func(each: Pack) -> StringName: return each.id)).is_equal([above.id, below.id])
	assert_that(_color_of(Pictures.resolve(needed[0]))).is_equal(Color.RED)
	assert_that(_color_of(Pictures.resolve(needed[needed.size() - 1]))).is_equal(Color.BLUE)
	assert_array(TroubleLog.session.told).is_empty()
	below.mount()                                                                            # (the lower alone does not cover)
	assert_int(Packs.picture_scale()).is_equal(1)


func test_the_highest_covering_scale_wins_and_a_lower_one_is_not_told() -> void:
	var needed := PictureScale.needed(Packs.chain())
	var twice := _pack_of(PackShelf.base_id(), 2, needed, Color.GREEN)
	var four := _pack_of(twice.id, 4, needed, Color.RED)
	four.mount()
	assert_int(Packs.picture_scale()).is_equal(4)
	assert_that(_color_of(Pictures.resolve(needed[0]))).is_equal(Color.RED)
	assert_array(TroubleLog.session.told).is_empty()
	twice.mount()
	assert_int(Packs.picture_scale()).is_equal(2)


# --- a pack that does not cover is off, and told once -------------------------------------------------------------------------

func test_a_pack_of_scale_4_that_does_not_cover_is_off_and_told_once_per_run() -> void:
	var needed := PictureScale.needed(Packs.chain())
	var partial := _pack_of(PackShelf.base_id(), 4, [needed[0], needed[1]] as Array[String], Color.RED)
	partial.mount()
	assert_int(Packs.picture_scale()).is_equal(1)
	var drawn := Pictures.resolve(needed[0])                                                 # (the dev pack's picture: a 4x pack that does not cover gives none)
	assert_bool(drawn is ScaledTexture).is_false()
	assert_vector(drawn.get_size()).is_equal(Vector2(Packs.dev().texture(Packs.dev().picture_table().files[needed[0]]).get_size()))
	var held := needed.size()
	var expected := "[pictures] pack '%s' (picture scale 4) has no row for %d of the %d pictures the game needs (%s, %s, %s, %s, %s and %d more), so the pictures of that pack are not drawn and the game draws the pictures of scale 1 (pack '%s') instead" % [
			partial.id, held - 2, held, needed[2], needed[3], needed[4], needed[5], needed[6], held - 2 - 5, PackShelf.base_id()]
	for i in 3:
		Pictures.resolve(needed[0])
		Pictures.forget()                                                                     # (asked again from scratch: the same cause is not told again)
		Pictures.resolve(needed[i])
	assert_array(TroubleLog.session.told).is_equal([expected])
	GameState.reset()                                                                         # (a new run is told too)
	assert_array(TroubleLog.session.told).is_empty()
	Pictures.resolve(needed[0])
	assert_array(TroubleLog.session.told).is_equal([expected])


func test_the_check_of_the_pack_gives_the_same_finding_with_every_key() -> void:
	var needed := PictureScale.needed(Packs.chain())
	var partial := _pack_of(PackShelf.base_id(), 4, [needed[0]] as Array[String], Color.RED)
	var options := PackCheck.Options.new()
	options.reach = false
	var report := PackCheck.run(Pack.open(partial.root), options)
	var told := report.findings.filter(func(finding: PackReport.Finding) -> bool: return finding.area == "pictures" and finding.message.contains("picture scale 4"))
	assert_array(told).has_size(1)
	assert_int(told[0].severity).is_equal(PackReport.Severity.WARNING)
	var decision := PictureScale.decide(PackNeeds.chain_of(Pack.open(partial.root)))
	assert_str("%s %s" % [PictureScale.TAG, told[0].message]).is_equal(decision.shortfalls[0].line(-1))
	for key in needed.slice(1):
		assert_str(told[0].message).contains(key)
	assert_str(told[0].message).not_contains("more)")


func test_a_4x_alias_never_lands_on_a_1x_row() -> void:
	_shelf.mount_hires()
	assert_object(Pictures.resolve("ui_picture/lost_in_4x")).is_null()                       # (only the 1x base has a row for it)
	assert_object(Pictures.resolve("ui_picture/four_x_alias")).is_null()                     # (the alias is in the 4x pack, its target is not: left out, told)
	var told := _told_about("'ui_picture/four_x_alias' is an alias of 'ui_picture/lost_in_4x'")
	assert_array(told).has_size(1)
	assert_str(told[0]).contains("pack '%s'" % _shelf.hires.id)
	assert_str(Pictures.unanswered("ui_picture/four_x_alias")).contains("no pack of the chain has a row for that")
	_shelf.mount_base()
	assert_object(Pictures.resolve("ui_picture/lost_in_4x")).is_not_null()                   # (at scale 1 the row answers)


# --- every change of the chain decides again --------------------------------------------------------------------------------------

func test_every_change_of_the_chain_decides_the_scale_again_and_the_pictures_follow() -> void:
	var ref := PictureRef.of("frame/sub_00")
	_shelf.mount_base()
	assert_object(ref.resolved()).is_not_instanceof(ScaledTexture)
	var epoch := Pictures.epoch
	_shelf.mount_hires()
	assert_int(Packs.picture_scale()).is_equal(4)
	assert_int(Pictures.epoch).is_greater(epoch)
	assert_object(ref.resolved()).is_instanceof(ScaledTexture)                                # (a holder of the key follows the chain)
	assert_vector(ref.get_size()).is_equal(Vector2(4, 4))
	_shelf.mount_over()                                                                       # (`over` is laid over the 1x base: the 4x pack is no longer in the chain)
	assert_int(Packs.picture_scale()).is_equal(1)
	assert_object(ref.resolved()).is_not_instanceof(ScaledTexture)
	_shelf.mount_hires()
	assert_int(Packs.picture_scale()).is_equal(4)
	var saved := Packs.snapshot()
	_shelf.base.mount()                                                                       # (a chain borrowed and put back: `restore`)
	assert_int(Packs.picture_scale()).is_equal(1)
	Packs.restore(saved)
	assert_int(Packs.picture_scale()).is_equal(4)
	assert_object(ref.resolved()).is_instanceof(ScaledTexture)
