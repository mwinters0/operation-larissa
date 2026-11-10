class_name TestDrawOrderLegacy
extends GdUnitTestSuite
## The original's HUD frame: its left black strip is the rectangle (12, 32, 5, 288) and the playfield, drawn after the frame, covers its last pixel column.
## The order of the layers of the playfield is in `tests/engine/test_draw_order.gd`.

const GAME_SCENE := "res://src/gameplay/game.tscn"


func test_the_playfield_covers_the_last_pixel_column_of_the_frames_black_strip() -> void:
	# The frame's left black strip is Rect2i(12, 32, 5, 288): x 12-16. The playfield starts at x = 16 and is drawn
	# after the frame, so its first column shows. (Drawing the HUD frame last blacked it out.)
	var game := scene_runner(GAME_SCENE).scene() as Game
	assert_bool(game.get_node("%Hud").get_index() < game.get_node("%SectorWorld").get_index()).is_true()
	var strip := Rect2i()
	for rect in (game.get_node("%Hud") as Hud).frame.layout.frame_rects:
		if rect.position == Vector2i(12, 32):
			strip = rect
	assert_int(strip.end.x).is_equal(17)
	assert_int(int(game.world.global_position.x)).is_equal(16)
