class_name AnimDeco
extends AnimatedSprite2D
## An animated decoration: shows the entries of a frame list, one per game tick.
##
## Teaches: connecting to a global signal (GameClock.tick) from a node's own
## `_ready`. A connection made with a node's method is dropped automatically
## when the node is freed, so a screen can be thrown away without cleanup code.
##
## The list loops forever. Its entries repeat each picture several times
## (for example 6 x picture A, then 6 x picture B), which is how the original
## makes slow blinking or swaying with one picture per tick.

var data: AnimDecoData
var _cursor: int = 0


## Configures the sprite from the record. Call before adding the node to the tree.
func setup(frames: SpriteFrames, record: AnimDecoData) -> void:
	data = record
	sprite_frames = frames
	animation = &"all"
	position = Vector2(record.pos) - Sub.PLAYFIELD_ORIGIN         # stored in window pixels
	if not record.frames.is_empty():
		_cursor = record.start_cursor % record.frames.size()
		frame = record.frames[_cursor]


func _ready() -> void:
	GameClock.tick.connect(_on_tick)


func _on_tick(_count: int) -> void:
	if data == null or data.frames.is_empty():
		return
	_cursor = (_cursor + 1) % data.frames.size()
	frame = data.frames[_cursor]
