class_name Pack
extends RefCounted
## One pack: a folder of content with a manifest, one link of the chain the game is made of.
##
## A pack is a ROOT plus the relative paths under it. `Packs` keeps the chain (the chosen pack, the pack its manifest names as its `base`, and so on) and
## the lookups (`Catalog`, `Assets`, the sound resolvers) ask `Packs`, which asks each pack in turn. A pack with no `base` is COMPLETE: it holds everything the
## game needs (`legacy`, `dev`), and a pack with a `base` is laid over another. Whether a pack is a folder of `.tres` files, pictures and sounds laid out the way
## the importer writes them (`assets/`, `data/`, `midi/`) or is in the data form is a matter of where its folder is (`trusted`); the layout is as below.
##
## THE LAYOUT OF A PACK IN THE DATA FORM (every part is optional; docs: docs/engine/PACKS.md)
##     pack.json                        the manifest: id, title, version (and author, description, format, `base`: the id of the pack this one is laid over, `mod`: see below)
##     campaigns/<id>.json              a `Campaign` (ResourceJson: the fields of the .tres, defaults left out)
##     sectors/sector_NN/sector_NN.json a `SectorData` (SectorJson: header, pieces, creatures, screens)
##     sectors/sector_NN/sector_NN.foe  its creature script, the same text as in the base game
##     texts.json                       {"text name": "the words"}: new texts, or new words for a text of the original
##     voice_cues.json                  {"groups": {"group name": ["voice name", ...]}}: the speech groups a campaign names
##     pictures/<kind>/<name>.png       a picture by its skin key (`ui_picture/title_sky`, `background/bg_s40_00`, `frame/...`)
##     audio/sound|music|voice/<name>.ogg   a sound, song or speech clip by its registry name, or a new name
##     audio/lengths.json               {"voice": {"name": ticks}}: lengths the pack states for its clips (else they are measured, `ClipLengths`)
##     data/problems/problem_type_NN.json   a problem type (ResourceJson)
##     <entry>.sgd                      the script of a MOD PACK (the manifest's `mod`, `ModSpec`): SafeGDScript, run in a Sandbox with restrictions by `ModLoader`
## A pack that holds no zones, trigger table or tile set names the pack that has them as its `base`; a complete pack in the data form (`PackExport.complete`
## writes one) holds `data/zones.json` for `data/zones.tres` and so on for every kind (`ResourceJson`), the sectors and campaigns in the layout above, `assets/`,
## `midi/` and `rules/` as the importer lays them out.
##
## FOLDER OR FILE. A pack is a folder, which editors can write to, or a pack file (`<id>.larissa`), which is read-only and read where it lies: its `root` is the path of the file, `path_of(rel)` is a
## virtual path under it (`user://packs/legacy.larissa/data/zones.json`, which names the file and exists for no file system), and `has`, `read_bytes`, `files_in` and the rest answer from the
## file's own index (`PackArchive`), the one owner of what the file holds. Code that reads a pack's file asks the pack (`has`, `read_bytes`, `size_of`, `files_in`), never the file system with `path_of`.
##
## TRUSTED OR NOT. A pack whose folder is inside the project (`res://packs/<id>`, `trusted`; a pack file never is) is as much the project's as its code: its `.tres` files are
## loaded with `ResourceLoader` (the authoring form: editors, the Inspector and uids work on them). Every other pack (`user://packs/<id>`, anything
## installed) is read in the DATA FORM only: JSON, `.foe` text, PNG, OGG, WAV, MIDI, with `FileAccess` and the `load_from_buffer` of `Image` and the
## audio streams, and NEVER with `ResourceLoader` (a `.tres` can carry a script), so installing one from anyone runs nothing but the creature VM and, in a mod pack, a sandboxed script (`ModLoader`) that bounds what it can reach. The
## data form of `X.tres` is `X.json` at the same relative path (`ResourceJson`, `EngineJson`). `resource`, `texture` and `stream` are THE door: the one
## place a file of a pack becomes an object, and `trusted` decides how. There is no other kind of pack: trust is the folder.
##
## A MOD PACK is a pack whose manifest has a `mod` entry. Its `.sgd` script is the only code a pack may carry and it is never loaded as a script of the game: `ModLoader` compiles it into a
## Sandbox with restrictions, trusted folder or not. So a pack that is not trusted may hold a `.sgd` file and none of `RESOURCE_EXTENSIONS`, and it needs the godot-sandbox extension: a build
## without it refuses the manifest (`errors`).
##
## Teaches: a root plus a relative path as the whole idea of a mod folder; and why trust is a property of HOW a file is read, not of what it is
## called: one door, and the same file (`data/zones.tres`) is a resource for the project's own pack and a JSON description for a stranger's.

const MANIFEST := "pack.json"
## A pack as ONE file, to hand round or to ship next to a game: `<id>.larissa`, a zip archive of the pack's folder (`PackExport` with `archive` makes
## it). It is read in place, never extracted (`PackArchive`; `is_archive`). Its own extension says what it is: a file manager, the pack screen's file picker
## and a web server tell a pack from any other zip.
const FILE_EXTENSION := "larissa"
## The meta a picture or sound read from a pack's file carries: the full path of the file (a decoded texture has no `resource_path`). `Packs.source_of`.
const SOURCE_META := &"pack_file"
## The version of the manifest and layout this code reads. A pack that says a higher one is refused.
const FORMAT := 1
const ID_PATTERN := "^[a-z][a-z0-9_]{0,31}$"
## What a pack that is not trusted may never hold: these are the formats the engine runs.
const RESOURCE_EXTENSIONS: Array[String] = ["tres", "res", "tscn", "scn", "gd", "gdc", "cs", "gdextension", "dll", "so", "dylib", "elf", "pck", "wasm"]

var id: StringName = &""
var title: String = ""
var version: String = ""
var author: String = ""
var description: String = ""
## The id of the pack this one is laid over (the manifest's `"base"`), or `&""` for a complete pack. `Packs` follows the links.
var base: StringName = &""
var format: int = FORMAT
## The folder of the pack, without a trailing slash: `res://packs/<id>` or `user://packs/<id>`; or the pack file: `user://packs/<id>.larissa`.
var root: String = ""
## Is the folder inside the project (`res://packs/<id>`)? Then its resources are loaded with `ResourceLoader`; else only its data form is read (see the header). Never true for a pack file.
var trusted := false
## The manifest's `mod` entry, or null for a pack that is not a mod pack (`ModSpec`).
var mod: ModSpec = null
## What is wrong with the manifest (empty for a pack that can be mounted). `Pack.open` fills it; `mount` refuses a pack that has some.
var errors: Array[String] = []

## rel -> Texture2D / AudioStream (a missing file is kept as null: the folder is asked once).
var _textures: Dictionary = {}
var _streams: Dictionary = {}
## rel -> the resource a data-form file made (a trusted pack's are cached by `ResourceLoader`).
var _resources: Dictionary = {}
## kind -> {clip name -> ticks}: the clips' lengths, measured from the files / stated by `audio/lengths.json`. Filled by `measure_clips`.
var _measured: Dictionary = {}
var _stated: Dictionary = {}
var _clips_measured := false
## The open pack file, or null for a folder. The one owner of the list of files a pack file holds.
var _archive: PackArchive = null


## The pack at `location`, a folder or a pack file (`<id>.larissa`): reads its `pack.json`. Never null; check `errors`.
static func open(location: String) -> Pack:
	var pack := Pack.new()
	pack.root = location.trim_suffix("/")
	if pack.root.get_extension() == FILE_EXTENSION and not DirAccess.dir_exists_absolute(pack.root):
		pack._archive = PackArchive.open(pack.root)
		if not pack._archive.is_valid():
			pack.errors.append_array(pack._archive.errors)
			return pack
	else:
		pack.trusted = pack.root.begins_with(Packs.PROJECT_PACKS_DIR + "/")
	var text := pack.read_text(MANIFEST)
	pack.close()                                         # (a pack file is held open only by a pack that is read from)
	if text.is_empty():
		pack.errors.append("no %s in %s" % [MANIFEST, location])
		return pack
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		pack.errors.append("%s is not a JSON object" % MANIFEST)
		return pack
	pack._read_manifest(parsed)
	return pack


## The manifest as a Dictionary (what `open` reads): the fields every pack must have, and the optional ones.
func manifest() -> Dictionary:
	var data := {"format": format, "id": String(id), "title": title, "version": version}
	if not author.is_empty():
		data["author"] = author
	if not description.is_empty():
		data["description"] = description
	if base != &"":
		data["base"] = String(base)
	if mod != null:
		data["mod"] = mod.to_dict()
	return data


## (A key this code does not know, such as `"tier"`, is left alone; `mod` is read by `ModSpec`, which names what is wrong with it.)
func _read_manifest(data: Dictionary) -> void:
	for key in ["id", "title", "version"]:
		if not data.has(key):
			errors.append("%s has no \"%s\"" % [MANIFEST, key])
	for key in ["id", "title", "version", "author", "description", "base"]:
		if data.has(key) and not data[key] is String:
			errors.append("\"%s\" must be a string" % key)
	if data.has("format") and not (data["format"] is float or data["format"] is int):
		errors.append("\"format\" must be a number")
	if not errors.is_empty():
		return
	id = StringName(data["id"])
	title = data["title"]
	version = data["version"]
	author = data.get("author", "")
	description = data.get("description", "")
	format = int(data.get("format", FORMAT))
	base = StringName(data.get("base", ""))
	if RegEx.create_from_string(ID_PATTERN).search(String(id)) == null:
		errors.append("the id '%s' is not a lowercase word (letters, digits and _, starting with a letter, at most 32)" % id)
	if base != &"" and RegEx.create_from_string(ID_PATTERN).search(String(base)) == null:
		errors.append("the base '%s' is not a pack id (a lowercase word)" % base)
	if base == id:
		errors.append("the pack '%s' cannot be its own base" % id)
	if title.strip_edges().is_empty():
		errors.append("the title is empty")
	if version.strip_edges().is_empty():
		errors.append("the version is empty")
	if format < 1 or format > FORMAT:
		errors.append("format %d: this game reads packs of format 1 to %d" % [format, FORMAT])
	if data.has("mod"):
		mod = ModSpec.parse(data["mod"], errors)
		if mod != null and mod.has_entry() and not ModLoader.sandbox_available():
			errors.append(ModLoader.missing_extension_text())


func is_valid() -> bool:
	return errors.is_empty()


# --- paths and files ---------------------------------------------------------------------------------------------

## Is `rel` a path that stays inside the pack: relative, no `..`, no drive or scheme, no backslash? Everything else is refused before a
## file is touched, so a manifest or a JSON file cannot name a file outside the pack.
static func is_safe(rel: String) -> bool:
	return not rel.is_empty() and not rel.begins_with("/") and not rel.contains("..") and not rel.contains(":") \
			and not rel.contains("\\") and not rel.contains("//")


## The full path of `rel` under the root ("" for an unsafe one).
func path_of(rel: String) -> String:
	return "%s/%s" % [root, rel] if is_safe(rel) else ""


func has(rel: String) -> bool:
	if not is_safe(rel):
		return false
	if _archive != null:
		return _archive.has(rel)
	return FileAccess.file_exists(path_of(rel)) or (trusted and ResourceLoader.exists(path_of(rel)))


## Does the pack have the folder `rel`?
func has_folder(rel: String) -> bool:
	if not is_safe(rel):
		return false
	return _archive.has_folder(rel) if _archive != null else DirAccess.dir_exists_absolute(path_of(rel))


## The size of the file `rel` in bytes, or -1 when the pack has no such file (an imported resource that is only known to `ResourceLoader` has none either).
func size_of(rel: String) -> int:
	if not is_safe(rel):
		return -1
	if _archive != null:
		return _archive.size_of(rel)
	var file := FileAccess.open(path_of(rel), FileAccess.READ)
	return file.get_length() if file != null else -1


## When the file `rel` was last changed (seconds since 1970; 0 when unknown). For a pack file that is when the pack file was: its files change together.
func modified_time(rel: String) -> int:
	if not is_safe(rel):
		return 0
	return FileAccess.get_modified_time(root if _archive != null else path_of(rel))


## Is the pack one file (`<id>.larissa`, read in place and read-only) rather than a folder?
func is_archive() -> bool:
	return _archive != null


## Lets go of the pack file so that it can be replaced or deleted (a folder holds nothing open). Reading it again opens it again.
func close() -> void:
	if _archive != null:
		_archive.close()


## The data form of the resource file `rel`: `data/zones.tres` is `data/zones.json`. "" for a file that is not a resource of the game (`.tres`).
static func data_rel(rel: String) -> String:
	return rel.get_basename() + ".json" if rel.get_extension() == "tres" else ""


## The authoring file of the data form `rel` (`data/zones.json` is `data/zones.tres`): `data_rel` the other way.
static func data_rel_to_authoring(rel: String) -> String:
	return rel.get_basename() + ".tres" if rel.get_extension() == "json" else ""


## Would the door answer for `rel` (`resource`, `texture`, `stream`)? A resource file (`RESOURCE_EXTENSIONS`: a `.tres` or a script could run code) is
## answered by a trusted pack that has it, and by any pack that has its data form (`data_rel`); any other file when the pack has it. `Packs.holder` asks this.
func provides(rel: String) -> bool:
	if not is_safe(rel):
		return false
	if RESOURCE_EXTENSIONS.has(rel.get_extension()):
		return (trusted and has(rel)) or has(data_rel(rel))
	return has(rel)


## The text of a file, or "" (a missing file, an unsafe path).
func read_text(rel: String) -> String:
	if not has(rel):
		return ""
	return _archive.read(rel).get_string_from_utf8() if _archive != null else FileAccess.get_file_as_string(path_of(rel))


## The bytes of a file; empty when there is none.
func read_bytes(rel: String) -> PackedByteArray:
	if not has(rel):
		return PackedByteArray()
	return _archive.read(rel) if _archive != null else FileAccess.get_file_as_bytes(path_of(rel))


## A JSON file parsed, or null for a missing file or text that is not JSON (with a warning that says which).
func read_json(rel: String) -> Variant:
	if not has(rel):
		return null
	var parser := JSON.new()
	if parser.parse(read_text(rel)) != OK:
		push_warning("Pack %s: %s line %d: %s" % [id, rel, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data


## The files of the folder `rel_dir` (names only, sorted), optionally only those ending `.extension`.
func files_in(rel_dir: String, extension: String = "") -> PackedStringArray:
	var found := PackedStringArray()
	if not is_safe(rel_dir) or not has_folder(rel_dir):
		return found
	for file in (_archive.files_in(rel_dir) if _archive != null else DirAccess.get_files_at(path_of(rel_dir))):
		if extension.is_empty() or file.get_extension() == extension:
			found.append(file)
	found.sort()
	return found


func folders_in(rel_dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not is_safe(rel_dir) or not has_folder(rel_dir):
		return found
	found = _archive.folders_in(rel_dir) if _archive != null else DirAccess.get_directories_at(path_of(rel_dir))
	found.sort()
	return found


## The picture file `rel` (PNG) as a texture, or null. A trusted pack's imported picture is loaded (its import settings hold); else the PNG is
## decoded from the file's bytes, so no import and no `ResourceLoader` is involved. Either carries its file (`SOURCE_META`).
func texture(rel: String) -> Texture2D:
	if not _textures.has(rel):
		var loaded: Texture2D = null
		if trusted and rel.get_extension() == "png" and ResourceLoader.exists(path_of(rel)):
			loaded = load(path_of(rel)) as Texture2D
		elif has(rel):
			var image := Image.new()
			if image.load_png_from_buffer(read_bytes(rel)) == OK and not image.is_empty():
				loaded = ImageTexture.create_from_image(image)
			else:
				push_warning("Pack %s: %s is not a PNG picture" % [id, rel])
		if loaded != null:
			loaded.set_meta(SOURCE_META, path_of(rel))
		_textures[rel] = loaded
	return _textures[rel]


## The sound file `rel` (`.ogg` or `.wav`) as a stream, or null; read once and kept. A trusted pack's imported file is loaded (its import settings hold);
## else the bytes are decoded (`load_from_buffer`), so no import and no `ResourceLoader` is involved. Either carries its file (`SOURCE_META`).
func stream(rel: String) -> AudioStream:
	var kind := rel.get_extension()
	if kind != "ogg" and kind != "wav":
		return null
	if not _streams.has(rel):
		var loaded: AudioStream = null
		if trusted and ResourceLoader.exists(path_of(rel)):
			loaded = load(path_of(rel)) as AudioStream
		elif has(rel):
			var bytes := read_bytes(rel)
			loaded = AudioStreamOggVorbis.load_from_buffer(bytes) if kind == "ogg" else AudioStreamWAV.load_from_buffer(bytes)
			if loaded == null:
				push_warning("Pack %s: %s is not %s file" % [id, rel, "an OGG Vorbis" if kind == "ogg" else "a WAV"])
		if loaded != null:
			loaded.set_meta(SOURCE_META, path_of(rel))
		_streams[rel] = loaded
	return _streams[rel]


## THE DOOR for a resource. `rel` is the AUTHORING path (`data/zones.tres`). A trusted pack that has the file loads it; else the data form of it
## (`data_rel`, ResourceJson) is read. Either is made once and kept until `forget`. Null for a file the pack lacks in a form it may read; an untrusted pack's `.tres` is never opened.
func resource(rel: String) -> Resource:
	if not is_safe(rel):
		return null
	if not _resources.has(rel):
		var made: Resource = null
		if trusted and has(rel):
			made = load(path_of(rel))
		elif has(data_rel(rel)):
			made = ResourceJson.new(self).read(data_rel(rel))
			if made != null:
				made.set_meta(SOURCE_META, path_of(rel))
		if made == null:
			return null                                  # (not kept: a file that is written later is found)
		_resources[rel] = made                           # (kept here, the one owner: `ResourceLoader`'s own cache lets go of what nobody holds)
	return _resources[rel]


## The file `rel` as the object its extension says: a picture, a sound, or a resource (`resource`). Null for any other file.
func file(rel: String) -> Resource:
	match rel.get_extension():
		"png":
			return texture(rel)
		"ogg", "wav":
			return stream(rel)
		"tres":
			return resource(rel)
	return null


## Forgets the pictures, streams and clip lengths read so far (a file changed under a mounted pack), and lets go of a pack file (`close`).
func forget() -> void:
	close()
	_textures.clear()
	_streams.clear()
	_resources.clear()
	_measured = {}
	_stated = {}
	_clips_measured = false


# --- the lengths of the clips ---------------------------------------------------------------------------------------

## Loads every clip of the pack once and notes its length in ticks (`ClipLengths.measure`), and reads `audio/lengths.json`. `Packs` calls it when
## the pack is mounted, so the numbers are there before anything asks for a clip. Nothing is played: the same files give the same numbers.
func measure_clips() -> void:
	if _clips_measured:
		return
	_clips_measured = true
	_measured = {}
	for kind in Packs.CLIP_KINDS:
		var lengths := {}
		for file in files_in("audio/%s" % kind, "ogg"):
			lengths[StringName(file.get_basename())] = ClipLengths.measure(stream("audio/%s/%s" % [kind, file]))
		_measured[kind] = lengths
	var problems: Array[String] = []
	_stated = ClipLengths.stated(self, problems)
	for problem in problems:
		push_warning("Pack %s: %s" % [id, problem])


## The length of the clip called `clip_name` that this pack holds, in ticks of 1/73 s: the length the pack states, else the measured one,
## else -1 (the pack holds no such clip, or the file has no measurable length).
func clip_ticks(kind: StringName, clip_name: StringName) -> int:
	var own := stated_clip_ticks(kind, clip_name)
	return own if own >= 0 else measured_clip_ticks(kind, clip_name)


## The length of the file itself, rounded up to ticks; -1 when there is none to measure.
func measured_clip_ticks(kind: StringName, clip_name: StringName) -> int:
	measure_clips()
	return (_measured.get(kind, {}) as Dictionary).get(clip_name, -1)


## The length `audio/lengths.json` states for the clip, or -1 when it states none.
func stated_clip_ticks(kind: StringName, clip_name: StringName) -> int:
	measure_clips()
	return (_stated.get(kind, {}) as Dictionary).get(clip_name, -1)


## What is doubtful about the lengths of this pack's clips (see `ClipLengths.warnings`): the validation G4 calls.
func clip_warnings() -> Array[String]:
	return ClipLengths.warnings(self)


# --- what the layout holds -----------------------------------------------------------------------------------------

## The numbers of the sectors this pack holds as JSON (a folder `sectors/sector_NN` with its `sector_NN.json`), in order.
func sector_ids() -> Array[int]:
	return _sector_numbers()


func _sector_numbers() -> Array[int]:
	var numbers: Array[int] = []
	for folder in folders_in("sectors"):
		var digits := folder.trim_prefix("sector_")
		if folder.begins_with("sector_") and digits.is_valid_int() and not digits.begins_with("-") and not digits.begins_with("+") \
				and folder == "sector_%02d" % digits.to_int() and has(SectorJson.json_rel(digits.to_int())):
			numbers.append(digits.to_int())
	numbers.sort()
	return numbers


## The ids of the campaigns this pack holds (`campaigns/<id>.json`), in order.
func campaign_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for file in files_in("campaigns", "json"):
		found.append(StringName(file.get_basename()))
	return found


## What is wrong with the pack's layout, one sentence each; empty when it is sound. The manifest's own errors come first. (The pack tools' validation
## adds the checks that need the game: the playability checks on the sectors, names that resolve, clip lengths.)
func problems() -> Array[String]:
	var found: Array[String] = errors.duplicate()
	if not trusted:
		for rel in _all_files():
			if RESOURCE_EXTENSIONS.has(rel.get_extension()):
				found.append("%s: a pack outside the project holds no resources or code (%s): it is read as data (a .json for a .tres)" % [rel, rel.get_extension()])
	return found


## Every file of the pack as a relative path (a walk of the whole folder, or the pack file's index): what an exporter copies and an installer checks.
func all_files() -> Array[String]:
	return _all_files()


func _all_files() -> Array[String]:
	if _archive != null:
		return _archive.all_files()
	var found: Array[String] = []
	if root.is_empty():
		return found                                     # (a pack that was never opened has no folder: not the root of the disk)
	return PackFiles.files_under(root)
