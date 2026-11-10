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
	for index in Catalog.sector_ids():
		GameState.reset()
		var sim := SimWorld.new(GameState)
		var presenter := (load("res://src/mods/mod_presenter.tscn") as PackedScene).instantiate() as ModPresenter
		presenter.skin = skin
		add_child(presenter)
		presenter.run_in_skin(presenter.bind.bind(sim))
		sim.load_sector(index, 0)
		for screen in Catalog.sector(index).screens.size():
			sim.load_screen(screen)
			presenter.refresh()
			screens += 1
			for child in presenter.get_children():
				if child is ModLayer:
					most = maxi(most, (child as ModLayer).commands.size())
		presenter.unbind()
		presenter.free()
		sim.abandon_damage()
	var faulted := int(mod.get("monitor_exceptions")) - faults
	ModSkinShelf.release(shelves)
	assert_int(screens).is_greater(100)
	assert_int(faulted).override_failure_message("the example skin faulted on a screen of the original").is_equal(0)
	assert_int(most).is_greater(20)
