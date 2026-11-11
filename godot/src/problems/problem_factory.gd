class_name ProblemFactory
extends RefCounted
## Picks a problem the way the original does: from a stored table.
##
## Teaches: a static factory and injectable randomness. Every function takes an optional
## `RandomNumberGenerator`; the game passes none (a fresh random pick) and the tests pass
## a seeded one, or a fixed record index, so results can be reproduced.

## The problem of type `type_id` at educational level `level` (0-3). The original reads
## `records[rand() % N]` of the level's table. With `record_index >= 0` that record is used.
## Returns null if the type has no record at that level (the caller decides what to do; many types
## exist only at some levels, so this is not an error).
static func make(type_id: int, level: int, rng: RandomNumberGenerator = null, record_index: int = -1) -> ProblemInstance:
	var type := Catalog.problem_type(type_id)
	if type == null or type.record_count(level) == 0:                 # (a type the chain does not have: a pack that adds it is not in use)
		return null
	var count := type.record_count(level)
	var index := record_index
	if index < 0:
		index = (rng.randi() if rng != null else randi()) % count
	# the food pie chart (type 17) shows its legend in one of two random orders
	var rotation := (rng.randi() if rng != null else randi()) % 2 if type_id == 17 else 0
	return ProblemInstance.build(type, level, index, rotation)


## The problem a math trigger asks for. The trigger table gives two candidate types per
## (slot, level); one is chosen at random, as the original does.
static func for_trigger_slot(slot: int, level: int, rng: RandomNumberGenerator = null) -> ProblemInstance:
	var table := Catalog.trigger_table()
	var pick := (rng.randi() if rng != null else randi()) % TriggerTable.PICKS
	var type_id := table.type_for(slot, level, pick)
	if not _has_problems(type_id, level):                       # that type is absent at this level (or from this chain): use the other one
		type_id = table.type_for(slot, level, 1 - pick)
	var instance := make(type_id, level, rng)
	if instance == null:
		TroubleLog.session.tell("[problems] the trigger table (of the chain in use) names problem types %d and %d for slot %d at level %d, and the chain has no problem of either there; no problem opens" % [
				table.type_for(slot, level, 0), table.type_for(slot, level, 1), slot, level])
	else:
		instance.trigger_slot = slot
	return instance


static func _has_problems(type_id: int, level: int) -> bool:
	var type := Catalog.problem_type(type_id)
	return type != null and type.record_count(level) > 0


## The data canister problem (slot 1) with the log entry its sector delivers as the success message. Which entry that is
## comes from `CanisterLog` (the sector's campaign: the original's unlock tables), not from the order of the sectors.
static func for_canister(sector: SectorData, level: int, rng: RandomNumberGenerator = null) -> ProblemInstance:
	var instance := for_trigger_slot(1, level, rng)
	var campaign := CanisterLog.campaign_of(sector.index)
	if instance != null and campaign != null:                                # (a sector of no campaign has no log)
		var number := CanisterLog.newest(sector.index)
		instance.success = campaign.log_entry_text(number)           # (a name of the string tables, or the campaign's own words)
		instance.log_index = number - 1
		instance.log_sector = sector.index
	return instance
