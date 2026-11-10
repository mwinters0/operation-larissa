@tool
class_name NameRegistry
extends RefCounted
## The symbol table of a content set: friendly names for the numbers the original's data uses, and back.
## A creature script says `Play_Sound begin`, the file says 22; this class turns one into the other.
## The names live in `names/original.json` (hand-made, committed, stored apart from everything the importer
## generates); the format, the kinds, the scopes and the naming rules are described in docs/create/NAMES.md.
##
## Teaches: what a SYMBOL TABLE is (the table an assembler keeps to turn names into numbers, here with a second
## direction for the disassembler); SCOPES (the same number means different things in different places, like a
## local variable: creature picture 40 is a different drawing in every zone, so a picture name belongs to a zone;
## a name that holds everywhere is "common", like a global); and a TOTAL function (every number always has a name,
## because an unnamed one gets a made-up name from its number, `sfx_28`, and that name can be looked up again).
##
## Usage:
##     var names := NameRegistry.original()
##     names.index_of(&"sound", "begin")                      # 22
##     names.name_of(&"sound", 28)                            # "sfx_28": nobody named it yet
##     names.index_of(&"frame", "ink_burst_3", zone)          # 31; a frame name needs the zone it is looked up in
##     names.names(&"flag", sector)                           # for a completion list
## Lookups answer -1 (or "") for something unknown; `explain_unknown` says why, in words for the person who typed it.

## The name store of the original game. A content set made later (a campaign) has a file of its own.
const STORE_PATH := "res://names/original.json"
## The version of the file format (the "format" key of the file).
const FORMAT := 1

## "No scope": the one table of a GLOBAL kind, and the `common` names of a scoped kind (valid in every scope).
const NO_SCOPE := -1
## The key of the common names in the file (a scope is otherwise written as its number).
const COMMON_KEY := "common"

## How far a name reaches.
##   GLOBAL  one table for the whole content set (sounds, songs, speech ...)
##   ZONE    one table per zone, plus the common names (creature and deco pictures: slot 35+ is a different
##           drawing in every zone)
##   SECTOR  one table per sector, plus the common names (creatures, screens and flags are numbered per sector)
enum Scope { GLOBAL, ZONE, SECTOR }

## The longest name.
const MAX_NAME_LENGTH := 40
## Words a name may not be, because an operand already uses them: `self` / `self+N` name a creature, and `mirror` is
## kept for writing a mirrored picture. (Instruction names, like `jump_to`, are refused too: see `name_problem`.)
const RESERVED: Array[String] = ["self", "mirror", "mirrored"]
## How many sectors / zones a scope number can reach (a sector number is a byte). The real counts of a content set
## are checked by its tests (tests/engine/test_name_registry.gd), not here.
const SECTOR_SCOPES := 256

## The kinds. For each:
##   "scope"     a Scope
##   "scopes"    (ZONE and SECTOR only) how many scopes there are: valid scope numbers are 0 .. scopes - 1
##   "first"     the lowest and highest original number of the kind ("last"); a wider check than the real
##   "last"      content, so that it holds for every content set
##   "fallback"  the made-up name of an unnamed number, a format for one integer. Decimal everywhere: the numbers in
##               the file, in the scripts and in the file names of the assets are decimal too.
##   "what"      one line for the editor and the docs: what the number is
## The kind ids are the words the assembler's operands use.
const KINDS := {
	&"sound": {"scope": Scope.GLOBAL, "first": 0, "last": 51, "fallback": "sfx_%02d",
		"what": "sound effect: the original's common sound index (NE0SOUND 8000 + n)"},
	&"frame": {"scope": Scope.ZONE, "scopes": 7, "first": 0, "last": 127, "fallback": "frame_%03d",
		"what": "creature picture: a slot of the zone's creature set (0-27 common, 28-34 ink, 35+ the zone's own)"},
	&"deco": {"scope": Scope.ZONE, "scopes": 5, "first": 0, "last": 255, "fallback": "deco_%03d",
		"what": "decoration picture: a slot of the art zone's deco set (0-69 common, 70+ the zone's own)"},
	&"music": {"scope": Scope.GLOBAL, "first": 9500, "last": 9999, "fallback": "music_%d",
		"what": "song: the original's music id (9500-9509)"},
	&"voice": {"scope": Scope.GLOBAL, "first": 4000, "last": 4999, "fallback": "voice_%d",
		"what": "speech clip: NE1SOUND id (4000-4370)"},
	&"ui_picture": {"scope": Scope.GLOBAL, "first": 1000, "last": 2999, "fallback": "ui_%d",
		"what": "picture of the interface, the story or the console: NEP256 picture id"},
	&"problem_art": {"scope": Scope.GLOBAL, "first": 1000, "last": 2999, "fallback": "pa_%d",
		"what": "picture of a math problem's panel: NEP256 picture id"},
	&"text": {"scope": Scope.GLOBAL, "first": 0, "last": 65535, "fallback": "text_%d",
		"what": "string: its id in the original's string tables"},
	&"zone": {"scope": Scope.GLOBAL, "first": 0, "last": 15, "fallback": "zone_%d",
		"what": "zone (0-4, then the Voyager and the Expert finale)"},
	&"sector": {"scope": Scope.GLOBAL, "first": 0, "last": 255, "fallback": "sector_%02d",
		"what": "sector number"},
	&"foe": {"scope": Scope.SECTOR, "scopes": SECTOR_SCOPES, "first": 0, "last": 127, "fallback": "foe_%d",
		"what": "creature: its number in the sector's list (0-127)"},
	&"screen": {"scope": Scope.SECTOR, "scopes": SECTOR_SCOPES, "first": 0, "last": 11, "fallback": "screen_%02d",
		"what": "screen: 0-11 within the sector"},
	&"flag": {"scope": Scope.SECTOR, "scopes": SECTOR_SCOPES, "first": 0, "last": 15, "fallback": "flag_%02d",
		"what": "global flag bit 0-15 of the creature scripts: shared by all creatures of the sector, 15 ends the game"},
}

static var _original: NameRegistry
static var _name_rule: RegEx

## Everything wrong with the file this registry was read from, one line each; empty when it is sound.
## A registry with problems still answers (with what was readable), so an editor can show the problems and go on.
var problems: Array[String] = []
## kind -> scope (NO_SCOPE or a number) -> {name: original number}
var _by_name: Dictionary = {}
## kind -> scope -> {original number: name}; the same names, the other way round
var _by_index: Dictionary = {}
## kind -> the groups of numbers that hold one and the same recording (the file's "same_audio"), each group ascending: for a
## skin or an editor, replacing one of them does not replace the others.
var _same_audio: Dictionary = {}


# =============================================================================
# Loading
# =============================================================================

## The name store of the original game (`STORE_PATH`), read once.
static func original() -> NameRegistry:
	if _original == null:
		_original = from_file(STORE_PATH)
	return _original


## A registry from a file. A missing or unreadable file gives an empty registry with a problem
## (every number then still has its fallback name).
static func from_file(path: String) -> NameRegistry:
	if not FileAccess.file_exists(path):
		var missing := NameRegistry.new()
		missing.problems.append("%s: no such file" % path)
		return missing
	return parse(FileAccess.get_file_as_string(path))


## A registry from the text of a name file. Whatever is wrong is listed in `problems`.
static func parse(text: String) -> NameRegistry:
	var registry := NameRegistry.new()
	var json := JSON.new()
	if json.parse(text) != OK:
		registry.problems.append("not JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
		return registry
	if not json.data is Dictionary:
		registry.problems.append("the file is not a JSON object")
		return registry
	var root: Dictionary = json.data
	if int(root.get("format", 0)) != FORMAT:
		registry.problems.append("format %s, this reader reads format %d" % [str(root.get("format")), FORMAT])
	var by_kind: Variant = root.get("names")
	if not by_kind is Dictionary:
		registry.problems.append("\"names\" is missing or not an object")
		return registry
	for kind: String in by_kind:
		if not KINDS.has(StringName(kind)):
			registry.problems.append("unknown kind '%s' (the kinds are %s)" % [kind, _kind_list()])
			continue
		registry._add_kind(StringName(kind), by_kind[kind])
	registry._check_visible_together()
	registry._add_same_audio(root.get("same_audio"))
	return registry


## Reads the tables of one kind: a global kind is {name: number}, a scoped one {scope: {name: number}}.
func _add_kind(kind: StringName, tables: Variant) -> void:
	if not tables is Dictionary:
		problems.append("%s: expected an object" % kind)
		return
	if KINDS[kind]["scope"] == Scope.GLOBAL:
		_add_table(kind, NO_SCOPE, tables)
		return
	for key: String in tables:
		var scope := NO_SCOPE
		if key != COMMON_KEY:
			if not key.is_valid_int() or str(key.to_int()) != key or not _scope_exists(KINDS[kind], key.to_int()):
				problems.append("%s: '%s' is not a scope (%s)" % [kind, key, _scope_help(kind)])
				continue
			scope = key.to_int()
		if not tables[key] is Dictionary:
			problems.append("%s %s: expected an object of names" % [kind, _scope_text(kind, scope)])
			continue
		_add_table(kind, scope, tables[key])


## Reads the names of one table, one by one; a name that is wrong is reported and left out.
func _add_table(kind: StringName, scope: int, table: Dictionary) -> void:
	var def: Dictionary = KINDS[kind]
	var where := "%s %s" % [kind, _scope_text(kind, scope)] if def["scope"] != Scope.GLOBAL else str(kind)
	var by_name: Dictionary = {}
	var by_index: Dictionary = {}
	for name: String in table:
		var value: Variant = table[name]
		var wrong := name_problem(name)
		if wrong.is_empty() and fallback_index(kind, name) >= 0:
			wrong = "is the made-up name of number %d (names like %s are kept for numbers nobody named)" % [fallback_index(kind, name), fallback_name(kind, fallback_index(kind, name))]
		if not wrong.is_empty():
			problems.append("%s: '%s' %s" % [where, name, wrong])
			continue
		if not (value is float or value is int) or float(value) != floorf(float(value)):
			problems.append("%s: '%s' should be a whole number, got %s" % [where, name, str(value)])
			continue
		var index := int(value)
		if index < def["first"] or index > def["last"]:
			problems.append("%s: '%s' is %d, outside %d to %d" % [where, name, index, def["first"], def["last"]])
			continue
		if by_index.has(index):
			problems.append("%s: '%s' and '%s' are both %d (one number, one name)" % [where, by_index[index], name, index])
			continue
		by_name[name] = index
		by_index[index] = name
	if not _by_name.has(kind):
		_by_name[kind] = {}
		_by_index[kind] = {}
	_by_name[kind][scope] = by_name
	_by_index[kind][scope] = by_index


## A name must be unique among the names that are valid together: a scope's own and the common ones. Also one
## number must have one name there, or the way back would not know which to print.
func _check_visible_together() -> void:
	for kind: StringName in _by_name:
		if KINDS[kind]["scope"] == Scope.GLOBAL or not _by_name[kind].has(NO_SCOPE):
			continue
		var common: Dictionary = _by_name[kind][NO_SCOPE]
		for scope: int in _by_name[kind]:
			if scope == NO_SCOPE:
				continue
			for name: String in _by_name[kind][scope]:
				var index: int = _by_name[kind][scope][name]
				if common.has(name):
					problems.append("%s %s: '%s' is also a common name" % [kind, _scope_text(kind, scope), name])
				if _by_index[kind][NO_SCOPE].has(index):
					problems.append("%s %s: %d is named '%s' and also '%s' (common)" % [kind, _scope_text(kind, scope), index, name, _by_index[kind][NO_SCOPE][index]])


## Reads "same_audio": {kind: [[number, number, ...], ...]}, the numbers of one kind that hold one and the same recording
## (the original stores some sounds twice under two numbers, and a script plays one or the other). Every group has at least
## two numbers that exist in the kind, and a number is in one group only. Whatever is wrong is reported and left out.
func _add_same_audio(value: Variant) -> void:
	if value == null:
		return
	if not value is Dictionary:
		problems.append("same_audio: expected an object")
		return
	for kind_key: String in value:
		var kind := StringName(kind_key)
		if not KINDS.has(kind):
			problems.append("same_audio: unknown kind '%s' (the kinds are %s)" % [kind_key, _kind_list()])
			continue
		if not value[kind_key] is Array:
			problems.append("same_audio %s: expected a list of groups" % kind)
			continue
		var groups: Array[Array] = []
		var used: Dictionary = {}
		for group: Variant in value[kind_key]:
			var numbers := _group_numbers(kind, group)
			if numbers.size() < 2:
				problems.append("same_audio %s: %s is not a group of two or more different numbers of the kind" % [kind, str(group)])
				continue
			var twice := numbers.filter(func(number: int) -> bool: return used.has(number))
			if not twice.is_empty():
				problems.append("same_audio %s: %d is in more than one group" % [kind, twice[0]])
				continue
			for number in numbers:
				used[number] = true
			groups.append(numbers)
		groups.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		_same_audio[kind] = groups


## The numbers of one group of "same_audio", ascending; empty when it is not a list of different whole numbers of the kind.
func _group_numbers(kind: StringName, group: Variant) -> Array[int]:
	var numbers: Array[int] = []
	var none: Array[int] = []
	if not group is Array:
		return none
	for number: Variant in group:
		if not (number is int or number is float) or float(number) != floorf(float(number)):
			return none
		var index := int(number)
		if index < KINDS[kind]["first"] or index > KINDS[kind]["last"] or numbers.has(index):
			return none
		numbers.append(index)
	numbers.sort()
	return numbers


# =============================================================================
# The kinds
# =============================================================================

## Every kind id, in the order of the docs.
static func kinds() -> Array[StringName]:
	var found: Array[StringName] = []
	for kind: StringName in KINDS:
		found.append(kind)
	return found


static func _kind_list() -> String:
	var found := PackedStringArray()
	for kind: StringName in KINDS:
		found.append(String(kind))
	return ", ".join(found)


## Does a name of this kind belong to a zone or a sector (so that a lookup needs a scope)?
static func is_scoped(kind: StringName) -> bool:
	return KINDS.has(kind) and KINDS[kind]["scope"] != Scope.GLOBAL


## How many scopes a scoped kind has (7 zones, 5 art zones, 256 sectors); 0 for a global kind.
static func scope_count(kind: StringName) -> int:
	return KINDS[kind].get("scopes", 0) if KINDS.has(kind) else 0


# =============================================================================
# Names and numbers
# =============================================================================

## The number called `name`, or -1. For a scoped kind `scope` is the zone or sector the name is used in: the
## names of that scope and the common ones count. The made-up name of a number (`fallback_name`) always
## counts, even where the number has been given a real name since, so a script that used it keeps working.
func index_of(kind: StringName, name: String, scope: int = NO_SCOPE) -> int:
	if not KINDS.has(kind) or not _scope_ok(kind, scope):
		return -1
	for table_scope in _visible_scopes(kind, scope):
		var table: Dictionary = _by_name.get(kind, {}).get(table_scope, {})
		if table.has(name):
			return table[name]
	return fallback_index(kind, name)


## The name of number `index`: the one it was given, else its made-up name. "" only for a number that cannot
## exist in this kind at all (outside "first" .. "last"), so every number a file can hold has a name.
func name_of(kind: StringName, index: int, scope: int = NO_SCOPE) -> String:
	if not KINDS.has(kind) or not _scope_ok(kind, scope):
		return ""
	for table_scope in _visible_scopes(kind, scope):
		var table: Dictionary = _by_index.get(kind, {}).get(table_scope, {})
		if table.has(index):
			return table[index]
	return fallback_name(kind, index)


## Does `name` mean a number of this kind (in this scope)? Includes the made-up names.
func has_name(kind: StringName, name: String, scope: int = NO_SCOPE) -> bool:
	return index_of(kind, name, scope) >= 0


## Was number `index` given a real name (in this scope or common), not just a made-up one?
func is_named(kind: StringName, index: int, scope: int = NO_SCOPE) -> bool:
	if not KINDS.has(kind) or not _scope_ok(kind, scope):
		return false
	for table_scope in _visible_scopes(kind, scope):
		if _by_index.get(kind, {}).get(table_scope, {}).has(index):
			return true
	return false


## The real names usable in this scope (its own and the common ones) in the order of their numbers: what a
## completion list offers. The made-up names are not in it.
func names(kind: StringName, scope: int = NO_SCOPE) -> PackedStringArray:
	return PackedStringArray(entries(kind, scope).keys())


## The same as a Dictionary name -> number, in the order of the numbers.
func entries(kind: StringName, scope: int = NO_SCOPE) -> Dictionary:
	var by_index: Dictionary = {}
	if KINDS.has(kind) and _scope_ok(kind, scope):
		for table_scope in _visible_scopes(kind, scope):
			by_index.merge(_by_index.get(kind, {}).get(table_scope, {}))
	var numbers: Array = by_index.keys()
	numbers.sort()
	var found: Dictionary = {}
	for number: int in numbers:
		found[by_index[number]] = number
	return found


## The scopes of a scoped kind that have names of their own (not counting the common ones), ascending.
func named_scopes(kind: StringName) -> Array[int]:
	var found: Array[int] = []
	for scope: int in _by_name.get(kind, {}):
		if scope != NO_SCOPE and not _by_name[kind][scope].is_empty():
			found.append(scope)
	found.sort()
	return found


## Why `name` is not a name of this kind in this scope, in words for the person who typed it ("unknown sound
## 'bgin' (did you mean 'begin'?)"); "" when the name is fine.
func explain_unknown(kind: StringName, name: String, scope: int = NO_SCOPE) -> String:
	if not KINDS.has(kind):
		return "unknown kind '%s' (the kinds are %s)" % [kind, _kind_list()]
	if not _scope_ok(kind, scope):
		return "%s names belong to %s (%s), got %d" % [kind, _scope_noun(kind), _scope_help(kind), scope]
	if index_of(kind, name, scope) >= 0:
		return ""
	var text := "unknown %s '%s'" % [kind, name]
	var wrong := name_problem(name)
	if not wrong.is_empty():
		return "'%s' %s" % [name, wrong]
	# The same name in another scope is the likely mistake for a scoped kind.
	if is_scoped(kind):
		for other in named_scopes(kind):
			if other != scope and _by_name[kind][other].has(name):
				return "%s here; there is one in %s %d (names of that scope work only there)" % [text, _scope_noun(kind), other]
	var best := ""
	var best_score := 0.5
	for known in names(kind, scope):
		var score := known.similarity(name)
		if score > best_score:
			best = known
			best_score = score
	return "%s (did you mean '%s'?)" % [text, best] if not best.is_empty() else text


# =============================================================================
# Recordings stored twice
# =============================================================================

## The other numbers of `kind` that hold the very same recording as `index`, ascending; empty when it is the only one.
## The creature scripts of the original play the twins by different numbers (sounds 6, 20 and 21 are one recording), so a
## skin that replaces one of them should know about the others.
func same_audio(kind: StringName, index: int) -> Array[int]:
	var others: Array[int] = []
	for group in same_audio_groups(kind):
		if group.has(index):
			others.assign(group.filter(func(number: int) -> bool: return number != index))
	return others


## Every group of numbers of `kind` that share one recording, each ascending, in the order of their lowest numbers.
func same_audio_groups(kind: StringName) -> Array[Array]:
	var groups: Array[Array] = []
	groups.assign(_same_audio.get(kind, []))
	return groups


# =============================================================================
# Made-up names
# =============================================================================

## The name of a number nobody named: "sfx_28", "frame_040", "sector_07" ... (`KINDS[kind]["fallback"]`).
## "" for a number outside the kind.
static func fallback_name(kind: StringName, index: int) -> String:
	if not KINDS.has(kind) or index < KINDS[kind]["first"] or index > KINDS[kind]["last"]:
		return ""
	return String(KINDS[kind]["fallback"]) % index


## The number a made-up name stands for, or -1. Only the exact spelling `fallback_name` writes counts:
## "sfx_28", not "sfx_028" or "sfx_+28".
static func fallback_index(kind: StringName, name: String) -> int:
	if not KINDS.has(kind):
		return -1
	var pattern: String = KINDS[kind]["fallback"]
	var prefix := pattern.substr(0, pattern.find("%"))
	if not name.begins_with(prefix):
		return -1
	var digits := name.substr(prefix.length())
	if digits.is_empty() or not digits.is_valid_int():
		return -1
	var index := digits.to_int()
	return index if fallback_name(kind, index) == name else -1


# =============================================================================
# The naming convention
# =============================================================================

## Why `name` cannot be a name, or "" when it can. The rule: lowercase letters, digits and underscores, starting
## with a letter, at most MAX_NAME_LENGTH long. Such a word can never be read as a number, as `self+N` or as a label
## (`name:` ends with a colon), so an assembler operand is never ambiguous. Not allowed besides: the RESERVED words
## and the names of instructions. A name must also not look like a made-up name; that depends on the kind
## and is checked when a file is read.
static func name_problem(name: String) -> String:
	if name.is_empty():
		return "is empty"
	if name.length() > MAX_NAME_LENGTH:
		return "is longer than %d characters" % MAX_NAME_LENGTH
	if _rule().search(name) == null:
		return "is not a valid name (lowercase letters, digits and underscores, starting with a letter)"
	if RESERVED.has(name):
		return "is a reserved word"
	if FoeOps.op_from_mnemonic(name) >= 0:
		return "is the name of an instruction"
	return ""


static func is_valid_name(name: String) -> bool:
	return name_problem(name).is_empty()


static func _rule() -> RegEx:
	if _name_rule == null:
		_name_rule = RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return _name_rule


# =============================================================================
# Scopes
# =============================================================================

## The tables that count for a lookup in `scope`, most specific first: the scope's own, then the common ones.
func _visible_scopes(kind: StringName, scope: int) -> Array[int]:
	if KINDS[kind]["scope"] == Scope.GLOBAL or scope == NO_SCOPE:
		return [NO_SCOPE]
	return [scope, NO_SCOPE]


## Is `scope` a scope this kind has (or NO_SCOPE, which every kind takes)?
static func _scope_ok(kind: StringName, scope: int) -> bool:
	return scope == NO_SCOPE or (KINDS[kind]["scope"] != Scope.GLOBAL and _scope_exists(KINDS[kind], scope))


static func _scope_exists(def: Dictionary, scope: int) -> bool:
	return scope >= 0 and scope < int(def.get("scopes", 0))


static func _scope_noun(kind: StringName) -> String:
	return "a zone" if KINDS[kind]["scope"] == Scope.ZONE else "a sector"


static func _scope_help(kind: StringName) -> String:
	if KINDS[kind]["scope"] == Scope.GLOBAL:
		return "this kind has no scopes"
	return "%d to %d, or \"%s\"" % [0, int(KINDS[kind]["scopes"]) - 1, COMMON_KEY]


static func _scope_text(kind: StringName, scope: int) -> String:
	if scope == NO_SCOPE:
		return COMMON_KEY
	return ("zone %d" if KINDS[kind]["scope"] == Scope.ZONE else "sector %d") % scope
