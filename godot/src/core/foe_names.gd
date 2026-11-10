@tool
class_name FoeNames
extends RefCounted
## The names a creature script may use in its operands, in the place the script belongs to: a NameRegistry plus
## the SECTOR and the ZONE of the script. The assembler turns `Play_Sound begin` into 22 with it, the disassembler turns
## 22 back into `begin`, and the editor offers the names for completion; nobody else needs to know which kind of name
## is looked up in which scope.
##
## Teaches: a SCOPE as a plain context object. Creature pictures are numbered per zone (slot 40 is a different drawing in
## every zone) and creatures, screens and flags per sector, so "what does `eel_swim_1` mean here?" has no answer without
## knowing where "here" is. The registry (NameRegistry) answers for a given scope; this class remembers which one.
## tools/import/foe_names.py is the twin the importer uses to write the stored scripts.
##
## Without a sector or zone (`FoeNames.new()`) the global names (sounds) and the `common` names of the scoped kinds
## still work, and so do the made-up names (`foe_3`, `frame_040`).

var registry: NameRegistry
## The sector whose creatures, screens and flags are named; NameRegistry.NO_SCOPE when unknown.
var sector := NameRegistry.NO_SCOPE
## The zone (SectorData.zone) whose creature pictures are named; NameRegistry.NO_SCOPE when unknown.
var zone := NameRegistry.NO_SCOPE


func _init(p_registry: NameRegistry = null, p_sector := NameRegistry.NO_SCOPE, p_zone := NameRegistry.NO_SCOPE) -> void:
	registry = p_registry if p_registry != null else NameRegistry.original()
	sector = p_sector
	zone = p_zone


## The names of the sector `data` (its number, its zone).
static func for_sector(data: SectorData, p_registry: NameRegistry = null) -> FoeNames:
	if data == null:
		return FoeNames.new(p_registry)
	return FoeNames.new(p_registry, data.index, data.zone)


## The registry scope of an operand kind: the zone for pictures, the sector for creatures, screens and flags, none
## for the global kinds (and when the sector or zone is unknown or not a scope of the kind).
func scope_of(kind: int) -> int:
	var registry_kind := FoeOps.name_kind(kind)
	if registry_kind.is_empty() or not NameRegistry.is_scoped(registry_kind):
		return NameRegistry.NO_SCOPE
	var wanted := zone if registry_kind == &"frame" else sector
	return wanted if wanted >= 0 and wanted < NameRegistry.scope_count(registry_kind) else NameRegistry.NO_SCOPE


## The REAL name of `value` for an operand of `kind` ("" when nobody named it, or the kind has no names: the
## disassembler then prints the number, which says more than a made-up name like `sfx_28` would).
func name_for(kind: int, value: int) -> String:
	var registry_kind := FoeOps.name_kind(kind)
	if registry_kind.is_empty() or not registry.is_named(registry_kind, value, scope_of(kind)):
		return ""
	return registry.name_of(registry_kind, value, scope_of(kind))


## The number a name stands for (a real name or a made-up one), or -1.
func index_for(kind: int, word: String) -> int:
	var registry_kind := FoeOps.name_kind(kind)
	return -1 if registry_kind.is_empty() else registry.index_of(registry_kind, word, scope_of(kind))


## Why `word` is no name here, for the person who typed it ("unknown sound 'bgin' (did you mean 'begin'?)").
func explain(kind: int, word: String) -> String:
	var registry_kind := FoeOps.name_kind(kind)
	if registry_kind.is_empty():
		return "unknown name '%s'" % word
	if word.to_lower() == "mirror":
		return "unknown %s 'mirror' (write %s after the picture)" % [registry_kind, FoeOps.MIRROR_WORD]
	return registry.explain_unknown(registry_kind, word, scope_of(kind))


## The real names usable for an operand of `kind` here: name -> number, in the order of the numbers (completion).
func entries(kind: int) -> Dictionary:
	var registry_kind := FoeOps.name_kind(kind)
	return {} if registry_kind.is_empty() else registry.entries(registry_kind, scope_of(kind))
