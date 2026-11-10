class_name Packs
extends RefCounted
## The packs the game is made of: ONE chosen pack and the chain of packs it is laid over, and every lookup that asks them.
##
## THE CHAIN. A manifest may say `"base": "<id>"`, the pack it is laid over; a pack with no `base` is complete. The game chooses one pack
## (`--pack=<id>` after `--`, else the first pack found in the lexical order of the ids) and follows the `base` links: the chosen pack, its base,
## the base's base. `chain()` is that list, chosen pack first. A thing is asked of the chain in that order and the first pack that has it wins, so
## a pack that holds only a few files changes a game that it does not hold. Nothing is special about the original game: `legacy` is a pack like any
## other, a folder the importer writes. When the chain cannot be made (no pack at all, the pack asked for is not there, a base is missing, the
## links go round in a circle) or does not hold what the game needs (`PackNeeds`: checked once, when the chain is chosen), `fallback_reason()` says why, and
## what happens next depends on `dev_fallback`: on (a debug build, the default there) the pack `dev`, which is not meant for play, goes at the bottom of whatever
## was found, so it answers only what the chain lacks; off (a release build) nothing is added and the game refuses the chain (`is_refused`). `--pack=dev` chooses
## dev on purpose, and so does a pack whose `base` is `dev`: those chains are whole and there is nothing to say. Dev may be absent (`dev()` is null): it is the
## folder `res://packs/dev` of the project, else the installed `user://packs/dev`; with neither there is nothing to fall back to and the game refuses the chain in a
## debug build too.
##
## WHERE PACKS ARE FOUND (`available`, `dev`; the places are listed once, by `_places`, in the order that decides which pack is used when an id is in more than one): a folder with a
## `pack.json` in `res://packs/` (the project's own: TRUSTED, its `.tres` files are loaded), a folder in `user://packs/` (installed: read in the data form only, `Pack.trusted`), a pack file
## `user://packs/<id>.larissa` (`Pack.FILE_EXTENSION`: installed, read in place and never extracted, `PackArchive`) and a pack file the game carries next to it (`bundled`: `legacy.larissa`
## and `dev.larissa`, in `archive_folders`: the folder of the executable on a desktop build, the folder the Web page preloads into, also read in place). The first of these that has an
## id is the pack of that id; the others are left out and `ignored()` says which one is used. A pack file is used only when its `pack.json` names the id its file is called. The id `dev`
## is reserved for the dev pack: it is not among the packs to choose from but is where `dev()` comes from (the project's `res://packs/dev`, else the installed `user://packs/dev` or
## `user://packs/dev.larissa`, else the bundled `dev.larissa`), and a pack of another place that says it is `dev` is left out.
##
## THE DOOR, and the lookups, all down the chain: `resource(rel)`, `texture(rel)` and `stream(rel)` give the object a file of the first pack that provides it
## becomes (`Pack` decides how: a trusted pack's `.tres` is loaded, anything else is read in its data form), `file_at(path)` does the same for a path
## string held in data, and nothing else in the game turns a pack's file into an object. Besides:
##   * a WHOLE FILE the caller reads itself (MIDI bytes, a file an editor writes): `path(rel)` is where the first pack that has it keeps it (a virtual path for a
##     pack file); `has_file_at(path)` and `bytes_at(path)` read a path like that, whatever pack it is in.
##   * a THING a pack holds in its own layout (a sector or a campaign as JSON, a text, a picture by skin key, a clip by name): `sector_owner`,
##     `campaign_files`, `text`, `picture`, `clip`. A pack with no such files answers nothing, and the next one is asked.
##
## Teaches: a layered lookup (the Unix `PATH` idea, or CSS's cascade): the first layer that has the thing answers; a chain that is built by following
## links, and what to do when a link is broken; and a static class as the one owner of shared state, with a signal in a small object because a class
## cannot have a static signal.

## The folders `available` looks in, each holding `<id>/pack.json` folders.
const PROJECT_PACKS_DIR := "res://packs"
const USER_PACKS_DIR := "user://packs"
## The dev pack (placeholder content, `dev()`): the bottom of a chain that could not be made. Its id is reserved.
const DEV := StringName("dev")
## Where a Web build looks for the `<id>.larissa` pack files its page preloaded into the browser's virtual file system (`Engine.preloadFile(url, "/packs/<id>.larissa")`).
const WEB_ARCHIVES_DIR := "/packs"

## The command-line option that chooses the pack: `-- --pack=legacy`.
const PACK_OPTION := "--pack="
## Where each kind of clip is in a pack: `audio/<kind>/<name>.ogg` (the kinds are the registry's `sound`, `music`, `voice`).
const CLIP_KINDS: Array[StringName] = [&"sound", &"music", &"voice"]

## Does a chain that is not whole (`fallback_reason()` is not null) get `dev` at its bottom and play on? True in a debug build, where the dev pack's
## placeholders stand in for what is missing and the warning screen lets the player go on; false in a release build, where the game does not play a chain that is
## not whole (`is_refused`) and the warning screen is a refusal. A test sets it and puts it back. The setting is read when the chain is chosen.
static var dev_fallback := OS.is_debug_build()

## The folders packs are found in (each holds `<id>/pack.json` folders and `<id>.larissa` pack files), in the order they are looked at (the first wins when an id is in two). A test adds a
## scratch folder of its own, like adding a directory to `PATH`.
static var folders: Array[String] = [PROJECT_PACKS_DIR, USER_PACKS_DIR]
## The ids of the packs a game carries as pack files next to it (`archive_folders`), read in place; the Web shell's `PACK_IDS` lists the same two. A test gives it ids of its own.
static var bundled: Array[StringName] = [StringName("legacy"), DEV]
## The folders that are looked in for the `<id>.larissa` of the `bundled` packs (a folder in them is not a pack): `default_archive_folders`. (Other pack files are looked for in `folders`.)
static var archive_folders: Array[String] = default_archive_folders(OS.has_feature("web"), OS.has_feature("editor"), OS.get_executable_path())
## Where the dev pack is: the folder of the project, and (when the project has none) the installed copy (the folder, or the same path with `.larissa` added: the pack file). A test
## points them at folders that do not exist to make dev absent (`PackShelf.without_dev`).
static var dev_root := "%s/%s" % [PROJECT_PACKS_DIR, DEV]
static var installed_dev_root := "%s/%s" % [USER_PACKS_DIR, DEV]
## The signal of a change in the chain. (A class cannot have a static signal: this object has it.)
static var events := PackEvents.new()

static var _chain: Array[Pack] = []
static var _fallback: Fallback
## What `choose` was last asked for ("" is the default choice): `reset` makes the same choice again.
static var _wanted: StringName = &""
## Has a choice been made (`_chain` may be empty after one: a refused chain that holds no pack)?
static var _started := false
## Is `_chain` already built into the lookups (the start-up check built the chain it is about to judge)? `_settle` then does not build them again.
static var _tentative := false
static var _dev: Pack
## Has `dev()` looked for dev (`_dev` may be null after it)?
static var _dev_looked := false
## Why a copy of dev was left out, one sentence each; rebuilt with `_dev`.
static var _dev_notes: Array[String] = []
## "res://packs/legacy/data/zones.tres"'s `rel` -> the pack that holds it; filled as files are asked for, emptied when the chain changes.
static var _holders: Dictionary = {}
## Why packs found in the folders were left out; rebuilt by `available`.
static var _ignored: Array[String] = []
## The places already reported in the log, so that listing the packs again does not say it again.
static var _logged: Dictionary = {}
## The last fallback sentence written to the log (the choice is made again when something asks for it; the log says it once).
static var _said := ""
## sector number -> the first pack of the chain that holds it as JSON; filled by `_reindex`.
static var _sector_owner: Dictionary = {}
## text name -> words, the packs' `texts.json` merged (the pack nearest the top wins).
static var _texts: Dictionary = {}
## voice group name -> the nearest pack's list of clip names.
static var _voice_groups: Dictionary = {}
## Does any pack of the chain hold a picture? Worked out when the chain changes, because a skin asks on every data resource it shows.
static var _has_pictures := false


class PackEvents extends RefCounted:
	## The chain changed (a pack was chosen, or `refresh` was called).
	signal changed


## Why the chain is not the one asked for, and so has `dev` at its bottom (`Packs.dev_fallback`) or is refused. The warning screen, the log and the pack screen read it:
## `text()` says what happened and what it means in this mode, `advice()` where to read.
class Fallback extends RefCounted:
	enum Why {
		## No pack was found in `res://packs/` or `user://packs/`.
		NO_PACK,
		## `--pack=<id>` named a pack that is not there.
		NOT_FOUND,
		## A pack's manifest has errors, so it cannot be used.
		BROKEN,
		## A pack names a `base` that is not there.
		MISSING_BASE,
		## The `base` links go round in a circle.
		CYCLE,
		## The chain does not hold everything the game needs (`PackNeeds`): `missing` things, `detail` names the first.
		MISSING_ASSETS,
	}

	## Where to read, by situation (`advice`).
	const ADVICE_NO_PACK := "To play, build the game's content from your own copy of the original with the importer: see docs/play/LEGACY.md."
	const ADVICE_NOT_FOUND := "The pack screen lists the packs that were found. The importer builds the game's content from your own copy of the original (docs/play/LEGACY.md); 'Packs' in docs/create/CONTENT.md says how to get or make others."
	const ADVICE_COMPLETE := "The pack is damaged or out of date. If the importer made it, run the importer again: see 'Troubleshooting' in docs/play/LEGACY.md."
	const ADVICE_LAYERED := "The pack is unfinished, or it needs a pack that is not installed. To make packs, see docs/create/MAKING_CONTENT.md and 'Packs' in docs/create/CONTENT.md."
	const ADVICE_NEEDS_DEV := "This needs the dev pack, dev.larissa, which is not installed. It comes with the creator download: see 'Packs' in docs/create/CONTENT.md for where it goes."
	const ADVICE_GET_DEV := "The dev pack, dev.larissa, comes with the creator download: see 'Packs' in docs/create/CONTENT.md for where it goes."
	const NO_DEV_SENTENCE := "There are no dev assets to fall back to."

	var why: Why = Why.NO_PACK
	## The pack the trouble is about: the one asked for, the one with the errors, the one whose `base` is missing or that closes the circle, the chosen pack of an incomplete chain.
	var pack_id: StringName = &""
	## The pack that was not found (`NOT_FOUND`, `MISSING_BASE`), the first error (`BROKEN`), or what `PackNeeds.summary` says is missing (`MISSING_ASSETS`).
	var detail := ""
	## How many things the chain lacks (`MISSING_ASSETS`), else 0.
	var missing := 0
	## Is the chosen pack a complete pack (no `base`)? Then trouble means it is damaged or out of date; otherwise it is a pack laid over another.
	var complete_pack := false
	## Does the game refuse this chain (`dev` is not under it), or does `dev` stand in? Fixed when the chain is chosen (`Packs.dev_fallback`).
	var refused := false
	## Would dev have stood in (`Packs.dev_fallback` was on) but there is no dev pack (`Packs.dev()` is null)? Then the chain is refused all the same. False when the trouble
	## is dev itself (`needs_dev`): that says so on its own.
	var no_dev := false

	## Is the trouble that dev is not there (`--pack=dev`, or a pack laid over `dev`)?
	func needs_dev() -> bool:
		return (why == Why.NOT_FOUND and pack_id == Packs.DEV) or (why == Why.MISSING_BASE and detail == String(Packs.DEV))

	func text() -> String:
		var outcome := "so the game cannot play it." if refused else ""
		var said := ""
		match why:
			Why.NO_PACK:
				said = "No pack was found, so the game cannot play." if refused else "No pack was found, so the dev pack, which is not meant for play, is all there is."
			Why.NOT_FOUND:
				said = "There is no pack '%s', so the game cannot play." % pack_id if refused else "There is no pack '%s', so the dev pack, which is not meant for play, is all there is." % pack_id
			Why.BROKEN:
				said = "The pack '%s' cannot be used (%s), %s" % [pack_id, detail, outcome if refused else "so the dev pack is under it."]
			Why.MISSING_BASE:
				said = "The pack '%s' is laid over '%s', which is not there, %s" % [pack_id, detail, outcome if refused else "so the dev pack is under it."]
			Why.CYCLE:
				said = "The pack '%s' is laid over itself through its bases, %s" % [pack_id, outcome if refused else "so the dev pack is under it."]
			Why.MISSING_ASSETS:
				said = "The pack '%s' is incomplete (%s), %s" % [pack_id, detail, outcome if refused else "so the dev pack, which is not meant for play, stands in for what it lacks."]
		return said + (" " + NO_DEV_SENTENCE if no_dev and not said.is_empty() else "")

	## Where to read about this situation: the importer for no pack at all, a pack that is damaged or out of date, the creators' documents for a pack laid over another,
	## and where the dev pack comes from when it is the dev pack that is missing.
	func advice() -> String:
		if needs_dev():
			return ADVICE_NEEDS_DEV
		var read := ADVICE_COMPLETE if complete_pack else ADVICE_LAYERED
		match why:
			Why.NO_PACK:
				read = ADVICE_NO_PACK
			Why.NOT_FOUND:
				read = ADVICE_NOT_FOUND
		return read + (" " + ADVICE_GET_DEV if no_dev else "")

	## A line saying how much is missing, for the warning screen ("" unless the chain lacks things).
	func missing_text() -> String:
		if missing == 0:
			return ""
		return "%d %s missing." % [missing, "thing is" if missing == 1 else "things are"]


## A chain and the reason it is not the one asked for (null when it is whole).
class Chain extends RefCounted:
	var packs: Array[Pack] = []
	var fallback: Fallback


# --- the chain ------------------------------------------------------------------------------------------------------

## The packs in use, chosen pack first, the pack at the bottom last. The first call makes the choice the command line asks for. Empty only when the game refused a
## choice that found no pack at all (`is_refused`).
static func chain() -> Array[Pack]:
	if not _started:
		start()
	return _chain


## The pack that was chosen; null when the game refused the choice and no pack of it could be used (`is_refused`).
static func chosen() -> Pack:
	var made := chain()
	return made[0] if not made.is_empty() else null


## What `choose` was last asked for: the id from `--pack=`, or `&""` for the default choice.
static func asked() -> StringName:
	chain()
	return _wanted


## The ids of the chain, chosen pack first.
static func chain_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for each in chain():
		ids.append(each.id)
	return ids


## The pack of the chain called `id`, or null.
static func pack(id: StringName) -> Pack:
	for each in chain():
		if each.id == id:
			return each
	return null


static func in_chain(id: StringName) -> bool:
	return pack(id) != null


## Why the chain is not the one asked for, or null when it is whole. (`--pack=dev` is a choice, not a fallback: null; so is a pack laid over `dev`.)
static func fallback_reason() -> Fallback:
	chain()
	return _fallback


## Does the game refuse the chain it has (a fallback while `dev_fallback` was off when the choice was made)? Then nothing is played: the warning screen is a refusal.
static func is_refused() -> bool:
	chain()
	return _fallback != null and _fallback.refused


## Chooses the pack the command line asks for (`--pack=<id>` among `args`), else the first pack found. The game does this once, in `main.gd`; the first
## lookup does it by itself when nobody has (a tool, the editor, a test).
static func start(args: PackedStringArray = OS.get_cmdline_user_args()) -> void:
	var asked: StringName = &""
	for arg in args:
		if arg.begins_with(PACK_OPTION):
			asked = StringName(arg.trim_prefix(PACK_OPTION))
	choose(asked)


## Chooses the pack `id` among the packs found (`available`, and `dev`) and builds its chain; `&""` is the default choice, the first pack found in the
## lexical order of the ids. True when the chain is whole; false when it is not (`fallback_reason` says why; `dev` is put at the bottom of it, or the chain is refused,
## by `dev_fallback`). A chain that resolves is then checked for what the game needs (`_checked`), once.
static func choose(id: StringName = &"") -> bool:
	_wanted = id
	var found := available()
	var first: Pack = null
	if id == &"":
		for each in found:
			if each.is_valid():
				first = each
				break
		if first == null:
			return _settle(_failed(Fallback.Why.NO_PACK, &"", ""))
	else:
		first = _found(id, found)
		if first == null:
			return _settle(_failed(Fallback.Why.NOT_FOUND, id, ""))
	return _settle(_checked(resolve(first, found, dev_fallback)))


## Uses `first` (a pack that is not among the found ones: a scratch pack of a test, a folder that is being checked) and the chain of its bases. `dev` goes under a chain
## that cannot be made whatever `dev_fallback` says, and the chain is not checked for what it holds: this is for a tool or a test that looks at a pack, not the game's choice.
static func use(first: Pack) -> bool:
	return _settle(resolve(first))


## The chain in use, to give back to `restore` (a check or a test borrows the chain for a while).
static func snapshot() -> Dictionary:
	chain()
	return {"chain": _chain, "fallback": _fallback, "wanted": _wanted}


static func restore(saved: Dictionary) -> void:
	_chain = saved["chain"]
	_fallback = saved["fallback"]
	_wanted = saved["wanted"]
	_changed()


## Runs `body` with exactly `packs` as the chain (chosen pack first, nothing appended: `dev` is not put under it), then puts the chain in use back. For a
## question about a chain that is not the one in use (`PackNeeds`).
static func lend(packs: Array[Pack], body: Callable) -> void:
	var saved := snapshot()
	_chain = packs
	_fallback = null
	_changed()
	body.call()
	restore(saved)


## Makes the choice again (the packs on the disk changed, or a test is over): what `choose` was last asked for, the default if nothing was.
static func reset() -> bool:
	return choose(_wanted)


## The chain that starts with `first`: it, its base, its base's base; with `dev` under it and the reason when a link is broken (unless `with_dev` is false:
## then the chain stops at the broken link, as far as it got). Changes nothing.
static func resolve(first: Pack, found: Array[Pack] = [], with_dev := true) -> Chain:
	if found.is_empty():
		found = available()
	var result := Chain.new()
	var next: Pack = first
	while next != null:
		var each := next
		if not each.is_valid():
			return _broken(result, Fallback.Why.BROKEN, each.id if each.id != &"" else StringName(each.root.get_file()), each.errors[0], with_dev, each)
		if result.packs.any(func(held: Pack) -> bool: return held.id == each.id):
			return _broken(result, Fallback.Why.CYCLE, each.id, "", with_dev)
		result.packs.append(each)
		if each.base == &"":
			return result
		next = _found(each.base, found)
		if next == null:
			return _broken(result, Fallback.Why.MISSING_BASE, each.id, String(each.base), with_dev)
	return result


static func _failed(why: Fallback.Why, pack_id: StringName, detail: String) -> Chain:
	return _broken(Chain.new(), why, pack_id, detail, dev_fallback)


## `chain` with `dev` appended (unless it is in there, or `with_dev` is false, or there is no dev: then the game refuses it) and the reason it had to be. `offender` is the pack
## the trouble is in when no pack of the chain is yet (a first pack with errors).
static func _broken(chain_so_far: Chain, why: Fallback.Why, pack_id: StringName, detail: String, with_dev := true, offender: Pack = null) -> Chain:
	chain_so_far.fallback = Fallback.new()
	chain_so_far.fallback.why = why
	chain_so_far.fallback.pack_id = pack_id
	chain_so_far.fallback.detail = detail
	var stands_in: Pack = dev() if with_dev else null
	chain_so_far.fallback.refused = stands_in == null
	chain_so_far.fallback.no_dev = with_dev and stands_in == null and not chain_so_far.fallback.needs_dev()
	var first: Pack = chain_so_far.packs[0] if not chain_so_far.packs.is_empty() else offender
	chain_so_far.fallback.complete_pack = first != null and first.base == &""
	if stands_in != null and not chain_so_far.packs.any(func(held: Pack) -> bool: return held.id == DEV):
		chain_so_far.packs.append(stands_in)
	return chain_so_far


## The start-up check: does a chain that resolved hold everything the game needs? `PackNeeds.gaps` on the chain with no `dev` under it and no skin (a pack must be
## complete whatever skin is on). Hard gaps make it a fallback (`MISSING_ASSETS`, with `dev` under it or refused as `dev_fallback` says); soft gaps are only logged. A chain
## with `dev` in it (`--pack=dev`, a pack laid over it) is whole: dev is complete and is not asked. The chain is built into the lookups first, because `PackNeeds` asks
## the lookups; `_settle` knows and does not build it again when nothing is added to it.
static func _checked(result: Chain) -> Chain:
	if result.fallback != null or result.packs.is_empty() or result.packs.any(func(held: Pack) -> bool: return held.id == DEV):
		return result
	_chain = result.packs.duplicate()                          # (a copy: `_broken` may add `dev` to the result, and then the lookups must be built again)
	_fallback = null
	_started = true
	_tentative = true
	_rebuild()
	var found := PackNeeds.gaps(result.packs)
	var hard := PackNeeds.hard(found)
	var soft := PackNeeds.soft(found)
	if not soft.is_empty():
		_log_once("soft", "The chain %s lacks %s (the game goes on without)." % ["/".join(PackedStringArray(result.packs.map(func(held: Pack) -> String: return String(held.id)))), PackNeeds.summary(soft)])
	if hard.is_empty():
		return result
	var failed := _broken(result, Fallback.Why.MISSING_ASSETS, result.packs[0].id, PackNeeds.summary(hard), dev_fallback)
	failed.fallback.missing = hard.size()
	return failed


static func _log_once(key: String, line: String) -> void:
	if not _logged.has(key + line):
		_logged[key + line] = true
		print("Packs: ", line)


static func _settle(result: Chain) -> bool:
	var built := _tentative and _chain == result.packs
	_tentative = false
	_chain = result.packs
	_fallback = result.fallback
	_started = true
	if _fallback != null and _fallback.text() != _said:
		_said = _fallback.text()
		print("Packs: ", _said)
	if built:
		events.changed.emit()
	else:
		_changed()
	return _fallback == null


## The pack called `id` among `found` (and `dev`, which is not among them, and null when dev is absent), or null.
static func _found(id: StringName, found: Array[Pack]) -> Pack:
	if id == DEV:
		return dev()
	for each in found:
		if each.id == id:
			return each
	return null


## The dev pack, or null when it is absent. It is the folder `res://packs/dev` of the project (the editor, the tests); with no such folder it is the installed `user://packs/dev` (a
## folder) or `user://packs/dev.larissa` (a pack file, installed from the pack screen), and with neither the bundled `dev.larissa` next to the game, which is read in place. The first of
## these that is a dev pack wins: the others are left out and `ignored()` says so. The answer is kept until `forget_dev`.
static func dev() -> Pack:
	if not _dev_looked:
		_dev_looked = true
		_dev = _find_dev()
	return _dev


## Is there a dev pack (`dev()` is not null)?
static func has_dev() -> bool:
	return dev() != null


## Looks for dev again the next time it is asked (a test changed `dev_root`, `installed_dev_root` or `archive_folders`, or a dev pack was installed or removed).
static func forget_dev() -> void:
	if _dev != null:
		_dev.close()
	_dev = null
	_dev_looked = false
	_dev_notes = []


static func _find_dev() -> Pack:
	_dev_notes = []
	var found: Pack = null
	var places := _dev_places()
	for where in _places():
		if not places.has(where):
			continue
		var candidate := Pack.open(where)
		if candidate.is_archive() and not _archive_note(candidate).is_empty():
			continue                                         # (`available` says why a pack file is left out)
		if not candidate.is_valid():
			_dev_notes.append("%s: it cannot be used (%s), so it is left out" % [where, candidate.errors[0]])
		elif candidate.id != DEV:
			_dev_notes.append("%s: its pack.json says '%s', not 'dev', so it is left out" % [where, candidate.id])
		elif found != null:
			_dev_notes.append("%s: dev is %s, so this copy is left out" % [where, found.root])
		else:
			found = candidate
	for note in _dev_notes:
		_log_once("left out", note)
	return found


## The places `dev()` looks in: where the project and the installed dev are (`dev_root`, `installed_dev_root` and its `.larissa`) and the bundled `dev.larissa`.
static func _dev_places() -> Array[String]:
	var places: Array[String] = [dev_root, installed_dev_root, "%s.%s" % [installed_dev_root, Pack.FILE_EXTENSION]]
	for dir in archive_folders:
		places.append("%s/%s.%s" % [dir, DEV, Pack.FILE_EXTENSION])
	return places


## The `archive_folders` of a build: the folder the Web page preloads files into (`WEB_ARCHIVES_DIR`); on a desktop the folder of the executable, so that `legacy.larissa` or
## `dev.larissa` can sit next to the game; none in the editor (the executable there is Godot's own) or when the executable is not known.
static func default_archive_folders(web: bool, in_editor: bool, executable: String) -> Array[String]:
	if web:
		return [WEB_ARCHIVES_DIR]
	if in_editor or executable.is_empty():
		return []
	return [executable.get_base_dir()]


# --- finding packs ----------------------------------------------------------------------------------------------------

## Every place that holds a pack, in the order that decides which pack is used when an id is in more than one: the folders (with a `pack.json`) of each of `folders` (the project's
## `res://packs/` first, then `user://packs/`), dev's own folders (`dev_root`, `installed_dev_root`), the `.larissa` pack files of each of `folders`, the installed dev's pack file, and the
## bundled pack files (`archive_folders`, the ids of `bundled`). Nothing is opened: this is the one search, `available` and `dev` open what they want of it. A folder that
## is the same folder as another (a link to it) is listed once, and so is a pack file.
static func _places() -> Array[String]:
	var places: Array[String] = []
	var seen: Array[String] = []
	var folder_places: Array[String] = []
	for dir in folders:
		if DirAccess.dir_exists_absolute(dir):
			for folder in DirAccess.get_directories_at(dir):
				folder_places.append("%s/%s" % [dir, folder])
	folder_places.append(dev_root)
	folder_places.append(installed_dev_root)
	for where in folder_places:
		if FileAccess.file_exists("%s/%s" % [where, Pack.MANIFEST]) and not seen.has(real_folder(where)):
			seen.append(real_folder(where))
			places.append(where)
	var file_places: Array[String] = []
	for dir in folders:
		if DirAccess.dir_exists_absolute(dir):
			for file in DirAccess.get_files_at(dir):
				if file.get_extension() == Pack.FILE_EXTENSION:
					file_places.append("%s/%s" % [dir, file])
	file_places.append("%s.%s" % [installed_dev_root, Pack.FILE_EXTENSION])
	for dir in archive_folders:
		for id in bundled:
			file_places.append("%s/%s.%s" % [dir, id, Pack.FILE_EXTENSION])
	for where in file_places:
		var real := ProjectSettings.globalize_path(where).simplify_path()
		if not seen.has(real) and FileAccess.file_exists(where):
			seen.append(real)
			places.append(where)
	return places


## The packs that could be chosen, in the lexical order of their ids: one for each id found in the places of `_places` (`ignored()` says what was left out and which pack is used instead). `dev`
## is not among them (it is `dev()`), and a pack elsewhere that says it is `dev` is left out. A folder with errors in its manifest is listed (the pack screen shows them) but is never the
## default choice; a pack file that cannot be read, or whose manifest names another id than its file, is left out.
static func available() -> Array[Pack]:
	var found: Array[Pack] = []
	_ignored = []
	for where in _places():
		var candidate := Pack.open(where)
		var note := _archive_note(candidate) if candidate.is_archive() else ""
		if not note.is_empty():
			_leave_out(note)
		elif candidate.id == DEV:
			if not _dev_places().has(where) and not ["%s/%s" % [PROJECT_PACKS_DIR, DEV], "%s/%s" % [USER_PACKS_DIR, DEV], "%s/%s.%s" % [USER_PACKS_DIR, DEV, Pack.FILE_EXTENSION]].has(where):
				_leave_out("%s: the id 'dev' is reserved for the dev pack (the folder res://packs/dev, or dev installed in %s), so this one is left out; copy the dev pack under an id of your own" % [where, USER_PACKS_DIR])
		else:
			var used := found.filter(func(held: Pack) -> bool: return held.id == candidate.id)
			if used.is_empty():
				found.append(candidate)
			else:
				_leave_out("%s: '%s' is %s, so this one is left out" % [where, candidate.id, used[0].root])
	_ignored.append_array(_dev_notes)                          # (what `dev()` found about the copies of dev; listing does not look for one)
	found.sort_custom(func(a: Pack, b: Pack) -> bool: return String(a.id) < String(b.id))
	return found


## Why the pack file `candidate` is not a pack the game can use ("" when it is): it cannot be read, or its manifest's id is not its file's name (`legacy.larissa` holds `legacy`).
static func _archive_note(candidate: Pack) -> String:
	if not candidate.is_valid():
		return "%s: it cannot be used (%s), so it is left out" % [candidate.root, candidate.errors[0]]
	if String(candidate.id) != candidate.root.get_file().get_basename():
		return "%s: its pack.json says '%s', not '%s', so it is left out" % [candidate.root, candidate.id, candidate.root.get_file().get_basename()]
	return ""


static func _leave_out(note: String) -> void:
	_ignored.append(note)
	_log_once("left out", note)


## Packs left out of `available` and why, one sentence each. For the pack screen and the log.
static func ignored() -> Array[String]:
	return _ignored


## The folder `path` (`res://` or `user://`) on the file system with a link at its end followed: two paths that name the same folder give the same text.
static func real_folder(path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path).simplify_path().trim_suffix("/")
	var parent := DirAccess.open(absolute.get_base_dir())
	if parent != null and parent.is_link(absolute):
		var target := parent.read_link(absolute)
		absolute = (target if target.is_absolute_path() else absolute.get_base_dir().path_join(target)).simplify_path().trim_suffix("/")
	return absolute


## Lets go of the pack file of the pack `id` if the chain in use, or dev, holds it open (`Pack.close`), so that the file can be replaced or deleted (`PackInstall`). It is opened again by the next read.
static func release_file(id: StringName) -> void:
	for each in _chain:
		if each.id == id:
			each.close()
	if _dev != null and _dev.id == id:
		_dev.close()


## Looks at the chain again (a tool wrote files into a pack): pictures and sounds read so far are dropped, the pack files are let go of (`Pack.close`) and the lists rebuilt.
static func refresh() -> void:
	for each in chain():
		each.forget()
	if _dev != null:
		_dev.close()
	_changed()


# --- whole files, down the chain ----------------------------------------------------------------------------------------

## The first pack of the chain that provides the file `rel` (`data/zones.tres`) in a form it may be read in (`Pack.provides`: a trusted pack's `.tres`, any
## pack's data form `data/zones.json`, any other file the pack has), or null.
static func holder(rel: String) -> Pack:
	if not _holders.has(rel):
		for each in chain():
			if each.provides(rel):
				_holders[rel] = each
				return each
		return null
	return _holders[rel]


static func has(rel: String) -> bool:
	return holder(rel) != null


## `first` if it provides the file `rel` (or, with `folder_too`, has the folder), else the first pack UNDER it in the chain that does (never one above it), or null.
## Where a `$ref` of a file of `first` is looked for. A `first` that is not in the chain (a pack being checked) is followed by the whole chain; a null `first` is the chain.
static func provider_below(first: Pack, rel: String, folder_too := false) -> Pack:
	var packs := chain()
	var at := packs.find(first) if first != null else -1
	if first != null and (first.provides(rel) or (folder_too and first.has_folder(rel))):
		return first
	for i in range(at + 1, packs.size()):
		if packs[i].provides(rel) or (folder_too and packs[i].has_folder(rel)):
			return packs[i]
	return null


## Where the file `rel` is: in the first pack of the chain that has it. A file nobody has is named in the bottom pack (the one that should have it), so that a
## message about it says which file is missing (in a refused choice that holds no pack, in a folder that does not exist).
static func path(rel: String) -> String:
	var held := holder(rel)
	if held != null:
		return held.path_of(rel)
	var made := chain()
	return made.back().path_of(rel) if not made.is_empty() else "%s/none/%s" % [PROJECT_PACKS_DIR, rel]


## The file `path` of a pack as a path relative to the pack: "data/zones.tres" for "res://packs/legacy/data/zones.tres" (a pack of the chain anywhere, or any
## folder `res://packs/<id>/`). "" for a path that is not in a pack.
static func relative(path_in_a_pack: String) -> String:
	var owner := pack_of_path(path_in_a_pack)
	if owner != null:
		return path_in_a_pack.trim_prefix(owner.root + "/")
	var prefix := PROJECT_PACKS_DIR + "/"
	if not path_in_a_pack.begins_with(prefix):
		return ""
	var inside := path_in_a_pack.trim_prefix(prefix)
	return inside.substr(inside.find("/") + 1) if inside.contains("/") else ""


# --- what a pack holds in its own layout, found nearest the top first -------------------------------------------------------

## Sectors: the pack that holds sector `index` as JSON, or null.
static func sector_owner(index: int) -> Pack:
	return _sector_owner.get(index)


## The numbers of the sectors the packs of the chain hold as JSON, in order.
static func sector_ids() -> Array[int]:
	chain()
	var found: Array[int] = []
	for index: int in _sector_owner:
		found.append(index)
	found.sort()
	return found


## Campaigns: pack, id and file of every campaign the packs of the chain hold as JSON, the chosen pack's first.
static func campaign_files() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for each in chain():
		for campaign_id in each.campaign_ids():
			found.append({"pack": each, "id": campaign_id, "rel": "campaigns/%s.json" % campaign_id})
	return found


## Texts: the words of the text `text_name` in a pack's `texts.json`, or null when no pack has one. (The pack may name a text of the
## original, to say it differently, or one of its own.)
static func text(text_name: String) -> Variant:
	chain()
	return _texts.get(text_name)


## The `voice_cues.json` groups of the packs: group name -> clip names (`Catalog.voice_cues` merges these into the complete pack's).
static func voice_groups() -> Dictionary:
	chain()
	return _voice_groups


## Pictures: the picture for a skin key (`ui_picture/title_sky`, `background/bg_s40_00`) in the first pack that has `pictures/<key>.png`.
static func picture(key: String) -> Texture2D:
	if key.is_empty():
		return null
	var rel := "pictures/%s.png" % key
	for each in chain():
		var texture := each.texture(rel)
		if texture != null:
			return texture
	return null


## Does any pack hold a picture? (A skin treats the pictures as mapped then: `GameSkin.has_pictures`.)
static func has_pictures() -> bool:
	chain()
	return _has_pictures


## Clips: the sound, song or speech clip called `clip_name` (`kind` is `sound`, `music` or `voice`) in the first pack that has
## `audio/<kind>/<name>.ogg`, as a `PackClip`; null when no pack has it. The clip's length comes back in it, from the SAME pack as the stream:
## the pack's stated length, else the measured one (`Pack.clip_ticks`).
static func clip(kind: StringName, clip_name: StringName) -> PackClip:
	if not CLIP_KINDS.has(kind) or clip_name == &"":
		return null
	var rel := "audio/%s/%s.ogg" % [kind, clip_name]
	for each in chain():
		var stream := each.stream(rel)
		if stream != null:
			return PackClip.of(each, stream, each.clip_ticks(kind, clip_name))
	return null


# --- THE DOOR: the first pack that provides the thing ------------------------------------------------------------------------

## The resource `rel` (the authoring path, `data/zones.tres`) of the first pack of the chain that provides it: loaded from a trusted pack's file, or made from
## the data form of any pack (`Pack.resource`). Null when no pack does.
static func resource(rel: String) -> Resource:
	var held := holder(rel)
	return held.resource(rel) if held != null else null


## The picture file `rel` (`assets/tiles/zone0_tiles.png`) of the first pack that has it, as a texture (`Pack.texture`), or null.
static func texture(rel: String) -> Texture2D:
	var held := holder(rel)
	return held.texture(rel) if held != null else null


## The sound file `rel` (`assets/audio/sfx/x.wav`, `.ogg`) of the first pack that has it, as a stream (`Pack.stream`), or null.
static func stream(rel: String) -> AudioStream:
	var held := holder(rel)
	return held.stream(rel) if held != null else null


## The pack whose folder `path` is under (the packs of the chain, `dev`, and `extra`), or null.
static func pack_of_path(path: String, extra: Pack = null) -> Pack:
	if path.is_empty():
		return null
	var candidates: Array[Pack] = []
	if extra != null:
		candidates.append(extra)
	candidates.append_array(chain())
	var dev_pack := dev()
	if dev_pack != null:
		candidates.append(dev_pack)
	for each in candidates:
		if not each.root.is_empty() and path.begins_with(each.root + "/"):
			return each
	return null


## The path of the file a picture, sound or resource was read from (`resource_path`, else what `Pack` noted: a decoded picture has no path of its own), or "".
static func source_of(resource: Resource) -> String:
	if resource == null:
		return ""
	return resource.resource_path if not resource.resource_path.is_empty() else String(resource.get_meta(Pack.SOURCE_META, ""))


## THE DOOR for a path STRING held in data (`VoiceIndex.paths`, `MusicCatalog.gm_paths`, `ProblemType.art_files`: `res://packs/dev/assets/...`): the pack whose folder
## it is under answers by the extension of the file (`Pack.file`); a path of the project itself (`res://data/...`) is project code and is loaded. A path under
## `user://`, or in a pack that is not in the chain, gives null: nothing outside the project reaches `ResourceLoader`.
static func file_at(path: String) -> Resource:
	var owner := pack_of_path(path)
	if owner != null:
		return owner.file(path.trim_prefix(owner.root + "/"))
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path)
	return null


## Is there the plain file `path`? A file of a pack (folder or pack file) is asked of its pack (`Pack.has`), any other path of the file system. For code that is handed a path
## and reads bytes (`bytes_at`); `exists_at` is for the objects the door makes.
static func has_file_at(path: String) -> bool:
	var owner := pack_of_path(path)
	return owner.has(path.trim_prefix(owner.root + "/")) if owner != null else FileAccess.file_exists(path)


## The bytes of the plain file `path` (empty when there is none): of a pack's file through its pack (`Pack.read_bytes`: a folder or a pack file alike), else from the file system.
static func bytes_at(path: String) -> PackedByteArray:
	var owner := pack_of_path(path)
	return owner.read_bytes(path.trim_prefix(owner.root + "/")) if owner != null else FileAccess.get_file_as_bytes(path)


## Is there a file `path` for `file_at` to answer with? (Existence only; nothing is read.)
static func exists_at(path: String) -> bool:
	var owner := pack_of_path(path)
	if owner != null:
		return owner.provides(path.trim_prefix(owner.root + "/"))
	return path.begins_with("res://") and ResourceLoader.exists(path)


# --- keeping the lists ---------------------------------------------------------------------------------------------

static func _changed() -> void:
	_rebuild()
	events.changed.emit()


## Builds the lookups for the chain in use.
static func _rebuild() -> void:
	_holders = {}
	_reindex()
	Catalog.packs_changed()
	Durations.read_files()


## Builds the lists the lookups use: who holds each sector, the merged texts, the merged speech groups; measures the clips of a pack
## that has not been. The chain is walked from the bottom so that the pack nearest the top has the last word.
static func _reindex() -> void:
	_sector_owner = {}
	_texts = {}
	_voice_groups = {}
	_has_pictures = false
	for i in range(_chain.size() - 1, -1, -1):
		var each := _chain[i]
		each.measure_clips()
		_has_pictures = _has_pictures or not each.folders_in("pictures").is_empty()
		for number in each.sector_ids():
			_sector_owner[number] = each
		var words: Variant = each.read_json("texts.json")
		if words is Dictionary:
			for key: String in words:
				if words[key] is String:
					_texts[key] = words[key]
				else:
					push_warning("Pack %s: texts.json: '%s' is not a string" % [each.id, key])
		var cues: Variant = each.read_json("voice_cues.json")
		if cues is Dictionary and cues.get("groups") is Dictionary:
			for group: String in cues["groups"]:
				var names: Array[StringName] = []
				for clip_name: String in cues["groups"][group]:
					names.append(StringName(clip_name))
				_voice_groups[group] = names
