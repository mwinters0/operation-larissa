class_name CutsceneCast
extends RefCounted
## The VIEW's half of a cutscene: which node plays which actor of a `CutsceneTimeline`, and how a name of the timeline
## becomes a thing Godot can set (a picture name -> a texture).
##
## Teaches: a seam between data and presentation. A timeline says "the actor `radar` shows `ship_radar_1`"; the cast
## knows that `radar` is the `Sprite2D` called `Radar` on the ship and that `Assets.ui_picture` turns the name into a texture.
## A skin that draws the radar some other way builds a cast with other nodes and other resolvers, and the timeline (and
## so the timing) stays exactly the same.
##
## Not a node: a plain object that the scene's script makes in `_ready`, fills with `bind()` while it builds its
## sprites, and hands to `Cutscene.animation()`.

## The node the `AnimationPlayer`'s paths start from (the scene's root; the players are its children).
var root: Node
## The sub's cells and drawings, for `CutsceneTrack.PROP_POSE`: the `sub` section of the tuning of the run that plays the cutscene (`GameState.tuning`).
var sub_tuning: SubTuning = null
## The creature set (a zone) whose picture names `CutsceneTrack.PROP_FRAME` uses; -1 when only numbers are used.
var frame_zone: int = -1
## picture name -> Texture2D
var pictures: Callable = Assets.ui_picture
## text name -> String (the text of the original, perhaps tidied for the screen)
var texts: Callable = _plain_text

var _nodes: Dictionary = {}               # actor -> Node
var _property_names: Dictionary = {}      # actor -> {logical property -> Godot property}


func _init(scene_root: Node) -> void:
	root = scene_root


## `node` plays `actor`. `property_names` renames a logical property for this actor when its node calls it something
## else (the crane's chain has `bottom` and `hook_frame` of its own).
func bind(actor: StringName, node: Node, property_names: Dictionary = {}) -> void:
	_nodes[actor] = node
	_property_names[actor] = property_names


func has_actor(actor: StringName) -> bool:
	return _nodes.has(actor)


func node_of(actor: StringName) -> Node:
	return _nodes.get(actor)


## The path from the root to the node of `actor`, the way an `Animation` track writes it.
func path_to(actor: StringName) -> NodePath:
	return root.get_path_to(_nodes[actor])


## Where the origin of the actor's node is in the window: a position of the timeline is in window pixels, a node's `position`
## is relative to its parent (the playfield starts at (16, 32)), so the builder subtracts this.
func origin_of(actor: StringName) -> Vector2:
	var parent := (_nodes[actor] as Node).get_parent() as CanvasItem
	return parent.get_global_transform().origin if parent != null else Vector2.ZERO


## The name of the Godot property that plays `property` for `actor`.
func godot_property(actor: StringName, property: StringName, default: String) -> String:
	return _property_names.get(actor, {}).get(property, default)


# --- the resolvers -------------------------------------------------------------------------------------------

## The number of the picture a `FRAME` key names, in the set of `frame_zone` (a number passes through).
func frame_number(value: Variant) -> int:
	if value is int:
		return value
	return NameRegistry.original().index_of(&"frame", String(value), frame_zone)


## The drawing of the sub for a `POSE` key (cell, propeller phase).
func pose_frame(pose: Vector2i) -> int:
	return sub_tuning.picture_for(pose.x, pose.y)


static func _plain_text(text_name: StringName) -> String:
	return Catalog.text(text_name) if text_name != &"" else ""
