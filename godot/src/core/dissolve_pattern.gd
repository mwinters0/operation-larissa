class_name DissolvePattern
extends RefCounted
## The pattern of the "tank lost" dissolve: which pixel of the sub's box is replaced in which pass.
##
## Teaches: turning a loop that DRAWS over time (the original's `dissolve`, 16 passes of tiny copies) into a
## table that says WHEN each pixel changes. The table (an `Image`, one byte per pixel) can then be handed to a
## shader, and the animation is just "show the first N passes". The rule itself is plain integer arithmetic
## and can be unit tested without a renderer.
##
## How the original does it (`RedrawFrameAfterTankLoss` 0x418bcb -> `dissolve` 0x414f81):
##   * The box is the sub's 96 x 58 picture box, cut to the playfield window (`box_for`).
##   * Pass p (0..15) copies 2 x 2 pixel blocks from the picture without the sub over the picture with it. In the
##     pair of rows that starts at row r (r = 0, 2, 4 ...) the blocks sit at x = k * 16 + COLUMN_ORDER[p] - ROW_ORDER[r % 16]
##     (only x in 0 .. width - 3 are copied). COLUMN_ORDER shuffles which column residue comes in which pass, and
##     ROW_ORDER shifts the pattern from one pair of rows to the next, so the dissolve looks like noise.
##   * After every pass the box is flushed to the screen (`FlushRect`); after the 16th, one more full copy and flush
##     replaces whatever the blocks missed (the last column of the box).
##
## The tables are the 16 bytes at 0x441188 (columns) and 0x441198 (rows) of ONWIN32.EXE
## (`docs/data/dissolve_tables.json`, checked by `tests/engine/test_tank_loss_dissolve.gd`).

const COLUMN_ORDER: Array[int] = [11, 13, 5, 14, 7, 1, 15, 2, 0, 3, 8, 4, 9, 12, 6, 10]
const ROW_ORDER: Array[int] = [13, 11, 6, 10, 3, 1, 15, 0, 12, 5, 7, 2, 4, 14, 9, 8]
const PASSES := 16
const BLOCK := 2
## The "pass" of a pixel the 16 passes miss: it changes with the final full copy.
const FINAL_COPY := PASSES
## The picture box of the sub in window pixels (`DrawSub` draws a 96 x 54 picture; the flush box is 96 x 58).
const BOX_SIZE := Vector2i(96, 58)
## The playfield window inside the 640 x 400 screen: x 16 .. 623, y 32 .. 319.
const WINDOW := Rect2i(16, 32, 608, 288)


## The part of the sub's picture box that is dissolved, in window pixels: `RedrawFrameAfterTankLoss` (0x418bcb)
## cuts the box where it sticks out of the window (SubX < 16, SubX >= 528, SubY < 32, SubY >= 262).
static func box_for(sub_x: int, sub_y: int) -> Rect2i:
	var x := sub_x
	var width := BOX_SIZE.x
	if sub_x < WINDOW.position.x:
		x = WINDOW.position.x
		width = BOX_SIZE.x - (WINDOW.position.x - sub_x)
	elif sub_x >= WINDOW.end.x - BOX_SIZE.x:
		width = WINDOW.end.x - sub_x
	var y := sub_y
	var height := BOX_SIZE.y
	if sub_y < WINDOW.position.y:
		y = WINDOW.position.y
		height = BOX_SIZE.y - (WINDOW.position.y - sub_y)
	elif sub_y >= WINDOW.end.y - BOX_SIZE.y:
		height = WINDOW.end.y - sub_y
	return Rect2i(x, y, width, height)


## Does pass `pass_index` (0..15) copy the 2 x 2 block whose top-left corner is (x, y) in the box?
## This is the test inside the original's two loops, written as a question about ONE block.
static func block_in_pass(pass_index: int, x: int, y: int, width: int) -> bool:
	if x < 0 or x > width - BLOCK - 1 or y % BLOCK != 0:
		return false
	var row_shift: int = ROW_ORDER[y % 16]
	return posmod(x + row_shift, 16) == COLUMN_ORDER[pass_index]


## The pass in which pixel (x, y) of a box `width` wide changes: 0..15, or `FINAL_COPY` for a pixel no block
## reaches. A pixel belongs to two blocks (the one that starts at x and the one that starts at x - 1).
static func pass_of(x: int, y: int, width: int) -> int:
	var row := y - y % BLOCK                          # the pair of rows the pixel is in
	for pass_index in PASSES:
		if block_in_pass(pass_index, x, row, width) or block_in_pass(pass_index, x - 1, row, width):
			return pass_index
	return FINAL_COPY


## A `width` x `height` single-channel image: the pass of every pixel as its value. This is what the shader reads.
static func make_mask(width: int, height: int) -> Image:
	var mask := Image.create(width, height, false, Image.FORMAT_R8)
	for y in height:
		for x in width:
			mask.set_pixel(x, y, Color(pass_of(x, y, width) / 255.0, 0.0, 0.0))
	return mask


## The pixels that changed in `step` (0..15 = that pass; `FINAL_COPY` = the closing full copy). For tests and
## debugging: the shader does not need the list.
static func pixels_in_step(step: int, width: int, height: int) -> Array[Vector2i]:
	var pixels: Array[Vector2i] = []
	for y in height:
		for x in width:
			if pass_of(x, y, width) == step:
				pixels.append(Vector2i(x, y))
	return pixels
