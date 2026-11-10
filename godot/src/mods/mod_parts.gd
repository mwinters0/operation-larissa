class_name ModParts
extends RefCounted
## What the game keeps of a running mod besides its node: the pieces its manifest asks for, made by ONE builder (`make`) from what the pack holds. `skin` is the `ModSkin` of a mod whose manifest says `skin`, `screens` the
## `ModProblems` of one that says `problems`; either is null when the manifest does not say it. The rule hooks need no piece (a campaign's run resolves them, `ModHooks`), but the problem types a mod judges are judged here too.
## The manifest is judged in one place, `make`, which `PackCheck` (for the author, through `problems`) and `ModHost` (before the mod runs) both ask; the functions the script must define are `ModSpec.functions`.
##
## Teaches: one record per running thing, built by one function that is also the validator, so the tool that tells the author and the host that refuses the pack cannot disagree.

## The skin a skin mod is, or null.
var skin: ModSkin
## The problem screens a mod draws, or null.
var screens: ModProblems


## The parts of the mod pack `pack`, or null with every reason in `reasons` (null with no reason for a pack that is no mod): a skin or problem screen the pack cannot have (`ModSkin.make`, `ModProblems.make`), or a problem type
## whose answers the manifest's `rules` judges that the pack does not hold as data (a mod judges the answers of types of its own pack).
static func make(pack: Pack, reasons: Array[String]) -> ModParts:
	if pack.mod == null:
		return null
	var parts := ModParts.new()
	parts.skin = ModSkin.make(pack, reasons)
	parts.screens = ModProblems.make(pack, reasons)
	for type_id in pack.mod.rule_answers:
		ModProblems.check_type(pack, type_id, reasons)
	return parts if reasons.is_empty() else null


## What stops `pack` from being the mod its manifest says, as sentences ([] when nothing does or it is no mod): `PackCheck` tells the author, `ModHost` refuses the mod.
static func problems(pack: Pack) -> Array[String]:
	var reasons: Array[String] = []
	make(pack, reasons)
	return reasons


## The mod ends: its skin is not offered any more.
func end() -> void:
	if skin != null:
		skin.alive = false
