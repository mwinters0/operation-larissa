class_name PicturesShelf
extends RefCounted
## Two scratch packs for a test of the picture tables (`Pictures`): a COMPLETE pack, and a pack laid over it, whose picture files are called nothing like the keys they are for (`art/zz1.png`, `art/zz2.png`), so a test that finds the right picture proves the table did it and not a
## file name. The complete pack holds every kind of row (a file, an alias, an alias of an alias, two aliases that go round in a circle, an alias to a key nobody has, a row whose file is missing); the pack over it redraws one picture, so its aliases follow, and has a row of its
## own that does not resolve.
##
##     keys of `base`     file or row                                            color
##     ui_picture/title_sky     art/zz1.png                                      RED
##     ui_picture/coral_dawn    alias of ui_picture/title_sky
##     ui_picture/coral_noon    alias of ui_picture/coral_dawn
##     frame/sub_00             art/zz5.png                                      YELLOW
##     frame/eel_swim_0         art/zz2.png                                      GREEN
##     problem_art/log_scan_0   art/zz3.png                                      BLUE
##     ui_picture/loop_a, loop_b   aliases of each other
##     ui_picture/dangling      alias of ui_picture/nothing_here
##     ui_picture/lost          art/gone.png (not in the pack)
##     tile/wall_sheet          art/sheet.png, 32 x 16: two 16 x 16 tiles, RED then GREEN
##     deco/half_clear          art/half.png, 8 x 4: the left half transparent, the right half RED
## `over` (laid over `base`): ui_picture/title_sky is art/other.png (WHITE), frame/eel_swim_0 names art/missing_too.png (not in the pack), deco/coral_fan_cyan is art/zz4.png (MAGENTA).
## `hires` (made by `mount_hires`, laid over `base`): a pack of picture scale 4 that holds a row for every picture the chain needs and holds and for every file row of `base` but one (16 x 16 files, 4 x 4 drawn): frame/sub_00 is YELLOW, every other key CYAN;
## `ui_picture/four_x_alias` is an alias of `ui_picture/lost_in_4x`, a key only `base` has a row for.
##
## Teaches: a scratch pack as a fixture of a lookup (`PackShelf`), and a table whose files are named at random.

const RED := Color(1, 0, 0)
const GREEN := Color(0, 1, 0)
const BLUE := Color(0, 0, 1)
const YELLOW := Color(1, 1, 0)
const WHITE := Color(1, 1, 1)
const MAGENTA := Color(1, 0, 1)
const CYAN := Color(0, 1, 1)

var base: PackShelf
var over: PackShelf
var hires: PackShelf


func _init() -> void:
	base = PackShelf.new()
	base.write_json("pack.json", {"id": String(base.id), "title": "Pictures base", "version": "1"})            # (complete: no `base`)
	base.add_picture("art/zz1.png", RED)
	base.add_picture("art/zz2.png", GREEN)
	base.add_picture("art/zz3.png", BLUE)
	base.add_picture("art/zz5.png", YELLOW)
	var sheet := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	sheet.fill_rect(Rect2i(0, 0, 16, 16), RED)
	sheet.fill_rect(Rect2i(16, 0, 16, 16), GREEN)
	base.write_bytes("art/sheet.png", sheet.save_png_to_buffer())
	var half := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	half.fill_rect(Rect2i(4, 0, 4, 4), RED)
	base.write_bytes("art/half.png", half.save_png_to_buffer())
	base.write_json(PictureTable.FILE, {"format": 1, "pictures": {
		"ui_picture/title_sky": "art/zz1.png",
		"ui_picture/coral_dawn": {"alias": "ui_picture/title_sky"},
		"ui_picture/coral_noon": {"alias": "ui_picture/coral_dawn"},
		"frame/sub_00": "art/zz5.png",
		"ui_picture/lost_in_4x": "art/zz2.png",
		"frame/eel_swim_0": "art/zz2.png",
		"problem_art/log_scan_0": "art/zz3.png",
		"ui_picture/loop_a": {"alias": "ui_picture/loop_b"},
		"ui_picture/loop_b": {"alias": "ui_picture/loop_a"},
		"ui_picture/dangling": {"alias": "ui_picture/nothing_here"},
		"ui_picture/lost": "art/gone.png",
		"tile/wall_sheet": "art/sheet.png",
		"deco/half_clear": "art/half.png",
	}})
	over = PackShelf.new(&"", base.id)
	over.add_picture("art/other.png", WHITE)
	over.add_picture("art/zz4.png", MAGENTA)
	over.write_json(PictureTable.FILE, {"format": 1, "pictures": {
		"ui_picture/title_sky": "art/other.png",
		"frame/eel_swim_0": "art/missing_too.png",
		"deco/coral_fan_cyan": "art/zz4.png",
	}})


## The chain is the complete pack alone.
func mount_base() -> void:
	base.mount()


## The chain is `over` on `base`.
func mount_over() -> void:
	over.mount()


## The chain is `hires` on `base`: a pack of picture scale 4 that holds a row for every picture the chain needs, so the run draws at scale 4. Made the first time.
func mount_hires() -> void:
	base.mount()
	if hires == null:
		hires = PackShelf.new(&"", base.id)
		hires.set_picture_scale(4)
		hires.add_picture("art/hi_sub.png", YELLOW, Vector2i(16, 16))
		hires.add_picture("art/hi_all.png", CYAN, Vector2i(16, 16))
		var rows := {}
		for key in PictureScale.needed(Packs.chain(), PackNeeds.picture_keys(Packs.chain())):
			rows[key] = "art/hi_all.png"
		for key: String in Packs.pack(base.id).picture_table().files:                                       # (and every picture the base draws, but `lost_in_4x`)
			rows[key] = "art/hi_all.png"
		rows.erase("ui_picture/lost_in_4x")
		rows["frame/sub_00"] = "art/hi_sub.png"
		rows["ui_picture/four_x_alias"] = {"alias": "ui_picture/lost_in_4x"}
		hires.write_json(PictureTable.FILE, {"format": PictureTable.FORMAT, "pictures": rows})
	hires.mount()


## The pixel of a texture's image, to tell the pictures apart by color.
static func color_of(texture: Texture2D) -> Color:
	var image := texture.get_image()
	return image.get_pixel(image.get_width() / 2, image.get_height() / 2)


## Chooses the command-line pack again and deletes both packs.
func remove() -> void:
	if hires != null:
		hires.remove()
	over.remove()
	base.remove()
