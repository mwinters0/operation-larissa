class_name SupplyStation
extends Node2D
## The supply station drawn on the first screen (sub starts here) and the last screen (sub docks here).
##
## Teaches: a view that is told how far along it is. The rules own the trip (`StationSequence`, counted by `SimWorld.tick`: how
## many ticks it lasts, which picture the door shows after each, where the balloon is); this node only turns "after tick N" into
## sprites. There is no `AnimationPlayer` and no `Tween` here, because a length that lives in an animation would be a length the
## rules do not know (and a skin could change). Everything is measured in game ticks of the original (6/73 s), as in
## `ExitSupplyStation` and its sister routines (DESIGN 3.7); see `StationSequence` for the schedule:
##
##   tick 0   the door shows picture 3      tick 1   picture 4      tick 2   the door is open
##   from tick 3 the sub drives 4 px per tick (96 px out of the left station, 100 px into the right one)
##   after that the door closes again: picture 4, 3, then 2 (closed); sound 0x17 plays with picture 3
##   (`ExitSupplyStation` 0x4328b0, `EnterSupplyStation` 0x432b96: the state-2 iteration of the closing)
##
## The pictures are the 7 of the station bundle: 0 and 1 the body (the right station is picture 0, picture 1
## and a mirrored picture 1; the left one is just a mirrored picture 0), 2-4 the door, 5-6 the balloon.
## Positions are window pixels of the original, minus the playfield's origin (16, 32).
##
## Draw order is node order (see the scene), back to front: the balloon, the station's body, the door. `LaunchBalloon` (0x432eae)
## draws the balloon (picture 6) BEFORE the body pictures and the door, so the balloon rises out from BEHIND the station, as the
## sub drives in and out behind it (`OriginalPresenter` puts the `Sub` before this node).

enum Side { LEFT, RIGHT }

const DRIVE_Y := StationSequence.DRIVE_Y

var side: int = Side.LEFT

@onready var body_a: Sprite2D = %BodyA
@onready var body_b: Sprite2D = %BodyB
@onready var body_c: Sprite2D = %BodyC
@onready var door: Sprite2D = %Door
@onready var balloon: Sprite2D = %Balloon


func _ready() -> void:
	var frames := Catalog.station_frames()
	for sprite in [body_a, body_b, body_c, door, balloon]:
		(sprite as Sprite2D).centered = false
	body_a.texture = frames.get_frame_texture(&"all", StationLayout.BODY)
	body_b.texture = frames.get_frame_texture(&"all", StationLayout.BODY_END)
	body_c.texture = frames.get_frame_texture(&"all", StationLayout.BODY_END)
	balloon.texture = frames.get_frame_texture(&"all", StationLayout.BALLOON)
	balloon.hide()
	set_side(side)


## Chooses which station to show: LEFT (start of the sector) or RIGHT (the dock at the end). The parts and their places are `StationLayout`'s.
func set_side(new_side: int) -> void:
	side = new_side
	var nodes := {&"balloon": balloon, &"body_a": body_a, &"body_b": body_b, &"body_c": body_c, &"door": door}
	body_b.visible = side == Side.RIGHT
	body_c.visible = side == Side.RIGHT
	for part in StationLayout.parts(side == Side.LEFT):
		var node: Sprite2D = nodes[part["name"]]
		node.position = part["position"]
		node.flip_h = part["mirrored"]
	set_door_picture(StationLayout.DOOR_CLOSED)
	balloon.hide()


## Shows door picture 2 (closed), 3 or 4 (opening / closing), or nothing (-1 = wide open).
func set_door_picture(picture: int) -> void:
	door.visible = picture >= 0
	if picture >= 0:
		door.texture = Catalog.station_frames().get_frame_texture(&"all", picture)


## Shows the trip as it is after `sequence.elapsed` ticks (`SimWorld.ticked`): the door's picture, and for the balloon where it is.
## Instant and idempotent: the rules decide what the state is, this only draws it.
func show_sequence(sequence: StationSequence) -> void:
	if sequence.is_drive():
		set_door_picture(sequence.door_picture())
		return
	balloon.visible = not sequence.is_done()
	balloon.position = Vector2(sequence.balloon_x, sequence.balloon_y()) - Vector2(Sub.PLAYFIELD_ORIGIN)


## Between two ticks the balloon glides from where it was to where it is, `fraction` (0..1) of the way into the tick.
func show_between_ticks(sequence: StationSequence, fraction: float) -> void:
	if sequence == null or sequence.is_drive() or sequence.is_done():
		return
	var y := lerpf(sequence.balloon_y(maxi(sequence.elapsed - 1, 0)), sequence.balloon_y(), fraction)
	balloon.position = Vector2(sequence.balloon_x, y) - Vector2(Sub.PLAYFIELD_ORIGIN)
