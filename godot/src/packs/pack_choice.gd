class_name PackChoice
extends RefCounted
## What the pack screen knows: the packs that were found, which of them the game is using and why. The sibling of `SkinChoice` (which
## skin) and `PresenterChoice`: one small place that knows, so the menu, the command line (`pack_tool.tscn --list`) and the tests all say the same thing.
##
## THERE IS NOTHING TO SWITCH. The game uses one pack and the chain it is laid over (`Packs`): `--pack=<id>` on the command line chooses, and without it the
## first pack found in the order of the ids is chosen. So this class only describes: `entries` (every pack found, and the packs of the chain that are not
## found, such as `dev`), `summary` (the chain, and how it came to be), and the quick check the menu runs on a pack.
##
## Teaches: a view that asks the state instead of keeping a copy of it. Nothing here remembers anything; `Packs` is the one owner.


## One line of the list.
class Entry extends RefCounted:
	var pack: Pack
	## Where the pack is in the chain: 0 is the chosen pack, 1 its base, and so on; -1 when the game does not use it.
	var position := -1

	func id() -> StringName:
		return pack.id

	func in_use() -> bool:
		return position >= 0


## The quick check of the menu: the playability checks on the sectors without the reachability search. (The full check is `pack_tool.tscn --check=`.)
static func check_options() -> PackCheck.Options:
	var options := PackCheck.Options.new()
	options.reach = false
	return options


## Everything the screen lists: the packs found (`Packs.available`, in `res://packs/` and `user://packs/`), an installed `dev` (it is not among those: `Packs.dev`), and
## the packs of the chain that are not among them (the project's `dev` at the bottom of a chain that could not be made).
static func entries() -> Array[Entry]:
	var found: Array[Entry] = []
	var seen := {}
	for pack in Packs.available():
		seen[pack.id] = true
		found.append(_entry_of(pack))
	var stand_in := Packs.dev()
	if stand_in != null and stand_in.root.begins_with(PackInstall.DIR + "/") and not seen.has(stand_in.id):
		seen[stand_in.id] = true
		found.append(_entry_of(stand_in))
	for pack in Packs.chain():
		if not seen.has(pack.id):
			found.append(_entry_of(pack))
	return found


static func _entry_of(pack: Pack) -> Entry:
	var entry := Entry.new()
	var used := Packs.pack(pack.id)
	entry.pack = used if used != null else pack
	entry.position = Packs.chain().find(used) if used != null else -1
	return entry


static func entry(id: StringName) -> Entry:
	for each in entries():
		if each.id() == id:
			return each
	return null


## Does anything need showing? (A pack is installed in the player's folder: the sign-in screen shows its small "Packs" button only then; the project's own
## packs and the pack files a game carries next to it (`Packs.bundled`, read where they lie) are no reason to.)
static func any() -> bool:
	return Packs.available().any(func(pack: Pack) -> bool: return pack.root.begins_with(Packs.USER_PACKS_DIR + "/") and not Packs.bundled.has(pack.id))


## "in use", "base of legacy" or "": the third column of the list.
static func state_text(entry: Entry) -> String:
	match entry.position:
		-1:
			return ""
		0:
			return "in use"
		_:
			return "base"


## The chain in one line, chosen pack first: "orchard > legacy".
static func chain_text() -> String:
	if Packs.chain().is_empty():
		return "(no pack)"
	return " > ".join(PackedStringArray(Packs.chain_ids().map(func(id: StringName) -> String: return String(id))))


## What the screen says above the list: the chain in use and why it is that one.
static func summary() -> String:
	var lines := PackedStringArray()
	lines.append("In use: %s" % chain_text())
	var reason := Packs.fallback_reason()
	if reason != null:
		lines.append(reason.text())
		lines.append(reason.advice())
	elif Packs.asked() != &"":
		lines.append("Chosen with --pack=%s." % Packs.asked())
	else:
		lines.append("Chosen because it is the first pack found, in the order of the ids; --pack=<id> chooses another.")
	for line in Packs.ignored():
		lines.append(line)
	return "\n".join(lines)
