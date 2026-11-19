class_name FrameSets
extends RefCounted
## The picture sets the engine offers to a scene's stage, by fixed names: the one table that the cast (`CutsceneCast.of`), the builder (`StageBuilder`, through the cast) and the check of a pack (`PackCheck`) read. A `frames` actor of a stage
## (`StageActor.frames`) names one of them; a timeline's `frame` and `pose` tracks pick the picture of it.
##
## `sub`             the sub's drawings (`Catalog.sub_frames`); every scene is offered it
## `zone_creatures`  the creature pictures of the zone of the sector in play (`Catalog.foes_frames`); offered only to a scene that is laid over a sector, which the director hands the zone of (`Game.show_closing`: `TimelineSegment.of`). The opening has no
##                   sector in play, so it is offered none: a stage that asks for it there is told, as one that names a set the engine does not have.
##
## Which creature a picture of the second set is depends on the zone, so a pack names the creature pictures of the zone its scene is played in (the legacy pack's Expert closing names those of zone 6, the Expert finale's).
##
## Teaches: a fixed vocabulary of names as one table of data in code, so that what a stage may ask for, what the view hands in and what the check accepts cannot differ; the zone is an argument, never a number in the code that plays a scene.

const SUB := &"sub"
const ZONE_CREATURES := &"zone_creatures"
## Every set of the engine, each with whether it needs a zone (`true`: only offered when a zone is handed in).
const SETS: Dictionary[StringName, bool] = {SUB: false, ZONE_CREATURES: true}
## The zone of a scene that is laid over no sector.
const NO_ZONE := -1


## The names of the sets offered to a scene played in `zone` (`NO_ZONE`: no sector is in play).
static func offered(zone: int) -> Array[StringName]:
	var names: Array[StringName] = []
	for set_name in SETS:
		if not SETS[set_name] or _has_zone(zone):
			names.append(set_name)
	return names


## The names of the sets offered to a scene that is laid over some sector (the closings: a zone is handed in whichever it is): the check of a pack asks it, as it does not know which sector the game ends in.
static func over_a_sector() -> Array[StringName]:
	var names: Array[StringName] = []
	names.assign(SETS.keys())
	return names


## The sets offered to a scene played in `zone`, each with its pictures (`CutsceneCast.frame_sets`).
static func make(zone: int) -> Dictionary[StringName, SpriteFrames]:
	var made: Dictionary[StringName, SpriteFrames] = {}
	for set_name in offered(zone):
		made[set_name] = _frames_of(set_name, zone)
	return made


static func _has_zone(zone: int) -> bool:
	return zone >= 0 and zone < Catalog.ZONE_COUNT


static func _frames_of(set_name: StringName, zone: int) -> SpriteFrames:
	if set_name == ZONE_CREATURES:
		return Catalog.foes_frames(zone)
	return Catalog.sub_frames()
