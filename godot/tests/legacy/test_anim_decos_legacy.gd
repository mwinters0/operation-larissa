class_name TestAnimDecosLegacy
extends GdUnitTestSuite
## The original's animated decorations (legacy pack): the 1-based frame lists point at pictures of the size the record says.
## The engine half (playback on the game clock, with a deco of dev's own) is `tests/engine/test_anim_decos.gd`.


func test_frame_lists_point_at_pictures_of_the_header_size() -> void:
	# The header says how big the largest frame is. Every frame in the list must be a
	# real slot and no picture may be larger than that. (If the list were 0-based
	# instead of 1-based, 342 of 355 records would fail this.)
	for sector_index in Catalog.ORIGINAL_SECTOR_COUNT:
		var sector := Catalog.sector(sector_index)
		var frames := Catalog.decos_frames(sector.zone)
		var slot_count := 70 + Catalog.zone(sector.zone).deco_count
		for screen in sector.screens:
			for record in screen.anim_decos:
				assert_int(record.frames.size()).is_greater(0)
				for slot in record.frames:
					assert_int(slot).is_between(0, slot_count - 1)
					var picture_size := frames.get_frame_texture(&"all", slot).get_size()
					assert_bool(picture_size.x <= record.size.x and picture_size.y <= record.size.y).is_true()

