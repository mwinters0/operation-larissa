class_name ModProblems
extends RefCounted
## The problem screens a mod draws: what `ModHost` keeps of a mod whose manifest says `problems`. Its `types` are the problem types the mod draws the screen of; the pack holds each type as DATA (`data/problems/problem_type_NN.json`:
## its words, its stored records, how an answer is judged) with the diagram family `mod`, so the game words the problem, judges the answer, counts the tries and the oxygen exactly as for any type, and only the picture on the
## left monitor is the mod's (`ModDiagram`, asked through `ModHost.problem_screen`). Like a skin, it holds what the script may name (`assets`: the pictures of `problems/` and the shaders the manifest lists) and nothing else.
## The manifest is judged in one place, `ModParts.make`, which `PackCheck` (for the author) and `ModHost` (before the mod runs) both ask.
##
## Teaches: extending a system by data first and code second: a new problem type is a data file like the original's 34, and the script only draws; the game's own checker stays the only judge.

## The family a mod's problem type names in its diagram data: `DiagramFactory` makes a `ModDiagram` for it.
const FAMILY := "mod"
## The function a problem-screen mod defines, called by `ModDiagram` when the problem, the entry or the step changes.
const FUNCTION := "problem_frame"

## The mod pack's id.
var pack_id: StringName = &""
## The problem types the mod draws.
var types: Array[int] = []
## What the script may name: the pictures of `problems/` and the shaders of the manifest (`ModAssets`).
var assets: ModAssets


## The problem screens of the mod pack `pack`, or null with every reason in `reasons`: a type that the pack does not hold as data, that is not the type it is called, that names no `mod` diagram family or that has no
## records; a shader of the manifest that is not what `ModShader` accepts, a picture of `problems/` that is not a PNG the engine can decode. (Null with no reason for a pack that draws none.)
static func make(pack: Pack, reasons: Array[String]) -> ModProblems:
	if pack.mod == null or not pack.mod.has_problems:
		return null
	var screens := ModProblems.new()
	screens.pack_id = pack.id
	screens.types = pack.mod.problem_types.duplicate()
	for type_id in screens.types:
		var type := check_type(pack, type_id, reasons)
		if type == null:
			continue
		if String(type.diagram.get("family", "")) != FAMILY:
			reasons.append("problem type %d: its diagram family must be \"%s\" (it is \"%s\"), or the mod draws nothing of it" % [type_id, FAMILY, type.diagram.get("family", "")])
		elif type.records.is_empty():
			reasons.append("problem type %d: it has no records to ask" % type_id)
	screens.assets = ModAssets.make(pack, ModSpec.PROBLEM_FOLDER, pack.mod.problem_shaders, reasons)
	return screens if reasons.is_empty() else null


## The problem type `type_id` as the pack holds it, or null with the reason in `reasons`: the pack holds the data form of the type (`data/problems/problem_type_NN.json`), it reads as a `ProblemType`, and it says the id it is called.
## The one question of "a problem type this pack holds", asked for the types a mod draws (`make`) and the ones it judges (`ModParts.make`): a mod works on the types of its own pack.
static func check_type(pack: Pack, type_id: int, reasons: Array[String]) -> ProblemType:
	var rel := Catalog.problem_type_rel(type_id)
	if not pack.provides(rel):
		reasons.append("problem type %d: the pack holds no %s (the data form of the type: a mod works on the types of its own pack)" % [type_id, rel.get_basename() + ".json"])
		return null
	var type := pack.resource(rel) as ProblemType
	if type == null:
		reasons.append("problem type %d: %s cannot be read as a problem type" % [type_id, rel])
		return null
	if type.id != type_id:
		reasons.append("problem type %d: %s says its id is %d" % [type_id, rel, type.id])
		return null
	return type
