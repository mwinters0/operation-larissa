class_name SectorJson
extends RefCounted
## A sector in the data form: `sectors/sector_NN/sector_NN.json` and its creature script `sector_NN.foe` beside it.
##
## The JSON is the sector as `ResourceJson` writes any resource: the header fields (`index`, `zone`, `start_pos`, `music_name`, the four
## neighbour tables), `pieces`, `foes` (each with its place, picture and the LABELS of its script) and the twelve `screens` (the tiles as
## base64, the decorations, the math triggers). The creature script is NOT in the JSON: it stays the plain `.foe` text of the base game
## (docs/create/FOE_SCRIPTING.md), named by the sector's `foe_script` field (default `sector_NN.foe`), so a student edits it as text, with the
## names of the registry. Sectors 0 to 31 are the original's and are never read from a pack; a pack's sectors are numbered 32 and up
## (`Catalog.next_free_sector`).
##
## Teaches: one resource in two files when the parts are different kinds of thing (data and a program), and that the second file is the same
## file the base game has: nothing new to learn for the creature language.

const SCRIPT_FIELD := "foe_script"


static func folder_rel(index: int) -> String:
	return "sectors/sector_%02d" % index


static func json_rel(index: int) -> String:
	return "%s/sector_%02d.json" % [folder_rel(index), index]


static func foe_rel(index: int) -> String:
	return "%s/sector_%02d.foe" % [folder_rel(index), index]


## Sector `index` as `pack` holds it, or null (with a warning that says why). The creature script is read but not compiled
## (`Catalog.sector` does that).
static func read(pack: Pack, index: int) -> SectorData:
	var reader := ResourceJson.new(pack)
	reader.skip = PackedStringArray([SCRIPT_FIELD])
	var sector := reader.read(json_rel(index), SectorData) as SectorData
	if sector == null:
		return null
	var raw: Variant = pack.read_json(json_rel(index))
	var problems := reader.problems.duplicate()
	if sector.index != index:
		if (raw as Dictionary).has("index"):
			problems.append("the file is in the folder of sector %d but says it is sector %d" % [index, sector.index])
		sector.index = index
	var script_file := String((raw as Dictionary).get(SCRIPT_FIELD, "sector_%02d.foe" % index))
	var rel := "%s/%s" % [folder_rel(index), script_file]
	if pack.has(rel):
		var script := FoeScript.new()
		script.source = pack.read_text(rel)
		sector.foe_script = script
	else:
		problems.append("no creature script %s" % rel)
	for problem in problems:
		if not reader.problems.has(problem):
			push_warning("SectorJson: sector %d: %s" % [index, problem])
	return sector


## The JSON-ready Dictionary of `sector` (without its script, which `save` writes as text).
static func data_of(sector: SectorData) -> Dictionary:
	var writer := ResourceJson.new()
	writer.skip = PackedStringArray([SCRIPT_FIELD])
	return writer.data_of(sector)


## Writes the sector into the pack folder `root`: its JSON and its `.foe`. `OK` or the first error.
static func save(sector: SectorData, root: String) -> Error:
	var error := ResourceJson.save_json(data_of(sector), "%s/%s" % [root, json_rel(sector.index)])
	if error != OK:
		return error
	var file := FileAccess.open("%s/%s" % [root, foe_rel(sector.index)], FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(sector.foe_script.source if sector.foe_script != null else "")
	return OK
