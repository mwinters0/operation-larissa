class_name TestPictures
extends GdUnitTestSuite
## Teaches: the picture tables as a lookup you can test by their effect. The packs of `PicturesShelf` name their picture files at random (`art/zz1.png`), so a picture found for a KEY was found through the table, never through a file name. The order (the pack laid over another
## first, aliases asked of the whole chain again), a row that does not resolve (left out, told once per run, naming the pack and what is shown instead), and the answers forgotten when the chain changes.

var _shelf: PicturesShelf


func before_test() -> void:
	GameState.reset()                                                               # (a run begins: the session's log is a new one)
	_shelf = PicturesShelf.new()


func after_test() -> void:
	_shelf.remove()
	GameState.reset()


## The picture file `rel` of the pack `shelf` made, as the pack of the chain in use holds it (a chain made again opens its packs again).
func _held(shelf: PackShelf, rel: String) -> Texture2D:
	return Packs.pack(shelf.id).texture(rel)


func _told_about(text: String) -> Array[String]:
	var found: Array[String] = []
	for line in TroubleLog.session.told:
		if line.contains(text):
			found.append(line)
	return found


# --- the table of one pack ------------------------------------------------------------------------------------------------

func test_a_table_is_read_through_the_pack() -> void:
	var table := _shelf.base.mount().picture_table()
	assert_bool(table.present).is_true()
	assert_array(table.problems).is_empty()
	assert_str(table.files["ui_picture/title_sky"]).is_equal("art/zz1.png")
	assert_str(table.aliases["ui_picture/coral_noon"]).is_equal("ui_picture/coral_dawn")
	assert_dict(PictureTable.read(Pack.open(_shelf.base.root)).to_data()["pictures"]).is_equal(table.to_data()["pictures"])


func test_a_table_names_each_of_its_mistakes_and_keeps_the_good_rows() -> void:
	var shelf := PackShelf.new()
	shelf.write_json(PictureTable.FILE, {"format": 1, "extra": 1, "pictures": {
		"ui_picture/ok": "art/ok.png", "sky/ok": "art/ok.png", "ui_picture/bad name": "art/ok.png", "frame": "art/ok.png",
		"frame/escape": "../ok.png", "frame/not_png": "art/ok.gif", "frame/number": 5, "frame/two": {"alias": "frame/a", "file": "x.png"},
		"frame/scaled_row": {"file": "art/ok.png", "scale": 2}, "frame/alias_of_nothing": {"alias": "nothing"}, "frame/good": "art/ok.png"}})
	var table := PictureTable.read(Pack.open(shelf.root))
	assert_array(table.keys()).contains_exactly_in_any_order(["ui_picture/ok", "frame/good"])
	var text := "\n".join(table.problems)
	for fragment in ["has no field 'extra'", "'sky/ok' is no picture key", "'ui_picture/bad name' is no picture key", "'frame' is no picture key", "'../ok.png' is not a path inside the pack",
			"'art/ok.gif' is not a .png file", "'frame/number' should be a file", "'frame/two' should be a file", "'frame/scaled_row' should be a file",
			"'nothing', which is no picture key"]:
		assert_str(text).override_failure_message("no sentence says: " + fragment + "\n" + text).contains(fragment)
	for text_of_file in ["not json", "[1]", "{\"format\": 2, \"pictures\": {}}", "{\"pictures\": {}}", "{\"format\": 1, \"pictures\": 3}"]:
		shelf.write_text(PictureTable.FILE, text_of_file)
		var broken := PictureTable.read(Pack.open(shelf.root))
		assert_array(broken.problems).override_failure_message(text_of_file).is_not_empty()
		assert_array(broken.keys()).is_empty()
	shelf.remove()


func test_a_check_finds_a_file_the_pack_lacks_and_aliases_that_circle_within_it() -> void:
	var table := _shelf.base.mount().picture_table()
	var found := "\n".join(table.check(Packs.pack(_shelf.base.id)))
	assert_str(found).contains("'ui_picture/lost' names the file art/gone.png, which the pack does not hold")
	assert_str(found).contains("ui_picture/loop_a -> ui_picture/loop_b -> ui_picture/loop_a")
	assert_str(found).not_contains("nothing_here")                                  # (another pack may hold it: the chain says so when it is in use)


# --- the lookup -----------------------------------------------------------------------------------------------------------

func test_a_key_is_found_through_the_table_whatever_its_file_is_called() -> void:
	_shelf.mount_base()
	var sky := Pictures.resolve("ui_picture/title_sky")
	assert_object(sky).is_same(_held(_shelf.base, "art/zz1.png"))
	assert_object(sky).is_same(Assets.picture_by_key("ui_picture/title_sky").resolved())
	assert_object(Pictures.resolve("problem_art/log_scan_0")).is_same(_held(_shelf.base, "art/zz3.png"))
	assert_object(Pictures.resolve("ui_picture/never_heard_of")).is_null()
	assert_object(Pictures.resolve("")).is_null()
	assert_bool(Pictures.has("frame/eel_swim_0")).is_true()
	assert_bool(Pictures.has("frame/nope")).is_false()


func test_an_alias_is_the_picture_of_its_target_and_so_is_an_alias_of_an_alias() -> void:
	_shelf.mount_base()
	var sky := Pictures.resolve("ui_picture/title_sky")
	assert_object(Pictures.resolve("ui_picture/coral_dawn")).is_same(sky)
	assert_object(Pictures.resolve("ui_picture/coral_noon")).is_same(sky)
	assert_array(TroubleLog.session.told).is_empty()


func test_a_pack_above_that_redraws_the_target_redraws_every_alias_of_it() -> void:
	_shelf.mount_base()
	assert_object(Pictures.resolve("ui_picture/coral_noon")).is_same(_held(_shelf.base, "art/zz1.png"))
	_shelf.mount_over()
	var redrawn := _held(_shelf.over, "art/other.png")
	assert_object(Pictures.resolve("ui_picture/title_sky")).is_same(redrawn)               # (the answers were forgotten with the chain: this is the new chain's)
	assert_object(Pictures.resolve("ui_picture/coral_dawn")).is_same(redrawn)              # (the alias is in the pack UNDER: it asks the whole chain again)
	assert_object(Pictures.resolve("ui_picture/coral_noon")).is_same(redrawn)
	assert_that(PicturesShelf.color_of(Pictures.resolve("ui_picture/coral_noon"))).is_equal(PicturesShelf.WHITE)
	assert_object(Pictures.resolve("problem_art/log_scan_0")).is_same(_held(_shelf.base, "art/zz3.png"))     # (what the pack above does not say, the pack under does)
	assert_object(Pictures.resolve("deco/coral_fan_cyan")).is_same(_held(_shelf.over, "art/zz4.png"))        # (a key only the pack above holds)
	assert_array(TroubleLog.session.told).is_empty()                                       # (nothing asked for did not resolve)


func test_the_answers_are_forgotten_when_the_chain_changes_and_come_back_with_it() -> void:
	_shelf.mount_over()
	var white := Pictures.resolve("ui_picture/title_sky")
	var epoch := Pictures.epoch
	_shelf.mount_base()
	assert_int(Pictures.epoch).is_greater(epoch)
	assert_that(PicturesShelf.color_of(Pictures.resolve("ui_picture/title_sky"))).is_equal(PicturesShelf.RED)
	_shelf.mount_over()
	assert_that(PicturesShelf.color_of(Pictures.resolve("ui_picture/title_sky"))).is_equal(PicturesShelf.WHITE)
	assert_that(PicturesShelf.color_of(white)).is_equal(PicturesShelf.WHITE)


# --- a row that does not resolve ----------------------------------------------------------------------------------------------

func test_a_row_whose_file_is_missing_is_left_out_and_told_once_naming_the_pack() -> void:
	_shelf.mount_base()
	for i in 3:
		assert_object(Pictures.resolve("ui_picture/lost")).is_null()
		Pictures.forget()                                                               # (asked again from scratch: the same cause is not told again)
	var lines := _told_about("art/gone.png")
	assert_array(lines).has_size(1)
	assert_str(lines[0]).contains("pack '%s'" % _shelf.base.id).contains("'ui_picture/lost'").contains("the pack does not hold").contains("the packs under it answer for 'ui_picture/lost', if any do")


func test_a_row_that_is_no_picture_is_told_as_that() -> void:
	_shelf.base.write_bytes("art/zz1.png", "not a picture".to_utf8_buffer())
	_shelf.mount_base()
	assert_object(Pictures.resolve("ui_picture/title_sky")).is_null()
	assert_str(_told_about("art/zz1.png")[0]).contains("is not a PNG picture the game can read")


func test_a_row_of_the_pack_above_that_does_not_resolve_leaves_the_picture_to_the_pack_under_it() -> void:
	_shelf.mount_over()
	assert_object(Pictures.resolve("frame/eel_swim_0")).is_same(_held(_shelf.base, "art/zz2.png"))      # (the row names art/missing_too.png)
	var lines := _told_about("art/missing_too.png")
	assert_array(lines).has_size(1)
	assert_str(lines[0]).contains("pack '%s'" % _shelf.over.id).contains("'frame/eel_swim_0'")


func test_aliases_that_go_round_in_a_circle_give_no_picture_and_are_told_once() -> void:
	_shelf.mount_base()
	for i in 3:
		assert_object(Pictures.resolve("ui_picture/loop_a")).is_null()
		assert_object(Pictures.resolve("ui_picture/loop_b")).is_null()
		Pictures.forget()
	var lines := _told_about("circle")
	assert_array(lines).has_size(2)                                                    # (one cause for each key asked: the circle as met from loop_a, and as met from loop_b)
	assert_str(lines[0]).contains("pack '%s'" % _shelf.base.id).contains("ui_picture/loop_a -> ui_picture/loop_b -> ui_picture/loop_a")
	assert_array(_told_about("which no pack of the chain has a picture for")).is_empty()      # (the circle is the cause: no second line for the same thing)


func test_an_alias_to_a_key_nobody_holds_gives_no_picture_and_is_told_once() -> void:
	_shelf.mount_base()
	for i in 3:
		assert_object(Pictures.resolve("ui_picture/dangling")).is_null()
		Pictures.forget()
	var lines := _told_about("nothing_here")
	assert_array(lines).has_size(1)
	assert_str(lines[0]).contains("pack '%s'" % _shelf.base.id).contains("'ui_picture/dangling' is an alias of 'ui_picture/nothing_here'").contains("which no pack of the chain has a picture for")


func test_what_was_told_is_told_again_in_the_next_run() -> void:
	_shelf.mount_base()
	Pictures.resolve("ui_picture/lost")
	assert_array(_told_about("art/gone.png")).has_size(1)
	GameState.begin_run(null)
	Pictures.forget()
	Pictures.resolve("ui_picture/lost")
	assert_array(_told_about("art/gone.png")).has_size(1)


func test_the_troubles_of_the_rows_are_told_again_in_the_next_run_from_the_kept_answer() -> void:
	_shelf.mount_base()
	var epoch := Pictures.epoch
	Pictures.resolve("ui_picture/lost")                                                                 # (a file the pack does not hold)
	Pictures.resolve("ui_picture/dangling")                                                             # (an alias of a key nobody holds)
	Pictures.resolve("ui_picture/loop_a")                                                               # (aliases that go round)
	var lines: Array[String] = []
	lines.append_array(_told_about("art/gone.png"))
	lines.append_array(_told_about("'ui_picture/dangling' is an alias"))
	lines.append_array(_told_about("go round in a circle"))
	assert_array(lines).has_size(3)
	GameState.begin_run(null)                                                                           # (a run begins: a new log, the chain is the same and its answers are kept)
	assert_array(TroubleLog.session.told).is_empty()
	for key in ["ui_picture/lost", "ui_picture/dangling", "ui_picture/loop_a"]:
		Pictures.resolve(key)
		Pictures.resolve(key)
	assert_int(Pictures.epoch).override_failure_message("the answers were kept").is_equal(epoch)
	assert_array(TroubleLog.session.told).is_equal(lines)                                                # (each once, as the first run was told)


func test_a_reference_tells_what_it_met_and_that_nobody_holds_its_key_again_in_the_next_run() -> void:
	_shelf.mount_base()
	var lost := PictureRef.of("ui_picture/lost")
	var nobody := PictureRef.of("ui_picture/zz_nobody_has_me")
	for ref in [lost, nobody]:
		(ref as PictureRef).get_width()
	assert_array(_told_about("art/gone.png")).has_size(1)
	assert_array(_told_about("'ui_picture/zz_nobody_has_me'")).has_size(1)
	GameState.begin_run(null)
	assert_array(TroubleLog.session.told).is_empty()
	for ref in [lost, nobody]:
		(ref as PictureRef).get_width()
		(ref as PictureRef).get_height()
	assert_array(_told_about("art/gone.png")).has_size(1)
	assert_array(_told_about("'ui_picture/zz_nobody_has_me'")).has_size(1)


# --- the Assets lookups ask the table -----------------------------------------------------------------------------------------

func test_the_assets_lookups_find_a_key_the_table_holds_even_when_the_registry_has_not_its_name() -> void:
	_shelf.mount_over()
	assert_object(Assets.ui_picture(&"title_sky").resolved()).is_same(_held(_shelf.over, "art/other.png"))
	assert_object(Assets.ui_picture(&"coral_dawn").resolved()).is_same(_held(_shelf.over, "art/other.png"))        # (a name of the pack's own)
	assert_object(Assets.problem_art(&"log_scan_0").resolved()).is_same(_held(_shelf.base, "art/zz3.png"))
	assert_object(Assets.picture_by_key("deco/coral_fan_cyan").resolved()).is_same(_held(_shelf.over, "art/zz4.png"))


# --- a pack with no table holds no picture; a name nobody holds is told once -------------------------------------------------

func test_a_pack_with_no_table_holds_no_picture_however_its_files_are_named() -> void:
	var shelf := PackShelf.new()
	shelf.add_picture("assets/ui/title/title_sky_1039.png", Color.RED)               # (the importer's file name for the key)
	shelf.add_picture("pictures/ui_picture/zz_nobody_names_me.png", Color.RED)       # (a folder of <kind>/<name>.png)
	shelf.add_picture("assets/sprites/zz_loose/frame_zz_loose.png", Color.RED)
	shelf.mount()
	assert_bool(Packs.pack(shelf.id).picture_table().present).is_false()
	assert_object(Pictures.resolve("ui_picture/zz_nobody_names_me")).is_null()
	assert_object(Pictures.resolve("frame/zz_loose")).is_null()
	assert_str(Pictures.unanswered("frame/zz_loose", Packs.chain())).is_not_empty()
	assert_str(Pictures.resolve("ui_picture/title_sky").resource_path).override_failure_message("the pack under it answers, a pack with no table says nothing").is_equal(DevPack.picture_file("ui_picture/title_sky"))
	shelf.remove()


func test_a_name_no_pack_holds_is_told_once_naming_the_key_by_the_reference_that_draws_nothing() -> void:
	for ref in [Assets.ui_picture(&"zz_nobody_has_me"), Assets.ui_picture(&"zz_nobody_has_me"), Assets.problem_art(&"zz_nor_me")]:
		assert_vector((ref as PictureRef).get_size()).is_equal(Vector2.ZERO)
		assert_object((ref as PictureRef).resolved()).is_null()
	assert_array(_told_about("'ui_picture/zz_nobody_has_me'")).has_size(1)
	assert_array(_told_about("'problem_art/zz_nor_me'")).has_size(1)
	assert_str(_told_about("'ui_picture/zz_nobody_has_me'")[0]).contains("nothing is drawn")
	assert_bool(Assets.holds("ui_picture/zz_quiet")).override_failure_message("asking whether a picture is held says nothing: the one that draws it says so").is_false()
	Assets.picture_by_key("ui_picture/zz_quiet")
	assert_array(_told_about("zz_quiet")).override_failure_message("a reference nobody draws says nothing").is_empty()
