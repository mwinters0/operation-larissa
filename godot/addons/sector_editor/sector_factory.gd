@tool
class_name SectorFactory
extends RefCounted
## Makes a NEW sector: an empty one from a template, or a copy of any sector that exists. The new sector's files are
## written under the sectors folder (`Catalog.sectors_dir`, which is `Catalog.SECTORS_DIR` unless a test points it elsewhere, or a `dir` of your own: a test makes them in `user://`), and from then on
## `Catalog.sector_ids()` lists it, the editors open it and `SectorChecks` judge it.
##
## Teaches: why a sector the designers make is different from an original one, and how to make files by text. The 32 original sectors
## are written by the importer from the player's copy of the game and are guarded by hashes of the original bytes (the fidelity
## tests). A sector with a higher number has NO original bytes: its files are its own source, so nothing regenerates, resets or
## compares them (the importer and the reset tools refuse such a number, see `tools/import/common.py` `refuse_new_sectors`), and the
## only judge is the playability checks. This class never touches an original sector, and refuses a number that is taken.
##
## A SECTOR'S FILES (what `Catalog.sector_dir` names): `sector_NN/sector_NN.tres` (the header, the pieces and creatures, the neighbour
## tables, a reference to each screen and to the script), `sector_NN/sector_NN.foe` (the creature script) and
## `sector_NN/screen_00.tres` .. `screen_11.tres`. The sector file lists the other files by PATH, which is why a copy is not a file copy:
## every path inside is rewritten for the new folder. The text is written the way the importer writes it (`ScreenFile`), so the other
## editors (`ScreenFile.sector_patch`, `SectorLists`) can change the new sector's file in place afterwards.
##
## THE TEMPLATE is the smallest sector the checks accept: 12 empty screens with a floor of rock, in a chain (each screen's right link
## leads to the next one and its left link back), the start station on screen 0 and the end station on screen 11 (the game draws both
## itself, the sector only has to leave room), a data canister and one more piece, and NO creatures (an empty script). It plays: swim to
## the piece, take the canister, dock. Add rock, decorations, creatures and triggers from there, with the screen editor and the
## Sector Inspector.
##
## A COPY keeps everything of its source: the screens (with their provenance, `ScreenData.original_sector`), the creatures and
## the script with its comments. One thing is translated: the NAMES in the script. A creature, screen or flag is named per sector in
## the registry (`ray_stinger` is creature 3 of sector 3 only), and the new sector has no names of its own, so a name that would mean
## something else in the new sector is written as its number (`Wake_Foe 3`). The assembled bytes are the source's, to the byte.

## The tile of the template's floor: the solid rock that fills most of every zone's screens (`0x40` solid + picture 0x31).
const FLOOR_TILE := 0x71
## The rows of rock at the bottom of every template screen (the playfield is 18 tile rows high).
const FLOOR_ROWS := 2
## The template's first piece (the data canister) and its other piece, on screens before and after the midpoint (screen 6 in the original, `Tuning.midpoint_screen`).
const CANISTER_SCREEN := 3
const SECOND_PIECE_SCREEN := 8
const PIECE_POS := Vector2i(320, 200)
## The sub's start after a lost tank (on the midpoint screen) and the picture it shows.
const START_POS := Vector2i(96, 160)
const START_FRAME := 6


## What `new_from_template` and `new_from_copy` return.
class Made extends RefCounted:
	## The number of the new sector, or -1 when nothing was made.
	var index := -1
	## Why nothing was made ("" when the sector exists now). Nothing is left behind when this is set.
	var error := ""
	## The sector's `.tres`, and every file written.
	var path := ""
	var files: Array[String] = []

	func ok() -> bool:
		return error.is_empty()


## Why a sector `index` cannot be made under `dir` ("" when it can): the number is one of the original's, out of range, or taken.
static func refusal(index: int, dir: String = "") -> String:
	if Catalog.is_original_sector(index):
		return "sector %d is one of the original sectors (0-%d), which are never replaced; a new sector gets a number from %d up" % [index, Catalog.ORIGINAL_SECTOR_COUNT - 1, Catalog.ORIGINAL_SECTOR_COUNT]
	if index < 0 or index > Catalog.MAX_SECTOR:
		return "sector %d is out of range: a new sector is %d to %d" % [index, Catalog.ORIGINAL_SECTOR_COUNT, Catalog.MAX_SECTOR]
	if DirAccess.dir_exists_absolute(Catalog.sector_dir(index, dir)) or Catalog.has_sector(index, dir):
		return "sector %d exists already (%s)" % [index, Catalog.sector_dir(index, dir)]
	return ""


## The number a new sector gets when none is asked for (`index` < 0), or `index`: -1 and an error in `made` when there is none.
static func _number(index: int, dir: String, made: Made) -> int:
	if index < 0:
		index = Catalog.next_free_sector(dir)
		if index < 0:
			made.error = "all the sector numbers up to %d are taken" % Catalog.MAX_SECTOR
			return -1
	made.error = refusal(index, dir)
	return -1 if not made.ok() else index


# =====================================================================================================================
# From the template
# =====================================================================================================================

## Makes the empty sector `index` (default: the next free number) in `zone` (0-6, the pictures of the tiles, decorations and creatures)
## of `game` (0 Voyager, 1 Expert). See the class comment for what is in it.
static func new_from_template(index: int = -1, zone: int = 0, game: int = 0, dir: String = "") -> Made:
	var made := Made.new()
	index = _number(index, dir, made)
	if not made.ok():
		return made
	if zone < 0 or zone >= Catalog.ZONE_COUNT:
		made.error = "zone %d does not exist: there are %d zones (0 to %d)" % [zone, Catalog.ZONE_COUNT, Catalog.ZONE_COUNT - 1]
		return made
	if game < 0 or game > 1:
		made.error = "game %d is not 0 (Voyager) or 1 (Expert)" % game
		return made
	var files: Dictionary = {}                                   # path -> text
	files[Catalog.sector_path(index, dir)] = template_sector_text(index, zone, game, dir)
	files[Catalog.foe_path(index, dir)] = template_script_text(index)
	for m in SectorData.SCREEN_COUNT:
		files[ScreenFile.screen_path(dir, index, m)] = ScreenFile.screen_text(template_screen())
	return _write_all(made, index, dir, files)


## One empty screen of the template: a floor of rock and nothing else.
static func template_screen() -> ScreenData:
	var screen := ScreenData.new()
	var tiles := PackedByteArray()
	tiles.resize(ScreenData.TILE_BYTES)
	for row in range(ScreenData.TILE_ROWS - FLOOR_ROWS, ScreenData.TILE_ROWS):
		for column in ScreenData.TILE_COLUMNS:
			tiles[row * ScreenData.TILE_COLUMNS + column] = FLOOR_TILE
	screen.tiles = tiles
	return screen


## The text of the template's `sector_NN.tres`, in the importer's format (tools/import/step_sectors.py `build_sector`).
static func template_sector_text(index: int, zone: int, game: int, dir: String) -> String:
	var folder := Catalog.sector_dir(index, dir)
	var lines: Array[String] = ['[gd_resource type="Resource" script_class="SectorData" format=3]', ""]
	for pair: Array in [["sector_data", 1], ["piece_data", 2], ["foe_data", 3], ["screen_data", 4]]:
		lines.append('[ext_resource type="Script" path="%s%s.gd" id="%d_%s"]' % [ScreenFile.SCRIPTS, pair[0], pair[1], pair[0]])
	var screen_refs: Array[String] = []
	for m in SectorData.SCREEN_COUNT:
		lines.append('[ext_resource type="Resource" path="%s/screen_%02d.tres" id="%d_screen_%02d"]' % [folder, m, 5 + m, m])
		screen_refs.append('ExtResource("%d_screen_%02d")' % [5 + m, m])
	lines.append('[ext_resource type="Resource" path="%s" id="17_sector_%02d"]' % [Catalog.foe_path(index, dir), index])
	lines.append("")
	var piece_refs: Array[String] = []
	for k in 2:
		piece_refs.append('SubResource("Piece_%d")' % (k + 1))
		lines.append_array(['[sub_resource type="Resource" id="Piece_%d"]' % (k + 1), 'script = ExtResource("2_piece_data")',
				"screen = %d" % (CANISTER_SCREEN if k == 0 else SECOND_PIECE_SCREEN), "pos = Vector2i(%d, %d)" % [PIECE_POS.x, PIECE_POS.y],
				"is_canister = %s" % ("true" if k == 0 else "false"), ""])
	var last := SectorData.SCREEN_COUNT - 1
	var left := PackedInt32Array()                             # the screens in a chain: right leads on, left leads back
	var right := PackedInt32Array()
	var none := PackedInt32Array()
	for m in SectorData.SCREEN_COUNT:
		left.append(m - 1)                                     # screen 0: -1, no neighbour
		right.append(m + 1 if m < last else -1)
		none.append(-1)
	lines.append_array(["[resource]", 'script = ExtResource("1_sector_data")', "index = %d" % index, "game = %d" % game, "zone = %d" % zone,
			"start_pos = Vector2i(%d, %d)" % [START_POS.x, START_POS.y], "start_frame = %d" % START_FRAME,
			"neighbors_left = " + _ints(left), "neighbors_right = " + _ints(right), "neighbors_up = " + _ints(none), "neighbors_down = " + _ints(none),
			'pieces = Array[ExtResource("2_piece_data")]([%s])' % ", ".join(piece_refs),
			'screens = Array[ExtResource("4_screen_data")]([%s])' % ", ".join(screen_refs),
			'foes = Array[ExtResource("3_foe_data")]([])', 'foe_script = ExtResource("17_sector_%02d")' % index,
			"foe_script_base = 1", 'music_name = "%s"' % _music_of_zone(zone),
			"header_unused_3d = 0", "header_unused_40 = 0", "header_unused_41 = 0"])
	return "\n".join(lines) + "\n"


## The template's creature script: no creatures, so only a comment. `foe_script_base` is 1 (the count byte), as for any sector without creatures.
static func template_script_text(index: int) -> String:
	return "; Sector %02d - a new sector (SectorFactory), made from the template.\n;\n; It has no creatures yet. Add one in the screen editor (Add creature) or the Sector Inspector, then write\n; what it does here: see docs/create/FOE_SCRIPTING.md. Every creature names three labels of this file (start, hit, ink).\n" % index


## The song of the first sector of the chain in `zone`, so the new sector sounds like its zone ("" if no sector is in it).
static func _music_of_zone(zone: int) -> String:
	for existing in Catalog.sector_ids():
		var sector := Catalog.sector(existing)
		if sector != null and sector.zone == zone:
			return sector.music_name
	return ""


static func _ints(values: PackedInt32Array) -> String:
	return "PackedInt32Array(%s)" % ", ".join(Array(values).map(func(v: int) -> String: return str(v)))


# =====================================================================================================================
# From a copy
# =====================================================================================================================

## Makes sector `index` (default: the next free number) as a copy of sector `source`, an original or a new one. The source is read from
## `source_dir` (default: `dir`). The copy is checked right away: its script must assemble to the source's bytes.
static func new_from_copy(source: int, index: int = -1, dir: String = "", source_dir: String = "") -> Made:
	var made := Made.new()
	if source_dir.is_empty():
		source_dir = dir
	if not Catalog.has_sector(source, source_dir):
		made.error = "there is no sector %d to copy (%s)" % [source, Catalog.sector_path(source, source_dir)]
		return made
	index = _number(index, dir, made)
	if not made.ok():
		return made
	var sector_text := FileAccess.get_file_as_string(Catalog.sector_path(source, source_dir))
	var from := ResourceLoader.load(Catalog.sector_path(source, source_dir), "", ResourceLoader.CACHE_MODE_IGNORE) as SectorData
	if from == null or sector_text.is_empty():
		made.error = "sector %d could not be read" % source
		return made
	var files: Dictionary = {}
	var moved := retarget_sector_text(sector_text, source, source_dir, index, dir)
	if not (moved.error as String).is_empty():
		made.error = moved.error
		return made
	files[Catalog.sector_path(index, dir)] = moved.text
	var script_text := FileAccess.get_file_as_string(Catalog.foe_path(source, source_dir))
	var copied := copied_script_text(script_text, from, source, index)
	var problem := script_problem(script_text, copied, from, source, index)
	if not problem.is_empty():
		made.error = problem
		return made
	files[Catalog.foe_path(index, dir)] = copied
	for m in SectorData.SCREEN_COUNT:
		var screen_path := ScreenFile.screen_path(source_dir, source, m)
		if not FileAccess.file_exists(screen_path):
			made.error = "%s is missing" % screen_path
			return made
		files[ScreenFile.screen_path(dir, index, m)] = FileAccess.get_file_as_string(screen_path)
	return _write_all(made, index, dir, files)


## "" when the copied script `copied` assembles in sector `index` to exactly the bytes the source's script `original` gives in sector `source`
## (the copy must behave as the source does), else what differs.
static func script_problem(original: String, copied: String, from: SectorData, source: int, index: int) -> String:
	var before := FoeAsm.assemble(original, from.foe_script_base, FoeNames.new(null, source, from.zone))
	var after := FoeAsm.assemble(copied, from.foe_script_base, FoeNames.new(null, index, from.zone))
	if not after.ok():
		return "the script of sector %d does not assemble as sector %d: %s" % [source, index, after.errors[0]]
	if after.bytes != before.bytes:
		return "the script of sector %d assembles to other bytes as sector %d; it was not copied" % [source, index]
	return ""


## `text` (the source's `sector_NN.tres`) for the new sector: the paths of its screens and script point into the new folder, the file
## names carry the new number, and `index` is the new number. {"text", "error"}. Nothing else in the file changes.
static func retarget_sector_text(text: String, source: int, source_dir: String, index: int, dir: String) -> Dictionary:
	var old_folder := Catalog.sector_dir(source, source_dir) + "/"
	var new_folder := Catalog.sector_dir(index, dir) + "/"
	var lines := text.split("\n")
	var moved := 0
	var renumbered := false
	var in_resource := false
	for k in lines.size():
		var line := lines[k]
		if line.begins_with("[ext_resource") and line.contains(old_folder):
			line = line.replace(old_folder, new_folder).replace("sector_%02d.foe" % source, "sector_%02d.foe" % index).replace("_sector_%02d\"" % source, "_sector_%02d\"" % index)
			moved += 1
		elif line == "[resource]":
			in_resource = true
		elif in_resource and line.begins_with("index = "):
			line = "index = %d" % index
			renumbered = true
		elif in_resource and line.begins_with("foe_script = "):         # refers to the script's ext_resource id, which carries the number
			line = line.replace("_sector_%02d\"" % source, "_sector_%02d\"" % index)
		lines[k] = line
	if moved != SectorData.SCREEN_COUNT + 1 or not renumbered:
		return {"text": "", "error": "the file of sector %d does not look like a sector file: %d of its %d screen and script paths were found%s" % [source, moved, SectorData.SCREEN_COUNT + 1, "" if renumbered else ", and no 'index = ' line"]}
	var result := "\n".join(lines)
	if result.contains(old_folder):
		return {"text": "", "error": "the file of sector %d still points into its old folder after the paths were rewritten" % source}
	return {"text": result, "error": ""}


## The script of the new sector: `text` (the source's) with the names that mean something else in the new sector written as numbers,
## under a comment that says where it comes from. `from` is the source sector (for its zone).
static func copied_script_text(text: String, from: SectorData, source: int, index: int) -> String:
	var header := "; Sector %02d - a copy of sector %d (SectorFactory). The comments below are those of the sector it was copied from.\n;\n" % [index, source]
	return header + rename_for_sector(text, FoeNames.new(null, source, from.zone), FoeNames.new(null, index, from.zone))


## `text` (a creature script) with every operand NAME that `to` does not give the number it has in `from` written as that number. A
## creature, screen or flag name belongs to one sector in the registry; a picture name to one zone; sounds are global and stay as they
## are. Only the operands are touched, never a comment, a label or the spacing, so the assembled bytes do not change.
static func rename_for_sector(text: String, from: FoeNames, to: FoeNames) -> String:
	var words := RegEx.create_from_string("\\S+")
	var lines := text.split("\n")
	for n in lines.size():
		var line := lines[n]
		var semicolon := line.find(";")
		var code := line if semicolon < 0 else line.substr(0, semicolon)
		var found := words.search_all(code)
		if found.is_empty() or code.strip_edges().ends_with(":"):
			continue
		var opcode := FoeOps.op_from_mnemonic(found[0].get_string())
		if opcode < 0:
			continue
		var spec := FoeOps.operands(opcode)
		# the operand words, each with the `mirrored` word that follows a picture left out (it is not an operand of its own)
		var operands: Array[RegExMatch] = []
		for k in range(1, found.size()):
			if found[k].get_string().to_lower() != FoeOps.MIRROR_WORD:
				operands.append(found[k])
		if operands.size() != spec.size():
			continue                                               # not valid: the assembler says so, this only renames
		var edits: Array[Array] = []                               # [start, end, number]
		for k in spec.size():
			var kind: int = spec[k]["kind"]
			var word := operands[k].get_string()
			if kind == FoeOps.Kind.LABEL or FoeOps.name_kind(kind).is_empty() or word.is_valid_int() or not FoeAsm.is_identifier(word):
				continue
			if kind == FoeOps.Kind.FOE and FoeOps.parse_foe(word) >= 0:
				continue                                           # `self`, `self+2`
			var number := from.index_for(kind, word)
			if number >= 0 and to.index_for(kind, word) != number:
				edits.append([operands[k].get_start(), operands[k].get_end(), number])
		for k in range(edits.size() - 1, -1, -1):                  # from the right, so the positions stay right
			line = line.substr(0, edits[k][0]) + str(edits[k][2]) + line.substr(edits[k][1])
		lines[n] = line
	return "\n".join(lines)


# =====================================================================================================================
# Writing
# =====================================================================================================================

## Writes every file (path -> text). All or nothing: when one fails, those already written and the folder are removed again.
static func _write_all(made: Made, index: int, dir: String, files: Dictionary) -> Made:
	var folder := Catalog.sector_dir(index, dir)
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK:
		made.error = "could not make the folder %s (%s)" % [folder, error_string(error)]
		return made
	for path: String in files:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			made.error = "could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
			break
		file.store_string(files[path])
		file.close()
		made.files.append(path)
	if not made.ok():
		for path in made.files:
			DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(folder)
		made.files.clear()
		return made
	made.index = index
	made.path = Catalog.sector_path(index, dir)
	return made
