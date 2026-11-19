class_name CutsceneStage
extends Resource
## A cutscene's STAGE as data: the actors a scene has (the pictures, the text box, the groups that carry others), each with the place it
## starts at. The pack holds it as `data/story/<scene>_stage.tres` (`Catalog.story_stage`); `StageBuilder` makes the nodes of it and tells the
## `CutsceneCast` which node plays which actor, and the `CutsceneTimeline`s played on the stage name the same actors.
##
## Order is DRAW ORDER: the actors are drawn in the order they are listed, a child above its parent and above the siblings listed before it.
##
## The legacy pack's stages are written by the importer from the original's position table (`tools/import/step_story.py`), the dev pack's by
## `tools/dev_pack/dev_story.py`; `provenance` says which. A pack replaces a stage whole, as it replaces a timeline.
##
## Teaches: separating WHERE things stand from WHEN they move: the timeline holds the moving (in ticks), the stage the standing (in pixels), the
## builder the nodes. Each is data a pack can replace without touching the others' format.

## Where the numbers come from: the original's table and which numbers are our own.
@export_multiline var provenance: String = ""
## The actors, in draw order.
@export var actors: Array[StageActor] = []


## The actor called `actor_name`, or null.
func find(actor_name: StringName) -> StageActor:
	for actor in actors:
		if actor.name == actor_name:
			return actor
	return null


func has_actor(actor_name: StringName) -> bool:
	return find(actor_name) != null


## The names of the actors, in draw order.
func names() -> Array[StringName]:
	var found: Array[StringName] = []
	for actor in actors:
		found.append(actor.name)
	return found


## What is wrong with this stage, one sentence each, or an empty list when it is fine (what `problem_with` says of each actor, the actors that are fine placed in turn).
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var placed: Dictionary = {}
	for actor in actors:
		var problem := problem_with(actor, placed)
		if problem.is_empty():
			placed[actor.name] = actor
		else:
			found.append(problem)
	return found


## What is wrong with `actor` given the actors `placed` before it (name -> StageActor), or "" when it can be put on the stage: no name or one another has, a kind the builder
## does not know, a parent that is not an actor placed before it (or that is a text box), a text box with no size. The one judgement `problems` and `StageBuilder` share.
func problem_with(actor: StageActor, placed: Dictionary) -> String:
	if actor == null:
		return "an actor that is not a StageActor"
	if actor.name == &"":
		return "an actor with no name"
	if placed.has(actor.name):
		return "two actors are called '%s'" % actor.name
	if not StageActor.KINDS.has(actor.kind):
		return "actor '%s': unknown kind '%s' (one of %s)" % [actor.name, actor.kind, ", ".join(StageActor.KINDS)]
	if actor.kind == StageActor.TEXT and (actor.size.x <= 0.0 or actor.size.y <= 0.0):
		return "actor '%s': a text box needs a size" % actor.name
	if actor.parent != &"":
		if not placed.has(actor.parent):
			return "actor '%s': its parent '%s' is not an actor listed before it" % [actor.name, actor.parent]
		if (placed[actor.parent] as StageActor).kind == StageActor.TEXT:
			return "actor '%s': its parent '%s' is a text box, which carries nothing" % [actor.name, actor.parent]
	return ""
