class_name TestPackCheckPictures
extends GdUnitTestSuite
## Teaches: one finding for one mistake, pinned by its words. `PackCheck` judges a pack's picture table (`pictures.json`) as the game will read it: the file itself (`PictureTable.problems`), each row's file (the pack holds it, the engine can decode it, it is the size of the picture it
## redraws), each alias through the WHOLE chain (`Pictures.unanswered`: the pack under may hold the key, a pack above may make aliases go round), a PNG no row names, a manifest that still maps `pictures`. Every pack here is a scratch pack in `user://` laid over the suite's pack
## (`PackShelf`), with the one thing wrong.

var _shelves: Array[PackShelf] = []


func after_test() -> void:
	for shelf in _shelves:
		shelf.remove()
	_shelves.clear()
	Packs.start()


func _shelf(base: StringName = &"") -> PackShelf:
	var shelf := PackShelf.new(&"", base)
	_shelves.append(shelf)
	return shelf


func _check(shelf: PackShelf) -> PackReport:
	var options := PackCheck.Options.new()
	options.reach = false
	return PackCheck.run(Pack.open(shelf.root), options)


## The texts of the findings of `severity` in the area `pictures`.
func _told(report: PackReport, severity: PackReport.Severity) -> Array[String]:
	var found: Array[String] = []
	for finding in report.findings:
		if finding.severity == severity and finding.area == "pictures":
			found.append(finding.message)
	return found


func _has(report: PackReport, severity: PackReport.Severity, fragment: String) -> bool:
	return _told(report, severity).any(func(message: String) -> bool: return message.contains(fragment))


func test_a_sound_table_says_nothing() -> void:
	var shelf := _shelf()
	shelf.add_picture_row("ui_picture/coral_dawn", Color.RED)
	shelf.add_row("ui_picture/coral_noon", {"alias": "ui_picture/coral_dawn"})
	shelf.add_row("ui_picture/title_sea", {"alias": "ui_picture/title_sky"})                  # (the pack under it holds title_sky)
	var report := _check(shelf)
	assert_array(_told(report, PackReport.Severity.ERROR)).is_empty()
	assert_array(_told(report, PackReport.Severity.WARNING)).is_empty()


func test_a_table_that_is_not_json_or_has_a_bad_row_is_an_error_for_each_mistake() -> void:
	var shelf := _shelf()
	shelf.write_json(PictureTable.FILE, {"format": 1, "pictures": {"ui_picture/ok": "art/ok.png", "wallpaper/sea": "art/ok.png", "ui_picture/bad name": "art/ok.png", "frame/escape": "../ok.png", "frame/odd": 5}})
	shelf.add_picture("art/ok.png", Color.RED)
	var report := _check(shelf)
	for fragment in ["'wallpaper/sea' is no picture key (the kind 'wallpaper' is not one of", "'ui_picture/bad name' is no picture key", "'../ok.png' is not a path inside the pack", "'frame/odd' should be a file of the pack"]:
		assert_bool(_has(report, PackReport.Severity.ERROR, fragment)).override_failure_message("no error says: %s\n%s" % [fragment, report.text()]).is_true()
	var broken := _shelf()
	broken.write_text(PictureTable.FILE, "{not json")
	assert_bool(_has(_check(broken), PackReport.Severity.ERROR, "pictures.json line")).is_true()


func test_a_row_whose_file_the_pack_lacks_or_the_engine_cannot_decode_is_an_error() -> void:
	var shelf := _shelf()
	shelf.add_row("ui_picture/lost", "art/gone.png")
	shelf.write_text("art/liar.png", "not a picture")
	shelf.add_row("ui_picture/liar", "art/liar.png")
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "'ui_picture/lost' names the file art/gone.png, which the pack does not hold")).is_true()
	assert_bool(_has(report, PackReport.Severity.ERROR, "'ui_picture/liar' names art/liar.png, which is not a PNG picture the engine can decode")).is_true()
	assert_bool(report.passes()).is_false()


func test_aliases_that_go_round_inside_the_pack_are_an_error() -> void:
	var shelf := _shelf()
	shelf.add_row("ui_picture/loop_a", {"alias": "ui_picture/loop_b"})
	shelf.add_row("ui_picture/loop_b", {"alias": "ui_picture/loop_a"})
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "the aliases ui_picture/loop_a -> ui_picture/loop_b -> ui_picture/loop_a go round in a circle")).is_true()
	assert_bool(_has(report, PackReport.Severity.ERROR, "no picture answers for")).override_failure_message("the circle is the one cause: it is told once, not again as an alias nothing answers").is_false()


func test_an_alias_to_a_key_no_pack_of_the_chain_holds_is_an_error_and_the_pack_under_may_hold_it() -> void:
	var shelf := _shelf()
	shelf.add_row("ui_picture/dangling", {"alias": "ui_picture/nothing_here"})
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.ERROR, "'ui_picture/dangling' is an alias of 'ui_picture/nothing_here', which no picture answers for: no pack of the chain has a row for it")).override_failure_message(report.text()).is_true()
	var under := _shelf()
	under.add_picture_row("ui_picture/nothing_here", Color.RED)
	var over := _shelf(under.id)
	over.add_row("ui_picture/dangling", {"alias": "ui_picture/nothing_here"})
	assert_array(_told(_check(over), PackReport.Severity.ERROR)).is_empty()


func test_an_alias_whose_target_row_names_a_missing_file_is_an_error_naming_the_pack() -> void:
	var under := _shelf()
	under.add_row("ui_picture/target", "art/gone.png")
	var over := _shelf(under.id)
	over.add_row("ui_picture/via", {"alias": "ui_picture/target"})
	var report := _check(over)
	assert_bool(_has(report, PackReport.Severity.ERROR, "'ui_picture/via' is an alias of 'ui_picture/target', which no picture answers for: its row in pack '%s' names the file art/gone.png, which that pack does not hold" % under.id)).override_failure_message(report.text()).is_true()


func test_aliases_that_go_round_through_two_packs_are_an_error() -> void:
	var under := _shelf()
	under.add_row("ui_picture/a", {"alias": "ui_picture/b"})
	var over := _shelf(under.id)
	over.add_row("ui_picture/b", {"alias": "ui_picture/a"})
	var report := _check(over)
	assert_bool(_has(report, PackReport.Severity.ERROR, "go round in a circle")).override_failure_message(report.text()).is_true()


func test_a_png_no_row_names_is_a_warning_and_the_folders_of_a_mod_are_not_judged() -> void:
	var shelf := _shelf()
	shelf.add_picture_row("ui_picture/named", Color.RED)
	shelf.add_picture("art/stray.png", Color.BLUE)
	shelf.add_picture("skin/own.png", Color.GREEN)                                                # (not a mod: judged)
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.WARNING, "art/stray.png is named by no row of pictures.json: nothing reads it")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "skin/own.png is named by no row")).is_true()
	assert_bool(_has(report, PackReport.Severity.WARNING, "art/ui_picture_named.png")).is_false()
	var mod := _shelf()
	mod.add_mod_fixture("res://tests/mods/skin_data")
	ModSkinShelf.add_files(mod)
	assert_bool(_told(_check(mod), PackReport.Severity.WARNING).any(func(message: String) -> bool: return message.contains("skin/dot.png"))).override_failure_message("a draw list names a mod's own pictures by path").is_false()


func test_a_pack_with_no_table_holds_no_picture_and_its_pngs_are_named_by_no_row() -> void:
	var shelf := _shelf()
	shelf.add_picture("assets/ui/title/title_sky_1039.png", Color.RED)
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.WARNING, "assets/ui/title/title_sky_1039.png is named by no row of pictures.json: nothing reads it")).override_failure_message(report.text()).is_true()
	assert_array(_told(report, PackReport.Severity.ERROR)).is_empty()


func test_a_picture_that_is_not_the_size_of_the_one_it_redraws_is_a_warning_unless_the_pack_scale_makes_it_so() -> void:
	var size: Vector2i = SkinTemplates.sizes()["ui_picture/ui_1195"]
	var shelf := _shelf()
	shelf.add_picture_row("ui_picture/ui_1195", Color.RED, Vector2i(3, 3))
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.WARNING, "'ui_picture/ui_1195' is 3x3, and the picture it replaces is %dx%d: it is drawn stretched to that place" % [size.x, size.y])).override_failure_message(report.text()).is_true()
	var right := _shelf()
	right.add_picture_row("ui_picture/ui_1195", Color.RED, size)
	assert_array(_told(_check(right), PackReport.Severity.WARNING)).is_empty()
	var scaled := _shelf()
	scaled.add_picture("art/big.png", Color.RED, size * 4)
	scaled.add_row("ui_picture/ui_1195", "art/big.png")
	scaled.set_picture_scale(4)                                                                    # (4x art: drawn at its size over 4)
	var scaled_report := _check(scaled)
	assert_bool(_told(scaled_report, PackReport.Severity.WARNING).any(func(message: String) -> bool: return message.contains("stretched"))).override_failure_message(scaled_report.text()).is_false()
	assert_array(_told(scaled_report, PackReport.Severity.ERROR)).is_empty()


func test_a_pack_of_a_higher_picture_scale_that_does_not_cover_is_a_warning_with_every_missing_key() -> void:
	var shelf := _shelf()
	shelf.add_picture_row("ui_picture/title_sea", Color.RED, Vector2i(16, 16))
	shelf.set_picture_scale(4)
	var report := _check(shelf)
	var told := _told(report, PackReport.Severity.WARNING).filter(func(message: String) -> bool: return message.contains("picture scale 4"))
	assert_array(told).has_size(1)
	var needed := PictureScale.needed(PackNeeds.chain_of(Pack.open(shelf.root)), PackNeeds.picture_keys(PackNeeds.chain_of(Pack.open(shelf.root))))
	var missing := needed.filter(func(key: String) -> bool: return key != "ui_picture/title_sea")
	assert_array(missing).has_size(needed.size() - 1)                                              # (the pack's one row is a picture the game needs)
	assert_str(told[0]).contains("pack '%s' (picture scale 4) has no picture for %d of the %d pictures the game needs (" % [shelf.id, missing.size(), needed.size()])
	for key in missing:
		assert_str(told[0]).contains(key)                                                           # (every key, not the first few)
	assert_str(told[0]).contains("the game draws the pictures of scale 1 (pack '%s') instead" % PackShelf.base_id())
	assert_str(told[0]).not_contains(" more)")
	assert_array(_told(report, PackReport.Severity.ERROR)).is_empty()


func test_a_pictures_folder_is_not_read_and_the_check_says_so() -> void:
	var shelf := _shelf()
	shelf.add_picture("pictures/ui_picture/title_sky.png", Color.RED)
	var report := _check(shelf)
	assert_bool(_has(report, PackReport.Severity.WARNING, "the pictures/ folder is not read: the game finds a picture through pictures.json")).is_true()


func test_a_manifest_that_maps_pictures_is_refused_with_the_way_to_do_it() -> void:
	var shelf := _shelf()
	shelf.write_json("pack.json", {"id": String(shelf.id), "title": "Old", "version": "1", "base": String(PackShelf.base_id()), "mod": {"requires_api": 5, "skin": {"pictures": {"ui_picture/title_sky": "skin/sky.png"}}}})
	var report := _check(shelf)
	assert_bool(report.passes()).is_false()
	assert_bool(report.findings.any(func(f: PackReport.Finding) -> bool: return f.severity == PackReport.Severity.ERROR and f.message.contains("a skin maps no picture") and f.message.contains("pictures.json"))).override_failure_message(report.text()).is_true()


func test_a_theme_picture_no_pack_holds_is_a_warning_and_one_a_table_holds_is_not() -> void:
	var theme := {"button": {"normal": {"picture": "ui_picture/no_such_picture", "slice": [2, 2, 2, 2]}}}
	var shelf := _shelf()
	shelf.write_json("pack.json", {"id": String(shelf.id), "title": "Themed", "version": "1", "base": String(PackShelf.base_id()), "mod": {"requires_api": 5, "skin": {"theme": theme}}})
	assert_bool(_told(_check(shelf), PackReport.Severity.WARNING).is_empty()).is_true()                # (the pictures area has nothing to say)
	var report := _check(shelf)
	assert_bool(report.findings.any(func(f: PackReport.Finding) -> bool: return f.area == "mod" and f.message.contains("the theme's picture ui_picture/no_such_picture is held by no pack"))).override_failure_message(report.text()).is_true()
	shelf.add_picture_row("ui_picture/no_such_picture", Color.RED)
	assert_bool(_check(shelf).findings.any(func(f: PackReport.Finding) -> bool: return f.message.contains("theme's picture"))).is_false()
