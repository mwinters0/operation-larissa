class_name StageChain
extends Control
## A stack of pictures that one number lowers and raises, clipped to a box: the crane's cable of the Expert closing (a hook at the bottom, a few links, a ball, links again, as far up as the picture reaches).
## `StageBuilder` makes it for a `StageActor.CHAIN`: the pieces are the actors of the stage that have the chain as their parent, placed where they stand when `extent` is 0, and the box clips them the way the original
## clips the drawing at the crane's arm (`ExpertClosingCableTop`). Original: `ExpertClosingDrawCable` (0x41cc8d) draws the chain from the hook up, `ExpertClosingEraseCable` (0x41cbac) restores the background behind it, both once per step.
##
## Teaches: a composite moved by a single property. A timeline's `extent` track says how far down the chain reaches and its `frame` track which picture the hook shows; the node turns each into the move of every piece and the swap of the
## hook's texture, so an `AnimationPlayer` can animate a thing of twenty sprites with two tracks, and the stage (not this script) says what the pieces are and where they stand.

## What the hook can look like (open, closing, closed), by `frame`: the textures of the actor's `pictures`.
var hooks: Array[Texture2D] = []
## Where the chain is told it is, for the words of a warning ("the chain 'cable' of the stage 'x' of pack 'y'").
var where: String = ""
## How far down the chain reaches: every piece stands this many pixels lower than the stage placed it (the y of the bottom row of the hook in the closing's window pixels, when the pieces were placed for 0).
var extent: int = 0:
	set(value):
		var delta := value - extent
		extent = value
		for piece in get_children():
			(piece as Node2D).position.y += delta
## Which of `hooks` the first piece shows.
var frame: int = 0:
	set(value):
		if value < 0 or value >= hooks.size():
			TroubleLog.session.tell("[story] %s: a timeline sets its hook to picture %d, and the stage gives it %d: the hook keeps its picture" % [where, value, hooks.size()])
			return
		frame = value
		if get_child_count() > 0:
			(get_child(0) as Sprite2D).texture = hooks[value]
