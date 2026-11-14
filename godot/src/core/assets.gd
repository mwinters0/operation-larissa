class_name Assets
extends RefCounted
## Turns the NAME of a picture into the picture: the one place that knows the keys of the pictures the code asks for.
##
## The rest of the game says what it means (`Assets.ui_picture(&"title_sky")`), never which number or file that is. A name is a picture key
## (`ui_picture/title_sky`, `problem_art/log_scan_0`, `background/bg_s03_07`) and the key is answered by the chain's picture tables
## (`Pictures`: the `pictures.json` of each pack, the top of the chain first). Nothing here knows a file name, a folder or a number of the
## original: which file draws a key is the pack's business, and a key no pack holds is a picture the game does not show (told once, naming the key).
##
## NO SKIN. A skin maps no picture: the pictures are the packs'.
##
## ONE WAY TO HOLD A PICTURE. Every picture handed out here is a `PictureRef` (one per key, kept: the same key is the same object), the way data holds a picture. A screen that keeps one in a node keeps the KEY, so it shows what the chain holds
## now when the chain changes (a pack installed or removed), with nothing to rebuild; a snapshot of a texture would go on showing the pack that was. `holds` says whether a pack of the chain has a picture for a key, for the caller that must
## decide something by it (a screen with no picture behind it, a style that falls back to flat colour). A reference to a key nothing holds draws nothing and says so itself, once per run (`PictureRef`, `Pictures.unheld_line`).
##
## Teaches: a resolver as a seam. Code that needs a picture holds a name, a small static class owns "name -> key -> the chain's texture",
## and a key nothing holds is said once instead of drawing a missing texture without a word.
##
## Kinds of this class and who resolves the others: `ui_picture` and `problem_art` here; `sound` is `SfxCatalog.stream_named`,
## `music` is `MusicCatalog.stream_named`, `voice` is `VoiceIndex.stream_named`, `text` is `Catalog.text`, and the creature
## and decoration pictures are slots of the SpriteFrames sets, whose frames hold their keys (`PictureRef`).
##
## A few pictures are chosen by DATA, which holds their keys (`ClosingCrewScripts.pictures`, `ProblemType.art_keys`, `Campaign.finale_picture`);
## the cutscene timelines hold NAMES. Code never writes a number itself (tests/engine/test_no_asset_numbers.gd checks that).


# --- the interface, story and console pictures (`ui_picture`) ------------------------------------------------

## The picture `picture_name` (a `ui_picture` name), held by its key (nothing is drawn, and the reference says so once, when no pack of the chain holds it).
static func ui_picture(picture_name: StringName) -> PictureRef:
	return picture_by_key("ui_picture/" + picture_name)


# --- the pictures of the math problems (`problem_art`) -----------------------------------------------------------

## The problem-art picture `picture_name`, held by its key (as `ui_picture`).
static func problem_art(picture_name: StringName) -> PictureRef:
	return picture_by_key("problem_art/" + picture_name)


# --- the backgrounds of the screens ------------------------------------------------------------------------

## The picture behind screen `screen` of sector `sector`, held by its key, or null when the screen has none (two of the finale's are plain black, and that is no trouble).
static func background(sector: int, screen: int) -> PictureRef:
	var key := _background_key(sector, screen)
	return picture_by_key(key) if holds(key) else null


## Has screen `screen` of sector `sector` a picture behind it (a picture of the chain for its key)?
static func has_background(sector: int, screen: int) -> bool:
	return holds(_background_key(sector, screen))


## The key of that picture (`background/bg_s03_07`), or "" when the screen has none.
static func background_key(sector: int, screen: int) -> String:
	return _background_key(sector, screen) if has_background(sector, screen) else ""


static func _background_key(sector: int, screen: int) -> String:
	return "background/bg_s%02d_%02d" % [sector, screen]


# --- a picture by its picture key ------------------------------------------------------------------------------------

## key -> the `PictureRef` handed out for it.
static var _refs: Dictionary = {}


## The picture of the picture key `key` (`frame/sub_00`, `background/bg_s03_07`, `deco/coral_fan_cyan`), held by it: the reference shows what the chain's picture tables say now (`Pictures.resolve`, the one resolver), draws nothing for a key no pack holds
## (told once per run, by the reference). What a mod's draw list names is held here (`ModDraw`), so a mod sees what `OriginalPresenter` would show, and holds no picture itself.
static func picture_by_key(key: String) -> PictureRef:
	if not _refs.has(key):
		_refs[key] = PictureRef.of(key)
	return _refs[key]


## Does a pack of the chain hold a picture for `key`? Said nowhere (the caller that decides by it says what it does instead).
static func holds(key: String) -> bool:
	return Pictures.has(key)
