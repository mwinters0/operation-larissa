class_name ModRuleShelf
extends RefCounted
## Rule-hook mods for tests: ONE scratch pack made of a fixture of `tests/mods/` (`rules`, `rules_chaos`) with what a campaign of a mod needs, laid over the pack the suite runs on and running (`Mods.sync`):
##   * problem type 41, "name a multiple of {0}", whose data stores ONE answer (the first multiple) so that its `compare_mode` calls every other multiple wrong, and which the mod judges (`rules.answers`);
##   * sector 190, a copy of the dev arena whose first creature runs `Mod_Instruction` (0 raises flag 3 the third time, 1 is the condition before a picture), and sector 191, the same script for a campaign that declares no mod;
##   * the campaign `rules_campaign` (sector 190, `mods` names the pack) and `bystander_campaign` (sector 191, no mods): the mod is in the chain of both, and only the first declares it.
## `player` is a player of a campaign. `release` takes the pack away. They need the godot-sandbox extension (`uv run tools/fetch_sandbox.py`).
##
## Teaches: a test double for a campaign that declares a mod, built the way a creator would: the data and the script are files of a pack, and nothing of either is known to the game but through the chain and the campaign.

const FIXTURES := "res://tests/mods"
const PACK := &"rules_box"
const TYPE := 41
const SECTOR := 190
const BYSTANDER_SECTOR := 191
const CAMPAIGN := &"rules_campaign"
const BYSTANDER := &"bystander_campaign"
## The creature that runs the instructions (the arena's post), the flag instruction 0 raises, and the picture instruction 1 guards.
const CREATURE := DevCreatures.POST
const FLAG := 3
const WORDS := ["Name a multiple of {0}.", "A multiple of {0} is {0} times a whole number.", "{0} itself is one: {1}.", "Well done!"]
## The script of the post in both sectors.
const POST_WAIT := "post_wait:\n    Wait_Next_Tick"
const POST_WAIT_WITH_MOD := "post_wait:\n    Mod_Instruction 0 3\n    Mod_Instruction 1 40\n    Set_Frame clam_open_mid\n    Wait_Next_Tick"


## The scratch pack of the fixture `fixture`, mounted (over the pack `base`, by default the bottom of the chain in use), with the mods synced.
static func mount(fixture: String = "rules", base: StringName = &"") -> PackShelf:
	var shelf := PackShelf.new(PACK, base)
	shelf.add_mod_fixture("%s/%s" % [FIXTURES, fixture])
	shelf.write_json("data/problems/problem_type_%02d.json" % TYPE, ResourceJson.new().data_of(problem_type()))
	for index in [SECTOR, BYSTANDER_SECTOR]:
		var copy := shelf.add_sector_copy(DevCreatures.ARENA, index)
		copy.foe_script.source = copy.foe_script.source.replace(POST_WAIT, POST_WAIT_WITH_MOD)
		shelf.add_sector(copy)
	shelf.add_campaign(campaign(CAMPAIGN, SECTOR, [PACK]))
	shelf.add_campaign(campaign(BYSTANDER, BYSTANDER_SECTOR, []))
	shelf.mount()
	Mods.sync()
	return shelf


## Takes the pack away and syncs the mods with the chain that is left.
static func release(shelf: PackShelf) -> void:
	if shelf != null:
		shelf.remove()
	Mods.sync()


## A one-sector campaign that declares the mods `mods`.
static func campaign(id: StringName, sector: int, mods: Array[StringName]) -> Campaign:
	var made := Campaign.new()
	made.id = id
	made.title = "Rules of %s" % id
	made.sectors = PackedInt32Array([sector])
	made.default_edu_levels = PackedInt32Array([0])
	made.log_unlock_order = PackedInt32Array([1])
	made.log_texts = [&"A note."]
	made.log_voices = [&""]
	made.supply_texts = [&"Well done."]
	made.supply_voices = [&""]
	made.finale_text = "The end."
	made.mods = mods
	return made


## A new player of the campaign `id`, at its sector.
static func player(id: StringName = CAMPAIGN) -> PlayerProfile:
	return PlayerProfile.new_player_in("Hook", Catalog.campaign(id))


## Problem type 41: a stored multiple of field 0 (field 1), the calculator, the generic diagram.
static func problem_type() -> ProblemType:
	var type := ProblemKit.type_of("exact", "cn", 1, [
		ProblemKit.flat([3, ProblemKit.decimal(3.0, 0)]),
		ProblemKit.flat([5, ProblemKit.decimal(5.0, 0)]),
		ProblemKit.flat([7, ProblemKit.decimal(7.0, 0)]),
	], 0.0, false, [0, 0, 1])
	type.id = TYPE
	type.title = "Multiples"
	type.texts = PackedStringArray(WORDS)
	type.text_ids = PackedInt32Array([0, 0, 0, 0])
	type.diagram = {"family": "items", "items": [{"text": {"field": 0}, "box": [100, 100], "y": 100}]}
	return type
