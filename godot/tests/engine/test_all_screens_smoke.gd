class_name TestAllScreensSmoke
extends GdUnitTestSuite
## "Slow" smoke test: build every screen of every sector of the chain once (the pack's sectors, whichever pack it is). Catches a
## missing background, a deco slot outside the SpriteFrames, a bad tile source ...
##
## Teaches: a loop test that only checks "does not blow up and produces something".


func test_every_screen_loads() -> void:
	var world := scene_runner("res://src/gameplay/sector_world.tscn").scene() as SectorWorld
	var loaded := 0
	var sectors := Catalog.sector_ids()
	assert_int(sectors.size()).is_greater(0)
	var played := _sectors_of_campaigns()
	for sector_index in sectors:
		world.load_sector(sector_index)
		for screen_index in Catalog.SCREENS_PER_SECTOR:
			world.load_screen(screen_index)
			assert_int(world.screen_index).is_equal(screen_index)
			var screen := world.sector.screens[screen_index]
			# A sector of the pack's own game has a background behind every screen that holds anything; a test sector may have none.
			if sector_index in played and (screen.tiles.count(0) < screen.tiles.size() or not screen.bg_decos.is_empty()):
				assert_object(world.original.background.texture).override_failure_message("sector %d screen %d has no background" % [sector_index, screen_index]).is_not_null()
			# Setting `frame` on an AnimatedSprite2D silently clamps to the last picture,
			# so check that every deco really shows the slot the data asks for.
			_check_slots(world.original.back_decos, screen.bg_decos)
			_check_slots(world.original.mid_decos, screen.mid_decos)
			_check_slots(world.original.front_decos, screen.fg_decos)
			loaded += 1
	assert_int(loaded).is_equal(sectors.size() * Catalog.SCREENS_PER_SECTOR)


## The numbers of the sectors of the pack's own game (the dev tour): the ones that have a picture behind every screen. (The test sectors of the batches are in no
## campaign, or in one made for a test, and have none.)
func _sectors_of_campaigns() -> Array[int]:
	var found: Array[int] = []
	found.append_array(DevPack.TOUR_SECTORS)
	found.append(DevPack.TOUR_FINALE)
	return found


func _check_slots(container: Node2D, placements: Array[DecoPlacement]) -> void:
	for i in placements.size():
		assert_int((container.get_child(i) as Deco).frame).is_equal(placements[i].slot)
