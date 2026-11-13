class_name PicturesShelf
extends RefCounted
## Two scratch packs for a test of the picture tables (`Pictures`): a COMPLETE pack, and a pack laid over it, whose picture files are called nothing like the keys they are for (`art/zz1.png`, `art/zz2.png`), so a test that finds the right picture proves the table did it and not a
## file name. The complete pack holds every kind of row (a file, a scaled file, an alias, an alias of an alias, two aliases that go round in a circle, an alias to a key nobody has, a row whose file is missing); the pack over it redraws one picture, so its aliases follow, and has a row of its
## own that does not resolve.
##
##     keys of `base`     file or row                                            color
##     ui_picture/title_sky     art/zz1.png                                      RED
##     ui_picture/coral_dawn    alias of ui_picture/title_sky
##     ui_picture/coral_noon    alias of ui_picture/coral_dawn
##     frame/sub_00             art/hi@4x.png, scale 4 (16 x 16 file, 4 x 4 drawn) YELLOW
##     frame/eel_swim_0         art/zz2.png                                      GREEN
##     problem_art/log_scan_0   art/zz3.png                                      BLUE
##     ui_picture/loop_a, loop_b   aliases of each other
##     ui_picture/dangling      alias of ui_picture/nothing_here
##     ui_picture/lost          art/gone.png (not in the pack)
##     tile/wall_sheet          art/sheet.png, 32 x 16: two 16 x 16 tiles, RED then GREEN
##     deco/half_clear          art/half.png, 8 x 4: the left half transparent, the right half RED
## `over` (laid over `base`): ui_picture/title_sky is art/other.png (WHITE), frame/eel_swim_0 names art/missing_too.png (not in the pack), deco/coral_fan_cyan is art/zz4.png (MAGENTA).
##
## Teaches: a scratch pack as a fixture of a lookup (`PackShelf`), and a table whose files are named at random.

const RED := Color(1, 0, 0)
const GREEN := Color(0, 1, 0)
const BLUE := Color(0, 0, 1)
const YELLOW := Color(1, 1, 0)
const WHITE := Color(1, 1, 1)
const MAGENTA := Color(1, 0, 1)

var base: PackShelf
var over: PackShelf


func _init() -> void:
	base = PackShelf.new()
	base.write_json("pack.json", {"id": String(base.id), "title": "Pictures base", "version": "1"})            # (complete: no `base`)
	base.add_picture("art/zz1.png", RED)
	base.add_picture("art/zz2.png", GREEN)
	base.add_picture("art/zz3.png", BLUE)
	base.add_picture("art/hi@4x.png", YELLOW, Vector2i(16, 16))
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
		"frame/sub_00": {"file": "art/hi@4x.png", "scale": 4},
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


## The pixel of a texture's image, to tell the pictures apart by color.
static func color_of(texture: Texture2D) -> Color:
	var image := texture.get_image()
	return image.get_pixel(image.get_width() / 2, image.get_height() / 2)


## Chooses the command-line pack again and deletes both packs.
func remove() -> void:
	over.remove()
	base.remove()
