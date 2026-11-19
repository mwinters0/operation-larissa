class_name StageNodes
extends RefCounted
## What a scene's nodes must be when a stage file has been built: every actor of the `CutsceneStage` is a node of its kind under its parent's node, at the place the file says (window pixels), mirrored,
## visible, clipped and showing the picture the file names, drawn in the order the file lists, and nothing else stands on the stage. A TEST helper: the engine and legacy suites (`test_opening`,
## `test_opening_legacy`) ask it of the same built scenes, so the dev pack's stages and the original's are held to one reading of the file.
##
## Teaches: checking a derived thing (the nodes) against the data that owns it (the stage) by reading both, field by field, instead of repeating the numbers in the test.


## One sentence per difference between the nodes under `container` (the scene's `Stage`, standing at the window's origin and in the tree) and the actors of `stage`; empty when they agree.
static func differences(stage: CutsceneStage, container: Node2D) -> Array[String]:
	var found: Array[String] = []
	var nodes: Dictionary = {}            # actor name -> Node
	var made := 0
	for actor in stage.actors:
		var parent_node: Node = nodes[actor.parent] if actor.parent != &"" else container
		var node := parent_node.get_node_or_null(actor.node_name())
		if node == null:
			found.append("%s: no node called %s under %s" % [actor.name, actor.node_name(), parent_node.name])
			continue
		nodes[actor.name] = node
		made += 1
		_actor_differences(actor, node, found)
		var listed := stage.actors.filter(func(each: StageActor) -> bool: return each.parent == actor.parent)
		var before := listed.slice(0, listed.find(actor)).filter(func(each: StageActor) -> bool: return nodes.has(each.name))
		for earlier: StageActor in before:
			if (nodes[earlier.name] as Node).get_index() > node.get_index():
				found.append("%s is drawn before %s, the file lists it after" % [actor.name, earlier.name])
	var every := 0
	for node in container.find_children("*", "", true, false):
		every += 1
	if every != made:
		found.append("the stage holds %d nodes, the file %d actors" % [every, made])
	return found


static func _actor_differences(actor: StageActor, node: Node, found: Array[String]) -> void:
	var canvas := node as CanvasItem
	if canvas.get_global_transform().origin != actor.position:
		found.append("%s stands at %s, the file says %s" % [actor.name, canvas.get_global_transform().origin, actor.position])
	if canvas.visible != actor.visible:
		found.append("%s is visible = %s, the file says %s" % [actor.name, canvas.visible, actor.visible])
	match actor.kind:
		StageActor.PICTURE:
			var sprite := node as Sprite2D
			if sprite == null:
				found.append("%s is a %s, not a Sprite2D" % [actor.name, node.get_class()])
				return
			if actor.picture != &"" and PictureRef.key_of(sprite.texture) != "ui_picture/" + actor.picture:
				found.append("%s shows %s, the file says ui_picture/%s" % [actor.name, PictureRef.key_of(sprite.texture), actor.picture])
			if sprite.flip_h != actor.mirror:
				found.append("%s is mirrored = %s, the file says %s" % [actor.name, sprite.flip_h, actor.mirror])
			if sprite.centered:
				found.append("%s is centered: its position is its top-left corner" % actor.name)
			if sprite.region_enabled != actor.clip.has_area() or (actor.clip.has_area() and sprite.region_rect != actor.clip):
				found.append("%s is clipped to %s (%s), the file says %s" % [actor.name, sprite.region_rect, sprite.region_enabled, actor.clip])
		StageActor.TEXT:
			var label := node as Label
			if label == null:
				found.append("%s is a %s, not a Label" % [actor.name, node.get_class()])
			elif label.size != actor.size:
				found.append("%s is %s big, the file says %s" % [actor.name, label.size, actor.size])
		StageActor.BUTTON:
			var button := node as TextureButton
			if button == null:
				found.append("%s is a %s, not a TextureButton" % [actor.name, node.get_class()])
				return
			if PictureRef.key_of(button.texture_normal) != "ui_picture/" + actor.picture:
				found.append("%s shows %s, the file says ui_picture/%s" % [actor.name, PictureRef.key_of(button.texture_normal), actor.picture])
			if actor.pressed_picture != &"" and PictureRef.key_of(button.texture_pressed) != "ui_picture/" + actor.pressed_picture:
				found.append("%s shows %s pressed, the file says ui_picture/%s" % [actor.name, PictureRef.key_of(button.texture_pressed), actor.pressed_picture])
			if button.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
				found.append("%s acts on the release: the original's buttons act on the press" % actor.name)
		StageActor.GROUP:
			var boxed := actor.size.x > 0.0 and actor.size.y > 0.0
			if node.get_class() != ("Control" if boxed else "Node2D"):
				found.append("%s is a %s, not a %s" % [actor.name, node.get_class(), "Control (a group with a size is a clipping box)" if boxed else "Node2D"])
			elif boxed and (not (node as Control).clip_contents or (node as Control).size != actor.size):
				found.append("%s is %s big and clips = %s, the file says a box of %s" % [actor.name, (node as Control).size, (node as Control).clip_contents, actor.size])
		StageActor.FRAMES:
			var animated := node as AnimatedSprite2D
			if animated == null:
				found.append("%s is a %s, not an AnimatedSprite2D" % [actor.name, node.get_class()])
			elif animated.sprite_frames == null or animated.is_playing() or animated.centered:
				found.append("%s shows no picture set, or plays, or is centered: it shows a picture of its set and stands still, by its top-left corner" % actor.name)
		StageActor.FILL:
			var fill := node as ColorRect
			if fill == null:
				found.append("%s is a %s, not a ColorRect" % [actor.name, node.get_class()])
			elif fill.size != actor.size or fill.color != actor.color:
				found.append("%s is %s of %s, the file says %s of %s" % [actor.name, fill.size, fill.color, actor.size, actor.color])
		StageActor.CHAIN:
			var chain := node as StageChain
			if chain == null:
				found.append("%s is a %s, not a StageChain" % [actor.name, node.get_class()])
			elif chain.size != actor.size or chain.hooks.size() != actor.pictures.size() or chain.extent != 0 or (chain.get_child_count() > 0 and PictureRef.key_of((chain.get_child(0) as Sprite2D).texture) != "ui_picture/" + actor.pictures[0]):
				found.append("%s is %s big with %d hook pictures at extent %d, the first piece showing %s: the file says %s big, %s, the hook first showing %s" % [actor.name, chain.size, chain.hooks.size(), chain.extent,
						PictureRef.key_of((chain.get_child(0) as Sprite2D).texture) if chain.get_child_count() > 0 else "nothing", actor.size, actor.pictures, actor.pictures[0]])
