class_name Bubbles
extends Node2D
## The random air bubbles that rise through the water (the original's BUBBLES.C, `UpdateAmbientBubbles` (0x41a800), DESIGN 9).
##
## Teaches: an object POOL (the same two sprites are reused for ever; nothing is created or freed while the
## game runs), a seeded `RandomNumberGenerator` (so a test can replay the exact same bubbles), and logic that
## advances on the `GameClock` tick instead of on the frame rate.
##
## The rules, all taken from the decompiled routine (they are DATA in `BubbleRules`, not numbers in this file; that includes the
## pictures' sizes, which the spawn range and the despawn test use: the rules never ask a texture how big it is):
##  * There are exactly two bubbles: a thin "column" (rises 10 px per tick) and a wider "cluster" (6 px).
##  * A bubble that is idle starts with a 1 in 50 chance per tick, at the bottom edge of the playfield, at a
##    random even x. Every tick it rises and shows its next picture; once it is above the top edge it is idle again.
##  * They are cleared on every screen change, and there are none at all on the first four screens of sector 0.
##  * Nothing they do depends on the sub, a hit or the oxygen. (The blue blobs ON the sub in the original's
##    screenshots are `Sub`'s hit bubbles and message light, not these.)
##  * The art already looks "translucent": its pixels are a sparse pattern of blue with see-through gaps, drawn
##    with the usual colour-key transparency. No blending is needed, so a plain sprite is exactly right.
##
## Why not `CPUParticles2D`? Particles emit at a random time inside a frame, move with the frame rate and
## cannot repeat the original's tick-stepped moves (10 px jumps at 12 Hz), its 1-in-50 per-tick spawn rule or
## its two-bubble cap. Two pooled sprites stepped by `GameClock` reproduce all three exactly, in about 100 lines.
##
## The node sits LAST in the `OriginalPresenter`: the original draws the bubbles after everything else, over the sub too.

## One of the two bubbles: a sprite plus what the original keeps about it.
class Bubble extends AnimatedSprite2D:
	var slot: int = 0
	var active: bool = false
	## Ticks since it started (the first picture is age 0).
	var age: int = 0
	## The picture's top-left corner in WINDOW pixels (the playfield's top-left is (16, 32)).
	var window_pos: Vector2i = Vector2i.ZERO

## The numbers of the rules. Tests may replace it before `_ready`.
var rules: BubbleRules
## Every random choice comes from here. `seed_rng(n)` makes a run repeatable.
var rng := RandomNumberGenerator.new()
## False on the screens that never have bubbles (see `BubbleRules.allowed_on`).
var enabled: bool = true
## True while a supply trip runs: `ExitSupplyStation`, `EnterSupplyStation` and `LaunchBalloon` never call `UpdateAmbientBubbles`, so no bubble
## is seen or moves (`hold`).
var held: bool = false

var _pool: Array[Bubble] = []
var _seeded: bool = false


func _ready() -> void:
	if rules == null:
		rules = Catalog.bubble_rules()
	if not _seeded:
		rng.randomize()
	var frames := Catalog.fx_frames()
	for slot in rules.slot_count():
		var bubble := Bubble.new()
		bubble.slot = slot
		bubble.sprite_frames = frames
		bubble.animation = &"all"
		bubble.centered = false
		bubble.use_parent_material = true    # (the shader of the `bubbles` layer, if the skin puts one on it)
		bubble.visible = false
		bubble.pause()                       # the frame is chosen by `step`, never by the animation player
		_pool.append(bubble)
		add_child(bubble)
	GameClock.tick.connect(_on_game_tick)


## Makes the random choices repeatable (tests, replays).
func seed_rng(value: int) -> void:
	rng.seed = value
	_seeded = true


## The sub arrived on a screen: forget all bubbles (the original does this on every screen change) and
## switch the whole system off where the original never shows any.
func enter_screen(sector_index: int, screen_index: int) -> void:
	enabled = rules.allowed_on(sector_index, screen_index)
	clear()


## A supply trip starts (`on`: no bubble is drawn, none moves, and the ones that were there are gone) or the play goes on.
func hold(on: bool) -> void:
	if on and not held:
		clear()
	held = on


## Back to "no bubble anywhere".
func clear() -> void:
	for bubble in _pool:
		_stop(bubble)


## How many bubbles exist right now (never more than `BubbleRules.slot_count()`).
func active_count() -> int:
	var count := 0
	for bubble in _pool:
		if bubble.active:
			count += 1
	return count


## The pooled sprite of a slot, for tests and tools.
func bubble(slot: int) -> Bubble:
	return _pool[slot]


func _on_game_tick(_count: int) -> void:
	step()


## One game tick: every active bubble moves on, every idle one may start. Called by the clock; tests call it by hand.
func step() -> void:
	if not enabled or held:
		return
	for current in _pool:
		if current.active:
			_advance(current)
		else:
			_maybe_start(current)


func _maybe_start(bubble: Bubble) -> void:
	if rng.randi_range(0, rules.spawn_chance - 1) != 0:
		return
	var first_picture := rules.slot_first_picture[bubble.slot]
	var width := rules.spawn_width(bubble.slot)                         # the first picture's width, rounded down to even, from the rules' data
	bubble.active = true
	bubble.age = 0
	bubble.window_pos = Vector2i(rules.x_for(rng.randi_range(0, rules.x_span - width - 1)), rules.spawn_y)
	_show(bubble, first_picture)


func _advance(bubble: Bubble) -> void:
	bubble.age += 1
	bubble.window_pos.y -= rules.slot_rise_per_tick[bubble.slot]
	var picture := rules.picture_at(bubble.slot, bubble.age)
	if rules.picture_height(picture) + bubble.window_pos.y < rules.top_y:      # completely above the playfield
		_stop(bubble)
	else:
		_show(bubble, picture)


func _show(bubble: Bubble, picture: int) -> void:
	bubble.frame = picture
	bubble.position = Vector2(bubble.window_pos) - Sub.PLAYFIELD_ORIGIN    # window pixels -> playfield pixels
	bubble.visible = true


func _stop(bubble: Bubble) -> void:
	bubble.active = false
	bubble.visible = false

