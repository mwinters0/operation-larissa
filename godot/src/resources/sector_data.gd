@tool
class_name SectorData
extends Resource
## A whole sector: 12 screens, collectibles, creatures and neighbour tables.
##
## Teaches: `class_name`, `@export`, typed arrays; data authored (here:
## generated) outside the code and edited in the Inspector; SOURCE versus
## COMPILED data: the creature script is stored as readable text (a `.foe` file, loaded
## as a `FoeScript`) and turned into bytes when the game needs it (`compile`), like a
## program and its executable; and an encoder with validation, like `ScreenData`'s:
## `encode()` rebuilds the original's 0x72-byte sector HEADER from the editable fields and
## `encode_resource()` the whole 0x3E00-byte resource (header, 12 screen records, zero
## tail). tests/legacy/test_sector_header_fidelity.gd compares their hashes with the original's. The creatures' 34-byte
## records are rebuilt the same way, `encode_foe_records()` (each `FoeData.encode()`, once the script is compiled so that
## the entry points are numbers); tests/legacy/test_foe_record_fidelity.gd compares their hashes with the original's.
##
## THE HEADER (DESIGN 4.1), 0x72 bytes at the start of a sector's data:
##   0x00 u16 start x / 2     0x02 u16 start y / 2     0x04 u16 piece count (at most 11)
##   0x06 u8[11] piece screen     0x11 u16[11] piece x / 2     0x27 u16[11] piece y / 2
##   0x3D u8 unused           0x3E u16 start frame     0x40 u8 unused     0x41 u8 unused
##   0x42 u8[12] left neighbour   0x4E right   0x5A up   0x66 down     each: destination screen + 1, 0 = none
## Every byte is stored in some field, so `encode()` gives the original header back exactly. Three of the
## fields are stored in a more convenient form than the file's: positions are in pixels (the file halves
## them), neighbours are the destination screen or -1 (the file adds one), and `pieces` holds only the pieces
## that exist (the file has 11 entries and a count). `encode()` undoes each of those exactly, and
## `header_problems()` refuses the values that have no such form (an odd position, a neighbour of 12, ...).

## Size of the header, of the whole resource (header, 12 records of 0x500, then a zero tail up to 0x3E00) and the
## number of piece slots in the header.
const HEADER_SIZE := 0x72
const RESOURCE_SIZE := 0x3E00
const SCREEN_COUNT := 12
const MAX_PIECES := 11
## The most creatures a sector can have: the foe buffer starts with ONE count byte (DESIGN 3.5). The original's sectors have
## 21 to 29. A script can only NAME the creatures 0 to `FoeOps.FOE_MAX` (127) in `Put_Foe_To_Sleep` / `Wake_Foe` (the operand's bit 7
## means "relative to me"); a creature beyond that still runs, it just cannot be put to sleep by number (`foe_notes`).
const MAX_FOES := 255

## 0-14 Voyager, 15-29 Expert, 30 Voyager finale, 31 Expert finale (a campaign's own sectors have higher numbers).
@export var index: int = 0
## 0 = Voyager, 1 = Expert. The original's two games only: a sector's game is the `Campaign` that lists it (`Catalog.campaign_of_sector`),
## which is what the code asks; this field is kept for the importer's data and the debug views.
@export var game: int = 0
## Index into zones.tres (0-4 normal, 5/6 finale).
@export var zone: int = 0
## The screen (0-11) on which the closing sequence starts once the creature that holds the treasure has set semaphore bit 15 (`SimWorld`,
## DESIGN 2 item 9), or -1 for an ordinary sector. The original hard-codes it in `DoAction` for its two finale sectors: screen 2 in sector
## 30, screen 10 in sector 31. A campaign's finale sector (`Campaign.finales`) sets it.
@export var finale_screen: int = -1
## Where the sub starts (playfield pixels, even numbers: the file stores half) and which sub frame it shows.
@export var start_pos: Vector2i = Vector2i.ZERO
@export var start_frame: int = 0
## Destination screen when leaving through a side, or -1 for "no neighbour".
## One entry per screen (12). The file stores "destination + 1", with 0 meaning none; `encode()` adds the 1 again.
@export var neighbors_left: PackedInt32Array = PackedInt32Array()
@export var neighbors_right: PackedInt32Array = PackedInt32Array()
@export var neighbors_up: PackedInt32Array = PackedInt32Array()
@export var neighbors_down: PackedInt32Array = PackedInt32Array()
## Pieces to collect; element 0 is the data canister. These are the ACTIVE pieces: the header counts them
## (`n_pieces`) and the game uses exactly this many. The header has room for 11 entries; see `stale_pieces`
## for the others.
@export var pieces: Array[PieceData] = []
## Leftover entries in the piece slots the game does not use (slot number >= the number of `pieces`), four numbers
## each: slot, screen, x, y (pixels, like `PieceData`). Empty for 30 of the 32 original sectors; sectors 6 and 22 have
## one each (slot 7, slot 9). Every loop of the game over the pieces stops at the piece count, so it never reads them. Like `ScreenData.stale_bytes` they look like left-overs of an earlier version of the data and the game
## never reads them, but the original header holds them, so they are kept to rebuild it byte for byte.
##
## Why a separate sparse list and not more `PieceData`: `pieces` keeps its meaning (every element is a piece the
## player can take, and the screen editor and the game loop over it), and the 31 sectors without stale entries
## store nothing extra (the unused slots are zero). A slot is named by its absolute number, so a designer who adds
## a piece to the sector simply overwrites that slot when encoding, as a grown screen overwrites its stale bytes.
## Not something to edit.
@export var stale_pieces: PackedInt32Array = PackedInt32Array()
@export var screens: Array[ScreenData] = []
@export var foes: Array[FoeData] = []
## The creatures' program, as text, in its own file `data/sectors/sector_NN/sector_NN.foe`
## (the language is explained in docs/create/FOE_SCRIPTING.md). This is the STORED version:
## edit the file (Godot's script editor opens it with a double click, or any text
## editor) and the change takes effect the next time the game runs. The bytes the VM
## executes are built from it. Plain text diffs and blames well in git, which is why it
## is not a text box inside this `.tres`.
@export var foe_script: FoeScript
## The ORIGINAL foe-buffer offset of the script's first byte. Labels are assembled
## to offsets starting here, so debug displays and tests keep using the offsets of
## the original game.
@export var foe_script_base: int = 0
## Background music: the stem of the song's MIDI file, e.g. "esect1" (the song is an OGG called `<song name>_<id>.ogg` in assets/audio/music: `MusicCatalog`).
@export var music_name: String = ""
## Header byte 0x3D: never read by the game (the EXE's `SectorHeaderUnused3D`), kept for byte fidelity. 11 in sectors
## 0-10 and 12-24, 0 in the others.
@export var header_unused_3d: int = 0
## Header byte 0x40: never read by the game (`SectorHeaderUnused40`), kept for byte fidelity. 72 (0x48) in the same
## sectors as `header_unused_3d`, 0 in the others.
@export var header_unused_40: int = 0
## Header byte 0x41: never read by the game (`SectorHeaderUnused41`), kept for byte fidelity. Always 0 in the original.
@export var header_unused_41: int = 0

## What the last `compile` found, one "line N: ..." (or "foe N field: ...") message
## per problem. Empty when the script is fine.
var compile_errors: Array[String] = []

## What the compiled script was made from (`_compile_inputs`). The compiled bytes, labels, source map and the creatures' entry points
## are a cache KEYED by it: any change of the text, the base, the list of creatures or a creature's label compiles again on next use,
## whoever made the change (an editor, a reload from disk with `CACHE_MODE_REPLACE`, a test).
var _compiled_from: Array = []
var _foe_bytecode: PackedByteArray = PackedByteArray()
var _foe_labels: Dictionary = {}
var _foe_source_map: FoeSourceMap = null

enum Direction { LEFT, RIGHT, UP, DOWN }

## The script bytes (opcodes, see DESIGN 3.5) built from `foe_script`; byte 0
## sits at buffer offset `foe_script_base`. Compiled on first use. Empty if the
## source has errors.
var foe_bytecode: PackedByteArray:
	get:
		ensure_compiled()
		return _foe_bytecode

## Label name -> buffer offset, for debug displays (FoeAsm.instruction_text).
var foe_labels: Dictionary:
	get:
		ensure_compiled()
		return _foe_labels


## Which `.foe` line every instruction came from, for debug displays: `foe_source_map.line_of(creature.pc)`.
var foe_source_map: FoeSourceMap:
	get:
		ensure_compiled()
		return _foe_source_map


## The `.foe` line (1-based) of the instruction at buffer offset `pc`, e.g. a creature's live program counter; 0 if none.
func foe_line_of(pc: int) -> int:
	return foe_source_map.line_of(pc)


## Compiles the script once; later calls do nothing until something it is made from changes (`_compile_inputs`: the text, the base,
## the creatures and their labels). Everything that wants the bytes or the creatures' pc / script_hit / script_ink goes through here
## first (Catalog.sector and FoeVM.from_data do).
func ensure_compiled() -> void:
	if _compiled_from != _compile_inputs():
		compile()


## Everything the compiled script derives from, as one Array that `==` compares: the `FoeScript` and its text, the base, and every
## creature record (the object: a new record must get its entry points) with its three labels.
func _compile_inputs() -> Array:
	var inputs: Array = [foe_script, foe_script.source if foe_script != null else "", foe_script_base, foes.size()]
	for foe in foes:
		if foe == null:
			inputs.append_array([null, "", "", ""])
		else:
			inputs.append_array([foe, foe.start_label, foe.hit_label, foe.ink_label])
	return inputs


## Assembles `foe_script.source`, fills in every creature's `pc`, `script_hit` and
## `script_ink` from its labels, and returns the problems. A problem is also reported
## with push_error, naming this resource. When there are problems NO creature gets a
## script (the bytes stay empty and the offsets 0), and FoeVM.from_data makes every
## creature of this sector fault with the first message, so nothing runs on garbage.
func compile() -> Array[String]:
	_compiled_from = _compile_inputs()
	_foe_bytecode = PackedByteArray()
	_foe_labels = {}
	var source := foe_script.source if foe_script != null else ""
	var result := FoeAsm.assemble(source, foe_script_base, FoeNames.for_sector(self))
	_foe_source_map = FoeSourceMap.from_result(source, result)
	var errors: Array[String] = result.errors.duplicate()
	if errors.is_empty():
		for i in foes.size():
			var foe := foes[i]
			foe.pc = _entry(result.labels, i, "start_label", foe.start_label, errors)
			foe.script_hit = _entry(result.labels, i, "hit_label", foe.hit_label, errors)
			foe.script_ink = _entry(result.labels, i, "ink_label", foe.ink_label, errors)
	if errors.is_empty():
		_foe_bytecode = result.bytes
		_foe_labels = result.labels
	else:
		for foe in foes:
			foe.pc = 0
			foe.script_hit = 0
			foe.script_ink = 0
	compile_errors = errors
	for message in errors:
		push_error("%s: foe script: %s" % [describe(), message])
	return errors


## "SectorData res://packs/legacy/data/sectors/sector_00/sector_00.tres (sector 0)", for messages.
func describe() -> String:
	return "SectorData %s (sector %d)" % [resource_path if not resource_path.is_empty() else "<not saved>", index]


## The buffer offset of `label`, or 0 with a message added to `errors`.
func _entry(labels: Dictionary, foe_index: int, field: String, label: String, errors: Array[String]) -> int:
	if labels.has(label):
		return labels[label]
	if label.is_empty():
		errors.append("foe %d %s is empty; name a label of the script" % [foe_index, field])
	else:
		errors.append("foe %d %s: unknown label '%s'" % [foe_index, field, label])
	return 0


## Screen reached from `screen_index` by moving in `direction`, or -1.
func neighbor(screen_index: int, direction: Direction) -> int:
	match direction:
		Direction.LEFT:
			return neighbors_left[screen_index]
		Direction.RIGHT:
			return neighbors_right[screen_index]
		Direction.UP:
			return neighbors_up[screen_index]
		_:
			return neighbors_down[screen_index]


# --- adding and removing pieces and creatures ---------------------------------------------------------------------
##
## Plain functions on the data, with no editor in them: the Sector Inspector calls them (inside an undo action), the screen
## editor's creature markers can call them, and so can a test or a script. Each returns the PROBLEMS in plain words and changes
## nothing when there are any, so `if not sector.add_piece(3, pos).is_empty(): show them` is the whole error handling.
## A change emits `changed`.
##
## PIECES are known by their number in `pieces` (slot k of the header, bit k of the run's collected-pieces mask,
## `PieceModel.index`). Piece 0 is the data canister: the first piece of the list is the one the game starts the canister's
## problem for, so it can be removed only when it is the last piece left, and nothing can be put in front of it. The rest
## can be added at the end (the default) or inserted, and removed anywhere: the pieces after a removed one move up a number.
## Nothing else in the data refers to a piece by number (the triggers use their own slots), only the run does: the collected
## mask of a game in progress, saved with the player's record. `pieces_mask_after_remove` / `pieces_mask_after_insert` give the
## mask of such a game for the changed sector. A slot freed by a removal is zero in the header, except where `stale_pieces`
## keeps the original's left-over (so adding a piece and removing it again gives the original header back).
##
## CREATURES are known by their number in `foes` too, and that number is written in the creature SCRIPT: `Put_Foe_To_Sleep` and
## `Wake_Foe` take a creature number (or a name from the registry, which stands for a number) or "self+N". Insert or remove a
## creature anywhere but at the end and every number after it changes, so the decision is: THE EDIT IS REFUSED while the script
## depends on the numbers it would change, and the message names the script line. Removing the last creature (or adding one at
## the end, the default) renumbers nothing and is refused only if the script names the removed one. Nothing is renumbered
## behind the designer's back, and `names/original.json` (which names the original sectors' creatures) is never touched.
## Edit the script first, then the creature. The creature records follow the count byte and the script follows the records
## (`encode_foe_buffer`), so every change of the count moves `foe_script_base` by `FoeData.RECORD_SIZE`: the script text
## uses labels, so it needs no edit for that. In the finale sectors creature 0 is the treasure (`ReachSweep`): it stays.


## Adds a piece lying at `pos` (window pixels, even numbers) on `screen`, as piece number `at` (default: the end).
func add_piece(screen: int, pos: Vector2i, at := -1) -> Array[String]:
	var piece := PieceData.new()
	piece.screen = screen
	piece.pos = pos
	return insert_piece(piece, at)


## `add_piece` for a piece that exists already (the undo of a removal puts the same object back).
func insert_piece(piece: PieceData, at := -1) -> Array[String]:
	var found: Array[String] = []
	if piece == null:
		found.append("there is no piece to add")
		return found
	if at < 0:
		at = pieces.size()
	if pieces.size() >= MAX_PIECES:
		found.append("a sector has room for %d pieces (the header has %d slots), so no piece can be added" % [MAX_PIECES, MAX_PIECES])
	if at > pieces.size():
		found.append("piece %d: the sector has only %d pieces, so a piece can be put at 0 to %d" % [at, pieces.size(), pieces.size()])
	elif at == 0 and not pieces.is_empty():
		found.append("piece 0 is the data canister: a piece can not be put in front of it")
	if piece.screen < 0 or piece.screen >= SCREEN_COUNT:
		found.append("screen %d: a sector has the screens 0 to %d" % [piece.screen, SCREEN_COUNT - 1])
	found.append_array(_position_problems(piece.pos, "the piece's"))
	if not found.is_empty():
		return found
	piece.is_canister = at == 0
	pieces.insert(at, piece)
	emit_changed()
	return found


## Removes piece `number`. The pieces after it move up a number. The data canister (piece 0) goes only when it is the only piece.
func remove_piece(number: int) -> Array[String]:
	var found: Array[String] = []
	if number < 0 or number >= pieces.size():
		found.append("piece %d does not exist: the sector has %d pieces" % [number, pieces.size()])
	elif number == 0 and pieces.size() > 1:
		found.append("piece 0 is the data canister: the game counts on it, so it can be removed only when no other piece is left")
	if not found.is_empty():
		return found
	pieces.remove_at(number)
	emit_changed()
	return found


## The collected-pieces mask (bit k set = piece k taken, `GameState.pieces_mask`) of a game in progress, for the sector after
## `remove_piece(index)`: the bits above `index` move down one place, the removed piece's bit goes.
static func pieces_mask_after_remove(mask: int, index: int) -> int:
	return (mask & ((1 << index) - 1)) | ((mask >> (index + 1)) << index)


## The same after `insert_piece` at `at`: the bits from `at` move up one place, the new piece is not taken.
static func pieces_mask_after_insert(mask: int, at: int) -> int:
	return (mask & ((1 << at) - 1)) | ((mask >> at) << (at + 1))


## Adds a creature on `screen` at `pos` (window pixels, even numbers) as creature number `at` (default: the end). It starts as a
## COPY of creature `like` (its picture, damage and the three script labels, so it behaves like it), or, by default, of the first
## creature that hurts; a sector without creatures gets an empty one whose labels you must name. See the section header for the
## numbering.
func add_foe(screen: int, pos: Vector2i, like := -1, at := -1) -> Array[String]:
	return insert_foe(new_foe(screen, pos, like), at)


## The creature `add_foe` would add, not yet in the list: a copy of creature `like` (-1: the first one that hurts, else none) on
## `screen` at `pos`.
func new_foe(screen: int, pos: Vector2i, like := -1) -> FoeData:
	if like < 0:
		for k in foes.size():
			if foes[k] != null and foes[k].damage > 0:
				like = k
				break
	var foe: FoeData
	if like >= 0 and like < foes.size() and foes[like] != null:
		foe = foes[like].duplicate() as FoeData
	else:
		foe = FoeData.new()
	foe.screen = screen
	foe.pos = pos
	return foe


## `add_foe` for a creature that exists already (the undo of a removal puts the same object back).
func insert_foe(foe: FoeData, at := -1) -> Array[String]:
	var found: Array[String] = []
	if foe == null:
		found.append("there is no creature to add")
		return found
	if at < 0:
		at = foes.size()
	if foes.size() >= MAX_FOES:
		found.append("a sector has room for %d creatures (the count is one byte), so no creature can be added" % MAX_FOES)
	if at > foes.size():
		found.append("creature %d: the sector has only %d creatures, so a creature can be put at 0 to %d" % [at, foes.size(), foes.size()])
	elif at < foes.size():
		found.append_array(renumber_problems(at, true))
	if foe.screen < 0 or foe.screen >= SCREEN_COUNT:
		found.append("screen %d: a sector has the screens 0 to %d" % [foe.screen, SCREEN_COUNT - 1])
	for message in foe.problems():
		if not message.begins_with("pc ") and not message.begins_with("script_"):       # the entry points come from the script
			found.append(message)
	if not found.is_empty():
		return found
	foes.insert(at, foe)
	foe_script_base += FoeData.RECORD_SIZE
	emit_changed()
	return found


## Removes creature `number`, if the script does not depend on the numbers that change (see the section header).
func remove_foe(number: int) -> Array[String]:
	var found: Array[String] = []
	if number < 0 or number >= foes.size():
		found.append("creature %d does not exist: the sector has %d creatures" % [number, foes.size()])
		return found
	if number == 0 and finale_screen >= 0:
		found.append("creature 0 of a finale sector is the treasure the game waits for, so it stays")
	found.append_array(renumber_problems(number, false))
	if not found.is_empty():
		return found
	foes.remove_at(number)
	foe_script_base -= FoeData.RECORD_SIZE
	emit_changed()
	return found


## What would go wrong in the script if creature `at` were removed (`inserting` false) or a new creature were put at number `at`
## (`inserting` true): one message per script line that names a creature the change removes, moves to another number, or
## reaches with `self+N` from a creature (one whose entry points can reach the line) whose distance to it changes. Empty when the change is safe: always for an insertion at
## the end and for the removal of a last creature that no line names. A script that does not compile cannot be checked, which is
## a problem of its own.
func renumber_problems(at: int, inserting: bool) -> Array[String]:
	var found: Array[String] = []
	var count := foes.size()
	ensure_compiled()
	if not compile_errors.is_empty():
		found.append("the creature script does not compile (%s), so it can not be checked for creature numbers" % compile_errors[0])
		return found
	var uses := foe_operand_uses()
	var decoded: Array[Dictionary] = []
	var reach := {}                                             # "pc,hit,ink" -> the offsets a creature with those entry points can run
	for use in uses:
		var line := "line %d, %s" % [use["line"], use["instruction"]]
		var operand: int = use["operand"]
		if operand & 0x80:                                      # self+N: the creature running the line, plus N
			var offset := operand & 0x7F
			offset = offset - 128 if offset >= 64 else offset
			if offset == 0:
				continue
			if decoded.is_empty():
				decoded = FoeAsm.decode(foe_bytecode, foe_script_base)
			for who in count:
				var target := who + offset
				if target < 0 or target >= count or (not inserting and who == at):
					continue
				var key := "%d,%d,%d" % [foes[who].pc, foes[who].script_hit, foes[who].script_ink]
				if not reach.has(key):
					reach[key] = FoeAsm.reachable(decoded, [foes[who].pc, foes[who].script_hit, foes[who].script_ink])
				if not (reach[key] as Dictionary).has(use["offset"]):
					continue                                    # this creature never runs the line
				if not inserting and target == at:
					found.append("%s: self%+d of creature %d is the creature to remove" % [line, offset, who])
					break
				if _number_after(target, at, inserting) - _number_after(who, at, inserting) != offset:
					found.append("%s: self%+d would reach another creature than now, from creature %d" % [line, offset, who])
					break
		elif operand < count:
			if not inserting and operand == at:
				found.append("%s names creature %d, the one to remove" % [line, operand])
			elif _number_after(operand, at, inserting) != operand:
				found.append("%s names creature %d, which would become creature %d" % [line, operand, _number_after(operand, at, inserting)])
	return found


## The number creature `k` has after creature `at` was removed or a creature was inserted at `at`.
static func _number_after(k: int, at: int, inserting: bool) -> int:
	if inserting:
		return k + 1 if k >= at else k
	return k - 1 if k > at else k


## Every operand of the script that names a creature, as {"line": source line, "offset": buffer offset, "instruction": name,
## "operand": the stored byte (0-127 a creature number, bit 7 set: self+N)}. Empty for a script that does not assemble.
func foe_operand_uses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var result := FoeAsm.assemble(foe_script.source if foe_script != null else "", foe_script_base, FoeNames.for_sector(self))
	if not result.ok():
		return out
	for item in FoeAsm.decode(result.bytes, foe_script_base):
		if item["op"] < 0:
			continue
		var position := 0
		for part in FoeOps.operands(item["op"]):
			if part["kind"] == FoeOps.Kind.FOE:
				out.append({"line": result.instruction_lines.get(item["at"], 0), "offset": item["at"],
						"instruction": FoeOps.op_name(item["op"]), "operand": (item["operands"] as PackedByteArray)[position]})
			position += FoeOps.kind_width(part["kind"])
	return out


## Things that are allowed but worth knowing, in plain words (a problem stops an edit, a note does not).
func foe_notes() -> Array[String]:
	var found: Array[String] = []
	if foes.size() > FoeOps.FOE_MAX + 1:
		found.append("%d creatures: a script can name only the first %d by number (Put_Foe_To_Sleep, Wake_Foe)" % [foes.size(), FoeOps.FOE_MAX + 1])
	return found


# --- the original's header and resource bytes -------------------------------------------------------------------

## Everything that stops the header from being stored as the original's, in plain words; empty when it fits.
## `encode()` returns nothing while this is not empty.
func header_problems() -> Array[String]:
	var found: Array[String] = []
	found.append_array(_position_problems(start_pos, "start"))
	if start_frame < 0 or start_frame > 0xFFFF:
		found.append("start_frame %d does not fit: the original keeps it in two bytes, so 0 to 65535" % start_frame)
	if pieces.size() > MAX_PIECES:
		found.append("pieces: %d, but the header has room for %d" % [pieces.size(), MAX_PIECES])
	for i in pieces.size():
		if pieces[i] == null:
			found.append("piece %d: empty" % i)
			continue
		if pieces[i].screen < 0 or pieces[i].screen > 255:
			found.append("piece %d: screen %d does not fit: the original keeps it in one byte, so 0 to 255" % [i, pieces[i].screen])
		found.append_array(_position_problems(pieces[i].pos, "piece %d" % i))
	if stale_pieces.size() % 4 != 0:
		found.append("stale_pieces: %d numbers, but each entry is four (slot, screen, x, y)" % stale_pieces.size())
	for e in stale_pieces.size() / 4:
		var slot := stale_pieces[4 * e]
		if slot < 0 or slot >= MAX_PIECES:
			found.append("stale piece %d: slot %d does not exist, the header has slots 0 to %d" % [e, slot, MAX_PIECES - 1])
		var screen := stale_pieces[4 * e + 1]
		if screen < 0 or screen > 255:
			found.append("stale piece %d: screen %d does not fit in one byte" % [e, screen])
		found.append_array(_position_problems(Vector2i(stale_pieces[4 * e + 2], stale_pieces[4 * e + 3]), "stale piece %d" % e))
	for side in 4:
		var side_name: String = ["left", "right", "up", "down"][side]
		var table := _neighbors(side)
		if table.size() != SCREEN_COUNT:
			found.append("neighbors_%s: %d entries, but a sector has %d screens" % [side_name, table.size(), SCREEN_COUNT])
		for screen in table.size():
			if table[screen] < -1 or table[screen] >= SCREEN_COUNT:
				found.append("neighbors_%s of screen %d: %d is not a screen of the sector (0 to %d, or -1 for none)" % [side_name, screen, table[screen], SCREEN_COUNT - 1])
	for pair: Array in [["header_unused_3d", header_unused_3d], ["header_unused_40", header_unused_40], ["header_unused_41", header_unused_41]]:
		if pair[1] < 0 or pair[1] > 0xFF:
			found.append("%s %d does not fit in one byte" % pair)
	return found


## The original header: exactly HEADER_SIZE bytes, or an empty array while `header_problems()` finds problems.
## The piece slots the game does not use are zero, except the `stale_pieces` (an active piece overwrites its slot).
func encode() -> PackedByteArray:
	if not header_problems().is_empty():
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(HEADER_SIZE)
	out.encode_u16(0x00, start_pos.x / 2)
	out.encode_u16(0x02, start_pos.y / 2)
	out.encode_u16(0x04, pieces.size())
	for e in stale_pieces.size() / 4:
		_put_piece(out, stale_pieces[4 * e], stale_pieces[4 * e + 1], Vector2i(stale_pieces[4 * e + 2], stale_pieces[4 * e + 3]))
	for i in pieces.size():
		_put_piece(out, i, pieces[i].screen, pieces[i].pos)
	out[0x3D] = header_unused_3d
	out.encode_u16(0x3E, start_frame)
	out[0x40] = header_unused_40
	out[0x41] = header_unused_41
	for side in 4:
		var table := _neighbors(side)
		for screen in SCREEN_COUNT:
			out[0x42 + 12 * side + screen] = table[screen] + 1
	return out


## Everything that stops the whole resource from being stored as the original's: the header's problems, the number
## of screens, and each screen's own `validate()` messages, prefixed with the screen number.
func resource_problems() -> Array[String]:
	var found := header_problems()
	if screens.size() != SCREEN_COUNT:
		found.append("screens: %d, but a sector has %d" % [screens.size(), SCREEN_COUNT])
	for m in screens.size():
		for message in screens[m].validate():
			found.append("screen %d: %s" % [m, message])
	return found


## The whole original resource, as the game's file holds it: the header, the 12 screen records
## (`ScreenData.encode()`) and zeros up to RESOURCE_SIZE (the original's tail after the last record is zero).
## Empty while `resource_problems()` finds problems.
func encode_resource() -> PackedByteArray:
	if not resource_problems().is_empty():
		return PackedByteArray()
	var out := encode()
	for screen in screens:
		out.append_array(screen.encode())
	out.resize(RESOURCE_SIZE)
	return out


## Everything that stops the creature records from being stored as the original's: a script that does not compile (the
## records' entry points are numbers only once it does), more creatures than the count byte holds, and each creature's
## own `problems()`, prefixed with its number.
func foe_problems() -> Array[String]:
	ensure_compiled()
	var found: Array[String] = []
	for message in compile_errors:
		found.append("the creature script does not compile: %s" % message)
	if foes.size() > MAX_FOES:
		found.append("foes: %d, but the original keeps the count in one byte, so at most %d" % [foes.size(), MAX_FOES])
	for k in foes.size():
		if foes[k] == null:
			found.append("creature %d: empty" % k)
			continue
		for message in foes[k].problems():
			found.append("creature %d: %s" % [k, message])
	return found


## The original record of every creature, in order (`FoeData.RECORD_SIZE` bytes each), or an empty array while
## `foe_problems()` finds problems. The entry points come from the compiled script.
func encode_foe_records() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if not foe_problems().is_empty():
		return out
	for foe in foes:
		out.append(foe.encode())
	return out


## The whole foe buffer as the game loads it (DESIGN 3.5): the count byte, the records, then the script's bytes. Empty while
## `foe_problems()` finds problems, or when the script does not start right after the records (`foe_script_base` is
## 1 + 34 x the number of creatures in the original, and `add_foe` / `remove_foe` keep it that way).
func encode_foe_buffer() -> PackedByteArray:
	var out := PackedByteArray()
	if not foe_problems().is_empty() or foe_script_base != 1 + FoeData.RECORD_SIZE * foes.size():
		return out
	out.append(foes.size())
	for record in encode_foe_records():
		out.append_array(record)
	out.append_array(foe_bytecode)
	return out


## The neighbour table of side 0 left, 1 right, 2 up, 3 down.
func _neighbors(side: int) -> PackedInt32Array:
	match side:
		0:
			return neighbors_left
		1:
			return neighbors_right
		2:
			return neighbors_up
		_:
			return neighbors_down


## Writes piece slot `slot`: its screen byte and its x / y halves.
static func _put_piece(out: PackedByteArray, slot: int, screen: int, pos: Vector2i) -> void:
	if slot >= MAX_PIECES:
		return
	out[0x06 + slot] = screen
	out.encode_u16(0x11 + 2 * slot, pos.x / 2)
	out.encode_u16(0x27 + 2 * slot, pos.y / 2)


## Messages for a pixel position that the header stores halved in a 16-bit number (start point, pieces).
static func _position_problems(pos: Vector2i, what: String) -> Array[String]:
	var found: Array[String] = []
	for pair: Array in [["x", pos.x], ["y", pos.y]]:
		var value: int = pair[1]
		if value < 0 or value > 2 * 0xFFFF:
			found.append("%s %s %d does not fit: the original keeps %s / 2 in two bytes, so 0 to %d" % [what, pair[0], value, pair[0], 2 * 0xFFFF])
		elif value % 2 != 0:
			found.append("%s %s %d is not on the grid: the original keeps %s / 2, so it must be even" % [what, pair[0], value, pair[0]])
	return found


## The name of the header field that byte `offset` of `header` belongs to, e.g. "piece_x entry 3" or "right
## neighbour of screen 5". `header` is only needed for the piece count: entries beyond it are marked "(unused slot)".
static func field_at(header: PackedByteArray, offset: int) -> String:
	var count := header.decode_u16(4) if header.size() >= 6 else MAX_PIECES
	if offset < 0x06:
		return ["start x", "start x", "start y", "start y", "piece count", "piece count"][offset]
	if offset < 0x11:
		return "piece_screen entry %d%s" % [offset - 0x06, _unused(offset - 0x06, count)]
	if offset < 0x27:
		return "piece_x entry %d%s" % [(offset - 0x11) / 2, _unused((offset - 0x11) / 2, count)]
	if offset < 0x3D:
		return "piece_y entry %d%s" % [(offset - 0x27) / 2, _unused((offset - 0x27) / 2, count)]
	if offset == 0x3D:
		return "unused byte 0x3d"
	if offset < 0x40:
		return "start frame"
	if offset < 0x42:
		return "unused byte 0x%02x" % offset
	var side := (offset - 0x42) / 12
	return "%s neighbour of screen %d" % [["left", "right", "up", "down"][side], (offset - 0x42) % 12]


static func _unused(slot: int, count: int) -> String:
	return " (unused slot)" if slot >= count else ""


## "" when the two headers are the same, else "first difference at byte 0x3a (piece_y entry 7): expected 0x40,
## got 0x42". Names the field using the `expected` header.
static func first_difference(expected: PackedByteArray, actual: PackedByteArray) -> String:
	if actual.size() != expected.size():
		return "the header has %d bytes, expected %d" % [actual.size(), expected.size()]
	for i in expected.size():
		if expected[i] != actual[i]:
			return "first difference at byte 0x%02x (%s): expected 0x%02x, got 0x%02x" % [i, field_at(expected, i), expected[i], actual[i]]
	return ""


## The same for a whole resource: names the header field, or the screen and the field inside it
## ("screen 3 mid decos entry 2 y"), or the zero tail.
static func resource_first_difference(expected: PackedByteArray, actual: PackedByteArray) -> String:
	if actual.size() != expected.size():
		return "the resource has %d bytes, expected %d" % [actual.size(), expected.size()]
	for i in expected.size():
		if expected[i] == actual[i]:
			continue
		var where: String
		if i < HEADER_SIZE:
			where = field_at(expected, i)
		elif i < HEADER_SIZE + SCREEN_COUNT * ScreenData.RECORD_SIZE:
			var screen := (i - HEADER_SIZE) / ScreenData.RECORD_SIZE
			var start := ScreenData.original_offset(screen)
			where = "screen %d %s" % [screen, ScreenData.field_at(expected.slice(start, start + ScreenData.RECORD_SIZE), i - start)]
		else:
			where = "zero tail after the screens"
		return "first difference at byte 0x%04x (%s): expected 0x%02x, got 0x%02x" % [i, where, expected[i], actual[i]]
	return ""
