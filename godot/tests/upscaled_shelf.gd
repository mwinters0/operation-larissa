class_name UpscaledShelf
extends RefCounted
## Two scratch packs for a test of every consumer of a picture of scale 4 (`test_picture_scale_consumers.gd`, `test_picture_scale_render.gd`): `plain` redraws a few pictures at scale 1, `upscaled` (picture scale `SCALE`, laid over the pack in use) holds a row for EVERY row of the dev pack (so for every picture the
## chain needs), each the picture the chain draws now at four times the size (every pixel a 4 x 4 block, `Image.INTERPOLATE_NEAREST`), so a run on `upscaled` must draw exactly what a run on the pack under it draws, from four times the pixels. The few pictures the tests need to tell
## apart by pixel are redrawn in both: `NINE_KEY` is a nine-patch (nine flat 4 x 4 blocks of 12 x 12, `NINE_SLICE` wide), `TILE_KEY` the atlas of the first zone (every tile of its own colour with a mark at the same place in each) and `TILE_CURRENTS_KEY` its currents.
##
## Teaches: a high-resolution pack made from the one under it, so that "the same picture at four times the size" is a fact of the files and not of a test's eye.

const SCALE := 4
const NINE_KEY := "ui_picture/ui_1195"
const NINE_SLICE := 4
const TILE_KEY := "tile/zone0_tiles"
const TILE_CURRENTS_KEY := "tile/currents"
## The backgrounds the pack redraws from the pictures of the chain (the others of the chain are one small file).
const BACKGROUNDS: Array[String] = ["background/bg_s00_00", "background/bg_s00_01"]
const TILE := 16
## Where the mark is in every tile of the atlas (a 2 x 2 white square), so a tile cut one pixel off shows.
const MARK := Rect2i(3, 5, 2, 2)

var plain: PackShelf
var upscaled: PackShelf


func _init() -> void:
	var redrawn := {NINE_KEY: nine_image(), TILE_KEY: atlas_image(Color.RED), TILE_CURRENTS_KEY: atlas_image(Color.BLUE)}
	plain = PackShelf.new()
	upscaled = PackShelf.new()
	var rows := {}
	var plain_rows := {}
	var written := {}                                                                          # (the file a picture comes from -> the file it is written to: pictures many keys share are written once)
	var filler_keys: Array[String] = []
	var keys := PackShelf.dev_picture_keys()                                                   # (every row of the dev pack, so the pack covers whatever the chain needs and scale 1 would draw, and the keys the tests redraw)
	for key: String in redrawn:
		if not keys.has(key):
			keys.append(key)
	for key in keys:
		if key.begins_with("background/") and not BACKGROUNDS.has(key):                       # (a background the tests do not look at pixel by pixel: one small file stands for it, so the pack covers without four times the pixels of every screen)
			filler_keys.append(key)
			continue
		var image: Image = redrawn[key] if redrawn.has(key) else _image_of(key)
		if image == null:
			continue
		var source := key if redrawn.has(key) else String(Pictures.resolve(key).get_meta(Pack.SOURCE_META, key))
		if not written.has(source):
			written[source] = "art/p%d.png" % written.size()
			var big := image.duplicate() as Image
			big.resize(image.get_width() * SCALE, image.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
			upscaled.write_bytes(written[source], big.save_png_to_buffer())
		rows[key] = written[source]
		if redrawn.has(key):
			plain_rows[key] = "art/%s.png" % key.replace("/", "_")
			plain.write_bytes(plain_rows[key], image.save_png_to_buffer())
	upscaled.write_json(PictureTable.FILE, {"format": PictureTable.FORMAT, "pictures": rows})
	upscaled.add_scaled_rows(SCALE, filler_keys, Color(0, 0, 0, 0), Vector2i(SCALE * 640, SCALE * 400))
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


## Chooses `upscaled`: the run draws at scale `SCALE` (checked by the tests that use it).
func mount_upscaled() -> void:
	upscaled.mount()


## Chooses the command-line pack again and deletes both packs.
func remove() -> void:
	upscaled.remove()
	plain.remove()
