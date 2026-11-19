class_name ScenePlace
extends RefCounted
## Where a scene is played: the one small value a director hands to `TimelineSegment.of` and that the resolver of a scene's timelines (`StoryScene.timeline_named`) reads. A scene laid over a running sector (a closing) is played where the
## game is: the zone of that sector (what the creature pictures of its stage are, `FrameSets`) and the place and drawing of the sub (a flight file makes its timeline for them, `SubFlight`). The opening is played nowhere (`nowhere`).
##
## Teaches: one value instead of an argument list that grows with each thing a scene may depend on; a scene file never names a place, the director says it, so the same file is played wherever the game ends.

## The zone of the sector in play (`FrameSets.NO_ZONE`: none).
var zone: int = FrameSets.NO_ZONE
## The sub's place when the scene begins, in window pixels (the top-left of its picture), and the cell (drawing) it shows.
var sub_at: Vector2i = Vector2i.ZERO
var sub_cell: int = 0


## The place of a scene that is laid over no sector (the opening); also the place the check of a pack makes a flight for: the window's origin, cell 0 (the actors a flight names do not depend on the place).
static func nowhere() -> ScenePlace:
	return ScenePlace.new()


## The place of a scene laid over a sector of `in_zone` with the sub at `at` showing cell `cell`.
static func over(in_zone: int, at: Vector2i = Vector2i.ZERO, cell: int = 0) -> ScenePlace:
	var place := ScenePlace.new()
	place.zone = in_zone
	place.sub_at = at
	place.sub_cell = cell
	return place
