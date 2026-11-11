class_name TestModSkinLegacy
extends GdUnitTestSuite
## A skin mod and the original game's sectors: the example skin (`tests/mods/skinny`) draws every screen of every sector of the original without a fault. A sandboxed script may hold only so many of
## the host's objects (`references_max`), so the state the game hands a skin must be small enough for a skin that walks all of it: this is the proof for the biggest screens there are. (The skin API itself, on any pack, is in tests/engine/test_mod_skin.gd.)


## Without the legacy pack (the original game, made by the importer from your own copy) this suite skips.
func before(do_skip := not LegacyPack.present() or not ModLoader.sandbox_available(), skip_reason := "run the importer on your copy of the game (uv run tools/import/import_all.py) and fetch the sandbox (uv run tools/fetch_sandbox.py)") -> void:
	pass


func test_the_example_skin_draws_every_screen_of_every_sector_of_the_original_without_a_fault() -> void:
	var shelves := ModSkinShelf.mount(["skinny"] as Array[String])
	var skin := SkinChoice.load_skin(shelves[0].id)
	var mod := ModHost.mod(String(shelves[0].id))
	var faults := int(mod.get("monitor_exceptions"))
	var screens := 0
	var most := 0
	var most_decos := 0
	var backgrounds := 0
	for index in Catalog.sector_ids():
		GameState.reset()
		var sim := SimWorld.new(GameState)
		var presenter := (load("res://src/gameplay/original_presenter.tscn") as PackedScene).instantiate() as OriginalPresenter
		presenter.skin = skin
		add_child(presenter)
		presenter.run_in_skin(presenter.bind.bind(sim))
		sim.load_sector(index, 0)
		for screen in Catalog.sector(index).screens.size():
			sim.load_screen(screen)
			presenter.refresh()
			screens += 1
			most_decos = maxi(most_decos, presenter.view.decorations().size())
			var first_layer := presenter.mod_layers()[0]
			for layer in presenter.mod_layers():
				most = maxi(most, layer.commands.size())
			if Assets.has_background(index, screen):                                  # (the picture behind the screen is the first the skin draws, by its key: the very texture the original look shows)
				var first_picture: Array = first_layer.commands.filter(func(c: Array) -> bool: return c[0] == "picture")[0]
				assert_object(first_picture[1]).override_failure_message("sector %d screen %d: the skin's background is not the original look's" % [index, screen]).is_same(Assets.background(index, screen))
				backgrounds += 1
		presenter.unbind()
		presenter.free()
		sim.abandon_damage()
	var faulted := int(mod.get("monitor_exceptions")) - faults
	ModSkinShelf.release(shelves)
	assert_int(screens).is_greater(100)
	assert_int(faulted).override_failure_message("the example skin faulted on a screen of the original").is_equal(0)
	assert_int(backgrounds).override_failure_message("screens with a background to compare").is_greater(100)
	assert_int(most).is_greater(20)
	assert_int(most_decos).override_failure_message("a screen with a hundred decorations to walk").is_greater(100)
