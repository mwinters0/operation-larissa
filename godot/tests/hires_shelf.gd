class_name HiresShelf
extends RefCounted
## Two scratch packs for a test of every consumer of a picture of scale 4 (`test_picture_scale_consumers.gd`, `test_picture_scale_render.gd`): `plain` redraws a few pictures at scale 1, `hires` (picture scale `SCALE`, laid over the pack in use) holds a row for EVERY picture the
## chain needs, each the picture the chain draws now at four times the size (every pixel a 4 x 4 block, `Image.INTERPOLATE_NEAREST`), so a run on `hires` must draw exactly what a run on the pack under it draws, from four times the pixels. The few pictures the tests need to tell
## apart by pixel are redrawn in both: `NINE_KEY` is a nine-patch (nine flat 4 x 4 blocks of 12 x 12, `NINE_SLICE` wide), `TILE_KEY` the atlas of the first zone (every tile of its own colour with a mark at the same place in each) and `TILE_CURRENTS_KEY` its currents.
##
## Teaches: a high-resolution pack made from the one under it, so that "the same picture at four times the size" is a fact of the files and not of a test's eye.

const SCALE := 4
const NINE_KEY := "ui_picture/ui_1195"
const NINE_SLICE := 4
const TILE_KEY := "tile/zone0_tiles"
const TILE_CURRENTS_KEY := "tile/currents"
## The backgrounds the pack redraws besides the pictures the chain needs.
const BACKGROUNDS: Array[String] = ["background/bg_s00_00", "background/bg_s00_01"]
const TILE := 16
## Where the mark is in every tile of the atlas (a 2 x 2 white square), so a tile cut one pixel off shows.
const MARK := Rect2i(3, 5, 2, 2)

var plain: PackShelf
var hires: PackShelf


func _init() -> void:
	var redrawn := {NINE_KEY: nine_image(), TILE_KEY: atlas_image(Color.RED), TILE_CURRENTS_KEY: atlas_image(Color.BLUE)}
	plain = PackShelf.new()
	hires = PackShelf.new()
	hires.set_picture_scale(SCALE)
	var rows := {}
	var plain_rows := {}
	var written := {}                                                                          # (the file a picture comes from -> the file it is written to: pictures many keys share are written once)
	var keys := PictureScale.needed(Packs.chain())
	for key in BACKGROUNDS:                                                                    # (the sectors' backgrounds are no need of the chain's, and are drawn all the same: two of them, the rest would be most of the pixels of the pack)
		if not keys.has(key):
			keys.append(key)
	for key: String in redrawn:
		if not keys.has(key):
			keys.append(key)
	for key in keys:
		var image: Image = redrawn[key] if redrawn.has(key) else _image_of(key)
		if image == null:
			continue
		var source := key if redrawn.has(key) else String(Pictures.resolve(key).get_meta(Pack.SOURCE_META, key))
		if not written.has(source):
			written[source] = "art/p%d.png" % written.size()
			var big := image.duplicate() as Image
			big.resize(image.get_width() * SCALE, image.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
			hires.write_bytes(written[source], big.save_png_to_buffer())
		rows[key] = written[source]
		if redrawn.has(key):
			plain_rows[key] = "art/%s.png" % key.replace("/", "_")
			plain.write_bytes(plain_rows[key], image.save_png_to_buffer())
	hires.write_json(PictureTable.FILE, {"format": PictureTable.FORMAT, "pictures": rows})
	plain.write_json(PictureTable.FILE, {"format": PictureTable.FORMAT, "pictures": plain_rows})


## The picture the chain in use draws for `key`, as a plain RGBA image (no `ScaledTexture`: the chain is scale 1 when this is made), or null.
static func _image_of(key: String) -> Image:
	var texture := Pictures.resolve(key)
	var image := texture.get_image() if texture != null else null
	if image == null:
		return null
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


## The 12 x 12 nine-patch: corners red, green, blue, yellow; edges cyan, magenta, orange, grey; the middle white (flat blocks, so a stretched part is its block's colour).
static func nine_image() -> Image:
	var colors := [Color.RED, Color.CYAN, Color.GREEN, Color.MAGENTA, Color.WHITE, Color.ORANGE, Color.BLUE, Color.GRAY, Color.YELLOW]
	var image := Image.create(NINE_SLICE * 3, NINE_SLICE * 3, false, Image.FORMAT_RGBA8)
	for row in 3:
		for column in 3:
			image.fill_rect(Rect2i(column * NINE_SLICE, row * NINE_SLICE, NINE_SLICE, NINE_SLICE), colors[row * 3 + column])
	return image


## The color of the nine-patch's block at `column`, `row` (0 to 2).
static func nine_color(column: int, row: int) -> Color:
	return nine_image().get_pixel(column * NINE_SLICE, row * NINE_SLICE)


## An atlas of 8 x 8 tiles of 16 x 16 pixels: each a color of its own from `tint` with the white `MARK` in it.
static func atlas_image(tint: Color) -> Image:
	var image := Image.create(TILE * 8, TILE * 8, false, Image.FORMAT_RGBA8)
	for row in 8:
		for column in 8:
			image.fill_rect(Rect2i(column * TILE, row * TILE, TILE, TILE), tint.lerp(Color(0.2, 0.2, 0.2), (row * 8 + column) / 80.0))
			image.fill_rect(Rect2i(Vector2i(column * TILE, row * TILE) + MARK.position, MARK.size), Color.WHITE)
	return image


## Chooses `plain` (scale 1) as the chosen pack.
func mount_plain() -> void:
	plain.mount()


## Chooses `hires`: the run draws at scale `SCALE` (checked by the tests that use it).
func mount_hires() -> void:
	hires.mount()


## Chooses the command-line pack again and deletes both packs.
func remove() -> void:
	hires.remove()
	plain.remove()
