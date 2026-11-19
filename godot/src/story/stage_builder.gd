class_name StageBuilder
extends RefCounted
## The one builder of a cutscene's stage: it makes the nodes of a `CutsceneStage` under a container and tells the `CutsceneCast` which node plays which actor.
## Every path that shows a scene's stage (the opening's cartoon and title, a debug scene, a test) calls `build`; none puts a picture, a position or a draw order of its own.
##
## What it makes: a picture is a `Sprite2D` (top-left corner, its picture resolved through the cast's `pictures`, mirrored, clipped as the actor says), a text box a `Label` of the
## actor's size that wraps the whole text and reveals it a character at a time, a group a `Node2D`. The nodes are named by the actors (`StageActor.node_name`), made in the
## order of the list so that the list is the draw order, and an actor with a parent is made inside the parent's node at the place that is its window position less the parent's.
## The container stands at the window's origin.
##
## An actor that cannot be made (a parent that is not listed before it, a kind nobody knows) is left out of the scene and told once (`TroubleLog`), with the pack that holds
## the stage; a timeline that names it is told by `Cutscene`.
##
## Teaches: one builder as the owner of a derived thing (the nodes) read entirely from the data that owns it (the stage), so a scene that is built twice, or by a test, is built the same.

## The theme variation of a text box: the HUD's label.
const TEXT_THEME := &"HudLabel"


## Makes the actors of the stage `stage_name` (`Catalog.story_stage`) under `container` and binds each to `cast`. Returns the stage, null when the chain holds none (told once).
static func build(stage_name: StringName, container: Node, cast: CutsceneCast) -> CutsceneStage:
	var stage := Catalog.story_stage(stage_name)
	if stage == null:
		TroubleLog.session.tell("[story] no pack of the chain holds the stage '%s' (data/story/%s.tres): the scene shows nothing and its animations move nothing" % [stage_name, stage_name])
		return null
	var placed: Dictionary = {}         # actor name -> StageActor, the actors that were made
	var nodes: Dictionary = {}          # actor name -> Node
	for actor in stage.actors:
		var problem := stage.problem_with(actor, placed)
		if not problem.is_empty():
			TroubleLog.session.tell("[story] the stage '%s' of pack '%s': %s; the actor is left out of the scene" % [stage_name, _pack_of(stage_name), problem])
			continue
		var parent: Node = nodes[actor.parent] if actor.parent != &"" else container
		var origin: Vector2 = (placed[actor.parent] as StageActor).position if actor.parent != &"" else Vector2.ZERO
		var node := _make(actor, cast)
		node.name = actor.node_name()
		node.position = actor.position - origin
		node.visible = actor.visible
		parent.add_child(node)
		cast.bind(actor.name, node)
		placed[actor.name] = actor
		nodes[actor.name] = node
	return stage


static func _make(actor: StageActor, cast: CutsceneCast) -> Node:
	match actor.kind:
		StageActor.TEXT:
			var label := Label.new()
			label.size = actor.size
			label.theme_type_variation = TEXT_THEME
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			# The text is wrapped as a whole and only REVEALED character by character: with the default (characters hidden before shaping) the label wraps the part
			# typed so far, and a word that reaches the edge jumps to the next line.
			label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
			return label
		StageActor.GROUP:
			return Node2D.new()
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = cast.pictures.call(actor.picture)
	sprite.flip_h = actor.mirror
	if actor.clip.has_area():
		sprite.region_enabled = true
		sprite.region_rect = actor.clip
	return sprite


static func _pack_of(stage_name: StringName) -> String:
	var holder := Packs.holder(Catalog.STORY_REL % stage_name)
	return String(holder.id) if holder != null else "?"
