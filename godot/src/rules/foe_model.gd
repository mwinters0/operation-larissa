class_name FoeModel
extends RefCounted
## One creature, as the rules of the playfield see it: a `FoeVM` (the script), the hit rectangles of its pictures and whether its
## screen is the one shown. No nodes.
##
## Teaches: an adapter between pure logic (`FoeVM`) and the world that referees the contacts, and "tell me when it changes":
## the creature announces a new picture, a mirror flip or a change of visibility the moment it happens (the signals below), so a
## view, a skin or a test can follow a creature without looking at it every frame. Where the creature IS (`vm.x`, `vm.y`) and
## what it looks like are the VM's fields; the node that draws it (`Foe`) reads them.
##
## All creatures of a sector exist from the moment the sector is loaded (so that a script can wake a creature on a screen you are
## not looking at), but only those whose screen is shown are visible and touchable.
##
## LIFETIMES. A creature lives one load of the creatures (`SimWorld._build_foes` makes new ones at every load, respawn and reload).
## Within it each field is in one of the lists below (docs/engine/ARCHITECTURE.md, "Lifetimes of state").

## The picture (slot `frame` of the zone's creature pictures) is another one now, or was shown for the first time.
signal picture_changed(picture: int)
## The creature is mirrored (or not any more).
signal mirror_changed(mirrored: bool)
## The creature is drawn / not drawn any more: it is on the shown screen and not hidden.
signal visibility_changed(shown: bool)

## Set by `refresh` (the world calls it when a screen is shown, and every tick of the creature): whether its screen is the one shown.
const SCREEN_FIELDS: Array[StringName] = [&"on_screen"]
## Set by `tick` (and `snap`): where the creature was before the last tick.
const TICK_FIELDS: Array[StringName] = [&"previous_pos", &"was_hidden"]
## Member variables that live as long as the creature (one load), and why.
const KEPT_FIELDS: Dictionary[StringName, String] = {
	&"vm": "wiring: the script this creature shows, handed to _init",
	&"meta": "wiring: the zone's hit rectangles, handed to _init",
	&"ticks_run": "a counter over the creature's life, for a view that looks now and then",
	&"_announced_picture": "what the listeners were last told, so `announce_changes` says only changes",
	&"_announced_mirror": "what the listeners were last told",
	&"_announced_shown": "what the listeners were last told",
}

var vm: FoeVM
var meta: SpriteMetaTable
## True if this creature's screen is the one shown (set by the world on every screen change and every creature tick).
var on_screen: bool = false
## Where the picture was, and whether it was hidden, before the last tick: the previous state a view smooths from. Whether it
## glides or jumps is the view's decision (`Foe.follow`), not a rule: nothing here depends on it.
var previous_pos: Vector2i = Vector2i.ZERO
var was_hidden: bool = false
## How many times `tick` ran: a view that only looks now and then can tell whether `previous_pos` is new.
var ticks_run: int = 0

var _announced_picture: int = -1
var _announced_mirror: bool = false
var _announced_shown: bool = false


func _init(foe_vm: FoeVM, sprite_meta: SpriteMetaTable) -> void:
	vm = foe_vm
	meta = sprite_meta
	previous_pos = Vector2i(vm.x, vm.y)
	was_hidden = vm.hidden


## Runs the script for one tick and announces what changed. `ctx.current_screen` is the screen that is shown.
func tick(ctx: FoeVM.Context) -> void:
	previous_pos = Vector2i(vm.x, vm.y)
	was_hidden = vm.hidden
	ticks_run += 1
	vm.tick(ctx)
	refresh(vm.screen == ctx.current_screen)


## Takes `on_screen` and announces the changes of picture, mirror and visibility since the last time.
func refresh(is_on_screen: bool) -> void:
	on_screen = is_on_screen
	announce_changes()


## Announces the changes of picture, mirror and visibility since the last time. It changes nothing about the creature (`refresh` also
## takes `on_screen`, which the contacts use). The world calls it for every creature at the end of the creatures' step, so an
## announcement is never later than the tick that made the change, even when another creature's script did it.
func announce_changes() -> void:
	var shown := is_shown()
	if vm.frame != _announced_picture:
		_announced_picture = vm.frame
		picture_changed.emit(vm.frame)
	if vm.flip != _announced_mirror:
		_announced_mirror = vm.flip
		mirror_changed.emit(vm.flip)
	if shown != _announced_shown:
		_announced_shown = shown
		visibility_changed.emit(shown)


## Forget the previous place: after a jump the picture must not glide.
func snap() -> void:
	previous_pos = Vector2i(vm.x, vm.y)
	was_hidden = vm.hidden


## Is the creature drawn: on the shown screen and not hidden?
func is_shown() -> bool:
	return on_screen and not vm.hidden


## Is this creature there to be touched (visible, awake or not)? A hidden creature, or one on another screen, cannot be.
func is_touchable() -> bool:
	return on_screen and not vm.hidden


## The sub touched this creature: run its contact script (usually just `RET`). Returns true if the script was started.
func hit_by_sub() -> bool:
	if not vm.can_be_interrupted():
		return false
	vm.interrupt(vm.script_hit)
	return true


## An ink pellet hit this creature: run its ink script (the creature turns into a harmless ink cloud for a while). Returns true
## if the script was started. As in the original only a creature that is already busy with an interrupt script ignores the
## pellet; damage and the dormant flag do not matter.
func hit_by_ink() -> bool:
	if vm.interrupted or not vm.fault.is_empty():
		return false
	vm.interrupt(vm.script_ink)
	return true


## The hit rectangle of the current picture in WINDOW pixels, the same system as `SubModel.hurt_rect_window()`. Edges are
## inclusive, see `rects_touch`.
func hit_rect_window() -> Rect2i:
	var rect := meta.hit_rect(vm.frame, vm.flip)
	return Rect2i(rect.position + Vector2i(vm.x, vm.y), rect.size)


## The original's overlap test: a rectangle is the pixels from its left/top edge to its right/bottom edge INCLUDING both edges,
## so rectangles that merely touch count as overlapping (`Rect2i.intersects` would say no). In the original: a creature does not
## touch the sub only if `foe.right < sub.left or foe.bottom < sub.top or sub.right < foe.left or sub.bottom < foe.top`.
static func rects_touch(a: Rect2i, b: Rect2i) -> bool:
	return a.position.x <= b.end.x and b.position.x <= a.end.x \
			and a.position.y <= b.end.y and b.position.y <= a.end.y
