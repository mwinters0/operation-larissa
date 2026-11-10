class_name RainbowFishRig
extends CreatureRig
## A rainbow fish (sector 0, screens 3 and 5) drawn from its ORIGINAL pictures and moved by an `AnimationTree`: the pictures come from the
## rules, the body language (a gentle hover, a faster swim, a lunge when it chomps, a swing when it turns round, a flinch in the ink)
## comes from the tree, and the tree's parameters come from what the rules say about the creature.
##
##   rules say (skin API)                          the tree does
##   ----------------------------------------------------------------------------------------------------
##   how far it moved in the last tick           -> `parameters/swim/blend_position` (0 = hover, 1 = cruise)
##   picture is a spit picture (mouth opens)     -> state `chomp`   (a lunge; ends by itself, back to `swim`)
##   `creature_mirror_changed` (it turned round) -> state `turn`    (a swing of the body; ends by itself)
##   `creature_hit_by_ink` / an ink picture      -> state `inked`   (dark tint, shaking) until the fish is a fish again
##
## The tree:   Start -> swim [BlendSpace1D: hover (0) .. cruise (1)]  <->  chomp, turn, inked      (chomp and turn go back to swim at the end)
##
## Teaches: `AnimationTree` with an `AnimationNodeStateMachine` and a `AnimationNodeBlendSpace1D` inside it, built in code so the whole
## thing can be read in one file (the same tree can be built in the editor, with the same names): the animations are ordinary
## `Animation` resources in an `AnimationPlayer` (the tree only chooses and blends them), a state is moved with
## `AnimationNodeStateMachinePlayback.travel`, a number is handed to the tree as a PARAMETER (`tree.set("parameters/...")`). The animations
## move only `scale`, `rotation`, the sprite's offset and its tint, never the place: the place is the rules' (and `Motion.at`'s), so the
## animation and the movement cannot fight over the same property. And the footprint: the body swells at most 10 percent around the middle
## of the original picture.

const SPEED_FOR_FULL_BLEND := 4.0              # pixels per tick of a patrolling rainbow fish (`Move_Foe_Relative_XY 4 0` in its script)
const REST_COLOR := Color.WHITE

var _body: Node2D
var _sprite: Sprite2D
var _player: AnimationPlayer
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _speed := 0.0                              # the blend position now (it eases to `_speed_target`)
var _speed_target := 0.0
var _spit_slots: Array[int] = []
var _ink_slots: Array[int] = []
var picture_before := -1                       # the picture before the one shown now (a chomp starts when the mouth opens, not on every spit picture)


func _build() -> void:
	_spit_slots = CreatureSpecies.slot_list(zone, ["rainbow_fish_spit_0", "rainbow_fish_spit_1"])
	_ink_slots = CreatureSpecies.slot_list(zone, CreatureSpecies.INK_PICTURES)
	_body = Node2D.new()                       # the pivot: turns and swells around the middle of the picture
	_body.name = "Body"
	add_child(_body)
	_sprite = Sprite2D.new()                   # (centered: the original picture, whatever its size)
	_sprite.name = "Sprite"
	_body.add_child(_sprite)
	_player = AnimationPlayer.new()
	_player.name = "Player"
	add_child(_player)
	_player.add_animation_library(&"", _make_library())
	_tree = AnimationTree.new()
	_tree.name = "Tree"
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.tree_root = _make_state_machine()
	_tree.active = true
	_playback = _tree.get("parameters/playback")


# --- what the rules say -----------------------------------------------------------------------------

func _set_picture(new_picture: int) -> void:
	var texture := frames.get_frame_texture(&"all", new_picture) if new_picture < frames.get_frame_count(&"all") else null
	_sprite.texture = texture
	_body.position = picture_size(new_picture) / 2.0
	if _ink_slots.has(new_picture):
		_go(&"inked")
	elif _playback.get_current_node() == &"inked":
		_go(&"swim")                           # a fish again
	elif _spit_slots.has(new_picture) and not _spit_slots.has(picture_before):
		_go(&"chomp")
	picture_before = new_picture


func _set_mirror(new_mirrored: bool, animate: bool) -> void:
	_sprite.flip_h = new_mirrored              # (the picture is the rules' and so is its facing: the hit rectangle flips with it)
	if animate:
		_go(&"turn")


func hit_by_ink() -> void:
	_go(&"inked")


func _on_followed(creature: SimView.CreatureState) -> void:
	_speed_target = clampf(creature.motion.previous.distance_to(creature.motion.current) / SPEED_FOR_FULL_BLEND, 0.0, 1.0)


func _process(delta: float) -> void:
	_speed = move_toward(_speed, _speed_target, 5.0 * delta)
	_tree.set("parameters/swim/blend_position", _speed)


## Goes to the state `state` of the tree; one that is playing already starts again from its beginning (a second turn in a row).
func _go(state: StringName) -> void:
	if _playback.get_current_node() == state or _playback.get_current_node() == &"":
		_playback.start(state)
	else:
		_playback.travel(state)


# --- the tree -----------------------------------------------------------------------------------------

func _make_state_machine() -> AnimationNodeStateMachine:
	var swim := AnimationNodeBlendSpace1D.new()    # the speed picks and mixes `hover` and `cruise`
	swim.min_space = 0.0
	swim.max_space = 1.0
	swim.add_blend_point(_animation_node(&"hover"), 0.0, -1, &"hover")
	swim.add_blend_point(_animation_node(&"cruise"), 1.0, -1, &"cruise")
	var machine := AnimationNodeStateMachine.new()
	machine.add_node(&"swim", swim, Vector2(300, 100))
	machine.add_node(&"chomp", _animation_node(&"chomp"), Vector2(560, 0))
	machine.add_node(&"turn", _animation_node(&"turn"), Vector2(560, 100))
	machine.add_node(&"inked", _animation_node(&"inked"), Vector2(560, 200))
	machine.add_transition(&"Start", &"swim", _transition(AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO))
	# A state of the tree is left on request (`travel`) ...
	for state: StringName in [&"chomp", &"turn", &"inked"]:
		machine.add_transition(&"swim", state, _transition(AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED))
	machine.add_transition(&"inked", &"swim", _transition(AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED))
	for state: StringName in [&"chomp", &"turn"]:
		machine.add_transition(state, &"inked", _transition(AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED))
	machine.add_transition(&"chomp", &"turn", _transition(AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED))
	machine.add_transition(&"turn", &"chomp", _transition(AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED))
	# ... or by itself when its animation has played to the end.
	for state: StringName in [&"chomp", &"turn"]:
		var back := _transition(AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO)
		back.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		machine.add_transition(state, &"swim", back)
	return machine


func _animation_node(animation: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation
	return node


func _transition(mode: AnimationNodeStateMachineTransition.AdvanceMode) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.advance_mode = mode
	transition.xfade_time = 0.12
	return transition


# --- the animations -----------------------------------------------------------------------------------
# Each is a list of [time, value] keys for `scale`, `rotation`, the sprite's `position` and `modulate`. Every animation keys all four
# (what it does not move stays at rest), so no animation leaves a value of its own behind when the tree changes state.

func _make_library() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	library.add_animation(&"hover", _animation(2.0, true, {
		"rotation": [[0.0, 0.0], [0.5, 0.02], [1.0, 0.0], [1.5, -0.02], [2.0, 0.0]],
		"offset": [[0.0, Vector2.ZERO], [0.5, Vector2(0, -1.5)], [1.0, Vector2.ZERO], [1.5, Vector2(0, 1.5)], [2.0, Vector2.ZERO]],
	}))
	library.add_animation(&"cruise", _animation(0.5, true, {            # the body wave of a swimming fish
		"scale": [[0.0, Vector2.ONE], [0.125, Vector2(0.97, 1.03)], [0.25, Vector2.ONE], [0.375, Vector2(0.97, 1.03)], [0.5, Vector2.ONE]],
		"rotation": [[0.0, 0.0], [0.125, 0.07], [0.25, 0.0], [0.375, -0.07], [0.5, 0.0]],
		"offset": [[0.0, Vector2.ZERO], [0.125, Vector2(0, -1.0)], [0.25, Vector2.ZERO], [0.375, Vector2(0, -1.0)], [0.5, Vector2.ZERO]],
	}))
	library.add_animation(&"chomp", _animation(0.4, false, {            # a lunge: stretch, then squash, then rest
		"scale": [[0.0, Vector2.ONE], [0.12, Vector2(1.1, 0.92)], [0.24, Vector2(0.94, 1.06)], [0.4, Vector2.ONE]],
		"rotation": [[0.0, 0.0], [0.12, -0.05], [0.4, 0.0]],
		"offset": [[0.0, Vector2.ZERO], [0.12, Vector2(-3, 0)], [0.4, Vector2.ZERO]],
	}))
	library.add_animation(&"turn", _animation(0.4, false, {             # it starts edge-on (the picture has just been mirrored) and swings round
		"scale": [[0.0, Vector2(0.2, 1.1)], [0.2, Vector2(1.08, 0.95)], [0.4, Vector2.ONE]],
		"rotation": [[0.0, 0.2], [0.2, -0.05], [0.4, 0.0]],
	}))
	library.add_animation(&"inked", _animation(0.7, true, {             # a flinch in the ink: dark, shaking, swelling a little
		"scale": [[0.0, Vector2.ONE], [0.35, Vector2(1.06, 1.06)], [0.7, Vector2.ONE]],
		"offset": [[0.0, Vector2.ZERO], [0.175, Vector2(-1.5, 0)], [0.35, Vector2(1.5, 0)], [0.525, Vector2(-1.5, 0)], [0.7, Vector2.ZERO]],
		"tint": [[0.0, REST_COLOR], [0.35, Color(0.6, 0.5, 0.8)], [0.7, REST_COLOR]],
	}))
	return library


## An `Animation` of `length` seconds from `keys` (property -> [[time, value], ...]; a property that is not there stays at rest).
func _animation(length: float, loops: bool, keys: Dictionary) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	_add_track(animation, "Body:scale", keys.get("scale", [[0.0, Vector2.ONE], [length, Vector2.ONE]]))
	_add_track(animation, "Body:rotation", keys.get("rotation", [[0.0, 0.0], [length, 0.0]]))
	_add_track(animation, "Body/Sprite:position", keys.get("offset", [[0.0, Vector2.ZERO], [length, Vector2.ZERO]]))
	_add_track(animation, "Body/Sprite:modulate", keys.get("tint", [[0.0, REST_COLOR], [length, REST_COLOR]]))
	return animation


func _add_track(animation: Animation, path: String, keys: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))                     # (relative to the node the animations play on: this rig)
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for key: Array in keys:
		animation.track_insert_key(track, key[0], key[1])


## The state the tree is in, for the tests.
func current_state() -> StringName:
	return _playback.get_current_node()


## The blend position of the swim state now, for the tests.
func blend_position() -> float:
	return _tree.get("parameters/swim/blend_position")
