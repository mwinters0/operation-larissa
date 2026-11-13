class_name Assets
extends RefCounted
## Turns the NAME of a picture into the picture: the one place that knows the keys of the pictures the code asks for.
##
## The rest of the game says what it means (`Assets.ui_picture(&"title_sky")`), never which number or file that is. A name is a skin key
## (`ui_picture/title_sky`, `problem_art/log_scan_0`, `background/bg_s03_07`) and the key is answered by the chain's picture tables
## (`Pictures`: the `pictures.json` of each pack, the top of the chain first). Nothing here knows a file name, a folder or a number of the
## original: which file draws a key is the pack's business, and a key no pack holds is a picture the game does not show (told once, naming the key).
##
## NO SKIN. A skin maps no picture: the pictures are the packs'.
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

## The texture of the picture `picture_name` (a `ui_picture` name), or null when no pack of the chain holds it (told once).
static func ui_picture(picture_name: StringName) -> Texture2D:
	return _named("ui_picture/" + picture_name)


# --- the pictures of the math problems (`problem_art`) -----------------------------------------------------------

## The texture of the problem-art picture `picture_name`, or null when no pack of the chain holds it (told once).
static func problem_art(picture_name: StringName) -> Texture2D:
	return _named("problem_art/" + picture_name)


# --- the backgrounds of the screens ------------------------------------------------------------------------

## The picture behind screen `screen` of sector `sector`, or null when the screen has none (two of the finale's are plain black).
static func background(sector: int, screen: int) -> Texture2D:
	return picture_by_key(_background_key(sector, screen))


## Has screen `screen` of sector `sector` a picture behind it (a picture of the chain for its key)?
static func has_background(sector: int, screen: int) -> bool:
	return picture_by_key(_background_key(sector, screen)) != null


## The key of that picture (`background/bg_s03_07`), or "" when the screen has none.
static func background_key(sector: int, screen: int) -> String:
	return _background_key(sector, screen) if has_background(sector, screen) else ""


static func _background_key(sector: int, screen: int) -> String:
	return "background/bg_s%02d_%02d" % [sector, screen]


## Forget what was read from the chain's files (`Catalog.packs_changed`: another pack is in use).
static func forget_folders() -> void:
	Pictures.forget()


# --- a picture by its skin key ------------------------------------------------------------------------------------

## The picture of the skin key `key` (`frame/sub_00`, `background/bg_s03_07`, `deco/coral_fan_cyan`): what the chain's picture tables say (`Pictures.resolve`, the one resolver; a `PictureRef` asks it too);
## null for a key no pack holds, said nowhere (a caller that needs the picture says so: `ui_picture`, `problem_art`). What a mod's draw list names is resolved here (`ModDraw`), so a mod sees what `OriginalPresenter` would show, and holds no picture itself.
static func picture_by_key(key: String) -> Texture2D:
	return Pictures.resolve(key)


## The picture of `key` that the game asks for by name: null, and a warning naming the key (once per run), when no pack holds it.
static func _named(key: String) -> Texture2D:
	var held := picture_by_key(key)
	if held == null:
		TroubleLog.session.tell(Pictures.unheld_line(key))
	return held
