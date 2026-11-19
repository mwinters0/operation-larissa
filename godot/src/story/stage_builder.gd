class_name StageBuilder
extends RefCounted
## The one builder of a cutscene's stage: it makes the nodes of a `CutsceneStage` under a container and tells the `CutsceneCast` which node plays which actor.
## Every path that shows a scene's stage (the opening's scenes, the closings, a test) calls `build`; none puts a picture, a position or a draw order of its own.
##
## What it makes: a picture is a `Sprite2D` (top-left corner, its picture resolved through the cast's `pictures`, mirrored, clipped as the actor says), a text box a `Label` of the
## actor's size that wraps the whole text and reveals it a character at a time, a group a `Node2D`, a button a `TextureButton` of its picture's size that acts on the PRESS (a `TimelineSegment` connects it), a frames actor an `AnimatedSprite2D` of the set the cast hands in (`CutsceneCast.frame_sets`),
## a fill a `ColorRect`, a chain a `StageChain` that its child actors are the pieces of, a group with a size a `Control` that clips what it carries. The nodes are named by the actors (`StageActor.node_name`), made in the
## order of the list so that the list is the draw order, and an actor with a parent is made inside the parent's node at the place that is its window position less the parent's.
## The container stands at the window's origin.
##
## An actor that cannot be made (a parent that is not listed before it, a kind nobody knows) is left out of the scene and told once (`TroubleLog`), with the pack that holds
## the stage; a timeline that names it is told by `Cutscene`.
##
## Teaches: one builder as the owner of a derived thing (the nodes) read entirely from the data that owns it (the stage), so a scene that is built twice, or by a test, is built the same.

## The theme variation of a text box: the HUD's label.
const TEXT_THEME := &"HudLabel"
## The animation of a picture set that a `frames` actor shows (every set the game holds, the sub's and each zone's creatures, has its pictures in this one).
const FRAMES_ANIMATION := &"all"


## Makes the actors of the stage `stage_name` (`Catalog.story_stage`) under `container` and binds each to `cast`. Returns the stage, null when the chain holds none (told once).
static func build(stage_name: StringName, container: Node, cast: CutsceneCast) -> CutsceneStage:
	var stage := Catalog.story_stage(stage_name)
	if stage == null:
		TroubleLog.session.tell("[story] no pack of the chain holds the stage '%s' (data/story/%s.tres): the scene shows nothing and its animations move nothing" % [stage_name, stage_name])
		return null
	var placed: Dictionary = {}         # actor name -> StageActor, the actors that were made
	var nodes: Dictionary = {}          # actor name -> Node
	var offered: Array[StringName] = []
	offered.assign(cast.frame_sets.keys())
	for actor in stage.actors:
		var problem := stage.problem_with(actor, placed, offered)
		if not problem.is_empty():
			TroubleLog.session.tell("[story] the stage '%s' of pack '%s': %s; the actor is left out of the scene" % [stage_name, Catalog.story_pack_id(stage_name), problem])
			continue
		var parent: Node = nodes[actor.parent] if actor.parent != &"" else container
		var origin: Vector2 = (placed[actor.parent] as StageActor).position if actor.parent != &"" else Vector2.ZERO
		var node := _make(actor, cast)
		if node is StageChain:
			(node as StageChain).where = "the chain '%s' of the stage '%s' of pack '%s'" % [actor.name, stage_name, Catalog.story_pack_id(stage_name)]
		node.name = actor.node_name()
		node.position = actor.position - origin
		node.visible = actor.visible
		parent.add_child(node)
		cast.bind(actor.name, node)
		placed[actor.name] = actor
		nodes[actor.name] = node
	for node: Node in nodes.values():
		if node is StageChain:
			(node as StageChain).frame = 0                    # (the pieces are all there now: the hook, the first, shows its first picture)
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
			if actor.size.x > 0.0 and actor.size.y > 0.0:
				return _box(actor)
			return Node2D.new()
		StageActor.CHAIN:
			var chain := StageChain.new()
			for picture in actor.pictures:
				chain.hooks.append(cast.pictures.call(picture))
			chain.size = actor.size
			chain.clip_contents = actor.size.x > 0.0 and actor.size.y > 0.0
			chain.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return chain
		StageActor.FILL:
			var fill := ColorRect.new()
			fill.size = actor.size
			fill.color = actor.color
			fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return fill
		StageActor.FRAMES:
			var sprite := AnimatedSprite2D.new()
			sprite.centered = false
			sprite.sprite_frames = cast.frame_sets[actor.frames]
			sprite.animation = FRAMES_ANIMATION
			sprite.frame = cast.frame_number(actor.picture) if actor.picture != &"" else 0
			sprite.pause()                                    # (a timeline's `frame` and `pose` tracks choose the picture; nothing plays)
			return sprite
		StageActor.BUTTON:
			var button := TextureButton.new()
			button.texture_normal = cast.pictures.call(actor.picture)
			if actor.pressed_picture != &"":
				button.texture_pressed = cast.pictures.call(actor.pressed_picture)
			if button.texture_normal != null:
				button.size = button.texture_normal.get_size()
			button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS        # the original's buttons answer the left button DOWN
			button.focus_mode = Control.FOCUS_NONE
			return button
	var sprite := Sprite2D.new()
	sprite.centered = false
	if actor.picture != &"":
		sprite.texture = cast.pictures.call(actor.picture)           # (a piece of a chain, a sailor a timeline dresses: no picture of its own)
	sprite.flip_h = actor.mirror
	if actor.clip.has_area():
		sprite.region_enabled = true
		sprite.region_rect = actor.clip
	return sprite


## A group with a size: a box that draws only what lies inside it.
static func _box(actor: StageActor) -> Control:
	var box := Control.new()
	box.size = actor.size
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

